# frozen_string_literal: true

module Ast
  module Merge
    module Navigable
      # Wraps any node (parser-backed or synthetic) with uniform navigation.
      #
      # Provides two levels of navigation:
      # 1. **Flat list navigation**: prev_statement, next_statement, index
      #    - Works for ALL nodes (synthetic and parser-backed)
      #    - Represents position in the flattened statement list
      #
      # 2. **Tree navigation**: tree_parent, tree_next, tree_previous, tree_children
      #    - Only available for parser-backed nodes
      #    - Delegates to inner_node's tree methods
      #
      # This allows code to work with the flat list for simple merging,
      # while still accessing tree structure for section-aware operations.
      #
      # @example Basic usage
      #   statements = Statement.build_list(raw_statements)
      #   stmt = statements[0]
      #
      #   # Flat navigation (always works)
      #   stmt.next           # => next statement in flat list
      #   stmt.previous       # => previous statement in flat list
      #   stmt.index          # => position in array
      #
      #   # Tree navigation (when available)
      #   stmt.tree_parent    # => parent in original AST (or nil)
      #   stmt.tree_next      # => next sibling in original AST (or nil)
      #   stmt.tree_children  # => children in original AST (or [])
      #
      # @example Section grouping
      #   # Group statements into sections by heading level
      #   sections = Statement.group_by_heading(statements, level: 3)
      #   sections.each do |section|
      #     puts "Section: #{section.heading.text}"
      #     section.statements.each { |s| puts "  - #{s.type}" }
      #   end
      #
      class Statement
        # @return [Object] The wrapped node (parser-backed or synthetic)
        attr_reader :node

        # @return [Integer] Index in the flattened statement list
        attr_reader :index

        # @return [Statement, nil] Previous statement in flat list
        attr_accessor :prev_statement

        # @return [Statement, nil] Next statement in flat list
        attr_accessor :next_statement

        # @return [Object, nil] Optional context/metadata for this statement
        attr_accessor :context

        # Initialize a Statement wrapper.
        #
        # @param node [Object] The node to wrap
        # @param index [Integer] Position in the statement list
        def initialize(node, index:)
          @node = node
          @index = index
          @prev_statement = nil
          @next_statement = nil
          @context = nil
        end

        class << self
          # Build a linked list of Statements from raw statements.
          #
          # @param raw_statements [Array<Object>] Raw statement nodes
          # @return [Array<Statement>] Linked statement list
          def build_list(raw_statements)
            statements = raw_statements.each_with_index.map do |node, i|
              new(node, index: i)
            end

            # Link siblings in flat list
            statements.each_cons(2) do |prev_stmt, next_stmt|
              prev_stmt.next_statement = next_stmt
              next_stmt.prev_statement = prev_stmt
            end

            statements
          end

          # Find statements matching a query.
          #
          # @param statements [Array<Statement>] Statement list
          # @param type [Symbol, String, nil] Node type to match (nil = any)
          # @param text [String, Regexp, nil] Text pattern to match
          # @yield [Statement] Optional block for custom matching
          # @return [Array<Statement>] Matching statements
          def find_matching(statements, type: nil, text: nil, &block)
            # If no criteria specified, return empty array (nothing to match)
            return [] if type.nil? && text.nil? && !block_given?

            statements.select do |stmt|
              matches = true
              matches &&= stmt.type.to_s == type.to_s if type
              matches &&= text.is_a?(Regexp) ? stmt.text.match?(text) : stmt.text.include?(text.to_s) if text
              matches &&= yield(stmt) if block_given?
              matches
            end
          end

          # Find the first statement matching criteria.
          #
          # @param statements [Array<Statement>] Statement list
          # @param type [Symbol, String, nil] Node type to match
          # @param text [String, Regexp, nil] Text pattern to match
          # @yield [Statement] Optional block for custom matching
          # @return [Statement, nil] First matching statement
          def find_first(statements, type: nil, text: nil, &block)
            find_matching(statements, type: type, text: text, &block).first
          end
        end

        # ============================================================
        # Flat list navigation (always available)
        # ============================================================

        # @return [Statement, nil] Next statement in flat list
        def next
          next_statement
        end

        # @return [Statement, nil] Previous statement in flat list
        def previous
          prev_statement
        end

        # @return [Boolean] true if this is the first statement
        def first?
          prev_statement.nil?
        end

        # @return [Boolean] true if this is the last statement
        def last?
          next_statement.nil?
        end

        # Iterate from this statement to the end (or until block returns false).
        #
        # @yield [Statement] Each statement
        # @return [Enumerator, nil]
        def each_following(&block)
          return to_enum(:each_following) unless block_given?

          current = self.next
          while current
            break unless yield(current)

            current = current.next
          end
        end

        # Collect statements until a condition is met.
        #
        # @yield [Statement] Each statement
        # @return [Array<Statement>] Statements until condition
        def take_until(&block)
          result = []
          each_following do |stmt|
            break if yield(stmt)

            result << stmt
            true
          end
          result
        end

        # ============================================================
        # Tree navigation (delegates to inner_node when available)
        # ============================================================

        # @return [Object, nil] Parent node in original AST
        def tree_parent
          inner = unwrapped_node
          inner.parent if inner.respond_to?(:parent)
        end

        # @return [Object, nil] Next sibling in original AST
        def tree_next
          inner = unwrapped_node
          inner.next if inner.respond_to?(:next)
        end

        # @return [Object, nil] Previous sibling in original AST
        def tree_previous
          inner = unwrapped_node
          inner.previous if inner.respond_to?(:previous)
        end

        # @return [Array<Object>] Children in original AST
        def tree_children
          inner = unwrapped_node
          if inner.respond_to?(:each)
            inner.to_a
          elsif inner.respond_to?(:children)
            inner.children
          else
            []
          end
        end

        # @return [Object, nil] First child in original AST
        def tree_first_child
          inner = unwrapped_node
          inner.first_child if inner.respond_to?(:first_child)
        end

        # @return [Object, nil] Last child in original AST
        def tree_last_child
          inner = unwrapped_node
          inner.last_child if inner.respond_to?(:last_child)
        end

        # @return [Boolean] true if tree navigation is available
        def has_tree_navigation?
          inner = unwrapped_node
          inner.respond_to?(:parent) || inner.respond_to?(:next)
        end

        # @return [Boolean] true if this is a synthetic node (no tree navigation)
        def synthetic?
          !has_tree_navigation?
        end

        # Calculate the tree depth (distance from root).
        #
        # @return [Integer] Depth in tree (0 = root level)
        def tree_depth
          depth = 0
          current = tree_parent
          while current
            depth += 1
            # Navigate up through parents
            break unless current.respond_to?(:parent)

            current = current.parent

          end
          depth
        end

        # Check if this node is at same or shallower depth than another.
        # Useful for determining section boundaries.
        #
        # @param other [Statement, Integer] Other statement or depth value
        # @return [Boolean] true if this node is at same or shallower depth
        def same_or_shallower_than?(other)
          other_depth = other.is_a?(Integer) ? other : other.tree_depth
          tree_depth <= other_depth
        end

        # ============================================================
        # Node delegation
        # ============================================================

        # @return [Symbol, String] Node type
        def type
          return node.type if node.respond_to?(:type)

          # Fallback: derive type from class name (handle anonymous classes)
          class_name = node.class.name
          class_name ? class_name.split('::').last : 'Anonymous'
        end

        # @return [Array, Object, nil] Node signature for matching
        def signature
          node.signature if node.respond_to?(:signature)
        end

        # @return [String] Node text content
        def text
          # TreeHaver nodes (and any node conforming to the unified API) provide #text.
          # No conditional fallbacks - nodes must conform to the API.
          node.text.to_s
        end

        # @return [Hash, nil] Source position info
        def source_position
          node.source_position if node.respond_to?(:source_position)
        end

        # @return [Integer, nil] Start line number
        def start_line
          pos = source_position
          pos[:start_line] if pos
        end

        # @return [Integer, nil] End line number
        def end_line
          pos = source_position
          pos[:end_line] if pos
        end

        # ============================================================
        # Node attribute helpers (language-agnostic)
        # ============================================================

        # Check if this node matches a type.
        #
        # @param expected_type [Symbol, String] Type to check
        # @return [Boolean]
        def type?(expected_type)
          type.to_s == expected_type.to_s
        end

        # Check if this node's text matches a pattern.
        #
        # @param pattern [String, Regexp] Pattern to match
        # @return [Boolean]
        def text_matches?(pattern)
          case pattern
          when Regexp
            text.match?(pattern)
          else
            text.include?(pattern.to_s)
          end
        end

        # Get an attribute from the underlying node.
        #
        # Tries multiple method names to support different parser APIs.
        #
        # @param name [Symbol, String] Attribute name
        # @param aliases [Array<Symbol>] Alternative method names
        # @return [Object, nil] Attribute value
        def node_attribute(name, *aliases)
          inner = unwrapped_node
          [name, *aliases].each do |method_name|
            return inner.send(method_name) if inner.respond_to?(method_name)
          end
          nil
        end

        # ============================================================
        # Utilities
        # ============================================================

        # Get the unwrapped inner node.
        #
        # @return [Object] The innermost node
        def unwrapped_node
          current = node
          current = current.inner_node while current.respond_to?(:inner_node) && current.inner_node != current
          current
        end

        # @return [String] Human-readable representation
        def inspect
          "#<Navigable::Statement[#{index}] type=#{type} tree=#{has_tree_navigation?}>"
        end

        # @return [String] String representation
        def to_s
          text.to_s.strip[0, 50]
        end

        # Delegate unknown methods to the wrapped node.
        def method_missing(method, *args, &block)
          if node.respond_to?(method)
            node.send(method, *args, &block)
          else
            super
          end
        end

        def respond_to_missing?(method, include_private = false)
          node.respond_to?(method, include_private) || super
        end
      end
    end
  end
end
