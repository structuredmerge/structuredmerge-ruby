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

        TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND)

        grammar_finder = TreeHaver::GrammarFinder.new(:rust)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def rust_feature_profile
      { family: 'rust', supported_dialects: ['rust'], supported_policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def available_rust_backends
      rust_backend_available_for_analysis?(TREE_SITTER_BACKEND.id) ? [TREE_SITTER_BACKEND] : []
    end

    def rust_backend_feature_profile(backend: nil)
      requested = requested_tree_sitter_backend_id(backend)
      unless rust_backend_available_for_analysis?(requested)
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
      unless rust_backend_available_for_analysis?(nil)
        diagnostic_backend = TreeHaver.current_backend_id || 'tree-sitter'
        return unsupported_feature_result("Unsupported Rust backend #{diagnostic_backend}.")
      end

      return analyze_rust_module(source) if dialect == 'rust'

      { ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: "Unsupported Rust dialect #{dialect}." }], policies: [] }
    end

    def rust_backend_available_for_analysis?(backend_id)
      register_backend!

      if backend_id.to_s.empty?
        TreeHaver.parser_for(:rust, backend_type: :tree_sitter)
      else
        TreeHaver.with_backend(backend_id) { TreeHaver.parser_for(:rust, backend_type: :tree_sitter) }
      end
      true
    rescue TreeHaver::Error, ArgumentError
      false
    end

    def requested_tree_sitter_backend_id(backend)
      return backend.to_s unless backend.to_s.empty?

      contextual = TreeHaver.current_backend_id || ENV['TREE_HAVER_BACKEND']
      contextual.to_s.empty? || contextual.to_s == 'auto' ? TREE_SITTER_BACKEND.id : contextual.to_s
    end
    private_class_method :requested_tree_sitter_backend_id

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
      parser = TreeHaver.parser_for(:rust, backend_type: :tree_sitter)
      tree = parser.parse(source)
      collect_parse_errors(tree.root_node)

      imports = []
      declarations = []
      tree.root_node.children.each do |node|
        case node.type
        when 'use_declaration'
          import_source = line_anchored_slice(source, node)
          imports << {
            path: "/imports/#{imports.length}",
            owner_kind: 'import',
            match_key: normalize_rust_import_path(import_source),
            text: import_text(source, node)
          }
        when 'function_item', 'struct_item', 'enum_item', 'trait_item', 'impl_item', 'const_item', 'static_item',
             'type_item', 'mod_item'
          name = first_named_descendant_text(source, node, %w[identifier type_identifier])
          next unless name

          declarations << {
            path: "/declarations/#{name}",
            owner_kind: 'declaration',
            match_key: name,
            text: declaration_text(source, node)
          }
        end
      end

      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: 'rust',
          dialect: 'rust',
          imports: imports,
          declarations: declarations,
          owners: owner_views(imports + declarations)
        },
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end
    private_class_method :analyze_rust_module

    def collect_parse_errors(node)
      raise TreeHaver::NotAvailable, 'Rust parse returned no root node' unless node
      return unless node.respond_to?(:has_error?) && node.has_error?

      raise TreeHaver::NotAvailable,
            'Rust parse contains syntax errors'
    end
    private_class_method :collect_parse_errors

    def parse_failure_result(error)
      { ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: error.message }],
        policies: [] }
    end
    private_class_method :parse_failure_result

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
        policies: []
      }
    end
    private_class_method :unsupported_feature_result

    def normalize_rust_import_path(import_source)
      import_source.sub(/\Ause\s+/, '').sub(/;\z/, '').strip
    end
    private_class_method :normalize_rust_import_path

    def first_named_descendant_text(source, node, types)
      return slice_span(source, node) if types.include?(node.type)

      node.children.each do |child|
        value = first_named_descendant_text(source, child, types)
        return value if value && !value.empty?
      end
      nil
    end
    private_class_method :first_named_descendant_text

    def owner_view(item)
      item.slice(:path, :owner_kind, :match_key)
    end
    private_class_method :owner_view

    def owner_views(items)
      items.map { |item| owner_view(item) }
    end
    private_class_method :owner_views

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
