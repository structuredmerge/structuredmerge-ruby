# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Declarative handling policy for a named ambiguous/corruption-class seam.
      class RepairPolicy
        attr_reader :kind, :handling, :metadata

        def initialize(kind:, handling:, metadata: {})
          @kind = kind&.to_sym
          @handling = Ast::Merge::Healer.normalize_mode(handling)
          @metadata = metadata.dup.freeze
        end

        def to_h
          {
            kind: kind,
            handling: handling,
            metadata: metadata
          }.compact
        end
      end
    end
  end
end
