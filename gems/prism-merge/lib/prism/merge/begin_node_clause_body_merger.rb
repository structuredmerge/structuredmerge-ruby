# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodeClauseBodyMerger
      MergeResult = Struct.new(
        :merged_body,
        :template_trailing_suffix,
        :dest_trailing_suffix,
        keyword_init: true
      )

      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def merge(template_clause_node:, template_clause_region:, dest_clause_node:, dest_clause_region:)
        template_components = merger.send(
          :clause_body_components,
          template_clause_node,
          template_clause_region,
          merger.template_analysis
        )
        dest_components = merger.send(
          :clause_body_components,
          dest_clause_node,
          dest_clause_region,
          merger.dest_analysis
        )
        template_body = template_components[:merge_body]
        dest_body = dest_components[:merge_body]

        return unless merger.send(:clause_bodies_have_matching_statements?, template_body, dest_body)

        body_merger = merger.class.new(
          template_body,
          dest_body,
          signature_generator: merger.instance_variable_get(:@raw_signature_generator),
          preference: merger.preference,
          add_template_only_nodes: merger.add_template_only_nodes,
          remove_template_missing_nodes: merger.remove_template_missing_nodes,
          freeze_token: merger.freeze_token,
          max_recursion_depth: merger.max_recursion_depth,
          current_depth: merger.instance_variable_get(:@current_depth) + 1,
          node_typing: merger.node_typing
        )

        MergeResult.new(
          merged_body: body_merger.merge.delete_suffix("\n"),
          template_trailing_suffix: template_components[:trailing_suffix],
          dest_trailing_suffix: dest_components[:trailing_suffix]
        )
      end
    end
  end
end
