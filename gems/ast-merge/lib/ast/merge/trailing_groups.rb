# frozen_string_literal: true

module Ast
  module Merge
    # Shared infrastructure for position-aware template-only node interleaving.
    #
    # When merging a template file into a destination file, nodes that exist
    # only in the template must be inserted at positions that respect their
    # relative ordering among matched (shared) nodes in the template.
    #
    # Two named patterns are provided:
    #
    # ## Pattern A — DestIterate
    #
    # Used by gems that iterate destination nodes and match against template
    # (prism-merge, psych-merge, json-merge, jsonc-merge, toml-merge, bash-merge).
    #
    # Includes {Core} and wraps it with conventional entry points:
    # - {DestIterate#build_dest_iterate_trailing_groups}
    # - {DestIterate#emit_prefix_trailing_group}
    # - Delegates to {Core#flush_ready_trailing_groups} and
    #   {Core#emit_remaining_trailing_groups}
    #
    # ## Pattern B — AlignmentSort
    #
    # Used by gems that build an alignment array and sort template-only entries
    # to their correct positions (dotenv-merge, rbs-merge, markdown-merge,
    # markly-merge, commonmarker-merge).
    #
    # Provides {AlignmentSort#sort_alignment_with_template_position} and an
    # overridable {AlignmentSort#template_only_sort_key} hook.
    #
    # @example Including Pattern A in a conflict resolver
    #   class ConflictResolver < Ast::Merge::ConflictResolverBase
    #     include Ast::Merge::TrailingGroups::DestIterate
    #
    #     def merge_nodes(template_nodes, dest_nodes)
    #       groups, matched = build_dest_iterate_trailing_groups(
    #         template_nodes: template_nodes,
    #         matched_predicate: ->(node, _idx) { dest_sigs.include?(sig_for(node)) },
    #       )
    #       emit_prefix_trailing_group(groups) { |info| emit(info) }
    #       # ... iterate dest, flush, emit_remaining ...
    #     end
    #   end
    #
    # @example Including Pattern B in a file aligner
    #   class FileAligner
    #     include Ast::Merge::TrailingGroups::AlignmentSort
    #
    #     def align
    #       # ... build alignment array ...
    #       sort_alignment_with_template_position(alignment, dest_size)
    #     end
    #   end
    #
    # @see Core
    # @see DestIterate
    # @see AlignmentSort
    module TrailingGroups
      autoload :AlignmentSort, 'ast/merge/trailing_groups/alignment_sort'
      autoload :Core, 'ast/merge/trailing_groups/core'
      autoload :DestIterate, 'ast/merge/trailing_groups/dest_iterate'
    end
  end
end
