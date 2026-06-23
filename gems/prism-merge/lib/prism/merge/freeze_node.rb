# frozen_string_literal: true

module Prism
  module Merge
    # Wrapper to represent freeze blocks as first-class nodes.
    # A freeze block is a section marked with freeze/unfreeze comment markers that
    # should be preserved from the destination during merges.
    #
    # Inherits from Ast::Merge::FreezeNodeBase for shared functionality including
    # the Location struct, InvalidStructureError, and configurable marker patterns.
    #
    # Uses the `:hash_comment` pattern type by default for Ruby source files.
    #
    # While freeze blocks are delineated by comment markers, they are conceptually
    # different from CommentNode and do not inherit from it because:
    # - FreezeNodeBase is a *structural directive* that contains code and/or comments
    # - CommentNode represents *pure documentation* with no structural significance
    # - FreezeNodeBase can contain Ruby code nodes (methods, constants, etc.)
    # - CommentNode only contains comments
    # - Their signatures need different semantics for merge matching
    #
    # Freeze blocks can contain other nodes (methods, classes, etc.) and those
    # nodes remain as separate entities within the block for analysis purposes,
    # but the entire freeze block is treated as an atomic unit during merging.
    #
    # @example Freeze block with mixed content
    #   # prism-merge:freeze
    #   # Custom documentation
    #   CUSTOM_CONFIG = { key: "secret" }
    #   def custom_method
    #     # ...
    #   end
    #   # prism-merge:unfreeze
    class FreezeNode < Ast::Merge::FreezeNodeBase
      # Inherit InvalidStructureError from base class
      InvalidStructureError = Ast::Merge::FreezeNodeBase::InvalidStructureError

      # Extended location struct with byte offsets for compatibility with
      # TopLevelMergeRunner's already_output? check, which compares byte offsets.
      # Without real offsets, line numbers (e.g. 2..4) falsely fall within
      # the byte range of real Prism nodes, causing FreezeNodes to be skipped.
      LocationWithOffsets = Struct.new(:start_line, :end_line, :start_offset, :end_offset) do
        def cover?(line)
          (start_line..end_line).cover?(line)
        end

        def leading_comments
          []
        end

        def trailing_comments
          []
        end
      end

      # Inherit Location from base class (used when no offset info available)
      Location = Ast::Merge::FreezeNodeBase::Location

      # @param start_line [Integer] Line number of freeze marker
      # @param end_line [Integer] Line number of unfreeze marker
      # @param analysis [FileAnalysis] The file analysis containing this block
      # @param nodes [Array<Prism::Node>] Nodes fully contained within the freeze block
      # @param overlapping_nodes [Array<Prism::Node>] All nodes that overlap with freeze block (for validation)
      # @param start_marker [String, nil] The freeze start marker text
      # @param end_marker [String, nil] The freeze end marker text
      # @param pattern_type [Symbol] Pattern type for marker matching (defaults to :hash_comment)
      def initialize(start_line:, end_line:, analysis:, nodes: [], overlapping_nodes: nil, start_marker: nil,
                     end_marker: nil, pattern_type: Ast::Merge::FreezeNodeBase::DEFAULT_PATTERN)
        super(
          start_line: start_line,
          end_line: end_line,
          analysis: analysis,
          nodes: nodes,
          overlapping_nodes: overlapping_nodes || nodes,
          start_marker: start_marker,
          end_marker: end_marker,
          pattern_type: pattern_type
        )

        # Validate structure
        validate_structure!
      end

      # Returns a location with real byte offsets so TopLevelMergeRunner's
      # already_output? works correctly (it compares byte ranges).
      # @return [LocationWithOffsets]
      def location
        @location ||= begin
          lines = @analysis&.lines
          if lines
            # Byte offset of first char of start_line (sum of all prior line bytes)
            so = lines.take(@start_line - 1).sum(&:bytesize)
            # Byte offset past end of end_line (sum through end_line)
            eo = lines.take(@end_line).sum(&:bytesize)
            LocationWithOffsets.new(@start_line, @end_line, so, eo)
          else
            Location.new(@start_line, @end_line)
          end
        end
      end

      # Returns a stable signature for this freeze block
      # Signature includes the normalized content to detect changes
      # @return [Array] Signature array
      def signature
        normalized = (@start_line..@end_line).map do |ln|
          @analysis.normalized_line(ln)
        end.compact.join("\n")

        [:FreezeNode, normalized]
      end

      # String representation for debugging
      # @return [String]
      def inspect
        "#<Prism::Merge::FreezeNode lines=#{@start_line}..#{@end_line} nodes=#{@nodes.length}>"
      end

      private

      # Validate that the freeze block has proper structure:
      # - All nodes must be either fully contained or fully outside
      # - No partial overlaps allowed (a node cannot start before and end inside, or vice versa)
      def validate_structure!
        unclosed = []

        # Check all overlapping nodes
        @overlapping_nodes.each do |node|
          node_start = node.location.start_line
          node_end = node.location.end_line

          # Check if node is fully contained (valid)
          fully_contained = node_start >= @start_line && node_end <= @end_line

          # Check if node completely encompasses the freeze block
          # This is valid for nodes that define a body scope where freeze blocks make sense:
          # - ClassNode, ModuleNode, SingletonClassNode (class/module definitions)
          # - CallNode with blocks (like RSpec describe/context blocks)
          # - DefNode (method definitions)
          # - LambdaNode (lambda/proc definitions)
          encompasses = node_start < @start_line && node_end > @end_line
          valid_encompass = encompasses && (
            node.is_a?(Prism::ClassNode) ||
            node.is_a?(Prism::ModuleNode) ||
            node.is_a?(Prism::SingletonClassNode) ||
            node.is_a?(Prism::DefNode) ||
            node.is_a?(Prism::LambdaNode) ||
            (node.is_a?(Prism::CallNode) && node.block) ||
            (node.is_a?(Prism::LocalVariableWriteNode) && node.value.is_a?(Prism::LambdaNode))
          )

          # Check if node partially overlaps (invalid - unclosed/incomplete structure)
          partially_overlaps = !fully_contained && !encompasses &&
                               ((node_start < @start_line && node_end >= @start_line) ||
                                (node_start <= @end_line && node_end > @end_line))

          # Invalid if: partial overlap OR if an unsupported node type encompasses the freeze block
          unclosed << node if partially_overlaps || (encompasses && !valid_encompass)
        end

        return if unclosed.empty?

        # Build error message with details about unclosed/overlapping nodes
        node_descriptions = unclosed.map do |node|
          node_start = node.location.start_line
          node_end = node.location.end_line
          overlap_type = if node_start < @start_line
                           "starts before freeze block (line #{node_start}) and ends inside (line #{node_end})"
                         else
                           "starts inside freeze block (line #{node_start}) and ends after (line #{node_end})"
                         end
          "#{node.class.name.split('::').last} at lines #{node_start}-#{node_end} (#{overlap_type})"
        end.join(', ')

        raise InvalidStructureError.new(
          "Freeze block at lines #{@start_line}-#{@end_line} contains incomplete nodes: #{node_descriptions}. " \
            'A freeze block must fully contain all nodes within it, or be placed between nodes.',
          start_line: @start_line,
          end_line: @end_line,
          unclosed_nodes: unclosed
        )
      end
    end
  end
end
