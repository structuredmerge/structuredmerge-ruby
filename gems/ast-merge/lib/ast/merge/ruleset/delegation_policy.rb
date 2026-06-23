# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Declarative delegation strategy for a named merge surface.
      class DelegationPolicy
        attr_reader :surface_name, :strategy, :metadata

        def initialize(surface_name:, strategy:, metadata: {})
          @surface_name = surface_name&.to_sym
          @strategy = strategy&.to_sym
          @metadata = metadata.dup.freeze
        end

        def to_h
          {
            surface_name: surface_name,
            strategy: strategy,
            metadata: metadata
          }.compact
        end
      end
    end
  end
end
