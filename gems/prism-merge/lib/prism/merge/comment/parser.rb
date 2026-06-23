# frozen_string_literal: true

module Prism
  module Merge
    module Comment
      # Ruby-specific comment parser.
      #
      # Produces `Prism::Merge::Comment::Line` and `Prism::Merge::Comment::Block`
      # nodes instead of the generic `Ast::Merge::Comment::*` classes, enabling
      # Ruby-specific features like magic comment detection.
      #
      # @example
      #   lines = ["# frozen_string_literal: true", "", "# A comment"]
      #   nodes = Parser.parse(lines)
      #   nodes.first.contains_magic_comment? #=> true
      #
      class Parser
        # @return [Array<String>] The source lines
        attr_reader :lines

        # Initialize a new Ruby comment Parser.
        #
        # @param lines [Array<String>] Source lines
        def initialize(lines)
          @lines = lines || []
        end

        # Parse the lines into Ruby-specific comment AST.
        #
        # @return [Array<Ast::Merge::AstNode>] Parsed nodes
        def parse
          return [] if lines.empty?

          nodes = []
          current_block = []
          header_magic_comment_types = Prism::Merge::MagicCommentSupport.header_magic_comment_types_for_lines(lines)

          lines.each_with_index do |line, idx|
            line_number = idx + 1
            raw = line.to_s.chomp
            # Classification uses trailing-space-insensitive text, but parsed nodes
            # keep the raw line so merge output can preserve owned trailing spaces.
            stripped = raw.rstrip

            if stripped.empty?
              # Blank line - flush current block and add Empty
              if current_block.any?
                nodes << build_block(current_block)
                current_block = []
              end
              nodes << Ast::Merge::Comment::Empty.new(line_number: line_number, text: raw)
            elsif stripped.start_with?('#')
              # Ruby comment line
              current_block << Line.new(
                text: raw,
                line_number: line_number,
                magic_comment_type: header_magic_comment_types[line_number]
              )
            else
              # Non-comment content (shouldn't happen in comment-only files)
              if current_block.any?
                nodes << build_block(current_block)
                current_block = []
              end
              # Add as generic line
              nodes << Ast::Merge::Comment::Line.new(
                text: raw,
                line_number: line_number,
                style: :hash_comment
              )
            end
          end

          # Flush remaining block
          nodes << build_block(current_block) if current_block.any?

          nodes
        end

        class << self
          # Class method for convenient one-shot parsing.
          #
          # @param lines [Array<String>] Source lines
          # @return [Array<Ast::Merge::AstNode>] Parsed nodes
          def parse(lines)
            new(lines).parse
          end
        end

        private

        # Build a Block from accumulated comment lines.
        #
        # @param comment_lines [Array<Line>] The comment lines
        # @return [Block] Block containing the lines
        def build_block(comment_lines)
          Block.new(children: comment_lines)
        end
      end
    end
  end
end
