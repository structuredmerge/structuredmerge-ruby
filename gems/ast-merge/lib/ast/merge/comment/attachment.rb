# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # A passive per-node container for comment regions associated with a
      # structural AST node.
      #
      # This does not yet impose merge policy. It simply normalizes how merge
      # gems can describe leading, inline, trailing, and orphan comment regions
      # around a structural owner node.
      class Attachment
        # @return [Object, nil] structural node this attachment belongs to
        # @return [Region, nil] normalized leading comment region
        # @return [Region, nil] normalized inline comment region
        # @return [Region, nil] normalized trailing comment region
        # @return [Array<Region>] detached/orphan regions carried with this owner
        # @return [Layout::Gap, nil] leading layout gap associated with the owner
        # @return [Layout::Gap, nil] trailing layout gap associated with the owner
        # @return [Hash] producer metadata for downstream consumers
        attr_reader :owner,
                    :leading_region,
                    :inline_region,
                    :trailing_region,
                    :orphan_regions,
                    :leading_gap,
                    :trailing_gap,
                    :metadata

        # Build a passive comment attachment.
        #
        # @param owner [Object, nil] structural owner for the attachment
        # @param leading_region [Region, nil] leading comment region
        # @param inline_region [Region, nil] inline comment region
        # @param trailing_region [Region, nil] trailing comment region
        # @param orphan_regions [Array<Region>] detached regions associated with the owner
        # @param leading_gap [Layout::Gap, nil] adjacent leading blank-line gap
        # @param trailing_gap [Layout::Gap, nil] adjacent trailing blank-line gap
        # @param metadata [Hash] base metadata
        # @param options [Hash] extra metadata merged into +metadata+
        # @return [void]
        def initialize(owner: nil, leading_region: nil, inline_region: nil, trailing_region: nil, orphan_regions: [],
                       leading_gap: nil, trailing_gap: nil, metadata: {}, **options)
          @owner = owner
          @leading_region = leading_region
          @inline_region = inline_region
          @trailing_region = trailing_region
          @orphan_regions = Array(orphan_regions).freeze
          @leading_gap = leading_gap
          @trailing_gap = trailing_gap
          @metadata = metadata.merge(options).freeze
        end

        # Return all normalized comment regions carried by this attachment.
        #
        # @return [Array<Region>]
        def regions
          [leading_region, inline_region, trailing_region, *orphan_regions].compact
        end

        def empty?
          regions.empty?
        end

        # Return all distinct layout gaps referenced by this attachment.
        #
        # @return [Array<Layout::Gap>]
        def layout_gaps
          [leading_gap, trailing_gap].compact.uniq
        end

        def leading_region_layout_owned?(**options)
          !!(leading_region&.floating? &&
            leading_gap&.leading_for?(owner) &&
            leading_gap&.controls_output_for?(owner, **options))
        end

        def trailing_region_layout_owned?(**options)
          !!(trailing_region&.floating? &&
            trailing_gap&.trailing_for?(owner) &&
            trailing_gap&.controls_output_for?(owner, **options))
        end

        def layout_owned_regions(**options)
          [
            (leading_region if leading_region_layout_owned?(**options)),
            (trailing_region if trailing_region_layout_owned?(**options))
          ].compact
        end

        def leading_freeze?(freeze_token)
          leading_region.respond_to?(:freeze?) && leading_region.freeze?(freeze_token)
        end

        def leading_unfreeze?(freeze_token)
          leading_region.respond_to?(:unfreeze?) && leading_region.unfreeze?(freeze_token)
        end

        def freeze?(freeze_token)
          regions.any? { |region| region.respond_to?(:freeze?) && region.freeze?(freeze_token) }
        end

        def unfreeze?(freeze_token)
          regions.any? { |region| region.respond_to?(:unfreeze?) && region.unfreeze?(freeze_token) }
        end

        def freeze_marker?(freeze_token)
          freeze?(freeze_token) || unfreeze?(freeze_token)
        end

        # Return a concise debug representation of the attachment.
        #
        # @return [String]
        def inspect
          owner_desc = if owner&.respond_to?(:type)
                         owner.method(:type).call
                       elsif owner.nil?
                         nil
                       else
                         owner.class.name
                       end

          "#<#{self.class.name} owner=#{owner_desc.inspect} regions=#{regions.size} layout_gaps=#{layout_gaps.size}>"
        end
      end
    end
  end
end
