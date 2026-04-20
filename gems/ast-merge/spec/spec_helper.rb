# frozen_string_literal: true

require "json"
require "pathname"
require "structured_merge/ast_merge"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) do |expectations|
    expectations.syntax = :expect
  end
end
