# frozen_string_literal: true

module Yaml
  module Merge
    class MergeResult < Ast::Merge::MergeResultBase
      DECISION_KEPT_TEMPLATE = Ast::Merge::MergeResultBase::DECISION_KEPT_TEMPLATE
      DECISION_KEPT_DEST = Ast::Merge::MergeResultBase::DECISION_KEPT_DEST
      DECISION_MERGED = Ast::Merge::MergeResultBase::DECISION_MERGED
      DECISION_ADDED = Ast::Merge::MergeResultBase::DECISION_ADDED
      DECISION_FREEZE_BLOCK = Ast::Merge::MergeResultBase::DECISION_FREEZE_BLOCK

      attr_reader :statistics

      def initialize(**options)
        super(**options)
        @statistics = {
          template_lines: 0,
          dest_lines: 0,
          merged_lines: 0,
          freeze_preserved_lines: 0,
          total_decisions: 0
        }
      end

      def add_line(line, decision:, source:, original_line: nil)
        @lines << {
          content: line,
          decision: decision,
          source: source,
          original_line: original_line
        }
        track_statistics(decision)
        track_decision(decision, source, line: original_line)
      end

      def to_yaml
        content = @lines.map { |line| line[:content] }.join("\n")
        content += "\n" unless content.empty? || content.end_with?("\n")
        content
      end

      alias content to_yaml
      alias to_s to_yaml

      def line_count
        @lines.size
      end

      private

      def track_statistics(decision)
        @statistics[:total_decisions] += 1
        case decision
        when DECISION_KEPT_TEMPLATE
          @statistics[:template_lines] += 1
        when DECISION_KEPT_DEST
          @statistics[:dest_lines] += 1
        when DECISION_FREEZE_BLOCK
          @statistics[:freeze_preserved_lines] += 1
        else
          @statistics[:merged_lines] += 1
        end
      end
    end
  end
end
