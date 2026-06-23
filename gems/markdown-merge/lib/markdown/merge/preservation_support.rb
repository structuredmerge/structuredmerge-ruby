# frozen_string_literal: true

module Markdown
  module Merge
    # Shared Markdown-local helper methods for statement classification,
    # standalone comment fragment preservation, and remove-plan-backed range filtering.
    #
    # Provides the canonical gap-line / blank-gap-line / non-blank-gap-line /
    # structural-for-preservation predicate set used by both SmartMergerBase
    # (removal mode) and PartialTemplateMerger (replace-mode insertion indexing).
    # Both classes should call these predicates rather than performing direct
    # is_a?(GapLineNode) checks.
    module PreservationSupport
      private

      def normalized_preserved_fragment_text(text)
        text.to_s.sub(/\n+\z/, '')
      end

      def standalone_comment_text?(text)
        normalized_preserved_fragment_text(text).strip.match?(CommentTracker::STANDALONE_HTML_COMMENT_REGEX)
      end

      def standalone_comment_node?(node, analysis)
        return false unless node.respond_to?(:source_position)
        return false unless analysis.respond_to?(:comment_tracker)
        return false unless analysis.respond_to?(:comment_node_at)
        return false unless analysis.comment_tracker

        pos = node.source_position
        start_line = pos&.dig(:start_line)
        end_line = pos&.dig(:end_line)
        return false unless start_line && end_line
        return false unless start_line == end_line

        !!analysis.comment_node_at(start_line)
      end

      def link_definition_node?(node)
        node.is_a?(LinkDefinitionNode) || (node.respond_to?(:merge_type) && node.merge_type == :link_definition)
      end

      def gap_line_node?(node)
        node.is_a?(GapLineNode) ||
          (node.respond_to?(:merge_type) && node.merge_type == :gap_line) ||
          (node.respond_to?(:type) && node.type == :gap_line)
      end

      def blank_gap_line_node?(node)
        return false unless gap_line_node?(node)
        return node.blank? if node.respond_to?(:blank?)

        text = if node.respond_to?(:text)
                 node.text
               elsif node.respond_to?(:content)
                 node.content
               else
                 ''
               end

        text.to_s.strip.empty?
      end

      # Returns true when the node is a gap line whose content is non-blank
      # (e.g. a consumed link-reference definition or similar inline content
      # that was mapped to a GapLineNode).
      #
      # This is the canonical replacement for `node.is_a?(GapLineNode) && !node.blank?`
      # and handles wrapped gap-line statement nodes uniformly alongside real
      # GapLineNode instances.
      #
      # @param node [Object] The node to classify
      # @return [Boolean] true when the node is a gap line with non-blank content
      def non_blank_gap_line_node?(node)
        gap_line_node?(node) && !blank_gap_line_node?(node)
      end

      def structural_preservation_statement?(statement, analysis)
        !gap_line_node?(statement) &&
          !standalone_comment_node?(statement, analysis) &&
          !link_definition_node?(statement)
      end

      def standalone_comment_region?(region)
        standalone_comment_text?(region.respond_to?(:text) ? region.text : nil)
      end

      def preserved_comment_region_key(region)
        [
          region.respond_to?(:start_line) ? region.start_line : nil,
          region.respond_to?(:end_line) ? region.end_line : nil,
          normalized_preserved_fragment_text(region.respond_to?(:text) ? region.text : nil)
        ]
      end

      def preserved_comment_node_key(node, analysis, text: nil)
        pos = node.respond_to?(:source_position) ? node.source_position : nil

        [
          pos&.dig(:start_line),
          pos&.dig(:end_line),
          normalized_preserved_fragment_text(text || source_text_for_preserved_node(node, analysis))
        ]
      end

      def region_within_removed_range?(region, remove_plan)
        return false unless region

        start_line = region.respond_to?(:start_line) ? region.start_line : nil
        end_line = region.respond_to?(:end_line) ? region.end_line : nil
        return true unless start_line && end_line

        start_line >= remove_plan.remove_start_line && end_line <= remove_plan.remove_end_line
      end

      def remove_plan_preserved_comment_regions(remove_plan)
        return [] unless remove_plan

        regions = Array(remove_plan.promoted_comment_regions)
        regions << remove_plan.trailing_boundary&.comment_attachment&.leading_region

        seen = Set.new
        regions.each_with_object([]) do |region, preserved_regions|
          next unless standalone_comment_region?(region)
          next unless region_within_removed_range?(region, remove_plan)

          region_key = preserved_comment_region_key(region)
          next if seen.include?(region_key)

          seen << region_key
          preserved_regions << region
        end
      end

      def remove_plan_preserved_comment_keys(remove_plan)
        remove_plan_preserved_comment_regions(remove_plan).each_with_object(Set.new) do |region, keys|
          keys << preserved_comment_region_key(region)
        end
      end

      def rebase_preserved_comment_keys(keys, line_offset:)
        Array(keys).each_with_object(Set.new) do |key, rebased_keys|
          start_line, end_line, text = Array(key)
          rebased_keys << [
            start_line ? start_line - line_offset : nil,
            end_line ? end_line - line_offset : nil,
            text
          ]
        end
      end

      def remove_plan_owns_comment_node?(node, analysis, remove_plan, preserved_comment_keys: nil)
        return false unless remove_plan
        return false unless standalone_comment_node?(node, analysis)

        keys = preserved_comment_keys || remove_plan_preserved_comment_keys(remove_plan)
        region = comment_region_for_node(node, analysis, kind: :orphan)
        return false unless region_within_removed_range?(region, remove_plan)

        keys.include?(preserved_comment_region_key(region))
      end

      def remove_plan_preserved_comment_keys_for_nodes(remove_plan, nodes:, analysis:)
        keys = remove_plan_preserved_comment_keys(remove_plan)

        Array(nodes).each do |node|
          next unless standalone_comment_node?(node, analysis)

          region = comment_region_for_node(node, analysis, kind: :orphan)
          next unless region_within_removed_range?(region, remove_plan)

          keys << preserved_comment_node_key(node, analysis)
        end

        keys
      end

      def remove_plan_comment_insertion_specs(remove_plan, insertion_index_by_owner:, final_insertion_index:)
        return [] unless remove_plan

        allowed_region_keys = remove_plan_preserved_comment_keys(remove_plan)
        seen_region_keys = Set.new

        Array(remove_plan.removed_attachments).each_with_object([]) do |attachment, specs|
          append_remove_plan_comment_insertion_spec(
            specs,
            region: attachment.respond_to?(:leading_region) ? attachment.leading_region : nil,
            insertion_index: insertion_index_by_owner[attachment_owner_key(attachment)],
            gap_count: blank_gap_count(attachment.respond_to?(:leading_gap) ? attachment.leading_gap : nil),
            allowed_region_keys: allowed_region_keys,
            seen_region_keys: seen_region_keys
          )
        end.tap do |specs|
          append_remove_plan_comment_insertion_spec(
            specs,
            region: remove_plan.trailing_boundary&.comment_attachment&.leading_region,
            insertion_index: final_insertion_index,
            gap_count: blank_gap_count(remove_plan.trailing_boundary&.comment_attachment&.leading_gap),
            allowed_region_keys: allowed_region_keys,
            seen_region_keys: seen_region_keys
          )
        end
      end

      def comment_region_for_node(node, analysis, kind: :orphan, full_line_only: true)
        return unless node.respond_to?(:source_position)
        return unless analysis.respond_to?(:comment_region_for_range)

        pos = node.source_position
        start_line = pos&.dig(:start_line)
        end_line = pos&.dig(:end_line)
        return unless start_line && end_line

        analysis.comment_region_for_range(start_line..end_line, kind: kind, full_line_only: full_line_only)
      end

      def preserved_fragment_for_node(
        node,
        analysis,
        template_has_standalone_comments:,
        template_link_definition_signatures:
      )
        if standalone_comment_node?(node, analysis)
          return if template_has_standalone_comments

          {
            kind: :standalone_comment,
            text: normalized_preserved_fragment_text(source_text_for_preserved_node(node, analysis))
          }
        elsif link_definition_node?(node)
          return if template_link_definition_signatures.include?(node.signature)

          {
            kind: :link_definition,
            text: normalized_preserved_fragment_text(source_text_for_preserved_node(node, analysis))
          }
        end
      end

      def preserved_fragment_separator(gap_count:, previous_kind:, current_kind:)
        return "\n\n" if gap_count.positive?
        return "\n" if previous_kind == :link_definition && current_kind == :link_definition

        "\n\n"
      end

      def blank_gap_count(gap)
        return 0 unless gap&.respond_to?(:blank_line_count)

        gap.blank_line_count
      end

      def attachment_owner_key(owner_or_attachment)
        owner = if owner_or_attachment.respond_to?(:owner)
                  owner_or_attachment.owner
                else
                  owner_or_attachment
                end

        owner&.object_id
      end

      def source_text_for_preserved_node(node, analysis)
        if respond_to?(:node_to_source, true)
          node_to_source(node, analysis)
        else
          ''
        end
      end

      def append_remove_plan_comment_insertion_spec(specs, region:, insertion_index:, gap_count:, allowed_region_keys:,
                                                    seen_region_keys:)
        return unless region && insertion_index

        region_key = preserved_comment_region_key(region)
        return unless allowed_region_keys.include?(region_key)
        return if seen_region_keys.include?(region_key)

        seen_region_keys << region_key
        specs << {
          insertion_index: insertion_index,
          fragment: {
            kind: :standalone_comment,
            text: normalized_preserved_fragment_text(region.text)
          },
          gap_count: gap_count
        }
      end
    end
  end
end
