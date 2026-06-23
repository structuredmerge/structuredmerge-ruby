# frozen_string_literal: true

# Ast::Merge RSpec Dependency Tags - Combined Loader
#
# This file provides the standard entry point for RSpec dependency tags.
# It loads both the helper module and the RSpec configuration.
#
# **When to use the split loading pattern:**
# - ast-merge: MUST use split pattern (to preserve SimpleCov coverage of ast-merge itself)
# - Merge gems that register other merge gems: MUST use split pattern (to avoid catch-22)
# - Other gems: Can use simple `require "ast/merge/rspec"` (this file)
#
# @example Simple pattern (for gems that DON'T register other gems)
#   # In spec/config/tree_haver.rb:
#   require "ast-merge"
#   require "ast/merge/rspec"  # Loads everything
#
# @example Split pattern (for ast-merge or gems that register other merge gems)
#   # In spec/config/tree_haver.rb:
#   require "ast-merge"
#   require "ast/merge/rspec/setup"  # Load registry/helpers only
#   Ast::Merge::RSpec::MergeGemRegistry.register_known_gem(
#     :markly_merge,
#     require_path: "markly/merge",
#     merger_class: "Markly::Merge::SmartMerger",
#     test_source: "# Test\n\nParagraph",
#     category: :markdown,
#   )
#   Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(:markly_merge)
#   require "ast/merge/rspec/dependency_tags_config"  # Load RSpec config
#   require "ast/merge/rspec/shared_examples"
#
# @example Usage in specs
#   it "requires markly-merge", :markly_merge do
#     # This test only runs when markly-merge is available
#   end

# Load the helper module (DependencyTags methods)
require_relative 'dependency_tags_helpers'

# Load the RSpec configuration (exclusion filters)
require_relative 'dependency_tags_config'
