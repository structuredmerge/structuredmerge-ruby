# frozen_string_literal: true

module Prism
  module Merge
    # Debug logging utility for Prism::Merge.
    # Extends the base Ast::Merge::DebugLogger with Prism-specific configuration.
    #
    # @example Enable debug logging
    #   ENV['PRISM_MERGE_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "mapping", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Prism-specific configuration
      self.env_var_name = 'PRISM_MERGE_DEBUG'
      self.log_prefix = '[Prism::Merge]'

      # Override extract_node_info to handle Prism-specific node types.
      #
      # @param node [Object] Node to extract info from
      # @return [Hash] Node information
      class << self
        def extract_node_info(node)
          if node.is_a?(Prism::Merge::FreezeNode)
            return { type: 'FreezeNode', lines: "#{node.start_line}..#{node.end_line}" }
          end

          # Delegate to base implementation for other node types
          Ast::Merge::DebugLogger.extract_node_info(node)
        end
      end
    end
  end
end
