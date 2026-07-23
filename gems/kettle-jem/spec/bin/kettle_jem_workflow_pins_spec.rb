# frozen_string_literal: true

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
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  it "defaults the project root to the gem root relative to the bin script" do
    options = described_class.parse_options([])

    expect(options.fetch(:project_root)).to eq(File.expand_path("../..", __dir__))
  end

  it "updates the pin index and workflow examples by action key" do
    result = described_class.new(project_root: project_root, env: env, options: {write: true}).run

    expect(result[:updated_actions]).to eq(["actions/checkout"])
    expect(File.read(pin_index_path)).to include(new_pin)
    expect(File.read(workflow_path)).to include("uses: #{new_pin}")
    expect(Kettle::Gha::Pins).to have_received(:resolve_action_plan).with(
      cache: {},
      client: client,
      repo_ref: "actions/checkout",
      old_ref: old_sha,
      upgrade_level: "major"
    )
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
