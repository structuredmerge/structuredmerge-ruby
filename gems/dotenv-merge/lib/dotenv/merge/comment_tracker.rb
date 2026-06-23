# frozen_string_literal: true

module Dotenv
  module Merge
    # Extracts and tracks dotenv comments with their line numbers from source.
    #
    # Inherits shared lookup, query, region-building, and attachment API from
    # +Ast::Merge::Comment::HashTrackerBase+. Only format-specific comment
    # extraction and owner resolution are overridden here.
    #
    # Dotenv supports hash-style comments as either:
    # - full-line comments (`# comment`)
    # - safe inline comments on unquoted assignments (`KEY=value # comment`)
    #
    # This adapter intentionally stays conservative around quoted values. `#`
    # inside quoted values is not treated as a comment, and quoted assignments
    # with trailing comment-like text remain literal value content. That is a
    # deliberate parser boundary for dotenv-merge, not a pending comment-matrix
    # bug to "fix" later without an explicit product decision.
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      def initialize(source_or_lines)
        @line_objects = normalize_line_objects(source_or_lines)
        @line_parser = Ast::Merge::Comment::QuotedHashLineParser.new
        super(@line_objects.map(&:raw))
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

      def normalize_line_objects(source_or_lines)
        case source_or_lines
        when String
          source_or_lines.lines.each_with_index.map do |line, index|
            EnvLine.new(line.chomp, index + 1)
          end
        else
          Array(source_or_lines)
        end
      end

      def extract_comments
        @line_objects.filter_map do |line|
          if line.comment?
            build_full_line_comment(line)
          elsif line.assignment?
            build_inline_comment(line)
          end
        end
      end

      def build_full_line_comment(line)
        match = line.raw.match(FULL_LINE_COMMENT_REGEX)
        return unless match

        {
          line: line.line_number,
          indent: match[:indent].length,
          text: match[:text].to_s,
          full_line: true,
          raw: line.raw
        }
      end

      def build_inline_comment(line)
        value_part = raw_value_part(line)
        return if value_part.nil?

        stripped_value = value_part.lstrip
        return if stripped_value.start_with?('"', "'")

        parsed = @line_parser.parse(value_part)
        return unless parsed&.inline?

        {
          line: line.line_number,
          indent: leading_indent(line.raw),
          text: parsed.text,
          full_line: false,
          raw: parsed.raw
        }
      end

      def raw_value_part(line)
        raw = line.raw.sub(/\A\s*export\s+/, '')
        _key_part, value_part = raw.split('=', 2)
        value_part
      end

      def leading_indent(raw)
        raw[/\A\s*/].to_s.length
      end

      def owner_line_num(owner)
        return owner.start_line if owner.respond_to?(:start_line) && owner.start_line
        return owner.line_number if owner.respond_to?(:line_number)

        nil
      end
    end
  end
end
