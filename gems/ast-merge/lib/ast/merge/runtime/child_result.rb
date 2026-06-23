# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Return contract from a delegated child merge.
      class ChildResult
        attr_reader :replacement_text,
                    :preserved_boundaries,
                    :diagnostics,
                    :capabilities_used,
                    :capabilities_missing,
                    :unresolved_cases,
                    :metadata

        def initialize(
          replacement_text:,
          preserved_boundaries: {},
          diagnostics: [],
          capabilities_used: [],
          capabilities_missing: [],
          unresolved_cases: [],
          metadata: {}
        )
          @replacement_text = replacement_text.to_s
          @preserved_boundaries = normalize_hash(preserved_boundaries)
          @diagnostics = Array(diagnostics).dup.freeze
          @capabilities_used = Array(capabilities_used).map(&:to_sym).freeze
          @capabilities_missing = Array(capabilities_missing).map(&:to_sym).freeze
          @unresolved_cases = Array(unresolved_cases).dup.freeze
          @metadata = metadata.dup.freeze
        end

        def unresolved?
          unresolved_cases.any?
        end

        def to_h
          {
            replacement_text: replacement_text,
            preserved_boundaries: preserved_boundaries,
            diagnostics: diagnostics.map { |diagnostic| diagnostic.respond_to?(:to_h) ? diagnostic.to_h : diagnostic },
            capabilities_used: capabilities_used,
            capabilities_missing: capabilities_missing,
            unresolved_cases: unresolved_cases.map do |resolution_case|
              resolution_case.respond_to?(:to_h) ? resolution_case.to_h : resolution_case
            end,
            metadata: metadata
          }
        end

        private

        def normalize_hash(value)
          value.to_h.each_with_object({}) do |(key, entry), hash|
            hash[key.to_sym] = entry
          end.freeze
        end
      end
    end
  end
end
