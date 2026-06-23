# frozen_string_literal: true

module TreeHaver
  # Unified Tree wrapper providing a consistent API across all backends
  #
  # This class wraps backend-specific tree objects and provides a unified interface.
  # It stores the source text to enable text extraction from nodes.
  #
  # == Wrapping/Unwrapping Contract
  #
  # TreeHaver follows a consistent pattern for object wrapping:
  #
  # 1. **TreeHaver::Parser** (top level) handles ALL wrapping/unwrapping
  # 2. **Backends** work exclusively with raw backend objects
  # 3. **User-facing API** uses only TreeHaver wrapper classes
  #
  # Specifically for trees:
  # - Backend Parser#parse returns raw backend tree (TreeSitter::Tree, TreeStump::Tree, etc.)
  # - TreeHaver::Parser#parse wraps it in TreeHaver::Tree
  # - TreeHaver::Parser#parse_string unwraps old_tree before passing to backend
  # - Backend Parser#parse_string receives raw backend tree, returns raw backend tree
  # - TreeHaver::Parser#parse_string wraps the returned tree
  #
  # This ensures:
  # - Backends are simple and consistent
  # - All complexity is in one place (TreeHaver top level)
  # - Users always work with TreeHaver wrapper classes
  #
  # @example Basic usage
  #   parser = TreeHaver::Parser.new
  #   parser.language = TreeHaver::Language.toml
  #   tree = parser.parse(source)
  #   root = tree.root_node
  #   puts root.type
  #
  # @example Incremental parsing (if backend supports it)
  #   tree = parser.parse("x = 1")
  #   # Edit the source: "x = 1" → "x = 42"
  #   tree.edit(
  #     start_byte: 4,
  #     old_end_byte: 5,
  #     new_end_byte: 6,
  #     start_point: { row: 0, column: 4 },
  #     old_end_point: { row: 0, column: 5 },
  #     new_end_point: { row: 0, column: 6 }
  #   )
  #   new_tree = parser.parse_string(tree, "x = 42")
  #
  # @example Accessing backend-specific features
  #   # Via passthrough (method_missing delegates to inner_tree)
  #   tree.some_backend_specific_method  # Automatically delegated
  #
  #   # Or explicitly via inner_tree
  #   tree.inner_tree.some_backend_specific_method
  class Tree < Base::Tree
    # The wrapped backend-specific tree object
    #
    # This provides direct access to the underlying backend tree for advanced usage
    # when you need backend-specific features not exposed by the unified API.
    #
    # @return [Object] The underlying tree (TreeSitter::Tree, TreeStump::Tree, etc.)
    # @example Accessing backend-specific methods
    #   # Print DOT graph (TreeStump-specific)
    #   if tree.inner_tree.respond_to?(:print_dot_graph)
    #     File.open("tree.dot", "w") do |f|
    #       tree.inner_tree.print_dot_graph(f)
    #     end
    #   end
    # NOTE: inner_tree is inherited from Base::Tree

    # The source text
    #
    # Stored to enable text extraction from nodes via byte offsets.
    #
    # @return [String] The original source code
    # NOTE: source is inherited from Base::Tree

    # @param tree [Object] Backend-specific tree object
    # @param source [String] Source text for node text extraction
    def initialize(tree, source: nil)
      super(tree, source: source)
    end

    # Get the root node of the tree
    #
    # @return [Node] Wrapped root node
    def root_node
      root = @inner_tree.root_node
      return if root.nil?

      Node.new(root, source: @source)
    end

    # Mark the tree as edited for incremental re-parsing
    #
    # Call this method after the source code has been modified but before
    # re-parsing. This tells tree-sitter which parts of the tree are
    # invalidated so it can efficiently re-parse only the affected regions.
    #
    # Not all backends support incremental parsing. Use {#supports_editing?}
    # to check before calling this method.
    #
    # @param start_byte [Integer] byte offset where the edit starts
    # @param old_end_byte [Integer] byte offset where the old text ended
    # @param new_end_byte [Integer] byte offset where the new text ends
    # @param start_point [Hash] starting position as `{ row:, column: }`
    # @param old_end_point [Hash] old ending position as `{ row:, column: }`
    # @param new_end_point [Hash] new ending position as `{ row:, column: }`
    # @return [void]
    # @raise [TreeHaver::NotAvailable] if the backend doesn't support incremental parsing
    # @see https://tree-sitter.github.io/tree-sitter/using-parsers#editing
    #
    # @example Incremental parsing workflow
    #   # Original source: "x = 1"
    #   tree = parser.parse("x = 1")
    #
    #   # Edit the source: replace "1" with "42" at byte offset 4
    #   tree.edit(
    #     start_byte: 4,
    #     old_end_byte: 5,     # "1" ends at byte 5
    #     new_end_byte: 6,     # "42" ends at byte 6
    #     start_point: { row: 0, column: 4 },
    #     old_end_point: { row: 0, column: 5 },
    #     new_end_point: { row: 0, column: 6 }
    #   )
    #
    #   # Re-parse with the edited tree for incremental parsing
    #   new_tree = parser.parse_string(tree, "x = 42")
    def edit(start_byte:, old_end_byte:, new_end_byte:, start_point:, old_end_point:, new_end_point:)
      # MRI backend (ruby_tree_sitter) requires an InputEdit object
      if defined?(::TreeSitter::InputEdit) && @inner_tree.is_a?(::TreeSitter::Tree)
        input_edit = ::TreeSitter::InputEdit.new
        input_edit.start_byte = start_byte
        input_edit.old_end_byte = old_end_byte
        input_edit.new_end_byte = new_end_byte

        # Convert hash points to Point objects if needed
        input_edit.start_point = make_point(start_point)
        input_edit.old_end_point = make_point(old_end_point)
        input_edit.new_end_point = make_point(new_end_point)

        @inner_tree.edit(input_edit)
      else
        # Other backends may accept keyword arguments directly
        @inner_tree.edit(
          start_byte: start_byte,
          old_end_byte: old_end_byte,
          new_end_byte: new_end_byte,
          start_point: start_point,
          old_end_point: old_end_point,
          new_end_point: new_end_point
        )
      end
    rescue NoMethodError => e
      # Re-raise as NotAvailable if it's about the edit method
      raise unless e.name == :edit || e.message.include?('edit')

      raise TreeHaver::NotAvailable,
            'Incremental parsing not supported by current backend. ' \
              'Use MRI (ruby_tree_sitter), Rust (tree_stump), or Java (java-tree-sitter / jtreesitter) backend.'
    end

    private

    # Convert a point hash to a TreeSitter::Point if available
    # @api private
    def make_point(point_hash)
      if defined?(::TreeSitter::Point)
        pt = ::TreeSitter::Point.new
        pt.row = point_hash[:row]
        pt.column = point_hash[:column]
        pt
      else
        point_hash
      end
    end

    public

    # Check if the current backend supports incremental parsing
    #
    # Incremental parsing allows tree-sitter to reuse unchanged nodes when
    # re-parsing edited source code, improving performance for large files
    # with small edits.
    #
    # @return [Boolean] true if {#edit} can be called on this tree
    # @example
    #   if tree.supports_editing?
    #     tree.edit(...)
    #     new_tree = parser.parse_string(tree, edited_source)
    #   else
    #     # Fall back to full re-parse
    #     new_tree = parser.parse(edited_source)
    #   end
    def supports_editing?
      # Try to get the edit method to verify it exists
      # This is more reliable than respond_to? with Delegator wrappers
      @inner_tree.method(:edit)
      true
    rescue NameError
      # NameError is the parent class of NoMethodError, so this catches both
      false
    end

    # String representation
    # @return [String]
    def inspect
      inner_class = @inner_tree ? @inner_tree.class.name : 'nil'
      "#<#{self.class} source_length=#{@source&.bytesize || 'unknown'} inner_tree=#{inner_class}>"
    end

    # Check if tree responds to a method (includes delegation to inner_tree)
    #
    # @param method_name [Symbol] method to check
    # @param include_private [Boolean] include private methods
    # @return [Boolean]
    def respond_to_missing?(method_name, include_private = false)
      @inner_tree.respond_to?(method_name, include_private) || super
    end

    # Delegate unknown methods to the underlying backend-specific tree
    #
    # This provides passthrough access for advanced usage when you need
    # backend-specific features not exposed by TreeHaver's unified API.
    #
    # The delegation is automatic and transparent - you can call backend-specific
    # methods directly on the TreeHaver::Tree and they'll be forwarded to the
    # underlying tree implementation.
    #
    # @param method_name [Symbol] method to call
    # @param args [Array] arguments to pass
    # @param block [Proc] block to pass
    # @return [Object] result from the underlying tree
    #
    # @example Using TreeStump-specific methods
    #   # print_dot_graph is TreeStump-specific
    #   File.open("tree.dot", "w") do |f|
    #     tree.print_dot_graph(f)  # Delegated to inner_tree
    #   end
    #
    # @example Safe usage with respond_to? check
    #   if tree.respond_to?(:print_dot_graph)
    #     File.open("tree.dot", "w") { |f| tree.print_dot_graph(f) }
    #   end
    #
    # @example Equivalent explicit access
    #   tree.print_dot_graph(file)              # Via passthrough (method_missing)
    #   tree.inner_tree.print_dot_graph(file)   # Explicit access (same result)
    #
    # @note This maintains backward compatibility with code written for
    #   specific backends while providing the benefits of the unified API
    def method_missing(method_name, *args, **kwargs, &block)
      if @inner_tree.respond_to?(method_name)
        @inner_tree.public_send(method_name, *args, **kwargs, &block)
      else
        super
      end
    end
  end
end
