# frozen_string_literal: true

require "stringio"

load File.expand_path("../../bin/kettle-jem-workflow-pins", __dir__)

RSpec.describe KettleJemWorkflowPins do
  let(:project_root) { Dir.mktmpdir }
  let(:old_sha) { "a" * 40 }
  let(:new_sha) { "b" * 40 }
  let(:old_pin) { "actions/checkout@#{old_sha} # v1.0.0" }
  let(:new_pin) { "actions/checkout@#{new_sha} # v1.0.1" }
  let(:pin_index_path) { File.join(project_root, "lib", "kettle", "jem.rb") }
  let(:workflow_path) { File.join(project_root, "lib", "kettle", "jem", "templates", ".github", "workflows", "ci.yml.example") }
  let(:env) { {"GITHUB_TOKEN" => "token"} }
  let(:client) { instance_double(Kettle::Gha::Pins::GitHubClient) }
  let(:resolver_plan) do
    {
      is_outdated: true,
      current_version: "1.0.0",
      latest_outdated: {
        sha: new_sha,
        version: "1.0.1"
      },
      reason: Kettle::Gha::Pins::UPGRADE_REASON,
      updates: {
        sha: new_sha,
        version: "1.0.1",
        reason: Kettle::Gha::Pins::UPGRADE_REASON
      }
    }
  end

  before do
    FileUtils.mkdir_p(File.dirname(pin_index_path))
    FileUtils.mkdir_p(File.dirname(workflow_path))
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"actions/checkout" => "#{old_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{old_pin}\n")
    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({"actions/checkout" => old_pin})
    allow(Kettle::Gha::Pins::GitHubClient).to receive(:new).and_return(client)
    allow(Kettle::Gha::Pins).to receive(:resolve_action_plan).and_return(resolver_plan)
    allow(Kettle::Jem::MaintenanceChangelog).to receive(:upsert_unreleased_entry).and_return(status: "updated")
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  def init_git_repository(root = project_root)
    run_git("init", root)
    run_git("-C", root, "config", "user.name", "Spec User")
    run_git("-C", root, "config", "user.email", "spec@example.com")
    run_git("-C", root, "add", ".")
    run_git("-C", root, "commit", "-m", "initial")
  end

  def run_git(*args)
    _stdout, stderr, status = Open3.capture3("git", *args)
    raise stderr unless status.success?
  end

  def git_status(root = project_root)
    stdout, _stderr, status = Open3.capture3("git", "-C", root, "status", "--short")
    raise "git status failed" unless status.success?

    stdout
  end

  def git_subject(root = project_root)
    stdout, _stderr, status = Open3.capture3("git", "-C", root, "log", "-1", "--format=%s")
    raise "git log failed" unless status.success?

    stdout.chomp
  end

  it "defaults the project root to the gem root relative to the bin script" do
    options = described_class.parse_options([])

    expect(options.fetch(:project_root)).to eq(File.expand_path("../..", __dir__))
  end

  it "allows workflow pin writes to opt out of default commits" do
    options = described_class.parse_options(%w[--write --no-commit --no-changelog])

    expect(options).to include(write: true, commit: false, changelog: false)
  end

  it "enables changelog entries by default" do
    expect(described_class.parse_options([])).to include(changelog: true)
  end

  it "updates the pin index and workflow examples by action key" do
    result = described_class.new(project_root: project_root, env: env, options: {write: true}).run

    expect(result[:updated_actions]).to eq(["actions/checkout"])
    expect(File.read(pin_index_path)).to include(new_pin)
    expect(File.read(workflow_path)).to include("uses: #{new_pin}")
    expect(Kettle::Jem::MaintenanceChangelog).to have_received(:upsert_unreleased_entry).with(
      project_root: project_root,
      section: "Changed",
      key: "kettle-jem-workflow-pins",
      legacy_prefixes: ["Update pinned GitHub Actions in kettle-jem templates:"],
      entry: kind_of(Proc)
    )
    expect(Kettle::Gha::Pins).to have_received(:resolve_action_plan).with(
      cache: {},
      client: client,
      repo_ref: "actions/checkout",
      old_ref: old_sha,
      upgrade_level: "major"
    )
  end

  it "renders one nested action detail while preserving its earliest baseline" do
    tool = described_class.new(project_root: project_root, env: env)
    entry = tool.send(
      :workflow_changelog_entry,
      [{
        action: "actions/checkout",
        old_version: "1.0.1",
        old_ref: new_sha,
        new_version: "1.0.2",
        new_ref: "c" * 40
      }],
      existing_entries: [{source: "- [kc] kettle-jem-workflow-pins: Previous.\n  - actions/checkout v1.0.0 (#{old_sha}) -> v1.0.1 (#{new_sha})\n"}]
    )

    expect(entry).to eq(
      "Update pinned GitHub Actions in kettle-jem templates:\n" \
        "  - actions/checkout v1.0.0 (#{old_sha}) -> v1.0.2 (#{"c" * 40})"
    )
  end

  it "prints dry-run mode and a write hint when stale pins are found" do
    out = StringIO.new
    err = StringIO.new
    allow(described_class).to receive(:new)
      .and_return(described_class.new(project_root: project_root, env: env, options: {upgrade: "patch"}))

    status = described_class.run(%w[--upgrade patch], env: env, out: out, err: err)

    expect(status).to eq(0)
    expect(out.string).to include("workflow-pins: mode=dry-run upgrade=patch")
    expect(out.string).to include("workflow-pins: 1 update")
    expect(out.string).to include("actions/checkout v1.0.0 (#{old_sha}) -> v1.0.1 (#{new_sha})")
    expect(out.string).to include("hint: rerun with --write --upgrade patch")
    expect(err.string).to eq("")
  end

  it "commits written updates by default inside git repositories" do
    init_git_repository

    result = described_class.new(project_root: project_root, env: env, options: {write: true}).run

    expect(result[:commit]).to include(status: "committed")
    expect(result[:commit].fetch(:files)).to include(
      "lib/kettle/jem.rb",
      "lib/kettle/jem/templates/.github/workflows/ci.yml.example"
    )
    expect(git_status).to eq("")
    expect(git_subject).to eq("📌 Update kettle-jem workflow pins")
  end

  it "leaves written updates uncommitted when commit is disabled" do
    init_git_repository

    result = described_class.new(project_root: project_root, env: env, options: {write: true, commit: false}).run

    expect(result[:commit]).to be_nil
    expect(git_status).to include(" M lib/kettle/jem.rb")
    expect(git_status).to include(" M lib/kettle/jem/templates/.github/workflows/ci.yml.example")
  end

  it "refuses to commit when target files were already dirty before writing" do
    init_git_repository
    File.write(workflow_path, "#{File.read(workflow_path)}# local edit\n")

    expect {
      described_class.new(project_root: project_root, env: env, options: {write: true}).run
    }.to raise_error(RuntimeError, /target files were already dirty/)
  end

  it "commits written updates from a project nested below the git worktree root" do
    monorepo_root = Dir.mktmpdir
    nested_project_root = File.join(monorepo_root, "gems", "kettle-jem")
    nested_pin_index_path = File.join(nested_project_root, "lib", "kettle", "jem.rb")
    nested_workflow_path = File.join(nested_project_root, "lib", "kettle", "jem", "templates", ".github", "workflows", "ci.yml.example")
    begin
      FileUtils.mkdir_p(File.dirname(nested_pin_index_path))
      FileUtils.mkdir_p(File.dirname(nested_workflow_path))
      FileUtils.cp(pin_index_path, nested_pin_index_path)
      FileUtils.cp(workflow_path, nested_workflow_path)
      init_git_repository(monorepo_root)

      result = described_class.new(project_root: nested_project_root, env: env, options: {write: true}).run

      expect(result[:commit]).to include(status: "committed")
      expect(result[:commit].fetch(:files)).to include("lib/kettle/jem.rb")
      expect(git_status(monorepo_root)).to eq("")
      expect(git_subject(monorepo_root)).to eq("📌 Update kettle-jem workflow pins")
    ensure
      FileUtils.rm_rf(monorepo_root)
    end
  end

  it "preserves Ruby source delimiters around pins when writing updates" do
    File.write(pin_index_path, <<~RUBY)
      def generated_workflow
        [
          "        uses: #{old_pin}",
          ""
        ]
      end

      def github_actions_step_pins
        {
          "actions/checkout" => "#{old_pin}"
        }
      end
    RUBY

    result = described_class.new(project_root: project_root, env: env, options: {write: true}).run
    updated = File.read(pin_index_path)

    expect(result[:updated_actions]).to eq(["actions/checkout"])
    expect(updated).to include(%("        uses: #{new_pin}",))
    expect(updated).to include(%("actions/checkout" => "#{new_pin}"))
  end

  it "updates sub-action pins through the parent action repository" do
    sub_action = "github/codeql-action/init"
    old_sub_pin = "#{sub_action}@#{old_sha} # v4.36.0"
    new_sub_pin = "#{sub_action}@#{new_sha} # v4.36.2"

    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({sub_action => old_sub_pin})
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"#{sub_action}" => "#{old_sub_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{old_sub_pin}\n")
    allow(Kettle::Gha::Pins).to receive(:resolve_action_plan).and_return(
      resolver_plan.merge(
        current_version: "4.36.0",
        latest_outdated: {sha: new_sha, version: "4.36.2"},
        updates: {
          sha: new_sha,
          version: "4.36.2",
          reason: Kettle::Gha::Pins::UPGRADE_REASON
        }
      )
    )

    result = described_class.new(project_root: project_root, env: env, options: {write: true}).run

    expect(result[:updated_actions]).to eq([sub_action])
    expect(File.read(pin_index_path)).to include(new_sub_pin)
    expect(File.read(workflow_path)).to include("uses: #{new_sub_pin}")
    expect(Kettle::Gha::Pins).to have_received(:resolve_action_plan).with(
      cache: {},
      client: client,
      repo_ref: "github/codeql-action",
      old_ref: old_sha,
      upgrade_level: "major"
    )
  end

  it "updates stale version comments when the pinned SHA is already current" do
    old_comment_pin = "codecov/codecov-action@#{old_sha} # v7"
    new_comment_pin = "codecov/codecov-action@#{old_sha} # v7.0.0"
    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({"codecov/codecov-action" => old_comment_pin})
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"codecov/codecov-action" => "#{old_comment_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{old_comment_pin}\n")
    allow(Kettle::Gha::Pins).to receive(:resolve_action_plan).and_return(
      {
        is_outdated: false,
        current_version: "7.0.0",
        latest_outdated: nil,
        reason: nil,
        updates: nil
      }
    )

    result = described_class.new(project_root: project_root, env: env, options: {write: true, commit: false}).run

    expect(result[:updated_actions]).to eq(["codecov/codecov-action"])
    expect(result[:planned_changes]).to include(
      hash_including(
        "action" => "codecov/codecov-action",
        "old_version" => "7",
        "new_version" => "7.0.0",
        "reason" => "update_version_comment"
      )
    )
    expect(File.read(pin_index_path)).to include(new_comment_pin)
    expect(File.read(workflow_path)).to include("uses: #{new_comment_pin}")
  end

  it "does not downgrade equivalent version comments to less specific release tags" do
    explicit_pin = "appraisal-rb/setup-ruby-flash@#{new_sha} # v2.0"
    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({"appraisal-rb/setup-ruby-flash" => explicit_pin})
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"appraisal-rb/setup-ruby-flash" => "#{explicit_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{explicit_pin}\n")
    allow(Kettle::Gha::Pins).to receive(:resolve_action_plan).and_return(
      {
        is_outdated: false,
        current_version: "2",
        latest_outdated: nil,
        reason: nil,
        updates: nil
      }
    )

    result = described_class.new(project_root: project_root, env: env, options: {write: true, commit: false}).run

    expect(result[:updates]).to eq(0)
    expect(File.read(pin_index_path)).to include(explicit_pin)
    expect(File.read(workflow_path)).to include("uses: #{explicit_pin}")
  end

  it "refreshes the persistent action cache when writing updates" do
    described_class.new(project_root: project_root, env: env, options: {write: true, commit: false}).run

    expect(Kettle::Gha::Pins::GitHubClient).to have_received(:new).with(
      hash_including(refresh_cache: true)
    )
  end

  it "uses the persistent action cache for dry-run reports" do
    described_class.new(project_root: project_root, env: env).run

    expect(Kettle::Gha::Pins::GitHubClient).to have_received(:new).with(
      hash_including(refresh_cache: false)
    )
  end

  it "fails check mode when template sources drift from the canonical pin index" do
    stale_pin = "actions/checkout@#{old_sha} # v1.0.0"
    canonical_pin = "actions/checkout@#{new_sha} # v1.0.1"

    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({"actions/checkout" => canonical_pin})
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"actions/checkout" => "#{canonical_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{stale_pin}\n")
    allow(Kettle::Gha::Pins).to receive(:resolve_action_plan).and_return(
      {is_outdated: false, current_version: nil, latest_outdated: nil, reason: nil, updates: nil}
    )

    expect {
      described_class.new(project_root: project_root, env: env, options: {check: true}).run
    }.to raise_error(RuntimeError, /GitHub Actions pins are stale/)
  end

  it "updates template source pins that drift from the canonical pin index" do
    stale_pin = "actions/checkout@#{old_sha} # v1.0.0"
    canonical_pin = "actions/checkout@#{new_sha} # v1.0.1"

    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({"actions/checkout" => canonical_pin})
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"actions/checkout" => "#{canonical_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{stale_pin}\n")
    allow(Kettle::Gha::Pins).to receive(:resolve_action_plan).and_return(
      {is_outdated: false, current_version: nil, latest_outdated: nil, reason: nil, updates: nil}
    )

    result = described_class.new(project_root: project_root, env: env, options: {write: true}).run

    expect(result[:updated_actions]).to eq(["actions/checkout"])
    expect(File.read(pin_index_path)).to include(canonical_pin)
    expect(File.read(workflow_path)).to include("uses: #{canonical_pin}")
  end

  it "uses gh auth token as a fallback when token env vars are absent" do
    allow(Open3).to receive(:capture3).with({}, "gh", "auth", "token", chdir: project_root).and_return(
      ["gh-token\n", "", instance_double(Process::Status, success?: true)]
    )

    described_class.new(project_root: project_root, env: {}).run

    expect(Kettle::Gha::Pins::GitHubClient).to have_received(:new).with(
      hash_including(token: "gh-token", user_agent: "kettle-jem-workflow-pins")
    )
  end
end
