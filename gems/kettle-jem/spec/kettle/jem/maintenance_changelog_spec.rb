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

  it "writes to the explicit destination when the caller exports a changelog path" do
    Dir.mktmpdir("kettle-jem-maintenance-changelog-source") do |source_root|
      Dir.mktmpdir("kettle-jem-maintenance-changelog-destination") do |destination_root|
        source_path = File.join(source_root, "CHANGELOG.md")
        destination_path = File.join(destination_root, "CHANGELOG.md")
        source_content = "# Source changelog\n"
        destination_content = <<~MARKDOWN
          # Destination changelog

          ## [Unreleased]

          ### Changed

          ### Fixed
        MARKDOWN
        File.write(source_path, source_content)
        File.write(destination_path, destination_content)
        previous_path = ENV.fetch("K_CHANGELOG_PATH", nil)
        # rubocop:disable Env/Assign
        ENV["K_CHANGELOG_PATH"] = source_path
        described_class.upsert_unreleased_entry(
          project_root: destination_root,
          section: "Changed",
          key: "kettle-jem/template",
          entry: "updated 1 project file:\n  - documentation (1)"
        )
      ensure
        if previous_path.nil?
          ENV.delete("K_CHANGELOG_PATH")
        else
          ENV["K_CHANGELOG_PATH"] = previous_path
        end
        # rubocop:enable Env/Assign

        expect(File.read(source_path)).to eq(source_content)
        expect(File.read(destination_path)).to include(
          "- [kc] kettle-jem/template: updated 1 project file:\n  - documentation (1)"
        )
      end
    end
  end

  it "supports compound keys without extending kettle-changelog's keyed entry format" do
    Dir.mktmpdir("kettle-jem-maintenance-changelog-compound-key") do |root|
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
        key: "kettle-jem/template",
        entry: "updated 1 project file:\n  - documentation (1)"
      )

      expect(result).to include(status: "updated", key: "kettle-jem/template")
      expect(File.read(File.join(root, "CHANGELOG.md"))).to include(
        "- [kc] kettle-jem/template: updated 1 project file:\n  - documentation (1)"
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

    it "records one keyed aggregate entry for actual template changes" do
      Dir.mktmpdir("kettle-jem-maintenance-changelog-entry") do |root|
        options = nil
        File.write(File.join(root, "CHANGELOG.md"), "# Changelog\n")
        allow(described_class).to receive(:upsert_unreleased_entry) do |**received_options|
          options = received_options
          {status: "updated", entry: "rendered entry"}
        end

        result = described_class.record_template_run(project_root: root, report: report)

        expect(result.fetch(:changelog)).to include(status: "updated")
        expect(result.fetch(:changed_files)).to include("CHANGELOG.md")
        expect(described_class).to have_received(:upsert_unreleased_entry).with(
          project_root: root,
          section: "Changed",
          key: "kettle-jem/template",
          entry: an_instance_of(Proc)
        )
        expect(options.fetch(:entry).call([])).to eq(<<~ENTRY.chomp)
          updated 4 project files:
            - code and tests (1)
            - dependencies (1)
            - documentation (1)
            - workflows (1)
        ENTRY
      end
    end

    it "does not invoke kettle-changelog when only bookkeeping changed" do
      allow(described_class).to receive(:upsert_unreleased_entry)

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: {changed_files: ["CHANGELOG.md", ".structuredmerge/kettle-jem.lock"]}
      )

      expect(result.fetch(:changelog)).to include(status: "skipped", reason: "no_template_changes")
      expect(described_class).not_to have_received(:upsert_unreleased_entry)
    end

    it "does not record the first-run config bootstrap" do
      allow(described_class).to receive(:upsert_unreleased_entry)

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: {setup_status: "bootstrap_config_written", changed_files: [".structuredmerge/kettle-jem.yml"]}
      )

      expect(result.fetch(:changelog)).to include(status: "skipped", reason: "bootstrap_only")
      expect(described_class).not_to have_received(:upsert_unreleased_entry)
    end

    it "skips changelog recording for partial destination projects without a changelog" do
      allow(described_class).to receive(:upsert_unreleased_entry)

      Dir.mktmpdir("kettle-jem-maintenance-changelog-missing") do |root|
        result = described_class.record_template_run(
          project_root: root,
          report: report
        )

        expect(result.fetch(:changelog)).to include(status: "skipped", reason: "missing_changelog")
        expect(described_class).not_to have_received(:upsert_unreleased_entry)
      end
    end

    it "supports an explicit changelog opt-out" do
      allow(described_class).to receive(:upsert_unreleased_entry)

      result = described_class.record_template_run(
        project_root: "/workspace/example",
        report: report,
        run_options: {skip_changelog: true}
      )

      expect(result.fetch(:changelog)).to include(status: "skipped", reason: "disabled")
      expect(described_class).not_to have_received(:upsert_unreleased_entry)
    end

    it "tracks distinct files across repeated runs of one Unreleased entry" do
      Dir.mktmpdir("kettle-jem-maintenance-changelog-paths") do |root|
        File.write(File.join(root, "CHANGELOG.md"), "# Changelog\n")
        entries = []
        allow(described_class).to receive(:upsert_unreleased_entry) do |**options|
          body = options.fetch(:entry).call(entries.empty? ? [] : [{source: entries.last}])
          entries << body
          {status: "updated", entry: body}
        end

        described_class.record_template_run(
          project_root: root,
          report: {changed_files: ["Gemfile", "README.md"]}
        )
        result = described_class.record_template_run(
          project_root: root,
          report: {changed_files: ["Gemfile", "lib/example.rb"]}
        )

        expect(result.fetch(:changelog).fetch(:entry)).to include(
          "updated 3 project files:",
          "- code and tests (1)",
          "- dependencies (1)",
          "- documentation (1)"
        )
        lock = Kettle::Jem::TemplateLock.load(project_root: root)
        expect(lock.dig("template_state", "maintenance_changelog", "kettle-jem/template")).to eq(
          ["Gemfile", "README.md", "lib/example.rb"]
        )
      end
    end

    it "starts a fresh path set after the keyed Unreleased entry is removed" do
      Dir.mktmpdir("kettle-jem-maintenance-changelog-reset") do |root|
        File.write(File.join(root, "CHANGELOG.md"), "# Changelog\n")
        Kettle::Jem::TemplateLock.update_maintenance_changelog_paths(
          project_root: root,
          key: "kettle-jem/template",
          paths: ["Gemfile", "README.md"]
        )
        allow(described_class).to receive(:upsert_unreleased_entry) do |**options|
          {status: "updated", entry: options.fetch(:entry).call([])}
        end

        result = described_class.record_template_run(
          project_root: root,
          report: {changed_files: ["lib/example.rb"]}
        )

        expect(result.fetch(:changelog).fetch(:entry)).to include("updated 1 project file:")
        lock = Kettle::Jem::TemplateLock.load(project_root: root)
        expect(lock.dig("template_state", "maintenance_changelog", "kettle-jem/template")).to eq(["lib/example.rb"])
      end
    end
  end
end
