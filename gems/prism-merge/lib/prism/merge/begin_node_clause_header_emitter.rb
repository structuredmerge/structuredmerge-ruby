# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodeClauseHeaderEmitter
      include Prism::Merge::SourceLineLookup

      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def emit(template_clause_node:, template_region:, dest_clause_node:, dest_region:, header_source:, decision:,
               template_inline_by_line:, dest_inline_by_line:)
        header_node = header_source == :template ? template_clause_node : dest_clause_node
        header_region = header_source == :template ? template_region : dest_region
        header_analysis = header_source == :template ? merger.template_analysis : merger.dest_analysis
        header_end_line = merger.send(:clause_header_end_line, header_node, header_region)
        template_header_end_line = merger.send(:clause_header_end_line, template_clause_node, template_region)
        dest_header_end_line = merger.send(:clause_header_end_line, dest_clause_node, dest_region)

        (header_region[:start_line]..header_end_line).each do |line_num|
          line = required_source_line(
            header_analysis,
            line_num,
            context: 'emitting begin-clause header line'
          )

          if header_source == :template &&
             line_num == template_header_end_line &&
             template_inline_by_line[line_num].empty?
            dest_clause_inline = dest_inline_by_line[dest_header_end_line]
            line = merger.send(:append_inline_comment_entries, line, dest_clause_inline) if dest_clause_inline.any?
          end

          merger.result.add_line(
            line,
            decision: decision,
            template_line: header_source == :template ? line_num : nil,
            dest_line: header_source == :destination ? line_num : nil
          )
        end
      end
    end
  end
end
