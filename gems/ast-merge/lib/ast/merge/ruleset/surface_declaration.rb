# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Declarative description of a merge-relevant nested/embedded surface.
      class SurfaceDeclaration
        attr_reader :name, :selector, :metadata

        def initialize(name:, selector:, metadata: {})
          @name = name&.to_sym
          @selector = selector&.to_sym
          @metadata = metadata.dup.freeze
        end

        def to_h
          {
            name: name,
            selector: selector,
            metadata: metadata
          }.compact
        end
      end
    end
  end
end
