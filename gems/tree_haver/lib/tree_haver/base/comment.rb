# frozen_string_literal: true

module TreeHaver
  module Base
    # Base class for backend comment wrappers.
    #
    # This defines the parser-facing contract for normalized comment wrappers in
    # TreeHaver. Backends that can expose comment objects should subclass this and
    # implement text/type/location accessors using their native parser data.
    class Comment
      ATTACHMENT_HINTS = %i[leading inline trailing].freeze

      # The underlying backend-specific comment object.
      # @return [Object]
      attr_reader :inner_comment

      # The source text used for fallback range extraction.
      # @return [String, nil]
      attr_reader :source

      # Optional parser-provided attachment hint.
      # @return [Symbol, nil]
      attr_reader :attachment_hint

      def initialize(comment, source: nil, attachment_hint: nil)
        @inner_comment = comment
        @source = source
        @attachment_hint = normalize_attachment_hint(attachment_hint)
      end

      # Get the normalized comment type.
      # Examples: "inline_comment", "block_comment".
      # @return [String]
      def type
        raise NotImplementedError, "#{self.class}#type must be implemented"
      end

      # Get the comment text including delimiters when appropriate.
      # @return [String]
      def text
        raise NotImplementedError, "#{self.class}#text must be implemented"
      end

      # Get the start byte offset of the comment.
      # @return [Integer]
      def start_byte
        raise NotImplementedError, "#{self.class}#start_byte must be implemented"
      end

      # Get the end byte offset of the comment.
      # @return [Integer]
      def end_byte
        raise NotImplementedError, "#{self.class}#end_byte must be implemented"
      end

      # Get the start position (row/column, 0-based).
      # @return [Hash{Symbol => Integer}]
      def start_point
        { row: 0, column: 0 }
      end

      # Get the end position (row/column, 0-based).
      # @return [Hash{Symbol => Integer}]
      def end_point
        { row: 0, column: 0 }
      end

      # Get the normalized delimiter style.
      #
      # @return [Symbol, nil]
      def style
        nil
      end

      # Get the opening delimiter for the comment, when the backend can provide it.
      #
      # Examples:
      # - `#` for hash comments
      # - `//` for C-style line comments
      # - `<!--` for HTML/XML block comments
      #
      # @return [String, nil]
      def opening_delimiter
        nil
      end

      # Get the closing delimiter for the comment, when applicable.
      #
      # This is typically `nil` for line comments.
      #
      # @return [String, nil]
      def closing_delimiter
        nil
      end

      # Get the comment body with outer delimiters removed when possible.
      #
      # Backends with richer native comment models should override this when they
      # can provide a more semantically accurate body than simple delimiter
      # trimming.
      #
      # @return [String]
      def body_text
        extract_body_text(text.to_s)
      end

      # Get a matching-friendly normalized comment body.
      #
      # This strips leading and trailing whitespace from {#body_text} while
      # preserving the raw rendered form in {#text}.
      #
      # @return [String]
      def normalized_text
        body_text.strip
      end

      # Get delimiter/body metadata in one normalized hash.
      #
      # @return [Hash{Symbol => String, nil}]
      def delimiter_metadata
        {
          opening: opening_delimiter,
          closing: closing_delimiter,
          body: body_text
        }
      end

      # Whether this comment uses a line-comment style.
      #
      # @return [Boolean]
      def line?
        style == :line
      end

      # Whether this comment uses a block-comment style.
      #
      # @return [Boolean]
      def block?
        style == :block
      end

      # Whether this comment spans multiple source lines.
      #
      # @return [Boolean]
      def multiline?
        start_line != end_line
      end

      # Whether this comment has a parser-provided attachment hint.
      #
      # @return [Boolean]
      def attachment_hint?
        !attachment_hint.nil?
      end

      # Whether this comment is hinted as leading its owner.
      #
      # @return [Boolean]
      def leading?
        attachment_hint == :leading
      end

      # Whether this comment is hinted as inline with its owner.
      #
      # @return [Boolean]
      def inline?
        attachment_hint == :inline
      end

      # Whether this comment is hinted as trailing its owner.
      #
      # @return [Boolean]
      def trailing?
        attachment_hint == :trailing
      end

      # Get the 1-based start line.
      #
      # @return [Integer]
      def start_line
        start_point[:row] + 1
      end

      # Get the 1-based end line.
      #
      # @return [Integer]
      def end_line
        end_point[:row] + 1
      end

      # Get a normalized source-position hash.
      #
      # @return [Hash{Symbol => Integer}]
      def source_position
        {
          start_line: start_line,
          end_line: end_line,
          start_column: start_point[:column],
          end_column: end_point[:column]
        }
      end

      # Whether this comment starts at the first line of the available source.
      #
      # @return [Boolean]
      def at_file_start?
        start_line == 1
      end

      # Whether this comment ends at the final line of the available source.
      #
      # @return [Boolean]
      def at_file_end?
        return false if source_lines.none?

        end_line >= source_lines.length
      end

      # Return the contiguous blank source lines immediately before this comment.
      #
      # This is parser-facing layout metadata. It does not decide ownership; it
      # simply exposes spacing adjacent to the comment so merge layers can reason
      # about floating vs attached behavior without rescanning source text.
      #
      # @return [Array<String>]
      def blank_lines_before
        return [] if at_file_start?

        line_num = start_line - 1
        blanks = []

        while line_num >= 1
          line = source_line(line_num)
          break unless line && line.strip.empty?

          blanks.unshift(line)
          line_num -= 1
        end

        blanks
      end

      # Return the contiguous blank source lines immediately after this comment.
      #
      # @return [Array<String>]
      def blank_lines_after
        return [] if at_file_end?

        line_num = end_line + 1
        blanks = []

        while line_num <= source_lines.length
          line = source_line(line_num)
          break unless line && line.strip.empty?

          blanks << line
          line_num += 1
        end

        blanks
      end

      # Return the count of immediately preceding blank source lines.
      #
      # @return [Integer]
      def blank_line_count_before
        blank_lines_before.length
      end

      # Return the count of immediately following blank source lines.
      #
      # @return [Integer]
      def blank_line_count_after
        blank_lines_after.length
      end

      def inspect
        "#<#{self.class} type=#{type.inspect} range=#{start_byte}...#{end_byte}>"
      end

      private

      def source_lines
        @source_lines ||= begin
          values = source.to_s.split("\n", -1)
          values.pop if values.last&.empty? && source.to_s.end_with?("\n")
          values
        end
      end

      def source_line(line_number)
        return if line_number < 1 || line_number > source_lines.length

        source_lines[line_number - 1]
      end

      def extract_body_text(raw_text)
        text_without_opening = if opening_delimiter
                                 raw_text.sub(/\A#{Regexp.escape(opening_delimiter)}[ \t]?/, '')
                               else
                                 raw_text
                               end

        return text_without_opening unless closing_delimiter

        text_without_opening.sub(/[ \t]*#{Regexp.escape(closing_delimiter)}\z/m, '')
      end

      def normalize_attachment_hint(hint)
        return if hint.nil?

        normalized = hint.to_sym
        return normalized if ATTACHMENT_HINTS.include?(normalized)

        raise ArgumentError,
              "Unknown comment attachment hint: #{hint.inspect}. Expected one of: #{ATTACHMENT_HINTS.join(', ')}"
      end
    end
  end
end
