# frozen_string_literal: true

require_relative 'dependency_tags_helpers'

# Ast::Merge RSpec Dependency Tags - RSpec Configuration
#
# This file configures RSpec with dependency-based exclusion filters.
# It should be loaded AFTER gems have been registered with MergeGemRegistry.
#
# @example Loading in spec_helper.rb (for merge gem test suites)
#   require "ast/merge/rspec"  # Loads this file automatically
#
# @example For ast-merge test suite (split loading)
#   # In spec_helper.rb BEFORE requiring ast-merge:
#   require "ast/merge/rspec/setup"
#
#   Ast::Merge::RSpec::MergeGemRegistry.register_known_gem(
#     :markly_merge,
#     require_path: "markly/merge",
#     merger_class: "Markly::Merge::SmartMerger",
#     test_source: "# Test\n\nParagraph",
#     category: :markdown,
#   )
#   Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(:markly_merge)
#
#   # Then AFTER requiring ast-merge, load config:
#   require "ast/merge/rspec/dependency_tags_config"

# Configure RSpec with dependency-based exclusion filters
RSpec.configure do |config|
  deps = Ast::Merge::RSpec::DependencyTags
  registry = Ast::Merge::RSpec::MergeGemRegistry

  # CRITICAL: Exclusion filters MUST be set during RSpec.configure, not in before(:suite)
  # because RSpec filters tests before before(:suite) runs!

  # Force availability checking for all registered gems
  # This loads the gems NOW during configuration, which is after SimpleCov has instrumented
  # the code (since this file is required AFTER ast-merge loads in spec_helper.rb)
  registry.force_check_availability!

  # Provider loading during availability checks can register additional
  # TreeHaver backend and grammar tags. Reapply the shared filters after that
  # discovery so late-registered unavailable backends remain excluded.
  TreeHaver::RSpec::DependencyTags.configure_filters(config)

  # Now configure exclusion filters based on actual availability
  registry.registered_gems.each do |tag|
    if registry.available?(tag)
      # Gem is available - exclude tests tagged with :not_tag
      negated_tag = :"not_#{tag}"
      config.filter_run_excluding(negated_tag => true)
    else
      # Gem is NOT available - exclude tests tagged with :tag
      config.filter_run_excluding(tag => true)
    end
  end

  # Configure composite tags (these also trigger gem loading, so must be here)
  if deps.any_markdown_merge_available?
    config.filter_run_excluding(not_any_markdown_merge: true)
  else
    config.filter_run_excluding(any_markdown_merge: true)
  end

  # Print dependency summary if AST_MERGE_DEBUG is set
  config.before(:suite) do
    unless ENV.fetch('AST_MERGE_DEBUG', 'false').casecmp?('false')
      puts "\n=== Ast::Merge Test Dependencies ==="
      deps.summary.each do |dep, available|
        status = available ? '✓ available' : '✗ not available'
        puts "  #{dep}: #{status}"
      end
      puts "=====================================\n"
    end
  end

  # ============================================================
  # Dynamic Merge Gem Tags - Initial Setup
  # ============================================================
  # Note: We don't set exclusions here because that would require checking
  # availability (loading gems) before SimpleCov. The actual exclusions are
  # set in the before(:suite) hook above after force_check_availability! runs.
  # This includes composite tags like :any_markdown_merge.
end
