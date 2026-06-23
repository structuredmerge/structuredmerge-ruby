# frozen_string_literal: true

module Dotenv
  module Merge
    # Represents a single line in a dotenv file.
    # Parses and categorizes lines as assignments, comments, blank lines, or invalid.
    #
    # Inherits from Ast::Merge::AstNode for a normalized API across all ast-merge
    # content nodes. This provides TreeHaver::Node protocol compatibility including
    # #slice, #location, #unwrap, #type, #text, and other standard methods.
    #
    # Dotenv files follow a simple format where each line is one of:
    # - `KEY=value` - Environment variable assignment
    # - `export KEY=value` - Assignment with export prefix
    # - `# comment` - Comment line
    # - Empty/whitespace - Blank line
    #
    # @example Parse a simple assignment
    #   line = EnvLine.new("API_KEY=secret123", 1)
    #   line.assignment? # => true
    #   line.key         # => "API_KEY"
    #   line.value       # => "secret123"
    #
    # @example Parse an export statement
    #   line = EnvLine.new("export DATABASE_URL=postgres://localhost/db", 2)
    #   line.assignment? # => true
    #   line.export?     # => true
    #   line.key         # => "DATABASE_URL"
    #
    # @example Parse a comment
    #   line = EnvLine.new("# Database configuration", 3)
    #   line.comment?    # => true
    #   line.comment     # => "# Database configuration"
    #
    # @example Quoted values with escape sequences
    #   line = EnvLine.new('MESSAGE="Hello\nWorld"', 4)
    #   line.value       # => "Hello\nWorld" (with actual newline)
    class EnvLine < Ast::Merge::AstNode
      # Prefix for exported environment variables
      # @return [String]
      EXPORT_PREFIX = 'export '

      # @return [String] The original raw line content
      attr_reader :raw

      # @return [Integer] The 1-indexed line number in the source file
      attr_reader :line_number

      # @return [Symbol, nil] The line type (:assignment, :comment, :blank, :invalid)
      attr_reader :line_type

      # @return [String, nil] The environment variable key (for assignments)
      attr_reader :key

      # @return [String, nil] The environment variable value (for assignments)
      attr_reader :value

      # @return [Boolean] Whether the line has an export prefix
      attr_reader :export

      # Initialize a new EnvLine by parsing the raw content
      #
      # @param raw [String] The raw line content from the dotenv file
      # @param line_number [Integer] The 1-indexed line number
      def initialize(raw, line_number)
        @raw = raw
        @line_number = line_number
        @line_type = nil
        @key = nil
        @value = nil
        @export = false
        parse!

        location = Ast::Merge::AstNode::Location.new(
          start_line: line_number,
          end_line: line_number,
          start_column: 0,
          end_column: @raw.length
        )

        super(slice: @raw, location: location)
      end

      # TreeHaver::Node protocol: type
      # @return [String] "env_line"
      def type
        'env_line'
      end

      # Generate a unique signature for this line (used for merge matching)
      #
      # @return [Array<Symbol, String>, nil] Signature array [:env, key] for assignments, nil otherwise
      def signature
        return unless @line_type == :assignment

        [:env, @key]
      end

      # Check if this line is an environment variable assignment
      #
      # @return [Boolean] true if the line is a valid KEY=value assignment
      def assignment?
        @line_type == :assignment
      end

      # Check if this line is a comment
      #
      # @return [Boolean] true if the line starts with #
      def comment?
        @line_type == :comment
      end

      # Check if this line is blank (empty or whitespace only)
      #
      # @return [Boolean] true if the line is blank
      def blank?
        @line_type == :blank
      end

      # Check if this line is invalid (unparseable)
      #
      # @return [Boolean] true if the line could not be parsed
      def invalid?
        @line_type == :invalid
      end

      # Check if this line has the export prefix
      #
      # @return [Boolean] true if the line starts with "export "
      def export?
        @export
      end

      # Get the raw comment text (for comment lines only)
      #
      # @return [String, nil] The raw line content if this is a comment, nil otherwise
      def comment
        return @raw if comment?

        nil
      end

      # Convert to string representation (returns raw content)
      #
      # @return [String] The original raw line content
      def to_s
        @raw
      end

      # Inspect for debugging
      #
      # @return [String] A debug representation of this EnvLine
      def inspect
        "#<#{self.class.name} line=#{@line_number} line_type=#{@line_type} key=#{@key.inspect}>"
      end

      private

      # Parse the raw line content and set line_type, key, value, and export
      #
      # @return [void]
      def parse!
        stripped = @raw.strip
        if stripped.empty?
          @line_type = :blank
        elsif stripped.start_with?('#')
          @line_type = :comment
        else
          parse_assignment!(stripped)
        end
      end

      # Parse a potential assignment line
      #
      # @param stripped [String] The stripped line content
      # @return [void]
      def parse_assignment!(stripped)
        line = stripped
        if line.start_with?(EXPORT_PREFIX)
          @export = true
          line = line[EXPORT_PREFIX.length..]
        end

        if line.include?('=')
          key_part, value_part = line.split('=', 2)
          key_part = key_part.strip
          if valid_key?(key_part)
            @line_type = :assignment
            @key = key_part
            @value = unquote(value_part || '')
          else
            @line_type = :invalid
          end
        else
          @line_type = :invalid
        end
      end

      # Validate an environment variable key
      #
      # @param key [String, nil] The key to validate
      # @return [Boolean] true if the key is valid (starts with letter/underscore, contains only alphanumerics/underscores)
      def valid_key?(key)
        return false if key.nil? || key.empty?

        key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      end

      # Remove quotes from a value and process escape sequences
      #
      # @param value [String] The raw value part after the =
      # @return [String] The unquoted and processed value
      def unquote(value)
        value = value.strip

        # Double-quoted: process escape sequences
        return process_escape_sequences(value[1..-2]) if value.start_with?('"') && value.end_with?('"')

        # Single-quoted: literal value, no escape processing
        return value[1..-2] if value.start_with?("'") && value.end_with?("'")

        # Unquoted: strip inline comments
        strip_inline_comment(value)
      end

      # Process escape sequences in double-quoted strings
      #
      # Handles: \n (newline), \t (tab), \r (carriage return), \" (quote), \\ (backslash)
      #
      # @param value [String] The value with escape sequences
      # @return [String] The value with escape sequences converted
      def process_escape_sequences(value)
        value
          .gsub('\n', "\n")
          .gsub('\t', "\t")
          .gsub('\r', "\r")
          .gsub('\"', '"')
          .gsub('\\\\', '\\')
      end

      # Strip inline comments from unquoted values
      #
      # @param value [String] The unquoted value
      # @return [String] The value with inline comments removed
      def strip_inline_comment(value)
        # Find # that's preceded by whitespace and strip from there
        if (match = value.match(/\s+#/))
          value[0, match.begin(0)].strip
        else
          value
        end
      end
    end
  end
end
