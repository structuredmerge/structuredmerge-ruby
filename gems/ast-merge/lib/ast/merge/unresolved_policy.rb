# frozen_string_literal: true

module Ast
  module Merge
    # Declarative caller-facing policy for reviewable unresolved merge behavior.
    class UnresolvedPolicy
      VALID_PROVISIONAL_WINNERS = %i[destination template].freeze

      attr_reader :enabled_kinds, :provisional_winner, :provisional_winner_by_kind, :metadata

      def self.coerce(value)
        case value
        when nil then new
        when self then value
        when Hash then new(**value)
        else
          raise ArgumentError,
                "unresolved_policy must be an #{name} or Hash, got #{value.class}"
        end
      end

      def initialize(
        enabled_kinds: :all,
        provisional_winner: nil,
        provisional_winner_by_kind: {},
        metadata: {}
      )
        @enabled_kinds = normalize_enabled_kinds(enabled_kinds)
        @provisional_winner = normalize_provisional_winner(provisional_winner)
        @provisional_winner_by_kind = normalize_provisional_winner_by_kind(provisional_winner_by_kind)
        @metadata = metadata.dup.freeze
      end

      def unresolved_for?(kind)
        return true if enabled_kinds == :all

        enabled_kinds.include?(kind.to_sym)
      end

      def provisional_winner_for(kind, fallback: nil)
        normalize_provisional_winner(
          provisional_winner_by_kind.fetch(kind.to_sym, provisional_winner || fallback)
        )
      end

      def to_h
        {
          enabled_kinds: enabled_kinds,
          provisional_winner: provisional_winner,
          provisional_winner_by_kind: provisional_winner_by_kind,
          metadata: metadata
        }.compact
      end

      private

      def normalize_enabled_kinds(enabled_kinds)
        return :all if enabled_kinds.nil? || enabled_kinds == :all

        Array(enabled_kinds).map(&:to_sym).freeze
      end

      def normalize_provisional_winner(winner)
        return if winner.nil?
        return winner.to_sym if VALID_PROVISIONAL_WINNERS.include?(winner.to_sym)

        raise ArgumentError,
              "provisional_winner must be one of: #{VALID_PROVISIONAL_WINNERS.map(&:inspect).join(', ')}"
      end

      def normalize_provisional_winner_by_kind(policy)
        policy.to_h.each_with_object({}) do |(kind, winner), hash|
          hash[kind.to_sym] = normalize_provisional_winner(winner)
        end.freeze
      end
    end
  end
end
