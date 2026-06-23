# frozen_string_literal: true

module Bash
  module Merge
    # Debug logging utility for Bash::Merge.
    # Extends the base Ast::Merge::DebugLogger with Bash-specific configuration.
    #
    # @example Enable debug logging
    #   ENV['BASH_MERGE_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "function_definition", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Bash-specific configuration
      self.env_var_name = 'BASH_MERGE_DEBUG'
      self.log_prefix = '[Bash::Merge]'

      class << self
        # Override log_node to handle Bash-specific node types.
        #
        # @param node [Object] Node to log information about
        # @param label [String] Label for the node
        def log_node(node, label: 'Node')
          return unless enabled?

          info = case node
                 when Bash::Merge::FreezeNode
                   { type: 'FreezeNode', lines: "#{node.start_line}..#{node.end_line}" }
                 when Bash::Merge::NodeWrapper
                   { type: node.type.to_s, lines: "#{node.start_line}..#{node.end_line}" }
                 else
                   extract_node_info(node)
                 end

          debug(label, info)
        end
      end
    end
  end
end
