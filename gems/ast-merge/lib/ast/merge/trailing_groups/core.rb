# frozen_string_literal: true

module Ast
  module Merge
    module TrailingGroups
      # Core primitives for position-aware template-only node interleaving.
      #
      # This module provides three stateless methods that form the backbone of
      # the trailing-groups algorithm.  They operate on plain data structures
      # (hashes, sets, arrays) and yield to caller-supplied blocks for
      # format-specific emission — no emitter API coupling.
      #
      # ## Algorithm overview
      #
      # 1. **Build** — Walk template nodes in template order.  Each node is
      #    classified as *matched* (present in destination) or *template-only*
      #    via a caller-supplied predicate.  Consecutive template-only nodes are
      #    grouped under the index of the preceding matched node (`:prefix` for
      #    nodes before the first match).
      #
      # 2. **Flush** — After each destination node is consumed during the dest
      #    iteration loop, check whether any interior trailing groups are now
      #    *ready*.  A group anchored at template index K is ready when **all**
      #    matched template indices ≤ K have been consumed.  This deferred-flush
      #    approach handles destination reordering correctly.
      #
      # 3. **Emit remaining** — After the dest loop, emit any trailing groups
      #    that were never flushed (tail groups, safety net for edge cases).
      #
      # @example Direct usage (rare — prefer DestIterate wrapper)
      #   include Ast::Merge::TrailingGroups::Core
      #
      #   groups, matched = build_trailing_groups(
      #     template_nodes: nodes,
      #     matched_predicate: ->(node, idx) { dest_sigs.include?(sig(node)) },
      #   )
      #
      # @see DestIterate  Higher-level wrapper for Pattern A gems
      # @see AlignmentSort Higher-level wrapper for Pattern B gems
      module Core
        # Build a map of trailing groups for position-aware insertion.
        #
        # Walks +template_nodes+ in order.  For each node the +matched_predicate+
        # is called with +(node, index)+.  Matched nodes become group anchors;
        # consecutive unmatched nodes accumulate in the current group.
        #
        # Each group entry is a Hash with at least +:node+ and +:index+ keys.
        # Callers may supply +entry_builder+ to add extra keys (e.g. +:item+
        # for sequence items in psych-merge).
        #
        # @param template_nodes [Array] Ordered template nodes
        # @param matched_predicate [#call] Lambda receiving +(node, index)+,
        #   returns truthy when the node is matched in the destination
        # @param entry_builder [#call, nil] Optional lambda receiving
        #   +(node, index)+ that returns the Hash to store in the buffer.
        #   Defaults to +{ node: node, index: index }+.
        # @return [Array(Hash{Symbol,Integer => Array<Hash>}, Set<Integer>)]
        #   Tuple of +[trailing_groups, matched_indices]+.
        #   +trailing_groups+ is keyed by +:prefix+ or the Integer index of the
        #   preceding matched template node.
        def build_trailing_groups(template_nodes:, matched_predicate:, entry_builder: nil)
          groups = {}
          matched_indices = ::Set.new
          current_anchor = :prefix
          current_buffer = []

          template_nodes.each_with_index do |node, idx|
            if matched_predicate.call(node, idx)
              matched_indices << idx
              groups[current_anchor] = current_buffer unless current_buffer.empty?
              current_anchor = idx
              current_buffer = []
            else
              entry = entry_builder ? entry_builder.call(node, idx) : { node: node, index: idx }
              current_buffer << entry
            end
          end

          groups[current_anchor] = current_buffer unless current_buffer.empty?
          [groups, matched_indices]
        end

        # Flush interior trailing groups whose prerequisites are met.
        #
        # An *interior* group is one whose anchor is strictly less than the
        # largest matched template index (tail groups are deferred to
        # {#emit_remaining_trailing_groups}).
        #
        # A group anchored at template index K is *ready* when every matched
        # template index in the range 0..K has been consumed.  This prevents
        # premature emission when the destination reorders matched items
        # relative to the template.
        #
        # @param trailing_groups [Hash{Symbol,Integer => Array<Hash>}]
        #   The groups built by {#build_trailing_groups}
        # @param matched_indices [Set<Integer>] All matched template indices
        # @param consumed_indices [Set<Integer>] Template indices consumed so far
        # @yield [info] Called for each entry that should be emitted
        # @yieldparam info [Hash] The entry hash (contains at least +:node+, +:index+)
        # @return [void]
        def flush_ready_trailing_groups(trailing_groups:, matched_indices:, consumed_indices:, &emit_block)
          return if matched_indices.empty?

          last_matched = matched_indices.max

          sorted_anchors(trailing_groups).each do |anchor|
            next if anchor == :prefix
            next if anchor >= last_matched # tail group — defer to remaining pass

            group = trailing_groups[anchor]
            next if group.nil? || group.all? { |info| consumed_indices.include?(info[:index]) }

            # Check if all matched template indices 0..anchor have been consumed
            ready = matched_indices
                    .select { |idx| idx <= anchor }
                    .all? { |idx| consumed_indices.include?(idx) }
            next unless ready

            group.each do |info|
              next if consumed_indices.include?(info[:index])

              emit_block.call(info)
              consumed_indices << info[:index]
            end
          end
        end

        # Emit any trailing groups not yet flushed (tail + safety net).
        #
        # This is called after the destination iteration loop completes.
        # Groups are emitted in ascending anchor order, skipping +:prefix+
        # (which is always handled before the loop).
        #
        # @param trailing_groups [Hash{Symbol,Integer => Array<Hash>}]
        # @param consumed_indices [Set<Integer>] Template indices consumed so far
        # @yield [info] Called for each entry that should be emitted
        # @yieldparam info [Hash] The entry hash
        # @return [void]
        def emit_remaining_trailing_groups(trailing_groups:, consumed_indices:, &emit_block)
          sorted_anchors(trailing_groups).each do |anchor|
            next if anchor == :prefix # already emitted before the loop

            group = trailing_groups[anchor]
            next unless group

            group.each do |info|
              next if consumed_indices.include?(info[:index])

              emit_block.call(info)
              consumed_indices << info[:index]
            end
          end
        end

        private

        # Sort trailing group keys in ascending order, with :prefix first.
        #
        # @param groups [Hash] Trailing groups hash
        # @return [Array<Symbol,Integer>] Sorted keys
        def sorted_anchors(groups)
          groups.keys.sort_by { |k| k == :prefix ? -1 : k }
        end
      end
    end
  end
end
