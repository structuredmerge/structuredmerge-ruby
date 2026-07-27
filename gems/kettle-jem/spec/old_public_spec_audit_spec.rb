# frozen_string_literal: true

RSpec.describe Kettle::Jem do
  it "records migration decisions for every old executable and task spec family" do
    audit = JSON.parse(
      File.read(File.join(__dir__, "fixtures", "old_public_spec_audit.json")),
      symbolize_names: true
    )

    expect(audit.fetch(:case_id)).to eq("kettle-jem-old-public-spec-audit")
    expect(audit.fetch(:policy)).to include("Port public behavior")
    superseded_decisions = audit.fetch(:superseded_decisions)
    expect(superseded_decisions.map { |entry| entry.fetch(:id) }).to include(
      "old-task-object-boundaries",
      "old-prompt-adapters",
      "old-parser-specific-helper-classes",
      "old-phase-class-internals",
      "old-template-helper-micro-apis"
    )
    expect(superseded_decisions).to all(include(:source_paths, :decision, :rationale, :active_contract))
    expect(superseded_decisions.map { |entry| entry.fetch(:decision) }).to all(eq("superseded"))

    files = audit.fetch(:files)
    expect(files.map { |entry| entry.fetch(:path) }).to contain_exactly(
      "spec/bin/setup_spec.rb",
      "spec/kettle/jem/setup_cli_spec.rb",
      "spec/kettle/jem/tasks/install_task_spec.rb",
      "spec/kettle/jem/tasks/prepare_task_spec.rb",
      "spec/kettle/jem/tasks/self_test_task_spec.rb",
      "spec/kettle/jem/tasks/template_task_include_spec.rb",
      "spec/kettle/jem/tasks/template_task_spec.rb",
      "spec/kettle/jem/version_gem_bootstrap_spec.rb",
      "spec/kettle/jem/rakelib/prepare_spec.rb",
      "spec/kettle/jem/rakelib/selftest_spec.rb",
      "spec/kettle/jem/rakelib/tasks_spec.rb",
      "spec/kettle/jem/self_test/manifest_spec.rb",
      "spec/kettle/jem/self_test/reporter_spec.rb"
    )
    expect(files).to all(include(:status, :active_specs))
    expect(files.map { |entry| entry.fetch(:status) }).to all(satisfy { |status| %w[ported partial superseded].include?(status) })
    partial_files = files.select { |entry| entry.fetch(:status) == "partial" }
    expect(partial_files).not_to be_empty
    expect(partial_files).to all(include(:remaining_behaviors))
    expect(partial_files.flat_map { |entry| entry.fetch(:remaining_behaviors) }).not_to be_empty

    template_task = files.find { |entry| entry.fetch(:path) == "spec/kettle/jem/tasks/template_task_spec.rb" }
    expect(template_task.fetch(:status)).to eq("ported")
    expect(template_task.fetch(:ported_behaviors)).to include(
      "legacy Markdown README H1, nested subsection, and fenced-code preservation",
      "appraisal matrix pruning parity against old generated workflow set",
      "RubyGems minimum-Ruby shunted.gemfile generation",
      "duplicate drift checks during template/install runs"
    )
    expect(template_task.fetch(:remaining_behaviors)).to be_empty
  end
end
