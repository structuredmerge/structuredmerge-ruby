# frozen_string_literal: true

module Markdown
  module Merge
    # Debug logging utility for Markdown::Merge operations.
    #
    # Extends Ast::Merge::DebugLogger to provide consistent logging
    # across all merge gems. Logs are controlled via environment variables.
    #
    # @example Enable debug logging
    #   ENV["MARKDOWN_MERGE_DEBUG"] = "1"
    #   DebugLogger.debug("Parsing markdown", { file: "README.md" })
    #
    # @example Time an operation
    #   result = DebugLogger.time("parse") { Markly.parse(source) }
    #
    # @see Ast::Merge::DebugLogger Base module
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Configure for markdown-merge
      self.env_var_name = 'MARKDOWN_MERGE_DEBUG'
      self.log_prefix = '[markdown-merge]'
    end
  end
end
