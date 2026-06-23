# frozen_string_literal: true

module Bash
  module Merge
    # Extracts and tracks comments with their line numbers from Bash source.
    # Bash comments use the # syntax, making freeze block detection straightforward.
    #
    # Inherits shared lookup, query, region-building, and attachment API from
    # +Ast::Merge::Comment::HashTrackerBase+. Only format-specific comment
    # extraction, shebang detection, and owner resolution are overridden here.
    #
    # @example Basic usage
    #   tracker = CommentTracker.new(bash_source)
    #   tracker.comments # => [{line: 1, indent: 0, text: "This is a comment"}]
    #   tracker.comment_at(1) # => {line: 1, indent: 0, text: "This is a comment"}
    #
    # @example Comment types
    #   # Full-line comment
    #   command # Inline comment
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      # Initialize comment tracker by scanning the source
      #
      # @param source [String] Bash source code
      def initialize(source)
        @source = source
        @line_parser = Ast::Merge::Comment::QuotedHashLineParser.new
        super(source.lines.map(&:chomp))
      end

      # Check if a line is a shebang
      #
      # @param line_num [Integer] 1-based line number
      # @return [Boolean]
      def shebang?(line_num)
        return false if line_num < 1 || line_num > @lines.length

        @lines[line_num - 1].start_with?('#!')
      end

      def augment(owners: [], **options)
        Ast::Merge::Comment::Augmenter.new(
          lines: @lines,
          comments: @comments,
          owners: owners,
          style: :hash_comment,
          total_comment_count: @comments.size,
          inline_comment_count: @comments.count { |comment| !comment[:full_line] },
          **options
        )
      end

      private

      def extract_comments
        comments = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1

          # Skip shebang lines
          next if line.start_with?('#!')

          parsed = @line_parser.parse(line)
          next unless parsed

          if parsed.full_line?
            comments << {
              line: line_num,
              indent: parsed.indent,
              text: parsed.text,
              full_line: true,
              raw: parsed.raw
            }
          elsif parsed.inline?
            comments << {
              line: line_num,
              indent: 0,
              text: parsed.text,
              full_line: false,
              raw: parsed.raw
            }
          end
        end

        comments
      end
    end
  end
end
