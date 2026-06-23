# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Builds standardized comment regions and attachments from source text,
      # tracked comment hashes, and structural owner ranges.
      #
      # This is a passive augmentation layer. It does not modify merge behavior;
      # it only infers normalized `Comment::Region` and `Comment::Attachment`
      # objects that format gems can adopt incrementally.
      class Augmenter
        attr_reader :lines,
                    :owners,
                    :tracked_comments,
                    :style,
                    :capability,
                    :attachments_by_owner,
                    :preamble_region,
                    :postlude_region,
                    :orphan_regions

        class << self
          # Build an augmenter and run augmentation immediately.
          #
          # @param options [Hash] arguments forwarded to {.new}
          # @return [Augmenter]
          def call(**options)
            new(**options)
          end
        end

        def initialize(lines: nil, source: nil, comments: [], owners: [], style: nil, capability: nil, **options)
          @lines = normalize_lines(lines, source)
          @style = resolve_style(style)
          @owners = normalize_owners(owners)
          @tracked_comments = normalize_comments(comments)
          @capability = capability || Capability.source_augmented(
            source: :tracked_hash,
            style: style_name,
            owner_count: @owners.size,
            comment_count: @tracked_comments.size,
            **options
          )

          @attachments_by_owner = {}
          @preamble_region = nil
          @postlude_region = nil
          @orphan_regions = []

          build!
        end

        # Return the inferred attachment for a specific owner.
        #
        # @param owner [Object] structural owner
        # @return [Attachment, nil]
        def attachment_for(owner)
          attachments_by_owner[owner]
        end

        private

        def build!
          claimed = Set.new
          layout_attachments = build_layout_attachments_by_owner

          owners.each do |owner|
            leading_comments = infer_leading_comments(owner, claimed)
            inline_comments = infer_inline_comments(owner, claimed)
            trailing_comments = infer_trailing_comments(owner, claimed)
            layout_attachment = layout_attachments[owner]

            leading_floating = leading_comments.any? && gap_before_owner?(leading_comments, owner)

            attachments_by_owner[owner] = Attachment.new(
              owner: owner,
              leading_region: build_region(:leading, leading_comments, floating: leading_floating),
              inline_region: build_region(:inline, inline_comments, include_blank_lines: false),
              trailing_region: build_region(:trailing, trailing_comments),
              leading_gap: layout_attachment&.leading_gap,
              trailing_gap: layout_attachment&.trailing_gap
            )

            leading_comments.each { |comment| claimed << comment.object_id }
            inline_comments.each { |comment| claimed << comment.object_id }
            trailing_comments.each { |comment| claimed << comment.object_id }
          end

          infer_postlude!(claimed)
          infer_remaining_regions!(claimed)
        end

        def infer_leading_comments(owner, claimed)
          return [] unless owner.respond_to?(:start_line)
          return [] unless owner.start_line

          candidates = tracked_comments.select do |comment|
            comment[:full_line] && !claimed.include?(comment.object_id) && comment[:line] < owner.start_line
          end
          return [] if candidates.empty?

          selected = []
          current_line = owner.start_line - 1

          while current_line >= 1
            comment = candidates.find { |candidate| candidate[:line] == current_line }

            if comment
              selected.unshift(comment)
              current_line -= 1
            elsif blank_line?(current_line)
              current_line -= 1
            else
              break
            end
          end

          strip_preamble(selected, owner.start_line)
        end

        def infer_inline_comments(owner, claimed)
          return [] unless owner.respond_to?(:start_line) && owner.respond_to?(:end_line)
          return [] unless owner.start_line && owner.end_line

          tracked_comments.select do |comment|
            !comment[:full_line] &&
              !claimed.include?(comment.object_id) &&
              (owner.start_line..owner.end_line).cover?(comment[:line])
          end
        end

        def infer_trailing_comments(owner, claimed)
          return [] unless owner.respond_to?(:end_line)
          return [] unless owner.end_line

          next_owner = next_owner_after(owner)
          max_line = next_owner&.start_line ? next_owner.start_line - 1 : lines.length
          current = owner.end_line + 1
          return [] if current > max_line || blank_line?(current)

          selected = []
          while current <= max_line
            comment = tracked_comments.find do |candidate|
              candidate[:full_line] &&
                !claimed.include?(candidate.object_id) &&
                candidate[:line] == current &&
                trailing_comment_owned_by?(candidate, owner)
            end
            break unless comment

            selected << comment
            current += 1
            current += 1 while current <= max_line && blank_line?(current)
          end

          selected
        end

        def infer_postlude!(claimed)
          last_line = owners.reverse_each.map(&:end_line).compact.first
          return unless last_line

          comments = tracked_comments.select do |comment|
            comment[:full_line] && !claimed.include?(comment.object_id) && comment[:line] > last_line
          end
          return if comments.empty?

          @postlude_region = build_region(:postlude, comments)
          comments.each { |comment| claimed << comment.object_id }
        end

        def infer_remaining_regions!(claimed)
          remaining = tracked_comments.select do |comment|
            comment[:full_line] && !claimed.include?(comment.object_id)
          end
          return if remaining.empty?

          groups = group_comments_with_blank_lines(remaining)
          first_owner_start = owners.first&.start_line

          groups.each do |group|
            # When a group starts at line 1 and spans a blank-line gap before
            # the first owner, split it: the pre-gap portion is the file
            # preamble and the post-gap portion is a separate orphan region.
            if @preamble_region.nil? && first_owner_start && group.first[:line] == 1 && group.length > 1
              split = split_preamble_group(group, first_owner_start)
              if split
                preamble_part, rest_part = split
                @preamble_region = build_region(:preamble, preamble_part)
                @orphan_regions << build_region(:orphan, rest_part) if rest_part&.any?
                next
              end
            end

            kind = if first_owner_start && group.last[:line] < first_owner_start
                     @preamble_region.nil? ? :preamble : :orphan
                   else
                     :orphan
                   end

            region = build_region(kind, group)
            if kind == :preamble && @preamble_region.nil?
              @preamble_region = region
            else
              @orphan_regions << region
            end
          end
        end

        # Split a comment group that starts at line 1 into preamble and
        # non-preamble portions at the last blank-line gap before
        # +first_owner_start+.
        #
        # @return [Array(Array<Hash>, Array<Hash>), nil] [preamble, rest] or nil if no split
        def split_preamble_group(group, first_owner_start)
          # Find blank-line gaps within the group's range
          last_gap = nil
          (group.first[:line]..group.last[:line]).each do |ln|
            last_gap = ln if blank_line?(ln) && ln < first_owner_start
          end
          return unless last_gap

          before = group.select { |c| c[:line] < last_gap }
          after = group.select { |c| c[:line] > last_gap }
          return if before.empty?

          [before, after]
        end

        def group_comments_with_blank_lines(comments)
          sorted = comments.sort_by { |comment| comment[:line] }
          groups = []
          current = []

          sorted.each do |comment|
            if current.empty?
              current << comment
              next
            end

            if only_blank_lines_between?(current.last[:line], comment[:line])
              current << comment
            else
              groups << current
              current = [comment]
            end
          end

          groups << current if current.any?
          groups
        end

        def only_blank_lines_between?(from_line, to_line)
          return true if to_line <= from_line + 1

          ((from_line + 1)...to_line).all? { |line_number| blank_line?(line_number) }
        end

        def next_owner_after(owner)
          index = owners.index(owner)
          return unless index

          owners[index + 1]
        end

        def trailing_comment_owned_by?(comment, owner)
          return true unless owner.respond_to?(:indent) && !owner.indent.nil?
          return true unless comment.key?(:indent)

          comment[:indent].to_i == owner.indent.to_i
        end

        def build_region(kind, comments, include_blank_lines: true, floating: false)
          return if comments.empty?

          nodes = []
          previous_line = nil

          comments.sort_by { |comment| comment[:line] }.each do |comment|
            if include_blank_lines && previous_line
              ((previous_line + 1)...comment[:line]).each do |line_number|
                if blank_line?(line_number)
                  nodes << Empty.new(line_number: line_number,
                                     text: line_at(line_number).to_s)
                end
              end
            end

            nodes << TrackedHashAdapter.node(comment, style: style)
            previous_line = comment[:line]
          end

          Region.new(
            kind: kind,
            nodes: nodes,
            metadata: {
              source: :augmenter,
              tracked_hashes: comments,
              floating: floating
            }
          )
        end

        def build_layout_attachments_by_owner
          return {} if owners.empty?

          Ast::Merge::Layout::Augmenter.new(lines: lines, owners: owners).attachments_by_owner
        end

        def normalize_lines(lines, source)
          return Array(lines) if lines
          return [] unless source

          values = source.split("\n", -1)
          values.pop if values.last&.empty? && source.end_with?("\n")
          values
        end

        def resolve_style(style)
          case style
          when nil
            Style.for(:hash_comment)
          when Style
            style
          else
            Style.for(style)
          end
        end

        def style_name
          style.respond_to?(:name) ? style.name : style.to_s
        end

        def normalize_comments(comments)
          Array(comments)
            .map { |comment| normalize_comment_hash(comment) }
            .sort_by { |comment| comment[:line] }
        end

        def normalize_comment_hash(comment)
          raise ArgumentError, 'comment must be a Hash' unless comment.is_a?(Hash)

          comment.each_with_object({}) do |(key, value), result|
            result[key.to_sym] = value
          end
        end

        def normalize_owners(owners)
          Array(owners)
            .tap { |values| values.each { |owner| validate_owner!(owner) } }
            .sort_by { |owner| [owner.start_line || Float::INFINITY, owner.end_line || Float::INFINITY] }
        end

        def validate_owner!(owner)
          return if owner.respond_to?(:start_line) && owner.respond_to?(:end_line)

          raise ArgumentError, 'owner must respond to #start_line and #end_line'
        end

        def blank_line?(line_number)
          line_at(line_number).to_s.strip.empty?
        end

        # Detects whether the leading comment block is gap-separated (floating)
        # from its owner node.  A gap is one or more blank lines between the
        # last comment in the block and the owner's start_line.
        #
        # @param comments [Array<Hash>] leading comments (ascending line order)
        # @param owner [#start_line] the structural node the comments precede
        # @return [Boolean]
        def gap_before_owner?(comments, owner)
          return false if comments.empty?
          return false unless owner.respond_to?(:start_line) && owner.start_line

          last_comment_line = comments.max_by { |c| c[:line] }[:line]
          return false unless last_comment_line

          # If there is at least one blank line between the last comment and
          # the owner start, the comment block is floating.
          ((last_comment_line + 1)...owner.start_line).any? { |ln| blank_line?(ln) }
        end

        # Strip file-preamble comments from a leading-comment collection.
        # Comments starting at line 1 with a blank-line gap before the node
        # are a file header, not owned by any key.  The gap is the signal.
        # Unclaimed preamble flows to {#infer_remaining_regions!} as
        # +preamble_region+.
        #
        # @param comments [Array<Hash>] ascending-line-order comments
        # @param node_line [Integer] 1-based line of the owner node
        # @return [Array<Hash>]
        def strip_preamble(comments, node_line)
          return comments if comments.empty?
          return comments unless comments.first[:line] == 1

          gaps = []
          ((comments.first[:line])..node_line).each do |ln|
            gaps << ln if blank_line?(ln)
          end
          return comments if gaps.empty?

          comments.select { |c| c[:line] > gaps.first }
        end

        def line_at(line_number)
          return if line_number < 1

          lines[line_number - 1]
        end
      end
    end
  end
end
