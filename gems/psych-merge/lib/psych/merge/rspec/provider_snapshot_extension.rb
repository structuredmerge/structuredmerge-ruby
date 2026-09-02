# frozen_string_literal: true

require 'psych/merge'

module Psych
  module Merge
    module RSpec
      # Native Psych AST attributes retained by the workflow provider.
      module ProviderSnapshotExtension
        module_function

        def call(tree:, **)
          {
            schema: 'structuredmerge.extension/ruby-psych/v1',
            namespace: 'ruby-psych',
            capabilities: %w[aliases anchors documents scalar-styles tags],
            payload: {
              ast: NativeProjection.attribute_tree(tree.inner_tree),
              semantic: NativeProjection.semantic(tree.inner_tree),
              native_tree_visibility: 'provider_internal'
            }
          }
        end
      end
    end
  end
end
