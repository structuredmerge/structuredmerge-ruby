# frozen_string_literal: true

module Prism
  module Merge
    module Comment
      # Ruby-specific comment block with magic comment detection.
      #
      # Extends the generic `Ast::Merge::Comment::Block` with Ruby-specific
      # features like detection and enumeration of magic comments.
      #
      # @example
      #   block = Block.new(children: [
      #     Line.new(text: "# frozen_string_literal: true", line_number: 1),
      #     Line.new(text: "# Regular comment", line_number: 2),
      #   ])
      #   block.contains_magic_comment? #=> true
      #   block.magic_comments.first.magic_comment_type #=> :frozen_string_literal
      #
      class Block < Ast::Merge::Comment::Block
        # Initialize a new Ruby comment Block.
        #
        # @param children [Array<Line, Ast::Merge::Comment::Empty>] Child nodes
        def initialize(children:)
          super(children: children, style: :hash_comment)
        end

        # Check if this block contains a magic comment.
        #
        # @return [Boolean] true if any child is a magic comment
        def contains_magic_comment?
          children.any? { |c| c.is_a?(Line) && c.magic_comment? }
        end

        # Alias for consistency with Line#magic_comment?
        alias magic_comment? contains_magic_comment?

        # Get all magic comments in this block.
        #
        # @return [Array<Line>] Magic comment lines
        def magic_comments
          children.select { |c| c.is_a?(Line) && c.magic_comment? }
        end

        # Generate signature for matching.
        #
        # For blocks containing magic comments, uses the FIRST magic comment's
        # signature (by type) so that blocks with the same type of magic comment
        # will match regardless of value (e.g., true vs false).
        #
        # For non-magic blocks, uses the parent implementation.
        #
        # @return [Array] Signature for matching
        def signature
          if contains_magic_comment?
            # Use the first magic comment's signature
            magic_comments.first.signature
          else
            super
          end
        end

        # @return [String] Human-readable representation
        def inspect
          magic = contains_magic_comment? ? ' has_magic_comments' : ''
          "#<Prism::Merge::Comment::Block lines=#{location.start_line}..#{location.end_line}#{magic} children=#{children.size}>"
        end
      end
    end
  end
end
