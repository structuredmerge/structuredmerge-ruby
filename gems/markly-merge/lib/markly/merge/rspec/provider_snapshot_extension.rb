# frozen_string_literal: true

require 'markly/merge'

module Markly
  module Merge
    module RSpec
      # Native Markly block kinds, source positions, and known attributes for
      # portable provider contract snapshots.
      module ProviderSnapshotExtension
        NATIVE_ATTRIBUTES = %i[
          fence_info
          header_level
          list_delim
          list_start
          list_tight
          list_type
          title
          url
        ].freeze

        module_function

        def call(tree:, **)
          {
            schema: 'structuredmerge.extension/ruby-markly/v1',
            namespace: 'ruby-markly',
            capabilities: %w[attributes block-kinds source-positions],
            payload: {
              nodes: project_nodes(tree.root_node),
              native_tree_visibility: 'provider_internal'
            }
          }
        end

        # rubocop:disable Metrics/MethodLength -- breadth-first projection carries path and native evidence together
        def project_nodes(root)
          queue = [[root, '0']]
          queue.map do |node, path|
            children = node.children
            children.each_with_index { |child, index| queue << [child, "#{path}.#{index}"] }
            {
              path: path,
              type: node.type.to_s,
              native_type: node.raw_type.to_s,
              source_position: node.inner_source_position,
              attributes: native_attributes(node)
            }
          end
        end
        # rubocop:enable Metrics/MethodLength
        private_class_method :project_nodes

        def native_attributes(node)
          NATIVE_ATTRIBUTES.each_with_object({}) do |name, attributes|
            next unless node.inner_node.respond_to?(name)

            value = read_native_attribute(node.inner_node, name)
            attributes[name] = value if value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false
          end
        end
        private_class_method :native_attributes

        def read_native_attribute(node, name)
          node.public_send(name)
        rescue ::Markly::Error
          nil
        end
        private_class_method :read_native_attribute
      end
    end
  end
end
