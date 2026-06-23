# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Represents an empty/blank line in source code.
      #
      # Empty lines are important for preserving document structure and
      # separating comment blocks. They serve as natural boundaries between
      # logical sections of comments.
      #
      # @example
      #   empty = Empty.new(line_number: 5)
      #   empty.slice #=> ""
      #   empty.signature #=> [:empty_line]
      #
      # @example With whitespace-only content
      #   empty = Empty.new(line_number: 5, text: "   ")
      #   empty.slice #=> "   "
      #   empty.signature #=> [:empty_line]
      #
      class Empty < AstNode
        # @return [Integer] The line number in source
        attr_reader :line_number

        # @return [String] The actual line content (may have whitespace)
        attr_reader :text

        # TreeHaver::Node protocol: type
        # @return [String] "empty_line"
        def type
          'empty_line'
        end

        # Initialize a new Empty line.
        #
        # @param line_number [Integer] The 1-based line number
        # @param text [String] The actual line content (may have whitespace)
        def initialize(line_number:, text: '')
          @line_number = line_number
          @text = text.to_s

          location = AstNode::Location.new(
            start_line: line_number,
            end_line: line_number,
            start_column: 0,
            end_column: @text.length
          )

          super(slice: @text, location: location)
        end

        # Empty lines have a generic signature - they don't match by content.
        #
        # All empty lines are considered equivalent for matching purposes.
        #
        # @return [Array] Signature for matching
        def signature
          [:empty_line]
        end

        # @return [String] Empty normalized content
        def normalized_content
          ''
        end

        # Empty lines never contain freeze markers.
        #
        # @param _freeze_token [String] Ignored
        # @return [Boolean] Always false
        def freeze_marker?(_freeze_token)
          false
        end

        # @return [String] Human-readable representation
        def inspect
          "#<Comment::Empty line=#{line_number}>"
        end
      end
    end
  end
end
