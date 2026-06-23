# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Represents a single comment line in source code.
      #
      # A comment line is a line that starts with a comment delimiter
      # (e.g., `#` in Ruby, `//` in JavaScript, `<!--` in HTML).
      # The style determines how the comment is parsed and normalized.
      #
      # @example Ruby-style hash comment
      #   line = Line.new(text: "# frozen_string_literal: true", line_number: 1)
      #   line.slice #=> "# frozen_string_literal: true"
      #   line.content #=> "frozen_string_literal: true"
      #   line.signature #=> [:comment_line, "frozen_string_literal: true"]
      #
      # @example JavaScript-style line comment
      #   style = Style.for(:c_style_line)
      #   line = Line.new(text: "// TODO: fix this", line_number: 5, style: style)
      #   line.content #=> "TODO: fix this"
      #
      # @example HTML-style comment
      #   style = Style.for(:html_comment)
      #   line = Line.new(text: "<!-- Important note -->", line_number: 1, style: style)
      #   line.content #=> "Important note"
      #
      class Line < AstNode
        # @return [String] The raw text of the comment line
        attr_reader :text

        # @return [Integer] The line number in source
        attr_reader :line_number

        # @return [Style] The comment style configuration
        attr_reader :style

        # TreeHaver::Node protocol: type
        # @return [String] "comment_line"
        def type
          'comment_line'
        end

        # Initialize a new Line.
        #
        # @param text [String] The full comment text including delimiter
        # @param line_number [Integer] The 1-based line number
        # @param style [Style, Symbol, nil] The comment style (default: :hash_comment)
        def initialize(text:, line_number:, style: nil)
          @text = text.to_s
          @line_number = line_number
          @style = resolve_style(style)

          location = AstNode::Location.new(
            start_line: line_number,
            end_line: line_number,
            start_column: 0,
            end_column: @text.length
          )

          super(slice: @text, location: location)
        end

        # Extract the comment content without the delimiter.
        #
        # Uses the style configuration to properly strip delimiters.
        #
        # @return [String] The comment text without the leading delimiter and whitespace
        def content
          @content ||= style.extract_line_content(text)
        end

        # Generate signature for matching.
        # Uses normalized content (without delimiter) for better matching across files.
        #
        # @return [Array] Signature for matching
        def signature
          [:comment_line, normalized_content.downcase]
        end

        # @return [String] Normalized content for comparison
        def normalized_content
          content.strip
        end

        # Check if this comment contains a specific token pattern.
        #
        # Useful for detecting freeze markers or other special directives.
        #
        # @param token [String] The token to look for
        # @param action [String, nil] Optional action suffix (e.g., "freeze", "unfreeze")
        # @return [Boolean] true if the token is found
        def contains_token?(token, action: nil)
          return false unless token

          pattern = if action
                      /#{Regexp.escape(token)}:#{action}/i
                    else
                      /#{Regexp.escape(token)}/i
                    end
          text.match?(pattern)
        end

        # Check if this comment contains a freeze marker.
        #
        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if this comment contains a freeze marker
        def freeze_action(freeze_token)
          return unless freeze_token

          pattern = /#{Regexp.escape(freeze_token)}:(freeze|unfreeze)/i
          match = text.match(pattern)
          match && match[1]&.downcase&.to_sym
        end

        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if this comment contains a freeze directive
        def freeze_marker?(freeze_token)
          !freeze_action(freeze_token).nil?
        end

        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if this comment contains a freeze directive
        def freeze?(freeze_token)
          freeze_action(freeze_token) == :freeze
        end

        # @param freeze_token [String] The freeze token to look for
        # @return [Boolean] true if this comment contains an unfreeze directive
        def unfreeze?(freeze_token)
          freeze_action(freeze_token) == :unfreeze
        end

        # @return [String] Human-readable representation
        def inspect
          "#<Comment::Line line=#{line_number} style=#{style.name} #{text.inspect}>"
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
          when Symbol
            Style.for(style)
          when nil
            Style.for(Style::DEFAULT_STYLE)
          else
            raise ArgumentError, "Invalid style: #{style.inspect}"
          end
        end
      end
    end
  end
end
