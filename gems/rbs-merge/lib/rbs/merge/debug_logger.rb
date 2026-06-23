# frozen_string_literal: true

module Rbs
  module Merge
    # Debug logging utility for RBS merge operations.
    # Extends Ast::Merge::DebugLogger for shared functionality.
    #
    # @example Enable debug logging
    #   ENV['RBS_MERGE_DEBUG'] = '1'
    #   # ... perform merge operations ...
    #
    # @example Time a block of code
    #   result = Rbs::Merge::DebugLogger.time("parsing") { parse_file }
    #
    # @see Ast::Merge::DebugLogger
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # RBS-specific configuration
      self.env_var_name = 'RBS_MERGE_DEBUG'
      self.log_prefix = '[rbs-merge]'
    end
  end
end
