# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Reviewable unresolved merge case surfaced by a runtime merge operation.
      class ResolutionCase
        def self.from_h(payload)
          payload = payload.to_h
          new(
            case_id: payload.key?(:case_id) ? payload[:case_id] : payload.fetch('case_id'),
            reason: payload.key?(:reason) ? payload[:reason] : payload.fetch('reason'),
            candidates: payload.key?(:candidates) ? payload[:candidates] : payload.fetch('candidates'),
            provisional_winner: payload[:provisional_winner] || payload['provisional_winner'],
            surface_path: payload[:surface_path] || payload['surface_path'],
            operation_id: payload[:operation_id] || payload['operation_id'],
            metadata: payload.fetch(:metadata, payload.fetch('metadata', {}))
          )
        end

        attr_reader :case_id,
                    :reason,
                    :candidates,
                    :provisional_winner,
                    :surface_path,
                    :operation_id,
                    :metadata

        def initialize(
          case_id:,
          reason:,
          candidates:,
          provisional_winner: nil,
          surface_path: nil,
          operation_id: nil,
          metadata: {}
        )
          @case_id = case_id.to_s
          @reason = reason.to_sym
          @candidates = normalize_candidates(candidates)
          @provisional_winner = provisional_winner&.to_sym
          @surface_path = surface_path
          @operation_id = operation_id
          @metadata = metadata.dup.freeze

          validate_provisional_winner!
        end

        def unresolved?
          true
        end

        def selected_candidate
          candidate_for(provisional_winner)
        end

        def candidate_for(selection = provisional_winner)
          return if selection.nil?

          candidates.fetch(selection.to_sym) do
            raise ArgumentError,
                  "selection #{selection.inspect} must be present in candidates"
          end
        end

        def to_h
          {
            case_id: case_id,
            reason: reason,
            candidates: candidates,
            provisional_winner: provisional_winner,
            surface_path: surface_path,
            operation_id: operation_id,
            metadata: metadata
          }.compact
        end

        private

        def normalize_candidates(candidates)
          candidates.to_h.transform_keys(&:to_sym).freeze
        end

        def validate_provisional_winner!
          return if provisional_winner.nil?
          return if candidates.key?(provisional_winner)

          raise ArgumentError,
                "provisional_winner #{provisional_winner.inspect} must be present in candidates"
        end
      end
    end
  end
end
