# frozen_string_literal: true

require 'tree_haver'
require 'ast/merge'
require_relative 'merge/version'

module TypeScript
  module Merge
    module_function

    PACKAGE_NAME = 'typescript-merge'
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: 'array', name: 'destination_wins_array' }.freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    autoload :NodeWrapper, 'typescript/merge/node_wrapper'
    autoload :FileAnalysis, 'typescript/merge/file_analysis'
    autoload :Provider, 'typescript/merge/provider'

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND)

        grammar_finder = TreeHaver::GrammarFinder.new(:typescript)
        grammar_finder.register! if grammar_finder.available?
        TreeHaver.register_language(
          :tsx,
          backend_module: TreeHaver::Backends::Tslp,
          backend_type: :tslp,
          gem_name: 'tree_sitter_language_pack'
        )

        BACKEND_REGISTRY.registered = true
      end
    end

    def type_script_feature_profile
      {
        family: 'typescript',
        supported_dialects: %w[typescript tsx],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def available_type_script_backends
      type_script_backend_available_for_analysis?(TREE_SITTER_BACKEND.id) ? [TREE_SITTER_BACKEND] : []
    end

    def type_script_backend_feature_profile(backend: nil)
      requested = requested_tree_sitter_backend_id(backend)
      unless type_script_backend_available_for_analysis?(requested)
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
      unless type_script_backend_available_for_analysis?(nil)
        diagnostic_backend = TreeHaver.current_backend_id || 'tree-sitter'
        return unsupported_feature_result("Unsupported TypeScript backend #{diagnostic_backend}.")
      end
      return analyze_type_script_module(source, dialect: dialect) if %w[typescript tsx].include?(dialect)

      { ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: "Unsupported TypeScript dialect #{dialect}." }], policies: [] }
    end

    def type_script_backend_available_for_analysis?(backend_id)
      register_backend!

      if backend_id.to_s.empty?
        TreeHaver.parser_for(:typescript, backend_type: :tree_sitter)
      else
        TreeHaver.with_backend(backend_id) { TreeHaver.parser_for(:typescript, backend_type: :tree_sitter) }
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

    def match_type_script_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
    end

    def merge_provider
      @merge_provider ||= Provider.new
    end

    def register_provider!(replace: false)
      return unless Ast::Merge.respond_to?(:register_provider)

      Ast::Merge.register_provider(merge_provider, replace: replace)
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

    def analyze_type_script_module(source, dialect: 'typescript')
      analysis = FileAnalysis.new(source, dialect: dialect)
      raise analysis.errors.first unless analysis.errors.empty?

      imports = []
      declarations = []
      analysis.declarations.each do |wrapper|
        signature = wrapper.signature
        if signature.first == :import
          imports << {
            path: "/imports/#{imports.length}",
            owner_kind: 'import',
            match_key: legacy_import_key(signature),
            text: "#{wrapper.source_text}\n"
          }
        else
          name = legacy_declaration_key(signature)
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
          kind: 'typescript',
          dialect: dialect,
          imports: imports,
          declarations: declarations,
          owners: owner_views(imports + declarations)
        },
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end
    private_class_method :analyze_type_script_module

    def legacy_declaration_key(signature)
      nested = signature.first == :export_declaration ? signature.fetch(1) : signature
      value = nested.last
      value.is_a?(Array) ? value.join(',') : value
    end
    private_class_method :legacy_declaration_key

    def legacy_import_key(signature)
      literal = signature.fetch(1)
      literal.byteslice(1...-1).to_s
    end
    private_class_method :legacy_import_key

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
      imports, declarations = items.partition { |item| item.fetch(:owner_kind) == 'import' }
      (imports + declarations.sort_by { |item| item.fetch(:path) }).map { |item| owner_view(item) }
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

TypeScript::Merge.register_backend!
TypeScript::Merge.register_provider!
