# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Describes how a merge pipeline will own, read, and write comments.
      #
      # {Capability} answers what a parser/backend can provide. SupportStyle
      # answers how the merge implementation intends to use those comments
      # end-to-end. Keeping the two concepts separate lets parsers expose native
      # comment information while merge gems still converge on a portable write
      # contract, even when the real architecture uses a synthetic ownership or
      # output pipeline internally.
      #
      # This is the support-style/write-model axis. It is deliberately separate
      # from parser capability and from ruleset capability declarations.
      class SupportStyle
        STYLES = %i[
          source_augmented_portable_write
          native_read_portable_write
          native_mutation
          hybrid_native_owned
          unavailable
        ].freeze

        attr_reader :style, :details

        class << self
          # Build a support style that scans or tracks comments from source and
          # emits them entirely through the merge layer.
          #
          # @param details [Hash] producer metadata
          # @return [SupportStyle]
          def source_augmented_portable_write(**details)
            new(style: :source_augmented_portable_write, details: details)
          end

          # Build a support style that reads parser-native comments but emits
          # them through the merge layer's portable write contract.
          #
          # @param details [Hash] producer metadata
          # @return [SupportStyle]
          def native_read_portable_write(**details)
            new(style: :native_read_portable_write, details: details)
          end

          # Build a support style that mutates and emits comments via the native
          # parser AST.
          #
          # @param details [Hash] producer metadata
          # @return [SupportStyle]
          def native_mutation(**details)
            new(style: :native_mutation, details: details)
          end

          # Build a support style that mixes native-owned and synthetic comment
          # output. This should remain an escape hatch, not the default target.
          #
          # @param details [Hash] producer metadata
          # @return [SupportStyle]
          def hybrid_native_owned(**details)
            new(style: :hybrid_native_owned, details: details)
          end

          # Build a support style describing no usable comment pipeline.
          #
          # @param details [Hash] producer metadata
          # @return [SupportStyle]
          def unavailable(**details)
            new(style: :unavailable, details: details)
          end
        end

        # @param style [Symbol] normalized support style name
        # @param details [Hash] base metadata
        # @param options [Hash] additional metadata merged into +details+
        # @return [void]
        def initialize(style:, details: {}, **options)
          @style = normalize_style(style)
          @details = details.merge(options).freeze
        end

        def source_augmented_portable_write?
          style == :source_augmented_portable_write
        end

        def native_read_portable_write?
          style == :native_read_portable_write
        end

        def native_mutation?
          style == :native_mutation
        end

        def hybrid_native_owned?
          style == :hybrid_native_owned
        end

        def unavailable?
          style == :unavailable
        end

        def portable_write?
          source_augmented_portable_write? || native_read_portable_write?
        end

        def native_read?
          native_read_portable_write? || native_mutation? || hybrid_native_owned?
        end

        def native_write?
          native_mutation? || hybrid_native_owned?
        end

        def available?
          !unavailable?
        end

        # Return the support style as a normalized Hash.
        #
        # @return [Hash]
        def to_h
          {
            style: style,
            details: details,
            portable_write: portable_write?,
            native_read: native_read?,
            native_write: native_write?,
            available: available?
          }
        end

        # Return a concise debug representation of the support style.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} style=#{style} details=#{details.inspect}>"
        end

        private

        def normalize_style(style)
          normalized = style&.to_sym
          return normalized if STYLES.include?(normalized)

          raise ArgumentError,
                "Unknown comment support style: #{style.inspect}. Expected one of: #{STYLES.join(', ')}"
        end
      end
    end
  end
end
