# frozen_string_literal: true

module TreeHaver
  module Backends
    # Psych backend using Ruby's built-in YAML parser
    #
    # This backend wraps Psych, Ruby's standard library YAML parser.
    # Psych provides AST access via Psych.parse_stream which returns
    # Psych::Nodes::* objects (Stream, Document, Mapping, Sequence, Scalar, Alias).
    #
    # @note This backend only parses YAML source code
    # @see https://ruby-doc.org/stdlib/libdoc/psych/rdoc/Psych.html Psych documentation
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = TreeHaver::Backends::Psych::Language.yaml
    #   tree = parser.parse(yaml_source)
    #   root = tree.root_node
    #   puts root.type  # => "stream"
    module Psych
      @load_attempted = false
      @loaded = false

      # Check if the Psych backend is available
      #
      # Psych is part of Ruby stdlib, so it should always be available.
      #
      # @return [Boolean] true if psych is available
      class << self
        def available?
          return @loaded if @load_attempted

          @load_attempted = true
          begin
            require 'psych'
            @loaded = true
          rescue LoadError
            @loaded = false
          rescue StandardError
            # simplecov:disable defensive code - StandardError during require is extremely rare
            @loaded = false
            # simplecov:enable
          end
          @loaded
        end

        # Reset the load state (primarily for testing)
        #
        # @return [void]
        # @api private
        def reset!
          @load_attempted = false
          @loaded = false
        end

        # Get capabilities supported by this backend
        #
        # @return [Hash{Symbol => Object}] capability map
        def capabilities
          return {} unless available?

          {
            backend: :psych,
            query: false,           # Psych doesn't have tree-sitter-style queries
            bytes_field: false,     # Psych uses line/column, not byte offsets
            incremental: false,     # Psych doesn't support incremental parsing
            pure_ruby: false,       # Psych has native libyaml C extension
            yaml_only: true,        # Psych only parses YAML
            error_tolerant: false,  # Psych raises on syntax errors
            comment_support: :none
          }
        end
      end

      # Psych language wrapper
      #
      # Unlike tree-sitter which supports many languages via grammar files,
      # Psych only parses YAML. This class exists for API compatibility with
      # other tree_haver backends.
      #
      # @example
      #   language = TreeHaver::Backends::Psych::Language.yaml
      #   parser.language = language
      class Language < TreeHaver::Base::Language
        # Create a new Psych language instance
        #
        # @param name [Symbol] Language name (should be :yaml)
        def initialize(name = :yaml)
          super(name, backend: :psych, options: {})
        end

        class << self
          # Create a YAML language instance
          #
          # @return [Language] YAML language
          def yaml
            new(:yaml)
          end

          # Load language from library path (API compatibility)
          #
          # Psych only supports YAML, so path and symbol parameters are ignored.
          #
          # @param _path [String] Ignored - Psych doesn't load external grammars
          # @param symbol [String, nil] Ignored - Psych only supports YAML
          # @param name [String, nil] Language name hint (defaults to :yaml)
          # @return [Language] YAML language
          # @raise [TreeHaver::NotAvailable] if requested language is not YAML
          def from_library(_path = nil, symbol: nil, name: nil) # rubocop:disable Lint/UnusedMethodArgument
            lang_name = name || :yaml

            unless lang_name == :yaml
              raise TreeHaver::NotAvailable,
                    "Psych backend only supports YAML, not #{lang_name}. " \
                      "Use a tree-sitter backend for #{lang_name} support."
            end

            yaml
          end
        end
      end

      # Psych parser wrapper
      #
      # Wraps Psych.parse_stream to provide TreeHaver-compatible parsing.
      #
      # @example
      #   parser = TreeHaver::Backends::Psych::Parser.new
      #   parser.language = Language.yaml
      #   tree = parser.parse(yaml_source)
      class Parser < TreeHaver::Base::Parser
        # Parse YAML source code
        #
        # @param source [String] YAML source to parse
        # @return [Tree] Parsed tree
        # @raise [::Psych::SyntaxError] on syntax errors
        def parse(source)
          raise 'Language not set' unless language

          Psych.available? or raise 'Psych not available'

          ast = ::Psych.parse_stream(source)
          Tree.new(ast, source)
        end

        # Alias for compatibility with tree-sitter API
        #
        # @param _old_tree [nil] Ignored (Psych doesn't support incremental parsing)
        # @param source [String] YAML source to parse
        # @return [Tree] Parsed tree
        def parse_string(_old_tree, source)
          parse(source)
        end
      end

      # Psych tree wrapper
      #
      # Wraps a Psych::Nodes::Stream to provide TreeHaver-compatible tree interface.
      class Tree < TreeHaver::Base::Tree
        # @return [::Psych::Nodes::Stream] The underlying Psych stream
        attr_reader :inner_tree

        # Create a new tree wrapper
        #
        # @param stream [::Psych::Nodes::Stream] Psych stream node
        # @param source [String] Original source
        def initialize(stream, source)
          super(stream, source: source)
        end

        # Get the root node
        #
        # @return [Node] Root node
        def root_node
          Node.new(inner_tree, source: source, lines: lines)
        end

        # Human-readable representation
        def inspect
          "#<TreeHaver::Backends::Psych::Tree documents=#{inner_tree.children&.size || 0}>"
        end
      end

      # Psych node wrapper
      #
      # Wraps Psych::Nodes::* classes to provide TreeHaver::Node-compatible interface.
      #
      # Psych node types:
      # - Stream: Root container
      # - Document: YAML document (multiple per stream possible)
      # - Mapping: Hash/object
      # - Sequence: Array/list
      # - Scalar: Primitive value (string, number, boolean, null)
      # - Psych::Nodes::Alias: YAML anchor reference
      class Node < TreeHaver::Base::Node
        # Get the node type as a string
        #
        # @return [String] Node type
        def type
          inner_node.class.name.split('::').last.downcase
        end

        # Alias for type (API compatibility)
        # @return [String] node type
        def kind
          type
        end

        # Get the text content of this node
        #
        # @return [String] Node text
        def text
          case inner_node
          when ::Psych::Nodes::Scalar
            inner_node.value.to_s
          when ::Psych::Nodes::Alias
            "*#{inner_node.anchor}"
          else
            # For container nodes, extract from source using location
            extract_text_from_location
          end
        end

        # Get child nodes
        #
        # @return [Array<Node>] Child nodes
        def children
          return [] unless inner_node.respond_to?(:children) && inner_node.children

          inner_node.children.map { |child| Node.new(child, source: source, lines: lines) }
        end

        # Get start byte offset
        #
        # @return [Integer] Start byte offset
        def start_byte
          return 0 unless inner_node.respond_to?(:start_line)

          line = inner_node.start_line || 0
          col = inner_node.start_column || 0
          calculate_byte_offset(line, col)
        end

        # Get end byte offset
        #
        # @return [Integer] End byte offset
        def end_byte
          return start_byte + text.bytesize unless inner_node.respond_to?(:end_line)

          line = inner_node.end_line || 0
          col = inner_node.end_column || 0
          calculate_byte_offset(line, col)
        end

        # Get start point (row, column) - 0-based
        #
        # @return [TreeHaver::Base::Point] Start position
        def start_point
          row = (inner_node.respond_to?(:start_line) ? inner_node.start_line : 0) || 0
          col = (inner_node.respond_to?(:start_column) ? inner_node.start_column : 0) || 0
          TreeHaver::Base::Point.new(row, col)
        end

        # Get end point (row, column) - 0-based
        #
        # @return [TreeHaver::Base::Point] End position
        def end_point
          row = (inner_node.respond_to?(:end_line) ? inner_node.end_line : 0) || 0
          col = (inner_node.respond_to?(:end_column) ? inner_node.end_column : 0) || 0
          TreeHaver::Base::Point.new(row, col)
        end

        # Psych-specific: Get the anchor name for Alias/anchored nodes
        #
        # @return [String, nil] Anchor name
        def anchor
          inner_node.anchor if inner_node.respond_to?(:anchor)
        end

        # Psych-specific: Get the tag for tagged nodes
        #
        # @return [String, nil] Tag
        def tag
          inner_node.tag if inner_node.respond_to?(:tag)
        end

        # Psych-specific: Get the scalar value
        #
        # @return [String, nil] Value for scalar nodes
        def value
          inner_node.value if inner_node.respond_to?(:value)
        end

        # Psych-specific: Check if this is a mapping (hash)
        #
        # @return [Boolean]
        def mapping?
          inner_node.is_a?(::Psych::Nodes::Mapping)
        end

        # Psych-specific: Check if this is a sequence (array)
        #
        # @return [Boolean]
        def sequence?
          inner_node.is_a?(::Psych::Nodes::Sequence)
        end

        # Psych-specific: Check if this is a scalar (primitive)
        #
        # @return [Boolean]
        def scalar?
          inner_node.is_a?(::Psych::Nodes::Scalar)
        end

        # Psych-specific: Check if this is an alias
        #
        # @return [Boolean]
        def alias?
          inner_node.is_a?(::Psych::Nodes::Alias)
        end

        # Psych-specific: Get mapping entries as key-value pairs
        #
        # For Mapping nodes, children alternate key, value, key, value...
        #
        # @return [Array<Array(Node, Node)>] Key-value pairs
        def mapping_entries
          return [] unless mapping?

          pairs = []
          children.each_slice(2) do |key, val|
            pairs << [key, val] if key && val
          end
          pairs
        end

        private

        # Extract text from source using location
        #
        # @return [String] Extracted text
        def extract_text_from_location
          return '' unless inner_node.respond_to?(:start_line) && inner_node.respond_to?(:end_line)

          start_ln = inner_node.start_line || 0
          end_ln = inner_node.end_line || start_ln
          start_col = inner_node.start_column || 0
          end_col = inner_node.end_column || 0

          if start_ln == end_ln
            line = lines[start_ln] || ''
            line[start_col...end_col] || ''
          else
            result = []
            (start_ln..end_ln).each do |ln|
              line = lines[ln] || ''
              result << if ln == start_ln
                          line[start_col..]
                        elsif ln == end_ln
                          line[0...end_col]
                        else
                          line
                        end
            end
            result.compact.join
          end
        end
      end

      # Alias Point to the base class for compatibility
      Point = TreeHaver::Base::Point

      # Register the availability checker for RSpec dependency tags
      TreeHaver::BackendRegistry.register_availability_checker(:psych) do
        available?
      end
    end
  end
end
