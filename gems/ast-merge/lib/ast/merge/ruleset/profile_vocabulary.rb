# frozen_string_literal: true

module Ast
  module Merge
    module Ruleset
      # Shared vocabulary registry for recurring feature-profile terms.
      module ProfileVocabulary
        OWNER_SELECTORS = {
          shared_default: {
            family: :generic,
            description: 'Unspecified shared default owner selection'
          },
          line_bound_statements: {
            family: :line_oriented,
            description: 'Line-oriented structural statements'
          },
          assignment_lines_plus_freeze_blocks: {
            family: :line_oriented,
            description: 'Assignment lines plus synthetic freeze-block owners'
          },
          heading_sections: {
            family: :section_branch,
            description: 'Heading-owned section branches'
          },
          link_definitions: {
            family: :reference_definition,
            description: 'Reference-definition owners keyed by normalized label'
          },
          mapping_entries: {
            family: :mapping,
            description: 'Key/value mapping entries'
          },
          rbs_declarations: {
            family: :declaration,
            description: 'Declaration-oriented type-signature owners'
          },
          prism_statement_sequence: {
            family: :statement_sequence,
            description: 'Parser-native Ruby statement sequence owners'
          }
        }.freeze

        MATCH_KEYS = {
          signature: {
            family: :structural_signature,
            description: 'Structural signature tuple matching'
          },
          env_key: {
            family: :named_key,
            description: 'Environment-variable key matching'
          },
          key_name: {
            family: :named_key,
            description: 'Mapping-entry key-name matching'
          },
          normalized_reference: {
            family: :normalized_reference,
            description: 'Normalized reference label matching'
          }
        }.freeze

        ATTACHMENT_STRATEGIES = {
          layout_only: {
            family: :layout_merge,
            tracked_comments: false,
            normalized: false,
            augmenter_preferred: false,
            description: 'Use only shared layout ownership without tracked comment regions'
          },
          tracker_layout_merge: {
            family: :layout_merge,
            tracked_comments: true,
            normalized: false,
            augmenter_preferred: false,
            description: 'Merge tracked comment attachments directly with shared layout ownership'
          },
          augmenter_preferred_tracker_layout: {
            family: :layout_merge,
            tracked_comments: true,
            normalized: false,
            augmenter_preferred: true,
            description: 'Prefer augmenter-built tracked attachments before folding in shared layout ownership'
          },
          normalize_tracked_layout_merge: {
            family: :layout_merge,
            tracked_comments: true,
            normalized: true,
            augmenter_preferred: false,
            description: 'Normalize tracked attachments while folding them into shared layout ownership'
          }
        }.freeze

        class << self
          def known_owner_selector?(value)
            OWNER_SELECTORS.key?(value&.to_sym)
          end

          def known_match_key?(value)
            MATCH_KEYS.key?(value&.to_sym)
          end

          def known_attachment_strategy?(value)
            ATTACHMENT_STRATEGIES.key?(value&.to_sym)
          end

          def owner_selector_metadata(value)
            metadata_for(OWNER_SELECTORS, value)
          end

          def match_key_metadata(value)
            metadata_for(MATCH_KEYS, value)
          end

          def attachment_strategy_metadata(value)
            metadata_for(ATTACHMENT_STRATEGIES, value)
          end

          private

          def metadata_for(registry, value)
            metadata = registry[value&.to_sym]
            metadata ? metadata.dup.freeze : nil
          end
        end
      end
    end
  end
end
