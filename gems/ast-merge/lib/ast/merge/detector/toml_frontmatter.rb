# frozen_string_literal: true

module Ast
  module Merge
    module Detector
      ##
      # Detects TOML frontmatter at the beginning of a document.
      #
      # TOML frontmatter is delimited by `+++` at the start and end,
      # and must begin on the first line of the document (optionally
      # preceded by a UTF-8 BOM). This format is commonly used by
      # Hugo and other static site generators.
      #
      # @example TOML frontmatter
      #   +++
      #   title = "My Document"
      #   author = "Jane Doe"
      #   +++
      #
      # @example Usage
      #   detector = TomlFrontmatter.new
      #   regions = detector.detect_all(markdown_source)
      #   # => [#<Region type=:toml_frontmatter content="title = \"My Document\"\n...">]
      #
      # @see YamlFrontmatter For YAML frontmatter detection
      #
      class TomlFrontmatter < Base
        ##
        # Pattern for detecting TOML frontmatter.
        # - Must start at beginning of document (or after BOM)
        # - Opening delimiter is `+++` followed by optional whitespace and newline
        # - Content is captured (non-greedy)
        # - Closing delimiter is `+++` at start of line, followed by optional whitespace and newline/EOF
        #
        FRONTMATTER_PATTERN = /\A(?:\xEF\xBB\xBF)?(\+\+\+[ \t]*\r?\n)(.*?)(^\+\+\+[ \t]*(?:\r?\n|\z))/m

        ##
        # @return [Symbol] the type identifier for TOML frontmatter regions
        #
        def region_type
          :toml_frontmatter
        end

        ##
        # Detects TOML frontmatter at the beginning of the document.
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
          start_line = 1

          # Count total newlines in the full match to determine end line
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
              metadata: { format: :toml }
            )
          ]
        end
      end
    end
  end
end
