# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Parser for building comment AST from source lines.
      #
      # This parser takes an array of source lines and produces an array of
      # AstNode objects (Block, Line, Empty) that represent the structure
      # of a comment-only file or section.
      #
      # The parser is style-aware and can handle:
      # - Line comments (`#`, `//`, `--`, `;`)
      # - HTML-style comments (`<!-- ... -->`)
      # - C-style block comments (`/* ... */`)
      #
      # @example Parsing Ruby-style comments
      #   lines = ["# frozen_string_literal: true", "", "# A comment block"]
      #   parser = Parser.new(lines)
      #   nodes = parser.parse
      #   # => [Block(...), Empty(...), Block(...)]
      #
      # @example Parsing C-style block comments
      #   lines = ["/* Header comment", " * with multiple lines", " */"]
      #   parser = Parser.new(lines, style: :c_style_block)
      #   nodes = parser.parse
      #   # => [Block(raw_content: "/* Header comment\n * with multiple lines\n */")]
      #
      # @example Auto-detecting comment style
      #   lines = ["// JavaScript comment", "// continues here"]
      #   parser = Parser.new(lines, style: :auto)
      #   nodes = parser.parse
      #
      class Parser
        # @return [Array<String>] The source lines
        attr_reader :lines

        # @return [Style] The comment style configuration
        attr_reader :style

        # Initialize a new Parser.
        #
        # @param lines [Array<String>] Source lines (without trailing newlines)
        # @param style [Style, Symbol, nil] The comment style (:hash_comment, :c_style_line, etc.)
        #   Pass :auto to attempt auto-detection.
        def initialize(lines, style: nil)
          @lines = lines || []
          @style = resolve_style(style)
        end

        # Parse the lines into an AST.
        #
        # Groups contiguous comment lines into Block nodes,
        # and represents blank lines as Empty nodes.
        #
        # @return [Array<AstNode>] Array of parsed nodes
        def parse
          return [] if lines.empty?

          if style.supports_block_comments?
            parse_with_block_comments
          else
            parse_line_comments
          end
        end

        class << self
          # Parse lines as comments.
          #
          # @param lines [Array<String>] Source lines
          # @param style [Style, Symbol, nil] Comment style
          # @return [Array<AstNode>] Parsed nodes
          def parse(lines, style: nil)
            new(lines, style: style).parse
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
          when :auto
            auto_detect_style
          when Symbol
            Style.for(style)
          when nil
            Style.for(Style::DEFAULT_STYLE)
          else
            raise ArgumentError, "Invalid style: #{style.inspect}"
          end
        end

        # Auto-detect the comment style from the source lines.
        #
        # Looks at the first non-empty line to determine the style.
        #
        # @return [Style] Detected style (defaults to hash_comment)
        def auto_detect_style
          first_content = lines.find { |l| !l.to_s.strip.empty? }
          return Style.for(:hash_comment) unless first_content

          stripped = first_content.to_s.strip

          # Check each style's pattern
          Style::STYLES.each do |name, config|
            return Style.for(name) if config[:line_pattern]&.match?(stripped)
            return Style.for(name) if config[:block_start_pattern]&.match?(stripped)
          end

          # Default to hash_comment
          Style.for(:hash_comment)
        end

        # Parse lines using line-comment style (e.g., #, //, --, ;).
        #
        # Groups contiguous comment lines into Block nodes.
        #
        # @return [Array<AstNode>] Parsed nodes
        def parse_line_comments
          nodes = []
          current_block = []

          lines.each_with_index do |line, idx|
            line_number = idx + 1
            # Parsing treats trailing-space-only differences as non-semantic for
            # comment/blank classification. Raw blank lines are still preserved.
            stripped = line.to_s.rstrip

            if stripped.empty?
              # Blank line - flush current block and add Empty
              if current_block.any?
                nodes << build_block(current_block)
                current_block = []
              end
              nodes << Empty.new(line_number: line_number, text: line.to_s)
            elsif style.match_line?(stripped)
              # Comment line - add to current block
              current_block << Line.new(
                text: line.to_s,
                line_number: line_number,
                style: style
              )
            else
              # Non-comment, non-empty line
              # Flush current block and treat this as content
              if current_block.any?
                nodes << build_block(current_block)
                current_block = []
              end
              # Add as a single line (non-comment content in a comment-only context)
              nodes << Line.new(
                text: line.to_s,
                line_number: line_number,
                style: Style.for(:hash_comment) # Fallback style for non-comment lines
              )
            end
          end

          # Flush remaining block
          nodes << build_block(current_block) if current_block.any?

          nodes
        end

        # Parse lines that may contain block comments (e.g., /* ... */, <!-- ... -->).
        #
        # Handles both single-line and multi-line block comments.
        #
        # @return [Array<AstNode>] Parsed nodes
        def parse_with_block_comments
          nodes = []
          current_block_lines = []
          in_block_comment = false

          lines.each_with_index do |line, idx|
            line_number = idx + 1
            # Block-comment detection is trailing-space-insensitive; emitted raw text
            # comes from the original line content, not this classification string.
            stripped = line.to_s.rstrip

            if stripped.empty? && !in_block_comment
              # Blank line outside block comment
              if current_block_lines.any?
                nodes << build_raw_block(current_block_lines)
                current_block_lines = []
              end
              nodes << Empty.new(line_number: line_number, text: line.to_s)
            elsif style.match_block_start?(stripped)
              # Starting a block comment
              # Flush any pending content first
              if current_block_lines.any? && !in_block_comment
                nodes << build_raw_block(current_block_lines)
                current_block_lines = []
              end

              current_block_lines << { line: line.to_s, line_number: line_number }
              in_block_comment = true

              # Check if block ends on same line
              if style.match_block_end?(stripped)
                nodes << build_raw_block(current_block_lines)
                current_block_lines = []
                in_block_comment = false
              end
            elsif in_block_comment
              # Inside a block comment
              current_block_lines << { line: line.to_s, line_number: line_number }

              # Check if block ends
              if style.match_block_end?(stripped)
                nodes << build_raw_block(current_block_lines)
                current_block_lines = []
                in_block_comment = false
              end
            elsif style.supports_line_comments? && style.match_line?(stripped)
              # Line comment (in a style that supports both line and block)
              current_block_lines << { line: line.to_s, line_number: line_number }
            else
              # Other content - flush and add as-is
              if current_block_lines.any?
                nodes << build_raw_block(current_block_lines)
                current_block_lines = []
              end
              nodes << Line.new(
                text: line.to_s,
                line_number: line_number,
                style: style
              )
            end
          end

          # Flush remaining block
          nodes << build_raw_block(current_block_lines) if current_block_lines.any?

          nodes
        end

        # Build a Block from accumulated line comment nodes.
        #
        # @param comment_lines [Array<Line>] The comment lines
        # @return [Block] Block containing the lines
        def build_block(comment_lines)
          Block.new(children: comment_lines, style: style)
        end

        # Build a Block from accumulated raw lines (for block-style comments).
        #
        # @param line_data [Array<Hash>] Array of { line:, line_number: } hashes
        # @return [Block] Block with raw content
        def build_raw_block(line_data)
          raw_content = line_data.map { |d| d[:line] }.join("\n")
          start_line = line_data.first[:line_number]
          end_line = line_data.last[:line_number]

          Block.new(
            raw_content: raw_content,
            start_line: start_line,
            end_line: end_line,
            style: style
          )
        end
      end
    end
  end
end
