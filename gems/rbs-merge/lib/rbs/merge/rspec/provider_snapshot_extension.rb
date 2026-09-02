# frozen_string_literal: true

require 'rbs/merge'

module Rbs
  module Merge
    module RSpec
      # Native RBS evidence for Ast::Merge provider contract snapshots.
      module ProviderSnapshotExtension
        module_function

        def call(tree:, **)
          {
            schema: 'structuredmerge.extension/ruby-rbs/v1',
            namespace: 'ruby-rbs',
            capabilities: %w[declaration-kinds method-types type-nodes],
            payload: {
              declarations: NativeProjection.call(tree.declarations),
              directives: NativeProjection.call(tree.directives),
              native_tree_visibility: 'provider_internal'
            }
          }
        end
      end
    end
  end
end
