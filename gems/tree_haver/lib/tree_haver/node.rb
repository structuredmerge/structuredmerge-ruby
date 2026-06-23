# frozen_string_literal: true

module TreeHaver
  # Unified Node wrapper providing a consistent API across all backends
  #
  # This class wraps backend-specific node objects (TreeSitter::Node, TreeStump::Node, etc.)
  # and provides a unified interface so code works identically regardless of which backend
  # is being used.
  #
  # The wrapper automatically maps backend differences:
  # - TreeStump uses `node.kind` → mapped to `node.type`
  # - TreeStump uses `node.is_named?` → mapped to `node.named?`
  # - All backends return consistent Point objects from position methods
  #
  # @example Basic node traversal
  #   tree = parser.parse(source)
  #   root = tree.root_node
  #
  #   puts root.type        # => "document"
  #   puts root.start_byte  # => 0
  #   puts root.text        # => full source text
  #
  #   root.children.each do |child|
  #     puts "#{child.type} at line #{child.start_point.row + 1}"
  #   end
  #
  # @example Position information
  #   node = tree.root_node.children.first
  #
  #   # Point objects work as both objects and hashes
  #   point = node.start_point
  #   point.row              # => 0 (method access)
  #   point[:row]            # => 0 (hash access)
  #   point.column           # => 0
  #
  #   # Byte offsets
  #   node.start_byte        # => 0
  #   node.end_byte          # => 23
  #
  # @example Error detection
  #   if node.has_error?
  #     puts "Parse error in subtree"
  #   end
  #
  #   if node.missing?
  #     puts "This node was inserted by error recovery"
  #   end
  #
  # @example Accessing backend-specific features
  #   # Via passthrough (method_missing delegates to inner_node)
  #   node.grammar_name  # TreeStump-specific, automatically delegated
  #
  #   # Or explicitly via inner_node
  #   node.inner_node.grammar_name  # Same result
  #
  #   # Check if backend supports a feature
  #   if node.inner_node.respond_to?(:some_feature)
  #     node.some_feature
  #   end
  #
  # @note This is the key to tree_haver's "write once, run anywhere" promise
  class Node < Base::Node
    # The wrapped backend-specific node object
    #
    # This provides direct access to the underlying backend node for advanced usage
    # when you need backend-specific features not exposed by the unified API.
    #
    # @return [Object] The underlying node (TreeSitter::Node, TreeStump::Node, etc.)
    # @example Accessing backend-specific methods
    #   # TreeStump-specific: grammar information
    #   if node.inner_node.respond_to?(:grammar_name)
    #     puts node.inner_node.grammar_name  # => "toml"
    #     puts node.inner_node.grammar_id    # => Integer
    #   end
    #
    #   # Check backend type
    #   case node.inner_node.class.name
    #   when /TreeStump/
    #     # TreeStump-specific code
    #   when /TreeSitter/
    #     # ruby_tree_sitter-specific code
    #   end
    # NOTE: inner_node is inherited from Base::Node

    # The source text for text extraction
    # @return [String]
    # NOTE: source is inherited from Base::Node

    # @param node [Object] Backend-specific node object
    # @param source [String] Source text for text extraction
    def initialize(node, source: nil)
      super(node, source: source)
    end

    # Get the node's type/kind as a string
    #
    # Maps backend-specific methods to a unified API:
    # - ruby_tree_sitter: node.type
    # - tree_stump: node.kind
    # - FFI: node.type
    #
    # @return [String] The node type
    def type
      if @inner_node.respond_to?(:type)
        @inner_node.type.to_s
      elsif @inner_node.respond_to?(:kind)
        @inner_node.kind.to_s
      else
        raise TreeHaver::Error, 'Backend node does not support type/kind'
      end
    end

    # Alias for type (tree_stump compatibility)
    #
    # tree_stump uses `kind` instead of `type` for node types.
    # This method delegates to `type` so either can be used.
    #
    # @return [String] The node type
    def kind
      type
    end

    def start_byte
      @inner_node.start_byte
    end

    # Get the node's end byte offset
    # @return [Integer]
    def end_byte
      @inner_node.end_byte
    end

    # Get the node's start position (row, column)
    #
    # @return [Point] with row and column accessors (also works as Hash)
    def start_point
      if @inner_node.respond_to?(:start_point)
        point = @inner_node.start_point
        # Handle both Point objects and hashes
        if point.is_a?(Hash)
          Point.new(point[:row], point[:column])
        else
          Point.new(point.row, point.column)
        end
      elsif @inner_node.respond_to?(:start_position)
        point = @inner_node.start_position
        # Handle both Point objects and hashes
        if point.is_a?(Hash)
          Point.new(point[:row], point[:column])
        else
          Point.new(point.row, point.column)
        end
      else
        raise TreeHaver::Error, 'Backend node does not support start_point/start_position'
      end
    end

    # Get the node's end position (row, column)
    #
    # @return [Point] with row and column accessors (also works as Hash)
    def end_point
      if @inner_node.respond_to?(:end_point)
        point = @inner_node.end_point
        # Handle both Point objects and hashes
        if point.is_a?(Hash)
          Point.new(point[:row], point[:column])
        else
          Point.new(point.row, point.column)
        end
      elsif @inner_node.respond_to?(:end_position)
        point = @inner_node.end_position
        # Handle both Point objects and hashes
        if point.is_a?(Hash)
          Point.new(point[:row], point[:column])
        else
          Point.new(point.row, point.column)
        end
      else
        raise TreeHaver::Error, 'Backend node does not support end_point/end_position'
      end
    end

    # Get the 1-based line number where this node starts
    #
    # Convenience method that converts 0-based row to 1-based line number.
    # This is useful for error messages and matching with editor line numbers.
    #
    # @return [Integer] 1-based line number
    def start_line
      start_point.row + 1
    end

    # Get the 1-based line number where this node ends
    #
    # Convenience method that converts 0-based row to 1-based line number.
    #
    # @return [Integer] 1-based line number
    def end_line
      end_point.row + 1
    end

    # Get position information as a hash
    #
    # Returns a hash with 1-based line numbers and 0-based columns.
    # This format is compatible with *-merge gems' FileAnalysisBase.
    #
    # @return [Hash{Symbol => Integer}] Position hash
    # @example
    #   node.source_position
    #   # => { start_line: 1, end_line: 3, start_column: 0, end_column: 10 }
    def source_position
      {
        start_line: start_line,
        end_line: end_line,
        start_column: start_point.column,
        end_column: end_point.column
      }
    end

    # Get the first child node
    #
    # Convenience method for iteration patterns that expect first_child.
    #
    # @return [Node, nil] First child node or nil if no children
    def first_child
      child(0)
    end

    # Get the node's text content
    #
    # @return [String]
    def text
      if @inner_node.respond_to?(:text)
        # Some backends (like TreeStump) require source as argument
        # Check arity to determine how to call
        arity = @inner_node.method(:text).arity
        if [0, -1].include?(arity)
          # No required arguments, or optional arguments only
          @inner_node.text
        elsif arity >= 1 && @source
          # Has required argument(s) - pass source
          @inner_node.text(@source)
        elsif @source
          # Fallback to byte extraction
          @source[start_byte...end_byte] || ''
        else
          raise TreeHaver::Error, 'Cannot extract text: backend requires source but none provided'
        end
      elsif @source
        # Fallback: extract from source using byte positions
        @source[start_byte...end_byte] || ''
      else
        raise TreeHaver::Error, 'Cannot extract text: node has no text method and no source provided'
      end
    end

    # Check if the node has an error
    # @return [Boolean]
    def has_error?
      @inner_node.has_error?
    end

    # Check if the node is missing
    # @return [Boolean]
    def missing?
      @inner_node.missing?
    end

    # Check if the node is named
    # @return [Boolean]
    def named?
      if @inner_node.respond_to?(:named?)
        @inner_node.named?
      elsif @inner_node.respond_to?(:is_named?)
        @inner_node.is_named?
      else
        true # Default to true if not supported
      end
    end

    # Check if the node is structural (non-terminal)
    #
    # In tree-sitter, this is equivalent to being a "named" node.
    # Named nodes represent actual syntactic constructs (e.g., table, keyvalue, string)
    # while anonymous nodes are syntax/punctuation (e.g., [, =, whitespace).
    #
    # For Citrus backends, this checks if the node is a non-terminal rule.
    #
    # @return [Boolean] true if this is a structural (non-terminal) node
    def structural?
      # Delegate to inner_node if it has its own structural? method (e.g., Citrus)
      if @inner_node.respond_to?(:structural?)
        @inner_node.structural?
      else
        # For tree-sitter backends, named? is equivalent to structural?
        # Named nodes are syntactic constructs; anonymous nodes are punctuation
        named?
      end
    end

    # Get the number of children
    # @return [Integer]
    def child_count
      @inner_node.child_count
    end

    # Get a child by index
    #
    # @param index [Integer] Child index
    # @return [Node, nil] Wrapped child node, or nil if index out of bounds
    def child(index)
      child_node = @inner_node.child(index)
      return if child_node.nil?

      Node.new(child_node, source: @source)
    rescue IndexError
      # Some backends (e.g., MRI w/ ruby_tree_sitter) raise IndexError for out of bounds
      nil
    end

    # Get a named child by index
    #
    # Returns the nth named child (skipping unnamed children).
    # Uses backend's native named_child if available, otherwise provides fallback.
    #
    # @param index [Integer] Named child index (0-based)
    # @return [Node, nil] Wrapped named child node, or nil if index out of bounds
    def named_child(index)
      # Try native implementation first
      if @inner_node.respond_to?(:named_child)
        child_node = @inner_node.named_child(index)
        return if child_node.nil?

        return Node.new(child_node, source: @source)
      end

      # Fallback: manually iterate through children and count named ones
      named_count = 0
      (0...child_count).each do |i|
        child_node = @inner_node.child(i)
        next if child_node.nil?

        # Check if this child is named
        is_named = if child_node.respond_to?(:named?)
                     child_node.named?
                   elsif child_node.respond_to?(:is_named?)
                     child_node.is_named?
                   else
                     true # Assume named if we can't determine
                   end

        next unless is_named
        return Node.new(child_node, source: @source) if named_count == index

        named_count += 1
      end

      nil # Index out of bounds
    end

    # Get the count of named children
    #
    # Uses backend's native named_child_count if available, otherwise provides fallback.
    #
    # @return [Integer] Number of named children
    def named_child_count
      # Try native implementation first
      return @inner_node.named_child_count if @inner_node.respond_to?(:named_child_count)

      # Fallback: count named children manually
      count = 0
      (0...child_count).each do |i|
        child_node = @inner_node.child(i)
        next if child_node.nil?

        # Check if this child is named
        is_named = if child_node.respond_to?(:named?)
                     child_node.named?
                   elsif child_node.respond_to?(:is_named?)
                     child_node.is_named?
                   else
                     true # Assume named if we can't determine
                   end

        count += 1 if is_named
      end

      count
    end

    # Get all children as wrapped nodes
    #
    # @return [Array<Node>] Array of wrapped child nodes
    def children
      (0...child_count).map { |i| child(i) }.compact
    end

    # Get named children only
    #
    # @return [Array<Node>] Array of named child nodes
    def named_children
      children.select(&:named?)
    end

    # Iterate over children
    #
    # @yield [Node] Each child node
    # @return [Enumerator, nil]
    def each(&block)
      return to_enum(__method__) unless block_given?

      children.each(&block)
    end

    # Get a child by field name
    #
    # @param name [String, Symbol] Field name
    # @return [Node, nil] The child node for that field
    def child_by_field_name(name)
      if @inner_node.respond_to?(:child_by_field_name)
        child_node = @inner_node.child_by_field_name(name.to_s)
        return if child_node.nil?

        Node.new(child_node, source: @source)
      else
        # Not all backends support field names
        nil
      end
    end

    # Alias for child_by_field_name
    alias field child_by_field_name

    # Get the parent node
    #
    # @return [Node, nil] The parent node
    def parent
      return unless @inner_node.respond_to?(:parent)

      parent_node = @inner_node.parent
      return if parent_node.nil?

      Node.new(parent_node, source: @source)
    end

    # Get next sibling
    #
    # @return [Node, nil]
    def next_sibling
      return unless @inner_node.respond_to?(:next_sibling)

      sibling = @inner_node.next_sibling
      return if sibling.nil?

      Node.new(sibling, source: @source)
    end

    # Get previous sibling
    #
    # @return [Node, nil]
    def prev_sibling
      return unless @inner_node.respond_to?(:prev_sibling)

      sibling = @inner_node.prev_sibling
      return if sibling.nil?

      Node.new(sibling, source: @source)
    end

    # String representation for debugging
    # @return [String]
    def inspect
      "#<#{self.class} type=#{type} bytes=#{start_byte}..#{end_byte}>"
    end

    # String representation
    # @return [String]
    def to_s
      text
    end

    # Compare nodes for ordering (used by Comparable module)
    #
    # Nodes are ordered by their position in the source:
    # 1. First by start_byte (earlier nodes come first)
    # 2. Then by end_byte for tie-breaking (shorter spans come first)
    # 3. Then by type for deterministic ordering
    #
    # This allows nodes to be sorted by position and used in sorted collections.
    # The Comparable module provides <, <=, ==, >=, >, and between? based on this.
    #
    # @param other [Node] node to compare with
    # @return [Integer, nil] -1, 0, 1, or nil if not comparable
    def <=>(other)
      return unless other.is_a?(Node)

      # Compare by position first (start_byte, then end_byte)
      cmp = start_byte <=> other.start_byte
      return cmp if cmp.nonzero?

      cmp = end_byte <=> other.end_byte
      return cmp if cmp.nonzero?

      # For nodes at the same position with same span, compare by type
      type <=> other.type
    end

    # Check equality based on inner_node identity
    #
    # Two nodes are equal if they wrap the same backend node object.
    # This is separate from the <=> comparison which orders by position.
    # Nodes at the same position but wrapping different backend nodes are
    # equal according to <=> (positional equality) but not equal according to == (identity equality).
    #
    # Note: We override Comparable's default == behavior to check inner_node identity
    # rather than just relying on <=> returning 0, because we want identity-based
    # equality for testing and collection membership, not position-based equality.
    #
    # @param other [Object] object to compare with
    # @return [Boolean] true if both nodes wrap the same inner_node
    def ==(other)
      return false unless other.is_a?(Node)

      @inner_node == other.inner_node
    end

    # Alias for == to support both styles
    alias eql? ==

    # Generate hash value for this node
    #
    # Uses the hash of the inner_node to ensure nodes wrapping the same
    # backend node have the same hash value.
    #
    # @return [Integer] hash value
    def hash
      @inner_node.hash
    end

    # Check if node responds to a method (includes delegation to inner_node)
    #
    # @param method_name [Symbol] method to check
    # @param include_private [Boolean] include private methods
    # @return [Boolean]
    def respond_to_missing?(method_name, include_private = false)
      @inner_node.respond_to?(method_name, include_private) || super
    end

    # Delegate unknown methods to the underlying backend-specific node
    #
    # This provides passthrough access for advanced usage when you need
    # backend-specific features not exposed by TreeHaver's unified API.
    #
    # The delegation is automatic and transparent - you can call backend-specific
    # methods directly on the TreeHaver::Node and they'll be forwarded to the
    # underlying node implementation.
    #
    # @param method_name [Symbol] method to call
    # @param args [Array] arguments to pass
    # @param block [Proc] block to pass
    # @return [Object] result from the underlying node
    #
    # @example Using TreeStump-specific methods
    #   # These methods don't exist in the unified API but are in TreeStump
    #   node.grammar_name      # => "toml" (delegated to inner_node)
    #   node.grammar_id        # => Integer (delegated to inner_node)
    #   node.kind_id           # => Integer (delegated to inner_node)
    #
    # @example Safe usage with respond_to? check
    #   if node.respond_to?(:grammar_name)
    #     puts "Using #{node.grammar_name} grammar"
    #   end
    #
    # @example Equivalent explicit access
    #   node.grammar_name              # Via passthrough (method_missing)
    #   node.inner_node.grammar_name   # Explicit access (same result)
    #
    # @note This maintains backward compatibility with code written for
    #   specific backends while providing the benefits of the unified API
    def method_missing(method_name, *args, **kwargs, &block)
      if @inner_node.respond_to?(method_name)
        @inner_node.public_send(method_name, *args, **kwargs, &block)
      else
        super
      end
    end
  end
end
