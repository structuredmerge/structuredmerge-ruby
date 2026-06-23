# frozen_string_literal: true

module Prism
  module Merge
    # Synthetic AST node representing a nocov block directive.
    #
    # A nocov block is a pair of `# :nocov:` comment markers that bracket content
    # to be excluded from SimpleCov coverage reporting.
    #
    # NocovNode implements Ast::Merge::BlockDirective and behaves like FreezeNode
    # but with kind: :nocov and merge_policy: nil (follows file preference — nocov
    # blocks ARE user-customizable).
    #
    # @example Nocov block
    #   # :nocov:
    #   def unreachable_defensive_branch
    #     raise "should never happen"
    #   end
    #   # :nocov:
    class NocovNode
      include Ast::Merge::BlockDirective

      # Error raised when nocov block has invalid structure
      InvalidStructureError = Class.new(StandardError)

      # Simple location struct for compatibility with AST nodes
      Location = Struct.new(:start_line, :end_line) do
        def cover?(line)
          (start_line..end_line).cover?(line)
        end
      end

      # Location struct with byte offsets for correct range comparison with Prism nodes.
      # start_offset / end_offset are used by TopLevelMergeRunner#node_offset_range and
      # must be byte offsets (not line numbers) to avoid false "already output" matches
      # against FreezeNode ranges that also use byte offsets.
      #
      # Also exposes leading_comments delegated from the owning NocovNode so that
      # filtered_leading_comments_for / emit_dest_gap_lines can find comments that
      # appear in the file before the opening # :nocov: marker.
      LocationWithOffsets = Struct.new(:start_line, :end_line, :start_offset, :end_offset, :owner) do
        def cover?(line)
          (start_line..end_line).cover?(line)
        end

        def leading_comments
          owner.leading_comments
        end
      end

      attr_reader :start_line, :end_line, :nodes, :analysis, :start_marker, :close_marker

      # @param start_line [Integer] Line number of opening # :nocov: marker (1-based)
      # @param end_line [Integer] Line number of closing # :nocov: marker (1-based)
      # @param analysis [FileAnalysis] The owning file analysis
      # @param nodes [Array] Content nodes between the markers
      # @param start_marker [String, nil] The open marker text
      # @param close_marker [String, nil] The close marker text
      def initialize(start_line:, end_line:, analysis:, nodes: [], start_marker: nil, close_marker: nil)
        @start_line = start_line
        @end_line = end_line
        @analysis = analysis
        @nodes = nodes
        @start_marker = start_marker
        @close_marker = close_marker
      end

      # @return [Symbol]
      def kind = :nocov

      # Content nodes between the open and close markers.
      # @return [Array]
      def children = @nodes

      # Nocov follows file preference — no policy override.
      # @return [nil]
      def merge_policy = nil

      # Leading Prism comments from the first inner node that appear BEFORE this
      # NocovNode's opening marker line.  These are comments that Prism attached
      # to the inner node via attach_comments! and represent content logically
      # preceding the # :nocov: block.  Exposing them here lets
      # filtered_leading_comments_for / emit_matched_template_node emit those
      # comment lines correctly when the NocovNode is the dest_node in a merge.
      #
      # @return [Array<Prism::Comment>]
      def leading_comments
        @leading_comments ||= begin
          first = @nodes&.first
          if first&.respond_to?(:location) && first.location.respond_to?(:leading_comments)
            first.location.leading_comments.select { |c| c.location.start_line < @start_line }
          else
            []
          end
        end
      end

      # Returns a location-like object for AST node compatibility.
      # Uses byte offsets when analysis.lines is available so that
      # TopLevelMergeRunner#node_offset_range produces comparable values
      # with FreezeNode (which also uses byte offsets).
      # Delegates leading_comments to self so merge emission can find
      # pre-directive comments attached by Prism's attach_comments!.
      # @return [LocationWithOffsets, Location]
      def location
        @location ||= begin
          lines = @analysis&.lines
          if lines
            # Byte offset of first char of start_line (sum of all prior line bytes)
            so = lines.take(@start_line - 1).sum(&:bytesize)
            # Byte offset past end of end_line (sum through end_line)
            eo = lines.take(@end_line).sum(&:bytesize)
            LocationWithOffsets.new(@start_line, @end_line, so, eo, self)
          else
            Location.new(@start_line, @end_line)
          end
        end
      end

      # Content of the nocov block (all lines from start to end).
      # @return [String, nil]
      def slice
        return unless @analysis

        lines = @analysis.lines
        return unless lines

        lines[(@start_line - 1)..(@end_line - 1)]&.join
      end

      # Stable signature for merge matching.
      #
      # For single-node blocks, delegates to the inner content's signature so that a
      # NocovNode in the template matches the equivalent bare node in the destination
      # (and vice-versa).  This prevents duplication when a nocov block is introduced
      # in the template but the destination does not yet have the markers.
      #
      # For multi-node blocks, uses a `:nocov_multi` fingerprint of the inner lines
      # (markers excluded) so two multi-node nocov blocks with identical content still
      # match each other.
      #
      # @return [Array]
      def signature
        return [:NocovNode, nil] if @nodes.empty? || @analysis.nil?

        if @nodes.length == 1
          @analysis.generate_signature(@nodes.first)
        else
          inner_lines = @analysis.lines && @analysis.lines[@start_line..(@end_line - 2)]
          [:nocov_multi, inner_lines&.map(&:strip)&.join("\n")]
        end
      end

      # Node type for merge classification
      # @return [Symbol]
      def merge_type = :nocov_block

      alias type merge_type

      # @return [Boolean]
      def nocov_node? = true

      # @return [String]
      def inspect
        "#<Prism::Merge::NocovNode lines=#{@start_line}..#{@end_line} nodes=#{@nodes.length}>"
      end

      alias to_s inspect
    end
  end
end
