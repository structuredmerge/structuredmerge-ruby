# frozen_string_literal: true

module Toml
  module Merge
    # Wraps tree-sitter nodes with comment associations, line information, and signatures.
    # This provides a unified interface for working with TOML AST nodes during merging.
    #
    # Inherits common functionality from Ast::Merge::NodeWrapperBase:
    # - Source context (lines, source, comments)
    # - Line info extraction
    # - Basic methods: #type, #text, #signature
    #
    # Adds TOML-specific functionality:
    # - Backend awareness for Citrus/tree-sitter normalization
    # - Type predicates using NodeTypeNormalizer
    # - Structural normalization for Citrus backend (pairs as siblings)
    #
    # @example Basic usage
    #   parser = TreeHaver::Parser.new
    #   parser.language = TreeHaver::Language.toml
    #   tree = parser.parse(source)
    #   wrapper = NodeWrapper.new(tree.root_node, lines: source.lines, source: source)
    #   wrapper.signature # => [:table, "section"]
    #
    # @see Ast::Merge::NodeWrapperBase
    class NodeWrapper < Ast::Merge::NodeWrapperBase
      class << self
        # Wrap a tree-sitter node, returning nil for nil input.
        #
        # @param node [TreeHaver::Node, nil] tree-sitter node to wrap
        # @param lines [Array<String>] Source lines for content extraction
        # @param source [String, nil] Original source string
        # @param leading_comments [Array<Hash>] Comments before this node
        # @param inline_comment [Hash, nil] Inline comment on the node's line
        # @param backend [Symbol] The backend used for parsing (:tree_sitter or :citrus)
        # @return [NodeWrapper, nil] Wrapped node or nil if node is nil
        def wrap(node, lines, source: nil, leading_comments: nil, inline_comment: nil, backend: :tree_sitter,
                 comment_entries: nil, comment_tracker: nil)
          return if node.nil?

          new(
            node,
            lines: lines,
            source: source,
            leading_comments: leading_comments,
            inline_comment: inline_comment,
            backend: backend,
            comment_entries: comment_entries,
            comment_tracker: comment_tracker
          )
        end
      end

      def initialize(node, lines:, source: nil, leading_comments: nil, inline_comment: nil, **options)
        @explicit_leading_comments = !leading_comments.nil?
        @explicit_inline_comment = !inline_comment.nil?

        super(
          node,
          lines: lines,
          source: source,
          leading_comments: leading_comments || [],
          inline_comment: inline_comment,
          **options,
        )

        normalize_toml_line_range!
        hydrate_comment_associations!
      end

      # @return [Symbol] The backend used for parsing
      attr_reader :backend

      # @return [TreeHaver::Node, nil] The document root node for sibling lookups
      attr_reader :document_root

      # Process TOML-specific options (backend, document_root)
      # @param options [Hash] Additional options
      def process_additional_options(options)
        @backend = options.fetch(:backend, :tree_sitter)
        @document_root = options[:document_root]
        @comment_entries = Array(options[:comment_entries])
        @comment_tracker = options[:comment_tracker]
        @raw_text = options[:raw_text]
      end

      def node_text(ts_node)
        return '' unless ts_node.respond_to?(:start_byte) && ts_node.respond_to?(:end_byte)

        length = ts_node.end_byte - ts_node.start_byte
        return @source[ts_node.start_byte, length].to_s if @backend == :citrus

        super
      end

      def normalize_toml_line_range!
        return unless pair?
        return unless @start_line && @end_line && @end_line > @start_line

        range_text = if @backend == :citrus
                       node_text(citrus_pair_value_node || @node).rstrip
                     else
                       node_text(@node).sub(/\n\z/, '')
                     end
        line_count = [range_text.lines.count, 1].max
        @end_line = @start_line + line_count - 1
      end

      # Get the canonical (normalized) type for this node
      # @return [Symbol]
      def canonical_type
        return parslet_element_canonical_type if parslet_element_node?

        NodeTypeNormalizer.canonical_type(@node.type, @backend)
      end

      # Check if this node has a specific type (checks both raw and canonical)
      # @param type_name [Symbol, String] Type to check
      # @return [Boolean]
      def type?(type_name)
        type_sym = type_name.to_sym
        @node.type.to_sym == type_sym || canonical_type == type_sym
      end

      # Check if this is a TOML table (section)
      # @return [Boolean]
      def table?
        canonical_type == :table
      end

      # Check if this is a TOML array of tables
      # Uses NodeTypeNormalizer for backend-agnostic type checking.
      # @return [Boolean]
      def array_of_tables?
        canonical_type == :array_of_tables
      end

      # Check if this is a TOML inline table
      # @return [Boolean]
      def inline_table?
        canonical_type == :inline_table
      end

      # Check if this is a TOML array
      # @return [Boolean]
      def array?
        canonical_type == :array
      end

      # Check if this is a TOML string
      # @return [Boolean]
      def string?
        canonical_type == :string
      end

      # Check if this is a TOML integer
      # @return [Boolean]
      def integer?
        canonical_type == :integer
      end

      # Check if this is a TOML float
      # @return [Boolean]
      def float?
        canonical_type == :float
      end

      # Check if this is a TOML boolean
      # @return [Boolean]
      def boolean?
        canonical_type == :boolean
      end

      # Check if this is a key-value pair
      # @return [Boolean]
      def pair?
        canonical_type == :pair
      end

      # Check if this is a comment
      # @return [Boolean]
      def comment?
        canonical_type == :comment
      end

      # Check if this is a datetime
      # @return [Boolean]
      def datetime?
        canonical_type == :datetime
      end

      # Check if this is the document root
      # @return [Boolean]
      def document?
        canonical_type == :document
      end

      # Get the table name (header) if this is a table
      # @return [String, nil]
      def table_name
        return unless table? || array_of_tables?

        # Find the dotted_key or bare_key child that represents the table name
        table_name_container.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          if NodeTypeNormalizer.key_type?(child_canonical)
            # Strip whitespace (Citrus backend includes trailing space in key nodes)
            return node_text(child)&.strip
          end
        end
        parslet_element_table_name
      end

      # Get the key name if this is a pair node
      # @return [String, nil]
      def key_name
        return unless pair?

        # In TOML, pair has key children (bare_key, quoted_key, or dotted_key)
        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          next unless NodeTypeNormalizer.key_type?(child_canonical)

          key_text = node_text(child)
          # Remove surrounding quotes if present, and strip whitespace
          # (Citrus backend includes trailing space in key nodes)
          return key_text&.gsub(/\A["']|["']\z/, '')&.strip
        end
        nil
      end

      # Get the value node if this is a pair
      # @return [NodeWrapper, nil]
      def value_node
        return unless pair?

        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          # Skip keys, equals sign, whitespace, and unknown (Citrus uses these for delimiters)
          next if NodeTypeNormalizer.key_type?(child_canonical)
          next if %i[equals whitespace unknown space].include?(child_canonical)

          if @backend == :parslet && child_canonical == :value
            scalar_child = each_child(child).find do |grandchild|
              grandchild_canonical = NodeTypeNormalizer.canonical_type(grandchild.type, @backend)
              !%i[whitespace unknown space].include?(grandchild_canonical)
            end

            if scalar_child
              return NodeWrapper.new(
                scalar_child,
                lines: @lines,
                source: @source,
                backend: @backend,
                document_root: @document_root,
                comment_entries: @comment_entries,
                comment_tracker: comment_tracker,
                raw_text: raw_pair_value_text
              )
            end
          end

          return NodeWrapper.new(
            child,
            lines: @lines,
            source: @source,
            backend: @backend,
            document_root: @document_root
          )
        end
        nil
      end

      def text
        return @raw_text if @raw_text

        super
      end

      # Get key-value pairs from a table or inline_table.
      #
      # Handles structural differences between backends:
      # - Tree-sitter: pairs are children of the table node
      # - Citrus: pairs are siblings at document level (table only contains header)
      #
      # For Citrus backend, when no pair children are found, we look for sibling
      # pairs in the document that belong to this table (pairs after this table's
      # header but before the next table).
      #
      # @return [Array<NodeWrapper>]
      def pairs
        return [] unless table? || inline_table? || document? || array_of_tables?

        # First, try to find pairs as direct children (tree-sitter structure)
        result = collect_child_pairs
        return result if result.any?

        # For Citrus backend: pairs are siblings, not children
        # Look for pairs in document that belong to this table
        return [] if @document_root.nil? || !(table? || array_of_tables?)

        collect_sibling_pairs_for_table
      end

      # Get array elements if this is an array
      #
      # Handles structural differences between backends:
      # - Tree-sitter: values are direct children of array node
      # - Citrus: values are nested inside array_elements container
      #
      # @return [Array<NodeWrapper>]
      def elements
        return [] unless array?

        result = []
        collect_array_elements(@node, result)
        result
      end

      # Get mergeable children - the semantically meaningful children for tree merging
      # For tables, returns pairs. For arrays, returns elements.
      # For other node types, returns empty array (leaf nodes).
      # @return [Array<NodeWrapper>]
      def mergeable_children
        case canonical_type
        when :table, :inline_table, :array_of_tables
          pairs
        when :array
          elements
        when :document
          # Return top-level pairs and tables
          result = []
          @node.each do |child|
            child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
            next if child_canonical == :comment

            result << NodeWrapper.new(
              child,
              lines: @lines,
              source: @source,
              backend: @backend,
              document_root: @document_root
            )
          end
          result
        else
          []
        end
      end

      # Check if this node is a container (has mergeable children)
      # @return [Boolean]
      def container?
        table? || array_of_tables? || inline_table? || array? || document?
      end

      # Get the opening line for a table (the line with [table_name])
      # @return [String, nil]
      def opening_line
        return unless @start_line
        return unless table? || array_of_tables?

        @lines[@start_line - 1]
      end

      # Get the closing line for a container node
      # For tables, this is the last line of content before the next table or EOF
      # @return [String, nil]
      def closing_line
        return unless container? && @end_line

        @lines[@end_line - 1]
      end

      # Get the content for this node from source lines.
      #
      # Handles structural differences between backends:
      # - Tree-sitter: table nodes include pairs, so start_line..end_line covers everything
      # - Citrus: table nodes only include header, so we extend to include associated pairs
      #
      # @return [String]
      def content
        return '' unless @start_line

        # For tables with Citrus backend, extend end_line to include pairs
        effective_end = effective_end_line
        return '' unless effective_end

        (@start_line..effective_end).map { |ln| @lines[ln - 1] }.compact.join("\n")
      end

      # Get the effective end line for this node, accounting for Citrus backend.
      # For Citrus tables, this extends to the line before the next table.
      # @return [Integer, nil]
      def effective_end_line
        return @end_line if !(table? || array_of_tables?) || @document_root.nil?

        # Check if we have pairs as children (tree-sitter structure). Some
        # backends expose table node spans that run through the next table
        # boundary, so use the semantic child range when it is available.
        child_pairs = collect_child_pairs
        return child_pairs.map(&:end_line).compact.max || @start_line if child_pairs.any?

        # Citrus structure: find the last pair that belongs to us
        sibling_pairs = collect_sibling_pairs_for_table
        return @end_line if sibling_pairs.empty?

        # Return the end line of the last pair
        sibling_pairs.map(&:end_line).compact.max || @end_line
      end

      protected

      # Override wrap_child to use Toml::Merge::NodeWrapper with proper options
      def wrap_child(child)
        build_wrapped_node(child)
      end

      def compute_signature(node)
        # Use canonical type for signature generation
        # Pass @backend to ensure correct type mapping for Citrus vs tree-sitter
        canonical = node.equal?(@node) ? canonical_type : NodeTypeNormalizer.canonical_type(node.type, @backend)

        case canonical
        when :document
          # Root document
          [:document]
        when :table
          # Tables identified by their header name
          name = node.equal?(@node) ? table_name : node_text(node)&.strip
          [:table, name]
        when :array_of_tables
          # Array of tables identified by their header name
          name = node.equal?(@node) ? table_name : node_text(node)&.strip
          [:array_of_tables, name]
        when :pair
          # Pairs identified by their key name
          key = node.equal?(@node) ? key_name : node_text(node)&.strip
          [:pair, key]
        when :inline_table
          # Inline tables identified by their keys
          keys = extract_inline_table_keys(node)
          [:inline_table, keys.sort]
        when :array
          # Arrays identified by their length
          elements_count = 0
          node.each do |c|
            elements_count += 1 unless %i[comment comma bracket_open
                                          bracket_close].include?(NodeTypeNormalizer.canonical_type(c.type, @backend))
          end
          [:array, elements_count]
        when :string
          # Strings identified by their content
          [:string, node_text(node)]
        when :integer
          # Integers identified by their value
          [:integer, node_text(node)]
        when :float
          # Floats identified by their value
          [:float, node_text(node)]
        when :boolean
          # Booleans
          [:boolean, node_text(node)]
        when :datetime
          # Datetime values
          [:datetime, node_text(node)]
        when :comment
          # Comments identified by their content
          [:comment, node_text(node)&.strip]
        else
          # Generic fallback - use canonical type in signature
          content_preview = node_text(node)&.slice(0, 50)&.strip
          [canonical, content_preview]
        end
      end

      private

      def citrus_pair_value_node
        each_child(@node).find do |child|
          canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          !NodeTypeNormalizer.key_type?(canonical) &&
            !%i[comment equals whitespace unknown space indent line_break].include?(canonical)
        end
      end

      def table_name_container
        return @node unless parslet_element_node?

        each_child(@node).find do |child|
          canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          NodeTypeNormalizer.table_type?(canonical)
        end || @node
      end

      def parslet_element_node?
        @backend == :parslet && @node.type.to_s.match?(/\Aelement(?:_\d+)?\z/)
      end

      def parslet_element_canonical_type
        child_canonicals = each_child(@node).map do |child|
          NodeTypeNormalizer.canonical_type(child.type, @backend)
        end

        return :table if child_canonicals.include?(:table)
        return :array_of_tables if child_canonicals.include?(:array_of_tables)
        return :pair if child_canonicals.any? do |type|
          NodeTypeNormalizer.key_type?(type)
        end && child_canonicals.include?(:value)

        :element
      end

      def parslet_element_table_name
        return unless parslet_element_node?

        name = node_text(@node)&.strip
        return if name.nil? || name.empty?
        return if name.include?('=')

        name
      end

      def each_child(node)
        children = []
        node.each { |child| children << child }
        children
      end

      def extract_inline_table_keys(inline_table_node)
        keys = []
        collect_inline_table_keys_recursive(inline_table_node, keys)
        keys
      end

      def raw_pair_value_text
        return unless pair? && @start_line

        line = @lines[@start_line - 1].to_s
        return if line.empty?

        equals_index = line.index('=')
        return unless equals_index

        inline_comment = comment_tracker&.inline_comment_for(@node, line_num: @start_line)
        value_end = inline_comment ? inline_comment[:column] : line.bytesize
        raw_value = line.byteslice((equals_index + 1)...value_end)
        raw_value&.strip
      end

      # Recursively collect keys from inline table, handling both tree-sitter and Citrus structures.
      #
      # Tree-sitter inline_table structure:
      #   inline_table -> pair -> bare_key (direct children)
      #
      # Citrus inline_table structure:
      #   inline_table -> optional -> keyvalue -> keyvalue -> stripped_key -> key -> bare_key
      #   With repeat and unknown nodes containing additional key-values
      #
      def collect_inline_table_keys_recursive(node, keys)
        node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          child_type_raw = child.type.to_sym

          # For Citrus: recurse into container nodes that hold pairs/keys
          # For tree-sitter: only recurse into pairs
          if @backend == :citrus
            if %i[optional repeat keyvalue unknown].include?(child_type_raw)
              collect_inline_table_keys_recursive(child, keys)
              next
            end
          elsif child_canonical == :pair
            # Tree-sitter: pairs contain keys directly
            child.each do |pair_child|
              pair_child_canonical = NodeTypeNormalizer.canonical_type(pair_child.type, @backend)
              next unless NodeTypeNormalizer.key_type?(pair_child_canonical)

              key_text = node_text(pair_child)&.gsub(/\A["']|["']\z/, '')&.strip
              keys << key_text if key_text && !key_text.empty?
              break
            end
            next
          end

          # Skip whitespace and punctuation
          next if %i[whitespace space brace_open brace_close comma].include?(child_canonical)

          # Found a key node - extract the key text (Citrus path)
          if NodeTypeNormalizer.key_type?(child_canonical)
            key_text = node_text(child)&.gsub(/\A["']|["']\z/, '')&.strip
            keys << key_text if key_text && !key_text.empty?
          end
        end
      end

      # Collect pairs that are direct children of this node.
      # This is the standard tree-sitter structure.
      # @return [Array<NodeWrapper>]
      def collect_child_pairs
        result = []
        @node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          next unless child_canonical == :pair

          result << build_wrapped_node(child)
        end
        result
      end

      # Collect pairs from document siblings that belong to this table.
      # Used for Citrus backend where pairs are siblings, not children.
      #
      # A pair belongs to this table if:
      # - It appears after this table's header line
      # - It appears before the next table's header line (or end of document)
      #
      # @return [Array<NodeWrapper>]
      def collect_sibling_pairs_for_table
        result = []
        my_start = @start_line
        return result unless my_start

        # Find the next table's start line (to know where our pairs end)
        next_table_start = find_next_table_start_line

        # Iterate through document children to find pairs in our range
        @document_root.each do |sibling|
          sibling_wrapper = build_wrapped_node(sibling)
          next unless sibling_wrapper.pair?

          sibling_start = sibling_wrapper.start_line
          next unless sibling_start

          # Pair must be after our header
          next if sibling_start <= my_start

          # Pair must be before the next table (if there is one)
          next if next_table_start && sibling_start >= next_table_start

          result << sibling_wrapper
        end

        result
      end

      # Find the start line of the next table in the document.
      # Returns nil if this is the last table.
      # @return [Integer, nil]
      def find_next_table_start_line
        return unless @document_root

        my_start = @start_line
        next_table_start = nil

        @document_root.each do |sibling|
          sibling_wrapper = build_wrapped_node(sibling)
          next unless sibling_wrapper.table? || sibling_wrapper.array_of_tables?

          sibling_start = sibling_wrapper.start_line
          next unless sibling_start
          next if sibling_start <= my_start

          # Found a table after us - track the closest one
          next_table_start = sibling_start if next_table_start.nil? || sibling_start < next_table_start
        end

        next_table_start
      end

      # Recursively collect array elements, handling Citrus's nested structure.
      #
      # Citrus array structure:
      #   array -> array_elements -> array_elements -> decimal_integer + repeat
      #   repeat -> indent -> decimal_integer (for each subsequent element)
      #
      # @param node [Object] Node to collect elements from
      # @param result [Array<NodeWrapper>] Array to append elements to
      def collect_array_elements(node, result)
        node.each do |child|
          child_canonical = NodeTypeNormalizer.canonical_type(child.type, @backend)
          child_type_raw = child.type.to_sym

          # For Citrus: recurse into container nodes that hold values
          if %i[array_elements repeat indent].include?(child_type_raw)
            collect_array_elements(child, result)
            next
          end

          # Skip punctuation, comments, whitespace, and structural nodes
          next if child_canonical == :comment
          next if %i[comma bracket_open bracket_close].include?(child_canonical)
          next if %i[whitespace unknown space array_comments sign].include?(child_canonical)

          # This is an actual value element (integer, string, boolean, etc.)
          result << build_wrapped_node(child)
        end
      end

      def build_wrapped_node(node)
        NodeWrapper.new(
          node,
          lines: @lines,
          source: @source,
          backend: @backend,
          document_root: @document_root,
          comment_entries: @comment_entries,
          comment_tracker: comment_tracker
        )
      end

      def node_start_line(node)
        extract_point_row(node.respond_to?(:start_point) ? node.start_point : nil)&.+(1)
      end

      def node_end_line(node)
        extract_point_row(node.respond_to?(:end_point) ? node.end_point : nil)&.+(1)
      end

      def extract_point_row(point)
        return point.row if point.respond_to?(:row)
        return point[:row] if point.is_a?(Hash)

        nil
      end

      def hydrate_comment_associations!
        return unless comment_tracker

        unless @explicit_leading_comments || @start_line.nil?
          @leading_comments = comment_tracker.leading_comments_before(@start_line)
        end
        return if @explicit_inline_comment || @start_line.nil?

        @inline_comment = comment_tracker.inline_comment_for(@node,
                                                             line_num: @start_line)
      end

      def comment_tracker
        @comment_tracker ||= (CommentTracker.new(@lines, @comment_entries, backend: @backend) if @comment_entries.any?)
      end
    end
  end
end
