# frozen_string_literal: true

require 'version_gem'
require_relative 'merge/version'

require 'tree_haver'
require 'ast/merge'

module Rust
  module Merge
    PACKAGE_NAME = 'rust-merge'
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: 'array', name: 'destination_wins_array' }.freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    module_function

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        grammar_finder = TreeHaver::GrammarFinder.new(:rust)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def rust_feature_profile
      { family: 'rust', supported_dialects: ['rust'], supported_policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def available_rust_backends
      [TREE_SITTER_BACKEND]
    end

    def rust_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? TREE_SITTER_BACKEND.id : backend.to_s
      unless requested == TREE_SITTER_BACKEND.id
        return unsupported_feature_result("Unsupported Rust backend #{requested}.")
      end

      rust_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
    end

    def rust_plan_context(backend: nil)
      profile = rust_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: rust_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_rust(source, dialect)
      return analyze_rust_module(source) if dialect == 'rust'

      { ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: "Unsupported Rust dialect #{dialect}." }], policies: [] }
    end

    def match_rust_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
    end

    def merge_rust(template_source, destination_source, dialect)
      template = parse_rust(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = parse_rust(destination_source, dialect)
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

    def analyze_rust_module(source)
      parser = TreeHaver.parser_for(:rust)
      tree = parser.parse(source)
      collect_parse_errors(tree.root_node)

      unsupported_feature_result('Rust owner extraction must be rebuilt from TreeHaver AST nodes.')
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end
    private_class_method :analyze_rust_module

    def collect_parse_errors(node)
      raise TreeHaver::NotAvailable, 'Rust parse returned no root node' unless node
      raise TreeHaver::NotAvailable, 'Rust parse contains syntax errors' if node.respond_to?(:has_error?) && node.has_error?
    end
    private_class_method :collect_parse_errors

    def parse_failure_result(error)
      { ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: error.message }],
        policies: [] }
    end
    private_class_method :parse_failure_result

    def normalize_rust_import_path(import_source)
      import_source.sub(/\Ause\s+/, '').sub(/;\z/, '').strip
    end
    private_class_method :normalize_rust_import_path

    def import_text(source, span) = "#{slice_span(source, span)}\n"
    def declaration_text(source, span) = "#{line_anchored_slice(source, span)}\n"
    def slice_span(source, span) = source[span.start_byte...span.end_byte].strip

    def line_anchored_slice(source, span)
      line_start = source.rindex("\n", [span.start_byte - 1, 0].max)
      line_start = line_start ? line_start + 1 : 0
      source[line_start...span.end_byte].strip
    end
    private_class_method :import_text, :declaration_text, :slice_span, :line_anchored_slice
  end
end

Rust::Merge.register_backend!

Rust::Merge::Version.class_eval do
  extend VersionGem::Basic
end
