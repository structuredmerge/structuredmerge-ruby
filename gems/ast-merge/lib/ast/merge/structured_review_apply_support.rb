# frozen_string_literal: true

module Ast
  module Merge
    module StructuredReviewApplySupport
      protected

      def apply_non_provisional_unresolved_resolution!(resolution_case, selection:, selected_candidate:)
        output_span = current_output_span_for(resolution_case)
        return super unless output_span

        start_index, end_index = output_span
        @lines[start_index..end_index] = replacement_line_entries_for(
          resolution_case,
          selection: selection,
          selected_candidate: selected_candidate
        )
      end

      private

      def current_output_span_for(resolution_case)
        source = source_for_selection(resolution_case.provisional_winner)
        source_span = source_line_span_for(resolution_case, resolution_case.provisional_winner)
        return unless source_span

        matching_indexes = @lines.each_index.select do |index|
          line = @lines[index]
          line[:source] == source &&
            line[:original_line] &&
            line[:original_line] >= source_span[0] &&
            line[:original_line] <= source_span[1]
        end
        return if matching_indexes.empty?

        expected_indexes = (matching_indexes.first..matching_indexes.last).to_a
        return unless matching_indexes == expected_indexes

        [matching_indexes.first, matching_indexes.last]
      end

      def replacement_line_entries_for(resolution_case, selection:, selected_candidate:)
        source = source_for_selection(selection)
        source_span = source_line_span_for(resolution_case, selection)
        lines = selected_candidate.to_s.lines(chomp: true)
        lines = [selected_candidate.to_s] if lines.empty?

        lines.each_with_index.map do |line, idx|
          {
            content: line,
            decision: decision_for_selection(selection),
            source: source,
            original_line: source_span ? source_span[0] + idx : nil
          }
        end
      end

      def source_line_span_for(resolution_case, selection)
        span = Array(
          selection.to_sym == :template ? resolution_case.metadata[:template_lines] : resolution_case.metadata[:destination_lines]
        )
        return unless span.length == 2

        [span[0].to_i, span[1].to_i]
      end

      def source_for_selection(selection)
        selection.to_sym == :template ? :template : :destination
      end

      def decision_for_selection(selection)
        if selection.to_sym == :template
          self.class.const_get(:DECISION_KEPT_TEMPLATE)
        else
          self.class.const_get(:DECISION_KEPT_DEST)
        end
      end
    end
  end
end
