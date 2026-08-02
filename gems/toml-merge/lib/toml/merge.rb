# frozen_string_literal: true

# External gems
# TreeHaver provides a unified cross-Ruby interface to tree-sitter.
# Toml::Merge registers TOML-specific backends with TreeHaver when loaded so
# parser_for(:toml) can resolve registered grammars and backends consistently.
require 'tree_haver'
require 'version_gem'

# Shared merge infrastructure
require 'ast/merge'
require_relative 'merge/version'

# This gem

# Toml::Merge provides a TOML file smart merge system using tree-sitter AST analysis.
# It intelligently merges template and destination TOML files by identifying matching
# keys and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.toml")
#   destination = File.read("destination.toml")
#   merger = Toml::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Toml::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Toml
  # Smart merge system for TOML files using tree-sitter AST analysis.
  # Provides intelligent merging by understanding TOML structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes TOML structure
  # @see ConflictResolver Resolves content conflicts
  module Merge
    PACKAGE_NAME = 'toml-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    TREE_SITTER_BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'kreuzberg-language-pack',
                                                                    family: 'tree-sitter').freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    # Base error class for Toml::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a TOML file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(toml_content)
    #   rescue ParseError => e
    #     puts "TOML syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The TOML source that failed to parse
      # @param errors [Array] Parse errors from tree-sitter
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each do |error|
    #       puts "  #{error.message}"
    #     end
    #   end
    class DestinationParseError < ParseError; end

    class CorruptionDetectedError < Error; end

    autoload :CommentTracker, 'toml/merge/comment_tracker'
    autoload :DebugLogger, 'toml/merge/debug_logger'
    autoload :Emitter, 'toml/merge/emitter'
    autoload :FileAnalysis, 'toml/merge/file_analysis'
    autoload :KeySorter, 'toml/merge/key_sorter'
    autoload :MergeResult, 'toml/merge/merge_result'
    autoload :NodeTypeNormalizer, 'toml/merge/node_type_normalizer'
    autoload :NodeWrapper, 'toml/merge/node_wrapper'
    autoload :ConflictResolver, 'toml/merge/conflict_resolver'
    autoload :SmartMerger, 'toml/merge/smart_merger'
    autoload :TableMatchRefiner, 'toml/merge/table_match_refiner'

    class << self
      def toml_feature_profile
        {
          family: 'toml',
          supported_dialects: ['toml'],
          supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      end

      def available_toml_backends
        toml_backend_available_for_analysis?(TREE_SITTER_BACKEND_REFERENCE.id) ? [TREE_SITTER_BACKEND_REFERENCE] : []
      end

      def toml_backend_feature_profile(backend: nil)
        requested = requested_toml_backend_id(backend)
        backend_ref = available_toml_backends.find { |candidate| candidate.id == requested }
        return unsupported_feature_result("Unsupported TOML backend #{requested}.") unless backend_ref

        toml_feature_profile.merge(
          backend: backend_ref.id,
          backend_ref: backend_ref.to_h
        )
      end

      def toml_plan_context(backend: nil)
        profile = toml_backend_feature_profile(backend: backend)
        return profile if profile[:ok] == false

        {
          family_profile: toml_feature_profile,
          feature_profile: {
            backend: profile[:backend],
            supports_dialects: false,
            supported_policies: profile[:supported_policies]
          }
        }
      end

      def parse_toml(source, dialect, backend: nil)
        return unsupported_feature_parse_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        requested = requested_toml_backend_id(backend)
        return unsupported_feature_parse_result("Unsupported TOML backend #{requested}.") unless available_toml_backends.any? do |candidate|
          candidate.id == requested
        end

        TreeHaver.with_backend(requested) { analyze_toml_source(source, dialect) }
      rescue StandardError => e
        parse_error_result(e.message)
      end

      def analyze_toml_source(source, dialect)
        return unsupported_feature_parse_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        analysis = FileAnalysis.new(source)
        return parse_error_result(analysis.errors.map(&:to_s).join('; ')) unless analysis.valid?

        {
          ok: true,
          diagnostics: [],
          analysis: {
            kind: 'toml',
            dialect: 'toml',
            normalized_source: normalize_toml_source(source),
            root_kind: 'table',
            owners: collect_file_analysis_owners(analysis)
          },
          policies: []
        }
      rescue StandardError => e
        parse_error_result(e.message)
      end

      def match_toml_owners(template, destination)
        Ast::Merge::OwnerSelection.match_by_path(template, destination)
      end

      def merge_toml(template_source, destination_source, dialect, backend: nil)
        return unsupported_feature_merge_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        requested = requested_toml_backend_id(backend)
        return unsupported_feature_merge_result("Unsupported TOML backend #{requested}.") unless available_toml_backends.any? do |candidate|
          candidate.id == requested
        end

        output = TreeHaver.with_backend(requested) do
          SmartMerger.new(
            template_source,
            destination_source,
            preference: :destination,
            add_template_only_nodes: true
          ).merge_result.to_toml
        end

        {
          ok: true,
          diagnostics: [],
          output: output,
          policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      rescue TemplateParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'template_parse_error', e.message)], policies: [] }
      rescue DestinationParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'destination_parse_error', e.message)], policies: [] }
      rescue StandardError => e
        { ok: false, diagnostics: [diagnostic('error', 'merge_error', e.message)], policies: [] }
      end

      def merge_toml_with_parser(template_source, destination_source, dialect)
        return unsupported_feature_merge_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'
        raise ArgumentError, 'merge_toml_with_parser requires a parser block' unless block_given?

        template_parse = yield(template_source, dialect)
        return provider_parse_failure(:template_parse_error, template_parse) unless template_parse[:ok]

        destination_parse = yield(destination_source, dialect)
        return provider_parse_failure(:destination_parse_error, destination_parse) unless destination_parse[:ok]

        output = SmartMerger.new(
          template_source,
          destination_source,
          preference: :destination,
          add_template_only_nodes: true
        ).merge_result.to_toml

        {
          ok: true,
          diagnostics: [],
          output: output,
          policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      rescue TemplateParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'template_parse_error', e.message)], policies: [] }
      rescue DestinationParseError => e
        { ok: false, diagnostics: [diagnostic('error', 'destination_parse_error', e.message)], policies: [] }
      rescue StandardError => e
        { ok: false, diagnostics: [diagnostic('error', 'merge_error', e.message)], policies: [] }
      end

      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND_REFERENCE)

          register_tree_sitter_backend!

          BACKEND_REGISTRY.registered = true
        end
      end

      private

      def register_tree_sitter_backend!
        grammar_finder = TreeHaver::GrammarFinder.new(:toml)
        grammar_finder.register! if grammar_finder.available?
      end

      def requested_toml_backend_id(backend)
        return backend.to_s unless backend.to_s.empty?

        current = TreeHaver.current_backend_id
        return current if toml_backend_available_for_analysis?(current)

        available_toml_backends.find do |backend_ref|
          toml_backend_available_for_analysis?(backend_ref.id)
        end&.id || TREE_SITTER_BACKEND_REFERENCE.id
      end

      def diagnostic(severity, category, message)
        { severity: severity, category: category, message: message }
      end

      def parse_error_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'parse_error', message)], policies: [] }
      end

      def provider_parse_failure(category, parse_result)
        diagnostics = Array(parse_result[:diagnostics])
        message = diagnostics.map { |diagnostic| diagnostic[:message] || diagnostic['message'] }.compact.join('; ')
        message = 'provider parse failed' if message.empty?
        { ok: false, diagnostics: [diagnostic('error', category.to_s, message)], policies: [] }
      end

      def normalize_toml_source(source)
        source.gsub(/\r\n?/, "\n")
      end

      def toml_backend_available_for_analysis?(backend_id)
        register_backend!
        registrations = TreeHaver.registered_languages(:toml)
        case backend_id.to_s
        when TREE_SITTER_BACKEND_REFERENCE.id
          registrations.key?(:tree_sitter) || registrations.key?(:tslp)
        else
          false
        end
      end

      def collect_file_analysis_owners(analysis)
        analysis.statements.flat_map do |statement|
          if statement.table? || statement.array_of_tables?
            collect_table_statement_owners(statement)
          elsif statement.pair?
            collect_pair_statement_owners(statement, [])
          else
            []
          end
        end.sort_by { |owner| owner.fetch(:path) }
      end

      def collect_table_statement_owners(statement)
        table_path = toml_owner_path_parts(statement.table_name)
        owner_kind = statement.array_of_tables? ? 'table_array' : 'table'
        [
          { path: toml_owner_path(table_path), owner_kind: owner_kind, match_key: table_path.last }
        ] + statement.pairs.flat_map { |pair| collect_pair_statement_owners(pair, table_path) }
      end

      def collect_pair_statement_owners(pair, parent_path)
        key_path = parent_path + toml_owner_path_parts(pair.key_name)
        owners = [{ path: toml_owner_path(key_path), owner_kind: 'key_value', match_key: key_path.last }]
        value = pair.value_node
        if value&.array?
          owners.concat(value.elements.each_with_index.map do |_element, index|
            { path: toml_owner_path(key_path + [index.to_s]), owner_kind: 'array_item' }
          end)
        end
        owners
      end

      def toml_owner_path_parts(value)
        value.to_s.split('.').map(&:strip).reject(&:empty?)
      end

      def toml_owner_path(parts)
        "/#{parts.join('/')}"
      end

      def unsupported_feature_parse_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'unsupported_feature', message)], policies: [] }
      end

      def unsupported_feature_merge_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'unsupported_feature', message)], policies: [] }
      end

      def unsupported_feature_result(message)
        { ok: false, diagnostic: diagnostic('error', 'unsupported_feature', message) }
      end
    end
  end
end

Toml::Merge.register_backend!

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :toml_merge,
    require_path: 'toml/merge',
    merger_class: 'Toml::Merge::SmartMerger',
    test_source: "[section]\nkey = \"value\"",
    category: :config
  )
end

Toml::Merge::Version.class_eval do
  extend VersionGem::Basic
end
