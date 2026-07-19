# frozen_string_literal: true

module Ast
  module Merge
    # Base class for emitters that convert AST structures back to text.
    # Provides common functionality for tracking indentation, managing output lines,
    # and handling comments.
    #
    # Subclasses implement format-specific emission methods (e.g., emit_pair for JSON,
    # emit_variable_assignment for Bash, etc.)
    #
    # Ownership boundary:
    # - shared structural recomposition and attachment preservation belong here
    # - syntax-aware normalization and serializer polish belong in the relevant
    #   family layer or concrete emitter subclass unless they prove reusable
    #   across unrelated formats
    #
    # @example Implementing a custom emitter
    #   class MyEmitter < Ast::Merge::EmitterBase
    #     def emit_my_construct(data)
    #       add_comma_if_needed if @needs_separator
    #       @lines << "#{current_indent}my_syntax: #{data}"
    #       @needs_separator = true
    #     end
    #   end
    class EmitterBase
      class UnsupportedCommentNodeError < Ast::Merge::Error; end

      # @return [Array<String>] Output lines
      attr_reader :lines

      # @return [Integer] Current indentation level
      attr_reader :indent_level

      # @return [Integer] Spaces per indent level
      attr_reader :indent_size

      # Initialize a new emitter
      #
      # @param indent_size [Integer] Number of spaces per indent level
      # @param options [Hash] Additional options for subclasses
      def initialize(indent_size: 2, **options)
        @lines = []
        @indent_level = 0
        @indent_size = indent_size
        initialize_subclass_state(**options)
      end

      # Hook for subclasses to initialize their own state
      # @param options [Hash] Additional options
      def initialize_subclass_state(**options)
        # Override in subclasses if needed
      end

      # Emit a blank line
      def emit_blank_line
        @lines << ''
      end

      # Emit leading comments from CommentTracker
      #
      # @param comments [Array<Hash>] Comment hashes with :text, :indent, etc.
      def emit_leading_comments(comments)
        comments.each do |comment|
          emit_tracked_comment(comment)
        end
      end

      # Emit a comment from CommentTracker hash
      # Subclasses should override this to handle format-specific comment syntax
      #
      # @param comment [Hash] Comment hash with :text, :indent, :block, etc.
      def emit_tracked_comment(comment)
        raise NotImplementedError, 'Subclasses must implement emit_tracked_comment'
      end

      # Emit a comment using the emitter's native syntax.
      # Subclasses should override this to support full-line and inline emission.
      #
      # @param text [String] Comment text without the delimiter
      # @param inline [Boolean] Whether this is an inline comment
      def emit_comment(text, inline: false)
        raise NotImplementedError, 'Subclasses must implement emit_comment'
      end

      # Emit a shared normalized comment region.
      #
      # Preserves explicit blank-line nodes and can also recreate blank gaps between
      # comment lines by consulting original source lines when those gaps are not
      # already represented as `Comment::Empty` nodes.
      #
      # @param region [Comment::Region, nil] Region to emit
      # @param inline [Boolean, nil] Force inline emission mode
      # @param source_lines [Array<String>, nil] Original source lines for gap preservation
      def emit_comment_region(region, inline: nil, source_lines: nil)
        return unless region
        return unless region.respond_to?(:nodes)
        return if region.respond_to?(:empty?) && region.empty?

        inline = region.inline? if inline.nil? && region.respond_to?(:inline?)
        return emit_inline_comment_region(region) if inline

        previous_line = nil
        comment_region_nodes(region).each do |node|
          current_line = comment_region_line_number(node)
          emit_region_gap_lines(previous_line, current_line, source_lines)
          emit_comment_node(node)
          previous_line = current_line
        end
      end

      # Emit selected regions from a shared comment attachment.
      #
      # @param attachment [Comment::Attachment, nil] Attachment to emit
      # @param leading [Boolean] Whether to emit the leading region
      # @param inline [Boolean] Whether to emit the inline region
      # @param trailing [Boolean] Whether to emit the trailing region
      # @param orphan [Boolean] Whether to emit orphan regions in order
      # @param source_lines [Array<String>, nil] Original source lines for gap preservation
      def emit_comment_attachment(attachment, leading: true, inline: false, trailing: false, orphan: false,
                                  source_lines: nil)
        return unless attachment
        return unless attachment.respond_to?(:leading_region) && attachment.respond_to?(:inline_region)

        regions = []
        regions << attachment.leading_region if leading && attachment.leading_region
        regions << attachment.inline_region if inline && attachment.inline_region
        if trailing && attachment.respond_to?(:trailing_region) && attachment.trailing_region
          regions << attachment.trailing_region
        end
        regions.concat(Array(attachment.orphan_regions)) if orphan && attachment.respond_to?(:orphan_regions)

        previous_region_end_line = nil
        regions.each do |region|
          current_region_start_line = region.respond_to?(:start_line) ? region.start_line : nil
          emit_region_gap_lines(previous_region_end_line, current_region_start_line, source_lines)
          emit_comment_region(region, inline: region.respond_to?(:inline?) ? region.inline? : nil,
                                      source_lines: source_lines)
          previous_region_end_line = region.respond_to?(:end_line) ? region.end_line : previous_region_end_line
        end
      end

      # Emit a shared layout gap when the requesting owner controls output.
      #
      # @param gap [Layout::Gap, nil] Gap to emit
      # @param owner [Object, nil] Owner requesting emission; defaults to the gap's effective controller
      # @param source_lines [Array<String>, nil] Original source lines for exact whitespace preservation
      # @param retained_owners [Array<Object>, nil] Explicit retained owners for controller fallback
      # @param removed_owners [Array<Object>, nil] Explicit removed owners for controller fallback
      # @param last_emitted_source_line [Integer, nil] Skip gap lines up to and including this source line
      # @return [Integer, nil] Last emitted source line number
      def emit_layout_gap(gap, owner: nil, source_lines: nil, retained_owners: nil, removed_owners: nil,
                          last_emitted_source_line: nil)
        return unless gap

        emitting_owner = owner || gap.effective_controller(retained_owners: retained_owners,
                                                           removed_owners: removed_owners) || gap.controller
        return unless emitting_owner
        return unless gap.controls_output_for?(emitting_owner, retained_owners: retained_owners,
                                                               removed_owners: removed_owners)

        start_line = if last_emitted_source_line
                       [gap.start_line, last_emitted_source_line + 1].max
                     else
                       gap.start_line
                     end
        return if start_line > gap.end_line

        emit_layout_gap_lines(gap, source_lines: source_lines, line_numbers: start_line..gap.end_line)
      end

      # Emit selected leading/trailing layout gaps from an attachment.
      #
      # Works with both Layout::Attachment and Comment::Attachment because both
      # expose owner/leading_gap/trailing_gap.
      #
      # @param attachment [Layout::Attachment, Comment::Attachment, nil]
      # @param leading [Boolean] Whether to emit the leading gap
      # @param trailing [Boolean] Whether to emit the trailing gap
      # @param source_lines [Array<String>, nil] Original source lines for exact whitespace preservation
      # @param retained_owners [Array<Object>, nil] Explicit retained owners for controller fallback
      # @param removed_owners [Array<Object>, nil] Explicit removed owners for controller fallback
      # @param leading_last_emitted_source_line [Integer, nil] Skip leading gap lines up to and including this source line
      # @param trailing_last_emitted_source_line [Integer, nil] Skip trailing gap lines up to and including this source line
      # @return [Hash{Symbol=>Integer}] Last emitted source line by selected gap side
      def emit_layout_attachment(attachment, leading: true, trailing: false, source_lines: nil, retained_owners: nil,
                                 removed_owners: nil, leading_last_emitted_source_line: nil, trailing_last_emitted_source_line: nil)
        return {} unless attachment
        unless attachment.respond_to?(:owner) && attachment.respond_to?(:leading_gap) && attachment.respond_to?(:trailing_gap)
          return {}
        end

        emitted_lines = {}

        if leading && attachment.leading_gap
          emitted_lines[:leading] = emit_layout_gap(
            attachment.leading_gap,
            owner: attachment.owner,
            source_lines: source_lines,
            retained_owners: retained_owners,
            removed_owners: removed_owners,
            last_emitted_source_line: leading_last_emitted_source_line
          )
        end

        if trailing && attachment.trailing_gap
          emitted_lines[:trailing] = emit_layout_gap(
            attachment.trailing_gap,
            owner: attachment.owner,
            source_lines: source_lines,
            retained_owners: retained_owners,
            removed_owners: removed_owners,
            last_emitted_source_line: trailing_last_emitted_source_line
          )
        end

        emitted_lines.compact
      end

      # Emit raw lines as-is (for preserving exact formatting)
      #
      # @param raw_lines [Array<String>] Lines to emit without modification
      def emit_raw_lines(raw_lines)
        raw_lines.each { |line| @lines << line.chomp }
      end

      # Get the output as a single string
      # Subclasses may override to customize output format (e.g., to_json, to_yaml)
      #
      # @return [String]
      def to_s
        content = @lines.join("\n")
        content += "\n" unless content.empty? || content.end_with?("\n")
        content
      end

      # Check whether every provided line is blank.
      #
      # @param candidate_lines [Array<String>] Lines to classify
      # @return [Boolean]
      def blank_lines?(candidate_lines)
        Array(candidate_lines).all? { |line| line.to_s.strip.empty? }
      end

      # Check whether the current emitter output ends with a blank line.
      #
      # @return [Boolean]
      def ends_with_blank_line?
        @lines.any? && blank_lines?([@lines.last])
      end

      # Clear the emitter state
      def clear
        @lines = []
        @indent_level = 0
        clear_subclass_state
      end

      # Hook for subclasses to clear their own state
      def clear_subclass_state
        # Override in subclasses if needed
      end

      # Increase indentation level
      def indent
        @indent_level += 1
      end

      # Decrease indentation level
      def dedent
        @indent_level -= 1 if @indent_level > 0
      end

      protected

      # Get the current indentation string
      # @return [String]
      def current_indent
        ' ' * (@indent_level * @indent_size)
      end

      # Add a line with current indentation
      # @param content [String] Line content
      def add_indented_line(content)
        @lines << "#{current_indent}#{content}"
      end

      private

      def emit_inline_comment_region(region)
        text = inline_comment_region_text(region)
        return if text.empty? || @lines.empty?

        emit_inline_comment_text(
          text,
          region: region,
          target_column: inline_comment_region_target_column(region, current_line: @lines[-1].to_s)
        )
      end

      def comment_region_nodes(region)
        Array(region.nodes)
      end

      def inline_comment_region_text(region)
        texts = comment_region_nodes(region).filter_map { |node| inline_comment_node_text(node) }
        return '' if texts.empty?

        texts.each_with_index.reduce(+'') do |memo, (text, index)|
          next text.dup if index.zero?

          memo << ' ' unless memo.end_with?(' ') || text.start_with?(' ')
          memo << text
        end
      end

      def inline_comment_region_target_column(_region, current_line:)
        nil
      end

      def emit_inline_comment_text(text, region:, target_column: nil)
        emit_comment(text, inline: true)
      end

      def emit_comment_node(node)
        if node.respond_to?(:slice)
          @lines << node.slice.to_s.chomp
        elsif node.respond_to?(:text)
          @lines << node.text.to_s.chomp
        else
          raise UnsupportedCommentNodeError,
                "Cannot emit comment node without raw text: #{node.class}"
        end
      end

      def inline_comment_node_text(node)
        return unless node

        unless node.respond_to?(:slice) && node.respond_to?(:style)
          raise UnsupportedCommentNodeError,
                "Cannot emit inline comment node without raw slice and style: #{node.class}"
        end

        slice = node.slice.to_s
        line_start = node.style.respond_to?(:line_start) ? node.style.line_start.to_s : ''
        if line_start.empty?
          raise UnsupportedCommentNodeError,
                "Cannot emit inline comment node without a line comment delimiter: #{node.class}"
        end

        stripped = slice.lstrip
        unless stripped.start_with?(line_start)
          raise UnsupportedCommentNodeError,
                "Cannot emit inline comment node whose raw slice does not start with the comment delimiter: #{node.class}"
        end

        content = stripped.delete_prefix(line_start)
        content = content.delete_prefix(' ')
        if node.style.respond_to?(:line_end) && node.style.line_end
          content = content.sub(/\s*#{Regexp.escape(node.style.line_end.to_s)}\z/, '')
        end
        content
      end

      def emit_region_gap_lines(previous_line, current_line, source_lines)
        return unless previous_line && current_line && current_line > previous_line + 1

        if source_lines
          gap_lines = source_lines[previous_line, current_line - previous_line - 1] || []
          blank_lines = gap_lines.select { |line| line.to_s.strip.empty? }
          emit_raw_lines(blank_lines) if blank_lines.any?
        else
          (current_line - previous_line - 1).times { emit_blank_line }
        end
      end

      def emit_layout_gap_lines(gap, source_lines:, line_numbers:)
        last_emitted_line = nil

        layout_gap_line_values(gap, source_lines: source_lines, line_numbers: line_numbers).each do |line_num, line|
          next unless line.to_s.strip.empty?

          @lines << line.to_s.chomp
          last_emitted_line = line_num
        end

        last_emitted_line
      end

      def layout_gap_line_values(gap, source_lines:, line_numbers:)
        if source_lines
          line_numbers.map { |line_num| [line_num, source_lines[line_num - 1]] }
        else
          line_numbers.map { |line_num| [line_num, gap.lines[line_num - gap.start_line]] }
        end
      end

      def comment_region_line_number(node)
        return node.line_number if node.respond_to?(:line_number)
        return node.location.start_line if node.respond_to?(:location) && node.location

        nil
      end
    end
  end
end
