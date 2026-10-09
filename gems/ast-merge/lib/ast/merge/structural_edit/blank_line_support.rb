# frozen_string_literal: true

module Ast
  module Merge
    module StructuralEdit
      # Blank-line invariants for structural splices and removals.
      #
      # This module owns the separator arithmetic a splice must respect so that
      # editing a line range cannot invent blank lines the source never had. It
      # stays parser-agnostic, working purely on source text the same way
      # +BoundarySupport+ works purely on line ranges and attachments.
      #
      # The two rules here are complementary:
      #
      # - {#missing_trailing_blank_line_chunks} decides which trailing blanks a
      #   replacement should re-emit so it is not left butting against the
      #   following content.
      # - {#cap_junction_blank_runs} then limits the blank run formed where the
      #   spliced head meets the untouched tail, so the two sides of a junction
      #   never stack into a longer run than either had.
      #
      # Removal is what makes both rules necessary. A replacement supplies its own
      # text, so the head usually ends in content and no junction run forms.
      # Deletion supplies none, which is exactly when separators on both sides of
      # the removed range become adjacent.
      module BlankLineSupport
        module_function

        # Trailing blank lines of +text+, as an array of line chunks.
        #
        # The chunks keep their trailing newlines so callers can rejoin them
        # losslessly.
        #
        # @param text [String] source fragment
        # @return [Array<String>] trailing blank lines, in source order
        def trailing_blank_line_chunks(text)
          text.lines.reverse.take_while { |line| line.strip.empty? }.reverse
        end

        # Leading blank lines of +text+.
        #
        # @param text [String] source fragment
        # @return [Array<String>] leading blank lines, in source order
        def leading_blank_line_chunks(text)
          text.lines.take_while { |line| line.strip.empty? }
        end

        # Trailing blanks from a removed range that a replacement should re-emit,
        # so the replacement is not left butting against the following content.
        #
        # Returns nothing when the replacement already ends in at least as many
        # blanks as the removed range did, or when the tail opens with a blank and
        # so needs no separator.
        #
        # @param removed_content [String] source removed by the splice
        # @param replacement [String] text substituted for the removed range
        # @param after_content [String] untouched source following the range
        # @return [Array<String>] trailing blank chunks to append to the replacement
        def missing_trailing_blank_line_chunks(removed_content:, replacement:, after_content:)
          removed_chunks = trailing_blank_line_chunks(removed_content)
          kept_chunks = trailing_blank_line_chunks(replacement)
          return [] if removed_chunks.empty?
          return [] if kept_chunks.length >= removed_chunks.length
          return [] if after_content.start_with?("\n")

          removed_chunks[kept_chunks.length..]
        end

        # Cap the blank-line run formed where a spliced head meets the untouched
        # tail, so a splice never emits a longer run than any single contributor
        # already had.
        #
        # Capping at the longest contributing run rather than at one is what keeps
        # a source that genuinely separates sections with two blanks intact, and
        # leaves in-place replacement unaffected, since its head ends with the
        # replacement text and forms no junction run at all. This mirrors the
        # excess-blank trimming the *-merge emitters already perform, keeping one
        # rule across the stack instead of a second, weaker one for structural
        # edits.
        #
        # This is a line-count invariant, not full blank-line ownership.
        # Layout::Gap#effective_controller can attribute a shared gap to a
        # surviving owner, but only where the analysis populates gaps. Psych-backed
        # analyses report empty layout attachments for nested mapping entries, so
        # ownership has no data to consult there. Wiring gap ownership into removal
        # needs gap population for those owners first.
        #
        # @param head [String] spliced source up to the junction
        # @param tail [String] untouched source after the junction
        # @param preserved_count [Integer] blanks appended to the replacement
        # @param before_content [String] untouched source before the range
        # @param replacement [String] text substituted for the removed range
        # @return [String] head and tail joined with the junction run capped
        def cap_junction_blank_runs(head:, tail:, preserved_count:, before_content:, replacement:)
          trailing_run = trailing_blank_line_chunks(head).length
          return head + tail if tail.empty? || trailing_run.zero?

          leading_run = leading_blank_line_chunks(tail).length
          allowed = max_contributing_blank_run(before_content, replacement, preserved_count, leading_run)
          excess = (trailing_run + leading_run) - allowed
          return head + tail unless excess.positive?

          # +allowed+ counts +leading_run+ among the contributors, so
          # +excess+ is always at most +trailing_run+ and never pops past the
          # head's own blanks. +trailing_run+ is nonzero because of the guard above.
          pop_blank_lines(head, count: excess) + tail
        end

        # Longest blank run any single contributor brings to a junction.
        #
        # The contributors are the blanks before the range, the blanks the
        # replacement itself ends with, the blanks preserved from the removed
        # range, and the blanks the tail opens with.
        #
        # @return [Integer]
        # @api private
        def max_contributing_blank_run(before_content, replacement, preserved_count, leading_run)
          [
            trailing_blank_line_chunks(before_content).length,
            trailing_blank_line_chunks(replacement).length,
            preserved_count,
            leading_run
          ].max
        end

        # Drop the last +count+ blank lines from +head+.
        #
        # @return [String]
        # @api private
        def pop_blank_lines(head, count:)
          head_lines = head.lines
          head_lines.pop(count)
          head_lines.join
        end
      end
    end
  end
end
