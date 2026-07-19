# frozen_string_literal: true

# Load all Ast::Merge shared examples for RSpec
#
# Usage:
#   require "ast/merge/rspec/shared_examples"
#
# This will load all shared examples provided by ast-merge,
# making them available for use in any *-merge gem's test suite.
#
# Available shared examples:
# - "Ast::Merge::CommentBehaviorMatrix" - validates standardized comment/layout and merge-option behavior
# - "Ast::Merge::Comment::Attachment" - validates merge-facing comment attachments
# - "Ast::Merge::Comment::Augmenter" - validates shared comment augmenter behavior
# - "Ast::Merge::Comment::Region" - validates merge-facing comment regions
# - "Ast::Merge::ConflictResolverBase" - validates conflict resolver base implementation
# - "Ast::Merge::DebugLogger" - validates debug logging integration
# - "Ast::Merge::FileAnalyzable" - validates file analysis mixin integration
# - "Ast::Merge::Ruleset::FeatureProfile" - validates spec-aligned feature-profile exposure
# - "Ast::Merge::FreezeNodeBase" - validates freeze node base implementation
# - "Ast::Merge::Layout::Attachment" - validates merge-facing layout attachments
# - "Ast::Merge::Layout::Augmenter" - validates shared layout gap inference
# - "Ast::Merge::MergeResultBase" - validates merge result implementation
# - "Ast::Merge::MergerConfig" - validates merger configuration
# - "Ast::Merge::Recipe::PresetContract" - validates preset loading and companion-script resolution
# - "Ast::Merge::RemovalModeCompliance" - validates generic remove_template_missing_nodes behavior
# - "Ast::Merge::RetainedBlankGapCompliance" - validates retained matched owner blank-gap preservation
# - "Ast::Merge::RuntimeDebugContract" - validates runtime-aware merge_with_debug payloads
# - "Ast::Merge::UnresolvedHelperContract" - validates shared unresolved helper support
# - "Ast::Merge::UnresolvedReviewStateTransportContract" - validates persisted unresolved review replay and JSON-safe transport
# - "Ast::Merge::UnresolvedRuntimeDebugContract" - validates unresolved review state in debug payloads
# - "Ast::Merge::UnresolvedRuntimeContract" - validates reviewable unresolved runtime payloads
# - "Ast::Merge::TreeHaverBackendContract" - validates advertised backend refs have concrete TreeHaver parsers
# - "a reproducible merge" - validates merge scenarios with fixtures and idempotency
# - "a reproducible partial merge" - validates partial-merge scenarios with idempotency

require_relative 'shared_examples/comment_behavior_matrix'
require_relative 'comment_behavior_matrix_adapters'
require_relative 'shared_examples/comment_attachment'
require_relative 'shared_examples/comment_augmenter'
require_relative 'shared_examples/comment_region'
require_relative 'shared_examples/conflict_resolver_base'
require_relative 'shared_examples/debug_logger'
require_relative 'shared_examples/file_analyzable'
require_relative 'shared_examples/feature_profile'
require_relative 'shared_examples/freeze_node_base'
require_relative 'shared_examples/layout_attachment'
require_relative 'shared_examples/layout_augmenter'
require_relative 'shared_examples/merge_result_base'
require_relative 'shared_examples/merger_config'
require_relative 'shared_examples/recipe_preset_contract'
require_relative 'shared_examples/removal_mode_compliance'
require_relative 'shared_examples/retained_blank_gap_compliance'
require_relative 'shared_examples/reproducible_merge'
require_relative 'shared_examples/reproducible_partial_merge'
require_relative 'shared_examples/runtime_debug_contract'
require_relative 'shared_examples/unresolved_helper_contract'
require_relative 'shared_examples/unresolved_review_state_transport_contract'
require_relative 'shared_examples/unresolved_runtime_debug_contract'
require_relative 'shared_examples/unresolved_runtime_contract'
require_relative 'shared_examples/tree_haver_backend_contract'
