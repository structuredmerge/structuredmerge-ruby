# frozen_string_literal: true

module Prism
  module Merge
    class NodeBodyLayout
      attr_reader :node, :analysis, :merger

      def initialize(node:, analysis:, merger:)
        @node = node
        @analysis = analysis
        @merger = merger
      end

      def body_text
        return '' unless body_present?

        lines = []
        lines << opening_line_body_text if body_starts_on_opening_line?

        middle_body_line_range.each do |line_num|
          lines << analysis.line_at(line_num).to_s.chomp
        end

        lines << closing_line_body_text if body_ends_on_closing_line?

        return '' if lines.empty?

        "#{lines.join("\n")}\n"
      end

      def opening_line_text
        return analysis.line_at(node.location.start_line).to_s.chomp unless body_starts_on_opening_line?

        analysis.source.byteslice(line_start_offset(node.location.start_line)...body_start_offset).to_s
      end

      def closing_line_text
        return analysis.line_at(node.location.end_line).to_s.chomp unless body_ends_on_closing_line?

        analysis.source.byteslice(body_end_offset...line_end_offset(node.location.end_line)).to_s.chomp
      end

      def body_starts_on_opening_line?
        body_present? && body_statements.first.location.start_line == node.location.start_line
      end

      def body_ends_on_closing_line?
        body_present? && body_statements.last.location.end_line == node.location.end_line
      end

      def source_line_for_body_line(body_line)
        return unless body_line

        body_source_lines[body_line - 1]
      end

      private

      def body_source_lines
        return [] unless body_present?

        lines = []
        lines << node.location.start_line if body_starts_on_opening_line?
        middle_body_line_range.each { |line_num| lines << line_num }
        lines << node.location.end_line if body_ends_on_closing_line?
        lines
      end

      def body_present?
        statements_node&.type.to_s == 'statements_node' && body_statements.any?
      end

      def statements_node
        @statements_node ||= case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
                             when :class, :module, :singleton_class, :lambda
                               node.body
                             when :if, :unless, :while, :until, :for
                               node.statements
                             when :call
                               node.block&.body
                             when :begin
                               node.statements
                             when :parens
                               node.body
                             else
                               if node.respond_to?(:body)
                                 node.body
                               elsif node.respond_to?(:statements)
                                 node.statements
                               elsif node.respond_to?(:block) && node.block
                                 node.block.body
                               end
                             end
      end

      def body_statements
        @body_statements ||= statements_node&.body || []
      end

      def body_start_line
        @body_start_line ||= case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
                             when :call
                               node.block.opening_loc ? node.block.opening_loc.start_line + 1 : body_statements.first.location.start_line
                             when :class, :module, :singleton_class
                               node.location.start_line + 1
                             else
                               body_statements.first.location.start_line
                             end
      end

      def body_end_line
        @body_end_line ||= case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
                           when :call
                             node.block.closing_loc ? node.block.closing_loc.start_line - 1 : body_statements.last.location.end_line
                           when :class, :module, :singleton_class
                             node.end_keyword_loc ? node.end_keyword_loc.start_line - 1 : body_statements.last.location.end_line
                           when :begin
                             clause_start_line = merger.send(:begin_node_clause_start_line, node)
                             clause_start_line ? clause_start_line - 1 : body_statements.last.location.end_line
                           else
                             body_statements.last.location.end_line
                           end
      end

      def body_start_offset
        body_statements.first.location.start_offset
      end

      def body_end_offset
        body_statements.last.location.end_offset
      end

      def opening_line_body_text
        analysis.source.byteslice(body_start_offset...line_end_offset(node.location.start_line)).to_s.chomp
      end

      def closing_line_body_text
        analysis.source.byteslice(line_start_offset(node.location.end_line)...body_end_offset).to_s.chomp
      end

      def middle_body_line_range
        start_line = body_starts_on_opening_line? ? node.location.start_line + 1 : body_start_line
        end_line = body_ends_on_closing_line? ? node.location.end_line - 1 : body_end_line
        return [] if end_line < start_line

        (start_line..end_line)
      end

      def line_start_offset(line_num)
        @line_start_offsets ||= begin
          offset = 0
          analysis.lines.map do |line|
            current_offset = offset
            offset += line.bytesize
            current_offset
          end
        end

        @line_start_offsets.fetch(line_num - 1, analysis.source.bytesize)
      end

      def line_end_offset(line_num)
        line_start_offset(line_num) + analysis.line_at(line_num).to_s.bytesize
      end
    end
  end
end
