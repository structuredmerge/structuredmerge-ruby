# frozen_string_literal: true

module Ast
  module Merge
    # Serializable unresolved-review payload for save/resume flows.
    class UnresolvedReviewState
      SCHEMA_VERSION = 1

      attr_reader :schema_version, :cases, :selections, :metadata

      def self.coerce(value)
        case value
        when self then value
        when Hash then from_h(value)
        else
          raise ArgumentError,
                "unresolved review state must be a #{name} or Hash, got #{value.class}"
        end
      end

      def self.from_h(payload)
        payload = payload.to_h
        new(
          schema_version: payload.fetch(:schema_version, payload.fetch('schema_version', SCHEMA_VERSION)),
          cases: payload.fetch(:cases, payload.fetch('cases', [])),
          selections: payload.fetch(:selections, payload.fetch('selections', {})),
          metadata: payload.fetch(:metadata, payload.fetch('metadata', {}))
        )
      end

      def initialize(cases:, schema_version: SCHEMA_VERSION, selections: {}, metadata: {})
        @schema_version = schema_version.to_i
        @cases = Array(cases).map do |entry|
          entry.is_a?(Runtime::ResolutionCase) ? entry : Runtime::ResolutionCase.from_h(entry)
        end.freeze
        @selections = normalize_selections(selections)
        @metadata = metadata.to_h.dup.freeze
      end

      def to_h
        {
          schema_version: schema_version,
          cases: cases.map(&:to_h),
          selections: selections,
          metadata: metadata
        }
      end

      private

      def normalize_selections(selections)
        selections.to_h.each_with_object({}) do |(case_id, selection), hash|
          hash[case_id.to_s] = selection&.to_sym
        end.freeze
      end
    end
  end
end
