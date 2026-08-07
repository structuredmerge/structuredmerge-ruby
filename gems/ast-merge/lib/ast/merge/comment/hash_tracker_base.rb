# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Shared base class for hash-comment (`#`) trackers across the merge family.
      #
      # This base provides the common lookup, query, region-building, and
      # attachment API that every `#`-syntax format shares. Format-specific
      # subclasses override:
      #
      # - {#extract_comments} — scanning/parsing logic for the format
      # - {#owner_line_num} — how to resolve a structural owner to a line number
      #
      # The tracked-comment hash shape is the same as TrackedHashAdapter expects:
      #
      #   { line: Integer,     # 1-based line number
      #     indent: Integer,   # leading whitespace width
      #     text: String,      # comment text without prefix
      #     full_line: Boolean, # true if the comment is the entire line
      #     raw: String }      # original source line
      #
      # @example Subclassing
      #   class MyFormat::CommentTracker < Ast::Merge::Comment::HashTrackerBase
      #     private
      #     def extract_comments
      #       # scan @lines, return Array<Hash> in tracked-hash shape
      #     end
      #   end
      #
      # @see Ast::Merge::Comment::TrackedHashAdapter
      class HashTrackerBase
        class MissingTrackedLineError < Ast::Merge::Error; end

        # Matches a full-line hash-style comment.
        #
        # @return [Regexp]
        FULL_LINE_COMMENT_REGEX = /\A(?<indent>\s*)#\s?(?<text>.*)\z/

        # @return [Array<Hash>] All extracted comments with metadata
        attr_reader :comments

        # @return [Array<String>] Source lines (chomped)
        attr_reader :lines

        # Initialize the tracker. Subclasses may accept additional arguments
        # but should call +super+ or reproduce the setup here.
        #
        # When +tree_haver_comments+ is provided the tracker skips its own
        # text-scanning path (+extract_comments+) and converts the tree_haver
        # comment objects into the internal hash format instead.  This is the
        # preferred input when the calling backend has already obtained a flat,
        # deduplicated list from +TreeHaver::Base::Parser#comments+.
        #
        # @param lines [Array<String>] Source lines (already chomped/split).
        #   Always required; used for +raw+ line lookup and blank-line queries
        #   even when +tree_haver_comments+ is supplied.
        # @param tree_haver_comments [Array<TreeHaver::Base::Comment>, nil]
        #   Optional pre-parsed comment objects from a tree_haver backend.
        def initialize(lines, tree_haver_comments: nil)
          @lines = Array(lines)
          @comments = if tree_haver_comments
                        comments_from_tree_haver(tree_haver_comments)
                      else
                        extract_comments
                      end
          @comments_by_line = @comments.group_by { |c| c[:line] }
        end

        # ----------------------------------------------------------------
        # Single-comment lookup
        # ----------------------------------------------------------------

        # Get comment hash at a specific line.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Hash, nil]
        def comment_at(line_num)
          @comments_by_line[line_num]&.first
        end

        # Get all comments converted to shared comment nodes.
        #
        # @return [Array<Ast::Merge::Comment::Line>]
        def comment_nodes
          @comment_nodes ||= @comments.map { |c| build_comment_node(c) }
        end

        # Get a shared comment node at a specific line.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Ast::Merge::Comment::Line, nil]
        def comment_node_at(line_num)
          comment = comment_at(line_num)
          return unless comment

          build_comment_node(comment)
        end

        # ----------------------------------------------------------------
        # Range queries
        # ----------------------------------------------------------------

        # Get all comments in a line range.
        #
        # @param range [Range] Range of 1-based line numbers
        # @return [Array<Hash>]
        def comments_in_range(range)
          @comments.select { |c| range.cover?(c[:line]) }
        end

        # Get comments in a line range converted to a shared comment region.
        #
        # @param range [Range] Range of 1-based line numbers
        # @param kind [Symbol] Region kind (:leading, :inline, :orphan, etc.)
        # @param full_line_only [Boolean] Whether to keep only full-line comments
        # @return [Ast::Merge::Comment::Region]
        def comment_region_for_range(range, kind:, full_line_only: false)
          selected = comments_in_range(range)
          selected = selected.select { |c| c[:full_line] } if full_line_only

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

        # Get leading full-line comments before a line, walking backward
        # and skipping blank lines between consecutive comment blocks.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Array<Hash>]
        def leading_comments_before(line_num)
          leading = []
          current = line_num - 1

          # Skip blank lines between the node and its leading comments
          current -= 1 while current >= 1 && blank_line?(current)

          while current >= 1
            comment = comment_at(current)
            break unless comment && comment[:full_line]

            leading.unshift(comment)
            current -= 1

            # Skip blank lines between consecutive comments
            current -= 1 while current >= 1 && blank_line?(current)
          end

          # If the collected comments extend all the way to the file's first
          # line, they are a preamble/header comment — not semantically owned
          # by this particular node.  Strip preamble lines that are separated
          # from the node-specific comment block by a blank line.
          strip_preamble(leading, line_num)
        end

        # Get a shared leading comment region before a line.
        #
        # @param line_num [Integer] 1-based line number
        # @param comments [Array<Hash>, nil] Optional preselected comment hashes
        # @return [Ast::Merge::Comment::Region, nil]
        def leading_comment_region_before(line_num, comments: nil)
          selected = comments || leading_comments_before(line_num)
          selected = selected.select { |c| c[:full_line] }
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

        # Get trailing comment on the same line (inline comment).
        #
        # @param line_num [Integer] 1-based line number
        # @return [Hash, nil]
        def inline_comment_at(line_num)
          comment = comment_at(line_num)
          comment if comment && !comment[:full_line]
        end

        # Get a shared inline comment region at a line.
        #
        # @param line_num [Integer] 1-based line number
        # @param comment [Hash, nil] Optional preselected inline comment hash
        # @return [Ast::Merge::Comment::Region, nil]
        def inline_comment_region_at(line_num, comment: nil)
          selected = [comment || inline_comment_at(line_num)].compact
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

        # Get adjacent full-line trailing comments after an owner line/span.
        #
        # Trailing ownership is stricter than leading ownership: the first
        # trailing comment must begin immediately on the next line after the
        # owner. Once attached, blank lines between later comment lines are
        # preserved inside the trailing region.
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
            break unless comment && comment[:full_line] && trailing_comment_owned_by?(comment, owner)

            trailing << comment
            current += 1
            current += 1 while current <= max_line && blank_line?(current)
          end

          trailing
        end

        # Get a shared trailing comment region after a line/span.
        #
        # @param line_num [Integer] 1-based end line of the owner
        # @param upper_bound [Integer, nil] exclusive upper bound before the next owner
        # @param comments [Array<Hash>, nil] Optional preselected trailing comments
        # @return [Ast::Merge::Comment::Region, nil]
        def trailing_comment_region_after(line_num, upper_bound: nil, comments: nil, owner: nil)
          selected = comments || trailing_comments_after(line_num, upper_bound: upper_bound, owner: owner)
          selected = selected.select { |c| c[:full_line] }
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

        # Build a passive shared comment attachment for an owner.
        #
        # @param owner [Object] Structural owner for the attachment
        # @param line_num [Integer, nil] Line number to use for leading/inline lookup
        # @param leading_comments [Array<Hash>, nil] Optional preselected leading comments
        # @param inline_comment [Hash, nil] Optional preselected inline comment
        # @param trailing_comments [Array<Hash>, nil] Optional preselected trailing comments
        # @param metadata [Hash] Additional metadata preserved on the attachment
        # @return [Ast::Merge::Comment::Attachment]
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

        # Check if a line is a full-line comment.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Boolean]
        def full_line_comment?(line_num)
          comment = comment_at(line_num)
          comment&.dig(:full_line) || false
        end

        # Check if a line is blank.
        #
        # @param line_num [Integer] 1-based line number
        # @return [Boolean]
        def blank_line?(line_num)
          return false if line_num < 1 || line_num > @lines.length

          @lines[line_num - 1].to_s.strip.empty?
        end

        # Strip file-preamble comments from a leading-comment collection.
        #
        # Any comment block that starts at line 1 and is followed by a
        # blank-line gap is a file header/preamble — it belongs to the file,
        # not to any particular key.  The gap is the definitive signal: it
        # separates the preamble from node-specific comments (if any).
        #
        # Unclaimed preamble comments are later picked up by the
        # {Augmenter} as a +preamble_region+ and emitted once at the
        # top of the merged output.
        #
        # @param comments [Array<Hash>] collected leading comments (ascending line order)
        # @param node_line [Integer] 1-based line of the node these comments precede
        # @return [Array<Hash>] pruned leading comments (may be empty)
        def strip_preamble(comments, node_line)
          return comments if comments.empty?
          return comments unless comments.first[:line] == 1

          # Find blank-line gaps in the range from the first comment to the node.
          gaps = []
          ((comments.first[:line])..node_line).each do |ln|
            gaps << ln if blank_line?(ln)
          end
          return comments if gaps.empty?

          # Everything at or before the first gap is preamble.
          # Keep only comments that appear after the first gap.
          comments.select { |c| c[:line] > gaps.first }
        end

        # Get raw line content.
        #
        # @param line_num [Integer] 1-based line number
        # @return [String, nil]
        def line_at(line_num)
          return if line_num < 1 || line_num > @lines.length

          @lines[line_num - 1]
        end

        def owner_end_line(owner)
          return owner.end_line if owner.respond_to?(:end_line) && owner.end_line

          owner_line_num(owner)
        end

        def trailing_comment_owned_by?(comment, owner)
          return true unless owner.respond_to?(:indent) && !owner.indent.nil?
          return true unless comment.key?(:indent)

          comment[:indent].to_i == owner.indent.to_i
        end

        # ----------------------------------------------------------------
        # Augmenter integration
        # ----------------------------------------------------------------

        # Build a passive shared comment augmenter for this source.
        #
        # @param owners [Array] Structural owners for attachment inference
        # @param options [Hash] Additional augmenter options
        # @return [Ast::Merge::Comment::Augmenter]
        def augment(owners: [], **options)
          Augmenter.new(
            lines: @lines,
            comments: @comments,
            owners: owners,
            style: comment_style,
            **options
          )
        end

        private

        # Extract comments from the source lines.
        #
        # Subclasses MUST override this method to provide format-specific
        # comment extraction. The returned array must contain hashes with
        # at minimum the keys: +:line+, +:indent+, +:text+, +:full_line+, +:raw+.
        #
        # This method is NOT called when +tree_haver_comments+ is provided to
        # the constructor; +comments_from_tree_haver+ is used instead.
        #
        # @return [Array<Hash>]
        def extract_comments
          raise NotImplementedError,
                "#{self.class}#extract_comments must be implemented by the format-specific subclass"
        end

        # Convert a flat list of +TreeHaver::Base::Comment+ objects to the
        # internal tracked-comment hash format.
        #
        # This is the tree_haver input path for backends that have already
        # obtained a flat, deduplicated comment list from a tree_haver parser.
        # The +@lines+ array is used to fill the +:raw+ key.
        #
        # Expected interface on each +th_comment+:
        # - +#text+ — full comment source (including +#+ delimiter)
        # - +#start_line+ — 1-based line number (from +TreeHaver::Base::Comment+)
        # - +#start_point+ — +{row: Integer, column: Integer}+ (0-based)
        # - +#attachment_hint+ — +:leading+, +:trailing+, or +:inline+ (or nil)
        #
        # @param th_comments [Array<TreeHaver::Base::Comment>]
        # @return [Array<Hash>]
        def comments_from_tree_haver(th_comments)
          th_comments.map { |th_comment| build_entry_from_tree_haver(th_comment) }
        end

        # Build a single internal comment hash from a +TreeHaver::Base::Comment+.
        #
        # @param th_comment [TreeHaver::Base::Comment]
        # @return [Hash]
        def build_entry_from_tree_haver(th_comment)
          line_num = th_comment.start_line
          raw_line = required_tree_haver_line(th_comment, line_num)
          indent = th_comment.start_point[:column]
          # Strip the leading `# ` or `#` prefix to get the bare content text.
          # tree_haver's #text includes the delimiter, matching Prism's #slice.
          content = th_comment.text.sub(/\A#\s?/, '')
          # :inline means non-whitespace code appears before the # on the same line.
          # :leading and :trailing both represent full-line (standalone) comments.
          full_line = th_comment.attachment_hint != :inline

          {
            line: line_num,
            indent: indent,
            text: content,
            full_line: full_line,
            raw: raw_line
          }
        end

        def required_tree_haver_line(_th_comment, line_num)
          line = line_at(line_num)
          return line if line

          raise MissingTrackedLineError,
                "tree_haver comment at line #{line_num} could not be mapped back to tracker source lines. " \
                  'HashTrackerBase requires source lines and tree_haver comments to describe the same input.'
        end

        # Resolve a structural owner to a 1-based line number.
        #
        # Subclasses may override this to support format-specific owner types.
        # The default implementation checks for +#start_line+ on the owner.
        #
        # @param owner [Object]
        # @return [Integer, nil]
        def owner_line_num(owner)
          return owner.start_line if owner.respond_to?(:start_line) && owner.start_line

          nil
        end

        # Build a shared comment node from a tracked comment hash.
        #
        # @param comment [Hash]
        # @return [Ast::Merge::Comment::Line]
        def build_comment_node(comment)
          TrackedHashAdapter.node(comment, style: comment_style)
        end

        # Build a shared comment region from tracked comment hashes.
        #
        # @param kind [Symbol] Region kind
        # @param comments [Array<Hash>] Comment hashes
        # @param metadata [Hash] Additional metadata
        # @return [Ast::Merge::Comment::Region]
        def build_region(kind:, comments:, metadata: {})
          TrackedHashAdapter.region(
            kind: kind,
            comments: comments,
            style: comment_style,
            metadata: metadata
          )
        end

        # Return the tracked comment style used for shared node/region building.
        #
        # Subclasses can override this when they share the tracked-hash
        # infrastructure but use a different comment delimiter family.
        #
        # @return [Symbol]
        def comment_style
          :hash_comment
        end
      end
    end
  end
end
