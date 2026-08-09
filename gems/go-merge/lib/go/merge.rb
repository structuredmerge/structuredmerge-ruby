# frozen_string_literal: true

require 'tree_haver'
require 'ast/merge'
require_relative 'merge/version'

# rubocop:disable Metrics/ModuleLength -- legacy API and native workflow registration share the public Go::Merge surface
module Go
  # Native Go parsing and source-preserving merge APIs.
  module Merge
    module_function

    PACKAGE_NAME = 'go-merge'
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: 'array', name: 'destination_wins_array' }.freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    autoload :NodeWrapper, 'go/merge/node_wrapper'
    autoload :FileAnalysis, 'go/merge/file_analysis'
    autoload :Provider, 'go/merge/provider'

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND)

        grammar_finder = TreeHaver::GrammarFinder.new(:go)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def go_feature_profile
      { family: 'go', supported_dialects: ['go'], supported_policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end

    def available_go_backends
      go_backend_available_for_analysis?(TREE_SITTER_BACKEND.id) ? [TREE_SITTER_BACKEND] : []
    end

    def go_backend_feature_profile(backend: nil)
      requested = requested_tree_sitter_backend_id(backend)
      unless go_backend_available_for_analysis?(requested)
        return unsupported_feature_result("Unsupported Go backend #{requested}.")
      end

      go_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
    end

    def go_plan_context(backend: nil)
      profile = go_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: go_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_go(source, dialect)
      unless go_backend_available_for_analysis?(nil)
        diagnostic_backend = TreeHaver.current_backend_id || 'tree-sitter'
        return unsupported_feature_result("Unsupported Go backend #{diagnostic_backend}.")
      end
      return analyze_go_module(source) if dialect == 'go'

      unsupported_feature_result("Unsupported Go dialect #{dialect}.")
    end

    def go_backend_available_for_analysis?(backend_id)
      register_backend!

      if backend_id.to_s.empty?
        TreeHaver.parser_for(:go, backend_type: :tree_sitter)
      else
        TreeHaver.with_backend(backend_id) { TreeHaver.parser_for(:go, backend_type: :tree_sitter) }
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

    def match_go_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
    end

    def merge_provider
      @merge_provider ||= Provider.new
    end

    def register_provider!(replace: false)
      Ast::Merge.register_provider(merge_provider, replace: replace)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- legacy merge result assembly remains one compatibility boundary
    def merge_go(template_source, destination_source, dialect)
      template = parse_go(template_source, dialect)
      return { ok: false, diagnostics: template[:diagnostics], policies: [] } unless template[:ok]

      destination = parse_go(destination_source, dialect)
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
      template_additions = template.dig(:analysis, :declarations).reject do |item|
        destination_declarations[item[:path]]
      end
      merged_declaration_texts = destination.dig(:analysis, :declarations).map { |item| item[:text] } +
                                 template_additions.map { |item| item[:text] }
      import_block = destination.dig(:analysis, :imports).map { |item| item[:text] }.join
      declaration_block = merged_declaration_texts.join("\n").rstrip
      sections = [import_block.rstrip, declaration_block].reject(&:empty?)
      { ok: true, diagnostics: [], output: "#{sections.join("\n\n").rstrip}\n",
        policies: [DESTINATION_WINS_ARRAY_POLICY] }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- one AST pass builds the legacy owner projection
    def analyze_go_module(source)
      analysis = FileAnalysis.new(source, require_package: false)
      raise analysis.errors.first unless analysis.errors.empty?

      imports = []
      declarations = []
      analysis.declarations.each do |wrapper|
        case wrapper.node.type
        when 'import_declaration'
          signature = wrapper.signature

          imports << {
            path: "/imports/#{imports.length}",
            owner_kind: 'import',
            match_key: signature.first == :import ? signature.last.last : signature,
            text: "#{wrapper.source_text}\n"
          }
        when 'function_declaration', 'method_declaration', 'type_declaration', 'const_declaration', 'var_declaration'
          name = legacy_declaration_key(wrapper.signature)
          declarations << {
            path: "/declarations/#{name}",
            owner_kind: 'declaration',
            match_key: name,
            text: "#{wrapper.source_text}\n"
          }
        end
      end

      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: 'go',
          dialect: 'go',
          imports: imports,
          declarations: declarations,
          owners: owner_views(imports + declarations)
        },
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    private_class_method :analyze_go_module

    def legacy_declaration_key(signature)
      return "#{signature.fetch(1)}.#{signature.fetch(2)}" if signature.first == :method

      signature.last
    end
    private_class_method :legacy_declaration_key

    def parse_failure_result(error)
      { ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: error.message }],
        policies: [] }
    end
    private_class_method :parse_failure_result

    def owner_view(item)
      item.slice(:path, :owner_kind, :match_key)
    end
    private_class_method :owner_view

    def owner_views(items)
      items.map { |item| owner_view(item) }
    end
    private_class_method :owner_views

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
        policies: []
      }
    end
    private_class_method :unsupported_feature_result
  end
end
# rubocop:enable Metrics/ModuleLength

Go::Merge.register_backend!
Go::Merge.register_provider!
