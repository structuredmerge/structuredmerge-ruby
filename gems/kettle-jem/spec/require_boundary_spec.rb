# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "kettle/jem require boundary" do
  def clean_subprocess_env
    ENV.to_h.tap do |env|
      env.keys.grep(/\ABUNDLE_/).each { |key| env[key] = nil }
      env.keys.grep(/\ABUNDLER_/).each { |key| env[key] = nil }
      %w[RUBYLIB RUBYOPT].each { |key| env[key] = nil }
      env["BUNDLE_GEMFILE"] = ENV["BUNDLE_GEMFILE"] if ENV["BUNDLE_GEMFILE"]
    end
  end

  it "does not load parser-backed runtime dependencies before RuboCop" do
    script = <<~RUBY
      require "kettle/jem"
      raise "tree_sitter_language_pack loaded" if $LOADED_FEATURES.any? { |path| path.include?("tree_sitter_language_pack") }
      raise "Parser defined" if defined?(::Parser)

      require "rubocop"
      raise "Parser was not loaded as a module" unless ::Parser.is_a?(Module)
    RUBY

    stdout, stderr, status = Open3.capture3(
      clean_subprocess_env,
      RbConfig.ruby,
      "-rbundler/setup",
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e",
      script,
      chdir: File.expand_path("..", __dir__)
    )

    expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
  end

  it "loads parser-backed runtime dependencies for direct public helpers" do
    script = <<~RUBY
      require "kettle/jem"
      content = "[![Ruby][💎ruby-3.3i]][🚎3-3-wf]\\n\\n[💎ruby-3.3i]: https://example.test/ruby-3.3.svg\\n[🚎3-3-wf]: https://github.com/example/project/actions/workflows/ruby-3.3.yml\\n"

      processed = Kettle::Jem::ReadmePostProcessor.process(content: content, min_ruby: "4.0")
      raise "incompatible badge remained" if processed.include?("💎ruby-3.3i")

      calls = Kettle::Jem.ruby_call_records(%(gem "appraisal2"\\n), :gem)
      raise "ruby_call_records did not parse" unless calls.one?
    RUBY

    stdout, stderr, status = Open3.capture3(
      clean_subprocess_env,
      RbConfig.ruby,
      "-rbundler/setup",
      "-I#{File.expand_path("../lib", __dir__)}",
      "-e",
      script,
      chdir: File.expand_path("..", __dir__)
    )

    expect(status).to be_success, "stdout:\n#{stdout}\nstderr:\n#{stderr}"
  end
end
