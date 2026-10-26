# frozen_string_literal: true

RSpec.describe Kettle::Jem, "Duel performance regression guards" do
  include_context "with isolated kettle-jem environment"

  let(:duel_paths) { %w[.duel.rb .github/workflows/perf.yml gemfiles/modular/duel.gemfile] }
  let(:shared_paths) { %w[Appraisals Gemfile Rakefile .rubocop.yml README.md] }

  def duel_project(root, duel: nil, files: {})
    workflows = duel.nil? ? "" : "workflows:\n  duel: #{duel}\n"
    entries = (duel_paths + shared_paths).map { |path| "    - #{path}\n" }.join
    write_tree(root, {
      "example.gemspec" => <<~RUBY,
        Gem::Specification.new do |spec|
          spec.name = "example"
          spec.version = "1.0.0"
          spec.summary = "Example gem"
          spec.authors = ["Example Maintainer"]
          spec.email = ["maintainer@example.com"]
          spec.homepage = "https://github.com/example/example"
          spec.licenses = ["MIT"]
          spec.required_ruby_version = ">= 2.3"
        end
      RUBY
      ".kettle-jem.yml" => "#{workflows}templates:\n  root: packaged\n  apply: true\n  entries:\n#{entries}"
    }.merge(files))
  end

  def report_for(result, path)
    result.fetch(:recipe_reports).find do |report|
      report.fetch(:relative_path) == path && report.fetch(:recipe_name).start_with?("template_source_application_")
    end
  end

  def with_project(name)
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-duel-#{name}", tmp_root) { |root| yield root }
  end

  it "generates nothing for Duel while workflows.duel is absent" do
    with_project("absent") do |root|
      duel_project(root)

      plan = described_class.plan_project(root, env: {})
      described_class.apply_project(root, env: {})

      expect(plan.fetch(:facts).fetch(:ci)).not_to have_key(:duel)
      duel_paths.each do |path|
        expect(report_for(plan, path)).to be_nil, path
        expect(File).not_to exist(File.join(root, path)), path
      end
      expect(File.read(File.join(root, "Gemfile"))).not_to include("duel")
      expect(File.read(File.join(root, "Appraisals"))).not_to include('appraise "perf"')
      expect(File.read(File.join(root, "Rakefile"))).not_to include("duel")
      expect(File.read(File.join(root, ".rubocop.yml"))).not_to include(".duel.rb")
      expect(File.read(File.join(root, "README.md"))).not_to include("duel")
    end
  end

  it "renders the shared files identically whether workflows.duel is absent or false" do
    outputs = %w[absent false].to_h do |setting|
      with_project("output-#{setting}") do |root|
        duel_project(root, duel: (setting == "false") ? false : nil)
        described_class.apply_project(root, env: {})
        [setting, project_files(root, shared_paths)]
      end
    end

    expect(outputs.fetch("false")).to eq(outputs.fetch("absent"))
  end

  it "leaves a project's own Duel files alone while workflows.duel is false" do
    own = {
      ".duel.rb" => "# frozen_string_literal: true\n\nDuel.configure { |c| c.watch = %w[lib] }\n",
      ".github/workflows/perf.yml" => "name: Perf\n\npermissions:\n  contents: read\n\non:\n  push:\n    branches: [main]\n\nconcurrency:\n  group: perf\n  cancel-in-progress: true\n\njobs:\n  duel:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo own\n",
      "gemfiles/modular/duel.gemfile" => "# frozen_string_literal: true\n\ngem \"duel\"\n"
    }
    with_project("own-off") do |root|
      duel_project(root, duel: false, files: own)

      plan = described_class.plan_project(root, env: {})
      apply = described_class.apply_project(root, env: {})

      expect(plan.dig(:facts, :ci, :custom_workflows)).to include(".github/workflows/perf.yml")
      expect(plan.dig(:facts, :ci, :inactive_packaged_workflow_cleanups).to_a).not_to include(".github/workflows/perf.yml")
      expect(plan.dig(:facts, :templates, :inactive_packaged_template_cleanups).to_a).not_to include(target_path: "gemfiles/modular/duel.gemfile")
      duel_paths.each { |path| expect(report_for(plan, path)).to be_nil, path }
      expect(apply.fetch(:changed_files)).not_to include(*duel_paths)
      expect(project_files(root, own.keys)).to eq(own.transform_keys(&:to_sym))
    end
  end

  it "generates the Perf workflow, modular Gemfile, appraisal, Rake task, RuboCop include, and badge when workflows.duel is true" do
    with_project("on") do |root|
      duel_project(root, duel: true)

      plan = described_class.plan_project(root, env: {})
      described_class.apply_project(root, env: {})
      files = project_files(root, duel_paths + shared_paths)

      expect(plan.dig(:facts, :ci, :duel)).to be(true)
      expect(plan.dig(:facts, :ci, :custom_workflows)).not_to include(".github/workflows/perf.yml")

      workflow = files.fetch(:".github/workflows/perf.yml")
      expect(workflow).to eq(File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, ".github/workflows/perf.yml.example")))
      workflow_yaml = YAML.safe_load(workflow)
      expect(workflow_yaml.fetch("permissions")).to eq("contents" => "read")
      expect(workflow_yaml.dig("jobs", "duel", "env", "BUNDLE_GEMFILE")).to eq("${{ github.workspace }}/gemfiles/perf.gemfile")
      expect(workflow_yaml.dig("jobs", "duel")).not_to have_key("permissions")
      expect(workflow_yaml.dig("jobs", "comment", "permissions")).to eq("pull-requests" => "write")
      expect(workflow_yaml.dig("jobs", "comment", "steps").map { |step| step["uses"] }.compact).to all(start_with("actions/download-artifact@"))
      checkout = workflow_yaml.dig("jobs", "duel", "steps").find { |step| step["uses"].to_s.start_with?("actions/checkout@") }
      expect(checkout.fetch("with")).to include("fetch-depth" => 0, "persist-credentials" => false)
      baseline_ruby = workflow_yaml.dig("jobs", "duel", "steps").find { |step| step["id"] == "baseline-ruby" }
      expect(baseline_ruby.fetch("with")).to include("bundler-cache" => true)
      compare = workflow_yaml.dig("jobs", "duel", "steps").find { |step| step["name"] == "Compare" }
      expect(compare.fetch("id")).to eq("compare")
      expect(workflow_yaml.dig("jobs", "duel", "outputs")).to eq(
        "comment" => "${{ steps.compare.outputs.comment }}",
        "status" => "${{ steps.compare.outputs.status }}"
      )
      expect(workflow_yaml.dig("jobs", "comment", "if")).to end_with(" && (needs.duel.outputs.comment == 'post' || needs.duel.outputs.comment == 'change') }}")
      comment_step = workflow_yaml.dig("jobs", "comment", "steps").find { |step| step["name"] == "Comment on the pull request" }
      expect(comment_step.fetch("env")).to include("COMMENT" => "${{ needs.duel.outputs.comment }}", "STATUS" => "${{ needs.duel.outputs.status }}")
      expect(comment_step.fetch("run")).to include(%(marker="<!-- duel"\n), %(echo "$marker status=$STATUS -->"), "--method POST")
      expect(workflow).not_to include("PATCH")
      %w[actions/checkout ruby/setup-ruby actions/upload-artifact actions/download-artifact].each do |action|
        expect_pinned_action(workflow, action)
      end

      expect(files.fetch(:"gemfiles/modular/duel.gemfile")).to include(%(if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4")))
      expect_gem_dependency_declared(files.fetch(:"gemfiles/modular/duel.gemfile"), "duel")
      expect(files.fetch(:"gemfiles/modular/duel.gemfile")).to include(%(gem "duel", "~> 0.1", ">= 0.1.1"))
      expect_gem_dependency_declared(files.fetch(:"gemfiles/modular/duel.gemfile"), "stackprof")
      expect(files.fetch(:".duel.rb")).to include("c.ruby = :version_file", "c.watch += %w[.github/workflows/perf.yml]\n", "# c.comment = :failures\n")
      expect(files.fetch(:Gemfile).scan(%(eval_gemfile "gemfiles/modular/duel.gemfile")).size).to eq(1)
      expect(files.fetch(:Gemfile).index("gemfiles/modular/duel.gemfile")).to be < files.fetch(:Gemfile).index("gemfiles/modular/x_std_libs.gemfile")
      expect(appraisals_eval_gemfile_paths(files.fetch(:Appraisals), "perf")).to eq(%w[modular/duel.gemfile modular/x_std_libs.gemfile])
      expect(files.fetch(:Rakefile)).to include(%(require "duel/rake_task"\n  Duel::RakeTask.new\nrescue LoadError))
      expect(files.fetch(:Rakefile).index("### PERFORMANCE TASKS")).to be < files.fetch(:Rakefile).index("### RELEASE TASKS")
      rubocop = YAML.safe_load(files.fetch(:".rubocop.yml"))
      expect(rubocop.dig("inherit_mode", "merge")).to include("Exclude", "Include")
      expect(rubocop.dig("AllCops", "Include")).to eq([".duel.rb"])
      expect(files.fetch(:"README.md").lines.find { |line| line.start_with?("[![Version]") }.rstrip).to end_with(described_class::README_DUEL_BADGE)
      expect(files.fetch(:"README.md")).to include("[⚔️duel]: https://github.com/sferik/duel-ruby\n")
      expect(files.fetch(:"README.md")).to include("[⚔️duel-img]: https://raw.githubusercontent.com/sferik/duel-ruby/main/assets/badge.svg\n")

      # (A second run appends README metadata whether or not Duel is on, so
      # the README is checked for its badge only.)
      stable_paths = duel_paths + shared_paths - ["README.md"]
      second = described_class.apply_project(root, env: {})
      readme = File.read(File.join(root, "README.md"))
      expect(second.fetch(:changed_files) & stable_paths).to be_empty
      expect(project_files(root, stable_paths)).to eq(files.slice(*stable_paths.map(&:to_sym)))
      expect(readme.scan(described_class::README_DUEL_BADGE).size).to eq(1)
      expect(readme.scan("[⚔️duel]: ").size).to eq(1)
    end
  end

  it "keeps a project's own .duel.rb and perf appraisal when workflows.duel is true" do
    own_config = "# frozen_string_literal: true\n\nDuel.configure { |c| c.library = \"example\" }\n"
    own_appraisals = <<~RUBY
      # frozen_string_literal: true

      appraise "perf" do
        eval_gemfile "modular/duel.gemfile"
        eval_gemfile "modular/redis.gemfile"
        eval_gemfile "modular/x_std_libs.gemfile"
      end
    RUBY
    with_project("own-on") do |root|
      duel_project(root, duel: true, files: {".duel.rb" => own_config, "Appraisals" => own_appraisals})

      plan = described_class.plan_project(root, env: {})
      described_class.apply_project(root, env: {})
      appraisals = File.read(File.join(root, "Appraisals"))

      expect(report_for(plan, ".duel.rb").dig(:metadata, :template_source_preference)).to include(strategy: "keep_destination", policy: "copy_only_when_missing")
      expect(File.read(File.join(root, ".duel.rb"))).to eq(own_config)
      expect(appraisals.scan('appraise "perf"').size).to eq(1)
      expect(appraisals_eval_gemfile_paths(appraisals, "perf")).to include("modular/redis.gemfile")
    end
  end

  it "leaves Appraisal.root.gemfile without a perf appraisal" do
    template = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, "Appraisal.root.gemfile.example"))
    facts = {ci: {duel: true}}

    content = described_class.merge_appraisals_template_policy(template, facts: facts, target_path: "Appraisal.root.gemfile")
    appraisals = described_class.merge_appraisals_template_policy(%(appraise "current" do\nend\n), facts: facts, target_path: "Appraisals")

    expect(content).not_to include('appraise "perf"')
    expect(appraisals).to include('appraise "perf"')
  end

  it "uses Duel only with the full template profile" do
    config = {"workflows" => {"duel" => true}}

    expect(described_class.template_runtime_config(config, {template_profile: ""}).fetch("resolved_duel")).to be(true)
    expect(described_class.template_runtime_config(config, {template_profile: "full"}).fetch("resolved_duel")).to be(true)
    %w[monorepo-root monorepo-subgem-package monorepo-subgem-release monorepo-subgem-full].each do |profile|
      expect(described_class.template_runtime_config(config, {template_profile: profile})).not_to have_key("resolved_duel"), profile
    end
    expect(described_class.duel_template_profile?("shim")).to be(false)
    expect(described_class.template_runtime_config({"workflows" => {"duel" => "false"}}, {})).not_to have_key("resolved_duel")
  end

  it "replays the Duel changelog entry only for a project with workflows.duel true" do
    entry = described_class.changelog_transfer_entries(described_class::PACKAGED_TEMPLATE_ROOT).find do |candidate|
      candidate.fetch(:key) == "kettle-jem-template-20261025-001"
    end

    contexts = [nil, false, true].to_h do |setting|
      with_project("transfer-#{setting.inspect}") do |root|
        duel_project(root, duel: setting)
        [setting, described_class.transfer_changelog_context(root)]
      end
    end

    expect(contexts.transform_values { |context| context.fetch("workflow.duel") }).to eq(nil => false, false => false, true => true)
    expect(described_class.transfer_changelog_entry_applies?(entry, contexts.fetch(true))).to be(true)
    expect(described_class.transfer_changelog_entry_applies?(entry, contexts.fetch(false))).to be(false)
  end

  it "pins every action in the Perf workflow through the template pin table" do
    workflow = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, ".github/workflows/perf.yml.example"))
    pins = described_class.github_actions_step_pins.values
    used = workflow.scan(/^\s+uses: (\S+@[0-9a-f]{40} # \S+)$/).flatten

    expect(used).not_to be_empty
    expect(used - pins).to be_empty
  end

  describe "the RuboCop include for .duel.rb" do
    it "adds the parent mapping and the key when they are missing" do
      content = described_class.ensure_rubocop_duel_config("plugins:\n  - rubocop-rspec\n")

      expect(YAML.safe_load(content)).to include(
        "inherit_mode" => {"merge" => ["Include"]},
        "AllCops" => {"Include" => [".duel.rb"]}
      )
    end

    it "adds nothing that is already there" do
      content = <<~YAML
        inherit_mode:
          merge:
            - Exclude
            - Include

        AllCops:
          Include:
            - '.duel.rb'
      YAML

      expect(described_class.ensure_rubocop_duel_config(content)).to eq(content)
    end

    it "leaves flow sequences alone" do
      content = "inherit_mode:\n  merge: [Exclude]\n\nAllCops:\n  Include: ['**/*.rb']\n"

      expect(described_class.ensure_rubocop_duel_config(content)).to eq(content)
    end
  end
end
