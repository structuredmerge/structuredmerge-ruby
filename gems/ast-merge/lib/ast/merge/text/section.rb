# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Represents a named section within text content.
      #
      # Sections are logical units of text that can be matched and merged
      # independently. For example, in Markdown, sections might be delimited by
      # headings; in plain text, sections might be delimited by comment markers.
      #
      # This is used for text-based splitting of leaf node content, NOT for
      # AST-level node classification (see SectionTyping for that).
      #
      # @example A Markdown section
      #   Section.new(
      #     name: "Installation",
      #     header: "## Installation\n",
      #     body: "Install the gem...\n",
      #     start_line: 10,
      #     end_line: 25,
      #     metadata: { heading_level: 2 }
      #   )
      #
      # @api public
      Section = Struct.new(
        # @return [String, Symbol] Unique identifier for matching sections
        #   (e.g., heading text, comment marker, :preamble for content before first section)
        :name,

        # @return [String, nil] Header content (heading line, comment marker, etc.)
        :header,

        # @return [String] The section body content
        :body,

        # @return [Integer, nil] 1-indexed start line in the original content
        :start_line,

        # @return [Integer, nil] 1-indexed end line in the original content
        :end_line,

        # @return [Hash, nil] Optional metadata for splitter-specific information
        #   (e.g., { heading_level: 2 }, { marker_type: :comment })
        :metadata,
        keyword_init: true
      ) do
        # Returns the line range covered by this section.
        #
        # @return [Range, nil] The range from start_line to end_line (inclusive)
        def line_range
          return unless start_line && end_line

          start_line..end_line
        end

        # Returns the number of lines this section spans.
        #
        # @return [Integer, nil] The number of lines
        def line_count
          return unless start_line && end_line

          end_line - start_line + 1
        end

        # Reconstructs the full section text including header.
        #
        # @return [String] The complete section with header and body
        def full_text
          result = +''
          result << header.to_s if header
          result << body.to_s
          result
        end

        # Check if this is the preamble section (content before first split point).
        #
        # @return [Boolean] true if this is the preamble
        def preamble?
          name == :preamble
        end

        # Normalize the section name for matching.
        # Strips whitespace, downcases, and normalizes spaces.
        #
        # @return [String] Normalized name for matching
        def normalized_name
          return '' if name.nil?
          return name.to_s if name.is_a?(Symbol)

          name.to_s.strip.downcase.gsub(/\s+/, ' ')
        end
      end
    end
  end
end
