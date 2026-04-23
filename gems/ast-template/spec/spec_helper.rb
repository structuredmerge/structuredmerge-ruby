# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "tmpdir"
require "ast-template"
require "markdown-merge"
require "toml-merge"
require "ruby-merge"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
