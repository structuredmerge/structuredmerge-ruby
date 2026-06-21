# frozen_string_literal: true

module Ast
  module Merge
    # Base class for freeze block nodes in AST merge libraries.
    #
    # A freeze block is a section marked with freeze/unfreeze comment markers that
    # should be preserved from the destination during merges. The entire content
    # between the markers is treated as opaque and matched by content identity.
    #
    # ## Key Distinction from FrozenWrapper
    #
    # FreezeNodeBase represents **explicit freeze blocks** with clear boundaries:
    # - Starts with `# token:freeze` (or equivalent in other comment styles)
    # - Ends with `# token:unfreeze`
    # - The content between markers is opaque and preserved verbatim
    # - Matched by CONTENT identity via `freeze_signature`
    #
    # In contrast, NodeTyping::FrozenWrapper represents **AST nodes with freeze markers
    # in their leading comments**:
    # - The marker appears in the node's leading comments, not as a block boundary
    # - The node is still a structural AST element (e.g., a `gem` call)
    # - Matched by the underlying node's STRUCTURAL identity
    #
    # ## Signature Generation Behavior
    #
    # When FileAnalyzable#generate_signature encounters a FreezeNodeBase, it uses
    # the `freeze_signature` method directly, which returns `[:FreezeNode, content]`.
    # This ensures that explicit freeze blocks are matched by their exact content.
    #
    # This class provides shared functionality for file-type-specific implementations
    # (e.g., Prism::Merge::FreezeNode, Psych::Merge::FreezeNode).
    #
    # Supports multiple comment syntax styles via configurable marker patterns:
    # - `:hash_comment` - Ruby/Python/YAML style (`# freeze-begin` / `# freeze-end`)
    # - `:html_comment` - HTML/Markdown style (`<!-- freeze-begin -->` / `<!-- freeze-end -->`)
    # - `:c_style_line` - C/JavaScript line comments (`// freeze-begin` / `// freeze-end`)
    # - `:c_style_block` - C/JavaScript block comments (`/* freeze-begin */` / `/* freeze-end */`)
    #
    # @example Freeze block with hash comments (Ruby/YAML)
    #   # <token>:freeze
    #   content to preserve...
    #   # <token>:unfreeze
    #
    # @example Freeze block with HTML comments (Markdown)
    #   <!-- <token>:freeze -->
    #   content to preserve...
    #   <!-- <token>:unfreeze -->
    #
    # @example Creating a custom pattern
    #   FreezeNodeBase.register_pattern(:custom,
    #     start: /^--\s*freeze-begin/i,
    #     end_pattern: /^--\s*freeze-end/i
    #   )
    #
    # @see Freezable#freeze_signature - Content-based signature for matching
    # @see NodeTyping::FrozenWrapper - Structural matching alternative
    # @see FileAnalyzable#generate_signature - Routing logic for signature generation
    class FreezeNodeBase
      include Freezable
      include BlockDirective

      # @return [Symbol] Always :freeze for FreezeNodeBase
      def kind = :freeze

      # @return [Array] AST nodes contained within the freeze block
      def children = @nodes

      # @return [Symbol] Freeze blocks are user customizations; dest always wins
      def merge_policy = :destination

      # Error raised when a freeze block has invalid structure
      class InvalidStructureError < StandardError
        # @return [Integer, nil] Starting line of the freeze block
        attr_reader :start_line

        # @return [Integer, nil] Ending line of the freeze block
        attr_reader :end_line

        # @return [Array] Nodes that caused the structure error (optional)
        attr_reader :unclosed_nodes

        # @param message [String] Error message
        # @param start_line [Integer, nil] Start line number
        # @param end_line [Integer, nil] End line number
        # @param unclosed_nodes [Array] Nodes causing the error
        def initialize(message, start_line: nil, end_line: nil, unclosed_nodes: [])
          super(message)
          @start_line = start_line
          @end_line = end_line
          @unclosed_nodes = unclosed_nodes
        end
      end

      # Simple location struct for compatibility with AST nodes
      Location = Struct.new(:start_line, :end_line) do
        # Check if a line number is within this location
        # @param line [Integer] Line number to check
        # @return [Boolean]
        def cover?(line)
          (start_line..end_line).cover?(line)
        end
      end

      # Pattern configuration for freeze block markers.
      # Mutable to allow runtime registration of custom patterns.
      # @return [Hash{Symbol => Hash{Symbol => Regexp}}] Registered marker patterns
      MARKER_PATTERNS = {
        hash_comment: {
          start: /^\s*#\s*[\w-]+:freeze\b/i,
          end: /^\s*#\s*[\w-]+:unfreeze\b/i,
        },
        html_comment: {
          start: /^\s*<!--\s*[\w-]+:freeze\b.*-->/i,
          end: /^\s*<!--\s*[\w-]+:unfreeze\b.*-->/i,
        },
        c_style_line: {
          start: %r{^\s*//\s*[\w-]+:freeze\b}i,
          end: %r{^\s*//\s*[\w-]+:unfreeze\b}i,
        },
        c_style_block: {
          start: %r{^\s*/\*\s*[\w-]+:freeze\b.*\*/}i,
          end: %r{^\s*/\*\s*[\w-]+:unfreeze\b.*\*/}i,
        },
      }

      # Default pattern when none specified
      # @return [Symbol]
      DEFAULT_PATTERN = :hash_comment

      class << self
        # Register a custom marker pattern
        # @param name [Symbol] Pattern name
        # @param start [Regexp] Regex to match freeze start marker
        # @param end_pattern [Regexp] Regex to match freeze end marker
        # @return [Hash{Symbol => Regexp}] The registered pattern
        # @raise [ArgumentError] if name already exists or patterns invalid
        def register_pattern(name, start:, end_pattern:)
          raise ArgumentError, "Pattern :#{name} already registered" if MARKER_PATTERNS.key?(name)
          raise ArgumentError, "Start pattern must be a Regexp" unless start.is_a?(Regexp)
          raise ArgumentError, "End pattern must be a Regexp" unless end_pattern.is_a?(Regexp)

          MARKER_PATTERNS[name] = {start: start, end: end_pattern}
        end

        # Get start marker pattern for a given pattern type
        # @param pattern_type [Symbol] Pattern type name (defaults to DEFAULT_PATTERN)
        # @return [Regexp] Start marker regex
        # @raise [ArgumentError] if pattern type not found
        def start_pattern(pattern_type = DEFAULT_PATTERN)
          patterns = MARKER_PATTERNS[pattern_type]
          raise ArgumentError, "Unknown pattern type: #{pattern_type}" unless patterns

          patterns[:start]
        end

        # Get end marker pattern for a given pattern type
        # @param pattern_type [Symbol] Pattern type name (defaults to DEFAULT_PATTERN)
        # @return [Regexp] End marker regex
        # @raise [ArgumentError] if pattern type not found
        def end_pattern(pattern_type = DEFAULT_PATTERN)
          patterns = MARKER_PATTERNS[pattern_type]
          raise ArgumentError, "Unknown pattern type: #{pattern_type}" unless patterns

          patterns[:end]
        end

        # Get both start and end patterns for a given pattern type
        # When token is provided, returns a combined pattern with capture groups
        # for marker type (freeze/unfreeze) and optional reason.
        #
        # @param pattern_type [Symbol] Pattern type name (defaults to DEFAULT_PATTERN)
        # @param token [String, nil] Optional freeze token to build specific pattern
        # @return [Hash{Symbol => Regexp}, Regexp] Hash with :start/:end keys, or combined Regexp if token provided
        # @raise [ArgumentError] if pattern type not found
        #
        # @example Without token (returns hash of patterns)
        #   FreezeNode.pattern_for(:hash_comment)
        #   # => { start: /.../, end: /.../ }
        #
        # @example With token (returns combined pattern with capture groups)
        #   FreezeNode.pattern_for(:hash_comment, "my-merge")
        #   # => /^\s*#\s*my-merge:(freeze|unfreeze)\b\s*(.*)?$/i
        #   # Capture group 1: "freeze" or "unfreeze"
        #   # Capture group 2: optional reason text
        def pattern_for(pattern_type = DEFAULT_PATTERN, token = nil)
          raise ArgumentError, "Unknown pattern type: #{pattern_type}" unless MARKER_PATTERNS.key?(pattern_type)

          # If no token provided, return the static patterns hash
          return MARKER_PATTERNS[pattern_type] unless token

          # Build a combined pattern with capture groups for the specific token
          escaped_token = Regexp.escape(token)

          case pattern_type
          when :hash_comment
            /^\s*#\s*#{escaped_token}:(freeze|unfreeze)\b\s*(.*)?$/i
          when :html_comment
            /^\s*<!--\s*#{escaped_token}:(freeze|unfreeze)(?:\s+(.+?))?\s*-->/i
          when :c_style_line
            %r{^\s*//\s*#{escaped_token}:(freeze|unfreeze)\b\s*(.*)?$}i
          when :c_style_block
            %r{^\s*/\*\s*#{escaped_token}:(freeze|unfreeze)\b\s*(.*)? *\*/}i
          else
            # Fallback for custom registered patterns - can't build token-specific
            raise ArgumentError, "Cannot build token-specific pattern for custom type: #{pattern_type}"
          end
        end

        # Check if a line matches a freeze start marker
        # @param line [String] Line content to check
        # @param pattern_type [Symbol] Pattern type to use (defaults to DEFAULT_PATTERN)
        # @return [Boolean]
        def freeze_start?(line, pattern_type = DEFAULT_PATTERN)
          return false if line.nil?

          start_pattern(pattern_type).match?(line)
        end

        # Check if a line matches a freeze end marker
        # @param line [String] Line content to check
        # @param pattern_type [Symbol] Pattern type to use (defaults to DEFAULT_PATTERN)
        # @return [Boolean]
        def freeze_end?(line, pattern_type = DEFAULT_PATTERN)
          return false if line.nil?

          end_pattern(pattern_type).match?(line)
        end

        # Available pattern types
        # @return [Array<Symbol>]
        def pattern_types
          MARKER_PATTERNS.keys
        end
      end

      # @return [Integer] Line number of freeze marker (1-based)
      attr_reader :start_line

      # @return [Integer] Line number of unfreeze marker (1-based)
      attr_reader :end_line

      # @return [String] Content of the freeze block
      attr_reader :content

      # @return [String, nil] The freeze start marker text
      attr_reader :start_marker

      # @return [String, nil] The freeze end marker text
      attr_reader :end_marker

      # @return [Symbol] The pattern type used for this freeze node
      attr_reader :pattern_type

      # @return [Array<String>, nil] Lines within the freeze block
      attr_reader :lines

      # @return [Object, nil] Reference to FileAnalysis (for subclasses that need it)
      attr_reader :analysis

      # @return [Array] AST nodes contained within the freeze block
      attr_reader :nodes

      # @return [Array, nil] Nodes that overlap with the freeze block boundaries
      attr_reader :overlapping_nodes

      # Initialize a freeze node.
      #
      # This unified constructor accepts all parameters that any *-merge gem might need.
      # Subclasses should call super with the parameters they use.
      #
      # Content can be provided via:
      # - `lines:` - Direct array of line strings
      # - `analysis:` - FileAnalysis reference (lines extracted via analysis.lines)
      # - `content:` - Direct content string (will be split into lines)
      #
      # @param start_line [Integer] Line number of freeze marker (1-based)
      # @param end_line [Integer] Line number of unfreeze marker (1-based)
      # @param lines [Array<String>, nil] Direct array of source lines
      # @param analysis [Object, nil] FileAnalysis reference for content access
      # @param content [String, nil] Direct content string
      # @param nodes [Array] AST nodes contained within the freeze block
      # @param overlapping_nodes [Array, nil] Nodes that overlap block boundaries
      # @param start_marker [String, nil] The freeze start marker text
      # @param end_marker [String, nil] The freeze end marker text
      # @param pattern_type [Symbol] Pattern type for marker matching
      # @param reason [String, nil] Optional reason extracted from freeze marker
      def initialize(
        start_line:,
        end_line:,
        lines: nil,
        analysis: nil,
        content: nil,
        nodes: [],
        overlapping_nodes: nil,
        start_marker: nil,
        end_marker: nil,
        pattern_type: DEFAULT_PATTERN,
        reason: nil
      )
        @start_line = start_line
        @end_line = end_line
        @start_marker = start_marker
        @end_marker = end_marker
        @pattern_type = pattern_type
        @explicit_reason = reason
        @nodes = nodes
        @overlapping_nodes = overlapping_nodes
        @analysis = analysis

        # Handle content from various sources
        @lines = resolve_lines(lines, analysis, content)
        @content = resolve_content(@lines, content)
      end

      # Returns a location-like object for compatibility with AST nodes
      # @return [Location]
      def location
        @location ||= Location.new(@start_line, @end_line)
      end

      # Extract the reason/comment from the freeze start marker.
      # The reason is any text after the freeze directive.
      # If an explicit reason was provided at initialization, that takes precedence.
      #
      # @example With reason
      #   # rbs-merge:freeze Custom reason here
      #   => "Custom reason here"
      #
      # @example Without reason
      #   # rbs-merge:freeze
      #   => nil
      #
      # @return [String, nil] The reason text, or nil if not present
      def reason
        # Return explicit reason if provided at initialization
        return @explicit_reason if @explicit_reason

        return unless @start_marker

        # Use the canonical pattern which has capture group 2 for reason
        # We need to extract the token from the marker first
        token = extract_token_from_marker
        return unless token

        pattern = self.class.pattern_for(@pattern_type, token)
        match = @start_marker.match(pattern)
        return unless match

        # Capture group 2 is the reason text
        reason_text = match[2]&.strip
        reason_text&.empty? ? nil : reason_text
      end

      # Returns the freeze block content
      # @return [String]
      def slice
        @content
      end

      # Check if this is a freeze node (always true for FreezeNode)
      # @return [Boolean]
      def freeze_node?
        true
      end

      # Node type for merge classification
      # @return [Symbol] :freeze_block
      def merge_type
        :freeze_block
      end

      # Alias for compatibility
      alias_method :type, :merge_type

      # Returns a stable signature for this freeze block.
      # Override in subclasses for file-type-specific normalization.
      # @return [Array] Signature array
      def signature
        [:FreezeNode, @content&.strip]
      end

      # String representation for debugging
      # @return [String]
      def inspect
        "#<#{self.class.name} lines=#{start_line}..#{end_line} pattern=#{pattern_type}>"
      end

      # @return [String]
      def to_s
        inspect
      end

      protected

      # Validate that end_line is not before start_line
      # @raise [InvalidStructureError] if structure is invalid
      def validate_line_order!
        return if @end_line >= @start_line

        raise InvalidStructureError.new(
          "Freeze block end line (#{@end_line}) is before start line (#{@start_line})",
          start_line: @start_line,
          end_line: @end_line,
        )
      end

      private

      # Resolve lines from various sources
      # @param lines [Array<String>, nil] Direct lines array
      # @param analysis [Object, nil] FileAnalysis with lines method
      # @param content [String, nil] Direct content string
      # @return [Array<String>, nil] Resolved lines
      def resolve_lines(lines, analysis, content)
        return lines if lines

        if analysis&.respond_to?(:lines)
          # Extract lines from analysis using line numbers (1-based to 0-based)
          all_lines = analysis.lines
          return all_lines[(@start_line - 1)..(@end_line - 1)] if all_lines
        end

        content&.split("\n", -1)
      end

      # Resolve content from various sources
      # @param lines [Array<String>, nil] Resolved lines
      # @param content [String, nil] Direct content string
      # @return [String, nil] Resolved content
      def resolve_content(lines, content)
        return content if content

        lines&.join("\n")
      end

      # Extract the token from the start marker
      # @return [String, nil] The token (e.g., "rbs-merge" from "# rbs-merge:freeze")
      def extract_token_from_marker
        # simplecov:disable
        # Defensive: @start_marker is always set in normal usage, nil check is for safety
        return unless @start_marker
        # simplecov:enable

        # Match the token before :freeze
        match = @start_marker.match(/([\w-]+):freeze/i)
        match&.[](1)
      end
    end
  end
end
