# frozen_string_literal: true

module Markly
  module Merge
    # Debug logging utility for Markly::Merge operations.
    #
    # Extends Ast::Merge::DebugLogger to provide consistent logging
    # across all merge gems. Logs are controlled via environment variables.
    #
    # @example Enable debug logging
    #   ENV["MARKLY_MERGE_DEBUG"] = "1"
    #   DebugLogger.debug("Parsing markdown", { file: "README.md" })
    #
    # @example Time an operation
    #   result = DebugLogger.time("parse") { Markly.parse(source) }
    #
    # @see Ast::Merge::DebugLogger Base module
    module DebugLogger
      Markdown::Merge::WrapperSupport.configure_debug_logger!(
        debug_logger_module: self,
        env_var_name: 'MARKLY_MERGE_DEBUG',
        log_prefix: '[markly-merge]'
      )
    end
  end
end
