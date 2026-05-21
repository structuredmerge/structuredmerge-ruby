# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "tmpdir"
require "ast-template"
require "markly-merge"
require "toml-merge"
require "prism-merge"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
