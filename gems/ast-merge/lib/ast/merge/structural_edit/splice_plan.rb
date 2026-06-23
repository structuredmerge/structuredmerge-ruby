# frozen_string_literal: true

module Ast
  module Merge
    module StructuralEdit
      # Passive plan for a contiguous structural splice.
      #
      # The first shared primitive models exact line-range replacement: keep the
      # original source untouched outside the replaced window and substitute only
      # the requested structural range. This avoids separator surgery in callers
      # such as PartialTemplateMergerBase and gives future remove/rehome work a
      # stable place to grow richer ownership-transfer rules.
      class SplicePlan
        # @return [String] original source content
        # @return [String] replacement text inserted for the removed line range
        # @return [Integer] first replaced line number
        # @return [Integer] last replaced line number
        # @return [Boundary, nil] surviving boundary before the replaced range
        # @return [Boundary, nil] surviving boundary after the replaced range
        # @return [Boolean] whether trailing blank lines removed with the range may be preserved
        # @return [Hash] producer metadata
        attr_reader :source,
                    :replacement,
                    :replace_start_line,
                    :replace_end_line,
                    :leading_boundary,
                    :trailing_boundary,
                    :preserve_removed_trailing_blank_lines,
                    :metadata

        # Build a plan for exact line-range replacement.
        #
        # @param source [String] original source text
        # @param replacement [String] replacement text for the removed range
        # @param replace_start_line [Integer] first replaced line, 1-based
        # @param replace_end_line [Integer] last replaced line, 1-based
        # @param leading_boundary [Boundary, nil] surviving boundary before the replaced range
        # @param trailing_boundary [Boundary, nil] surviving boundary after the replaced range
        # @param preserve_removed_trailing_blank_lines [Boolean] whether to preserve trailing blank lines from removed content
        # @param metadata [Hash] base metadata
        # @param options [Hash] extra metadata merged into +metadata+
        def initialize(source:, replacement:, replace_start_line:, replace_end_line:, leading_boundary: nil,
                       trailing_boundary: nil, preserve_removed_trailing_blank_lines: true, metadata: {}, **options)
          @source = source.to_s
          @replacement = replacement.to_s
          @replace_start_line = Integer(replace_start_line)
          @replace_end_line = Integer(replace_end_line)
          @leading_boundary = leading_boundary
          @trailing_boundary = trailing_boundary
          @preserve_removed_trailing_blank_lines = preserve_removed_trailing_blank_lines
          @metadata = metadata.merge(options).freeze

          validate_range!
        end

        # Return the source split into line chunks.
        #
        # @return [Array<String>]
        def line_chunks
          @line_chunks ||= source.lines
        end

        # Return content before the replaced range.
        #
        # @return [String]
        def before_content
          line_chunks[0...(replace_start_line - 1)].to_a.join
        end

        # Return the replaced line range.
        #
        # @return [Range]
        def line_range
          replace_start_line..replace_end_line
        end

        # Return the content removed by the splice.
        #
        # @return [String]
        def removed_content
          line_chunks[(replace_start_line - 1)..(replace_end_line - 1)].to_a.join
        end

        # Return content after the replaced range.
        #
        # @return [String]
        def after_content
          line_chunks[replace_end_line..].to_a.join
        end

        # Return merged content after applying the splice.
        #
        # @return [String]
        def merged_content
          +before_content + replacement_with_preserved_boundary_layout + after_content
        end

        def changed?
          merged_content != source
        end

        # Return self so splice-compatible plans share a common adapter surface.
        #
        # @return [SplicePlan]
        def to_splice_plan
          self
        end

        # Apply the splice to the original source or a compatible alternate source.
        #
        # @param alternate_source [String] alternate source text
        # @return [String]
        def apply_to(alternate_source = source)
          alternate_text = alternate_source.to_s
          return merged_content if alternate_text == source

          self.class.new(
            source: alternate_text,
            replacement: replacement,
            replace_start_line: replace_start_line,
            replace_end_line: replace_end_line,
            leading_boundary: leading_boundary,
            trailing_boundary: trailing_boundary,
            metadata: metadata
          ).merged_content
        end

        # Return a concise debug representation of the splice plan.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} lines=#{replace_start_line}..#{replace_end_line} changed=#{changed?}>"
        end

        private

        def replacement_with_preserved_boundary_layout
          result = +replacement

          result << missing_trailing_blank_line_chunks.join if preserve_removed_trailing_blank_lines?

          result
        end

        def preserve_removed_trailing_blank_lines?
          return false unless preserve_removed_trailing_blank_lines

          !after_content.empty? &&
            !missing_trailing_blank_line_chunks.empty?
        end

        def missing_trailing_blank_line_chunks
          removed_blank_chunks = trailing_blank_line_chunks(removed_content)
          replacement_blank_chunks = trailing_blank_line_chunks(replacement)
          return [] if removed_blank_chunks.empty?
          return [] if replacement_blank_chunks.length >= removed_blank_chunks.length
          return [] if after_content.start_with?("\n")

          removed_blank_chunks[replacement_blank_chunks.length..]
        end

        def trailing_blank_line_chunks(text)
          text.lines.reverse.take_while { |line| line.strip.empty? }.reverse
        end

        def validate_range!
          raise ArgumentError, 'replace_start_line must be >= 1' if replace_start_line < 1
          raise ArgumentError, 'replace_end_line must be >= replace_start_line' if replace_end_line < replace_start_line

          line_count = line_chunks.length
          return if replace_end_line <= line_count

          raise ArgumentError,
                "replace_end_line #{replace_end_line} exceeds source line count #{line_count}"
        end
      end
    end
  end
end
