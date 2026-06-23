# frozen_string_literal: true

module Json
  module Merge
    # Debug logging utility for Json::Merge.
    # Extends the base Ast::Merge::DebugLogger with Json-specific configuration.
    #
    # @example Enable debug logging
    #   ENV['JSON_MERGE_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "pair", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Json-specific configuration
      self.env_var_name = 'JSON_MERGE_DEBUG'
      self.log_prefix = '[Json::Merge]'

      class << self
        # Override log_node to handle Json-specific node types.
        #
        # @param node [Object] Node to log information about
        # @param label [String] Label for the node
        def log_node(node, label: 'Node')
          return unless enabled?

          info = case node
                 when Json::Merge::NodeWrapper
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
