# frozen_string_literal: true

RSpec.describe Kettle::Jem::Tasks::SelfTestTask do
  def write_file(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it "validates a destination project against template output and writes reports" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest", tmp_root) do |root|
      write_file(root, "README.md", "before\n")
      allow(Kettle::Jem).to receive(:apply_project) do |project_root, **|
        File.write(File.join(project_root, "README.md"), "after\n")
        {mode: "apply"}
      end

      result = described_class.run(
        project_root: root,
        template_root: File.join(root, "template"),
        min_divergence_threshold: 100
      )

      expect(result.fetch(:mode)).to eq("selftest")
      expect(result.fetch(:comparison).fetch(:changed)).to eq(["README.md"])
      expect(result.fetch(:divergence)).to eq(100.0)
      expect(File).to exist(File.join(root, "tmp", "template_test", "report", "before.json"))
      expect(File).to exist(File.join(root, "tmp", "template_test", "report", "after.json"))
      expect(File.read(result.fetch(:report_path))).to include("## Drift Analysis")
    end
  end

  it "fails when divergence exceeds the configured threshold after writing the report" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest", tmp_root) do |root|
      write_file(root, "README.md", "before\n")
      allow(Kettle::Jem).to receive(:apply_project) do |project_root, **|
        File.write(File.join(project_root, "README.md"), "after\n")
        {mode: "apply"}
      end

      expect {
        described_class.run(project_root: root, min_divergence_threshold: 0)
      }.to raise_error(Kettle::Jem::Error, /divergence 100\.0% exceeds threshold 0\.0%/)

      expect(File).to exist(File.join(root, "tmp", "template_test", "report", "summary.md"))
    end
  end

  it "filters generated runtime artifacts from selftest comparisons" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest-artifacts", tmp_root) do |root|
      write_file(root, "README.md", "stable\n")
      allow(Kettle::Jem).to receive(:apply_project) do |project_root, **|
        write_file(project_root, "tmp/kettle-jem/templating-report-20260516-120000-000000-1234.md", "run report\n")
        write_file(project_root, "tmp/.gitignore", "*\n!.gitignore\n")
        write_file(project_root, "gemfiles/modular/shunted.gemfile", "# generated shunt\n")
        write_file(project_root, "results/test_results.html", "<html>runtime report</html>\n")
        write_file(project_root, "unexpected.txt", "real addition\n")
        {mode: "apply"}
      end

      result = described_class.run(project_root: root, min_divergence_threshold: 100)

      expect(result.fetch(:comparison).fetch(:added)).to eq(["unexpected.txt"])
    end
  end

  it "resolves explicit, environment, and config selftest thresholds" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    previous_threshold = ENV.fetch("KJ_MIN_DIVERGENCE_THRESHOLD", nil)
    Dir.mktmpdir("kettle-jem-selftest-threshold", tmp_root) do |root|
      expect(described_class.selftest_threshold("12.5", root)).to eq(12.5)

      # rubocop:disable Env/Assign
      ENV["KJ_MIN_DIVERGENCE_THRESHOLD"] = " 7.25 "
      expect(described_class.selftest_threshold(nil, root)).to eq(7.25)

      ENV.delete("KJ_MIN_DIVERGENCE_THRESHOLD")
      # rubocop:enable Env/Assign
      expect(described_class.selftest_threshold(nil, root)).to be_nil

      write_file(root, ".kettle-jem.yml", "min_divergence_threshold: \"\"\n")
      expect(described_class.selftest_threshold(nil, root)).to be_nil

      write_file(root, ".kettle-jem.yml", "min_divergence_threshold: 3.5\n")
      expect(described_class.selftest_threshold(nil, root)).to eq(3.5)

      write_file(root, ".kettle-jem.yml", "[]\n")
      expect(described_class.selftest_threshold(nil, root)).to be_nil

      write_file(root, ".kettle-jem.yml", "min_divergence_threshold: nope\n")
      expect {
        described_class.selftest_threshold(nil, root)
      }.to raise_error(Kettle::Jem::Error, "Invalid selftest min_divergence_threshold")
    end
  ensure
    # rubocop:disable Env/Assign
    if previous_threshold.nil?
      ENV.delete("KJ_MIN_DIVERGENCE_THRESHOLD")
    else
      ENV["KJ_MIN_DIVERGENCE_THRESHOLD"] = previous_threshold
    end
    # rubocop:enable Env/Assign
  end

  it "upserts template root overrides into existing and new config content" do
    existing_root = <<~YAML
      templates:
        apply: true
        root: old
    YAML
    replaced_root = <<~YAML
      templates:
        apply: true
        root: /template
    YAML
    missing_root = <<~YAML
      templates:
        apply: true
    YAML
    inserted_root = <<~YAML
      templates:
        root: /template
        apply: true
    YAML
    existing_config = "rubygems:\n  min_ruby: '>= 3.2'\n"
    appended_root = <<~YAML
      rubygems:
        min_ruby: '>= 3.2'

      templates:
        root: /template
    YAML
    new_config = <<~YAML
      templates:
        root: /template
    YAML

    expect(described_class.upsert_template_root_override(existing_root, "/template")).to eq(replaced_root)
    expect(described_class.upsert_template_root_override(missing_root, "/template")).to eq(inserted_root)
    expect(described_class.upsert_template_root_override(existing_config, "/template")).to eq(appended_root)
    expect(described_class.upsert_template_root_override("", "/template")).to eq(new_config)
  end

  it "writes template root overrides when the destination config is absent" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest-template-root", tmp_root) do |root|
      described_class.write_template_root_override(root, File.join(root, "template"))

      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(<<~YAML)
        templates:
          root: #{File.join(root, "template")}
      YAML

      described_class.write_template_root_override(root, File.join(root, "template-2"))
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to include("root: #{File.join(root, "template-2")}")
    end
  end

  it "appends drift summaries for available and unavailable drift results" do
    available = described_class.append_drift_summary(
      "Summary",
      {available: true, warning_count: 2, json_path: "tmp/drift.json"}
    )
    available_without_report = described_class.append_drift_summary(
      "Summary",
      {available: true, warning_count: 0}
    )
    unavailable = described_class.append_drift_summary(
      "Summary",
      {available: false, reason: "not installed"}
    )

    expect(described_class.append_drift_summary("Summary", nil)).to eq("Summary")
    expect(available).to include("**Duplicate drift warnings**: 2")
    expect(available).to include("**Drift report**: `tmp/drift.json`")
    expect(available_without_report).to include("**Duplicate drift warnings**: 0")
    expect(available_without_report).not_to include("**Drift report**")
    expect(unavailable).to include("Drift analysis unavailable: not installed")
  end

  it "scores empty comparisons and skips empty diffs" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest-empty-diff", tmp_root) do |root|
      before_dir = File.join(root, "before")
      after_dir = File.join(root, "after")
      diffs_dir = File.join(root, "diffs")
      [before_dir, after_dir, diffs_dir].each { |path| FileUtils.mkdir_p(path) }
      write_file(before_dir, "README.md", "same\n")
      write_file(after_dir, "README.md", "same\n")

      count = described_class.write_diffs({changed: ["README.md"]}, before_dir: before_dir, after_dir: after_dir, diffs_dir: diffs_dir)

      expect(count).to eq(0)
      expect(described_class.score_and_divergence({matched: [], changed: [], added: [], removed: []})).to eq([0.0, 100.0])
    end
  end

  it "runs a real scaffold selftest through the template apply path" do
    tmp_root = File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
    Dir.mktmpdir("kettle-jem-selftest-real-scaffold", tmp_root) do |root|
      write_file(root, "example.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "example"
          spec.summary = "Example"
        end
      RUBY
      write_file(root, ".kettle-jem.yml", <<~YAML)
        templates:
          root: template
          apply: true
          entries:
            - README.md
      YAML
      write_file(root, "README.md", "# Before\n")
      write_file(root, "template/README.md.example", "# Example\n")

      result = described_class.run(project_root: root, min_divergence_threshold: 100)

      expect(result.fetch(:comparison).fetch(:changed)).to include("README.md")
      expect(result.fetch(:output_root)).to start_with(File.join(root, "tmp", "template_test", "output"))
      expected_emoji = ENV.fetch("KJ_PROJECT_EMOJI", "💎")
      expect(File.read(File.join(result.fetch(:output_root), "README.md"))).to include("# #{expected_emoji} Example")
      expect(File).to exist(result.fetch(:report_path))
    end
  end
end
