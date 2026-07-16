# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "kettle/jem require boundary" do
  it "does not load parser-backed runtime dependencies before RuboCop" do
    script = <<~RUBY
      require "kettle/jem"
      raise "tree_sitter_language_pack loaded" if $LOADED_FEATURES.any? { |path| path.include?("tree_sitter_language_pack") }
      raise "Parser defined" if defined?(::Parser)

      require "rubocop"
      raise "Parser was not loaded as a module" unless ::Parser.is_a?(Module)
    RUBY

    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e",
      script,
      chdir: File.expand_path("..", __dir__)
    )

    expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
  end
end
