# frozen_string_literal: true

require 'parslet'

module Markdown
  module Merge
    module Cleanse
      # Fixes missing blank lines between block elements in Markdown.
      #
      # Markdown best practices require blank lines between:
      # - List items and headings
      # - Thematic breaks (---) and following content
      # - HTML blocks (like </details>) and following markdown
      # - Nested list items and headings
      #
      # This class detects and fixes these issues without using a full
      # markdown parser, making it safe to use on documents that might
      # have syntax issues.
      #
      # @example Basic usage
      #   fixer = Markdown::Merge::Cleanse::BlockSpacing.new(content)
      #   if fixer.malformed?
      #     fixed_content = fixer.fix
      #   end
      #
      # @example Check specific issues
      #   fixer = Markdown::Merge::Cleanse::BlockSpacing.new(content)
      #   fixer.issues.each do |issue|
      #     puts "Line #{issue[:line]}: #{issue[:type]}"
      #   end
      #
      class BlockSpacing
        # Patterns for block elements that should have blank lines after them
        THEMATIC_BREAK = /\A\s*(?:---+|\*\*\*+|___+)\s*\z/
        HEADING = /\A\s*\#{1,6}\s+/
        LIST_ITEM = /\A\s*(?:[-*+]|\d+\.)\s+/
        HTML_CLOSE_TAG = %r{\A\s*</[a-zA-Z][a-zA-Z0-9]*>\s*\z}
        HTML_OPEN_TAG = /\A\s*<[a-zA-Z][a-zA-Z0-9]*(?:\s|>)/
        HTML_ANY_TAG = %r{\A\s*</?[a-zA-Z]}
        LINK_REF_DEF = /\A\s*\[[^\]]+\]:\s*/

        # Block-level HTML elements that can span multiple lines
        # These create a context where we shouldn't insert blank lines
        HTML_BLOCK_ELEMENTS = %w[
          ul
          ol
          li
          dl
          dt
          dd
          div
          table
          thead
          tbody
          tfoot
          tr
          th
          td
          blockquote
          pre
          figure
          figcaption
          details
          summary
          section
          article
          aside
          nav
          header
          footer
          main
          address
          form
          fieldset
        ].freeze

        # Pattern to match opening block-level HTML tags
        HTML_BLOCK_OPEN = /\A\s*<(#{HTML_BLOCK_ELEMENTS.join('|')})(?:\s|>)/i

        # Pattern to match closing block-level HTML tags
        HTML_BLOCK_CLOSE = %r{\A\s*</(#{HTML_BLOCK_ELEMENTS.join('|')})>}i

        # HTML elements that contain markdown content (not HTML content)
        # These should have blank lines before their closing tags
        MARKDOWN_CONTAINER_ELEMENTS = %w[details].freeze

        # Pattern to match closing tags for markdown containers
        MARKDOWN_CONTAINER_CLOSE = %r{\A\s*</(#{MARKDOWN_CONTAINER_ELEMENTS.join('|')})>}i

        # Markdown content: anything that's not blank, not HTML, and not a link ref def
        MARKDOWN_CONTENT = lambda { |line|
          stripped = line.strip
          return false if stripped.empty?
          return false if stripped.start_with?('<')
          return false if line.match?(LINK_REF_DEF)

          true
        }

        # @return [String] The original content
        attr_reader :source

        # @return [Array<Hash>] Issues found
        attr_reader :issues

        # Initialize a new BlockSpacing fixer.
        #
        # @param source [String] The markdown content to analyze
        def initialize(source)
          @source = source
          @issues = []
          analyze
        end

        # Check if the content has block spacing issues.
        #
        # @return [Boolean] true if issues were found
        def malformed?
          @issues.any?
        end

        # Get the count of issues found.
        #
        # @return [Integer] number of issues
        def issue_count
          @issues.size
        end

        # Fix the block spacing issues.
        #
        # @return [String] Content with blank lines added where needed
        def fix
          return source unless malformed?

          lines = source.lines
          result = []
          insertions = @issues.map { |i| i[:line] }.to_set

          lines.each_with_index do |line, idx|
            result << line
            # If this line needs a blank line after it, add one
            result << "\n" if insertions.include?(idx + 1) && !line.strip.empty? # issues use 1-based line numbers
          end

          result.join
        end

        private

        def analyze
          lines = source.lines
          return if lines.empty?

          # Track depth of block-level HTML elements
          # When depth > 0, we're inside an HTML block and shouldn't add blank lines
          html_block_depth = 0

          lines.each_with_index do |line, idx|
            next_line = lines[idx + 1]
            prev_line = idx.positive? ? lines[idx - 1] : nil

            # Special case: closing tags for markdown containers like </details>
            # These contain markdown content, so we need blank lines before them
            # even when inside an HTML block
            is_markdown_container_close = line.match?(MARKDOWN_CONTAINER_CLOSE)

            # Check for issues BEFORE updating depth
            if html_block_depth <= 0
              # Check for issues that need blank line AFTER current line
              if next_line && !next_line.strip.empty?
                check_thematic_break(line, next_line, idx)
                check_list_before_heading(line, next_line, idx)
                check_html_close_before_markdown(line, next_line, idx)
              end

              # Check for issues that need blank line BEFORE current line
              check_markdown_before_html(prev_line, line, idx) if prev_line && !prev_line.strip.empty?
            end

            # Special case: always check for blank line before </details> etc.
            # because they contain markdown content
            if is_markdown_container_close && prev_line && !prev_line.strip.empty?
              check_markdown_before_html(prev_line, line, idx)
            end

            # Update HTML block depth AFTER checking for issues
            # Count opening block-level tags
            html_block_depth += 1 if line.match?(HTML_BLOCK_OPEN)

            # Check for closing block-level tags
            line.scan(HTML_BLOCK_CLOSE) do
              html_block_depth -= 1 if html_block_depth.positive?
            end
          end
        end

        def check_thematic_break(line, next_line, idx)
          return unless line.match?(THEMATIC_BREAK)
          return if next_line.strip.empty?

          @issues << {
            type: :thematic_break_needs_blank,
            line: idx + 1,
            description: 'Thematic break should be followed by blank line'
          }
        end

        def check_list_before_heading(line, next_line, idx)
          return unless line.match?(LIST_ITEM)
          return unless next_line.match?(HEADING)

          @issues << {
            type: :list_before_heading,
            line: idx + 1,
            description: 'List item should be followed by blank line before heading'
          }
        end

        def check_html_close_before_markdown(line, next_line, idx)
          return unless line.match?(HTML_CLOSE_TAG)
          # Next line is markdown (heading, list, paragraph start, etc.)
          # but not HTML or blank
          return if next_line.match?(/\A\s*</)
          return if next_line.match?(LINK_REF_DEF)

          @issues << {
            type: :html_before_markdown,
            line: idx + 1,
            description: 'HTML close tag should be followed by blank line before markdown'
          }
        end

        def check_markdown_before_html(prev_line, line, idx)
          # Current line is HTML (open or close tag)
          return unless line.match?(HTML_ANY_TAG)
          # Previous line is markdown content (not HTML, not blank, not link ref)
          return unless MARKDOWN_CONTENT.call(prev_line)

          @issues << {
            type: :markdown_before_html,
            line: idx, # Insert blank line BEFORE this line (so after prev_line)
            description: 'Markdown content should be followed by blank line before HTML'
          }
        end
      end
    end
  end
end
