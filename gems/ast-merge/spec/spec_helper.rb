# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# SimpleCov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for non-coverage appraisals may not have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require 'kettle-soup-cover'
  require 'simplecov' if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
rescue LoadError => e
  # check the error message and re-raise when unexpected
  raise e unless e.message.include?('kettle')
end

# External RSpec & related config
require 'kettle/test/rspec'

# This library
require 'ast/merge'
require 'ast/merge/rspec'
require_relative 'support/testable_node'

%w[markdown-merge markly-merge commonmarker-merge toml-merge prism-merge].each do |require_path|
  require require_path
rescue LoadError
  # Dependency-tag filtering skips backend-specific examples when the adapter
  # gem is not present in a particular bundle.
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
