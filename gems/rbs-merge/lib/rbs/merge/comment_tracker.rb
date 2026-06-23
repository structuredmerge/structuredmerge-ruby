# frozen_string_literal: true

module Rbs
  module Merge
    # Tracks hash-style comments in RBS source and exposes a shared comment API.
    #
    # Inherits shared lookup, query, region-building, and attachment API from
    # +Ast::Merge::Comment::HashTrackerBase+. Only format-specific comment
    # extraction and owner resolution are overridden here.
    #
    # RBS has only full-line comments for the declarations this adapter models;
    # inline hash-comment scenarios from the shared comment matrix do not exist
    # in the language surface here. Treat those skipped matrix cases as syntax
    # limits, not pending merge-engine work. Freeze marker lines are excluded
    # from the tracked set.
    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      DEFAULT_FREEZE_TOKEN = 'rbs-merge'

      def initialize(lines, freeze_token: DEFAULT_FREEZE_TOKEN)
        @freeze_token = freeze_token
        @freeze_marker_pattern = Ast::Merge::FreezeNodeBase.pattern_for(:hash_comment, @freeze_token)
        super(Array(lines))
      end

      # RBS format has no inline comment attachment here — override to always
      # return nil. This is intentional syntax modeling, not missing feature
      # work for the shared comment matrix.
      def comment_attachment_for(owner, line_num: nil, **metadata)
        resolved_line_num = line_num || owner_line_num(owner)
        resolved_end_line = owner_end_line(owner) || resolved_line_num
        leading_region = resolved_line_num ? leading_comment_region_before(resolved_line_num) : nil
        trailing_region = resolved_end_line ? trailing_comment_region_after(resolved_end_line) : nil

        Ast::Merge::Comment::Attachment.new(
          owner: owner,
          leading_region: leading_region,
          inline_region: nil,
          trailing_region: trailing_region,
          metadata: metadata.merge(
            line_num: resolved_line_num,
            end_line: resolved_end_line,
            source: :comment_tracker
          )
        )
      end

      def augment(owners: [], **options)
        Ast::Merge::Comment::Augmenter.new(
          lines: @lines,
          comments: @comments,
          owners: owners,
          style: :hash_comment,
          total_comment_count: @comments.size,
          **options
        )
      end

      private

      def extract_comments
        @lines.each_with_index.filter_map do |line, index|
          next if freeze_marker_comment?(line)

          match = line.match(FULL_LINE_COMMENT_REGEX)
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

      def freeze_marker_comment?(line)
        return false unless line

        !!line.match(@freeze_marker_pattern)
      end
    end
  end
end
