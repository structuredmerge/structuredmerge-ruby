# frozen_string_literal: true

require 'prism/merge'

module Prism
  module Merge
    module RSpec
      # Reuses Prism::Merge's established directive and node-path projection as
      # native evidence for portable provider contract snapshots.
      module ProviderSnapshotExtension
        module_function

        # rubocop:disable Metrics/MethodLength -- the extension envelope keeps all native evidence explicit
        def call(source:, **)
          normalized = Prism::Merge.parse_ruby_normalized(source)
          nodes = normalized.fetch(:nodes)
          {
            schema: 'structuredmerge.extension/ruby-prism/v1',
            namespace: 'ruby-prism',
            capabilities: %w[comment-directives magic-comments native-node-kinds node-paths],
            payload: {
              parser_metadata: normalized.fetch(:metadata),
              nodes: nodes.map { |node| native_node_evidence(node) },
              native_tree_visibility: 'provider_internal'
            }
          }
        end
        # rubocop:enable Metrics/MethodLength

        def native_node_evidence(node)
          {
            id: node.fetch(:id),
            role: node.fetch(:role),
            backend_kind: node.fetch(:backend_kind),
            semantic_roles: node.fetch(:semantic_roles),
            metadata: node.fetch(:metadata)
          }
        end
        private_class_method :native_node_evidence
      end
    end
  end
end
