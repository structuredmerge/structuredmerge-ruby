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
require 'ast/merge'
require 'rbs/merge'

require 'tree_haver/rspec'
require 'ast/merge/rspec'
require_relative 'support/testable_node'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # A grammar can be available without being registered for every native
  # backend. Exclude unsupported RBS grammar/backend combinations explicitly.
  %i[mri java rust ffi].each do |backend|
    next if TreeHaver.registered_languages(:rbs).key?(backend)

    config.filter_run_excluding(rbs_grammar: true, "#{backend}_backend": true)
  end
end
