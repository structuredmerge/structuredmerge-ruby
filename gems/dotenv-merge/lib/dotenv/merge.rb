# frozen_string_literal: true

# External gems

# Shared merge infrastructure
require 'ast/merge'
require 'plain/merge'
require 'tree_haver'
require_relative 'merge/version'

# This gem

module Dotenv
  module Merge
    # Base error class for dotenv-merge
    # Inherits from Ast::Merge::Error for consistency across merge gems.
    class Error < Ast::Merge::Error; end

    # Raised when a dotenv file has parsing errors.
    # Inherits from Ast::Merge::ParseError for consistency across merge gems.
    #
    # @example Handling parse errors
    #   begin
    #     analysis = FileAnalysis.new(env_content)
    #   rescue ParseError => e
    #     puts "Dotenv syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error}" }
    #   end
    class ParseError < Ast::Merge::ParseError
      # @param message [String, nil] Error message (auto-generated if nil)
      # @param content [String, nil] The dotenv source that failed to parse
      # @param errors [Array] Parse errors
      def initialize(message = nil, content: nil, errors: [])
        super(message, errors: errors, content: content)
      end
    end

    # Raised when the template file cannot be parsed.
    #
    # @example Handling template parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue TemplateParseError => e
    #     puts "Template syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    class TemplateParseError < ParseError; end

    # Raised when the destination file cannot be parsed.
    #
    # @example Handling destination parse errors
    #   begin
    #     merger = SmartMerger.new(template, destination)
    #     result = merger.merge
    #   rescue DestinationParseError => e
    #     puts "Destination syntax error: #{e.message}"
    #     e.errors.each { |error| puts "  #{error.message}" }
    #   end
    class DestinationParseError < ParseError; end

    # Raised when merge-time corruption detection is configured to error.
    class CorruptionDetectedError < Error; end

    autoload :DebugLogger, 'dotenv/merge/debug_logger'
    autoload :Backend, 'dotenv/merge/backend'
    autoload :CommentTracker, 'dotenv/merge/comment_tracker'
    autoload :EnvLine, 'dotenv/merge/env_line'
    autoload :FreezeNode, 'dotenv/merge/freeze_node'
    autoload :FileAnalysis, 'dotenv/merge/file_analysis'
    autoload :MergeResult, 'dotenv/merge/merge_result'
    autoload :SmartMerger, 'dotenv/merge/smart_merger'
  end
end

require_relative 'merge/backend'
Dotenv::Merge.register_backend!

# Register with ast-merge's MergeGemRegistry for RSpec dependency tags
# Only register if MergeGemRegistry is loaded (i.e., in test environment)
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :dotenv_merge,
    require_path: 'dotenv/merge',
    merger_class: 'Dotenv::Merge::SmartMerger',
    test_source: 'KEY=value',
    category: :config
  )
end
