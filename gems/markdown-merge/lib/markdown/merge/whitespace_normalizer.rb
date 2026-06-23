# frozen_string_literal: true

module Markdown
  module Merge
    # Normalizes whitespace in markdown documents.
    #
    # Supports multiple normalization modes:
    # - `:basic` (or `true`) - Collapse excessive blank lines (3+ → 2)
    # - `:link_refs` - Also remove blank lines between consecutive link reference definitions
    # - `:strict` - All of the above normalizations
    #
    # Uses {LinkParser} for detecting link reference definitions, which supports:
    # - Standard definitions: `[label]: url`
    # - Definitions with titles: `[label]: url "title"`
    # - Angle-bracketed URLs: `[label]: <url>`
    # - Emoji in labels: `[🎨logo]: url`
    #
    # @example Basic normalization (default)
    #   content = "Hello\n\n\n\nWorld"
    #   normalized = WhitespaceNormalizer.normalize(content)
    #   # => "Hello\n\nWorld"
    #
    # @example With link_refs mode
    #   content = "[link1]: url1\n\n[link2]: url2"
    #   normalized = WhitespaceNormalizer.normalize(content, mode: :link_refs)
    #   # => "[link1]: url1\n[link2]: url2"
    #
    # @example With problem tracking
    #   normalizer = WhitespaceNormalizer.new(content, mode: :link_refs)
    #   result = normalizer.normalize
    #   normalizer.problems.by_category(:link_ref_spacing)
    #
    class WhitespaceNormalizer
      # Valid normalization modes
      MODES = %i[basic link_refs strict].freeze

      # @return [String] The original content
      attr_reader :content

      # @return [Symbol] The normalization mode
      attr_reader :mode

      # @return [DocumentProblems] Problems found during normalization
      attr_reader :problems

      class << self
        # Normalize whitespace in content (class method for convenience).
        #
        # @param content [String] Content to normalize
        # @param mode [Symbol, Boolean] Normalization mode (:basic, :link_refs, :strict, or true for :basic)
        # @return [String] Normalized content
        def normalize(content, mode: :basic)
          new(content, mode: mode).normalize
        end
      end

      # Initialize a new normalizer.
      #
      # @param content [String] Content to normalize
      # @param mode [Symbol, Boolean] Normalization mode (:basic, :link_refs, :strict, or true for :basic)
      def initialize(content, mode: :basic)
        @content = content
        @mode = normalize_mode(mode)
        @problems = DocumentProblems.new
        @link_parser = LinkParser.new
      end

      # Normalize whitespace based on the configured mode.
      #
      # @return [String] Normalized content
      def normalize
        result = content.dup

        # Always collapse excessive blank lines (3+ → 2)
        result = collapse_excessive_blank_lines(result)

        # Remove blank lines between link refs if mode requires it
        result = remove_blank_lines_between_link_refs(result) if @mode == :link_refs || @mode == :strict

        result
      end

      # Check if normalization made any changes.
      #
      # @return [Boolean] true if content had whitespace issues
      def changed?
        !@problems.empty?
      end

      # Get count of normalizations performed.
      #
      # @return [Integer] Number of whitespace issues fixed
      def normalization_count
        @problems.count
      end

      private

      # Normalize mode parameter to a symbol.
      #
      # @param mode [Symbol, Boolean] Input mode
      # @return [Symbol] Normalized mode
      def normalize_mode(mode)
        case mode
        when true
          :basic
        when false
          :basic # Still do basic normalization
        when Symbol
          raise ArgumentError, "Unknown mode: #{mode}. Valid modes: #{MODES.join(', ')}" unless MODES.include?(mode)

          mode
        else
          raise ArgumentError, "Mode must be a Symbol or Boolean, got: #{mode.class}"
        end
      end

      # Collapse 3+ consecutive newlines to 2.
      #
      # This detects runs of blank lines (empty lines) and collapses them.
      # Note: A blank line is a line containing only whitespace.
      # 3+ consecutive newlines means 2+ blank lines.
      #
      # @param text [String] Text to process
      # @return [String] Processed text
      def collapse_excessive_blank_lines(text)
        lines = text.lines
        result = []
        consecutive_blank_count = 0
        problem_start_line = nil
        line_number = 0

        lines.each do |line|
          line_number += 1

          if line.chomp.empty?
            consecutive_blank_count += 1
            # The problem starts at the line BEFORE the first blank line
            # (i.e., the line that ends with the first \n of the excessive sequence)
            problem_start_line ||= line_number - 1

            # Only add up to 1 blank line (which creates the standard paragraph gap)
            result << line if consecutive_blank_count <= 1
            # Skip adding lines when consecutive_blank_count >= 2
          else
            # Record problem if we had 2+ blank lines (which means 3+ newlines)
            # consecutive_blank_count is the count of blank lines, so >= 2 means excessive
            if consecutive_blank_count >= 2
              @problems.add(
                :excessive_whitespace,
                severity: :warning,
                line: problem_start_line,
                newline_count: consecutive_blank_count + 1, # +1 because first line ends with \n too
                collapsed_to: 2
              )
            end

            consecutive_blank_count = 0
            problem_start_line = nil
            result << line
          end
        end

        # Handle trailing blank lines
        if consecutive_blank_count >= 2
          @problems.add(
            :excessive_whitespace,
            severity: :warning,
            line: problem_start_line,
            newline_count: consecutive_blank_count + 1,
            collapsed_to: 2
          )
        end

        result.join
      end

      # Remove blank lines between consecutive link reference definitions.
      #
      # Uses {LinkParser} to detect link definitions, supporting:
      # - Standard: `[label]: url`
      # - With title: `[label]: url "title"`
      # - Angle-bracketed: `[label]: <url>`
      # - Emoji labels: `[🎨logo]: url`
      #
      # @param text [String] Text to process
      # @return [String] Processed text
      def remove_blank_lines_between_link_refs(text)
        lines = text.lines
        result = []
        i = 0

        while i < lines.length
          line = lines[i]
          result << line

          # Check if current line is a link ref definition using LinkParser
          if link_definition_line?(line)
            # Look ahead for blank lines followed by another link ref
            j = i + 1
            while j < lines.length
              next_line = lines[j]
              break unless next_line.chomp.empty?

              # Check if there's a link ref definition after the blank line(s)
              k = j + 1
              k += 1 while k < lines.length && lines[k].chomp.empty?
              break unless k < lines.length && link_definition_line?(lines[k])

              # Skip all blank lines between link refs
              blanks_skipped = k - j
              @problems.add(
                :link_ref_spacing,
                severity: :info,
                line: j + 1,
                blank_lines_removed: blanks_skipped
              )
              j = k

              # Not followed by a link ref, keep the blank line

            end
            i = j
          else
            i += 1
          end
        end

        result.join
      end

      # Check if a line is a link reference definition using LinkParser.
      #
      # @param line [String] Line to check
      # @return [Boolean] true if line is a link definition
      def link_definition_line?(line)
        # Use LinkParser to attempt parsing the line as a definition
        result = @link_parser.parse_definition_line(line.chomp)
        !result.nil?
      end
    end
  end
end
