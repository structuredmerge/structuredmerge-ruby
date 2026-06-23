# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Represents a contiguous block of comment content.
      #
      # A comment block can represent:
      # - A sequence of line comments not separated by blank lines
      # - A C-style block comment (`/* ... */`)
      # - An HTML comment block (`<!-- ... -->`)
      #
      # The block acts as a grouping mechanism for signature matching and
      # merge operations.
      #
      # @example Line comment block (Ruby/Python style)
      #   block = Block.new(children: [
      #     Line.new(text: "# First line", line_number: 1),
      #     Line.new(text: "# Second line", line_number: 2),
      #   ])
      #   block.signature #=> [:comment_block, "first line"]
      #
      # @example C-style block comment
      #   block = Block.new(
      #     raw_content: "/* This is a\n   multi-line comment */",
      #     start_line: 1,
      #     end_line: 2,
      #     style: :c_style_block
      #   )
      #
      class Block < AstNode
        # @return [Array<Line, Empty>] The child nodes in this block (for line-based blocks)
        attr_reader :children

        # @return [String, nil] Raw content for block-style comments (e.g., /* ... */)
        attr_reader :raw_content

        # @return [Style] The comment style configuration
        attr_reader :style

        # TreeHaver::Node protocol: type
        # @return [String] "comment_block"
        def type
          'comment_block'
        end

        # Initialize a new Block.
        #
        # For line-based comments, pass `children` array.
        # For block-style comments (/* ... */), pass `raw_content`.
        #
        # @param children [Array<Line, Empty>, nil] Child nodes (for line comments)
        # @param raw_content [String, nil] Raw block content (for block comments)
        # @param start_line [Integer, nil] Start line (required for raw_content)
        # @param end_line [Integer, nil] End line (required for raw_content)
        # @param style [Style, Symbol, nil] Comment style (default: :hash_comment)
        def initialize(children: nil, raw_content: nil, start_line: nil, end_line: nil, style: nil)
          @style = resolve_style(style)
          @children = children || []
          @raw_content = raw_content

          if raw_content
            # Block-style comment (e.g., /* ... */)
            @start_line = start_line || 1
            @end_line = end_line || @start_line
            combined_slice = raw_content
          else
            # Line-based comment block
            first_child = @children.first
            last_child = @children.last
            @start_line = first_child&.location&.start_line || 1
            @end_line = last_child&.location&.end_line || @start_line
            combined_slice = @children.map(&:slice).join("\n")
          end

          location = AstNode::Location.new(
            start_line: @start_line,
            end_line: @end_line,
            start_column: 0,
            end_column: combined_slice.split("\n").last&.length || 0
          )

          super(slice: combined_slice, location: location)
        end

        # Generate signature for matching.
        #
        # For line-based blocks, uses the first non-empty line's content.
        # For block-style comments, uses the first meaningful line of content.
        #
        # @return [Array] Signature for matching
        def signature
          content = first_meaningful_content
          [:comment_block, content[0..120]] # Limit signature length
        end

        # @return [String] Normalized combined content
        def normalized_content
          if raw_content
            extract_block_content
          else
            children
              .select { |c| c.is_a?(Line) }
              .map { |c| c.content.strip }
              .join("\n")
          end
        end

        # Check if this block contains a freeze marker.
        #
        # @param freeze_token [String] The freeze token to look for
        # @return [Symbol, nil] :freeze, :unfreeze, or nil
        def freeze_action(freeze_token)
          return unless freeze_token

          if raw_content
            pattern = /#{Regexp.escape(freeze_token)}:(freeze|unfreeze)/i
            match = raw_content.match(pattern)
            return match[1]&.downcase&.to_sym if match
          end

          children.each do |child|
            next unless child.respond_to?(:freeze_action)

            action = child.freeze_action(freeze_token)
            return action if action
          end

          nil
        end

        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if any child contains a freeze marker
        def freeze_marker?(freeze_token)
          !freeze_action(freeze_token).nil?
        end

        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if this block contains a freeze directive
        def freeze?(freeze_token)
          freeze_action(freeze_token) == :freeze
        end

        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if this block contains an unfreeze directive
        def unfreeze?(freeze_token)
          freeze_action(freeze_token) == :unfreeze
        end

        # @return [String] Human-readable representation
        def inspect
          if raw_content
            "#<Comment::Block lines=#{@start_line}..#{@end_line} style=#{style.name} block_comment>"
          else
            "#<Comment::Block lines=#{@start_line}..#{@end_line} style=#{style.name} children=#{children.size}>"
          end
        end

        private

        # Resolve the style parameter to a Style instance.
        #
        # @param style [Style, Symbol, nil] Style configuration
        # @return [Style] Resolved style instance
        def resolve_style(style)
          case style
          when Style
            style
          when Symbol
            Style.for(style)
          when nil
            Style.for(Style::DEFAULT_STYLE)
          else
            raise ArgumentError, "Invalid style: #{style.inspect}"
          end
        end

        # Get the first meaningful content for signature generation.
        #
        # @return [String] First non-empty content, lowercased
        def first_meaningful_content
          if raw_content
            # Extract first line of content from block comment
            extract_block_content.split("\n").first&.strip&.downcase || ''
          else
            # Find first comment line with actual content
            first_content = children.find { |c| c.is_a?(Line) && !c.content.strip.empty? }
            first_content&.content&.strip&.downcase || ''
          end
        end

        # Extract content from a block-style comment.
        #
        # Removes the opening and closing delimiters.
        #
        # @return [String] The content without delimiters
        def extract_block_content
          return '' unless raw_content

          content = raw_content.to_s

          # Remove block start delimiter
          content = content.sub(/^\s*#{Regexp.escape(style.block_start)}\s*/, '') if style.block_start

          # Remove block end delimiter
          content = content.sub(/\s*#{Regexp.escape(style.block_end)}\s*$/, '') if style.block_end

          # Clean up common patterns in multi-line block comments
          # (leading asterisks on each line, common in /* ... */ style)
          lines = content.split("\n")
          if lines.size > 1 && lines[1..].all? { |l| l.match?(/^\s*\*/) }
            lines = lines.map { |l| l.sub(/^\s*\*\s?/, '') }
          end

          lines.map(&:strip).join("\n")
        end
      end
    end
  end
end
