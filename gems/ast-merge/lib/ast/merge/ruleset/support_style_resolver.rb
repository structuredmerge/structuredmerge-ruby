# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Bridges parsed ruleset read strategies to runtime support-style objects.
      class SupportStyleResolver
        class << self
          def call(read:, source:, capability:, style:)
            case read
            when :source_augmented_portable_write
              Comment::SupportStyle.source_augmented_portable_write(
                source: source,
                capability: capability,
                style: style
              )
            when :native_read_portable_write
              Comment::SupportStyle.native_read_portable_write(
                source: source,
                capability: capability,
                style: style
              )
            when :native_mutation
              Comment::SupportStyle.native_mutation(
                source: source,
                capability: capability,
                style: style
              )
            else
              raise ArgumentError, "Unknown ruleset read strategy: #{read.inspect}"
            end
          end
        end
      end
    end
  end
end
