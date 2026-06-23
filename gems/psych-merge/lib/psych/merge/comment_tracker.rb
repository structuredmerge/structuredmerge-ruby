# frozen_string_literal: true

module Psych
  module Merge
    # Extracts and tracks comments with their line numbers from YAML source.
    # YAML comments use the same # syntax as Ruby, making freeze block detection
    # straightforward.
    #
    # Inherits shared lookup, query, region-building, and attachment API from
    # +Ast::Merge::Comment::HashTrackerBase+. Only format-specific comment
    # extraction and owner resolution are overridden here.
    #
    # @example Basic usage
    #   tracker = CommentTracker.new(yaml_source)
    #   tracker.comments # => [{line: 1, indent: 0, text: "This is a comment"}]
    #   tracker.comment_at(1) # => {line: 1, indent: 0, text: "This is a comment"}
    #
    # @example Comment types
    #   # Full-line comment
    #   key: value # Inline comment
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      # Initialize comment tracker by scanning the source
      #
      # @param source [String] YAML source code
      def initialize(source)
        @source = source
        @line_parser = Ast::Merge::Comment::QuotedHashLineParser.new
        super(source.lines.map(&:chomp))
      end

      private

      def extract_comments
        comments = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
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
              indent: parsed.column,
              text: parsed.text,
              full_line: false,
              raw: parsed.raw
            }
          end
        end

        comments
      end

      def owner_line_num(owner)
        return owner.start_line if owner.respond_to?(:start_line) && owner.start_line
        if owner.respond_to?(:key) && owner.key&.respond_to?(:start_line) && owner.key.start_line
          return owner.key.start_line
        end

        nil
      end
    end
  end
end
