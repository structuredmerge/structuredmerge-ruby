# frozen_string_literal: true

# External gems
require 'psych'
require 'tree_haver'
require 'yaml/merge'

# Shared merge infrastructure
require 'ast/merge'
require_relative 'merge/version'

# This gem

# Psych::Merge provides a generic YAML file smart merge system using Psych AST analysis.
# It intelligently merges template and destination YAML files by identifying matching
# keys and resolving differences using structural signatures.
#
# @example Basic usage
#   template = File.read("template.yml")
#   destination = File.read("destination.yml")
#   merger = Psych::Merge::SmartMerger.new(template, destination)
#   result = merger.merge
#
# @example With debug information
#   merger = Psych::Merge::SmartMerger.new(template, destination)
#   debug_result = merger.merge_with_debug
#   puts debug_result[:content]
#   puts debug_result[:statistics]
module Psych
  # Smart merge system for YAML files using Psych AST analysis.
  # Provides intelligent merging by understanding YAML structure
  # rather than treating files as plain text.
  #
  # @see SmartMerger Main entry point for merge operations
  # @see FileAnalysis Analyzes YAML structure
  # @see ConflictResolver Resolves content conflicts
  module Merge
    PACKAGE_NAME = 'psych-merge'
    DESTINATION_WINS_ARRAY_POLICY = {
      surface: 'array',
      name: 'destination_wins_array'
    }.freeze
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'psych', family: 'native').freeze
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

    # Base error class for Psych::Merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a YAML file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(yaml_content)
    #   rescue ParseError => e
    #     puts "YAML syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The YAML source that failed to parse
      # @param errors [Array] Parse errors from Psych
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

    autoload :CommentTracker, 'psych/merge/comment_tracker'
    autoload :DebugLogger, 'psych/merge/debug_logger'
    autoload :DiffMapper, 'psych/merge/diff_mapper'
    autoload :Emitter, 'psych/merge/emitter'
    autoload :FreezeNode, 'psych/merge/freeze_node'
    autoload :FileAnalysis, 'psych/merge/file_analysis'
    autoload :MappingEntry, 'psych/merge/file_analysis'
    autoload :MergeResult, 'psych/merge/merge_result'
    autoload :NativeProjection, 'psych/merge/native_projection'
    autoload :NodeTypeNormalizer, 'psych/merge/node_type_normalizer'
    autoload :NodeWrapper, 'psych/merge/node_wrapper'
    autoload :ConflictResolver, 'psych/merge/conflict_resolver'
    autoload :PartialTemplateMerger, 'psych/merge/partial_template_merger'
    autoload :SmartMerger, 'psych/merge/smart_merger'
    autoload :MappingMatchRefiner, 'psych/merge/mapping_match_refiner'
    autoload :ProviderExtension, 'psych/merge/provider_extension'

    class << self
      def yaml_feature_profile
        {
          family: 'yaml',
          supported_dialects: ['yaml'],
          supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
        }
      end

      def available_yaml_backends
        [BACKEND_REFERENCE]
      end

      def yaml_backend_feature_profile(backend: nil)
        requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
        unless requested == BACKEND_REFERENCE.id
          return unsupported_feature_result("Unsupported YAML backend #{requested}.")
        end

        yaml_feature_profile.merge(
          backend: BACKEND_REFERENCE.id,
          backend_ref: BACKEND_REFERENCE.to_h
        )
      end

      def yaml_plan_context(backend: nil)
        profile = yaml_backend_feature_profile(backend: backend)
        return profile if profile[:ok] == false

        {
          family_profile: yaml_feature_profile,
          feature_profile: {
            backend: profile[:backend],
            supports_dialects: true,
            supported_policies: profile[:supported_policies]
          }
        }
      end

      def parse_yaml(source, dialect, backend: nil)
        requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
        unless requested == BACKEND_REFERENCE.id
          return unsupported_feature_parse_result("Unsupported YAML backend #{requested}.")
        end
        return unsupported_feature_parse_result("Unsupported YAML dialect #{dialect}.") unless dialect == 'yaml'

        parsed = yaml_value_for_source(source)
        Yaml::Merge.analyze_yaml_document(parsed, dialect)
      rescue TreeHaver::Error, StandardError => e
        parse_error_result(e.message)
      end

      def match_yaml_owners(template, destination)
        Yaml::Merge.match_yaml_owners(template, destination)
      end

      def merge_yaml(
        template_source,
        destination_source,
        dialect,
        backend: nil,
        comment_merge_policy: :preserve_destination,
        preference: :destination,
        add_template_only_nodes: true,
        add_template_only_sequence_items: false,
        **_options
      )
        requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
        unless requested == BACKEND_REFERENCE.id
          return unsupported_feature_merge_result("Unsupported YAML backend #{requested}.")
        end
        return unsupported_feature_merge_result("Unsupported YAML dialect #{dialect}.") unless dialect == 'yaml'

        output = SmartMerger.new(
          template_source,
          destination_source,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          add_template_only_sequence_items: add_template_only_sequence_items,
          recursive: true,
          comment_merge_policy: comment_merge_policy
        ).merge

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

          TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

          TreeHaver.register_language(
            :yaml,
            backend_module: TreeHaver::Backends::Psych,
            backend_type: :psych,
            gem_name: 'psych'
          )

          BACKEND_REGISTRY.registered = true
        end
      end

      def yaml_value_for_source(source)
        tree = TreeHaver.with_backend(BACKEND_REFERENCE.id) do
          TreeHaver.parser_for(:yaml, backend_type: :psych).parse(source)
        end
        yaml_document_value_from_tree(tree)
      end

      private

      def diagnostic(severity, category, message)
        { severity: severity, category: category, message: message }
      end

      def parse_error_result(message)
        { ok: false, diagnostics: [diagnostic('error', 'parse_error', message)], policies: [] }
      end

      def yaml_document_value_from_tree(tree)
        root = tree.root_node
        raise TreeHaver::NotAvailable, 'YAML parse returned no root node' unless root

        document = root.children.find { |child| child.type.to_s == 'document' }
        yaml_value_from_node(document&.children&.first)
      end

      def yaml_value_from_node(node)
        return nil unless node

        case node.type.to_s
        when 'mapping'
          yaml_mapping_from_node(node)
        when 'sequence'
          node.children.map { |child| yaml_value_from_node(child) }
        when 'scalar'
          yaml_scalar_from_node(node)
        else
          raise TreeHaver::NotAvailable, "Unsupported YAML node #{node.type}"
        end
      end

      def yaml_mapping_from_node(node)
        children = node.children
        children.each_slice(2).each_with_object({}) do |(key_node, value_node), mapping|
          key = yaml_value_from_node(key_node)
          mapping[key] = yaml_value_from_node(value_node)
        end
      end

      def yaml_scalar_from_node(node)
        value = node.value.to_s
        case node.tag.to_s
        when 'tag:yaml.org,2002:null'
          nil
        when 'tag:yaml.org,2002:bool'
          value.downcase == 'true'
        when 'tag:yaml.org,2002:int'
          Integer(value.delete('_'), 0)
        when 'tag:yaml.org,2002:float'
          Float(value.delete('_'))
        else
          value
        end
      rescue ArgumentError
        value
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

require_relative 'merge/provider'

Psych::Merge.register_backend!
Psych::Merge.register_provider!

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :psych_merge,
    require_path: 'psych/merge',
    merger_class: 'Psych::Merge::SmartMerger',
    test_source: 'key: value',
    category: :config
  )
end
