# frozen_string_literal: true

module Ast
  module Merge
    module TrailingGroups
      # Pattern A — Destination-iterate trailing groups.
      #
      # Convenience wrapper around {Core} for gems that iterate destination
      # nodes and match them against template nodes by signature.  This is the
      # pattern used by prism-merge, psych-merge, json-merge, jsonc-merge,
      # toml-merge, and bash-merge.
      #
      # ## Typical usage
      #
      #   include Ast::Merge::TrailingGroups::DestIterate
      #
      #   # 1. Build groups
      #   groups, matched = build_dest_iterate_trailing_groups(
      #     template_nodes: t_nodes,
      #     dest_sigs: dest_sig_set,
      #     signature_for: ->(node) { analysis.generate_signature(node) },
      #   )
      #
      #   # 2. Emit prefix
      #   emit_prefix_trailing_group(groups, consumed) { |info| emit(info[:node]) }
      #
      #   # 3. Inside dest loop, after each match:
      #   flush_ready_trailing_groups(
      #     trailing_groups: groups,
      #     matched_indices: matched,
      #     consumed_indices: consumed,
      #   ) { |info| emit(info[:node]) }
      #
      #   # 4. After dest loop:
      #   emit_remaining_trailing_groups(
      #     trailing_groups: groups,
      #     consumed_indices: consumed,
      #   ) { |info| emit(info[:node]) }
      #
      # ## Hooks
      #
      # Override {#trailing_group_node_matched?} to add format-specific match
      # criteria (e.g. freeze-node detection, refined-match IDs).
      #
      # Override the +entry_builder:+ parameter on {#build_dest_iterate_trailing_groups}
      # to add extra keys to each entry (e.g. +:item+ for psych-merge sequences).
      #
      # @see Core         The underlying primitives
      # @see AlignmentSort Alternative pattern for alignment-based gems
      module DestIterate
        include Core

        # Build trailing groups using destination signatures for match detection.
        #
        # This is the standard Pattern A builder.  A template node is considered
        # "matched" when any of the following is true:
        #
        # 1. Its signature exists in +dest_sigs+
        # 2. Its +object_id+ is in +refined_template_ids+
        # 3. {#trailing_group_node_matched?} returns true (override hook)
        #
        # @param template_nodes [Array] Ordered template nodes
        # @param dest_sigs [Set] Set of destination node signatures
        # @param signature_for [#call] Lambda receiving +(node)+ returning signature
        # @param refined_template_ids [Set] Object IDs of refined-match template nodes
        # @param entry_builder [#call, nil] Custom entry builder (see {Core#build_trailing_groups})
        # @param add_template_only_nodes [Boolean] Gate — returns empty results when false
        # @return [Array(Hash, Set)] Tuple of +[trailing_groups, matched_indices]+
        def build_dest_iterate_trailing_groups(
          template_nodes:,
          dest_sigs:,
          signature_for:,
          refined_template_ids: ::Set.new,
          entry_builder: nil,
          add_template_only_nodes: true
        )
          return [{}, ::Set.new] unless add_template_only_nodes

          predicate = lambda { |node, _idx|
            sig = signature_for.call(node)
            (sig && dest_sigs.include?(sig)) ||
              refined_template_ids.include?(node.object_id) ||
              trailing_group_node_matched?(node, sig)
          }

          build_trailing_groups(
            template_nodes: template_nodes,
            matched_predicate: predicate,
            entry_builder: entry_builder
          )
        end

        # Emit the +:prefix+ trailing group (template-only nodes before the
        # first matched template node).
        #
        # @param trailing_groups [Hash] Groups built by {#build_dest_iterate_trailing_groups}
        # @param consumed_indices [Set<Integer>] Indices consumed so far
        # @yield [info] Called for each prefix entry
        # @yieldparam info [Hash] Entry hash with at least +:node+ and +:index+
        # @return [void]
        def emit_prefix_trailing_group(trailing_groups, consumed_indices, &emit_block)
          group = trailing_groups[:prefix]
          return unless group

          group.each do |info|
            next if consumed_indices.include?(info[:index])

            emit_block.call(info)
            consumed_indices << info[:index]
          end
        end

        # Hook: additional match criteria for a template node.
        #
        # Override in including classes to recognize format-specific "always
        # matched" nodes (e.g. freeze nodes in psych-merge, bash-merge).
        #
        # The default implementation returns +false+.
        #
        # @param _node [Object] Template node
        # @param _signature [Object, nil] The node's computed signature
        # @return [Boolean] true if the node should be treated as matched
        def trailing_group_node_matched?(_node, _signature)
          false
        end
      end
    end
  end
end
