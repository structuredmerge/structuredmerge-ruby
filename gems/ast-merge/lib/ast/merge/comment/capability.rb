# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Glossary:
      # - Parser capability: what a parser/backend can observe or return.
      # - Merge capability: what the merge runtime can safely do with that data.
      # - Support style/write model: how observed data is read, owned, and rendered.
      # - Ruleset capability declaration: the user-facing feature request.
      #
      # Comment::Capability is the parser-capability axis for comments. It must
      # not imply that a merge strategy is enabled or that a write model is safe.
      # Ruleset::FeatureProfile and Comment::SupportStyle connect this signal to
      # merge-facing behavior.
      #
      # This is intentionally a passive value object. It provides shared
      # vocabulary for planning and incremental adoption without changing merge
      # behavior on its own.
      #
      # Supported levels:
      # - :native_full - native comments + attachment hints are available
      # - :native_partial - some native comment support, but incomplete ownership data
      # - :native_comment_nodes_only - native comment nodes exist, but attachment is unknown
      # - :source_augmented - comments are inferred from source text
      # - :none - no comment support is available
      class Capability
        # Supported capability levels.
        #
        # @return [Array<Symbol>]
        LEVELS = %i[
          native_full
          native_partial
          native_comment_nodes_only
          source_augmented
          none
        ].freeze

        attr_reader :level, :details

        class << self
          # Build a capability describing full native comment support.
          #
          # @param details [Hash] producer metadata
          # @return [Capability]
          def native_full(**details)
            new(level: :native_full, **details)
          end

          # Build a capability describing partial native comment support.
          #
          # @param details [Hash] producer metadata
          # @return [Capability]
          def native_partial(**details)
            new(level: :native_partial, **details)
          end

          # Build a capability describing native comment nodes without attachment hints.
          #
          # @param details [Hash] producer metadata
          # @return [Capability]
          def native_comment_nodes_only(**details)
            new(level: :native_comment_nodes_only, **details)
          end

          # Build a capability describing source-augmented comment support.
          #
          # @param details [Hash] producer metadata
          # @return [Capability]
          def source_augmented(**details)
            new(level: :source_augmented, **details)
          end

          # Build a capability describing no available comment support.
          #
          # @param details [Hash] producer metadata
          # @return [Capability]
          def none(**details)
            new(level: :none, **details)
          end
        end

        def initialize(level:, details: {}, **options)
          @level = normalize_level(level)
          @details = details.merge(options).freeze
        end

        def native_full?
          level == :native_full
        end

        def native_partial?
          level == :native_partial
        end

        def native_comment_nodes_only?
          level == :native_comment_nodes_only
        end

        def source_augmented?
          level == :source_augmented
        end

        def none?
          level == :none
        end

        def native?
          native_full? || native_partial? || native_comment_nodes_only?
        end

        def augmented?
          source_augmented?
        end

        def available?
          !none?
        end

        def attachment_hints?
          details.fetch(:attachment_hints, native_full?)
        end

        def comment_nodes?
          details.fetch(:comment_nodes, native_full? || native_comment_nodes_only?)
        end

        # Return the capability as a normalized Hash.
        #
        # @return [Hash]
        def to_h
          {
            level: level,
            details: details,
            native: native?,
            augmented: augmented?,
            available: available?,
            attachment_hints: attachment_hints?,
            comment_nodes: comment_nodes?
          }
        end

        # Return a concise debug representation of the capability.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} level=#{level} details=#{details.inspect}>"
        end

        private

        def normalize_level(level)
          normalized = level&.to_sym
          return normalized if LEVELS.include?(normalized)

          raise ArgumentError,
                "Unknown comment capability level: #{level.inspect}. Expected one of: #{LEVELS.join(', ')}"
        end
      end
    end
  end
end
