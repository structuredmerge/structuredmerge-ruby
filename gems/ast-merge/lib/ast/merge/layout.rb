# frozen_string_literal: true

module Ast
  module Merge
    # Shared merge-facing layout abstractions.
    #
    # `Ast::Merge::Layout` models interstitial blank-line runs in a way that lets
    # adjacent nodes both be aware of the same gap while ensuring only one side
    # controls output at a time.
    module Layout
      autoload :Attachment, "ast/merge/layout/attachment"
      autoload :Augmenter, "ast/merge/layout/augmenter"
      autoload :Gap, "ast/merge/layout/gap"
      autoload :Policy, "ast/merge/layout/policy"

      module_function

      def owner_controls_gap?(owner, gap)
        !!(owner && gap&.controls_output_for?(owner))
      end

      def removed_owner_controlled_gaps(attachment)
        return {} unless attachment&.respond_to?(:owner)

        {
          leading: (attachment.leading_gap if owner_controls_gap?(attachment.owner, attachment.leading_gap)),
          trailing: (attachment.trailing_gap if owner_controls_gap?(attachment.owner, attachment.trailing_gap)),
        }.compact
      end

      def prune_emitted_leading_gap_for_removed_owner(result:, attachment:)
        gap = removed_owner_controlled_gaps(attachment)[:leading]
        return 0 unless gap
        return 0 unless result.respond_to?(:remove_trailing_blank_lines)

        result.remove_trailing_blank_lines(max: gap.blank_line_count)
      end
    end
  end
end
