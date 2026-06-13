# frozen_string_literal: true

require "spec_helper"
require "psych"

load File.expand_path("../../bin/kettle-jem-workflow-pins", __dir__)

RSpec.describe KettleJemWorkflowPins do
  let(:project_root) { Dir.mktmpdir }
  let(:old_sha) { "a" * 40 }
  let(:new_sha) { "b" * 40 }
  let(:old_pin) { "actions/checkout@#{old_sha} # v1.0.0" }
  let(:new_pin) { "actions/checkout@#{new_sha} # v1.0.1" }
  let(:pin_index_path) { File.join(project_root, "lib", "kettle", "jem.rb") }
  let(:workflow_path) { File.join(project_root, "lib", "kettle", "jem", "templates", ".github", "workflows", "ci.yml.example") }

  before do
    FileUtils.mkdir_p(File.dirname(pin_index_path))
    FileUtils.mkdir_p(File.dirname(workflow_path))
    File.write(pin_index_path, %(def github_actions_step_pins\n  {"actions/checkout" => "#{old_pin}"}\nend\n))
    File.write(workflow_path, "steps:\n  - uses: #{old_pin}\n")
    allow(Kettle::Jem).to receive(:github_actions_step_pins).and_return({"actions/checkout" => old_pin})
    allow(Open3).to receive(:capture3) do |_env, *command, chdir:|
      root_arg = command.fetch(command.index("--root") + 1)
      synthetic_workflow = File.read(File.join(root_arg, "action-pin-index.yml"))

      expect(chdir).to eq(project_root)
      expect(command).not_to include("--cache-path")
      expect { Psych.parse_stream(synthetic_workflow) }.not_to raise_error
      expect(synthetic_workflow).to include("      - name: actions/checkout\n")

      [
        JSON.generate(
          "planned_changes" => [
            {
              "action" => "actions/checkout",
              "new_ref" => new_sha,
              "new_version" => "1.0.1"
            }
          ],
          "outdated_pins" => []
        ),
        "",
        instance_double(Process::Status, success?: true, exitstatus: 0)
      ]
    end
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  it "updates the pin index and workflow examples by action key" do
    result = described_class.new(project_root: project_root, options: {write: true}).run

    expect(result[:updated_actions]).to eq(["actions/checkout"])
    expect(File.read(pin_index_path)).to include(new_pin)
    expect(File.read(workflow_path)).to include("uses: #{new_pin}")
  end

  it "includes stdout diagnostics when kettle-gha-sha-pins fails without stderr" do
    allow(Open3).to receive(:capture3).and_return([
      JSON.generate("errors" => [{"error" => "yaml_parse_error"}]),
      "",
      instance_double(Process::Status, success?: false, exitstatus: 2)
    ])

    expect {
      described_class.new(project_root: project_root).run
    }.to raise_error(RuntimeError, /kettle-gha-sha-pins failed with exit 2: .*yaml_parse_error/m)
  end
end
