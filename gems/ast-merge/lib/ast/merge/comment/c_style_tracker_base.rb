# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Shared base class for C-style comment trackers across the merge family.
      #
      # This base owns reusable `//` + `/* */` scanning, span-aware lookup for
      # multi-line block comments, shared line-comment region/attachment building,
      # and augmenter integration. It intentionally keeps the current shared
      # tracked-hash adapter boundary: block comments are tracked and queryable,
      # but shared nodes/regions/attachments still expose only line-style comments
      # until a broader block-comment normalization layer exists.
      #
      # Subclasses may override:
      # - {#owner_line_num} for format-specific owner resolution
      # - {#inline_comment_candidate?} for syntax-specific inline-comment heuristics
      #
      # The tracked-comment hash shape extends the tracked-hash adapter input with
      # C-style facts such as `:block` and optional `:end_line` for multi-line
      # block spans.
      class CStyleTrackerBase
        # Matches a full-line single-line C-style comment.
        #
        # @return [Regexp]
        SINGLE_LINE_COMMENT_REGEX = %r{\A(?<indent>\s*)//\s?(?<text>.*)\z}
        # Matches a full-line block comment contained on one line.
        #
        # @return [Regexp]
        BLOCK_COMMENT_SINGLE_REGEX = %r{\A(?<indent>\s*)/\*\s?(?<text>.*?)\s?\*/\s*\z}

        attr_reader :comments, :lines

        # @param lines [Array<String>] Source lines (already chomped/split)
        def initialize(lines)
          @lines = Array(lines)
          @comments = extract_comments
          @comments_by_line = build_comments_by_line(@comments)
        end

        # ----------------------------------------------------------------
        # Single-comment lookup
        # ----------------------------------------------------------------

        def comment_at(line_num)
          @comments_by_line[line_num]&.first
        end

        # Return all normalized shared comment nodes eligible for region building.
        #
        # @return [Array<Comment::Line>]
        def comment_nodes
          @comment_nodes ||= shared_region_comments.map { |comment| build_comment_node(comment) }
        end

        # Return the normalized shared comment node at a line.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Comment::Line, nil]
        def comment_node_at(line_num)
          comment = comment_at(line_num)
          return unless comment && shared_region_comment?(comment)

          build_comment_node(comment)
        end

        # ----------------------------------------------------------------
        # Range queries
        # ----------------------------------------------------------------

        def comments_in_range(range)
          @comments.select do |comment|
            range.begin <= comment_end_line(comment) && range.end >= comment_start_line(comment)
          end
        end

        # Build a normalized region from comments intersecting a line range.
        #
        # @param range [Range] 1-based line range
        # @param kind [Symbol] region ownership kind
        # @param full_line_only [Boolean] whether to keep only full-line comments
        # @return [Region]
        def comment_region_for_range(range, kind:, full_line_only: false)
          selected = comments_in_range(range).select { |comment| shared_region_comment?(comment) }
          selected = selected.select { |comment| comment[:full_line] } if full_line_only

          build_region(
            kind: kind,
            comments: selected,
            metadata: {
              range: range,
              full_line_only: full_line_only,
              source: :comment_tracker
            }
          )
        end

        # ----------------------------------------------------------------
        # Leading / inline comment helpers
        # ----------------------------------------------------------------

        def leading_comments_before(line_num)
          leading = []
          current = line_num - 1
          current -= 1 while current >= 1 && blank_line?(current)

          while current >= 1
            comment = comment_at(current)
            break unless comment && comment[:full_line]

            leading.unshift(comment)
            current = comment_start_line(comment) - 1
            current -= 1 while current >= 1 && blank_line?(current)
          end

          leading
        end

        # Return the normalized leading comment region before a line.
        #
        # @param line_num [Integer] owner line number
        # @param comments [Array<Hash>, nil] optional preselected comments
        # @return [Region, nil]
        def leading_comment_region_before(line_num, comments: nil)
          selected = comments || leading_comments_before(line_num)
          selected = selected.select { |comment| comment[:full_line] && shared_region_comment?(comment) }
          return if selected.empty?

          build_region(
            kind: :leading,
            comments: selected,
            metadata: {
              line_num: line_num,
              source: :comment_tracker
            }
          )
        end

        # Return the inline comment tracked on a line.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Hash, nil]
        def inline_comment_at(line_num)
          comment = comment_at(line_num)
          comment if comment && !comment[:full_line]
        end

        # Return the normalized inline region for a single line.
        #
        # @param line_num [Integer] 1-based line number
        # @param comment [Hash, nil] optional preselected inline comment
        # @return [Region, nil]
        def inline_comment_region_at(line_num, comment: nil)
          selected = [comment || inline_comment_at(line_num)].compact.select { |item| shared_region_comment?(item) }
          return if selected.empty?

          build_region(
            kind: :inline,
            comments: selected,
            metadata: {
              line_num: line_num,
              source: :comment_tracker
            }
          )
        end

        # Return adjacent full-line trailing line comments after an owner span.
        #
        # The first trailing comment must begin immediately after the owner.
        # Blank lines are only preserved between later trailing comments, not
        # between the owner and the first trailing comment.
        #
        # @param line_num [Integer] 1-based end line of the owner
        # @param upper_bound [Integer, nil] exclusive upper bound before the next owner
        # @return [Array<Hash>]
        def trailing_comments_after(line_num, upper_bound: nil, owner: nil)
          trailing = []
          current = line_num + 1
          max_line = upper_bound ? upper_bound - 1 : @lines.length
          return trailing if current > max_line || blank_line?(current)

          while current <= max_line
            comment = comment_at(current)
            break unless comment && comment[:full_line] && shared_region_comment?(comment) && trailing_comment_owned_by?(
              comment, owner
            )

            trailing << comment
            current = comment_end_line(comment) + 1
            current += 1 while current <= max_line && blank_line?(current)
          end

          trailing
        end

        # Return the normalized trailing region after an owner span.
        #
        # @param line_num [Integer] 1-based end line of the owner
        # @param upper_bound [Integer, nil] exclusive upper bound before the next owner
        # @param comments [Array<Hash>, nil] optional preselected trailing comments
        # @return [Region, nil]
        def trailing_comment_region_after(line_num, upper_bound: nil, comments: nil, owner: nil)
          selected = comments || trailing_comments_after(line_num, upper_bound: upper_bound, owner: owner)
          selected = selected.select { |comment| comment[:full_line] && shared_region_comment?(comment) }
          return if selected.empty?

          build_region(
            kind: :trailing,
            comments: selected,
            metadata: {
              line_num: line_num,
              upper_bound: upper_bound,
              source: :comment_tracker
            }
          )
        end

        # ----------------------------------------------------------------
        # Attachment building
        # ----------------------------------------------------------------

        def comment_attachment_for(owner, line_num: nil, leading_comments: nil, inline_comment: nil,
                                   trailing_comments: nil, **metadata)
          resolved_line_num = line_num || owner_line_num(owner)
          resolved_end_line = owner_end_line(owner) || resolved_line_num
          leading_region = if resolved_line_num
                             leading_comment_region_before(resolved_line_num, comments: leading_comments)
                           end
          inline_region = (inline_comment_region_at(resolved_line_num, comment: inline_comment) if resolved_line_num)
          trailing_region = if resolved_end_line
                              trailing_comment_region_after(resolved_end_line, comments: trailing_comments,
                                                                               owner: owner)
                            end

          Attachment.new(
            owner: owner,
            leading_region: leading_region,
            inline_region: inline_region,
            trailing_region: trailing_region,
            metadata: metadata.merge(
              line_num: resolved_line_num,
              end_line: resolved_end_line,
              source: :comment_tracker
            )
          )
        end

        # ----------------------------------------------------------------
        # Line utilities
        # ----------------------------------------------------------------

        def full_line_comment?(line_num)
          comment = comment_at(line_num)
          comment&.dig(:full_line) || false
        end

        def blank_line?(line_num)
          return false if line_num < 1 || line_num > @lines.length

          @lines[line_num - 1].to_s.strip.empty?
        end

        # Return the raw source line at a 1-based line number.
        #
        # @param line_num [Integer] 1-based line number
        # @return [String, nil]
        def line_at(line_num)
          return if line_num < 1 || line_num > @lines.length

          @lines[line_num - 1]
        end

        # ----------------------------------------------------------------
        # Augmenter integration
        # ----------------------------------------------------------------

        def augment(owners: [], **options)
          Augmenter.new(
            lines: @lines,
            comments: shared_region_comments,
            owners: owners,
            style: :c_style_line,
            total_comment_count: @comments.size,
            block_comment_count: @comments.count { |comment| comment[:block] },
            **options
          )
        end

        private

        def build_comments_by_line(comments)
          comments.each_with_object({}) do |comment, index|
            (comment_start_line(comment)..comment_end_line(comment)).each do |line_num|
              index[line_num] ||= []
              index[line_num] << comment unless index[line_num].include?(comment)
            end
          end
        end

        def comment_start_line(comment)
          comment[:line]
        end

        def comment_end_line(comment)
          comment[:end_line] || comment[:line]
        end

        def shared_region_comments
          @shared_region_comments ||= @comments.select { |comment| shared_region_comment?(comment) }
        end

        def shared_region_comment?(comment)
          !comment[:block]
        end

        def owner_line_num(owner)
          return owner.start_line if owner.respond_to?(:start_line) && owner.start_line

          nil
        end

        def owner_end_line(owner)
          return owner.end_line if owner.respond_to?(:end_line) && owner.end_line

          owner_line_num(owner)
        end

        def trailing_comment_owned_by?(comment, owner)
          return true unless owner&.respond_to?(:indent) && !owner.indent.nil?
          return true unless comment.key?(:indent)

          comment[:indent].to_i == owner.indent.to_i
        end

        def build_comment_node(comment)
          TrackedHashAdapter.node(comment, style: :c_style_line)
        end

        def build_region(kind:, comments:, metadata: {})
          TrackedHashAdapter.region(
            kind: kind,
            comments: comments,
            style: :c_style_line,
            metadata: metadata
          )
        end

        def extract_comments
          comments = []
          in_block_comment = false
          current_block_comment = nil

          @lines.each_with_index do |line, idx|
            line_num = idx + 1

            if in_block_comment
              current_block_comment[:end_line] = line_num if current_block_comment
              current_block_comment[:raw_lines] << line if current_block_comment
              current_block_comment[:raw] = current_block_comment[:raw_lines].join("\n") if current_block_comment

              if line.include?('*/')
                in_block_comment = false
                current_block_comment = nil
              end
              next
            end

            if line.include?('/*') && !line.include?('*/')
              in_block_comment = true
              indent_match = line.match(/\A(?<indent>\s*)/)
              current_block_comment = {
                line: line_num,
                end_line: line_num,
                indent: indent_match ? indent_match[:indent].length : 0,
                text: line.sub(%r{\A\s*/\*\s?}, '').strip,
                full_line: true,
                block: true,
                raw: line,
                raw_lines: [line]
              }
              comments << current_block_comment
              next
            end

            if (match = line.match(BLOCK_COMMENT_SINGLE_REGEX))
              comments << {
                line: line_num,
                end_line: line_num,
                indent: match[:indent].length,
                text: match[:text],
                full_line: true,
                block: true,
                raw: line
              }
              next
            end

            if (match = line.match(SINGLE_LINE_COMMENT_REGEX))
              comments << {
                line: line_num,
                indent: match[:indent].length,
                text: match[:text],
                full_line: true,
                block: false,
                raw: line
              }
              next
            end

            inline_comment = extract_inline_comment(line, line_num)
            comments << inline_comment if inline_comment
          end

          comments.each { |comment| comment.delete(:raw_lines) }
          comments
        end

        def extract_inline_comment(line, line_num)
          return unless line.include?('//')

          before_comment, after_comment = line.split('//', 2)
          return unless after_comment
          return if before_comment.to_s.strip.empty?
          return unless inline_comment_candidate?(before_comment, after_comment, line: line, line_num: line_num)

          comment_column = before_comment.length
          raw = line[comment_column..]

          {
            line: line_num,
            indent: comment_column,
            text: after_comment.strip,
            full_line: false,
            block: false,
            raw: raw
          }
        end

        def inline_comment_candidate?(before_comment, _after_comment, line:, line_num:)
          quote_count = before_comment.to_s.count('"') - before_comment.to_s.scan('\\"').count
          quote_count.even?
        end
      end
    end
  end
end
