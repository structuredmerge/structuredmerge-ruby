# frozen_string_literal: true

module Ast
  module Merge
    module StructuredEmitterProvenanceSupport
      private

      def transfer_emitter_output(result)
        return if @emitter.lines.empty?

        @emitter.lines.each_with_index do |line, idx|
          metadata = @emitter.line_metadata[idx].to_h
          result.add_line(
            line.chomp,
            decision: result.class::DECISION_MERGED,
            source: metadata[:source] || :merged,
            original_line: metadata[:original_line]
          )
        end
      end

      def emitter_line_metadata(analysis, line_number:)
        {
          source: emitter_source(analysis),
          original_line: line_number
        }.compact
      end

      def emitter_block_metadata(analysis, start_line)
        {
          source: emitter_source(analysis),
          original_line_start: start_line
        }.compact
      end

      def emitter_source(analysis)
        return :template if analysis.equal?(@template_analysis)
        return :destination if analysis.equal?(@dest_analysis)

        :merged
      end
    end
  end
end
