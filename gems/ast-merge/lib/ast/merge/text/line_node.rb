# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Represents a line of text in the text-based AST.
      # Lines are top-level nodes, with words as nested children.
      #
      # Inherits from AstNode (SyntheticNode) to implement the TreeHaver::Node
      # protocol, making it compatible with all tree_haver-based merge operations.
      #
      # @example
      #   line = LineNode.new("Hello world!", line_number: 1)
      #   line.content       # => "Hello world!"
      #   line.words.size    # => 2
      #   line.signature     # => [:line, "Hello world!"]
      #   line.type          # => "line_node" (TreeHaver protocol)
      #   line.text          # => "Hello world!" (TreeHaver protocol)
      class LineNode < AstNode
        # @return [String] The full line content (without trailing newline)
        attr_reader :content

        # @return [Array<WordNode>] Words contained in this line
        attr_reader :words

        # Initialize a new LineNode
        #
        # @param content [String] The line content (without trailing newline)
        # @param line_number [Integer] 1-based line number
        def initialize(content, line_number:)
          @content = content

          location = AstNode::Location.new(
            start_line: line_number,
            end_line: line_number,
            start_column: 0,
            end_column: content.length
          )

          super(slice: content, location: location)

          # Parse words AFTER super sets up location
          @words = parse_words
        end

        # TreeHaver::Node protocol: type
        # @return [String] "line_node"
        def type
          'line_node'
        end

        # TreeHaver::Node protocol: children
        # Returns word nodes as children
        # @return [Array<WordNode>]
        def children
          @words
        end

        # Generate a signature for this line node.
        # The signature is used for matching lines across template/destination.
        #
        # @return [Array] Signature array [:line, normalized_content]
        def signature
          [:line, normalized_content]
        end

        # Get normalized content (trimmed whitespace for comparison)
        #
        # @return [String] Whitespace-trimmed content
        def normalized_content
          @content.strip
        end

        # Check if this line is blank (empty or whitespace only)
        #
        # @return [Boolean] True if line is blank
        def blank?
          @content.strip.empty?
        end

        # Check if this line is a comment (starts with # after whitespace)
        # This is a simple heuristic for text files.
        #
        # @return [Boolean] True if line appears to be a comment
        def comment?
          @content.strip.start_with?('#')
        end

        # Get the 1-based line number
        # @return [Integer] 1-based line number
        def line_number
          location.start_line
        end

        # Get the starting line (for compatibility with AST node interface)
        #
        # @return [Integer] 1-based start line
        def start_line
          location.start_line
        end

        # Get the ending line (for compatibility with AST node interface)
        #
        # @return [Integer] 1-based end line (same as start for single line)
        def end_line
          location.end_line
        end

        # Check equality with another LineNode
        #
        # @param other [LineNode] Other node to compare
        # @return [Boolean] True if content matches exactly
        def ==(other)
          other.is_a?(LineNode) && @content == other.content
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
          "#<LineNode line=#{line_number} #{@content.inspect} words=#{@words.size}>"
        end

        # Convert to string (returns content)
        #
        # @return [String] Line content
        def to_s
          @content
        end

        private

        # Parse words from the line content using word boundaries
        #
        # @return [Array<WordNode>] Parsed word nodes
        def parse_words
          words = []
          word_index = 0

          # Match words using word boundary regex
          # This captures sequences of word characters (\w+)
          @content.scan(/\b(\w+)\b/) do |match|
            word = match[0]
            # Get the match position
            match_data = Regexp.last_match
            start_col = match_data.begin(0)
            end_col = match_data.end(0)

            words << WordNode.new(
              word,
              line_number: line_number,
              word_index: word_index,
              start_col: start_col,
              end_col: end_col
            )
            word_index += 1
          end

          words
        end
      end
    end
  end
end
