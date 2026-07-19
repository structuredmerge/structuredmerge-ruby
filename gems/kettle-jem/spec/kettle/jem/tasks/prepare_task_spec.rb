# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe Kettle::Jem::Tasks::PrepareTask do
  def tmp_root
    File.expand_path("../../../../tmp", __dir__).tap { |path| FileUtils.mkdir_p(path) }
  end

  it "updates critical templating gems after applying the dependency bootstrap payload" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")
      command_runner = double("command_runner")
      setup_env = {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")}
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
      expect(result.fetch(:prepare_steps)).to eq([update_step, bundle_step])
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

  it "keeps the cold-start update command minimal when no lockfile exists" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      expect(described_class.bundle_update_templating_bootstrap_command(root)).to eq(
        %w[bundle update nomono]
      )
    end
  end

  it "lists parser gems that need lock-aware update handling" do
    expect(described_class::LOCKED_TEMPLATING_GEMS).to eq(
      %w[tree_sitter_language_pack]
    )
  end
end
