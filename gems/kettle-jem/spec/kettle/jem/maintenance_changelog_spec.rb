# frozen_string_literal: true

require "kettle/jem/maintenance_changelog"

RSpec.describe Kettle::Jem::MaintenanceChangelog do
  it "delegates keyed maintenance updates to kettle-changelog" do
    Dir.mktmpdir("kettle-jem-maintenance-changelog") do |root|
      stub_env("K_CHANGELOG_PATH" => nil)
      File.write(File.join(root, "CHANGELOG.md"), <<~MARKDOWN)
        # Changelog

        ## [Unreleased]

        ### Changed

        ### Fixed
      MARKDOWN

      result = described_class.upsert_unreleased_entry(
        project_root: root,
        section: "Changed",
        key: "kettle-jem-deps-floor",
        entry: "Update dependency floors:\n  - kettle-family (>= 1.2.50 -> >= 1.2.51)"
      )

      expect(result).to include(status: "updated", key: "kettle-jem-deps-floor")
      expect(File.read(File.join(root, "CHANGELOG.md"))).to include(
        "- [kc] kettle-jem-deps-floor: Update dependency floors:\n  - kettle-family (>= 1.2.50 -> >= 1.2.51)"
      )
    end
  end

  describe ".record_template_run" do
    let(:report) do
      {
        mode: "template",
        changed_files: [
          ".structuredmerge/kettle-jem.lock",
          ".github/workflows/current.yml",
          "Gemfile",
          "README.md",
          "lib/example.rb"
        ]
      }
    end

    it "records one aggregate entry for actual template changes" do
      allow(described_class).to receive(:add_unreleased_entry).and_return(status: "updated")

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: report
      )

      expect(result.fetch(:changelog)).to include(status: "updated")
      expect(result.fetch(:changed_files)).to include("CHANGELOG.md")
      expect(described_class).to have_received(:add_unreleased_entry).with(
        project_root: "/workspace/example",
        section: "Changed",
        entry: "Apply kettle-jem templates: updated 4 project files across code and tests (1), dependencies (1), documentation (1), workflows (1)."
      )
    end

    it "does not invoke kettle-changelog when only bookkeeping changed" do
      allow(described_class).to receive(:add_unreleased_entry)

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: {changed_files: ["CHANGELOG.md", ".structuredmerge/kettle-jem.lock"]}
      )

      expect(result.fetch(:changelog)).to include(status: "skipped", reason: "no_template_changes")
      expect(described_class).not_to have_received(:add_unreleased_entry)
    end

    it "does not record the first-run config bootstrap" do
      allow(described_class).to receive(:add_unreleased_entry)

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: {setup_status: "bootstrap_config_written", changed_files: [".structuredmerge/kettle-jem.yml"]}
      )

      expect(result.fetch(:changelog)).to include(status: "skipped", reason: "bootstrap_only")
      expect(described_class).not_to have_received(:add_unreleased_entry)
    end

    it "supports an explicit changelog opt-out" do
      allow(described_class).to receive(:add_unreleased_entry)

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: report,
        run_options: {skip_changelog: true}
      )

      expect(result.fetch(:changelog)).to include(status: "skipped", reason: "disabled")
      expect(described_class).not_to have_received(:add_unreleased_entry)
    end
  end
end
