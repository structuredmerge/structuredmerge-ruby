# frozen_string_literal: true

require 'version_gem'
require_relative 'merge/version'

require 'tree_haver'
require 'ast/merge'

module TypeScript
  module Merge
    extend self

    PACKAGE_NAME = 'typescript-merge'
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: 'array', name: 'destination_wins_array' }.freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        grammar_finder = TreeHaver::GrammarFinder.new(:typescript)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def type_script_feature_profile
      { family: 'typescript', supported_dialects: ['typescript'], supported_policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def available_type_script_backends
      [TREE_SITTER_BACKEND]
    end

    def type_script_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      unless requested == TREE_SITTER_BACKEND.id
        return unsupported_feature_result("Unsupported TypeScript backend #{requested}.")
      end

      type_script_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
    end

    def type_script_plan_context(backend: nil)
      profile = type_script_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: type_script_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_type_script(source, dialect)
      requested = TREE_SITTER_BACKEND.id
      unless requested == TREE_SITTER_BACKEND.id
        return unsupported_feature_result("Unsupported TypeScript backend #{requested}.")
      end
      return analyze_type_script_module(source) if dialect == 'typescript'

      { ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: "Unsupported TypeScript dialect #{dialect}." }], policies: [] }
    end

    def match_type_script_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
    end

    def merge_type_script(template_source, destination_source, dialect)
      template = parse_type_script(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = parse_type_script(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == 'parse_error' ? diagnostic.merge(category: 'destination_parse_error') : diagnostic
          end,
          policies: []
        }
      end

      destination_declarations = destination.dig(:analysis, :declarations).to_h { |item| [item[:path], item] }
      merged_declaration_texts = destination.dig(:analysis, :declarations).map { |item| item[:text] } +
                                 template.dig(:analysis, :declarations).reject do |item|
                                   destination_declarations[item[:path]]
                                 end.map { |item| item[:text] }
      import_block = destination.dig(:analysis, :imports).map { |item| item[:text] }.join
      declaration_block = merged_declaration_texts.join("\n").rstrip
      sections = [import_block.rstrip, declaration_block].reject(&:empty?)

      { ok: true, diagnostics: [], output: "#{sections.join("\n\n").rstrip}\n",
        policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def analyze_type_script_module(source)
      parser = TreeHaver.parser_for(:typescript)
      tree = parser.parse(source)
      collect_parse_errors(tree.root_node)

      unsupported_feature_result('TypeScript owner extraction must be rebuilt from TreeHaver AST nodes.')
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end
    private_class_method :analyze_type_script_module

    def collect_parse_errors(node)
      raise TreeHaver::NotAvailable, 'TypeScript parse returned no root node' unless node
      raise TreeHaver::NotAvailable, 'TypeScript parse contains syntax errors' if node.respond_to?(:has_error?) && node.has_error?
    end
    private_class_method :collect_parse_errors

    def parse_failure_result(error)
      { ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: error.message }],
        policies: [] }
    end
    private_class_method :parse_failure_result

    def import_text(source, span)
      "#{slice_span(source, span)}\n"
    end
    private_class_method :import_text

    def declaration_text(source, span)
      "#{line_anchored_slice(source, span)}\n"
    end
    private_class_method :declaration_text

    def slice_span(source, span)
      source[span.start_byte...span.end_byte].strip
    end
    private_class_method :slice_span

    def line_anchored_slice(source, span)
      line_start = source.rindex("\n", [span.start_byte - 1, 0].max)
      line_start = line_start ? line_start + 1 : 0
      source[line_start...span.end_byte].strip
    end
    private_class_method :line_anchored_slice

    def unsupported_feature_result(message)
      Ast::Merge.unsupported_feature_result(message)
    end
    private_class_method :unsupported_feature_result
  end
end

TypeScript::Merge.register_backend!

TypeScript::Merge::Version.class_eval do
  extend VersionGem::Basic
end
