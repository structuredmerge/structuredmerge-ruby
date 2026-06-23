# frozen_string_literal: true

module Markdown
  module Merge
    # Represents a "gap" line that exists between parsed Markdown nodes.
    #
    # Markdown parsers like Markly consume certain content during parsing (like
    # link reference definitions) and don't preserve blank lines between nodes
    # in the AST. This class represents lines that fall into "gaps" between
    # parsed nodes, allowing them to be preserved during merge operations.
    #
    # Gap lines include:
    # - Blank lines between sections
    # - Link reference definitions (handled specially by LinkDefinitionNode)
    # - Any other content consumed by the parser
    #
    # @example
    #   node = GapLineNode.new("", line_number: 5)
    #   node.type      # => :gap_line
    #   node.blank?    # => true
    #   node.signature # => [:gap_line, 5, ""]
    class GapLineNode < Ast::Merge::AstNode
      # @return [String] The line content (may be empty for blank lines)
      attr_reader :content

      # @return [Integer] 1-based line number
      attr_reader :line_number

      # @return [Object, nil] The preceding structural node (for context-aware signatures)
      # This is set after integration to avoid circular dependencies during creation
      attr_accessor :preceding_node

      # @return [Array, nil] Signature of the preceding structural node when available
      attr_accessor :preceding_signature

      # Initialize a new GapLineNode
      #
      # @param content [String] The line content (without trailing newline)
      # @param line_number [Integer] 1-based line number
      def initialize(content, line_number:)
        @content = content.chomp
        @line_number = line_number
        @preceding_node = nil # Set later during integration
        @preceding_signature = nil

        location = Ast::Merge::AstNode::Location.new(
          start_line: line_number,
          end_line: line_number,
          start_column: 0,
          end_column: @content.length
        )

        super(slice: @content, location: location)
      end

      # TreeHaver::Node protocol: type
      # @return [Symbol] :gap_line
      def type
        :gap_line
      end

      # Alias for compatibility with wrapped nodes that have merge_type
      # @return [Symbol] :gap_line
      alias merge_type type

      # Generate a signature for matching gap lines.
      # Gap lines are matched by their position relative to the preceding structural node.
      # This allows blank lines after a heading in template to match blank lines after
      # the same heading in destination, even if they're on different absolute line numbers.
      #
      # For gap lines at the start of the document (no preceding node), we use line number.
      # For gap lines after a structural node, we use offset from that node's end line.
      #
      # @return [Array] Signature array
      def signature
        if @preceding_node&.respond_to?(:source_position)
          pos = @preceding_node.source_position
          preceding_end_line = pos[:end_line] if pos

          if preceding_end_line
            # Offset from preceding node's end (e.g., heading ends on line 1, gap is line 2, offset = 1)
            offset = @line_number - preceding_end_line

            context_signature = @preceding_signature || if @preceding_node.respond_to?(:type)
                                                          @preceding_node.type
                                                        else
                                                          :unknown
                                                        end

            [:gap_line_after, context_signature, offset, @content]
          else
            # Fallback if we can't get position
            [:gap_line, @line_number, @content]
          end
        else
          # No preceding node - use absolute line number (for gaps at document start)
          [:gap_line, @line_number, @content]
        end
      end

      # TreeHaver::Node protocol: source_position
      # @return [Hash] Position info for source extraction
      def source_position
        {
          start_line: @line_number,
          end_line: @line_number,
          start_column: 0,
          end_column: @content.length
        }
      end

      # TreeHaver::Node protocol: children (none)
      # @return [Array] Empty array
      def children
        []
      end

      # TreeHaver::Node protocol: text
      # @return [String] The line content
      def text
        @content
      end

      # Check if this is a blank line
      # @return [Boolean] true if line is empty or whitespace only
      def blank?
        @content.strip.empty?
      end

      # Convert to commonmark format
      # @return [String] The line with trailing newline
      def to_commonmark
        "#{@content}\n"
      end

      # For debugging
      def inspect
        "#<#{self.class.name} line=#{@line_number} content=#{@content.inspect}>"
      end
    end
  end
end
