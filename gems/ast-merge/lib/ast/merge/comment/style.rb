# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Configuration for different comment syntax styles.
      #
      # Supports multiple comment syntax patterns used across programming languages:
      # - `:hash_comment` - Ruby/Python/YAML/Shell style (`# comment`)
      # - `:html_comment` - HTML/XML/Markdown style (`<!-- comment -->`)
      # - `:c_style_line` - C/JavaScript/Go line comments (`// comment`)
      # - `:c_style_block` - C/JavaScript/CSS block comments (`/* comment */`)
      # - `:semicolon_comment` - Lisp/Clojure/Assembly style (`; comment`)
      # - `:double_dash_comment` - SQL/Haskell/Lua style (`-- comment`)
      #
      # @example Using a predefined style
      #   style = Style.for(:hash_comment)
      #   style.line_start #=> "#"
      #   style.match_line?("# hello") #=> true
      #
      # @example Registering a custom style
      #   Style.register(:percent_comment,
      #     line_start: "%",
      #     line_pattern: /^\s*%/
      #   )
      #
      class Style
        # @return [Symbol] The style identifier
        attr_reader :name

        # @return [String, nil] Line comment start delimiter (e.g., "#", "//")
        attr_reader :line_start

        # @return [String, nil] Line comment end delimiter (for HTML-style: "-->")
        attr_reader :line_end

        # @return [String, nil] Block comment start delimiter (e.g., "/*")
        attr_reader :block_start

        # @return [String, nil] Block comment end delimiter (e.g., "*/")
        attr_reader :block_end

        # @return [Regexp] Pattern to match a single comment line
        attr_reader :line_pattern

        # @return [Regexp, nil] Pattern to match block comment start
        attr_reader :block_start_pattern

        # @return [Regexp, nil] Pattern to match block comment end
        attr_reader :block_end_pattern

        # Predefined comment styles.
        # Mutable to allow runtime registration of custom styles.
        # @return [Hash{Symbol => Hash}] Registered comment styles
        STYLES = {
          hash_comment: {
            line_start: '#',
            line_end: nil,
            block_start: nil,
            block_end: nil,
            line_pattern: /^\s*#/,
            block_start_pattern: nil,
            block_end_pattern: nil
          },
          html_comment: {
            line_start: '<!--',
            line_end: '-->',
            block_start: '<!--',
            block_end: '-->',
            line_pattern: /^\s*<!--.*-->\s*$/,
            block_start_pattern: /^\s*<!--/,
            block_end_pattern: /-->\s*$/
          },
          c_style_line: {
            line_start: '//',
            line_end: nil,
            block_start: nil,
            block_end: nil,
            line_pattern: %r{^\s*//},
            block_start_pattern: nil,
            block_end_pattern: nil
          },
          c_style_block: {
            line_start: nil,
            line_end: nil,
            block_start: '/*',
            block_end: '*/',
            line_pattern: nil,
            block_start_pattern: %r{^\s*/\*},
            block_end_pattern: %r{\*/\s*$}
          },
          semicolon_comment: {
            line_start: ';',
            line_end: nil,
            block_start: nil,
            block_end: nil,
            line_pattern: /^\s*;/,
            block_start_pattern: nil,
            block_end_pattern: nil
          },
          double_dash_comment: {
            line_start: '--',
            line_end: nil,
            block_start: nil,
            block_end: nil,
            line_pattern: /^\s*--/,
            block_start_pattern: nil,
            block_end_pattern: nil
          }
        }.freeze

        # Default style when none specified
        # @return [Symbol]
        DEFAULT_STYLE = :hash_comment

        class << self
          # Get a Style instance for a given style name.
          #
          # @param name [Symbol] Style name (e.g., :hash_comment, :c_style_line)
          # @return [Style] The style configuration
          # @raise [ArgumentError] if style name is not registered
          def for(name)
            name = name&.to_sym || DEFAULT_STYLE
            config = STYLES[name]
            raise ArgumentError, "Unknown comment style: #{name}" unless config

            new(name, **config)
          end

          # Register a custom comment style.
          #
          # @param name [Symbol] Style identifier
          # @param line_start [String, nil] Line comment start delimiter
          # @param line_end [String, nil] Line comment end delimiter
          # @param block_start [String, nil] Block comment start delimiter
          # @param block_end [String, nil] Block comment end delimiter
          # @param line_pattern [Regexp, nil] Pattern to match comment lines
          # @param block_start_pattern [Regexp, nil] Pattern to match block start
          # @param block_end_pattern [Regexp, nil] Pattern to match block end
          # @return [Hash] The registered style configuration
          # @raise [ArgumentError] if name already exists
          def register(name, line_start: nil, line_end: nil, block_start: nil, block_end: nil,
                       line_pattern: nil, block_start_pattern: nil, block_end_pattern: nil)
            name = name.to_sym
            raise ArgumentError, "Style :#{name} already registered" if STYLES.key?(name)

            config = {
              line_start: line_start,
              line_end: line_end,
              block_start: block_start,
              block_end: block_end,
              line_pattern: line_pattern,
              block_start_pattern: block_start_pattern,
              block_end_pattern: block_end_pattern
            }

            # Modify STYLES (it's frozen, so we need to work around)
            STYLES.dup.tap do |styles|
              styles[name] = config
              remove_const(:STYLES)
              const_set(:STYLES, styles.freeze)
            end

            config
          end

          # List all registered style names.
          #
          # @return [Array<Symbol>] Available style names
          def available_styles
            STYLES.keys
          end

          # Check if a style supports line comments.
          #
          # @param name [Symbol] Style name
          # @return [Boolean] true if style has line comment support
          def supports_line_comments?(name)
            config = STYLES[name.to_sym]
            config && config[:line_pattern]
          end

          # Check if a style supports block comments.
          #
          # @param name [Symbol] Style name
          # @return [Boolean] true if style has block comment support
          def supports_block_comments?(name)
            config = STYLES[name.to_sym]
            config && config[:block_start_pattern]
          end
        end

        # Initialize a new Style.
        #
        # @param name [Symbol] Style identifier
        # @param line_start [String, nil] Line comment start delimiter
        # @param line_end [String, nil] Line comment end delimiter
        # @param block_start [String, nil] Block comment start delimiter
        # @param block_end [String, nil] Block comment end delimiter
        # @param line_pattern [Regexp, nil] Pattern to match comment lines
        # @param block_start_pattern [Regexp, nil] Pattern to match block start
        # @param block_end_pattern [Regexp, nil] Pattern to match block end
        def initialize(name, line_start: nil, line_end: nil, block_start: nil, block_end: nil,
                       line_pattern: nil, block_start_pattern: nil, block_end_pattern: nil)
          @name = name
          @line_start = line_start
          @line_end = line_end
          @block_start = block_start
          @block_end = block_end
          @line_pattern = line_pattern
          @block_start_pattern = block_start_pattern
          @block_end_pattern = block_end_pattern
        end

        # Check if a line matches this style's line comment pattern.
        #
        # @param line [String] The line to check
        # @return [Boolean] true if line is a comment in this style
        def match_line?(line)
          return false unless line_pattern

          line_pattern.match?(line.to_s)
        end

        # Check if a line starts a block comment.
        #
        # @param line [String] The line to check
        # @return [Boolean] true if line starts a block comment
        def match_block_start?(line)
          return false unless block_start_pattern

          block_start_pattern.match?(line.to_s)
        end

        # Check if a line ends a block comment.
        #
        # @param line [String] The line to check
        # @return [Boolean] true if line ends a block comment
        def match_block_end?(line)
          return false unless block_end_pattern

          block_end_pattern.match?(line.to_s)
        end

        # Extract content from a line comment, removing the delimiter.
        #
        # @param line [String] The comment line
        # @return [String] The comment content without delimiters
        def extract_line_content(line)
          return line.to_s unless line_start

          content = line.to_s.sub(/^\s*#{Regexp.escape(line_start)}\s?/, '')
          content = content.sub(/\s*#{Regexp.escape(line_end)}\s*$/, '') if line_end
          # Content extraction normalizes trailing spaces for comparison/parsing.
          # Callers that need source-preserving output should use the raw line.
          content.rstrip
        end

        # Check if this style supports line comments.
        #
        # @return [Boolean] true if line comments are supported
        def supports_line_comments?
          !line_pattern.nil?
        end

        # Check if this style supports block comments.
        #
        # @return [Boolean] true if block comments are supported
        def supports_block_comments?
          !block_start_pattern.nil?
        end

        # @return [String] Human-readable representation
        def inspect
          "#<Comment::Style:#{name}>"
        end
      end
    end
  end
end
