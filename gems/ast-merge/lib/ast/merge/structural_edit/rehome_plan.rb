# frozen_string_literal: true

module Ast
  module Merge
    module StructuralEdit
      # Passive metadata for promoting preserved comment/layout fragments from a
      # removed owner to a surviving adjacent boundary owner.
      #
      # A rehome plan does not mutate attachments in place. It captures which
      # fragments should survive a removal and how they should be re-exposed on
      # the surviving side so emitters / downstream mergers can adopt the shared
      # contract incrementally.
      class RehomePlan
        # :reek:LongParameterList
        # Build a rehome plan for preserved fragments from a removed owner.
        #
        # @param source_owner [Object, nil] owner losing the fragments
        # @param target_boundary [Boundary] surviving boundary receiving fragments
        # @param comment_regions [Array<Comment::Region>] promoted comment regions
        # @param layout_gaps [Array<Layout::Gap>] promoted layout gaps
        # @param metadata [Hash] base metadata
        # @param options [Hash] extra metadata merged into +metadata+
        def initialize(target_boundary:, source_owner: nil, comment_regions: [], layout_gaps: [], metadata: {},
                       **options)
          raise ArgumentError, 'target_boundary is required' unless target_boundary

          @state = {
            source_owner: source_owner,
            target_boundary: target_boundary,
            comment_regions: Array(comment_regions).compact.freeze,
            layout_gaps: Array(layout_gaps).compact.freeze,
            metadata: metadata.merge(options).freeze
          }.freeze
        end

        # Return the owner losing fragments during the rehome operation.
        #
        # @return [Object, nil]
        def source_owner
          @state[:source_owner]
        end

        # Return the surviving boundary receiving preserved fragments.
        #
        # @return [Boundary]
        def target_boundary
          @state[:target_boundary]
        end

        # Return promoted comment regions to attach on the target side.
        #
        # @return [Array<Comment::Region>]
        def comment_regions
          @state[:comment_regions]
        end

        # Return promoted layout gaps to attach on the target side.
        #
        # @return [Array<Layout::Gap>]
        def layout_gaps
          @state[:layout_gaps]
        end

        # Return metadata describing how the rehome plan was constructed.
        #
        # @return [Hash]
        def metadata
          @state[:metadata]
        end

        # Return the surviving owner receiving preserved fragments.
        #
        # @return [Object, nil]
        def target_owner
          target_boundary.owner
        end

        # Return the target edge receiving fragments.
        #
        # @return [Symbol]
        def edge
          target_boundary.edge
        end

        def leading?
          target_boundary.leading?
        end

        def trailing?
          target_boundary.trailing?
        end

        def empty?
          comment_regions.empty? && layout_gaps.empty?
        end

        # Materialize the promoted comment regions as a shared attachment.
        #
        # @return [Ast::Merge::Comment::Attachment]
        def comment_attachment
          primary_region, *orphan_regions = comment_regions
          options = {
            owner: target_owner,
            orphan_regions: orphan_regions,
            metadata: { source: :structural_edit_rehome_plan }.merge(metadata)
          }

          if leading?
            Ast::Merge::Comment::Attachment.new(**options, trailing_region: primary_region)
          else
            Ast::Merge::Comment::Attachment.new(**options, leading_region: primary_region)
          end
        end

        # Materialize the promoted layout gaps as a shared attachment.
        #
        # @return [Ast::Merge::Layout::Attachment]
        def layout_attachment
          primary_gap = layout_gaps.first
          options = {
            owner: target_owner,
            metadata: { source: :structural_edit_rehome_plan }.merge(metadata)
          }

          if leading?
            Ast::Merge::Layout::Attachment.new(**options, trailing_gap: primary_gap)
          else
            Ast::Merge::Layout::Attachment.new(**options, leading_gap: primary_gap)
          end
        end

        # Return a concise debug representation of the rehome plan.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} edge=#{edge.inspect} target_owner=#{target_owner&.class&.name} comment_regions=#{comment_regions.size} layout_gaps=#{layout_gaps.size}>"
        end
      end
    end
  end
end
