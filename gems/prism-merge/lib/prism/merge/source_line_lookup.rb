# frozen_string_literal: true

module Prism
  module Merge
    module SourceLineLookup
      private

      # A present analysis object implies access to the original source line buffer.
      # If line_at returns nil for a line referenced by a node/comment from that same
      # analysis, the merge pipeline has violated an ownership/analysis invariant.
      def required_source_line(analysis, line_num, context:)
        line = analysis.line_at(line_num)
        return line.chomp if line

        raise Prism::Merge::MissingAnalyzedLineError,
              "#{context}: expected #{analysis.class}#line_at(#{line_num}) to return a source line, " \
                'but it returned nil. This path requires an analysis object that matches the AST/comment ownership.'
      end

      def required_comment_line(analysis, comment, context:)
        required_source_line(analysis, comment.location.start_line, context: context)
      end
    end
  end
end
