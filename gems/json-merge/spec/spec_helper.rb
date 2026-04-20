# frozen_string_literal: true

require "json"
require "pathname"
require "json/merge"
require "ast/merge"
require "tree_haver"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
