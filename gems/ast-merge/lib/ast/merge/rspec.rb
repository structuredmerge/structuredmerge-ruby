# frozen_string_literal: true

# Ast::Merge RSpec Support
#
# This file provides a single entry point for all RSpec helpers in the ast-merge family.
# It loads:
# - TreeHaver dependency tags (parser backend availability)
# - Ast::Merge dependency tags (merge gem availability)
# - Ast::Merge shared examples (for testing *-merge implementations)
#
# @example Loading in spec_helper.rb
#   require "ast/merge/rspec"
#
# @example Usage in specs
#   # Dependency tags for conditional execution
#   it "requires markly-merge", :markly_merge do
#     # Skipped if markly-merge not available
#   end
#
#   # Shared examples for implementation validation
#   RSpec.describe MyMerge::ConflictResolver do
#     it_behaves_like "Ast::Merge::ConflictResolverBase"
#   end
#
# @see https://github.com/structuredmerge/structuredmerge-ruby/blob/main/gems/tree_haver/lib/tree_haver/rspec/README.md
#   TreeHaver RSpec documentation for parser backend tags

# Load TreeHaver dependency tags first (provides parser backend tags like :markly, :prism_backend, etc.)
require 'tree_haver/rspec/dependency_tags'

# Load Ast::Merge dependency tags (provides merge gem tags like :markly_merge, :prism_merge, etc.)
require_relative 'rspec/dependency_tags'

# Load Ast::Merge shared examples (for testing *-merge implementations)
require_relative 'rspec/shared_examples'
