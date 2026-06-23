# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodePlanEmitter
      include Prism::Merge::SourceLineLookup

      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def emit(template_node:, dest_node:, node_preference:, decision:, template_inline_by_line:, dest_inline_by_line:)
        begin_clause_line_map = merger.send(:begin_node_clause_line_map, template_node, dest_node)

        merger.send(
          :begin_node_merge_planner,
          template_node: template_node,
          dest_node: dest_node,
          node_preference: node_preference
        ).plan.each do |step|
          emit_step(
            step,
            node_preference: node_preference,
            decision: decision,
            template_inline_by_line: template_inline_by_line,
            dest_inline_by_line: dest_inline_by_line,
            begin_clause_line_map: begin_clause_line_map
          )
        end
      end

      private

      def emit_step(step, node_preference:, decision:, template_inline_by_line:, dest_inline_by_line:,
                    begin_clause_line_map:)
        case step.kind
        when :merged_shared_clause, :fallback_shared_clause
          merger.send(:begin_node_clause_header_emitter).emit(
            template_clause_node: step.template_clause_node,
            template_region: step.template_region,
            dest_clause_node: step.dest_clause_node,
            dest_region: step.dest_region,
            header_source: step.header_source,
            decision: decision,
            template_inline_by_line: template_inline_by_line,
            dest_inline_by_line: dest_inline_by_line
          )

          emit_text(step.body_text, decision: decision)
          emit_text(step.trailing_suffix_text, decision: decision)
        when :copied_unmatched_clause
          emit_copied_unmatched_clause(
            step,
            node_preference: node_preference,
            decision: decision,
            template_inline_by_line: template_inline_by_line,
            dest_inline_by_line: dest_inline_by_line,
            begin_clause_line_map: begin_clause_line_map
          )
        end
      end

      def emit_text(text, decision:)
        text.to_s.lines.each do |line|
          merger.result.add_line(
            line.chomp,
            decision: decision,
            template_line: nil,
            dest_line: nil
          )
        end
      end

      def emit_copied_unmatched_clause(step, node_preference:, decision:, template_inline_by_line:,
                                       dest_inline_by_line:, begin_clause_line_map:)
        region_analysis = step.copied_analysis_side == :template ? merger.template_analysis : merger.dest_analysis

        (step.copied_region[:start_line]..step.copied_region[:end_line]).each do |line_num|
          line = required_source_line(
            region_analysis,
            line_num,
            context: 'emitting copied unmatched begin-clause region'
          )

          if node_preference == :template &&
             region_analysis.equal?(merger.template_analysis) &&
             template_inline_by_line[line_num].empty?
            dest_clause_line = begin_clause_line_map[line_num]
            dest_clause_inline = dest_clause_line ? dest_inline_by_line[dest_clause_line] : []
            line = merger.send(:append_inline_comment_entries, line, dest_clause_inline) if dest_clause_inline.any?
          end

          merger.result.add_line(
            line,
            decision: decision,
            template_line: region_analysis.equal?(merger.template_analysis) ? line_num : nil,
            dest_line: region_analysis.equal?(merger.dest_analysis) ? line_num : nil
          )
        end
      end
    end
  end
end
