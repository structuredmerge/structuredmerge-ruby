# frozen_string_literal: true

# Covers the slice-1038 platform-support feature in kettle-jem:
#
# - platforms: config key accessors (os_platforms_config, enabled_os_platforms)
# - ci_os_platforms_facts: configured → detected → default, so a missing key
#   cannot silently drop existing Windows CI on the first templating run
# - detected_os_platforms: Windows evidence from destination workflows
# - migrate_platforms_config: key injection with documentation, adjacent to
#   engines:, value computed from repo evidence
# - github_actions_current_os_matrix_entries / _os_test_steps: current.yml
#   generation from facts (Windows guards and step only when declared)
#
# The evidence data itself (Kettle::Rb::PlatformSupport) is covered in kettle-rb.

require "tmpdir"
require "fileutils"
require "yaml"

RSpec.describe Kettle::Jem do
  let(:current_yml_template) do
    File.read(
      File.expand_path("../../lib/kettle/jem/templates/.github/workflows/current.yml.example", __dir__)
    )
  end

  def ci_facts(platforms, exec_cmd: "bundle exec kettle-test")
    {ci: {exec_cmd: exec_cmd, platforms: platforms}}
  end

  describe "platforms config accessors" do
    it "normalizes values and falls back to the default when absent or empty" do
      expect(described_class.send(:os_platforms_config, {"platforms" => [" Linux ", "WINDOWS", "linux", ""]})).to eq(%w[linux windows])
      expect(described_class.send(:os_platforms_config, {"platforms" => "linux"})).to be_nil
      expect(described_class.send(:os_platforms_config, {})).to be_nil

      expect(described_class.send(:enabled_os_platforms, {"platforms" => ["windows"]})).to eq(["windows"])
      expect(described_class.send(:enabled_os_platforms, {"platforms" => []})).to eq(%w[linux macos])
      expect(described_class.send(:enabled_os_platforms, {})).to eq(%w[linux macos])
    end

    it "defaults exclude windows, which is opt-in only" do
      expect(described_class::DEFAULT_PLATFORMS).to eq(%w[linux macos])
    end
  end

  describe "detected_os_platforms" do
    it "returns [] with no workflow directory, the default without Windows evidence, and adds windows with it" do
      Dir.mktmpdir do |root|
        expect(described_class.send(:detected_os_platforms, root)).to be_empty

        FileUtils.mkdir_p(File.join(root, ".github", "workflows"))
        File.write(File.join(root, ".github", "workflows", "ci.yml"), "runs-on: ubuntu-latest\n")
        expect(described_class.send(:detected_os_platforms, root)).to eq(%w[linux macos])

        File.write(File.join(root, ".github", "workflows", "current.yml"), "matrix:\n  include:\n    - os: windows-latest\n")
        expect(described_class.send(:detected_os_platforms, root)).to eq(%w[linux macos windows])
      end
    end

    it "recognizes versioned and ARM Windows runner labels, not just windows-latest" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, ".github", "workflows"))
        File.write(File.join(root, ".github", "workflows", "win.yml"), "runs-on: windows-2022\n")
        expect(described_class.send(:detected_os_platforms, root)).to include("windows")

        File.write(File.join(root, ".github", "workflows", "win.yml"), "runs-on: windows-11-arm\n")
        expect(described_class.send(:detected_os_platforms, root)).to include("windows")
      end
    end
  end

  describe "ci_os_platforms_facts" do
    it "is configured → detected → default" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, ".github", "workflows"))
        File.write(File.join(root, ".github", "workflows", "current.yml"), "os: windows-latest\n")

        expect(described_class.send(:ci_os_platforms_facts, {"platforms" => ["linux"]}, root)).to eq(["linux"])
        expect(described_class.send(:ci_os_platforms_facts, {}, root)).to eq(%w[linux macos windows])

        Dir.mktmpdir do |empty|
          expect(described_class.send(:ci_os_platforms_facts, {}, empty)).to eq(%w[linux macos])
        end
      end
    end
  end

  describe "migrate_platforms_config" do
    it "injects the detected value with documentation adjacent to engines:" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, ".github", "workflows"))
        File.write(File.join(root, ".github", "workflows", "current.yml"), "    - os: windows-latest\n")
        content = "engines:\n  - ruby\n  - jruby\n\nruby:\n  test_minimum: \"2.4\"\n"

        migrated = described_class.send(:migrate_platforms_config, content, root)
        parsed = YAML.safe_load(migrated)

        expect(parsed["platforms"]).to eq(%w[linux macos windows])
        expect(parsed["engines"]).to eq(%w[ruby jruby])
        expect(migrated.index("platforms:")).to be > migrated.index("engines:")
        expect(migrated.index("platforms:")).to be < migrated.index("ruby:")
        expect(migrated).to include("# Supported values: linux, macos, windows")
      end
    end

    it "defaults the injected value when there is no workflow evidence" do
      Dir.mktmpdir do |root|
        migrated = described_class.send(:migrate_platforms_config, "engines:\n  - ruby\n", root)

        expect(YAML.safe_load(migrated)["platforms"]).to eq(%w[linux macos])
      end
    end

    it "leaves a present key untouched, including a flow-style sequence" do
      Dir.mktmpdir do |root|
        content = "platforms: [windows]\nengines:\n  - ruby\n"

        expect(described_class.send(:migrate_platforms_config, content, root)).to eq(content)
      end
    end

    it "appends at end of file when there is no engines: anchor" do
      Dir.mktmpdir do |root|
        migrated = described_class.send(:migrate_platforms_config, "ruby:\n  test_minimum: \"2.4\"\n", root)

        expect(YAML.safe_load(migrated)["platforms"]).to eq(%w[linux macos])
        expect(migrated).to include("platforms:")
      end
    end

    it "does not anchor on a nested engines: key" do
      Dir.mktmpdir do |root|
        content = "files:\n  nested:\n    engines:\n      - ruby\n"
        migrated = described_class.send(:migrate_platforms_config, content, root)

        expect(migrated.index("platforms:")).to be > migrated.index("      - ruby")
      end
    end
  end

  describe "github_actions_current_os_matrix_entries" do
    it "emits one entry per declared platform in order, with runner labels from the evidence data" do
      entries = described_class.send(:github_actions_current_os_matrix_entries, ci_facts(%w[linux macos windows]))

      expect(entries.scan('- ruby: "ruby"').length).to eq(3)
      expect(entries).to include("os: ubuntu-latest", "os: macos-latest", "os: windows-latest")
      expect(entries).to include('exec_cmd: "bundle exec kettle-test"')
    end

    it "falls back to the default platforms when facts are absent" do
      entries = described_class.send(:github_actions_current_os_matrix_entries, {ci: {}})

      expect(entries).to include("os: ubuntu-latest", "os: macos-latest")
      expect(entries).not_to include("os: windows-latest")
    end

    it "raises on an unknown OS family rather than silently dropping a lane" do
      expect {
        described_class.send(:github_actions_current_os_matrix_entries, ci_facts(%w[linux windos]))
      }.to raise_error(Kettle::Jem::Error, /windos/)
    end
  end

  describe "github_actions_current_os_test_steps" do
    it "emits a single unguarded step when windows is not declared" do
      steps = described_class.send(:github_actions_current_os_test_steps, ci_facts(%w[linux macos]))

      expect(steps).not_to include("windows-latest")
      expect(steps).not_to include("if:")
      expect(steps).to include("run: bundle exec appraisal ${{ matrix.appraisal }} ${{ matrix.exec_cmd }}")
    end

    it "emits the guard and the Windows-only step only when windows is declared" do
      steps = described_class.send(:github_actions_current_os_test_steps, ci_facts(%w[linux macos windows]))

      expect(steps).to include("if: matrix.os != 'windows-latest'")
      expect(steps).to include("if: matrix.os == 'windows-latest'")
      expect(steps).to include("run: ruby -rbundler/setup bin/kettle-test")
      expect(steps).to include("BUNDLE_GEMFILE: ${{ github.workspace }}/gemfiles/current.gemfile")
    end

    it "derives the Windows step's binstub from the destination's own exec_cmd" do
      steps = described_class.send(:github_actions_current_os_test_steps, ci_facts(%w[windows], exec_cmd: "rspec"))
      expect(steps).to include("run: ruby -rbundler/setup bin/rspec")

      steps = described_class.send(:github_actions_current_os_test_steps, ci_facts(%w[windows], exec_cmd: "ruby bin/turbo_tests2"))
      expect(steps).to include("run: ruby -rbundler/setup bin/turbo_tests2")
    end

    it "defaults the binstub to the curated kettle-test binstub when exec_cmd is empty" do
      steps = described_class.send(:github_actions_current_os_test_steps, ci_facts(%w[windows], exec_cmd: ""))

      expect(steps).to include("run: ruby -rbundler/setup bin/kettle-test")
    end
  end

  describe "github_actions_macos_hardening_step" do
    let(:script) { File.read(File.expand_path("../../lib/kettle/jem/ci/harden_macos_ca_bundle.sh", __dir__)).rstrip }

    def step_for(platforms)
      described_class.send(:github_actions_macos_hardening_step, ci_facts(platforms))
    end

    it "is empty when macos is not declared, so no dead step is emitted" do
      expect(step_for(%w[linux])).to eq("")
      expect(step_for(%w[linux windows])).to eq("")
    end

    it "emits a macOS-only inline step when macos is declared, including by default" do
      step = step_for(%w[linux macos])

      expect(step).to start_with("      - name: Remove eMudhra roots from the macOS CA bundle\n")
      expect(step).to include("        if: runner.os == 'macOS'\n")
      expect(step).to end_with("\n\n")
      expect(described_class.send(:github_actions_macos_hardening_step, {ci: {}})).to eq(step)
    end

    it "inlines the packaged script verbatim and parses as a workflow step" do
      steps = YAML.safe_load(step_for(%w[linux macos windows]))

      expect(steps.length).to eq(1)
      expect(steps.first).to include("if" => "runner.os == 'macOS'", "shell" => "bash")
      expect(steps.first.fetch("run").rstrip).to eq(script)
      expect(steps.first).not_to have_key("uses")
    end

    it "is wired in before checkout in the current.yml template" do
      template = File.read(File.expand_path("../../lib/kettle/jem/templates/.github/workflows/current.yml.example", __dir__))

      expect(template).to match(/steps:\n\{KJ\|CI:MACOS_HARDENING_STEP\}      - name: Checkout\n/)
    end

    it "produces a current.yml whose first step hardens macOS before checkout" do
      template = File.read(File.expand_path("../../lib/kettle/jem/templates/.github/workflows/current.yml.example", __dir__))
      rendered = template.sub("{KJ|CI:MACOS_HARDENING_STEP}", step_for(%w[linux macos]))
      rendered = rendered.sub("{KJ|CI:OS_MATRIX_ENTRIES}", "")
      names = rendered.scan(/^      - name: (.+)$/).flatten

      expect(names.first(2)).to eq(["Remove eMudhra roots from the macOS CA bundle", "Checkout"])
    end

    it "leaves the template unchanged for destinations without macos" do
      template = File.read(File.expand_path("../../lib/kettle/jem/templates/.github/workflows/current.yml.example", __dir__))
      rendered = template.sub("{KJ|CI:MACOS_HARDENING_STEP}", step_for(%w[linux]))

      expect(rendered).to include("    steps:\n      - name: Checkout\n")
    end
  end

  describe "readme_current_mri_platforms" do
    def summary_facts(platforms:)
      {ci: {platforms: platforms}}
    end

    it "summarizes the current-runtime OS matrix without engine/version claims" do
      platforms = described_class.send(:readme_current_mri_platforms, summary_facts(platforms: %w[linux macos]))

      expect(platforms).to eq("Linux and macOS")
      expect(platforms).not_to include("JRuby", "TruffleRuby", "all CI lanes", "Parallel support", "Unsupported", "MRI 2.4")
    end

    it "falls back to configured defaults when facts are absent" do
      platforms = described_class.send(:readme_current_mri_platforms, {})

      expect(platforms).to eq("Linux and macOS")
    end
  end

  describe "packaged current.yml template" do
    it "resolves its tokens through the real pipeline into valid YAML" do
      facts = ci_facts(%w[linux macos windows])
      resolved = described_class.send(
        :resolve_template_tokens,
        current_yml_template,
        {
          "KJ|CI:EXEC_CMD" => "bundle exec kettle-test",
          "KJ|CI:OS_MATRIX_ENTRIES" => described_class.send(:github_actions_current_os_matrix_entries, facts),
          "KJ|CI:OS_TEST_STEPS" => described_class.send(:github_actions_current_os_test_steps, facts),
          "KJ|CI:MACOS_HARDENING_STEP" => described_class.send(:github_actions_macos_hardening_step, facts)
        }
      )

      expect(resolved).not_to include("{KJ|")
      workflow = YAML.safe_load(resolved.gsub(/\{\{.*?}}/, "x"), aliases: true)
      expect(workflow.dig("jobs", "test", "strategy", "matrix", "include").length).to eq(3)
      steps = workflow.dig("jobs", "test", "steps")
      expect(steps.first(2).map { |step| step["name"] }).to eq(["Remove eMudhra roots from the macOS CA bundle", "Checkout"])
      expect(steps.first["if"]).to eq("runner.os == 'macOS'")
    end
  end
end
