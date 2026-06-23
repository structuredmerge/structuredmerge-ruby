# frozen_string_literal: true

require_relative 'merge_gem_registry'

# Ast::Merge RSpec Dependency Tags - Helper Module Only
#
# This module provides dependency detection helpers for conditional test execution
# in the ast-merge gem family. It uses MergeGemRegistry for dynamic merge gem detection.
#
# NOTE: This file contains ONLY the helper module, not the RSpec configuration.
# The RSpec configuration is in dependency_tags_config.rb and is loaded by
# ast/merge/rspec (the full entry point).

module Ast
  module Merge
    module RSpec
      # Dependency detection helpers for conditional test execution
      module DependencyTags
        class << self
          # ============================================================
          # Composite Availability Checks
          # ============================================================

          # Check if at least one markdown merge gem is available
          #
          # @return [Boolean] true if any markdown merge gem works
          def any_markdown_merge_available?
            MergeGemRegistry.gems_by_category(:markdown).any? do |tag|
              MergeGemRegistry.available?(tag)
            end
          end

          # ============================================================
          # Summary and Reset
          # ============================================================

          # Get a summary of available dependencies (for debugging)
          #
          # @return [Hash{Symbol => Boolean}] map of dependency name to availability
          def summary
            result = MergeGemRegistry.summary
            result[:any_markdown_merge] = any_markdown_merge_available?
            result
          end

          # Reset all memoized availability checks
          #
          # @return [void]
          def reset!
            MergeGemRegistry.reset_availability!
          end
        end
      end
    end
  end
end
