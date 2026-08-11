# frozen_string_literal: true

RSpec.describe Kettle::Jem::Tasks::PrepareTask do
  def tmp_root
    File.expand_path("../../../../tmp", __dir__).tap { |path| FileUtils.mkdir_p(path) }
  end

  it "prepares every modular Gemfile needed by the generated main Gemfile before Bundler runs" do
    expect(described_class::PREPARE_ONLY_PATHS).to include("Gemfile", "gemfiles/modular/**")
    expect(described_class::PREPARE_ONLY_PATHS).not_to include("gemfiles/modular/templating.gemfile")
  end

  it "resynchronizes monorepo subgem entries before bootstrapping new modular Gemfiles" do
    report = {
      facts: {template_profile: "monorepo-subgem-package"}
    }
    sync_step = {name: "monorepo_subgem_kettle_config_profile_sync", status: "applied"}

    allow(Kettle::Jem).to receive(:monorepo_subgem_template_profile?)
      .with(report.fetch(:facts))
      .and_return(true)
    allow(Kettle::Jem).to receive(:monorepo_subgem_kettle_config_profile_sync_step)
      .with("/workspace/project", report)
      .and_return(sync_step)

    expect(described_class.synchronize_monorepo_subgem_profile_step("/workspace/project", report)).to eq(sync_step)
  end

  it "merges the supplemental scoped apply after a profile sync" do
    report = {
      changed_files: ["Gemfile"],
      diagnostics: [{message: "initial"}]
    }
    supplemental = {
      changed_files: ["Gemfile", "gemfiles/modular/changelog.gemfile"],
      diagnostics: [{message: "supplemental"}]
    }

    expect(described_class.merge_supplemental_prepare_report(report, supplemental)).to include(
      changed_files: ["Gemfile", "gemfiles/modular/changelog.gemfile"],
      diagnostics: [{message: "initial"}, {message: "supplemental"}]
    )
  end

  it "repairs legacy local Gemfile nomono bootstraps before Bundler starts" do
    Dir.mktmpdir("kettle-jem-prepare-nomono-repair", tmp_root) do |root|
      path = File.join(root, "gemfiles/modular/coverage_local.gemfile")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        nomono_activation_requirements = ["~> 1.1", ">= 1.1.3"]
        nomono_lockfile = File.expand_path("../../Gemfile.lock", __dir__)
        if File.file?(nomono_lockfile)
          nomono_locked_spec = Bundler::LockfileParser.new(Bundler.read_file(nomono_lockfile)).specs.find { |spec| spec.name == "nomono" }
          nomono_locked = nomono_locked_spec && Gem::Requirement.new(nomono_activation_requirements).satisfied_by?(nomono_locked_spec.version)
        nomono_activation_requirements = ["= \#{nomono_locked_spec.version}"] if nomono_locked
        end
        Kernel.send(:gem, "nomono", *nomono_activation_requirements)
        require "nomono/bundler"

        local_gems = %w[example]
      RUBY

      step = described_class.normalize_existing_local_gemfile_bootstraps_step(
        root,
        events: Kettle::Jem.event_stream_from_options({})
      )
      expect(step.fetch(:status)).to eq("applied")
      expect(step.fetch(:changed_files)).to eq(["gemfiles/modular/coverage_local.gemfile"])
      content = File.read(path)
      expect(content).to include('nomono_activation_requirements = ["~> 1.1", ">= 1.1.4"]')
      expect(content).to include('Gem::Specification.find_all_by_name("nomono")')
      expect(content.scan(/^require "nomono\/bundler"$/).size).to eq(1)
    end
  end

  it "updates critical templating gems after applying the dependency bootstrap payload" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          specs:
            nomono (1.0.8)
      LOCK
      command_runner = double("command_runner")
      setup_env = {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")}
      reset_step = {
        name: "reset_release_lockfiles",
        status: "succeeded",
        changed_files: ["Gemfile.lock"]
      }
      update_step = {
        name: "bundle_update_templating_bootstrap",
        status: "succeeded",
        changed_files: ["Gemfile.lock"]
      }
      bundle_step = {
        name: "bundle_install",
        status: "succeeded",
        changed_files: ["Gemfile.lock"]
      }

      allow(Kettle::Jem).to receive(:apply_project).and_return(
        mode: "apply",
        changed_files: ["Gemfile"],
        diagnostics: []
      )
      allow(Kettle::Jem::Tasks::InstallTask).to receive_messages(
        setup_command_env: setup_env
      )
      allow(described_class).to receive(:reset_release_lockfiles_step)
        .with(
          project_root: root,
          setup_env: setup_env,
          quiet: false,
          command_runner: command_runner,
          events: an_instance_of(Kettle::Ndjson::EventRecorder)
        )
        .and_return(reset_step)
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run_command_step)
        .with(
          "bundle_update_templating_bootstrap",
          %w[bundle update nomono],
          project_root: root,
          env: setup_env,
          quiet: false,
          command_runner: command_runner
        )
        .and_return(update_step)
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run_command_step)
        .with(
          "bundle_install",
          %w[bundle install],
          project_root: root,
          env: setup_env,
          quiet: false,
          command_runner: command_runner
        )
        .and_return(bundle_step)

      result = described_class.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {force: true},
        command_runner: command_runner
      )

      expect(result).to include(
        mode: "prepare",
        prepared: true,
        prepare_only: described_class::PREPARE_ONLY_PATHS
      )
      expect(result.fetch(:prepare_steps)).to eq([
        {
          name: "normalize_local_gemfile_bootstraps",
          status: "already_current",
          changed_files: []
        },
        reset_step,
        update_step,
        bundle_step
      ])
      expect(result.fetch(:changed_files)).to eq(["Gemfile", "Gemfile.lock"])
      expect(Kettle::Jem).to have_received(:apply_project).with(
        root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: include(
          force: true,
          only: described_class::PREPARE_ONLY_PATHS,
          skip_lock_normalization: true
        )
      )
    end
  end

  it "installs once for cold-start projects without a lockfile" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")
      command_runner = double("command_runner")
      setup_env = {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")}
      reset_step = {
        name: "reset_release_lockfiles",
        command: %w[kettle-reset release-lockfiles],
        status: "skipped",
        reason: "no_release_lockfiles"
      }
      bootstrap_step = {
        name: "bundle_install_templating_bootstrap",
        status: "succeeded",
        changed_files: ["Gemfile.lock"]
      }

      allow(Kettle::Jem).to receive(:apply_project).and_return(
        mode: "apply",
        changed_files: ["Gemfile"],
        diagnostics: []
      )
      allow(Kettle::Jem::Tasks::InstallTask).to receive_messages(
        setup_command_env: setup_env
      )
      allow(described_class).to receive(:reset_release_lockfiles_step)
        .with(
          project_root: root,
          setup_env: setup_env,
          quiet: false,
          command_runner: command_runner,
          events: an_instance_of(Kettle::Ndjson::EventRecorder)
        )
        .and_return(reset_step)
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run_command_step)
        .with(
          "bundle_install_templating_bootstrap",
          %w[bundle install],
          project_root: root,
          env: setup_env,
          quiet: false,
          command_runner: command_runner
        )
        .and_return(bootstrap_step)

      result = described_class.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {force: true},
        command_runner: command_runner
      )

      expect(result).to include(
        mode: "prepare",
        prepared: true,
        prepare_only: described_class::PREPARE_ONLY_PATHS
      )
      expect(result.fetch(:prepare_steps)).to eq([
        {
          name: "normalize_local_gemfile_bootstraps",
          status: "already_current",
          changed_files: []
        },
        reset_step,
        bootstrap_step,
        {
          name: "bundle_install",
          command: %w[bundle install],
          status: "skipped",
          reason: "already_ran_as_templating_bootstrap"
        }
      ])
      expect(Kettle::Jem::Tasks::InstallTask).to have_received(:run_command_step).once
    end
  end

  it "resets release lockfiles before running the templating bootstrap command" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      lockfile = File.join(root, "Gemfile.lock")
      File.write(lockfile, "GEM\n")
      resetter = instance_double(Kettle::Dev::LockfileReset)
      calls = []
      command_runner = ->(command) { calls << [:command_runner, command] }

      allow(Kettle::Dev::LockfileReset).to receive(:new)
        .with(root: root, command_runner: an_instance_of(Proc))
        .and_return(resetter)
      allow(resetter).to receive(:lockfile_paths).and_return([lockfile])
      allow(resetter).to receive(:reset) do |target|
        calls << [:reset, target]
        File.write(lockfile, "GEM\n\nCHECKSUMS\n  rake (13.4.2) sha256=abc123\n")
      end

      step = described_class.reset_release_lockfiles_step(
        project_root: root,
        setup_env: {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")},
        quiet: false,
        command_runner: command_runner,
        events: nil
      )

      expect(step).to include(
        name: "reset_release_lockfiles",
        status: "succeeded",
        changed_files: ["Gemfile.lock"]
      )
      expect(calls).to eq([[:reset, Kettle::Dev::LockfileReset::RELEASE_LOCKFILES_TARGET]])
    end
  end

  it "skips release lockfile reset during local path template stack development" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile.lock"), "GEM\n")
      command_runner = ->(_command) { raise "unexpected command" }

      step = described_class.reset_release_lockfiles_step(
        project_root: root,
        setup_env: {
          "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
          "STRUCTUREDMERGE_DEV" => "/workspace/structuredmerge/ruby/gems"
        },
        quiet: false,
        command_runner: command_runner,
        events: nil
      )

      expect(step).to include(
        name: "reset_release_lockfiles",
        status: "skipped",
        reason: "local_path_development_env"
      )
    end
  end

  it "keeps templating enabled for bootstrap bundle commands during local path development" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")
      File.write(File.join(root, "Gemfile.lock"), "GEM\n")
      command_runner = double("command_runner")
      captured_env = nil

      allow(Kettle::Jem).to receive(:apply_project).and_return(
        mode: "apply",
        changed_files: [],
        diagnostics: []
      )
      allow(Kettle::Jem::Tasks::InstallTask).to receive(:run_command_step) do |_name, _command, project_root:, env:, quiet:, command_runner:|
        captured_env ||= env
        {
          name: "bundle_update_templating_bootstrap",
          status: "succeeded",
          changed_files: []
        }
      end

      described_class.run(
        project_root: root,
        env: {
          "K_JEM_TEMPLATING" => "true",
          "STRUCTUREDMERGE_DEV" => "/workspace/structuredmerge/ruby/gems"
        },
        run_options: {force: true},
        command_runner: command_runner
      )

      expect(captured_env).to include(
        "K_JEM_TEMPLATING" => "true",
        "STRUCTUREDMERGE_DEV" => "/workspace/structuredmerge/ruby/gems"
      )
    end
  end

  it "updates lockfile-safe templating bootstrap gems before the full template run" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          specs:
            nomono (1.0.8)
            tree_sitter_language_pack (1.13.0)
      LOCK

      expect(described_class.bundle_update_templating_bootstrap_command(root)).to eq(
        %w[bundle update nomono tree_sitter_language_pack]
      )
    end
  end

  it "does not explicitly update parser gems before they are present in the lockfile" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          specs:
            nomono (1.0.8)
      LOCK

      expect(described_class.bundle_update_templating_bootstrap_command(root)).to eq(
        %w[bundle update nomono]
      )
    end
  end

  it "uses bundle install as the cold-start bootstrap command when no lockfile exists" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      expect(described_class.templating_bootstrap_command(root)).to eq(%w[bundle install])
      expect(described_class.templating_bootstrap_step_name(root)).to eq("bundle_install_templating_bootstrap")
    end
  end

  it "uses bundle install until a legacy lockfile contains nomono" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
        GEM
          specs:
            rake (13.2.1)
      LOCK

      expect(described_class.templating_bootstrap_command(root)).to eq(%w[bundle install])
      expect(described_class.templating_bootstrap_step_name(root)).to eq("bundle_install_templating_bootstrap")
    end
  end

  it "lists parser gems that need lock-aware update handling" do
    expect(described_class::LOCKED_TEMPLATING_GEMS).to eq(
      %w[tree_sitter_language_pack]
    )
  end
end
