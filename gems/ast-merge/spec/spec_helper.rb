# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# SimpleCov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for non-coverage appraisals may not have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require 'kettle-soup-cover'
  if Kettle::Soup::Cover::DO_COV
    # Requiring simplecov loads the project-local `.simplecov`.
    require 'simplecov'
    require 'kettle/soup/cover/config'
    SimpleCov.start
  end
rescue LoadError => e
  # check the error message and re-raise when unexpected
  raise e unless e.message.include?('kettle')
end

# External RSpec & related config
require 'kettle/test/rspec'
# `kettle/test/rspec` installs harness helpers documented in spec/README.md.

# This library
require 'ast-merge'

require_relative 'support/testable_node'

# Load registry/helper support before RSpec dependency filters are configured.
# The ast-merge suite owns cross-gem fixtures, so it must predeclare the adapter
# tag universe before RSpec filters examples.
require 'tree_haver/rspec'
require 'ast/merge/rspec/setup'

merge_gem_registry = Ast::Merge::RSpec::MergeGemRegistry
merge_gem_registry.register_known_gem(
  :markly_merge,
  require_path: 'markly/merge',
  merger_class: 'Markly::Merge::SmartMerger',
  test_source: "# Test\n\nParagraph",
  category: :markdown
)
merge_gem_registry.register_known_gem(
  :commonmarker_merge,
  require_path: 'commonmarker/merge',
  merger_class: 'Commonmarker::Merge::SmartMerger',
  test_source: "# Test\n\nParagraph",
  category: :markdown
)
merge_gem_registry.register_known_gem(
  :markdown_merge,
  require_path: 'markdown/merge',
  merger_class: 'Markdown::Merge::SmartMerger',
  test_source: "# Test\n\nParagraph",
  category: :markdown,
  skip_instantiation: true
)
merge_gem_registry.register_known_gem(
  :prism_merge,
  require_path: 'prism/merge',
  merger_class: 'Prism::Merge::SmartMerger',
  test_source: 'def foo; end',
  category: :code
)
merge_gem_registry.register_known_gem(
  :bash_merge,
  require_path: 'bash/merge',
  merger_class: 'Bash::Merge::SmartMerger',
  test_source: "#!/bin/bash\necho hello",
  category: :code
)
merge_gem_registry.register_known_gem(
  :rbs_merge,
  require_path: 'rbs/merge',
  merger_class: 'Rbs::Merge::SmartMerger',
  test_source: "class Foo\nend",
  category: :code
)
merge_gem_registry.register_known_gem(
  :json_merge,
  require_path: 'json/merge',
  merger_class: 'Json::Merge::SmartMerger',
  test_source: '{"key": "value"}',
  category: :data
)
merge_gem_registry.register_known_gem(
  :toml_merge,
  require_path: 'toml/merge',
  merger_class: 'Toml::Merge::SmartMerger',
  test_source: "[section]\nkey = \"value\"",
  category: :config
)
merge_gem_registry.register_known_gem(
  :psych_merge,
  require_path: 'psych/merge',
  merger_class: 'Psych::Merge::SmartMerger',
  test_source: 'key: value',
  category: :config
)
merge_gem_registry.register_known_gem(
  :dotenv_merge,
  require_path: 'dotenv/merge',
  merger_class: 'Dotenv::Merge::SmartMerger',
  test_source: 'KEY=value',
  category: :config
)
merge_gem_registry.register_known_gems(
  :markly_merge,
  :commonmarker_merge,
  :markdown_merge,
  :prism_merge,
  :bash_merge,
  :rbs_merge,
  :json_merge,
  :toml_merge,
  :psych_merge,
  :dotenv_merge
)

require 'ast/merge/rspec/dependency_tags_config'
require 'ast/merge/rspec/shared_examples'

%w[
  markdown/merge
  markly/merge
  commonmarker/merge
  toml/merge
  prism/merge
].each do |require_path|
  require require_path
rescue LoadError
  # Adapter-specific examples are filtered by the dependency tags configured above.
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
