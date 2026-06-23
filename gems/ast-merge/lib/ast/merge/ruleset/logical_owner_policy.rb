# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Declarative policy for a logical owner kind.
      class LogicalOwnerPolicy
        PRESERVE_ALWAYS = :preserve_always
        PRESERVE_IF_REFERENCED = :preserve_if_referenced
        REMOVE_UNREFERENCED = :remove_unreferenced
        ACTIONS = [PRESERVE_ALWAYS, PRESERVE_IF_REFERENCED, REMOVE_UNREFERENCED].freeze

        attr_reader :kind, :action, :metadata

        def initialize(kind:, action:, metadata: {}, **options)
          @kind = kind.to_sym
          @action = normalize_action(action)
          @metadata = metadata.merge(options).freeze
        end

        def preserve?(referenced:)
          case action
          when PRESERVE_ALWAYS
            true
          when PRESERVE_IF_REFERENCED
            referenced
          when REMOVE_UNREFERENCED
            referenced
          else
            false
          end
        end

        def to_h
          {
            kind: kind,
            action: action,
            metadata: metadata
          }
        end

        private

        def normalize_action(value)
          normalized = value&.to_sym
          return normalized if ACTIONS.include?(normalized)

          raise ArgumentError, "Unknown logical owner action: #{value.inspect}"
        end
      end
    end
  end
end
