# frozen_string_literal: true

module Psych
  module Merge
    # Debug logging utility for Psych::Merge.
    # Extends the base Ast::Merge::DebugLogger with Psych-specific configuration.
    #
    # @example Enable debug logging
    #   ENV['PSYCH_MERGE_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "mapping", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Psych-specific configuration
      self.env_var_name = 'PSYCH_MERGE_DEBUG'
      self.log_prefix = '[Psych::Merge]'

      class << self
        # Override log_node to handle Psych-specific node types.
        #
        # @param node [Object] Node to log information about
        # @param label [String] Label for the node
        def log_node(node, label: 'Node')
          return unless enabled?

          info = case node
                 when Psych::Merge::FreezeNode
                   { type: 'FreezeNode', lines: "#{node.start_line}..#{node.end_line}" }
                 when Psych::Merge::MappingEntry
                   { type: 'MappingEntry', key: node.key_name, lines: "#{node.start_line}..#{node.end_line}" }
                 when Psych::Merge::NodeWrapper
                   { type: node.node.class.name.split('::').last, lines: "#{node.start_line}..#{node.end_line}" }
                 else
                   extract_node_info(node)
                 end

          debug(label, info)
        end
      end
    end
  end
end
