# frozen_string_literal: true

module Markdown
  module Merge
    # Represents a link reference definition that was consumed by the Markdown parser.
    #
    # Markdown parsers like Markly (libcmark-gfm) consume link reference definitions
    # during parsing and resolve them into inline links. This means they don't appear
    # as nodes in the AST. This class represents these "consumed" definitions so they
    # can be preserved during merge operations.
    #
    # Link reference definitions have the form:
    #   [label]: url "optional title"
    #   [label]: url 'optional title'
    #   [label]: url (optional title)
    #   [label]: <url> "optional title"
    #
    # Uses {LinkParser} for robust parsing that handles:
    # - Emoji in labels (e.g., `[🖼️galtzo-discord]`)
    # - Multi-byte UTF-8 characters
    # - Nested brackets in labels
    #
    # @example
    #   node = LinkDefinitionNode.new(
    #     "[ref]: https://example.com",
    #     line_number: 10,
    #     label: "ref",
    #     url: "https://example.com"
    #   )
    #   node.type        # => :link_definition
    #   node.label       # => "ref"
    #   node.url         # => "https://example.com"
    #   node.signature   # => [:link_definition, "ref"]
    class LinkDefinitionNode < Ast::Merge::AstNode
      # @return [String] The link label (reference name)
      attr_reader :label

      # @return [String] The URL
      attr_reader :url

      # @return [String, nil] Optional title
      attr_reader :title

      # @return [String] The full original line content
      attr_reader :content

      # Initialize a new LinkDefinitionNode
      #
      # @param content [String] The full line content
      # @param line_number [Integer] 1-based line number
      # @param label [String] The link label
      # @param url [String] The URL
      # @param title [String, nil] Optional title
      def initialize(content, line_number:, label:, url:, title: nil)
        @content = content
        @label = label
        @url = url
        @title = title

        location = Ast::Merge::AstNode::Location.new(
          start_line: line_number,
          end_line: line_number,
          start_column: 0,
          end_column: content.length
        )

        super(slice: content, location: location)
      end

      class << self
        # Shared parser instance for parsing link definitions
        # @return [LinkParser]
        def parser
          @parser ||= LinkParser.new
        end

        # Parse a line and create a LinkDefinitionNode if it's a link definition.
        #
        # @param line [String] The line content
        # @param line_number [Integer] 1-based line number
        # @return [LinkDefinitionNode, nil] Node if line is a link definition, nil otherwise
        def parse(line, line_number:)
          result = parser.parse_definition_line(line.chomp)
          return unless result

          new(
            line.chomp,
            line_number: line_number,
            label: result[:label],
            url: result[:url],
            title: result[:title]
          )
        end

        # Check if a line looks like a link reference definition.
        #
        # @param line [String] The line to check
        # @return [Boolean] true if line matches link definition pattern
        def link_definition?(line)
          !parser.parse_definition_line(line.strip).nil?
        end
      end

      # TreeHaver::Node protocol: type
      # @return [Symbol] :link_definition
      def type
        :link_definition
      end

      # Alias for compatibility with wrapped nodes that have merge_type
      # @return [Symbol] :link_definition
      alias merge_type type

      # Generate a signature for matching link definitions.
      # Link definitions are matched by their label (case-insensitive in Markdown).
      #
      # @return [Array] Signature array [:link_definition, lowercase_label]
      def signature
        [:link_definition, @label.downcase]
      end

      # TreeHaver::Node protocol: source_position
      # @return [Hash] Position info for source extraction
      def source_position
        {
          start_line: @location.start_line,
          end_line: @location.end_line,
          start_column: @location.start_column,
          end_column: @location.end_column
        }
      end

      # TreeHaver::Node protocol: children (none for link definitions)
      # @return [Array] Empty array
      def children
        []
      end

      # TreeHaver::Node protocol: text
      # @return [String] The full line content
      def text
        @content
      end

      # Convert to commonmark format (just returns the original content)
      # @return [String] The link definition line
      def to_commonmark
        "#{@content}\n"
      end

      # For debugging
      def inspect
        "#<#{self.class.name} [#{@label}]: #{@url}>"
      end
    end
  end
end
