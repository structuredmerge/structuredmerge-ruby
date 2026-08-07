# frozen_string_literal: true

require 'parslet'

module Markdown
  module Merge
    module Cleanse
      # Parslet-based parser for fixing condensed Markdown link reference definitions.
      #
      # == The Problem
      #
      # This class fixes **corrupted Markdown files** where link reference definitions
      # that were originally on separate lines got smashed together by having their
      # separating newlines removed.
      #
      # A previous bug in ast-merge caused link reference definitions at the bottom
      # of Markdown files to be merged together into a single line without newlines
      # or whitespace between them.
      #
      # == Corruption Patterns
      #
      # Two types of corruption are detected and fixed:
      #
      # 1. **Multiple definitions condensed on one line:**
      #    - Corrupted: `[label1]: url1[label2]: url2`
      #    - Fixed: Each definition on its own line
      #
      # 2. **Content followed by definition without newline:**
      #    - Corrupted: `Some text or URL[label]: url`
      #    - Fixed: Newline inserted before `[label]:`
      #
      # @example Condensed definitions (Pattern 1)
      #   # Before (corrupted):
      #   "[⛳liberapay-img]: https://example.com/img.svg[⛳liberapay]: https://example.com"
      #
      #   # After (fixed):
      #   "[⛳liberapay-img]: https://example.com/img.svg\n[⛳liberapay]: https://example.com"
      #
      # @example Content before definition (Pattern 2)
      #   # Before (corrupted):
      #   "https://donate.codeberg.org/[🤝contributing]: CONTRIBUTING.md"
      #
      #   # After (fixed):
      #   "https://donate.codeberg.org/\n[🤝contributing]: CONTRIBUTING.md"
      #
      # == How It Works
      #
      # The parser uses a **PEG grammar** (via Parslet) to:
      # - Recognize link reference definition patterns: `[label]: url`
      # - Detect when multiple definitions are on the same line
      # - Detect when content precedes a definition without newline separation
      # - Parse and reconstruct definitions with proper newlines
      #
      # **Why PEG?** The previous regex-based implementation had potential ReDoS
      # (Regular Expression Denial of Service) vulnerabilities due to complex
      # lookahead/lookbehind patterns. PEG parsers are linear-time and immune to
      # ReDoS attacks.
      #
      # The grammar extends the pattern from {LinkParser::DefinitionGrammar} but
      # handles the case where definitions are concatenated without separators.
      #
      # @example Basic usage
      #   parser = Markdown::Merge::Cleanse::CondensedLinkRefs.new(condensed_text)
      #   fixed_text = parser.expand
      #
      # @example Check if text contains condensed refs
      #   parser = Markdown::Merge::Cleanse::CondensedLinkRefs.new(text)
      #   parser.condensed? # => true/false
      #
      # @example Process a file
      #   content = File.read("README.md")
      #   parser = Markdown::Merge::Cleanse::CondensedLinkRefs.new(content)
      #   if parser.condensed?
      #     File.write("README.md", parser.expand)
      #   end
      #
      # @example Get parsed definitions
      #   parser = Markdown::Merge::Cleanse::CondensedLinkRefs.new(condensed_text)
      #   parser.definitions.each do |defn|
      #     puts "#{defn[:label]} => #{defn[:url]}"
      #   end
      #
      # @see LinkParser For parsing properly-formatted link definitions
      # @api public
      class CondensedLinkRefs
        # Grammar for parsing multiple condensed link reference definitions.
        #
        # This grammar handles the specific bug pattern where link definitions
        # are concatenated without newlines or whitespace between them.
        #
        # Key insight: A bare URL ends at any character that's not valid in a URL.
        # The `[` character that starts the next definition is NOT valid in a bare URL,
        # so we can use it as the delimiter.
        #
        # This PEG grammar is linear-time and cannot have polynomial backtracking,
        # eliminating ReDoS vulnerabilities.
        #
        # @api private
        class CondensedDefinitionsGrammar < Parslet::Parser
          rule(:space) { match('[ \t]') }
          rule(:spaces) { space.repeat(1) }
          rule(:spaces?) { space.repeat }
          rule(:newline) { match('[\r\n]') }
          rule(:newlines?) { newline.repeat }

          # Bracket content: handles nested brackets recursively
          # Same as LinkParser::DefinitionGrammar
          rule(:bracket_content) do
            (
              str('[') >> bracket_content.maybe >> str(']') |
              str(']').absent? >> any
            ).repeat
          end

          rule(:label) { str('[') >> bracket_content.as(:label) >> str(']') }

          # URL characters - everything except whitespace, >, and [
          # The [ is excluded because it signals the start of the next definition
          rule(:url_char) { match('[^\s>\[]') }
          rule(:bare_url) { url_char.repeat(1) }

          # Angled URLs can contain [ since they're delimited by <>
          rule(:angled_url_char) { match('[^>]') }
          rule(:angled_url) { str('<') >> angled_url_char.repeat(1) >> str('>') }

          rule(:url) { (angled_url | bare_url).as(:url) }

          # Title handling (same as LinkParser)
          rule(:title_content_double) { (str('"').absent? >> any).repeat }
          rule(:title_content_single) { (str("'").absent? >> any).repeat }
          rule(:title_content_paren) { (str(')').absent? >> any).repeat }

          rule(:title_double) { str('"') >> title_content_double.as(:title) >> str('"') }
          rule(:title_single) { str("'") >> title_content_single.as(:title) >> str("'") }
          rule(:title_paren) { str('(') >> title_content_paren.as(:title) >> str(')') }
          rule(:title) { title_double | title_single | title_paren }

          # A single definition
          rule(:definition) do
            spaces? >>
              label >>
              str(':') >>
              spaces? >>
              url >>
              (spaces >> title).maybe >>
              spaces?
          end

          # Multiple definitions, possibly with or without newlines between them
          rule(:definitions) do
            (definition.as(:definition) >> newlines?).repeat(1)
          end

          root(:definitions)
        end

        # @return [String] the input text to parse
        attr_reader :source

        # Create a new parser for the given text.
        #
        # @param source [String] the text that may contain condensed link refs
        def initialize(source)
          @source = source.to_s
          @grammar = CondensedDefinitionsGrammar.new
          @parsed = nil
          @definitions = nil
        end

        # Check if the source contains condensed link reference definitions.
        #
        # Detects patterns where link definitions are not properly separated:
        # 1. Multiple link defs on same line: `[l1]: url1[l2]: url2`
        # 2. Content followed by link def without newline: `text[label]: url`
        #
        # Uses the PEG grammar to parse and detect condensed sequences.
        #
        # @return [Boolean] true if condensed refs are detected
        def condensed?
          source.each_line do |line|
            # Pattern 1: Line contains 2+ link definitions (condensed together)
            return true if contains_multiple_definitions?(line)

            # Pattern 2: Line has content before first link definition
            # (indicates corruption where newline before def was removed)
            return true if has_content_before_definition?(line)
          end
          false
        end

        # Parse the source into individual link reference definitions that are condensed.
        #
        # This finds link refs that are part of corrupted patterns:
        # 1. Multiple refs on same line without newlines
        # 2. Content followed by ref without newline
        #
        # Uses the PEG grammar to properly parse link definitions.
        #
        # @return [Array<Hash>] Array of { label:, url:, title: (optional) }
        def definitions
          return @definitions if @definitions

          @definitions = []

          # Find all condensed sequences line by line
          source.each_line do |line|
            # Try to parse as definitions
            parsed = parse_line(line)
            next unless parsed && !parsed.empty?

            # Check if line has content before first definition
            first_bracket = line.index('[')
            has_prefix = first_bracket&.positive? && !line[0...first_bracket].strip.empty?

            # Include if: multiple definitions OR single definition with prefix
            next unless parsed.size > 1 || has_prefix

            # Extract definition info from parse tree
            parsed.each do |def_tree|
              @definitions << extract_definition(def_tree)
            end
          end

          @definitions
        end

        # Expand condensed link reference definitions to separate lines.
        #
        # Fixes only the condensed patterns (where a URL is immediately followed
        # by a new link ref definition without a newline). All other content
        # is preserved exactly as-is.
        #
        # Uses the PEG grammar to properly parse and reconstruct definitions.
        #
        # @return [String] the source with condensed link refs expanded to separate lines
        def expand
          return source unless condensed?

          lines = source.lines.map do |line|
            expand_line(line)
          end

          lines.join
        end

        # Count the number of link reference definitions in the source.
        #
        # @return [Integer] number of link ref definitions found
        def count
          definitions.size
        end

        private

        # Check if a line contains multiple link definitions (condensed).
        #
        # @param line [String] the line to check
        # @return [Boolean] true if line has 2+ definitions
        def contains_multiple_definitions?(line)
          parsed = parse_line(line)
          parsed && parsed.size > 1
        end

        # Check if a line has content before the first link definition.
        #
        # This indicates corruption where a newline was removed between
        # regular content and a link definition.
        #
        # Example: `https://example.com[label]: url` (should be on separate lines)
        #
        # @param line [String] the line to check
        # @return [Boolean] true if there's content before first `[label]:`
        def has_content_before_definition?(line)
          # Skip if no link definition pattern
          return false unless line.include?(']:')

          # Find first occurrence of [label]:
          first_bracket = line.index('[')
          return false unless first_bracket
          return false if inside_inline_code?(line, first_bracket)

          # Check if there's non-whitespace content before it
          prefix = line[0...first_bracket].strip
          return false if prefix.empty?

          # Verify what follows is actually a link definition by trying to parse
          parsed = parse_line(line)
          !parsed.nil? && !parsed.empty?
        end

        # Parse a line into link definitions using PEG grammar.
        #
        # Handles lines that may have content before the first definition.
        # For example: "https://example.com[label]: url.txt"
        #
        # @param line [String] the line to parse
        # @return [Array<Hash>, nil] array of definition parse trees, or nil if parse fails
        def parse_line(line)
          # Skip lines that don't look like link definitions
          return unless line.include?(']:')

          # First, try to find where the first link definition starts
          # Look for pattern: [anything]:
          first_bracket = line.index('[')
          return unless first_bracket
          return if inside_inline_code?(line, first_bracket)

          # Try parsing from the first bracket onward
          candidate = line[first_bracket..]

          begin
            tree = @grammar.parse(candidate)

            # Extract the definitions array from parse tree
            # Parslet returns either a single item or array
            defs = tree.is_a?(Array) ? tree : [tree]

            # Filter out non-definition nodes and return only definitions
            defs.select { |node| node.is_a?(Hash) && node.key?(:definition) }
                .map { |node| node[:definition] }
          rescue Parslet::ParseFailed
            nil
          end
        end

        # Extract definition data from a parse tree node.
        #
        # @param def_tree [Hash] the definition parse tree
        # @return [Hash] definition with :label and :url
        def extract_definition(def_tree)
          label_tree = def_tree[:label]
          url_tree = def_tree[:url]

          # Convert Parslet slices to strings
          label = label_tree.is_a?(Array) ? label_tree.map(&:to_s).join : label_tree.to_s
          url = url_tree.to_s

          {
            label: label,
            url: clean_url(url)
          }
        end

        # Expand a single line if it contains condensed definitions.
        #
        # Handles two cases:
        # 1. Multiple definitions on same line (always needs expansion)
        # 2. Single definition with content before it (needs newline before def)
        #
        # @param line [String] the line to expand
        # @return [String] expanded line with newlines between definitions
        def expand_line(line)
          parsed = parse_line(line)
          return line unless parsed && !parsed.empty?

          # Find where the first definition starts
          first_bracket = line.index('[')
          prefix = first_bracket&.positive? ? line[0...first_bracket].strip : ''

          # Case 1: Multiple definitions - always expand
          if parsed.size > 1
            definitions = parsed.map { |def_tree| reconstruct_definition(def_tree) }

            # First definition gets the prefix if present
            result = if prefix && !prefix.empty?
                       "#{prefix}\n#{definitions.join("\n")}"
                     else
                       definitions.join("\n")
                     end

            result += "\n" if line.end_with?("\n")
            return result
          end

          # Case 2: Single definition with prefix content - add newline before it
          if parsed.size == 1 && prefix && !prefix.empty?
            defn = reconstruct_definition(parsed[0])
            result = "#{prefix}\n#{defn}"
            result += "\n" if line.end_with?("\n")
            return result
          end

          # No expansion needed
          line
        end

        # Reconstruct a single definition from parse tree.
        #
        # @param def_tree [Hash] the definition parse tree
        # @return [String] reconstructed definition string
        def reconstruct_definition(def_tree)
          defn = extract_definition(def_tree)
          "[#{defn[:label]}]: #{defn[:url]}"
        end

        # Clean a URL (strip angle brackets if present).
        #
        # @param url [String] the URL to clean
        # @return [String] cleaned URL
        def clean_url(url)
          url = url.strip
          url.start_with?('<') && url.end_with?('>') ? url[1..-2] : url
        end

        def inside_inline_code?(line, index)
          line[0...index].count('`').odd?
        end
      end
    end
  end
end
