# frozen_string_literal: true

module Ast
  module Merge
    module Comment
      # Passive policy object describing when normalized comment regions are good
      # candidates for `Ast::Merge::Text` sub-merging.
      #
      # This does not perform a merge. It only standardizes the eligibility rules
      # so format gems can adopt textual comment-region merging consistently.
      class RegionMergePolicy
        # Region kinds eligible for text sub-merging.
        #
        # @return [Array<Symbol>]
        TEXT_MERGEABLE_KINDS = %i[leading trailing orphan preamble postlude].freeze
        # Supported policy outcomes.
        #
        # @return [Array<Symbol>]
        STRATEGIES = %i[preserve_preferred text_submerge].freeze

        attr_reader :preferred_region, :other_region, :attachment, :freeze_token, :details

        def initialize(preferred_region:, other_region: nil, attachment: nil, freeze_token: nil, details: {}, **options)
          @preferred_region = preferred_region
          @other_region = other_region
          @attachment = attachment
          @freeze_token = freeze_token
          @details = details.merge(options).freeze
        end

        # Return the merge strategy for this region pair.
        #
        # @return [Symbol]
        def strategy
          return :preserve_preferred if freeze_sensitive?
          return :preserve_preferred unless compatible_region_pair?
          return :preserve_preferred unless text_merge_candidate?(preferred_region)
          return :preserve_preferred unless text_merge_candidate?(other_region)

          :text_submerge
        end

        def text_submerge?
          strategy == :text_submerge
        end

        def preserve_preferred?
          strategy == :preserve_preferred
        end

        def inline?
          [preferred_region, other_region].compact.any? { |region| region.respond_to?(:inline?) && region.inline? }
        end

        def freeze_sensitive?
          return false unless freeze_token

          region_marked = [preferred_region, other_region].compact.any? do |region|
            region.respond_to?(:freeze_marker?) && region.freeze_marker?(freeze_token)
          end
          attachment_marked = attachment&.respond_to?(:freeze_marker?) && attachment&.freeze_marker?(freeze_token)

          region_marked || attachment_marked
        end

        def text_merge_candidate?(region)
          return false unless region
          return false unless region.respond_to?(:kind)
          return false unless TEXT_MERGEABLE_KINDS.include?(region.kind)
          return false if region.respond_to?(:empty?) && region.empty?
          return false unless multiline?(region)

          true
        end

        # Return the policy as a normalized Hash.
        #
        # @return [Hash]
        def to_h
          {
            strategy: strategy,
            text_submerge: text_submerge?,
            preserve_preferred: preserve_preferred?,
            freeze_sensitive: freeze_sensitive?,
            inline: inline?,
            preferred_kind: preferred_region&.kind,
            other_kind: other_region&.kind,
            details: details
          }
        end

        # Return a concise debug representation of the policy.
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} strategy=#{strategy} preferred=#{preferred_region&.kind.inspect} other=#{other_region&.kind.inspect}>"
        end

        private

        def compatible_region_pair?
          return false unless preferred_region && other_region
          return false unless preferred_region.respond_to?(:kind) && other_region.respond_to?(:kind)

          preferred_region.kind == other_region.kind
        end

        def multiline?(region)
          return false unless region.respond_to?(:start_line) && region.respond_to?(:end_line)
          return false unless region.start_line && region.end_line

          region.end_line > region.start_line
        end
      end
    end
  end
end
