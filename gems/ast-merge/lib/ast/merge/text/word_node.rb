# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Represents a word within a line of text.
      # Words are the nested level of the text-based AST.
      # They are identified by word boundaries (regex \b).
      #
      # Inherits from AstNode (SyntheticNode) to implement the TreeHaver::Node
      # protocol, making it compatible with all tree_haver-based merge operations.
      #
      # @example
      #   word = WordNode.new("hello", line_number: 1, word_index: 0, start_col: 0, end_col: 5)
      #   word.content    # => "hello"
      #   word.signature  # => [:word, "hello"]
      #   word.type       # => "word_node" (TreeHaver protocol)
      class WordNode < AstNode
        # @return [String] The word content
        attr_reader :content

        # @return [Integer] 0-based index of this word within the line
        attr_reader :word_index

        # Initialize a new WordNode
        #
        # @param content [String] The word content
        # @param line_number [Integer] 1-based line number
        # @param word_index [Integer] 0-based word index within line
        # @param start_col [Integer] 0-based start column
        # @param end_col [Integer] 0-based end column (exclusive)
        def initialize(content, line_number:, word_index:, start_col:, end_col:)
          @content = content
          @word_index = word_index

          location = AstNode::Location.new(
            start_line: line_number,
            end_line: line_number,
            start_column: start_col,
            end_column: end_col
          )

          super(slice: content, location: location)
        end

        # TreeHaver::Node protocol: type
        # @return [String] "word_node"
        def type
          'word_node'
        end

        # Generate a signature for this word node.
        # The signature is used for matching words across template/destination.
        #
        # @return [Array] Signature array [:word, content]
        def signature
          [:word, @content]
        end

        # Get normalized content (the word itself for words)
        # @return [String]
        def normalized_content
          @content
        end

        # Get the 1-based line number
        # @return [Integer]
        def line_number
          location.start_line
        end

        # Get start column (0-based)
        # @return [Integer]
        def start_col
          location.start_column
        end

        # Get end column (0-based, exclusive)
        # @return [Integer]
        def end_col
          location.end_column
        end

        # Check equality with another WordNode
        #
        # @param other [WordNode] Other node to compare
        # @return [Boolean] True if content matches
        def ==(other)
          other.is_a?(WordNode) && @content == other.content
        end

        alias eql? ==

        # Hash code for use in Hash keys
        #
        # @return [Integer] Hash code
        def hash
          @content.hash
        end

        # String representation for debugging
        #
        # @return [String] Debug representation
        def inspect
          "#<WordNode #{@content.inspect} line=#{line_number} col=#{start_col}..#{end_col}>"
        end

        # Convert to string (returns content)
        #
        # @return [String] Word content
        def to_s
          @content
        end
      end
    end
  end
end
