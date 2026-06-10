# frozen_string_literal: true

require_relative "../../../spec_helper"

RSpec.describe Kettle::Jem::Tasks::PrepareTask do
  def tmp_root
    File.expand_path("../../../../tmp", __dir__).tap { |path| FileUtils.mkdir_p(path) }
  end

  it "applies only the dependency bootstrap payload and runs bundle install" do
    Dir.mktmpdir("kettle-jem-prepare", tmp_root) do |root|
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")
      command_runner = double("command_runner")
      setup_env = {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")}
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
        setup_command_env: setup_env,
        run_command_step: bundle_step
      )

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
      expect(Kettle::Jem::Tasks::InstallTask).to have_received(:run_command_step).with(
        "bundle_install",
        %w[bundle install],
        project_root: root,
        env: setup_env,
        quiet: false,
        command_runner: command_runner
      )
    end
  end
end
