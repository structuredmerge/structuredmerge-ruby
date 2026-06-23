# frozen_string_literal: true

module Markdown
  module Merge
    # Conservatively tracks standalone HTML comment lines in Markdown sources.
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      STANDALONE_HTML_COMMENT_REGEX = /\A(?<indent>\s*)<!--\s?(?<text>.*?)\s?-->\s*\z/

      def initialize(lines)
        super(Array(lines))
      end

      private

      def comment_style
        :html_comment
      end

      def extract_comments
        @lines.each_with_index.filter_map do |line, index|
          match = line.match(STANDALONE_HTML_COMMENT_REGEX)
          next unless match

          {
            line: index + 1,
            indent: match[:indent].length,
            text: match[:text].to_s,
            full_line: true,
            raw: line
          }
        end
      end

      def owner_line_num(owner)
        pos = owner.respond_to?(:source_position) ? owner.source_position : nil
        return pos[:start_line] if pos && pos[:start_line]

        nil
      end
    end
  end
end
