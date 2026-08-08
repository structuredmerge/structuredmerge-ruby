# frozen_string_literal: true

require_relative "bootstrap/tree_haver_backends"
require_relative "bootstrap/merge_gems"
require_relative "support/fixture_repository"

warn StructuredMerge::FixtureRepository.report

# Register every parser-backed merge gem before ast-merge installs RSpec's
# dependency filters. Individual gem helpers do this naturally; the aggregate
# suite must preserve the same ordering across the whole family.
%w[
  bash/merge
  citrus/toml/merge
  commonmarker/merge
  dotenv/merge
  json/merge
  kramdown/merge
  markdown/merge
  markly/merge
  parslet/toml/merge
  prism/merge
  psych/merge
  rbs/merge
  ruby/merge
  toml/merge
  yaml/merge
].each { |require_path| require require_path }

require_relative "../gems/ast-merge/spec/spec_helper"
require_relative "../gems/ast-merge-git/spec/spec_helper"
require_relative "../gems/ast-crispr/spec/spec_helper"
require_relative "../gems/ast-crispr-ruby-prism/spec/spec_helper"
require_relative "../gems/ast-crispr-markdown-markly/spec/spec_helper"
require_relative "../gems/ast-template/spec/spec_helper"
require_relative "../gems/kettle-jem/spec/spec_helper"
require_relative "../gems/tree_haver/spec/spec_helper"
require_relative "../gems/plain-merge/spec/spec_helper"
require_relative "../gems/bash-merge/spec/spec_helper"
require_relative "../gems/dotenv-merge/spec/spec_helper"
require_relative "../gems/rbs-merge/spec/spec_helper"
require_relative "../gems/binary-merge/spec/spec_helper"
require_relative "../gems/zip-merge/spec/spec_helper"
require_relative "../gems/html-merge/spec/spec_helper"
require_relative "../gems/json-merge/spec/spec_helper"
require_relative "../gems/toml-merge/spec/spec_helper"
require_relative "../gems/citrus-toml-merge/spec/spec_helper"
require_relative "../gems/parslet-toml-merge/spec/spec_helper"
require_relative "../gems/yaml-merge/spec/spec_helper"
require_relative "../gems/psych-merge/spec/spec_helper"
require_relative "../gems/markdown-merge/spec/spec_helper"
require_relative "../gems/kramdown-merge/spec/spec_helper"
require_relative "../gems/commonmarker-merge/spec/spec_helper"
require_relative "../gems/markly-merge/spec/spec_helper"
require_relative "../gems/ruby-merge/spec/spec_helper"
require_relative "../gems/prism-merge/spec/spec_helper"
require_relative "../gems/typescript-merge/spec/spec_helper"
require_relative "../gems/rust-merge/spec/spec_helper"
require_relative "../gems/go-merge/spec/spec_helper"
require_relative "../gems/smorg-rb/spec/spec_helper"

# Aggregate root specs load every subgem in one process, so shared contracts
# normally loaded by an individual subgem's focused specs must be registered here.
require "ast/crispr/rspec"
require "ast/merge/rspec/shared_examples"
require_relative "../gems/ast-merge/spec/support/fictive_language_harness"
require_relative "../gems/bash-merge/spec/support/shared_examples/file_analysis_examples"
require_relative "../gems/bash-merge/spec/support/shared_examples/smart_merger_examples"

# Individual gem helpers are loaded after ast-merge's initial RSpec filter
# configuration. Reapply availability filters after all backend registrations
# so aggregate runs exclude unavailable explicit backend contexts.
RSpec.configure do |config|
  registry = Ast::Merge::RSpec::MergeGemRegistry
  registry.force_check_availability!
  TreeHaver::RSpec::DependencyTags.configure_filters(config)

  registry.registered_gems.each do |tag|
    if registry.available?(tag)
      config.filter_run_excluding("not_#{tag}": true)
    else
      config.filter_run_excluding(tag => true)
    end
  end

  if Ast::Merge::RSpec::DependencyTags.any_markdown_merge_available?
    config.filter_run_excluding(not_any_markdown_merge: true)
  else
    config.filter_run_excluding(any_markdown_merge: true)
  end
end
