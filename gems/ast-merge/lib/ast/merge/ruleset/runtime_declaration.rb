# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Merge-facing view of ruleset declarations after translation.
      class RuntimeDeclaration
        attr_reader :read_strategy,
                    :attachment_strategy,
                    :comment_style,
                    :render_family,
                    :capabilities,
                    :logical_owners,
                    :logical_owner_policies,
                    :support_style,
                    :metadata

        def initialize(
          read_strategy:,
          attachment_strategy:,
          comment_style: nil,
          render_family: nil,
          capabilities: {},
          logical_owners: {},
          support_style: nil,
          metadata: {}
        )
          @read_strategy = read_strategy&.to_sym
          @attachment_strategy = attachment_strategy&.to_sym
          @comment_style = comment_style&.to_sym
          @render_family = render_family&.to_sym
          @capabilities = capabilities.dup.freeze
          @logical_owners = logical_owners.dup.freeze
          @logical_owner_policies = @logical_owners.map do |kind, action|
            LogicalOwnerPolicy.new(kind: kind, action: action)
          end.freeze
          @support_style = support_style
          @metadata = metadata.dup.freeze
        end

        def comment_free?
          comment_style.nil? && support_style.nil?
        end

        def logical_owner?
          logical_owners.any?
        end

        def to_h
          {
            read_strategy: read_strategy,
            attachment_strategy: attachment_strategy,
            comment_style: comment_style,
            render_family: render_family,
            capabilities: capabilities,
            logical_owners: logical_owners,
            logical_owner_policies: logical_owner_policies.map(&:to_h),
            support_style: support_style&.to_h,
            metadata: metadata,
            comment_free: comment_free?,
            logical_owner: logical_owner?
          }.compact
        end
      end
    end
  end
end
