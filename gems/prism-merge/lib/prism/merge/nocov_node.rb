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
    class NocovNode < Ruby::Merge::NocovNodeBase
      InvalidStructureError = Ruby::Merge::NocovNodeBase::InvalidStructureError
      Location = Ruby::Merge::NocovNodeBase::Location

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

      # @return [String]
      def inspect
        "#<Prism::Merge::NocovNode lines=#{@start_line}..#{@end_line} nodes=#{@nodes.length}>"
      end

      alias to_s inspect
    end
  end
end
