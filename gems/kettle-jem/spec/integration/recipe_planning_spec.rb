# frozen_string_literal: true

RSpec.describe Kettle::Jem, "recipe planning and write-intent behavior" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "deduplicates destination file reads while planning recipes" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-file-cache", tmp_root) do |root|
      write_tree(root, {"README.md" => "# Example\n"})
      pack = {
        recipes: [
          {target_path: "README.md"},
          {target_path: "README.md"},
          {target_path: "CHANGELOG.md"}
        ]
      }
      readme_path = File.join(root, "README.md")

      allow(File).to receive(:read).and_call_original

      files = described_class.send(:read_project_files, root, pack)

      expect(files).to eq("README.md" => "# Example\n", "CHANGELOG.md" => "")
      expect(File).to have_received(:read).with(readme_path).once
    end
  end


  it "deduplicates template source reads while planning recipes" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-cache", tmp_root) do |root|
      write_tree(root, {"templates/README.md.example" => "# {KJ|GEM_NAME}\n"})
      template_path = File.join(root, "templates/README.md.example")
      template_preference = {
        source_root_path: root,
        source_relative_path: "templates/README.md.example",
        selected_source: "templates/README.md.example"
      }
      pack = {
        recipes: [
          {primitive: "supplied_template_source_application", target_path: "README.md", template_preference: template_preference},
          {primitive: "supplied_template_source_application", target_path: "README.md", template_preference: template_preference},
          {primitive: "supplied_managed_text_block_replacement", target_path: "gemfiles/modular/shunted.gemfile"}
        ]
      }

      allow(File).to receive(:read).and_call_original

      contents = described_class.send(:read_template_source_files, root, pack)

      expect(contents).to eq(template_path => "# {KJ|GEM_NAME}\n")
      expect(File).to have_received(:read).with(template_path).once
      expect(
        described_class.send(:recipe_template_content, root, pack.fetch(:recipes).first, template_contents: contents)
      ).to eq("# {KJ|GEM_NAME}\n")
    end
  end


  it "records recipe timing metadata in top-level and envelope reports" do
    report = described_class.send(:timed_recipe_report) do
      {
        metadata: {packaging_recipe: "example"},
        report_envelope: {
          report: {
            metadata: {packaging_recipe: "example"}
          }
        }
      }
    end

    expect(report.dig(:metadata, :duration_ms)).to be >= 0
    expect(report.dig(:report_envelope, :report, :metadata, :duration_ms)).to eq(report.dig(:metadata, :duration_ms))
  end


  it "parses recipe planning strategies from options and env" do
    expect(described_class.send(:recipe_planning_strategy_for, {}, {})).to eq("sequential")
    expect(described_class.send(:recipe_planning_strategy_for, {"KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified"}, {})).to eq("classified")
    expect(described_class.send(:recipe_planning_strategy_for, {}, {recipe_planning_strategy: "true"})).to eq("classified")
    expect(described_class.send(:recipe_planning_strategy_for, {"KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified"}, {recipe_planning_strategy: "sequential"})).to eq("sequential")

    expect do
      described_class.send(:recipe_planning_strategy_for, {}, {recipe_planning_strategy: "ractor"})
    end.to raise_error(ArgumentError, /Unsupported kettle-jem recipe planning strategy/)
  end


  it "parses Ractor recipe planning workers from options and env" do
    expect(described_class.send(:recipe_planning_workers_for, {}, {})).to eq(0)
    expect(described_class.send(:recipe_planning_workers_for, {"KETTLE_JEM_RACTOR_WORKERS" => "2"}, {})).to eq(2)
    expect(described_class.send(:recipe_planning_workers_for, {"KETTLE_JEM_RACTOR_WORKERS" => "2"}, {recipe_planning_workers: "1"})).to eq(1)
    expect(described_class.send(:recipe_planning_workers_for, {}, {ractor_workers: "3"})).to eq(3)

    expect do
      described_class.send(:recipe_planning_workers_for, {}, {recipe_planning_workers: "-1"})
    end.to raise_error(ArgumentError, /non-negative integer/)
    expect do
      described_class.send(:recipe_planning_workers_for, {"KETTLE_JEM_RACTOR_WORKERS" => "many"}, {})
    end.to raise_error(ArgumentError, /non-negative integer/)
  end


  it "parses thread recipe planning workers from options and env" do
    expect(described_class.send(:recipe_planning_thread_workers_for, {}, {})).to eq(0)
    expect(described_class.send(:recipe_planning_thread_workers_for, {"KETTLE_JEM_THREAD_WORKERS" => "2"}, {})).to eq(2)
    expect(described_class.send(:recipe_planning_thread_workers_for, {"KETTLE_JEM_THREAD_WORKERS" => "2"}, {recipe_planning_thread_workers: "1"})).to eq(1)
    expect(described_class.send(:recipe_planning_thread_workers_for, {}, {thread_workers: "3"})).to eq(3)

    expect do
      described_class.send(:recipe_planning_thread_workers_for, {}, {recipe_planning_thread_workers: "-1"})
    end.to raise_error(ArgumentError, /non-negative integer/)
    expect do
      described_class.send(:recipe_planning_thread_workers_for, {"KETTLE_JEM_THREAD_WORKERS" => "many"}, {})
    end.to raise_error(ArgumentError, /non-negative integer/)
  end


  it "classifies side-effect-free cleanup and template-source recipes as worker-safe" do
    safe_recipe = {
      name: "github_actions_obsolete_workflow_cleanup_old",
      target_path: ".github/workflows/old.yml",
      provider_family: "file",
      primitive: "supplied_obsolete_file_deletion",
      facts: []
    }
    template_recipe = {
      name: "template_source_application_notes_txt",
      target_path: "notes.txt",
      provider_family: "text",
      primitive: "supplied_template_source_application",
      facts: [],
      template_preference: {strategy: "raw_copy", selected_source: "templates/notes.txt.example"}
    }
    readme_recipe = {
      name: "template_source_application_readme",
      target_path: "README.md",
      provider_family: "markdown",
      primitive: "supplied_template_source_application",
      facts: []
    }

    expect(described_class.send(:worker_safe_recipe?, safe_recipe)).to be(true)
    expect(described_class.send(:worker_safe_recipe?, template_recipe)).to be(true)
    expect(described_class.send(:worker_safe_recipe?, readme_recipe)).to be(false)
    expect(described_class.send(:worker_safe_recipe?, template_recipe.merge(target_path: ".github/workflows/ci.yml"))).to be(false)
    expect(described_class.send(:worker_safe_recipe?, template_recipe.merge(target_path: described_class::KETTLE_CONFIG_PATH))).to be(false)
    expect(
      described_class.send(
        :worker_safe_recipe?,
        template_recipe.merge(target_path: "Gemfile", template_preference: {strategy: "accept_template", selected_source: "Gemfile.example"})
      )
    ).to be(false)
  end


  it "keeps classified recipe planning report output equivalent to sequential planning" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-classified-planning", tmp_root) do |root|
      write_tree(root, {
        ".github/workflows/old.yml" => "name: old\n",
        "README.md" => "# Example\n"
      })
      recipes = [
        {
          name: "noop_main_only",
          target_path: "README.md",
          provider_family: "markdown",
          primitive: "noop",
          facts: []
        },
        {
          name: "github_actions_obsolete_workflow_cleanup_old",
          target_path: ".github/workflows/old.yml",
          provider_family: "file",
          primitive: "supplied_obsolete_file_deletion",
          facts: []
        }
      ]
      files = {
        "README.md" => "# Example\n",
        ".github/workflows/old.yml" => "name: old\n"
      }
      policy = described_class::DecisionPolicy.from_env({"force" => "true"})
      common = {
        project_root: root,
        recipes: recipes,
        facts: {},
        files: files,
        template_contents: {},
        decision_policy: policy,
        env: {},
        events: nil
      }

      sequential = described_class.send(:execute_recipe_reports, **common.merge(strategy: "sequential"))
      classified = described_class.send(:execute_recipe_reports, **common.merge(strategy: "classified"))
      normalize = lambda do |reports|
        Marshal.load(Marshal.dump(reports)).each do |report|
          report.dig(:metadata)&.delete(:duration_ms)
          report.dig(:report_envelope, :report, :metadata)&.delete(:duration_ms)
        end
      end

      expect(normalize.call(classified)).to eq(normalize.call(sequential))
      expect(classified.map { |report| report.fetch(:recipe_name) }).to eq(%w[noop_main_only github_actions_obsolete_workflow_cleanup_old])
    end
  end


  it "keeps Ractor-backed classified recipe planning equivalent to main-Ractor classified planning" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ractor-planning", tmp_root) do |root|
      write_tree(root, {
        ".github/workflows/old.yml" => "name: old\n",
        ".github/workflows/stale.yml" => "name: stale\n",
        "templates/notes.txt.example" => "generated notes\n",
        "README.md" => "# Example\n"
      })
      template_path = File.join(root, "templates/notes.txt.example")
      recipes = [
        {
          name: "github_actions_obsolete_workflow_cleanup_old",
          target_path: ".github/workflows/old.yml",
          provider_family: "file",
          primitive: "supplied_obsolete_file_deletion",
          facts: []
        },
        {
          name: "noop_main_only",
          target_path: "README.md",
          provider_family: "markdown",
          primitive: "noop",
          facts: []
        },
        {
          name: "template_source_application_notes_txt",
          target_path: "notes.txt",
          provider_family: "text",
          primitive: "supplied_template_source_application",
          facts: [],
          template_preference: {
            strategy: "raw_copy",
            source_root_path: root,
            source_relative_path: "templates/notes.txt.example",
            selected_source: "templates/notes.txt.example"
          }
        },
        {
          name: "github_actions_obsolete_workflow_cleanup_stale",
          target_path: ".github/workflows/stale.yml",
          provider_family: "file",
          primitive: "supplied_obsolete_file_deletion",
          facts: []
        }
      ]
      files = {
        ".github/workflows/old.yml" => "name: old\n",
        ".github/workflows/stale.yml" => "name: stale\n",
        "notes.txt" => "",
        "README.md" => "# Example\n"
      }
      policy = described_class::DecisionPolicy.from_env({"force" => "true"})
      common = {
        project_root: root,
        recipes: recipes,
        facts: {},
        files: files,
        template_contents: {template_path => "generated notes\n"},
        decision_policy: policy,
        env: {},
        events: nil,
        strategy: "classified"
      }
      normalize = lambda do |reports|
        Marshal.load(Marshal.dump(reports)).each do |report|
          report.dig(:metadata)&.delete(:duration_ms)
          report.dig(:metadata)&.delete(:executor)
          report.dig(:metadata)&.delete(:ractor_id)
          report.dig(:report_envelope, :report, :metadata)&.delete(:duration_ms)
          report.dig(:report_envelope, :report, :metadata)&.delete(:executor)
          report.dig(:report_envelope, :report, :metadata)&.delete(:ractor_id)
        end
      end

      main_ractor = described_class.send(:execute_recipe_reports, **common.merge(workers: 0))
      stats = {}
      workers = described_class.send(:execute_recipe_reports, **common.merge(workers: 2, stats: stats))

      expect(normalize.call(workers)).to eq(normalize.call(main_ractor))
      expect(workers.map { |report| report.fetch(:recipe_name) }).to eq(%w[
        github_actions_obsolete_workflow_cleanup_old
        noop_main_only
        template_source_application_notes_txt
        github_actions_obsolete_workflow_cleanup_stale
      ])
      expect(stats).to include(
        worker_safe_recipes: 3,
        main_only_recipes: 1,
        ractor_worker_count: 2,
        ractor_spawn_count: 2,
        ractor_recipe_count: 3,
        main_recipe_count: 1
      )
      expect(workers.fetch(0).dig(:metadata, :executor)).to eq("ractor")
      expect(workers.fetch(2).dig(:metadata, :executor)).to eq("ractor")
      expect(workers.fetch(3).dig(:metadata, :executor)).to eq("ractor")
      expect(workers.fetch(1).dig(:metadata, :executor)).to be_nil
    end
  end


  it "keeps thread-backed classified recipe planning equivalent to main-Ractor classified planning" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-thread-planning", tmp_root) do |root|
      write_tree(root, {
        ".github/workflows/old.yml" => "name: old\n",
        "README.md" => "# Example\n"
      })
      recipes = [
        {
          name: "github_actions_obsolete_workflow_cleanup_old",
          target_path: ".github/workflows/old.yml",
          provider_family: "file",
          primitive: "supplied_obsolete_file_deletion",
          facts: []
        },
        {
          name: "noop_main_only",
          target_path: "README.md",
          provider_family: "markdown",
          primitive: "noop",
          facts: []
        }
      ]
      files = {
        ".github/workflows/old.yml" => "name: old\n",
        "README.md" => "# Example\n"
      }
      policy = described_class::DecisionPolicy.from_env({"force" => "true"})
      common = {
        project_root: root,
        recipes: recipes,
        facts: {},
        files: files,
        template_contents: {},
        decision_policy: policy,
        env: {},
        events: nil,
        strategy: "classified"
      }
      normalize = lambda do |reports|
        Marshal.load(Marshal.dump(reports)).each do |report|
          report.dig(:metadata)&.delete(:duration_ms)
          report.dig(:metadata)&.delete(:executor)
          report.dig(:metadata)&.delete(:thread_id)
          report.dig(:report_envelope, :report, :metadata)&.delete(:duration_ms)
          report.dig(:report_envelope, :report, :metadata)&.delete(:executor)
          report.dig(:report_envelope, :report, :metadata)&.delete(:thread_id)
        end
      end

      main_thread = described_class.send(:execute_recipe_reports, **common.merge(workers: 0))
      stats = {}
      workers = described_class.send(:execute_recipe_reports, **common.merge(thread_workers: 2, stats: stats))

      expect(normalize.call(workers)).to eq(normalize.call(main_thread))
      expect(stats).to include(
        worker_safe_recipes: 1,
        main_only_recipes: 0,
        thread_worker_count: 2,
        thread_spawn_count: 2,
        thread_recipe_count: 2,
        main_recipe_count: 0
      )
      expect(workers.map { |report| report.dig(:metadata, :executor) }).to eq(%w[thread thread])
    end
  end


  it "turns changed recipe reports into deterministic write intents" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-write-intents", tmp_root) do |root|
      write_report = {
        changed: true,
        relative_path: "lib/example.rb",
        recipe_name: "generated_lib_file",
        final_content: "# generated\n",
        metadata: {destination_existed: false}
      }
      delete_report = {
        changed: true,
        relative_path: ".github/workflows/old.yml",
        recipe_name: "github_actions_obsolete_workflow_cleanup_old",
        metadata: {delete_file: true}
      }
      unchanged_report = write_report.merge(changed: false)

      write_intent = described_class.send(:write_intent_from_recipe_report, root, write_report)
      delete_intent = described_class.send(:write_intent_from_recipe_report, root, delete_report)

      expect(write_intent.action).to eq(:write)
      expect(write_intent.relative_path).to eq("lib/example.rb")
      expect(write_intent.absolute_path).to eq(File.join(root, "lib/example.rb"))
      expect(write_intent.content).to eq("# generated\n")
      expect(write_intent.recipe_name).to eq("generated_lib_file")
      expect(write_intent.metadata).to eq(destination_existed: false)
      expect(delete_intent.action).to eq(:delete)
      expect(delete_intent.content).to be_nil
      expect(described_class.send(:write_intent_from_recipe_report, root, unchanged_report)).to be_nil
    end
  end


  it "parses opt-in Ractor file worker counts" do
    expect(described_class.send(:file_work_workers_for, {}, {})).to eq(0)
    expect(described_class.send(:file_work_workers_for, {"KETTLE_JEM_RACTOR_FILE_WORKERS" => "3"}, {})).to eq(3)
    expect(described_class.send(:file_work_workers_for, {}, {file_work_workers: 2})).to eq(2)

    expect do
      described_class.send(:file_work_workers_for, {"KETTLE_JEM_RACTOR_FILE_WORKERS" => "-1"}, {})
    end.to raise_error(ArgumentError, /non-negative integer/)
  end


  it "parses opt-in thread file worker counts" do
    expect(described_class.send(:file_work_thread_workers_for, {}, {})).to eq(0)
    expect(described_class.send(:file_work_thread_workers_for, {"KETTLE_JEM_THREAD_FILE_WORKERS" => "3"}, {})).to eq(3)
    expect(described_class.send(:file_work_thread_workers_for, {}, {file_work_thread_workers: 2})).to eq(2)

    expect do
      described_class.send(:file_work_thread_workers_for, {"KETTLE_JEM_THREAD_FILE_WORKERS" => "-1"}, {})
    end.to raise_error(ArgumentError, /non-negative integer/)
  end


  it "reduces phase write intents into per-file work units" do
    first_write = described_class::WriteIntent.new(
      relative_path: "lib/example.rb",
      absolute_path: "/project/lib/example.rb",
      action: :write,
      content: "first\n",
      recipe_name: "first_recipe"
    )
    final_delete = described_class::WriteIntent.new(
      relative_path: "lib/example.rb",
      absolute_path: "/project/lib/example.rb",
      action: :delete,
      recipe_name: "cleanup_recipe"
    )
    other_write = described_class::WriteIntent.new(
      relative_path: "README.md",
      absolute_path: "/project/README.md",
      action: :write,
      content: "# README\n",
      recipe_name: "readme_recipe"
    )

    work_units = described_class.send(:file_work_units_from_write_intents, [first_write, other_write, final_delete])

    expect(work_units.map(&:relative_path)).to eq(["lib/example.rb", "README.md"])
    expect(work_units.fetch(0).operations).to eq([first_write, final_delete])
    expect(work_units.fetch(0).outcome).to eq(final_delete)
    expect(work_units.fetch(1).operations).to eq([other_write])
    expect(work_units.fetch(1).outcome).to eq(other_write)
  end


  it "rejects file work units that mix relative paths" do
    write_intent = described_class::WriteIntent.new(
      relative_path: "lib/example.rb",
      absolute_path: "/project/lib/example.rb",
      action: :write,
      content: "# generated\n",
      recipe_name: "generated_lib_file"
    )

    expect do
      described_class::FileWorkUnit.new(relative_path: "README.md", operations: [write_intent])
    end.to raise_error(ArgumentError, /cannot include operations/)
  end


  it "lets one file worker own ordered operations for a path" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-file-work-unit", tmp_root) do |root|
      file_path = File.join(root, "lib/example.rb")
      first_write = described_class::WriteIntent.new(
        relative_path: "lib/example.rb",
        absolute_path: file_path,
        action: :write,
        content: "first\n",
        recipe_name: "first_recipe"
      )
      final_write = described_class::WriteIntent.new(
        relative_path: "lib/example.rb",
        absolute_path: file_path,
        action: :write,
        content: "final\n",
        recipe_name: "final_recipe"
      )
      work_unit = described_class::FileWorkUnit.new(
        relative_path: "lib/example.rb",
        operations: [first_write, final_write]
      )

      described_class.send(:commit_file_work_unit, work_unit)

      expect(File.read(file_path)).to eq("final\n")
    end
  end


  it "can commit independent file work units through Ractors within a phase" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ractor-file-work-units", tmp_root) do |root|
      first_path = File.join(root, "lib/first.rb")
      second_path = File.join(root, "lib/second.rb")
      FileUtils.mkdir_p(File.dirname(second_path))
      File.write(second_path, "old\n")
      first_work_unit = described_class::FileWorkUnit.new(
        relative_path: "lib/first.rb",
        operations: [
          described_class::WriteIntent.new(
            relative_path: "lib/first.rb",
            absolute_path: first_path,
            action: :write,
            content: "first\n",
            recipe_name: "first_recipe"
          )
        ]
      )
      second_work_unit = described_class::FileWorkUnit.new(
        relative_path: "lib/second.rb",
        operations: [
          described_class::WriteIntent.new(
            relative_path: "lib/second.rb",
            absolute_path: second_path,
            action: :write,
            content: "new\n",
            recipe_name: "second_recipe"
          ),
          described_class::WriteIntent.new(
            relative_path: "lib/second.rb",
            absolute_path: second_path,
            action: :delete,
            recipe_name: "cleanup_recipe"
          )
        ]
      )

      stats = described_class.send(:file_work_execution_stats, 2)

      described_class.send(:commit_file_work_units, [first_work_unit, second_work_unit], workers: 2, stats: stats)

      expect(File.read(first_path)).to eq("first\n")
      expect(File).not_to exist(second_path)
      expect(stats).to include(
        file_worker_count: 2,
        file_work_units: 2,
        file_operations: 3,
        file_ractor_units: 2,
        file_ractor_spawn_count: 2,
        main_file_units: 0
      )
    end
  end


  it "can commit independent file work units through threads within a phase" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-thread-file-work-units", tmp_root) do |root|
      first_path = File.join(root, "lib/first.rb")
      second_path = File.join(root, "lib/second.rb")
      first_work_unit = described_class::FileWorkUnit.new(
        relative_path: "lib/first.rb",
        operations: [
          described_class::WriteIntent.new(
            relative_path: "lib/first.rb",
            absolute_path: first_path,
            action: :write,
            content: "first\n",
            recipe_name: "first_recipe"
          )
        ]
      )
      second_work_unit = described_class::FileWorkUnit.new(
        relative_path: "lib/second.rb",
        operations: [
          described_class::WriteIntent.new(
            relative_path: "lib/second.rb",
            absolute_path: second_path,
            action: :write,
            content: "second\n",
            recipe_name: "second_recipe"
          )
        ]
      )
      stats = described_class.send(:file_work_execution_stats, 0, 2)

      described_class.send(:commit_file_work_units, [first_work_unit, second_work_unit], thread_workers: 2, stats: stats)

      expect(File.read(first_path)).to eq("first\n")
      expect(File.read(second_path)).to eq("second\n")
      expect(stats).to include(
        file_thread_worker_count: 2,
        file_work_units: 2,
        file_operations: 2,
        file_thread_units: 2,
        file_thread_spawn_count: 2,
        main_file_units: 0
      )
    end
  end


  it "commits file outcomes while preserving current apply behavior" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-file-outcome-commit", tmp_root) do |root|
      FileUtils.mkdir_p(File.join(root, "obsolete"))
      File.write(File.join(root, "obsolete/file.txt"), "old\n")
      write_intent = described_class::WriteIntent.new(
        relative_path: "lib/example.rb",
        absolute_path: File.join(root, "lib/example.rb"),
        action: :write,
        content: "# generated\n",
        recipe_name: "generated_lib_file"
      )
      delete_intent = described_class::WriteIntent.new(
        relative_path: "obsolete/file.txt",
        absolute_path: File.join(root, "obsolete/file.txt"),
        action: :delete,
        recipe_name: "obsolete_file_cleanup"
      )

      described_class.send(:commit_file_outcome, write_intent)
      described_class.send(:commit_file_outcome, delete_intent)

      expect(File.read(File.join(root, "lib/example.rb"))).to eq("# generated\n")
      expect(File).not_to exist(File.join(root, "obsolete/file.txt"))
    end
  end


  it "normalizes GitHub remote source URLs structurally" do
    expect(described_class.normalize_git_source_url("git@github.com:rubythems/them-server.git")).to eq(
      "https://github.com/rubythems/them-server"
    )
    expect(described_class.normalize_git_source_url("https://github.com/rubythems/them-server.git")).to eq(
      "https://github.com/rubythems/them-server"
    )
    expect(described_class.normalize_git_source_url("https://gitlab.com/rubythems/them-server.git")).to eq(
      "https://gitlab.com/rubythems/them-server.git"
    )
  end

end
