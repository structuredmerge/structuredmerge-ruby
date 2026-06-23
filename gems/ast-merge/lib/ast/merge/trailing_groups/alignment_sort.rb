# frozen_string_literal: true

module Ast
  module Merge
    module TrailingGroups
      # Pattern B — Alignment-based template-only positioning.
      #
      # Convenience helpers for gems that build an alignment array and sort
      # template-only entries to their correct positions.  This is the pattern
      # used by dotenv-merge, rbs-merge, markdown-merge, markly-merge, and
      # commonmarker-merge.
      #
      # ## Typical usage
      #
      #   include Ast::Merge::TrailingGroups::AlignmentSort
      #
      #   def sort_alignment(alignment, dest_size)
      #     sort_alignment_with_template_position(alignment, dest_size)
      #   end
      #
      # ## Hooks
      #
      # Override {#template_only_sort_key} to customize the sort key for
      # template-only entries.  The default appends them after all
      # destination-backed entries, ordered by +template_index+.
      #
      # @see Core         The underlying primitives (not directly used here)
      # @see DestIterate  Alternative pattern for dest-iterate gems
      module AlignmentSort
        # Sort an alignment array so that:
        # - Matched and dest-only entries preserve destination order
        # - Template-only entries appear after all destination-backed entries,
        #   in template order
        #
        # @param alignment [Array<Hash>] Alignment entries with +:type+,
        #   +:dest_index+, +:template_index+ keys
        # @param dest_size [Integer] Total number of destination statements
        #   (used as offset for template-only positioning)
        # @return [Array<Hash>] Sorted alignment (mutates in place via +sort_by!+)
        def sort_alignment_with_template_position(alignment, dest_size)
          alignment.sort_by! do |entry|
            case entry[:type]
            when :match
              match_sort_key(entry)
            when :dest_only
              dest_only_sort_key(entry)
            when :template_only
              template_only_sort_key(entry, dest_size)
            else
              # simplecov:disable defensive
              [999, 0, 0, 0]
              # simplecov:enable
            end
          end
        end

        # Sort key for matched entries.
        #
        # Default: sort by destination index.
        # Override for gems that need a more complex sort (e.g. rbs-merge's
        # 4-tuple key).
        #
        # @param entry [Hash] Alignment entry
        # @return [Array] Comparable sort key
        def match_sort_key(entry)
          [0, entry[:dest_index], 0, entry[:template_index] || 0]
        end

        # Sort key for destination-only entries.
        #
        # Default: interleave with matches by destination index.
        # Override for gems with special dest-only handling (e.g. freeze blocks
        # in rbs-merge).
        #
        # @param entry [Hash] Alignment entry
        # @return [Array] Comparable sort key
        def dest_only_sort_key(entry)
          [0, entry[:dest_index], 1, 0]
        end

        # Sort key for template-only entries.
        #
        # Default: append after all destination-backed entries, ordered by
        # template index.  Override for gems that need position-aware
        # interleaving (future enhancement).
        #
        # @param entry [Hash] Alignment entry
        # @param dest_size [Integer] Number of destination statements
        # @return [Array] Comparable sort key
        def template_only_sort_key(entry, _dest_size)
          [2, entry[:template_index], 0, 0]
        end
      end
    end
  end
end
