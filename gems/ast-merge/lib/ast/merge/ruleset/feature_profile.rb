# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Shared value object describing a merge implementation or ruleset surface
      # using spec-aligned feature terminology.
      #
      # FeatureProfile is the bridge from ruleset capability declarations to
      # merge-facing behavior. It may reference parser capabilities and support
      # styles, but it is not itself a parser adapter or renderer.
      class FeatureProfile
        attr_reader :owner_selector,
                    :match_key,
                    :read_strategy,
                    :attachment_strategy,
                    :comment_style,
                    :render_family,
                    :comment_capability,
                    :support_style,
                    :capabilities,
                    :logical_owners,
                    :logical_owner_policies,
                    :repair_policies,
                    :surfaces,
                    :delegation_policies,
                    :metadata

        def initialize(
          owner_selector:,
          match_key:,
          read_strategy: nil,
          attachment_strategy: nil,
          comment_style: nil,
          render_family: nil,
          comment_capability: nil,
          support_style: nil,
          capabilities: {},
          logical_owners: {},
          repair_policies: [],
          surfaces: [],
          delegation_policies: [],
          metadata: {}
        )
          @owner_selector = owner_selector&.to_sym
          @match_key = match_key&.to_sym
          @read_strategy = read_strategy&.to_sym
          @attachment_strategy = attachment_strategy&.to_sym
          @comment_style = comment_style&.to_sym
          @render_family = render_family&.to_sym
          @comment_capability = comment_capability
          @support_style = support_style
          @capabilities = capabilities.dup.freeze
          @logical_owners = logical_owners.dup.freeze
          @logical_owner_policies = @logical_owners.map do |kind, action|
            LogicalOwnerPolicy.new(kind: kind, action: action)
          end.freeze
          @repair_policies = normalize_repair_policies(repair_policies)
          @surfaces = normalize_surfaces(surfaces)
          @delegation_policies = normalize_delegation_policies(delegation_policies)
          @metadata = metadata.dup.freeze
        end

        def layout_aware?
          capabilities.fetch(:layout_aware, false)
        end

        def owner_selector_metadata
          ProfileVocabulary.owner_selector_metadata(owner_selector)
        end

        def owner_selector_family
          owner_selector_metadata&.fetch(:family, nil)
        end

        def match_key_metadata
          ProfileVocabulary.match_key_metadata(match_key)
        end

        def match_key_family
          match_key_metadata&.fetch(:family, nil)
        end

        def attachment_strategy_metadata
          ProfileVocabulary.attachment_strategy_metadata(attachment_strategy)
        end

        def attachment_strategy_family
          attachment_strategy_metadata&.fetch(:family, nil)
        end

        def owner_selector_kind
          OwnerSelection.selector_kind(owner_selector, logical_owners: logical_owners)
        end

        def logical_owner?
          capabilities.fetch(:logical_owner, logical_owners.any?)
        end

        def comment_aware?
          if support_style.respond_to?(:available?)
            support_style.available?
          elsif comment_capability.respond_to?(:available?)
            comment_capability.available?
          else
            false
          end
        end

        def structural_only?
          !layout_aware? && !comment_aware? && !logical_owner?
        end

        def repair_aware?
          repair_policies.any?
        end

        def surface_aware?
          surfaces.any?
        end

        def delegated_surface_aware?
          delegation_policies.any?
        end

        def tracked_attachment?
          attachment_strategy_metadata&.fetch(:tracked_comments, false) || false
        end

        def normalized_attachment?
          attachment_strategy_metadata&.fetch(:normalized, false) || false
        end

        def augmenter_preferred_attachment?
          attachment_strategy_metadata&.fetch(:augmenter_preferred, false) || false
        end

        def to_h
          {
            owner_selector: owner_selector,
            match_key: match_key,
            read_strategy: read_strategy,
            attachment_strategy: attachment_strategy,
            comment_style: comment_style,
            render_family: render_family,
            comment_capability: comment_capability&.to_h,
            support_style: support_style&.to_h,
            capabilities: capabilities,
            logical_owners: logical_owners,
            logical_owner_policies: logical_owner_policies.map(&:to_h),
            repair_policies: repair_policies.map(&:to_h),
            surfaces: surfaces.map(&:to_h),
            delegation_policies: delegation_policies.map(&:to_h),
            metadata: metadata,
            layout_aware: layout_aware?,
            owner_selector_family: owner_selector_family,
            owner_selector_kind: owner_selector_kind,
            match_key_family: match_key_family,
            attachment_strategy_family: attachment_strategy_family,
            logical_owner: logical_owner?,
            comment_aware: comment_aware?,
            structural_only: structural_only?,
            repair_aware: repair_aware?,
            surface_aware: surface_aware?,
            delegated_surface_aware: delegated_surface_aware?,
            tracked_attachment: tracked_attachment?,
            normalized_attachment: normalized_attachment?,
            augmenter_preferred_attachment: augmenter_preferred_attachment?
          }.compact
        end

        private

        def normalize_repair_policies(values)
          Array(values).map do |value|
            value.is_a?(RepairPolicy) ? value : RepairPolicy.new(**value)
          end.freeze
        end

        def normalize_surfaces(values)
          Array(values).map do |value|
            value.is_a?(SurfaceDeclaration) ? value : SurfaceDeclaration.new(**value)
          end.freeze
        end

        def normalize_delegation_policies(values)
          Array(values).map do |value|
            value.is_a?(DelegationPolicy) ? value : DelegationPolicy.new(**value)
          end.freeze
        end
      end
    end
  end
end
