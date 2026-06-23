# frozen_string_literal: true

module Prism
  module Merge
    # Represents the merged output with bidirectional links to source lines.
    # Tracks merge decisions and provenance for validation and debugging.
    #
    # Inherits decision constants and base functionality from Ast::Merge::MergeResultBase.
    class MergeResult < Ast::Merge::MergeResultBase
      include Prism::Merge::SourceLineLookup

      # Inherit decision constants from base class
      DECISION_KEPT_TEMPLATE = Ast::Merge::MergeResultBase::DECISION_KEPT_TEMPLATE
      DECISION_KEPT_DEST = Ast::Merge::MergeResultBase::DECISION_KEPT_DEST
      DECISION_APPENDED = Ast::Merge::MergeResultBase::DECISION_APPENDED
      DECISION_REPLACED = Ast::Merge::MergeResultBase::DECISION_REPLACED
      DECISION_FREEZE_BLOCK = Ast::Merge::MergeResultBase::DECISION_FREEZE_BLOCK

      attr_reader :line_metadata

      # @param options [Hash] Additional options for forward compatibility
      def initialize(**options)
        super(**options)
        @line_metadata = []
      end

      # Add a line to the result
      # @param content [String] Line content (without newline)
      # @param decision [Symbol] How this line was decided
      # @param template_line [Integer, nil] 1-based line number from template
      # @param dest_line [Integer, nil] 1-based line number from destination
      # @param comment [String, nil] Optional note about this decision
      def add_line(content, decision:, template_line: nil, dest_line: nil, comment: nil)
        @lines << content
        @line_metadata << {
          decision: decision,
          template_line: template_line,
          dest_line: dest_line,
          comment: comment,
          result_line: @lines.length
        }
        track_decision(decision, template_line ? :template : :destination, line: template_line || dest_line)
      end

      # Add multiple lines from a source with same decision
      # @param source_lines [Array<String>] Lines to add
      # @param decision [Symbol] Merge decision
      # @param source [Symbol] :template or :destination
      # @param start_line [Integer] Starting line number in source
      # @param comment [String, nil] Optional note
      def add_lines_from(source_lines, decision:, source:, start_line:, comment: nil)
        source_lines.each_with_index do |line, idx|
          line_num = start_line + idx
          if source == :template
            add_line(line, decision: decision, template_line: line_num, comment: comment)
          else
            add_line(line, decision: decision, dest_line: line_num, comment: comment)
          end
        end
      end

      # Add a node's content with its comments
      # @param node_info [Hash] Node information from FileAnalysis
      # @param decision [Symbol] Merge decision
      # @param source [Symbol] :template or :destination
      # @param source_analysis [FileAnalysis] Source file analysis for preserving indentation
      def add_node(node_info, decision:, source:, source_analysis: nil)
        node = node_info[:node]
        start_line = node.location.start_line
        end_line = node.location.end_line

        # Add leading comments with blank lines between them preserved
        prev_comment_line = nil
        node_info[:leading_comments].each do |comment|
          comment_line = comment.location.start_line

          # Add blank lines between this comment and the previous one
          if prev_comment_line && comment_line > prev_comment_line + 1
            ((prev_comment_line + 1)...comment_line).each do |blank_line_num|
              line = if source_analysis
                       required_source_line(
                         source_analysis,
                         blank_line_num,
                         context: 'emitting preserved blank line between leading comments'
                       )
                     else
                       ''
                     end
              if source == :template
                add_line(line, decision: decision, template_line: blank_line_num)
              else
                add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end

          # Use source_analysis to get full line with indentation if available
          line = if source_analysis
                   required_comment_line(
                     source_analysis,
                     comment,
                     context: 'emitting leading comment from analyzed source'
                   )
                 else
                   comment.slice.chomp
                 end
          if source == :template
            add_line(line, decision: decision, template_line: comment_line)
          else
            add_line(line, decision: decision, dest_line: comment_line)
          end

          prev_comment_line = comment_line
        end

        # Add blank lines between last comment and node if needed
        if node_info[:leading_comments].any?
          last_comment_line = node_info[:leading_comments].last.location.start_line
          if start_line > last_comment_line + 1
            ((last_comment_line + 1)...start_line).each do |blank_line_num|
              line = if source_analysis
                       required_source_line(
                         source_analysis,
                         blank_line_num,
                         context: 'emitting preserved blank line before node body'
                       )
                     else
                       ''
                     end
              if source == :template
                add_line(line, decision: decision, template_line: blank_line_num)
              else
                add_line(line, decision: decision, dest_line: blank_line_num)
              end
            end
          end
        end

        # Add node source lines
        # Use source_analysis.line_at to preserve original indentation
        if source_analysis
          # Get full lines from source to preserve indentation
          # Note: inline comments are already part of the source line from line_at(),
          # so we don't need to append them separately. The inline_comments in node_info
          # are just metadata about comments that were attached to the node by Prism.
          (start_line..end_line).each do |line_num|
            line = required_source_line(
              source_analysis,
              line_num,
              context: 'emitting analyzed node source line'
            )

            if source == :template
              add_line(line, decision: decision, template_line: line_num)
            else
              add_line(line, decision: decision, dest_line: line_num)
            end
          end
        else
          # Analysis-free emission path: use node.slice when no source analysis
          # object is available. This is an alternate input mode, not cleanup.
          node_source = node.slice
          node_lines = node_source.lines(chomp: true)

          # Handle inline comments
          inline_comments = node_info[:inline_comments]
          if inline_comments.any?
            # Inline comments are on the last line
            last_idx = node_lines.length - 1
            if last_idx >= 0
              # Analysis-free mode only has node.slice, which excludes the original
              # pre-comment separator. Reattach inline comments with a canonical
              # single space instead of pretending to preserve unavailable spacing.
              inline_text = inline_comments.map { |c| c.slice.strip }.join(' ')
              node_lines[last_idx] = node_lines[last_idx] + ' ' + inline_text
            end
          end

          node_lines.each_with_index do |line, idx|
            line_num = start_line + idx
            if source == :template
              add_line(line, decision: decision, template_line: line_num)
            else
              add_line(line, decision: decision, dest_line: line_num)
            end
          end
        end
      end

      # Convert to final merged content string
      # @return [String]
      def to_s
        @lines.join("\n") + "\n"
      end

      # Get statistics about merge decisions
      # @return [Hash<Symbol, Integer>]
      def statistics
        stats = Hash.new(0)
        @line_metadata.each do |meta|
          stats[meta[:decision]] += 1
        end
        stats
      end

      def decision_summary
        statistics
      end

      # Get lines by decision type
      # @param decision [Symbol] Decision type to filter by
      # @return [Array<Hash>] Metadata for matching lines
      def lines_by_decision(decision)
        @line_metadata.select { |meta| meta[:decision] == decision }
      end

      # Debug output showing merge provenance
      # @return [String]
      def debug_output
        output = ['=== Merge Result Debug ===']
        output << "Total lines: #{@lines.length}"
        output << "Statistics: #{statistics.inspect}"
        output << ''
        output << 'Line-by-line provenance:'

        @lines.each_with_index do |line, idx|
          meta = @line_metadata[idx]
          parts = [
            "#{idx + 1}:".rjust(4),
            meta[:decision].to_s.ljust(20)
          ]

          parts << if meta[:template_line]
                     "T:#{meta[:template_line]}".ljust(8)
                   else
                     ' ' * 8
                   end

          parts << if meta[:dest_line]
                     "D:#{meta[:dest_line]}".ljust(8)
                   else
                     ' ' * 8
                   end

          parts << "| #{line[0..60]}"
          output << parts.join(' ')
        end

        output.join("\n")
      end

      protected

      def apply_non_provisional_unresolved_resolution!(resolution_case, selection:, selected_candidate:)
        result_line_span = normalize_result_line_span(resolution_case.metadata[:result_lines])
        return super unless result_line_span

        replace_result_line_span!(
          result_line_span: result_line_span,
          selection: selection,
          selected_lines: unresolved_candidate_lines(selected_candidate),
          resolution_case: resolution_case
        )
      end

      private

      def normalize_result_line_span(value)
        span = Array(value)
        return unless span.length == 2

        start_line, end_line = span.map(&:to_i)
        return unless start_line >= 1 && end_line >= start_line && end_line <= @lines.length

        [start_line, end_line]
      end

      def unresolved_candidate_lines(candidate)
        lines = candidate.to_s.split("\n", -1)
        lines.empty? ? [''] : lines
      end

      def replace_result_line_span!(result_line_span:, selection:, selected_lines:, resolution_case:)
        start_line, end_line = result_line_span
        replacement_metadata = build_replacement_metadata(
          selection: selection,
          selected_lines: selected_lines,
          resolution_case: resolution_case
        )

        @lines[(start_line - 1)..(end_line - 1)] = selected_lines
        @line_metadata[(start_line - 1)..(end_line - 1)] = replacement_metadata
        reindex_result_lines!(start_line - 1)
      end

      def build_replacement_metadata(selection:, selected_lines:, resolution_case:)
        decision =
          case selection
          when :template then DECISION_KEPT_TEMPLATE
          when :destination then DECISION_KEPT_DEST
          else selection
          end
        source_line_key = selection == :template ? :template_line : :dest_line
        source_line_numbers = unresolved_source_line_numbers_for(selection, selected_lines.length,
                                                                 resolution_case.metadata)

        selected_lines.each_index.map do |index|
          {
            decision: decision,
            template_line: source_line_key == :template_line ? source_line_numbers[index] : nil,
            dest_line: source_line_key == :dest_line ? source_line_numbers[index] : nil,
            comment: nil,
            result_line: nil
          }
        end
      end

      def unresolved_source_line_numbers_for(selection, line_count, metadata)
        source_lines = Array(metadata[selection == :template ? :template_lines : :destination_lines])
        return Array.new(line_count) unless source_lines.length == 2

        start_line, end_line = source_lines.map(&:to_i)
        available = end_line >= start_line ? (start_line..end_line).to_a : []
        return available.take(line_count) if available.length >= line_count

        available + Array.new(line_count - available.length)
      end

      def reindex_result_lines!(start_index)
        @line_metadata[start_index..]&.each_with_index do |metadata, offset|
          metadata[:result_line] = start_index + offset + 1
        end
      end
    end
  end
end
