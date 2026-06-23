# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Translates normalized ruleset directives into merge-facing objects.
      class RuntimeTranslator
        class << self
          def declaration(config, source: :ruleset_config, capability: :full)
            support_style = config.comment_style && SupportStyleResolver.call(
              read: config.read,
              source: source,
              capability: capability,
              style: config.comment_style
            )
            RuntimeDeclaration.new(
              read_strategy: config.read,
              attachment_strategy: config.attach,
              comment_style: config.comment_style,
              render_family: config.render,
              capabilities: config.capabilities,
              logical_owners: config.logical_owners,
              support_style: support_style,
              metadata: {
                source: source,
                path: config.path
              }.compact
            )
          end

          def feature_profile(config, source: :ruleset_config, capability: :full)
            runtime = declaration(config, source: source, capability: capability)
            FeatureProfile.new(
              owner_selector: config.owners,
              match_key: config.match,
              read_strategy: runtime.read_strategy,
              attachment_strategy: runtime.attachment_strategy,
              comment_style: runtime.comment_style,
              render_family: runtime.render_family,
              support_style: runtime.support_style,
              capabilities: runtime.capabilities.merge(
                layout_aware: true,
                logical_owner: runtime.logical_owner?
              ),
              logical_owners: runtime.logical_owners,
              repair_policies: config.repair_policies,
              surfaces: config.surfaces,
              delegation_policies: config.delegation_policies,
              metadata: runtime.metadata
            )
          end

          def support_style(config, source:, capability: :full)
            declaration(config, source: source, capability: capability).support_style
          end
        end
      end
    end
  end
end
