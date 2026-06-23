# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodeMergePlanner
      Step = Struct.new(
        :kind,
        :clause_type,
        :template_region,
        :dest_region,
        :template_clause_node,
        :dest_clause_node,
        :header_source,
        :body_text,
        :trailing_suffix_text,
        :copied_region,
        :copied_analysis_side,
        keyword_init: true
      )

      attr_reader :merger, :template_node, :dest_node, :node_preference

      def initialize(merger:, template_node:, dest_node:, node_preference:)
        @merger = merger
        @template_node = template_node
        @dest_node = dest_node
        @node_preference = node_preference
      end

      def plan
        template_clause_regions = clause_regions_by_type(template_node)
        dest_clause_regions = clause_regions_by_type(dest_node)
        template_clause_nodes = merger.send(:begin_node_clause_nodes_by_type, template_node)
        dest_clause_nodes = merger.send(:begin_node_clause_nodes_by_type, dest_node)
        return [] if template_clause_regions.empty? && dest_clause_regions.empty?

        clause_types = if node_preference == :template
                         merger.send(:merge_ordered_clause_types, template_clause_regions.keys,
                                     dest_clause_regions.keys)
                       else
                         merger.send(:merge_ordered_clause_types, dest_clause_regions.keys,
                                     template_clause_regions.keys)
                       end
        clause_types = merger.send(:canonicalize_rescue_clause_order, clause_types)
        clause_types = merger.send(:canonicalize_begin_clause_kind_order, clause_types)

        clause_types.each_with_object([]) do |clause_type, steps|
          template_region = template_clause_regions[clause_type]
          dest_region = dest_clause_regions[clause_type]
          template_clause_node = template_clause_nodes[clause_type]
          dest_clause_node = dest_clause_nodes[clause_type]

          if template_region && dest_region && template_clause_node && dest_clause_node
            merged_step = build_shared_clause_step(
              clause_type: clause_type,
              template_region: template_region,
              dest_region: dest_region,
              template_clause_node: template_clause_node,
              dest_clause_node: dest_clause_node
            )
            steps << merged_step
            next
          end

          unmatched_step = build_unmatched_clause_step(
            clause_type: clause_type,
            template_region: template_region,
            dest_region: dest_region,
            template_clause_node: template_clause_node,
            dest_clause_node: dest_clause_node
          )
          steps << unmatched_step if unmatched_step
        end
      end

      private

      def clause_regions_by_type(node)
        merger.send(:begin_node_clause_regions, node).each_with_object({}) do |region, regions_by_type|
          regions_by_type[region[:type]] = region
        end
      end

      def build_shared_clause_step(clause_type:, template_region:, dest_region:, template_clause_node:,
                                   dest_clause_node:)
        merged_clause_body = merger.send(
          :merge_clause_body_recursively,
          template_clause_node,
          template_region,
          dest_clause_node,
          dest_region
        )

        if merged_clause_body
          normalized_clause = merger.send(
            :normalized_clause_body_and_header_source,
            template_clause_node,
            dest_clause_node,
            merged_clause_body[:merged_body],
            node_preference
          )
          trailing_suffix_text = if node_preference == :template
                                   merged_clause_body[:template_trailing_suffix].empty? ? merged_clause_body[:dest_trailing_suffix] : merged_clause_body[:template_trailing_suffix]
                                 else
                                   merged_clause_body[:dest_trailing_suffix].empty? ? merged_clause_body[:template_trailing_suffix] : merged_clause_body[:dest_trailing_suffix]
                                 end

          return Step.new(
            kind: :merged_shared_clause,
            clause_type: clause_type,
            template_region: template_region,
            dest_region: dest_region,
            template_clause_node: template_clause_node,
            dest_clause_node: dest_clause_node,
            header_source: normalized_clause[:header_source],
            body_text: normalized_clause[:clause_body],
            trailing_suffix_text: trailing_suffix_text
          )
        end

        preferred_clause_node = node_preference == :template ? template_clause_node : dest_clause_node
        preferred_clause_region = node_preference == :template ? template_region : dest_region
        preferred_clause_analysis = node_preference == :template ? merger.template_analysis : merger.dest_analysis
        alternate_clause_node = node_preference == :template ? dest_clause_node : template_clause_node
        alternate_clause_region = node_preference == :template ? dest_region : template_region
        alternate_clause_analysis = node_preference == :template ? merger.dest_analysis : merger.template_analysis

        preferred_components = merger.send(:clause_body_components, preferred_clause_node, preferred_clause_region,
                                           preferred_clause_analysis)
        alternate_components = merger.send(:clause_body_components, alternate_clause_node, alternate_clause_region,
                                           alternate_clause_analysis)
        if !merger.send(:body_contains_freeze_markers?,
                        preferred_components[:merge_body] + preferred_components[:trailing_suffix]) &&
           merger.send(:body_contains_freeze_markers?,
                       alternate_components[:merge_body] + alternate_components[:trailing_suffix])
          body_to_emit = alternate_components[:merge_body]
          trailing_suffix_text = alternate_components[:trailing_suffix]
        else
          preferred_prefix, preferred_remainder = merger.send(:split_leading_comment_prefix,
                                                              preferred_components[:merge_body])
          alternate_prefix, = merger.send(:split_leading_comment_prefix, alternate_components[:merge_body])
          body_to_emit = preferred_prefix.empty? && !alternate_prefix.empty? ? (alternate_prefix + preferred_remainder) : preferred_components[:merge_body]
          trailing_suffix_text = preferred_components[:trailing_suffix].empty? ? alternate_components[:trailing_suffix] : preferred_components[:trailing_suffix]
        end

        normalized_clause = merger.send(
          :normalized_clause_body_and_header_source,
          template_clause_node,
          dest_clause_node,
          body_to_emit,
          node_preference
        )

        Step.new(
          kind: :fallback_shared_clause,
          clause_type: clause_type,
          template_region: template_region,
          dest_region: dest_region,
          template_clause_node: template_clause_node,
          dest_clause_node: dest_clause_node,
          header_source: normalized_clause[:header_source],
          body_text: normalized_clause[:clause_body],
          trailing_suffix_text: trailing_suffix_text
        )
      end

      def build_unmatched_clause_step(clause_type:, template_region:, dest_region:, template_clause_node:,
                                      dest_clause_node:)
        region, region_analysis_side = if node_preference == :template
                                         if template_region
                                           [template_region, :template]
                                         else
                                           (dest_region ? [dest_region, :destination] : nil)
                                         end
                                       elsif dest_region
                                         [dest_region, :destination]
                                       else
                                         (template_region ? [template_region, :template] : nil)
                                       end
        return unless region

        if node_preference == :template && !template_region && dest_clause_node &&
           merger.send(:clause_body_fully_duplicated_in_preferred_begin?, dest_clause_node, merger.dest_analysis,
                       template_node, merger.template_analysis) && merger.send(
                         :handle_suspected_corruption,
                         kind: :duplicate_clause_body_migration,
                         message: "destination #{clause_type.to_s.tr('_',
                                                                     '-')} body is already represented elsewhere in the preferred template begin"
                       )
          return
        end
        if node_preference == :destination && !dest_region && template_clause_node &&
           merger.send(:clause_body_fully_duplicated_in_preferred_begin?, template_clause_node,
                       merger.template_analysis, dest_node, merger.dest_analysis) && merger.send(
                         :handle_suspected_corruption,
                         kind: :duplicate_clause_body_migration,
                         message: "template #{clause_type.to_s.tr('_',
                                                                  '-')} body is already represented elsewhere in the preferred destination begin"
                       )
          return
        end

        Step.new(
          kind: :copied_unmatched_clause,
          clause_type: clause_type,
          copied_region: region,
          copied_analysis_side: region_analysis_side
        )
      end
    end
  end
end
