# frozen_string_literal: true

module Ast
  module Merge
    module Layout
      # Named layout policy for whitespace comparison/rendering decisions.
      class Policy
        PRESERVE_EXACT = :preserve_exact
        BLANK_LINE_EQUIVALENT = :blank_line_equivalent
        MODES = [PRESERVE_EXACT, BLANK_LINE_EQUIVALENT].freeze

        attr_reader :mode, :metadata

        def initialize(mode: PRESERVE_EXACT, metadata: {}, **options)
          @mode = normalize_mode(mode)
          @metadata = metadata.merge(options).freeze
        end

        def preserve_exact?
          mode == PRESERVE_EXACT
        end

        def blank_line_equivalent?
          mode == BLANK_LINE_EQUIVALENT
        end

        def equivalent_blank_line?(left, right)
          if blank_line_equivalent?
            blank_line?(left) && blank_line?(right)
          else
            left == right
          end
        end

        def to_h
          {
            mode: mode,
            metadata: metadata,
            exact_preservation: preserve_exact?,
            blank_line_equivalence: blank_line_equivalent?
          }
        end

        private

        def normalize_mode(value)
          normalized = value&.to_sym
          return normalized if MODES.include?(normalized)

          raise ArgumentError, "Unknown layout policy mode: #{value.inspect}"
        end

        def blank_line?(value)
          value.to_s.strip.empty?
        end
      end
    end
  end
end
