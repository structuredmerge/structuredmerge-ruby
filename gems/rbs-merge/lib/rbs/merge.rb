# frozen_string_literal: true

# External gems
# NOTE: rbs gem is loaded by the RBS backend when needed.

# tree_haver provides unified parsing via multiple backends
require 'tree_haver'

# Shared merge infrastructure
require 'ast/merge'
require_relative 'merge/version'

# This gem

module Rbs
  module Merge
    # Base error class for rbs-merge errors
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    # @api public
    class Error < Ast::Merge::Error; end

    # Raised when an RBS file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(rbs_content)
    #   rescue ParseError => e
    #     puts "RBS syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    #
    # @api public
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The RBS source that failed to parse
      # @param errors [Array] Parse errors from RBS
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template RBS file has syntax errors.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    #
    # @api public
    class TemplateParseError < ParseError; end

    # Raised when the destination RBS file has syntax errors.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    #
    # @api public
    class DestinationParseError < ParseError; end

    # Raised when merge-time corruption detection is configured to error.
    class CorruptionDetectedError < Error; end

    autoload :DebugLogger, 'rbs/merge/debug_logger'
    autoload :CommentTracker, 'rbs/merge/comment_tracker'
    autoload :FreezeNode, 'rbs/merge/freeze_node'
    autoload :MergeResult, 'rbs/merge/merge_result'
    autoload :NativeProjection, 'rbs/merge/native_projection'
    autoload :NodeTypeNormalizer, 'rbs/merge/node_type_normalizer'
    autoload :NodeWrapper, 'rbs/merge/node_wrapper'
    autoload :FileAnalysis, 'rbs/merge/file_analysis'
    autoload :ConflictResolver, 'rbs/merge/conflict_resolver'
    autoload :FileAligner, 'rbs/merge/file_aligner'
    autoload :SmartMerger, 'rbs/merge/smart_merger'

    # Backends module containing RBS gem backend for TreeHaver integration
    module Backends
      autoload :RbsBackend, 'rbs/merge/backends/rbs_backend'
    end

    # Tracks whether backends were registered, without class instance variables.
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)
    RBS_BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'rbs', family: 'rbs').freeze
    TREE_SITTER_BACKEND_REFERENCE = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND

    class << self
      # Register the current RBS parsing entrypoints with TreeHaver.
      #
      # This registers:
      # 1. the RBS gem backend
      # 2. the tree-sitter-rbs grammar when the sibling TreeHaver runtime can load it
      #
      # @api private
      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          # Register the RBS gem backend (for MRI Ruby)
          TreeHaver::BackendRegistry.register(RBS_BACKEND_REFERENCE)
          TreeHaver.register_language(
            :rbs,
            backend_module: Backends::RbsBackend,
            backend_type: :rbs,
            gem_name: 'rbs'
          )

          # Also register the tree-sitter-rbs grammar when present.
          grammar_finder = TreeHaver::GrammarFinder.new(:rbs)
          grammar_finder.register! if grammar_finder.available?

          TreeHaver::BackendRegistry.register_tag(:rbs_backend, category: :backend, backend_name: :rbs) do
            Backends::RbsBackend.available?
          end
          TreeHaver::BackendRegistry.register_tag(:rbs_gem, category: :gem, backend_name: :rbs_gem) do
            Backends::RbsBackend.available?
          end
          TreeHaver::BackendRegistry.register_tag(:rbs_grammar, category: :grammar, backend_name: :rbs_grammar) do
            TreeHaver::GrammarFinder.new(:rbs).available?
          end

          BACKEND_REGISTRY.registered = true
        end
      end

      def available_rbs_backends
        backends = [RBS_BACKEND_REFERENCE]
        registrations = TreeHaver.registered_languages(:rbs)
        backends << TREE_SITTER_BACKEND_REFERENCE if registrations.key?(:tree_sitter) || registrations.key?(:tslp)
        backends
      end

      def merge_provider
        @merge_provider ||= Provider.new
      end

      def register_provider!(replace: false)
        Ast::Merge.register_provider(merge_provider, replace: replace)
      end
    end
  end
end

Rbs::Merge.autoload :Provider, 'rbs/merge/provider'

# Register the RBS backend with TreeHaver when this gem is loaded
Rbs::Merge.register_backend!
Rbs::Merge.register_provider!

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :rbs_merge,
    require_path: 'rbs/merge',
    merger_class: 'Rbs::Merge::SmartMerger',
    test_source: "class Foo\nend",
    category: :code
  )
end
