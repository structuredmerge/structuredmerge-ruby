# frozen_string_literal: true

module Psych
  module Merge
    # Portable native Psych AST facts retained across workflow host boundaries.
    module ProviderExtension
      SCHEMA = 'structuredmerge.extension/ruby-psych/v1'
      CAPABILITIES = %w[aliases anchors documents scalar-styles tags].freeze

      module_function

      def call(analysis: nil, tree: nil, **)
        native_tree = analysis&.ast || tree&.inner_tree
        raise ArgumentError, 'Psych provider extension requires an analysis or TreeHaver tree' unless native_tree

        {
          schema: SCHEMA,
          namespace: 'ruby-psych',
          capabilities: CAPABILITIES,
          payload: {
            ast: NativeProjection.attribute_tree(native_tree),
            semantic: NativeProjection.semantic(native_tree),
            native_tree_visibility: 'provider_internal'
          }
        }
      end
    end
  end
end
