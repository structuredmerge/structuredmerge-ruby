# frozen_string_literal: true

require "kettle/jem/tasks/install_task"

RSpec.describe Kettle::Jem::Tasks::InstallTask, ".normal_lockfile_env" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  around do |example|
    Dir.mktmpdir("sibling-lock-env-", ENV.fetch("TMPDIR", nil)) do |workspace|
      @root = File.join(workspace, "owner")
      sibling = File.join(workspace, "leaf")
      FileUtils.mkdir_p([@root, sibling])
      write_tree(@root, {
        "owner.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "owner"
            spec.version = "1.2.3"
            spec.summary = "Owner"
            spec.homepage = "https://github.com/acme/owner"
            spec.add_dependency "leaf", "= 1.2.3"
          end
        RUBY
        "Gemfile" => "gemspec\n"
      })
      write_tree(sibling, {
        "leaf.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "leaf"
            spec.version = "1.2.3"
            spec.summary = "Sibling"
          end
        RUBY
      })
      example.run
    end
  end

  it "disables local core paths while normalizing release lockfiles" do
    env = described_class.send(
      :normal_lockfile_env,
      @root,
      {"STRUCTUREDMERGE_CORE_DEV" => "/workspace/structuredmerge", "STRUCTUREDMERGE_CORE_PUBLISHED" => "true"},
      repository: {mode: "standalone"}
    )

    expect(env["STRUCTUREDMERGE_CORE_DEV"]).to eq("false")
    expect(env["STRUCTUREDMERGE_CORE_PUBLISHED"]).to eq("true")
  end

  it "does not infer local development from adjacent standalone repositories in CI" do
    env = described_class.send(:normal_lockfile_env, @root, {"CI" => "true"}, repository: {mode: "standalone"})

    expect(env["ACME_DEV"]).to be_nil
    expect(env["K_JEM_TEMPLATING"]).to eq("false")
  end

  it "keeps monorepo sibling paths enabled during lock normalization in CI" do
    env = described_class.send(:normal_lockfile_env, @root, {"CI" => "true"}, repository: {mode: "monorepo_subproject"})

    expect(env["ACME_DEV"]).to eq(File.dirname(@root))
    expect(env["K_JEM_TEMPLATING"]).to eq("false")
  end
end
