# frozen_string_literal: true

module Toml
  module Merge
    # Debug logging utility for Toml::Merge.
    # Extends the base Ast::Merge::DebugLogger with Toml-specific configuration.
    #
    # @example Enable debug logging
    #   ENV['TREE_HAVER_DEBUG'] = '1'
    #   DebugLogger.debug("Processing node", {type: "pair", line: 5})
    #
    # @example Disable debug logging (default)
    #   DebugLogger.debug("This won't be printed", {})
    module DebugLogger
      extend Ast::Merge::DebugLogger

      # Toml-specific configuration
      self.env_var_name = 'TREE_HAVER_DEBUG'
      self.log_prefix = '[Toml::Merge]'

      class << self
        # Override log_node to handle Toml-specific node types.
        #
        # @param node [Object] Node to log information about
        # @param label [String] Label for the node
        def log_node(node, label: 'Node')
          return unless enabled?

          info = case node
                 when Toml::Merge::NodeWrapper
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
