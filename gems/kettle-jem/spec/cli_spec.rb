# frozen_string_literal: true

require "kettle/jem/cli"
require "stringio"

RSpec.describe Kettle::Jem::CLI do
  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path.to_s)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def run_cli(argv, env: {})
    out = StringIO.new
    err = StringIO.new
    allow(Dir).to receive(:pwd).and_return(tmp_root)
    allow(Kettle::Jem::MaintenanceChangelog).to receive(:record_template_run) do |project_root:, report:, **|
      report
    end
    status = described_class.run(argv, env: env, out: out, err: err)
    [status, out.string, err.string]
  end

  def tmp_root
    File.join(__dir__, "tmp").tap { |path| FileUtils.mkdir_p(path) }
  end

  it "prints help and version information" do
    help_status, help_out, help_err = run_cli(["--help"])
    version_status, version_out, version_err = run_cli(["version"])

    expect(help_status).to eq(0)
    expect(help_out).to include("kettle-jem [PROJECT_ROOT]")
    expect(help_out).to include("kettle-jem prepare")
    expect(help_out).to include("kettle-jem plan")
    expect(help_out).to include("kettle-jem install")
    expect(help_out).to include("kettle-jem selftest")
    expect(help_err).to eq("")
    expect(version_status).to eq(0)
    expect(version_out).to eq("#{Kettle::Jem::Version::VERSION}\n")
    expect(version_err).to eq("")
  end

  it "refuses to target another project from kettle-jem's own project root" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      out = StringIO.new
      err = StringIO.new
      allow(Dir).to receive(:pwd).and_return(File.expand_path("..", __dir__))
      status = described_class.run(["plan", root], env: {}, out: out, err: err)

      expect(status).to eq(2)
      expect(out.string).to eq("")
      expect(err.string).to include("Refusing to run kettle-jem from its own project root")
    end
  end

  it "uses no-subcommand invocation as first-run setup bootstrap" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      status, out, err = run_cli([root])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("setup: bootstrap_config_written")
      expect(out).to include("Review it, then run kettle-jem --accept-config")
      expect(File).to exist(File.join(root, Kettle::Jem::KETTLE_CONFIG_PATH))
      expect(File).not_to exist(File.join(root, ".github", "FUNDING.yml"))
    end
  end

  it "continues setup when first-run config bootstrap is accepted" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run) do |project_root:, env:, run_options:|
        Kettle::Jem.apply_project(project_root, env: env, run_options: run_options).merge(
          mode: "install",
          installed: true,
          install_steps: []
        )
      end

      status, out, err = run_cli(["setup", root, "--accept-config"])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("setup: accepted_config_applied")
      expect(File).to exist(File.join(root, Kettle::Jem::KETTLE_CONFIG_PATH))
      expect(File).to exist(File.join(root, ".github", "FUNDING.yml"))
      expect(Kettle::Jem::Tasks::InstallTask).to have_received(:run).with(
        project_root: root,
        env: {},
        run_options: include(accept_config: true)
      )
    end
  end

  it "plans a project and emits a machine-readable report" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })
      report_path = File.join(root, "tmp", "kettle-jem-plan.json")

      status, out, err = run_cli(["plan", root, "--accept", "--json", "--report", report_path])

      expect(status).to eq(0)
      expect(err).to eq("")
      payload = JSON.parse(out, symbolize_names: true)
      report = JSON.parse(File.read(report_path), symbolize_names: true)
      expect(payload.fetch(:mode)).to eq("plan")
      expect(payload.fetch(:decision_policy).fetch(:mode)).to eq("accept")
      expect(payload.fetch(:changed_files)).to include(Kettle::Jem::KETTLE_CONFIG_PATH)
      expect(report.fetch(:changed_files)).to eq(payload.fetch(:changed_files))
      expect(File.exist?(File.join(root, Kettle::Jem::KETTLE_CONFIG_PATH))).to be(false)
    end
  end

  it "emits newline-delimited JSON template events" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      status, out, err = run_cli(["plan", root, "--accept", "--events"])

      expect(status).to eq(0)
      expect(err).to eq("")
      events = out.lines.map { |line| JSON.parse(line) }
      expect(events.first).to include("event_version" => 1, "type" => "run_start", "mode" => "plan")
      expect(events).to include(include("type" => "phase_start", "phase" => "recipes"))
      expect(events).to include(include("type" => "phase_finish", "phase" => "recipes", "status" => "ok"))
      expect(events).to include(include("type" => "recipe", "path" => Kettle::Jem::KETTLE_CONFIG_PATH))
      summary = events.last
      expect(summary).to include("type" => "summary", "mode" => "plan")
      expect(summary.fetch("planned_count")).to eq(
        summary.fetch("checksum_hit_count") + summary.fetch("checksum_protected_count") +
          summary.fetch("unchanged_count") + summary.fetch("changed_count")
      )
    end
  end

  it "filters newline-delimited JSON events by type" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      status, out, err = run_cli(["plan", root, "--accept", "--events=recipe,summary"])

      expect(status).to eq(0)
      expect(err).to eq("")
      events = out.lines.map { |line| JSON.parse(line) }
      expect(events.map { |event| event.fetch("type") }.uniq).to contain_exactly("recipe", "summary")
    end
  end

  it "maps old executable option semantics into the shared report contract" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      status, out, err = run_cli([
        "plan",
        root,
        "--json",
        "--force",
        "--failure-mode",
        "warn",
        "--allowed",
        "env",
        "--hook-templates",
        "false",
        "--git-drivers",
        "builtin-diff",
        "--quiet",
        "--verbose",
        "--accept-config",
        "--bootstrap-mode",
        "--only",
        "Gemfile,Rakefile",
        "--include",
        "gemfiles/modular/**",
        "--skip-commit",
        "--skip-drift-check",
        "--skip-rubocop-gradual",
        "--skip-binstubs"
      ])

      expect(status).to eq(0)
      expect(err).to eq("")
      payload = JSON.parse(out, symbolize_names: true)
      expect(payload.fetch(:decision_policy)).to include(
        mode: "accept",
        failure_mode: "warn"
      )
      expect(payload.fetch(:template_selection)).to eq(
        allowed: "env",
        hook_templates: "false",
        git_drivers: "builtin-diff",
        only: ["Gemfile", "Rakefile"],
        include: ["gemfiles/modular/**"],
        skip_commit: true,
        skip_drift_check: true,
        skip_rubocop_gradual: true,
        skip_binstubs: true,
        accept_config: true,
        bootstrap_mode: true,
        template_profile: "",
        quiet: true,
        verbose: true
      )
    end
  end

  it "supports old underscore aliases and quiet text output" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      status, out, err = run_cli(["plan", root, "--quiet", "--hook_templates", "false"])

      expect(status).to eq(0)
      expect(out).to eq("")
      expect(err).to eq("")
    end
  end

  it "accepts interactive prompt answers through the shared report contract" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - README.md
        YAML
        "templates/README.md.example" => "# Example\n\nTemplate README.\n",
        "README.md" => "# Example\n\nDestination README.\n"
      })

      status, out, err = run_cli([
        "apply",
        root,
        "--json",
        "--prompt-answer",
        "recipe:readme_metadata=keep",
        "--prompt-answer",
        "recipe:template_source_application_README_md=keep"
      ])

      expect(status).to eq(0)
      expect(err).to eq("")
      payload = JSON.parse(out, symbolize_names: true)
      expect(payload.fetch(:decision_policy)).to include(
        mode: "interactive",
        prompt_answers: {
          "recipe:readme_metadata": "keep",
          "recipe:template_source_application_README_md": "keep"
        }
      )
      expect(payload.fetch(:changed_files)).not_to include("README.md")
      expect(File.read(File.join(root, "README.md"))).to eq("# Example\n\nDestination README.\n")
    end
  end

  it "accepts checksum modes with space, equals, and ignore alias forms" do
    allow(Kettle::Jem).to receive(:plan_project) do |_root, env:, run_options:|
      {
        mode: "plan",
        env: env,
        run_options: run_options,
        checksum_mode: Kettle::Jem::ChecksumMode.parse(run_options[:checksums]).to_s
      }
    end

    space_status, space_out, space_err = run_cli(["plan", "--json", "--checksums", "dest,template"])
    equals_status, equals_out, equals_err = run_cli(["plan", "--json", "--checksums=dest,ignore-template"])
    ignore_status, ignore_out, ignore_err = run_cli(["plan", "--json", "--ignore-checksums"])

    expect(space_status).to eq(0)
    expect(space_err).to eq("")
    expect(JSON.parse(space_out).fetch("checksum_mode")).to eq("dest,template")
    expect(equals_status).to eq(0)
    expect(equals_err).to eq("")
    expect(JSON.parse(equals_out).fetch("checksum_mode")).to eq("dest,ignore-template")
    expect(ignore_status).to eq(0)
    expect(ignore_err).to eq("")
    expect(JSON.parse(ignore_out).fetch("checksum_mode")).to eq("off")
  end

  it "aliases bare template to the full install task" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run).and_return(
        mode: "install",
        installed: true,
        changed_files: [],
        install_steps: []
      )
      allow(Kettle::Jem::Tasks::TemplateTask).to receive(:run)

      status, out, err = run_cli([
        "template",
        root,
        "--skip-commit",
        "--skip-drift-check",
        "--skip-rubocop-gradual",
        "--skip-binstubs"
      ], env: {"K_JEM_TEMPLATING" => "true"})

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("install: 0 changed files")
      expect(Kettle::Jem::Tasks::InstallTask).to have_received(:run).with(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: include(
          skip_commit: true,
          skip_drift_check: true,
          skip_rubocop_gradual: true,
          skip_binstubs: true
        )
      )
      expect(Kettle::Jem::Tasks::TemplateTask).not_to have_received(:run)
    end
  end

  it "routes scoped template through the template task orchestration" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      allow(Kettle::Jem::Tasks::TemplateTask).to receive(:run).and_return(
        mode: "apply",
        changed_files: [],
        template_steps: [{
          name: "bundle_lock_normalization",
          status: "succeeded",
          reason: "executed"
        }]
      )
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run)

      status, out, err = run_cli(["template", root, "--skip-commit", "--only", "README.md"], env: {"K_JEM_TEMPLATING" => "true"})

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("apply: 0 changed files")
      expect(Kettle::Jem::Tasks::TemplateTask).to have_received(:run).with(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: include(skip_commit: true, only: ["README.md"])
      )
      expect(Kettle::Jem::Tasks::InstallTask).not_to have_received(:run)
    end
  end

  it "runs the prepare command through the pre-flight prepare task" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      allow(Kettle::Jem::Tasks::PrepareTask).to receive(:run).and_return(
        mode: "prepare",
        prepared: true,
        changed_files: ["Gemfile", "gemfiles/modular/templating.gemfile"],
        prepare_steps: [{name: "bundle_install", status: "succeeded"}]
      )

      status, out, err = run_cli(["prepare", root, "--force"], env: {"K_JEM_TEMPLATING" => "true"})

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("prepare: 2 changed files")
      expect(Kettle::Jem::Tasks::PrepareTask).to have_received(:run).with(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: include(force: true)
      )
    end
  end

  it "records a changelog summary after a mutating template command" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      allow(Kettle::Jem::Tasks::TemplateTask).to receive(:run).and_return(
        mode: "template",
        changed_files: ["README.md"],
        template_steps: []
      )

      status, _out, err = run_cli(["template", root, "--only", "README.md"], env: {"K_JEM_TEMPLATING" => "true"})

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(Kettle::Jem::MaintenanceChangelog).to have_received(:record_template_run).with(
        project_root: root,
        report: include(mode: "template", changed_files: ["README.md"]),
        run_options: include(only: ["README.md"]),
        label: "Apply kettle-jem templates"
      )
    end
  end

  it "prints old debug diagnostics without changing normal output" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      allow(Kettle::Jem).to receive(:plan_project).and_raise(Kettle::Jem::Error, "debug failure")

      status, out, err = run_cli(["plan", root, "--quiet"], env: {"DEBUG" => "true", "KETTLE_DEV_DEV" => "true"})

      expect(status).to eq(1)
      expect(out).to eq("")
      expect(err).to include("[kettle-jem] DEBUG: early environment snapshot")
      expect(err).to include("command=\"plan\"")
      expect(err).to include("DEBUG=\"true\"")
      expect(err).to include("KETTLE_DEV_DEV=\"true\"")
      expect(err).to include("Kettle::Jem::Error: debug failure")
      expect(err).to include("kettle/jem/cli.rb")
    end
  end

  it "applies a project through the template alias" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run) do |project_root:, env:, run_options:|
        File.write(File.join(project_root, ".kettle-jem.yml"), "templates:\n  root: packaged\n")
        {
          mode: "install",
          changed_files: [".kettle-jem.yml"],
          install_steps: [],
          install_phase_reports: []
        }
      end

      status, out, err = run_cli(["template", root, "--force", "--skip-commit"])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("install:")
      expect(File.exist?(File.join(root, ".kettle-jem.yml"))).to be(true)
      expect(Kettle::Jem::Tasks::InstallTask).to have_received(:run).with(
        project_root: root,
        env: {},
        run_options: include(force: true, skip_commit: true)
      )
    end
  end

  it "runs the install command through the active install task" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run).and_return(
        {
          mode: "install",
          installed: false,
          changed_files: [],
          diagnostics: []
        }
      )

      status, out, err = run_cli(["install", root, "--force"])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to include("install: 0 changed files")
      expect(Kettle::Jem::Tasks::InstallTask).to have_received(:run).with(
        project_root: root,
        env: {},
        run_options: include(force: true)
      )
    end
  end

  it "prints template manifest summaries" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      status, out, err = run_cli(["manifest", root])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(out).to match(/template manifest: \d+ entries/)
    end
  end

  it "runs the selftest command and emits a report" do
    Dir.mktmpdir("kettle-jem-cli", tmp_root) do |root|
      report_path = File.join(root, "tmp", "selftest.json")
      allow(Kettle::Jem::Tasks::SelfTestTask).to receive(:run).and_return(
        {
          mode: "selftest",
          report_path: File.join(root, "tmp", "template_test", "report", "summary.md"),
          comparison: {
            matched: ["README.md"],
            changed: ["Gemfile"],
            added: [],
            removed: [],
            skipped: []
          }
        }
      )

      template_root = File.join(root, "template")
      output_root = File.join(root, "tmp", "selftest-output")
      status, out, err = run_cli([
        "selftest",
        root,
        "--json",
        "--report",
        report_path,
        "--destination",
        root,
        "--template-root",
        template_root,
        "--selftest-output",
        output_root,
        "--min-divergence-threshold",
        "75"
      ])

      expect(status).to eq(0)
      expect(err).to eq("")
      expect(Kettle::Jem::Tasks::SelfTestTask).to have_received(:run).with(
        project_root: root,
        destination_root: root,
        template_root: template_root,
        output_root: output_root,
        min_divergence_threshold: 75.0
      )
      payload = JSON.parse(out, symbolize_names: true)
      expect(payload.fetch(:mode)).to eq("selftest")
      expect(payload.fetch(:comparison).fetch(:changed)).to eq(["Gemfile"])
      expect(JSON.parse(File.read(report_path), symbolize_names: true).fetch(:mode)).to eq("selftest")
    end
  end
end
