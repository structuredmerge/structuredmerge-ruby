# frozen_string_literal: true

module Dotenv
  module Merge
    # Debug logging support for dotenv-merge.
    # Extends the base Ast::Merge::DebugLogger with dotenv-specific configuration.
    #
    # @example Enable debug logging
    #   ENV["DOTENV_MERGE_DEBUG"] = "true"
    #
    # @example Direct usage
    #   Dotenv::Merge::DebugLogger.debug("message", { key: "value" })
    #
    # @see Ast::Merge::DebugLogger
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Configure for dotenv-merge
      self.env_var_name = 'DOTENV_MERGE_DEBUG'
      self.log_prefix = '[dotenv-merge]'
    end
  end
end
