# frozen_string_literal: true

require 'parslet'

module Markdown
  module Merge
    module Cleanse
      # Parslet-based parser for fixing malformed fenced code blocks in Markdown.
      #
      # == The Problem
      #
      # This class fixes **improperly formatted fenced code blocks** where there is
      # unwanted whitespace between the fence markers (``` or ~~~) and the language
      # identifier.
      #
      # A bug in ast-merge (or its dependencies) caused fenced code blocks to be
      # rendered with a space between the fence markers and the language identifier.
      #
      # == Bug Pattern
      #
      # CommonMark and most Markdown parsers expect NO space between fence and language:
      # - **Correct:** ` ```ruby` or ` ~~~python`
      # - **Incorrect:** ` ``` ruby` or ` ~~~ python` (extra space)
      #
      # The extra space can cause:
      # - Syntax highlighting to fail
      # - The language identifier to be ignored
      # - Rendering issues in various Markdown processors
      #
      # @example Malformed (buggy) input
      #   "``` console\nsome code\n```"
      #
      # @example Fixed output
      #   "```console\nsome code\n```"
      #
      # == Scope
      #
      # This fixer handles:
      # - **Any indentation level** (0+ spaces before fence)
      #   - Top-level: ` ```ruby`
      #   - In lists: `    ```python` (4 spaces)
      # - **Both fence types:** backticks (```) and tildes (~~~)
      # - **Any fence length:** 3+ markers (````, ~~~~~, etc.)
      #
      # == How It Works
      #
      # The parser uses a **PEG grammar** (via Parslet) to:
      # - Detect fence opening lines with optional indentation
      # - Identify spacing between fence and language identifier
      # - Track opening/closing fence pairs to avoid false positives
      # - Reconstruct fences with proper formatting (no space)
      #
      # **Why PEG?** The previous regex-based implementation used patterns like
      # `([ \t]*)` which can cause polynomial backtracking (ReDoS vulnerability)
      # when processing malicious input with many tabs/spaces. PEG parsers are
      # linear-time and immune to ReDoS attacks.
      #
      # @example Basic usage
      #   parser = Markdown::Merge::Cleanse::CodeFenceSpacing.new(content)
      #   fixed_content = parser.fix
      #
      # @example Check if content has malformed fences
      #   parser = Markdown::Merge::Cleanse::CodeFenceSpacing.new(content)
      #   parser.malformed? # => true/false
      #
      # @example Process a file
      #   content = File.read("README.md")
      #   parser = Markdown::Merge::Cleanse::CodeFenceSpacing.new(content)
      #   if parser.malformed?
      #     File.write("README.md", parser.fix)
      #   end
      #
      # @example Get details about code blocks
      #   parser = Markdown::Merge::Cleanse::CodeFenceSpacing.new(content)
      #   parser.code_blocks.each do |block|
      #     puts "#{block[:fence]}#{block[:language]}: malformed=#{block[:malformed]}"
      #   end
      #
      # @api public
      class CodeFenceSpacing
        # Grammar for parsing fenced code blocks with PEG parser.
        #
        # Recognizes:
        # - Any amount of indentation (handles nested lists)
        # - Backtick fences (```) and tilde fences (~~~)
        # - Optional info string (language identifier)
        # - Properly handles spacing issues
        #
        # This PEG grammar is linear-time and cannot have polynomial backtracking,
        # eliminating ReDoS vulnerabilities.
        #
        # @api private
        class CodeFenceGrammar < Parslet::Parser
          # Any amount of indentation (handles code blocks in lists)
          # Captured as string, not array
          rule(:indent) { match('[ ]').repeat }

          # Fence markers - 3+ backticks or tildes
          rule(:backtick) { str('`') }
          rule(:tilde) { str('~') }
          rule(:backtick_fence) { backtick.repeat(3, nil) }
          rule(:tilde_fence) { tilde.repeat(3, nil) }
          rule(:fence) { backtick_fence | tilde_fence }

          # Whitespace after fence (the bug we're fixing)
          rule(:space) { match('[ \t]') }
          rule(:spaces) { space.repeat(1) }
          rule(:spaces?) { space.repeat }

          # Info string (language identifier + optional attributes)
          # Cannot contain backticks or tildes per CommonMark
          rule(:info_char) { match('[^\r\n`~]') }
          rule(:info_string) { info_char.repeat(1) }

          # Line ending
          rule(:line_end) { str("\r").maybe >> str("\n").maybe >> any.absent? }

          # Fence line with optional indentation, optional spacing, optional info
          # Capture: indent (raw), fence (as :fence), spacing (as :spacing), info (as :info)
          rule(:fence_line) do
            indent.as(:indent) >> fence.as(:fence) >> spaces?.as(:spacing) >> info_string.maybe.as(:info) >> line_end
          end

          root(:fence_line)
        end

        # @return [String] the input text to parse
        attr_reader :source

        # Create a new parser for the given text.
        #
        # @param source [String] the text that may contain malformed code fences
        def initialize(source)
          @source = source.to_s
          @grammar = CodeFenceGrammar.new
          @code_blocks = nil
        end

        # Check if the source contains malformed fenced code blocks.
        #
        # Detects the pattern where there's whitespace between the fence
        # markers and the language identifier.
        #
        # @return [Boolean] true if malformed fences are detected
        def malformed?
          code_blocks.any? { |block| block[:malformed] }
        end

        # Parse and return information about all fenced code blocks.
        #
        # Only returns opening fences (not closing fences).
        #
        # @return [Array<Hash>] Array of code block info
        #   - :indent [String] The indentation before the fence
        #   - :fence [String] The fence markers (e.g., "```" or "~~~")
        #   - :language [String, nil] The language identifier
        #   - :spacing [String] Any spacing between fence and language
        #   - :malformed [Boolean] Whether this block has improper spacing
        #   - :line_number [Integer] Line number where block starts (1-based)
        #   - :original [String] The original opening fence line
        def code_blocks
          return @code_blocks if @code_blocks

          @code_blocks = []
          line_number = 0
          in_code_block = false
          current_fence_char = nil

          source.each_line do |line|
            line_number += 1

            # Try to parse as fence line using PEG grammar
            parsed = parse_fence_line(line)
            next unless parsed

            fence = parsed[:fence]
            fence_char = fence[0]
            spacing = parsed[:spacing] || ''
            info = parsed[:info] || ''
            indent = parsed[:indent] || ''

            # Closing fence: matches current fence type and has no info
            if in_code_block && fence_char == current_fence_char && info.empty?
              in_code_block = false
              current_fence_char = nil
              next
            end

            # Opening fence
            in_code_block = true
            current_fence_char = fence_char

            # Extract just the language (first word of info string)
            language = info.strip.split(/\s+/).first
            language = nil if language&.empty?

            @code_blocks << {
              indent: indent,
              fence: fence,
              language: language,
              info_string: info.strip,
              spacing: spacing,
              malformed: !spacing.empty? && !language.nil?,
              line_number: line_number,
              original: line.chomp
            }
          end

          @code_blocks
        end

        # Fix malformed fenced code blocks by removing improper spacing.
        #
        # @return [String] the source with code fences fixed
        def fix
          return source unless malformed?

          result = source.dup

          # Process line by line, fixing malformed fences
          lines = result.lines
          fixed_lines = lines.map do |line|
            fix_fence_line(line)
          end

          fixed_lines.join
        end

        # Count the number of malformed code blocks.
        #
        # @return [Integer] number of malformed fences found
        def malformed_count
          code_blocks.count { |block| block[:malformed] }
        end

        # Count the total number of code blocks.
        #
        # @return [Integer] total number of fenced code blocks
        def count
          code_blocks.size
        end

        private

        # Parse a single line as a fence using PEG grammar.
        #
        # @param line [String] the line to parse
        # @return [Hash, nil] parsed fence data or nil if not a fence
        def parse_fence_line(line)
          tree = @grammar.parse(line)

          # Convert Parslet tree to simple hash
          # Note: Parslet returns [] for empty repeats, we convert to empty string
          indent_val = tree[:indent]
          indent_str = indent_val.is_a?(Array) ? indent_val.join : indent_val.to_s

          spacing_val = tree[:spacing]
          spacing_str = spacing_val.is_a?(Array) ? spacing_val.join : spacing_val.to_s

          info_val = tree[:info]
          info_str = if info_val.is_a?(Array)
                       info_val.join
                     else
                       (info_val ? info_val.to_s : '')
                     end

          {
            indent: indent_str,
            fence: tree[:fence].to_s,
            spacing: spacing_str,
            info: info_str
          }
        rescue Parslet::ParseFailed
          nil
        end

        # Fix a single line if it's a malformed fence.
        #
        # @param line [String] the line to potentially fix
        # @return [String] the fixed line (or original if not malformed)
        def fix_fence_line(line)
          parsed = parse_fence_line(line)
          return line unless parsed

          # Only fix if there's spacing AND info string
          return line if parsed[:spacing].empty? || parsed[:info].empty?

          # Reconstruct: indent + fence + info (no spacing)
          "#{parsed[:indent]}#{parsed[:fence]}#{parsed[:info]}\n"
        end
      end
    end
  end
end
