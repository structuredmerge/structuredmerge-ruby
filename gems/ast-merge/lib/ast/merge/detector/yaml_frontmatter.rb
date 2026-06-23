# frozen_string_literal: true

module Ast
  module Merge
    module Detector
      ##
      # Detects YAML frontmatter at the beginning of a document.
      #
      # YAML frontmatter is delimited by `---` at the start and end,
      # and must begin on the first line of the document (optionally
      # preceded by a UTF-8 BOM).
      #
      # @example YAML frontmatter
      #   ---
      #   title: My Document
      #   author: Jane Doe
      #   ---
      #
      # @example Usage
      #   detector = YamlFrontmatter.new
      #   regions = detector.detect_all(markdown_source)
      #   # => [#<Region type=:yaml_frontmatter content="title: My Document\n...">]
      #
      # @see TomlFrontmatter For TOML frontmatter detection
      #
      class YamlFrontmatter < Base
        ##
        # Pattern for detecting YAML frontmatter.
        # - Must start at beginning of document (or after BOM)
        # - Opening delimiter is `---` followed by optional whitespace and newline
        # - Content is captured (non-greedy)
        # - Closing delimiter is `---` at start of line, followed by optional whitespace and newline/EOF
        #
        FRONTMATTER_PATTERN = /\A(?:\xEF\xBB\xBF)?(---[ \t]*\r?\n)(.*?)(^---[ \t]*(?:\r?\n|\z))/m

        ##
        # @return [Symbol] the type identifier for YAML frontmatter regions
        #
        def region_type
          :yaml_frontmatter
        end

        ##
        # Detects YAML frontmatter at the beginning of the document.
        #
        # @param source [String] the source document to scan
        # @return [Array<Region>] array containing at most one Region for frontmatter
        #
        def detect_all(source)
          return [] if source.nil? || source.empty?

          match = source.match(FRONTMATTER_PATTERN)
          return [] unless match

          opening_delimiter = match[1]
          content = match[2]
          closing_delimiter = match[3]

          # Calculate line numbers
          # Frontmatter starts at line 1 (or after BOM)
          start_line = 1

          # Simplify: count total newlines in the full match to determine end line
          full_match = match[0]
          total_newlines = full_match.count("\n")
          end_line = total_newlines + (full_match.end_with?("\n") ? 0 : 1)

          [
            Region.new(
              type: region_type,
              content: content,
              start_line: start_line,
              end_line: end_line,
              delimiters: [opening_delimiter.strip, closing_delimiter.strip],
              metadata: { format: :yaml }
            )
          ]
        end
      end
    end
  end
end
