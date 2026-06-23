# frozen_string_literal: true

module Ast
  module Merge
    # Base class for format-specific node wrappers used in *-merge gems.
    #
    # This provides common functionality for wrapping TreeHaver nodes with:
    # - Source context (lines, source string)
    # - Line information (start_line, end_line)
    # - Comment associations (leading_comments, inline_comment)
    # - Content extraction (text, content)
    # - Signature generation (abstract)
    #
    # ## Relationship to NodeTyping::Wrapper
    #
    # This class is DIFFERENT from `Ast::Merge::NodeTyping::Wrapper`:
    #
    # - **NodeWrapperBase**: Provides format-specific functionality (line info,
    #   signatures, comments, type predicates). Used to wrap raw TreeHaver nodes
    #   with rich context needed for merging.
    #
    # - **NodeTyping::Wrapper**: Adds a custom `merge_type` attribute for merge
    #   classification. Used by SmartMergerBase to apply custom typing rules.
    #
    # A node CAN be wrapped by both:
    # ```
    # NodeTyping::Wrapper(Toml::Merge::NodeWrapper(tree_sitter_node))
    # ```
    #
    # The `NodeTyping.unwrap` method handles unwrapping `NodeTyping::Wrapper`,
    # while `NodeWrapperBase#node` provides access to the underlying TreeHaver node.
    #
    # ## Subclass Responsibilities
    #
    # Subclasses MUST implement:
    # - `#compute_signature(node)` - Generate a signature for node matching
    #
    # Subclasses SHOULD implement format-specific type predicates:
    # - TOML: `#table?`, `#pair?`, `#array_of_tables?`, etc.
    # - JSON: `#object?`, `#array?`, `#pair?`, etc.
    # - Bash: `#function_definition?`, `#variable_assignment?`, etc.
    #
    # @example Creating a format-specific wrapper
    #   class NodeWrapper < Ast::Merge::NodeWrapperBase
    #     def table?
    #       type == :table
    #     end
    #
    #     private
    #
    #     def compute_signature(node)
    #       case node.type.to_sym
    #       when :table
    #         [:table, table_name]
    #       else
    #         [node.type.to_sym]
    #       end
    #     end
    #   end
    #
    # @abstract Subclass and implement `#compute_signature`
    class NodeWrapperBase
      # @return [Object] The wrapped TreeHaver node
      attr_reader :node

      # @return [Array<String>] Source lines for content extraction
      attr_reader :lines

      # @return [String] The original source string
      attr_reader :source

      # @return [Array<Hash>] Leading comments associated with this node
      attr_reader :leading_comments

      # @return [Hash, nil] Inline/trailing comment on the same line
      attr_reader :inline_comment

      # @return [Integer, nil] Start line (1-based)
      attr_reader :start_line

      # @return [Integer, nil] End line (1-based)
      attr_reader :end_line

      # Initialize the node wrapper with source context.
      #
      # @param node [Object] TreeHaver node to wrap
      # @param lines [Array<String>] Source lines for content extraction
      # @param source [String, nil] Original source string for byte-based text extraction
      # @param leading_comments [Array<Hash>] Comments before this node
      # @param inline_comment [Hash, nil] Inline comment on the node's line
      # @param options [Hash] Additional options for subclasses (forward compatibility)
      def initialize(node, lines:, source: nil, leading_comments: [], inline_comment: nil, **options)
        @node = node
        @lines = lines
        @source = source || lines.join("\n")
        @leading_comments = leading_comments
        @inline_comment = inline_comment

        # Store additional options for subclasses to use
        process_additional_options(options)

        # Extract line information from the node (0-indexed to 1-indexed)
        extract_line_info(node)

        # Handle edge case where end_line might be before start_line
        @end_line = @start_line if @start_line && @end_line && @end_line < @start_line
      end

      # Process additional options. Override in subclasses to handle format-specific options.
      # @param options [Hash] Additional options
      def process_additional_options(options)
        # Default: no-op. Subclasses can override to process options like :backend, :document_root
      end

      # Generate a signature for this node for matching purposes.
      # Signatures are used to identify corresponding nodes between template and destination.
      #
      # @return [Array, nil] Signature array or nil if not signaturable
      def signature
        compute_signature(@node)
      end

      # Get the node type as a symbol.
      # @return [Symbol]
      def type
        @node.type.to_sym
      end

      # Check if this node has a specific type.
      # @param type_name [Symbol, String] Type to check
      # @return [Boolean]
      def type?(type_name)
        @node.type.to_s == type_name.to_s
      end

      # Check if this is a freeze node.
      # Override in subclasses if freeze node detection differs.
      # @return [Boolean]
      def freeze_node?
        false
      end

      # Get the text content for this node by extracting from source using byte positions.
      # @return [String]
      def text
        node_text(@node)
      end

      # Extract text from a node using byte positions.
      # Uses byteslice for correct multi-byte character handling (e.g. emoji).
      # @param ts_node [Object] The TreeHaver node
      # @return [String]
      def node_text(ts_node)
        return '' unless ts_node.respond_to?(:start_byte) && ts_node.respond_to?(:end_byte)

        length = ts_node.end_byte - ts_node.start_byte
        text = @source.byteslice(ts_node.start_byte, length)
        return text if text&.valid_encoding?

        # Some parser adapters expose character offsets through byte-named
        # methods. Fall back before scrubbing so Unicode source is preserved.
        text = @source[ts_node.start_byte, length]
        return text if text&.valid_encoding?

        text.to_s.scrub
      end

      # Get the content for this node from source lines.
      # @return [String]
      def content
        return '' unless @start_line && @end_line

        (@start_line..@end_line).map { |ln| @lines[ln - 1] }.compact.join("\n")
      end

      # Convert the wrapper's raw leading comment hashes into a shared region.
      #
      # @param style [Comment::Style, Symbol, nil] line-comment style to use for conversion
      # @param metadata [Hash] extra region metadata
      # @return [Comment::Region, nil]
      def leading_comment_region(style: nil, **metadata)
        comments_to_region(:leading, leading_comments, style: style, **metadata)
      end

      # Convert the wrapper's raw inline comment hash into a shared region.
      #
      # @param style [Comment::Style, Symbol, nil] line-comment style to use for conversion
      # @param metadata [Hash] extra region metadata
      # @return [Comment::Region, nil]
      def inline_comment_region(style: nil, **metadata)
        comments_to_region(:inline, inline_comment ? [inline_comment] : [], style: style, **metadata)
      end

      # Build a shared attachment from the wrapper's raw comment hashes.
      #
      # This provides an incremental bridge from existing `leading_comments` /
      # `inline_comment` flows to the normalized merge-facing comment model.
      #
      # @param style [Comment::Style, Symbol, nil] line-comment style to use for conversion
      # @param metadata [Hash] extra attachment metadata
      # @return [Comment::Attachment]
      def comment_attachment(style: nil, **metadata)
        Comment::Attachment.new(
          owner: self,
          leading_region: leading_comment_region(style: style, **metadata),
          inline_region: inline_comment_region(style: style, **metadata),
          metadata: {
            source: :node_wrapper_base
          }.merge(metadata)
        )
      end

      # Check whether the wrapper's leading comment region contains a freeze directive.
      #
      # @param freeze_token [String] Freeze token to detect
      # @param style [Comment::Style, Symbol, nil] line-comment style to use for conversion
      # @param metadata [Hash] extra region metadata
      # @return [Boolean]
      def leading_comment_freeze?(freeze_token, style: nil, **metadata)
        region = leading_comment_region(style: style, **metadata)
        region.respond_to?(:freeze?) && region.freeze?(freeze_token)
      end

      # Check whether the wrapper's leading comment region contains an unfreeze directive.
      #
      # @param freeze_token [String] Freeze token to detect
      # @param style [Comment::Style, Symbol, nil] line-comment style to use for conversion
      # @param metadata [Hash] extra region metadata
      # @return [Boolean]
      def leading_comment_unfreeze?(freeze_token, style: nil, **metadata)
        region = leading_comment_region(style: style, **metadata)
        region.respond_to?(:unfreeze?) && region.unfreeze?(freeze_token)
      end

      # Check if this node is a container (has children for merging).
      # Override in subclasses to define container types.
      # @return [Boolean]
      def container?
        false
      end

      # Check if this node is a leaf (no mergeable children).
      # @return [Boolean]
      def leaf?
        !container?
      end

      # Get children wrapped as NodeWrappers.
      # Override in subclasses to return wrapped children.
      # @return [Array<NodeWrapperBase>]
      def children
        return [] unless @node.respond_to?(:each)

        result = []
        @node.each do |child|
          result << wrap_child(child)
        end
        result
      end

      # Get mergeable children - the semantically meaningful children for tree merging.
      # Override in subclasses to return format-specific mergeable children.
      # @return [Array<NodeWrapperBase>]
      def mergeable_children
        children
      end

      # String representation for debugging.
      # @return [String]
      def inspect
        "#<#{self.class.name} type=#{@node.type} lines=#{@start_line}..#{@end_line}>"
      end

      # Returns true to indicate this is a node wrapper.
      # Used to distinguish from NodeTyping::Wrapper.
      # @return [Boolean]
      def node_wrapper?
        true
      end

      # Get the underlying TreeHaver node.
      # Note: This is NOT the same as NodeTyping::Wrapper#unwrap which removes
      # the typing wrapper. This method provides access to the raw parser node.
      # @return [Object] The underlying TreeHaver node
      def underlying_node
        @node
      end

      protected

      # Wrap a child node. Override in subclasses to use the specific wrapper class.
      # @param child [Object] Child node to wrap
      # @return [NodeWrapperBase]
      def wrap_child(child)
        self.class.new(child, lines: @lines, source: @source)
      end

      # Compute signature for a node. Subclasses MUST implement this.
      # @param node [Object] The node to compute signature for
      # @return [Array, nil] Signature array
      # @abstract
      def compute_signature(node)
        raise NotImplementedError, "#{self.class} must implement #compute_signature"
      end

      private

      def comments_to_region(kind, comments, style: nil, **metadata)
        return if comments.empty?

        Comment::TrackedHashAdapter.region(
          kind: kind,
          comments: comments,
          style: style || :hash_comment,
          metadata: {
            source: :node_wrapper_base
          }.merge(metadata)
        )
      end

      # Extract line information from the node.
      # @param node [Object] The node to extract line info from
      def extract_line_info(node)
        if node.respond_to?(:start_point)
          point = node.start_point
          @start_line = extract_row(point) + 1
        end

        return unless node.respond_to?(:end_point)

        point = node.end_point
        @end_line = extract_row(point) + 1
      end

      # Extract row from a point, handling different point implementations.
      # @param point [Object] The point object
      # @return [Integer]
      def extract_row(point)
        if point.respond_to?(:row)
          point.row
        elsif point.is_a?(Hash)
          point[:row]
        else
          0
        end
      end
    end
  end
end
