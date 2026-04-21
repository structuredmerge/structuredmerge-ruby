# frozen_string_literal: true

require "json"
require "pathname"
require "parslet-toml-merge"
require "ast/merge"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
