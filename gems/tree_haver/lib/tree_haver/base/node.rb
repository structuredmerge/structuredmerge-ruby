# frozen_string_literal: true

module TreeHaver
  module Base
    # Base class for all backend Node implementations
    #
    # This class defines the API contract for Node objects across all backends.
    # It provides shared implementation for common behaviors and documents
    # required/optional methods that subclasses must implement.
    #
    # == Backend Architecture
    #
    # TreeHaver supports two categories of backends:
    #
    # === Tree-sitter Backends (MRI, Rust, FFI, Java)
    #
    # These backends use the native tree-sitter library (via different bindings).
    # They return raw `::TreeSitter::Node` objects which are wrapped by
    # `TreeHaver::Node` (which inherits from this class).
    #
    # - Backend Tree#root_node returns: `::TreeSitter::Node` (raw)
    # - TreeHaver::Tree#root_node wraps it in: `TreeHaver::Node`
    # - These backends do NOT define their own Tree/Node classes
    #
    # === Pure-Ruby/Plugin Backends (Citrus, Prism, Psych, Commonmarker, Markly)
    #
    # These backends define their own complete implementations:
    # - `Backend::X::Node` - wraps parser-specific node objects
    # - `Backend::X::Tree` - wraps parser-specific tree objects
    #
    # For consistency, these should also inherit from `Base::Node` and `Base::Tree`.
    #
    # @abstract Subclasses must implement #type, #start_byte, #end_byte, and #children
    # @see TreeHaver::Node The main wrapper class that inherits from this
    # @see TreeHaver::Backends::Citrus::Node Example of a backend-specific Node
    class Node
      include Comparable
      include Enumerable

      # The underlying backend-specific node object
      # @return [Object] Backend node
      attr_reader :inner_node

      # The source text
      # @return [String] Source code
      attr_reader :source

      # Source lines for byte offset calculations
      # @return [Array<String>] Lines of source
      attr_reader :lines

      # Create a new Node wrapper
      #
      # @param node [Object] The backend-specific node object
      # @param source [String, nil] The source code
      # @param lines [Array<String>, nil] Pre-split lines (optional optimization)
      def initialize(node, source: nil, lines: nil)
        @inner_node = node
        @source = source
        @lines = lines || source&.lines || []
      end

      # -- Required API Methods ------------------------------------------------

      # Get the node type as a string
      # @return [String] Node type
      def type
        raise NotImplementedError, "#{self.class}#type must be implemented"
      end

      # The parser's original node type before a backend applies any portable
      # vocabulary aliases. Backends without aliases use their public type.
      #
      # @return [String]
      def native_type
        type
      end

      # Get byte offset where the node starts
      # @return [Integer] Start byte offset
      def start_byte
        raise NotImplementedError, "#{self.class}#start_byte must be implemented"
      end

      # Get byte offset where the node ends
      # @return [Integer] End byte offset
      def end_byte
        raise NotImplementedError, "#{self.class}#end_byte must be implemented"
      end

      # Get all children as an array
      # @return [Array<Node>]
      def children
        raise NotImplementedError, "#{self.class}#children must be implemented"
      end

      # -- Derived Methods (use #children) -------------------------------------

      # Get the number of child nodes
      # @return [Integer] Number of children
      def child_count
        children.size
      end

      # Get a child node by index
      #
      # Returns nil for negative indices or indices out of bounds.
      # This matches tree-sitter behavior where negative indices are invalid.
      #
      # @param index [Integer] Child index (0-based, non-negative)
      # @return [Node, nil] The child node or nil
      def child(index)
        return if index.negative?
        return if index >= child_count

        children[index]
      end

      # Iterate over children
      # @yield [Node] Child node
      def each(&block)
        return to_enum(__method__) unless block

        children.each(&block)
      end

      # Retrieve the first child
      # @return [Node, nil]
      def first_child
        children.first
      end

      # Retrieve the last child
      # @return [Node, nil]
      def last_child
        children.last
      end

      # -- Optional API Methods (with default implementations) -----------------

      # Get the parent node
      # @return [Node, nil] Parent node or nil
      def parent
        nil
      end

      # Get the next sibling node
      # @return [Node, nil] Next sibling or nil
      def next_sibling
        nil
      end

      # Get the previous sibling node
      # @return [Node, nil] Previous sibling or nil
      def prev_sibling
        nil
      end

      # Check if this node is named (structural)
      # @return [Boolean] true if named
      def named?
        true
      end

      # Alias for named?
      alias structural? named?

      # Check if this node represents a syntax error
      # @return [Boolean] true on error
      def has_error?
        false
      end

      # Check if this node was inserted for error recovery
      # @return [Boolean] true if missing
      def missing?
        false
      end

      # Get the text content of this node
      # @return [String] Node text
      def text
        return '' unless source

        source[start_byte...end_byte] || ''
      end

      # Get a child by field name
      # @param _name [String, Symbol] Field name
      # @return [Node, nil] Child node or nil
      def child_by_field_name(_name)
        nil
      end

      # Get start position (row/col) - 0-based
      # @return [Hash{Symbol => Integer}] {row: 0, column: 0}
      def start_point
        { row: 0, column: 0 }
      end

      # Get end position (row/col) - 0-based
      # @return [Hash{Symbol => Integer}] {row: 0, column: 0}
      def end_point
        { row: 0, column: 0 }
      end

      # -- Shared Implementation -----------------------------------------------

      # Comparison based on byte range
      # @param other [Object]
      # @return [Integer, nil]
      def <=>(other)
        return unless other.respond_to?(:start_byte) && other.respond_to?(:end_byte)

        cmp = start_byte <=> other.start_byte
        return cmp unless cmp.zero?

        end_byte <=> other.end_byte
      end

      # Get 1-based start line
      # @return [Integer]
      def start_line
        sp = start_point
        row = if sp.is_a?(Hash)
                sp[:row]
              else
                (sp.respond_to?(:row) ? sp.row : 0)
              end
        row + 1
      end

      # Get 1-based end line
      # @return [Integer]
      def end_line
        ep = end_point
        row = if ep.is_a?(Hash)
                ep[:row]
              else
                (ep.respond_to?(:row) ? ep.row : 0)
              end
        row + 1
      end

      # Get unified source position hash
      # @return [Hash{Symbol => Integer}]
      def source_position
        sp = start_point
        ep = end_point

        sp_row = if sp.is_a?(Hash)
                   sp[:row]
                 else
                   (sp.respond_to?(:row) ? sp.row : 0)
                 end
        sp_col = if sp.is_a?(Hash)
                   sp[:column]
                 else
                   (sp.respond_to?(:column) ? sp.column : 0)
                 end
        ep_row = if ep.is_a?(Hash)
                   ep[:row]
                 else
                   (ep.respond_to?(:row) ? ep.row : 0)
                 end
        ep_col = if ep.is_a?(Hash)
                   ep[:column]
                 else
                   (ep.respond_to?(:column) ? ep.column : 0)
                 end

        {
          start_line: sp_row + 1,
          end_line: ep_row + 1,
          start_column: sp_col,
          end_column: ep_col
        }
      end

      # Human-readable representation
      # @return [String]
      def inspect
        class_name = self.class.name || "#{self.class.superclass&.name}(anonymous)"
        node_type = begin
          type
        rescue NotImplementedError
          '(not implemented)'
        end
        "#<#{class_name} type=#{node_type}>"
      end

      # String conversion returns the text content
      # @return [String]
      def to_s
        text
      end

      # Equality based on type and byte range
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        return false unless other.respond_to?(:type) && other.respond_to?(:start_byte) && other.respond_to?(:end_byte)

        type == other.type && start_byte == other.start_byte && end_byte == other.end_byte
      end

      protected

      # Calculate byte offset from line and column
      #
      # @param line [Integer] 0-based line number
      # @param column [Integer] 0-based column number
      # @return [Integer] Byte offset
      def calculate_byte_offset(line, column)
        return 0 if lines.empty?

        offset = 0
        lines.each_with_index do |line_content, idx|
          if idx < line
            offset += line_content.bytesize
          else
            offset += [column, line_content.bytesize].min
            break
          end
        end
        offset
      end
    end
  end
end
