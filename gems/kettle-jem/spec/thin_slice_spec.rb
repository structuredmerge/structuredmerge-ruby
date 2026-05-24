# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Kettle::Jem do
  def json_ready(value)
    JSON.parse(JSON.generate(value), symbolize_names: true)
  end

  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path.to_s)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def project_files(root, paths)
    paths.to_h do |relative_path|
      path = File.join(root, relative_path)
      [relative_path.to_sym, File.exist?(path) ? File.read(path) : nil]
    end
  end

  let(:fixture_path) { Pathname(__dir__).join("fixtures/thin_slice.json") }
  let(:fixture) { JSON.parse(fixture_path.read, symbolize_names: true) }
  let(:contract_path) do
    Pathname(__dir__).join("../../../../fixtures/packaging/thin-slice-contract.json").expand_path
  end
  let(:contract) { JSON.parse(contract_path.read, symbolize_names: true) }
  let(:bootstrap_contract_path) { Pathname(__dir__).join("fixtures/bootstrap_contract.json").expand_path }
  let(:bootstrap_contract) { JSON.parse(bootstrap_contract_path.read, symbolize_names: true) }
  let(:old_spec_contract_path) { Pathname(__dir__).join("fixtures/old_spec_migration_contract.json").expand_path }
  let(:old_spec_contract) { JSON.parse(old_spec_contract_path.read, symbolize_names: true) }

  it "plans and applies the RubyGems thin vertical slice" do
    expected_recipe_names = contract.fetch(:canonical_recipes).map { |recipe| recipe.fetch(:name).to_s }
    expect(contract.fetch(:validated_ecosystems)).to include(fixture.fetch(:ecosystem))
    expect(fixture.fetch(:expected).fetch(:facts).keys).to include(
      *contract.fetch(:required_fact_groups).map(&:to_sym),
      contract.fetch(:ecosystem_fact_groups).fetch(:rubygems).to_sym
    )

    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-thin-slice", tmp_root) do |root|
      write_tree(root, fixture.fetch(:inputs).fetch(:files))

      plan = described_class.plan_project(root, env: {})
      expect(json_ready(plan[:facts])).to eq(json_ready(fixture.fetch(:expected).fetch(:facts)))
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe[:name] }
      expect(recipe_names.take(expected_recipe_names.length)).to eq(expected_recipe_names)
      expect(recipe_names).to include("github_funding_yml")
      expect(recipe_names).not_to include("github_actions_ci")
      expect(recipe_names).not_to include("github_actions_framework_ci")
      expect(recipe_names).to include(a_string_starting_with("github_actions_obsolete_workflow_cleanup_"))
      expect(recipe_names).to include("rakefile_scaffold_cleanup")
      expect(recipe_names).to include(a_string_starting_with("github_actions_workflow_snippets_"))
      expect(plan[:changed_files]).to eq(fixture.fetch(:expected).fetch(:changed_files))
      expect(plan[:recipe_reports].map { |report| report[:request_envelope][:kind] }.uniq).to eq(
        [contract.fetch(:report_contract).fetch(:request_envelope_kind)]
      )
      expect(plan[:recipe_reports].map { |report| report[:report_envelope][:kind] }.uniq).to eq(
        [contract.fetch(:report_contract).fetch(:report_envelope_kind)]
      )
      rakefile_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "rakefile_scaffold_cleanup" }
      expect(rakefile_report.dig(:request_envelope, :request, :runtime_context, :delete_selectors).length).to eq(4)
      expect(rakefile_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :deleted_ranges)).to eq(4)
      expect(rakefile_report.fetch(:final_content)).to include("task :custom")
      expect(rakefile_report.fetch(:final_content)).not_to include("bundler/gem_tasks")
      expect(rakefile_report.fetch(:final_content)).not_to include("RSpec::Core::RakeTask")
      funding_yml_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_funding_yml" }
      expect(funding_yml_report.fetch(:final_content)).to include("tidelift: rubygems/example")
      expect(funding_yml_report.fetch(:final_content)).to include("open_collective: example")
      custom_ci_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == ".github/workflows/custom-ci.yml"
      end
      expect(custom_ci_report.fetch(:final_content)).to include("permissions:")
      expect(custom_ci_report.fetch(:final_content)).to include("concurrency:")
      expect(custom_ci_report.fetch(:final_content)).to include("actions/checkout@de0fac2")
      expect(custom_ci_report.fetch(:final_content)).to include("ruby/setup-ruby@afeafc")
      expect(custom_ci_report.fetch(:final_content)).to include("Upload coverage to Coveralls")
      expect(custom_ci_report.fetch(:final_content)).to include("qltysh/qlty-action/coverage@a192421")
      expect(custom_ci_report.fetch(:final_content)).to include("Code Coverage Summary Report")
      expect(custom_ci_report.fetch(:final_content)).to include("ruby: [\"3.2\", \"3.3\"]")
      obsolete_workflow_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == ".github/workflows/ancient.yml"
      end
      expect(obsolete_workflow_report.fetch(:metadata).fetch(:delete_file)).to be(true)
      expect(obsolete_workflow_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :deleted_file)).to eq(
        ".github/workflows/ancient.yml"
      )

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to eq(fixture.fetch(:expected).fetch(:changed_files))
      expect(project_files(root, fixture.fetch(:expected).fetch(:files).keys.map(&:to_s))).to eq(fixture.fetch(:expected).fetch(:files))
    end
  end

  it "does not synthesize a standalone coverage workflow outside the packaged template inventory" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-coverage-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            coverage:
              enabled: true
              appraisal: coverage
              command: rake test
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      recipe_names = plan[:recipe_reports].map { |report| report.fetch(:recipe_name) }
      expect(recipe_names).not_to include("github_actions_coverage_ci")
      expect(plan[:changed_files]).not_to include(".github/workflows/coverage.yml")
    end
  end

  it "projects configured workflow exec_cmd into GitHub workflow templates" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-exec-cmd-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            exec_cmd: rake spec
          templates:
            root: template
            apply: true
            entries:
              - .github/workflows/current.yml
        YAML
        "template/.github/workflows/current.yml.example" => <<~YAML,
          name: Current
          jobs:
            test:
              strategy:
                matrix:
                  include:
                    - ruby: "3.2"
                      exec_cmd: "{KJ|CI:EXEC_CMD}"
              steps:
                - run: bundle exec ${{ matrix.exec_cmd }}
        YAML
      })

      apply = described_class.apply_project(root, env: { "KJ_EXEC_CMD" => "kettle-test" })
      workflow_report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/current.yml"
      end

      expect(workflow_report.fetch(:final_content)).to include('exec_cmd: "kettle-test"')
    end
  end

  it "fails closed for GitHub YAML template merges when the YAML provider reports a ProcessResult adapter failure" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-github-yaml-provider-regression", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project: destination
          templates:
            root: template
            apply: true
            entries:
              - .github/FUNDING.yml
              - .kettle-jem.yml
        YAML
        ".github/FUNDING.yml" => <<~YAML,
          github: [destination]
          custom:
            - https://destination.example/fund
        YAML
        "template/.github/FUNDING.yml.example" => <<~YAML,
          github: [template]
          tidelift: rubygems/example
        YAML
        "template/.kettle-jem.yml.example" => <<~YAML,
          project: template
          generated: true
        YAML
      })
      allow(Psych::Merge).to receive(:merge_yaml).and_return(
        ok: false,
        diagnostics: [{
          severity: "error",
          category: "unsupported_feature",
          message: "undefined method '[]' for an instance of TreeSitterLanguagePack::ProcessResult",
        }],
        policies: []
      )

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /failed to merge yaml template \.github\/FUNDING\.yml: provider adapter failure/)
    end
  end

  it "falls back for Gemfile template merges when the Ruby provider reports a ProcessResult adapter failure" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-provider-regression", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
          files:
            Gemfile:
              strategy: accept_template
        YAML
        "Gemfile" => <<~RUBY,
          source "https://rubygems.org"
          gem "example", path: "."
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          source "https://gem.coop"
          gemspec
          gem "appraisal"
          gem "rake"
          gem "example", path: "."
        RUBY
      })
      allow(Ruby::Merge).to receive(:merge_ruby).and_return(
        ok: false,
        diagnostics: [{
          severity: "error",
          category: "unsupported_feature",
          message: "undefined method '[]' for an instance of TreeSitterLanguagePack::ProcessResult",
        }],
        policies: []
      )

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_Gemfile"
      end

      expect(report.fetch(:final_content)).to include('source "https://gem.coop"')
      expect(report.fetch(:final_content)).to include("gemspec")
      expect(report.fetch(:final_content)).to include('gem "rake"')
      expect(report.fetch(:final_content)).not_to include('gem "appraisal"')
      expect(report.fetch(:final_content)).not_to include('gem "example"')
    end
  end

  it "merges custom workflow YAML snippets without replacing destination jobs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-custom-workflow-yaml-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".github/workflows/custom-ci.yml" => <<~YAML,
          name: Custom CI
          on:
            pull_request:
          jobs:
            spec:
              runs-on: ubuntu-latest
              steps:
                - uses: actions/checkout@v4
                - uses: ruby/setup-ruby@v1
                - uses: actions/upload-artifact@v4
                - uses: codecov/codecov-action@v6
                - uses: coverallsapp/github-action@main
                - uses: actions/dependency-review-action@v4
                - uses: github/codeql-action/init@v4
                - uses: github/codeql-action/autobuild@v4
                - uses: github/codeql-action/analyze@v4
                - uses: pozil/auto-assign-issue@v2
                - uses: apache/skywalking-eyes/dependency@v0.8.0
                - uses: kettle-rb/ts-grammar-action@v1
                - uses: sarisia/actions-status-discord@v1
                - name: Project-specific check
                  run: bundle exec rake custom
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/custom-ci.yml"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:recipe_name)).to start_with("github_actions_workflow_snippets_")
      expect(content).to include("permissions:\n  contents: read")
      expect(content).to include("concurrency:\n  group: \"${{ github.workflow }}-${{ github.ref }}\"")
      expect(content).to include("actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2")
      expect(content).to include("ruby/setup-ruby@afeafc3d1ab54a631816aba4c914a0081c12ff2f # v1.310.0")
      expect(content).to include("actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1")
      expect(content).to include("codecov/codecov-action@e79a6962e0d4c0c17b229090214935d2e33f8354 # v6.0.1")
      expect(content).to include("coverallsapp/github-action@5cbfd81b66ca5d10c19b062c04de0199c215fb6e # v2.3.7")
      expect(content).to include("actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294 # v5.0.0")
      expect(content).to include("github/codeql-action/init@7211b7c8077ea37d8641b6271f6a365a22a5fbfa # v4.36.0")
      expect(content).to include("github/codeql-action/autobuild@7211b7c8077ea37d8641b6271f6a365a22a5fbfa # v4.36.0")
      expect(content).to include("github/codeql-action/analyze@7211b7c8077ea37d8641b6271f6a365a22a5fbfa # v4.36.0")
      expect(content).to include("pozil/auto-assign-issue@70adb98ca8b3941524e9ecde48e89067c4f96736 # v3.0.0")
      expect(content).to include("apache/skywalking-eyes/dependency@61275cc80d0798a405cb070f7d3a8aaf7cf2c2c1 # v0.8.0")
      expect(content).to include("kettle-rb/ts-grammar-action@4b0c04d11ed5b85c67c0c60c6ecb590e81748ccb # v1.0.1")
      expect(content).to include("sarisia/actions-status-discord@eb045afee445dc055c18d3d90bd0f244fd062708 # v1.16.0")
      expect(content).to include("Project-specific check")
      expect(content).to include("bundle exec rake custom")
    end
  end

  it "normalizes GitHub Action refs when merging packaged workflow templates" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-workflow-action-pin-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.3.yml
        YAML
        ".github/workflows/ruby-2.3.yml" => <<~YAML,
          name: Ruby 2.3
          jobs:
            test:
              runs-on: ubuntu-22.04
              steps:
                - name: Checkout
                  uses: actions/checkout@v6
                - name: Setup Ruby & RubyGems
                  uses: ruby/setup-ruby@v1
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/ruby-2.3.yml"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:recipe_name)).to start_with("template_source_application_")
      expect(content).to include("actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2")
      expect(content).to include("ruby/setup-ruby@afeafc3d1ab54a631816aba4c914a0081c12ff2f # v1.310.0")
      expect(content).not_to include("actions/checkout@v6")
      expect(content).not_to include("ruby/setup-ruby@v1")
    end
  end

  it "deletes skipped packaged workflows that already exist" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-skipped-workflow-action-pin-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.4"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.3.yml
        YAML
        ".github/workflows/ruby-2.3.yml" => <<~YAML,
          name: Ruby 2.3
          jobs:
            test:
              runs-on: ubuntu-22.04
              steps:
                - uses: actions/checkout@v6
                - uses: ruby/setup-ruby@v1
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/ruby-2.3.yml"
      end

      expect(report.fetch(:recipe_name)).to start_with("github_actions_inactive_packaged_workflow_cleanup_")
      expect(report.fetch(:metadata)).to include(delete_file: true)
    end
  end

  it "keeps the packaged Discord notifier workflow opt-in via include" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-discord-workflow-opt-in-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/discord-notifier.yml
        YAML
        ".github/workflows/discord-notifier.yml" => "name: stale notifier\n",
      })

      default_plan = described_class.plan_project(root, env: {})
      default_report = default_plan.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == ".github/workflows/discord-notifier.yml"
      end
      expect(default_report.fetch(:recipe_name)).to start_with("github_actions_opt_in_workflow_cleanup_")
      expect(default_report.fetch(:metadata)).to include(delete_file: true)
      expect(default_plan.fetch(:changed_files)).to include(".github/workflows/discord-notifier.yml")

      included_plan = described_class.plan_project(
        root,
        env: {},
        run_options: { include: ".github/workflows/discord-notifier.yml" }
      )
      expect(included_plan.fetch(:changed_files)).to include(".github/workflows/discord-notifier.yml")
      included_report = included_plan.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == ".github/workflows/discord-notifier.yml"
      end
      expect(included_report.fetch(:recipe_name)).to start_with("template_source_application_")
      expect(included_report.fetch(:metadata)).not_to include(delete_file: true)
    end
  end

  it "generates packaged framework workflow matrices only when configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-framework-workflow-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/framework-ci.yml
        YAML
        ".github/workflows/framework-ci.yml" => "name: stale framework\n",
      })

      unconfigured_plan = described_class.plan_project(root, env: {})
      unconfigured_report = unconfigured_plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/framework-ci.yml"
      end
      expect(unconfigured_plan.fetch(:changed_files)).to include(".github/workflows/framework-ci.yml")
      expect(unconfigured_report.fetch(:recipe_name)).to start_with("github_actions_inactive_packaged_workflow_cleanup_")
      expect(unconfigured_report.fetch(:metadata)).to include(delete_file: true)

      FileUtils.rm_f(File.join(root, ".github/workflows/framework-ci.yml"))
      missing_unconfigured_plan = described_class.plan_project(root, env: {})
      expect(missing_unconfigured_plan.fetch(:changed_files)).not_to include(".github/workflows/framework-ci.yml")

      File.write(File.join(root, ".kettle-jem.yml"), <<~YAML)
        workflows:
          preset: framework
          framework_matrix:
            dimension: rails
            versions:
              - "7.0"
              - "7.1"
            gemfile_pattern: rails_{version}
        templates:
          root: packaged
          apply: true
          entries:
            - .github/workflows/framework-ci.yml
      YAML

      configured_plan = described_class.plan_project(root, env: {})
      report = configured_plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/framework-ci.yml"
      end
      content = report.fetch(:final_content)

      expect(configured_plan.fetch(:changed_files)).to include(".github/workflows/framework-ci.yml")
      expect(content).to include("name: Rails CI")
      expect(content).to include('          - "3.2"')
      expect(content).to include('          - framework_version: "7.0"')
      expect(content).to include('            gemfile: "gemfiles/rails_7_0"')
      expect(content).to include('          - framework_version: "7.1"')
      expect(content).not_to include("framework_version: []")
      expect(content).not_to include("gemfile: []")
    end
  end

  it "prunes packaged workflow files by configured engines and minimum Ruby" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-prune-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.7.yml
              - .github/workflows/ruby-3.2.yml
              - .github/workflows/jruby.yml
              - .github/workflows/truffle.yml
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      paths = plan.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }

      expect(paths).to include(".github/workflows/ruby-3.2.yml")
      expect(paths).not_to include(".github/workflows/ruby-2.7.yml")
      expect(paths).not_to include(".github/workflows/jruby.yml")
      expect(paths).not_to include(".github/workflows/truffle.yml")
      expect(plan.fetch(:changed_files)).to include(".github/workflows/ruby-3.2.yml")
      expect(plan.fetch(:changed_files)).not_to include(".github/workflows/ruby-2.7.yml")
    end
  end

  it "prunes versioned engine workflows below minimum Ruby compatibility" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-engine-workflow-floor-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
            - jruby
            - truffleruby
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/jruby-9.1.yml
              - .github/workflows/jruby-9.4.yml
              - .github/workflows/truffleruby-23.0.yml
              - .github/workflows/truffleruby-23.1.yml
        YAML
        ".github/workflows/truffleruby-23.2.yml" => <<~YAML,
          name: TruffleRuby 23.2
          jobs:
            test:
              strategy:
                matrix:
                  include:
                    - ruby: "truffleruby-23.2"
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      paths = plan.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }
      stale_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == ".github/workflows/truffleruby-23.2.yml"
      end

      expect(paths).not_to include(".github/workflows/jruby-9.1.yml")
      expect(paths).not_to include(".github/workflows/jruby-9.4.yml")
      expect(paths).not_to include(".github/workflows/truffleruby-23.0.yml")
      expect(paths).to include(".github/workflows/truffleruby-23.1.yml")
      expect(stale_report).to include(
        recipe_name: "github_actions_inactive_packaged_workflow_cleanup_github_workflows_truffleruby_23_2_yml",
        changed: true
      )
      expect(stale_report.dig(:metadata, :delete_file)).to be(true)
    end
  end

  it "prunes packaged gemfile templates below minimum Ruby" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-floor-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.4"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/x_std_libs/r2.3/libs.gemfile
              - gemfiles/modular/x_std_libs/r2.4/libs.gemfile
        YAML
        "gemfiles/modular/x_std_libs/r2.3/libs.gemfile" => "stale ruby 2.3 gemfile\n",
      })

      plan = described_class.plan_project(root, env: {})
      r23_report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/x_std_libs/r2.3/libs.gemfile"
      end
      paths = plan.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }

      expect(paths).to include("gemfiles/modular/x_std_libs/r2.4/libs.gemfile")
      expect(r23_report.fetch(:recipe_name)).to start_with("template_inactive_packaged_cleanup_")
      expect(r23_report.fetch(:metadata)).to include(delete_file: true)
    end
  end

  it "disables checkout credential persistence in packaged GitHub workflows" do
    workflow_templates = Dir[File.join(described_class::PACKAGED_TEMPLATE_ROOT, ".github/workflows/*.{yml,yaml}.example")]
    checkout_templates = workflow_templates.select { |path| File.read(path).include?("uses: actions/checkout@") }

    expect(checkout_templates).not_to be_empty
    checkout_templates.each do |path|
      expect(File.read(path)).to include("persist-credentials: false"), path
    end
  end

  it "applies README style conditionals and reports missing integrations" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["PolyForm-Noncommercial-1.0.0"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - README.md
          readme:
            integrations:
              coveralls: false
        YAML
        "templates/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          [![CodeCov Test Coverage][🏀codecovi]][🏀codecov] [![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls] [![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov] [![QLTY Maintainability][🏀qlty-mnti]][🏀qlty-mnt] [![CodeQL][🖐codeQL-img]][🖐codeQL]

          ## 🌻 Synopsis

          Template synopsis.

          ## 🦷 FLOSS Funding

          Funding template text.

          ## 🔐 Security

          Security template text.

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.
        MARKDOWN
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Project synopsis.

          ## ⚙️ Configuration

          Project configuration.

          ## 🔧 Basic Usage

          Project usage.
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "template_source_application_README_md" }
      expect(report.fetch(:final_content)).to include("Project synopsis.")
      expect(report.fetch(:final_content)).to include("Project configuration.")
      expect(report.fetch(:final_content)).to include("Project usage.")
      expect(report.fetch(:final_content)).not_to include("## 🦷 FLOSS Funding")
      expect(report.fetch(:final_content)).not_to include("## 🔐 Security")
      expect(report.fetch(:final_content)).not_to include("CodeCov Test Coverage")
      expect(report.fetch(:final_content)).not_to include("Coveralls Test Coverage")
      expect(report.fetch(:final_content)).not_to include("QLTY Test Coverage")
      expect(report.fetch(:final_content)).not_to include("CodeQL")
      expect(report.dig(:metadata, :readme_style, :floss_funding_enabled)).to be(false)
      expect(report.dig(:metadata, :readme_style, :security_enabled)).to be(false)
      expect(report.dig(:metadata, :readme_style, :disabled_integrations)).to eq(["coveralls"])
      expect(report.dig(:metadata, :readme_style, :missing_integrations)).to contain_exactly("codecov", "qlty", "codeql")
    end
  end

  it "creates a package README through the packaged README style API" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-api-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:changed)).to be(true)
      expect(plan.fetch(:final_content)).to include("# 💎 Example")
      expect(plan.fetch(:final_content)).to include("## 🌻 Synopsis")
      expect(plan.fetch(:final_content)).not_to include("root package-family guide")
      expect(plan.fetch(:final_content)).not_to include("Tokens to Remember")

      apply = described_class.apply_readme_style(root, env: {})
      expect(apply.fetch(:changed)).to be(true)
      expect(File.read(File.join(root, "README.md"))).to eq(apply.fetch(:final_content))
      expect(described_class.plan_readme_style(root, env: {}).fetch(:changed)).to be(false)
    end
  end

  it "merges CHANGELOG templates without replacing release history" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-changelog-template-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - CHANGELOG.md
        YAML
        "templates/CHANGELOG.md.example" => <<~MARKDOWN,
          # Changelog

          Template intro.

          ## [Unreleased]

          ### Added

          ### Changed

          ### Deprecated

          ### Removed

          ### Fixed

          ### Security

          [Unreleased]: https://example.com/template/compare/HEAD
        MARKDOWN
        "CHANGELOG.md" => <<~MARKDOWN,
          # Changelog

          Project intro.

          ## [Unreleased]

          ### Added
          - Keep project pending feature.
            - Keep nested detail.

          ### Fixed
          - Keep project pending fix.

          ## [2.0.0] - 2026-01-02

          - Existing release must survive.

          [Unreleased]: https://github.com/acme/example/compare/v2.0.0...HEAD
          [2.0.0]: https://github.com/acme/example/compare/v1.0.0...v2.0.0
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "template_source_application_CHANGELOG_md" }
      changelog = report.fetch(:final_content)

      expect(changelog).to include("Template intro.")
      expect(changelog).not_to include("Project intro.")
      expect(changelog).to include("Template intro.\n\n## [Unreleased]")
      expect(changelog).to include("### Deprecated")
      expect(changelog).to include("### Removed")
      expect(changelog).to include("### Security")
      expect(changelog).to include("[Unreleased]\n\n### Added\n\n- Keep project pending feature.")
      expect(changelog).to include("### Fixed\n\n- Keep project pending fix.")
      expect(changelog).to include("- Keep project pending feature.")
      expect(changelog).to include("  - Keep nested detail.")
      expect(changelog).to include("- Keep project pending fix.")
      expect(changelog).to include("## [2.0.0] - 2026-01-02")
      expect(changelog).to include("[2.0.0]: https://github.com/acme/example/compare/v1.0.0...v2.0.0")
      expect(changelog).not_to include("[Unreleased]: https://example.com/template/compare/HEAD")
    end
  end

  it "keeps the real CHANGELOG template in canonical Unreleased form" do
    template = File.read(File.join(__dir__, "../lib/kettle/jem/templates/CHANGELOG.md.example"))

    expect(template).to include(<<~MARKDOWN)
      ## [Unreleased]

      ### Added

      ### Changed

      ### Deprecated

      ### Removed

      ### Fixed

      ### Security
    MARKDOWN
  end

  it "fills configured README section partials while preserving unconfigured manual sections" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-partials-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
          readme:
            section_partials:
              synopsis: readme/partials/synopsis.md
              configuration: readme/partials/configuration.md
              basic_usage: readme/partials/basic_usage.md
        YAML
        "templates/readme/partials/synopsis.md.example" => "Generated synopsis for {KJ|GEM_NAME}.\\n",
        "templates/readme/partials/configuration.md.example" => "Generated configuration.\\n",
        "templates/readme/partials/basic_usage.md.example" => "Generated usage.\\n",
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Old synopsis.

          ## ⚙️ Configuration

          Old configuration.

          ## 🔧 Basic Usage

          Old usage.
        MARKDOWN
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:final_content)).to include("Generated synopsis for example.")
      expect(plan.fetch(:final_content)).to include("Generated configuration.")
      expect(plan.fetch(:final_content)).to include("Generated usage.")
      expect(plan.fetch(:final_content)).not_to include("Old synopsis.")
      expect(plan.fetch(:final_content)).not_to include("Old configuration.")
      expect(plan.fetch(:final_content)).not_to include("Old usage.")
      expect(plan.dig(:readme_style, :section_partials, "synopsis", :selected_source)).to eq(
        "templates/readme/partials/synopsis.md.example"
      )
    end
  end

  it "loads packaged README section partials" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-readme-partials-slice", tmp_root) do |root|
      write_tree(root, {
        "kettle-jem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-jem"
            spec.summary = "Kettle Jem"
            spec.homepage = "https://github.com/structuredmerge/kettle-jem"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
          readme:
            section_partials:
              synopsis: readme/partials/synopsis.md
              configuration: readme/partials/configuration.md
              basic_usage: readme/partials/basic_usage.md
        YAML
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:final_content)).to include("Kettle template tool")
      expect(plan.fetch(:final_content)).to include("Configuration shape")
      expect(plan.fetch(:final_content)).to include("bundle exec rake kettle:jem:install")
      expect(plan.dig(:readme_style, :section_partials, "configuration", :source_root)).to eq("packaged")
    end
  end

  it "removes Open Collective funding when disabled" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
          templates:
            root: packaged
            entries:
              - README.md
              - source: FUNDING.md.example
                target: FUNDING.md
        YAML
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: example
        YAML
        ".github/workflows/opencollective.yml" => <<~YAML,
          name: Open Collective
          on:
            workflow_dispatch:
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: actions/checkout@v3
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_disabled_source)).to eq("config.funding.open_collective")
      expect(plan.dig(:facts, :funding, :open_collective_files)).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe.fetch(:name) }
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_opencollective_yml")
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_github_workflows_opencollective_yml")
      expect(recipe_names).not_to include("github_actions_workflow_snippets_github_workflows_opencollective_yml")
      expect(plan.dig(:facts, :templates, :source_preferences)).to contain_exactly(
        a_hash_including(
          target_path: "README.md",
          configured_source: "README.md",
          selected_source: "README.md.example",
          source_relative_path: "README.md.example",
          source_root: "packaged",
          selection_reason: "default_example_variant",
          apply: false
        ),
        a_hash_including(
          target_path: "FUNDING.md",
          configured_source: "FUNDING.md.example",
          selected_source: "FUNDING.md.no-osc.example",
          source_relative_path: "FUNDING.md.no-osc.example",
          source_root: "packaged",
          selection_reason: "opencollective_disabled_no_osc_variant",
          apply: false
        )
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.fetch(:changed)).to be(false)
      expect(template_report.dig(:metadata, :template_source_preference, :selected_source)).to eq(
        "README.md.example"
      )
      expect(template_report.dig(:request_envelope, :request, :runtime_context, :template_source_preference, :selection_reason)).to eq(
        "default_example_variant"
      )
      funding_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_funding_yml" }
      expect(funding_report.fetch(:final_content)).not_to include("open_collective")
      expect(funding_report.fetch(:final_content)).to include("tidelift: rubygems/example")
      open_collective_reports = plan[:recipe_reports].select do |report|
        report.fetch(:recipe_name).start_with?("opencollective_disabled_file_cleanup_")
      end
      expect(open_collective_reports.map { |report| report.fetch(:relative_path) }).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(open_collective_reports).to all(satisfy { |report| report.fetch(:metadata).fetch(:delete_file) == true })

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to include(".opencollective.yml", ".github/workflows/opencollective.yml")
      expect(File).not_to exist(File.join(root, ".opencollective.yml"))
      expect(File).not_to exist(File.join(root, ".github/workflows/opencollective.yml"))
    end
  end

  it "applies the packaged README Open Collective recipe from the canonical template" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-readme-no-opencollective", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/acme/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
          templates:
            root: packaged
            apply: true
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      readme = readme_report.fetch(:final_content)

      expect(readme_report.dig(:metadata, :template_source_preference, :selected_source)).to eq("README.md.example")
      expect(readme).not_to include("KJ:OPEN_COLLECTIVE")
      expect(readme).not_to include("KJ:NO_OPEN_COLLECTIVE")
      expect(readme).not_to include("opencollective")
      expect(readme).not_to include("Open Collective")
      expect(readme).not_to include("kettle-readme-backers")
      expect(readme).not_to include("Open Source Helpers")
      expect(readme).not_to include("codetriage")
      expect(readme).to include("Apache SkyWalking Eyes License Compatibility Check")
      expect(readme).to include("[![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor]")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "updates the README KLOC badge from the current changelog release coverage" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-kloc-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          gem_version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/example/version.rb", mod) }::Example::Version::VERSION

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.version = gem_version
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "lib/example/version.rb" => <<~RUBY,
          module Example
            module Version
              VERSION = "1.2.3"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            profile: full
            apply: true
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        "CHANGELOG.md" => <<~MARKDOWN,
          # Changelog

          ## [1.2.3] - 2026-05-23

          ### Fixed

          - COVERAGE: 91.09% -- 3644/4000 lines in 80 files
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|GEM_NAME}

          [🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).to include("KLOC-4.000-FFDD67.svg")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "applies packaged monorepo subgem README badge policy" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-subgem-readme-badge-policy", tmp_root) do |root|
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "☯️"
          readme:
            package_family: structuredmerge
          templates:
            root: packaged
            apply: true
            profile: monorepo-subgem
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        ".github/workflows/current.yml" => "name: Current\n",
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).not_to include("Open Source Helpers")
      expect(readme).not_to include("codetriage")
      expect(readme).not_to include("OpenCollective Backers")
      expect(readme).not_to include("OpenCollective Sponsors")
      expect(readme).not_to include("opencollective")
      expect(readme).not_to include("Apache SkyWalking Eyes License Compatibility Check")
      expect(readme).to include("https://github.com/structuredmerge/structuredmerge-ruby#package-family")
      expect(readme).to include("root package-family guide")
      expect(readme).to include("https://github.com/structuredmerge/structuredmerge-ruby/actions/workflows/current.yml")
      expect(readme).not_to include("https://github.com/structuredmerge/ast-merge/actions/workflows/current.yml")
      expect(readme).not_to include("actions/workflows/heads.yml")
      expect(readme).to include("https://img.shields.io/badge/wiki-gitlab-943CD2.svg")
      expect(readme).to include("https://img.shields.io/badge/wiki-github-943CD2.svg")
      expect(readme).not_to include("https://img.shields.io/badge/wiki-examples-943CD2.svg")
    end
  end

  it "honors falsey Open Collective environment variables when config is absent" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-env-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: { "OPENCOLLECTIVE_HANDLE" => "NO" })
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_disabled_source)).to eq("env.OPENCOLLECTIVE_HANDLE")
      expect(plan.dig(:facts, :funding, :open_collective_org)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      expect(plan[:changed_files]).to include(".opencollective.yml")
    end
  end

  it "lets explicit Open Collective config override falsey environment variables" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-config-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: true
        YAML
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: { "FUNDING_ORG" => "0" })
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/example")
    end
  end

  it "discovers Open Collective org from environment before .opencollective.yml" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-env-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            entries:
              - README.md
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: yaml-org
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: { "FUNDING_ORG" => "env-org" })
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("env-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("env.FUNDING_ORG")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/env-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include(
        "KJ|GEM_NAME" => "example",
        "KJ|GEM_NAME_PATH" => "example",
        "KJ|NAMESPACE" => "Example",
        "KJ|OPENCOLLECTIVE_ORG" => "env-org"
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.dig(:metadata, :template_tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "env-org")
      expect(template_report.dig(:request_envelope, :request, :runtime_context, :template_tokens)).to include(
        "KJ|OPENCOLLECTIVE_ORG" => "env-org"
      )
    end
  end

  it "discovers Open Collective org from .opencollective.yml when env is absent" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-yaml-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".opencollective.yml" => <<~YAML,
          org: yaml-org
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("yaml-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq(".opencollective.yml")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/yaml-org")
    end
  end

  it "applies selected template content with projected tokens when configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-application-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => "# old\n",
        ".opencollective.yml" => <<~YAML,
          collective: yaml-org
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|GEM_NAME}

          Namespace: {KJ|NAMESPACE}
          Path: {KJ|GEM_NAME_PATH}
          Ruby: {KJ|MIN_RUBY}
          Author: {KJ|AUTHOR:NAME}
          Given: {KJ|AUTHOR:GIVEN_NAMES}
          Family: {KJ|AUTHOR:FAMILY_NAMES}
          Email: {KJ|AUTHOR:EMAIL}
          Domain: {KJ|AUTHOR:DOMAIN}
          Funding: {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:changed)).to be(true)
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include("{KJ|GEM_NAME}")
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        # 💎 Example

        Namespace: Example
        Path: example
        Ruby: 3.2
        Author: Jane Q Public
        Given: Jane Q
        Family: Public
        Email: jane@example.test
        Domain: example.test
        Funding: yaml-org
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|AUTHOR:DOMAIN" => "example.test",
        "KJ|AUTHOR:EMAIL" => "jane@example.test",
        "KJ|AUTHOR:FAMILY_NAMES" => "Public",
        "KJ|AUTHOR:GIVEN_NAMES" => "Jane Q",
        "KJ|AUTHOR:NAME" => "Jane Q Public",
        "KJ|GEM_NAME" => "example",
        "KJ|GEM_NAME_PATH" => "example",
        "KJ|MIN_RUBY" => "3.2",
        "KJ|NAMESPACE" => "Example",
        "KJ|OPENCOLLECTIVE_ORG" => "yaml-org"
      )

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
    end
  end

  it "applies packaged template files when no project template root exists" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          tokens:
            forge:
              gh_user: acme
              gl_user: acme
              cb_user: acme
              sh_user: acme
            funding:
              patreon: acme
              kofi: acme
              paypal: acme
              buymeacoffee: acme
              polar: acme
              liberapay: acme
              issuehunt: acme
            social:
              mastodon: "@acme@example.social"
              bluesky: acme.example
              linktree: acme
              devto: acme
          templates:
            apply: true
            entries:
              - README.md
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: "README.md.example",
        source_relative_path: "README.md.example",
        source_root: "packaged"
      )
      expect(template_report.dig(:metadata, :template_source_preference, :source_root_path)).to end_with(
        "lib/kettle/jem/templates"
      )
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include("# {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}")
      expect(template_report.fetch(:final_content)).to include("# 💎 Example")
      expect(template_report.fetch(:final_content)).to include("Compatible with MRI Ruby 3.2+")
      expect(template_report.fetch(:final_content)).to include("https://patreon.com/acme")
      expect(template_report.fetch(:final_content)).to include("https://github.com/acme/example")

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
    end
  end

  it "trims README compatibility badges from minimum Ruby and engine config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-compatibility-badge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # Example

          | Works with MRI Ruby 3 | [![Ruby 3.0 Compat][💎ruby-3.0i]][🚎4-lg-wf] [![Ruby 3.2 Compat][💎ruby-3.2i]][🚎6-s-wf] [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf] |
          | Works with JRuby | [![JRuby 10.0 Compat][💎jruby-10.0i]][🚎11-j-wf] |

          [💎ruby-3.0i]: https://example/ruby-30
          [💎ruby-3.2i]: https://example/ruby-32
          [💎ruby-c-i]: https://example/ruby-current
          [💎jruby-10.0i]: https://example/jruby-100
          [🚎4-lg-wf]: https://example/legacy
          [🚎6-s-wf]: https://example/supported
          [🚎11-c-wf]: https://example/current
          [🚎11-j-wf]: https://example/jruby
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = report.fetch(:final_content)
      mri_line = final_content.lines.find { |line| line.start_with?("| Works with MRI Ruby 3") }

      expect(mri_line).not_to include("ruby-3.0i")
      expect(mri_line).to include("ruby-3.2i")
      expect(mri_line).to include("ruby-c-i")
      expect(final_content).not_to include("Works with JRuby")
      expect(final_content).not_to match(/^\[💎ruby-3\.0i\]:/)
      expect(final_content).not_to match(/^\[💎jruby-10\.0i\]:/)
      expect(final_content).not_to match(/^\[🚎4-lg-wf\]:/)
      expect(final_content).not_to match(/^\[🚎11-j-wf\]:/)
      expect(final_content).to match(/^\[💎ruby-3\.2i\]:/)
      expect(final_content).to match(/^\[🚎6-s-wf\]:/)
      expect(final_content).to match(/^\[🚎11-c-wf\]:/)
    end
  end

  it "filters template recipes with old only/include semantics" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-only-filter-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "# Example\n",
      })

      plan = described_class.plan_project(root, env: {}, run_options: {only: "README.md"})
      paths = plan.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }
      expect(paths.uniq).to eq(["README.md"])

      apply = described_class.apply_project(root, env: {}, run_options: {only: "README.md"})
      expect(apply.fetch(:changed_files)).to eq(["README.md"])
      expect(File).to exist(File.join(root, "README.md"))
      expect(File).not_to exist(File.join(root, ".github", "FUNDING.yml"))

      expanded = described_class.plan_project(root, env: {}, run_options: {only: "README.md", include: ".github/**"})
      expect(expanded.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }).to include(
        "README.md",
        ".github/FUNDING.yml"
      )
    end
  end

  it "bootstraps kettle config from packaged reference template when missing" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: { "KJ_MIN_DIVERGENCE_THRESHOLD" => "7" })
      bootstrap_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      expect(bootstrap_report.fetch(:changed)).to be(true)
      expect(bootstrap_report.fetch(:relative_path)).to eq(".kettle-jem.yml")
      expect(bootstrap_report.dig(:metadata, :bootstrap_file)).to be(true)
      expect(bootstrap_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: ".kettle-jem.yml.example",
        source_relative_path: ".kettle-jem.yml.example",
        source_root: "packaged"
      )
      expect(bootstrap_report.fetch(:final_content)).to include("# kettle-jem configuration file")
      expect(bootstrap_report.fetch(:final_content)).to include("min_divergence_threshold: 7")
      expect(bootstrap_report.fetch(:final_content)).to include("#   tokens    - values for {KJ|...} placeholders used across template files")

      described_class.apply_project(root, env: { "KJ_MIN_DIVERGENCE_THRESHOLD" => "7" })
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(bootstrap_report.fetch(:final_content))
    end
  end

  it "seeds bootstrap config licenses from the gemspec" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-licenses", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end

      expect(bootstrap_report.fetch(:final_content)).to include(<<~YAML)
        licenses:
          - AGPL-3.0-only
          - PolyForm-Small-Business-1.0.0
      YAML
      expect(bootstrap_report.fetch(:final_content)).not_to include(<<~YAML)
        licenses:
          - MIT
      YAML
      expect(bootstrap_report.fetch(:final_content)).to include(<<~YAML)
        license_eye:
          dependency_licenses:
            - name: simplecov-rcov
              version: 0.3.7
              license: MIT
      YAML
    end
  end

  it "bootstraps a monorepo subgem template profile with package-owned entries only" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-subgem", tmp_root) do |root|
      write_tree(root, {
        "tree_haver.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "tree_haver"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "README.md" => "# 💎 Tree::Haver\n\nExisting README.\n",
      })

      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )
      config = File.read(File.join(root, ".kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".kettle-jem.yml")
      expect(config).to include("project_emoji: 💎\n")
      expect(config_yaml.dig("templates", "root")).to eq("packaged")
      expect(config_yaml.dig("templates", "apply")).to be(true)
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-subgem")
      expect(config_yaml.dig("templates", "entries")).to include(
        "README.md",
        {"source" => "gem.gemspec", "target" => "tree_haver.gemspec"},
        "LICENSE.md"
      )
      expect(config).to include(
        "    - source: lib/gem/version.rb\n" \
        "      target: lib/tree_haver/version.rb\n" \
        "    - source: sig/gem/version.rbs\n" \
        "      target: sig/tree_haver/version.rbs\n"
      )
      expect(config).to include("    - certs/pboling.pem\n")
      expect(config).to include("    - tmp/.gitignore\n")
      expect(config).not_to include("    - .github/workflows/current.yml\n")
      expect(config).to include(<<~YAML)
        files:
          README.md:
            strategy: merge
          tree_haver.gemspec:
            strategy: keep_destination
      YAML

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})
      expect(apply.fetch(:changed_files)).to include("LICENSE.md")
      expect(apply.fetch(:changed_files)).to include("README.md")
      expect(apply.fetch(:changed_files)).not_to include("tree_haver.gemspec")
      expect(File).not_to exist(File.join(root, ".github"))
      expect(File).not_to exist(File.join(root, "Gemfile"))
      expect(File).not_to exist(File.join(root, "Rakefile"))
    end
  end

  it "renders version_gem Ruby and RBS files from packaged templates" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-template-files", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.9"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
                target: lib/example/gem/version.rb
              - source: sig/gem/version.rbs
                target: sig/example/gem/version.rbs
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/example/gem/version.rb", "sig/example/gem/version.rbs")
      version_rb = File.read(File.join(root, "lib", "example", "gem", "version.rb"))
      expect(version_rb).to include("module Example")
      expect(version_rb).to include("module Gem")
      expect(version_rb).to include('VERSION = "1.2.3"')
      version_rbs = File.read(File.join(root, "sig", "example", "gem", "version.rbs"))
      expect(version_rbs).to include("module Example")
      expect(version_rbs).to include("module Gem")
      expect(version_rbs).to include("VERSION: String")
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "version_gem_bootstrap" }
      expect(post_step.fetch(:changed_files)).to eq(["lib/example/gem.rb"])
    end
  end

  it "uses configured RubyGems entrypoint and namespace for version_gem files" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-configured-entrypoint", tmp_root) do |root|
      write_tree(root, {
        "turbo_tests2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "turbo_tests2"
            spec.version = "3.0.0"
            spec.summary = "Turbo tests"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.9"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🚀"
          rubygems:
            entrypoint_require: "turbo_tests"
            namespace: "TurboTests"
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
              - source: sig/gem/version.rbs
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/turbo_tests/version.rb", "sig/turbo_tests/version.rbs")
      expect(apply.fetch(:changed_files)).not_to include("lib/turbo_tests2/version.rb")
      version_rb = File.read(File.join(root, "lib", "turbo_tests", "version.rb"))
      expect(version_rb).to include("module TurboTests")
      version_rbs = File.read(File.join(root, "sig", "turbo_tests", "version.rbs"))
      expect(version_rbs).to include("module TurboTests")
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "version_gem_bootstrap" }
      expect(post_step.fetch(:changed_files)).to include("lib/turbo_tests.rb")
      expect(post_step.fetch(:changed_files)).not_to include("lib/turbo_tests2.rb")
    end
  end

  it "bootstraps a monorepo root template profile with shared documentation entries" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-root", tmp_root) do |root|
      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-root", skip_commit: true}
      )
      config = File.read(File.join(root, ".kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".kettle-jem.yml")
      expect(config_yaml.dig("templates", "root")).to eq("packaged")
      expect(config_yaml.dig("templates", "apply")).to be(true)
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-root")
      expect(config_yaml.dig("templates", "entries")).to include(
        "CHANGELOG.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "FUNDING.md",
        "IRP.md",
        "RUBOCOP.md",
        "SECURITY.md",
        ".github/FUNDING.yml"
      )
      expect(config).to include(<<~YAML)
        files:
          CHANGELOG.md:
            strategy: accept_template
      YAML
      expect(config.lines.count { |line| line == "  .github:\n" }).to eq(1)
    end
  end

  it "rewrites monorepo subgem README policy document references to source-hosted URLs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-subgem-readme-links", tmp_root) do |root|
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
            spec.licenses = ["AGPL-3.0-only"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "☯️"
          templates:
            root: template
            apply: true
            profile: monorepo-subgem
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}

          ## 🤝 Contributing

          See [CONTRIBUTING.md][🤝contributing].

          ## 🔐 Security

          See [SECURITY.md][🔐security].

          ## 📌 Versioning

          See [CHANGELOG.md][📌changelog].

          [🤝contributing]: CONTRIBUTING.md
          [🪇conduct]: CODE_OF_CONDUCT.md
          [📌changelog]: CHANGELOG.md
          [🧹rubocop]: RUBOCOP.md
          [🚨irp]: IRP.md
          [🔐security]: SECURITY.md
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "README.md" }
      readme = report.fetch(:final_content)
      source_root = "https://github.com/structuredmerge/structuredmerge-ruby/blob/main"

      expect(readme).to include("[🤝contributing]: #{source_root}/CONTRIBUTING.md")
      expect(readme).to include("[🪇conduct]: #{source_root}/CODE_OF_CONDUCT.md")
      expect(readme).to include("[📌changelog]: #{source_root}/CHANGELOG.md")
      expect(readme).to include("[🧹rubocop]: #{source_root}/RUBOCOP.md")
      expect(readme).to include("[🚨irp]: #{source_root}/IRP.md")
      expect(readme).to include("[🔐security]: #{source_root}/SECURITY.md")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "exposes canonical repository URL tokens for monorepo subgem templates" do
    repository = {
      url: "https://github.com/structuredmerge/structuredmerge-ruby",
      name: "structuredmerge-ruby",
      slug: "structuredmerge/structuredmerge-ruby",
      package_path: "gems/ast-merge",
      package_source_url: "https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge",
      gitlab_package_source_url: "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/ast-merge",
      codeberg_package_source_url: "https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/ast-merge",
      checksums_url: "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums",
    }
    tokens = described_class.send(:readme_url_template_tokens, repository, "ast-merge", "structuredmerge")

    expect(tokens.fetch("KJ|README:GH_REPOSITORY_URL")).to eq("https://github.com/structuredmerge/structuredmerge-ruby")
    expect(tokens.fetch("KJ|README:GH_PACKAGE_SOURCE_URL")).to eq(
      "https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge"
    )
    expect(tokens.fetch("KJ|README:GH_CONTRIBUTING_URL")).to eq(
      "https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CONTRIBUTING.md"
    )
    expect(tokens.fetch("KJ|README:GL_PACKAGE_SOURCE_URL")).to eq(
      "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/ast-merge"
    )
    expect(tokens.fetch("KJ|CHANGELOG:GL_COMPARE_URL")).to eq(
      "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/compare"
    )
    expect(tokens.fetch("KJ|CHANGELOG:GL_TAGS_URL")).to eq("https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tags")
  end

  it "projects monorepo subgem README output to thin form while preserving destination-owned sections" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-subgem-thin-readme", tmp_root) do |root|
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
            spec.licenses = ["AGPL-3.0-only"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "☯️"
          templates:
            root: template
            apply: true
            profile: monorepo-subgem
            entries:
              - README.md
          files:
            README.md:
              strategy: merge
        YAML
        "README.md" => <<~MARKDOWN,
          # Existing

          ## 🌻 Synopsis

          Destination synopsis.

          ## ⚙️ Configuration

          Destination configuration.

          ## 🔧 Basic Usage

          Destination usage.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}

          ## 🌻 Synopsis

          Template synopsis.

          ## 💡 Info you can shake a stick at

          Info.

          ### Compatibility

          Compatible.

          ### Enterprise Support

          Heavy support content.

          ## ✨ Installation

          Install.

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.

          ## 🦷 FLOSS Funding

          Funding.

          ## 🔐 Security

          See [SECURITY.md][🔐security].

          ## 🤝 Contributing

          Contributions.

          ### Code Coverage

          Coverage.

          ## 🌈 Contributors

          Contributors.

          ## 📌 Versioning

          Versioning.

          ## 📄 License

          License.

          ## 🤑 A request for help

          Request.

          [🔐security]: SECURITY.md
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "README.md" }.fetch(:final_content)

      expect(readme).to include("## 🌻 Synopsis\n\nDestination synopsis.")
      expect(readme).to include("## ⚙️ Configuration\n\nDestination configuration.")
      expect(readme).to include("## 🔧 Basic Usage\n\nDestination usage.")
      expect(readme).to include("### Compatibility")
      expect(readme).to include("## ✨ Installation")
      expect(readme).to include("## 🔐 Security")
      expect(readme).not_to include("### Enterprise Support")
      expect(readme).not_to include("## 🦷 FLOSS Funding")
      expect(readme).not_to include("### Code Coverage")
      expect(readme).not_to include("## 🌈 Contributors")
      expect(readme).not_to include("## 🤑 A request for help")
    end
  end

  it "seeds a default project emoji for monorepo subgems without a README" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-subgem-emoji", tmp_root) do |root|
      write_tree(root, {
        "ast-crispr.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-crispr"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
          end
        RUBY
      })

      described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )

      expect(File.read(File.join(root, ".kettle-jem.yml"))).to include("project_emoji: 💎\n")
    end
  end

  it "seeds project emoji from KJ_PROJECT_EMOJI before README or defaults" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-env-emoji", tmp_root) do |root|
      write_tree(root, {
        "json-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "json-merge"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
          end
        RUBY
        "README.md" => "# 💎 Json::Merge\n\nExisting README.\n",
      })

      described_class.setup_project(
        root,
        env: {"KJ_PROJECT_EMOJI" => "☯️"},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )

      expect(File.read(File.join(root, ".kettle-jem.yml"))).to include("project_emoji: ☯️\n")
    end
  end

  it "applies bootstrap with non-interactive defaults and converges on the next run" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-bootstrap-contract", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      bootstrap_target = bootstrap_contract.fetch(:expected).fetch(:bootstrap_target)

      expect(apply.fetch(:decision_policy).fetch(:mode)).to eq(
        bootstrap_contract.fetch(:expected).fetch(:non_interactive_mode)
      )
      expect(apply.fetch(:changed_files)).to include(bootstrap_target)
      expect(File).to exist(File.join(root, bootstrap_target))

      second_apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      selected = bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths).to_h do |relative_path|
        [relative_path, File.exist?(File.join(root, relative_path)) ? File.read(File.join(root, relative_path)) : nil]
      end
      third_apply = described_class.apply_project(root, env: {}, run_options: { accept: true })

      expect(third_apply.fetch(:decision_policy).fetch(:mode)).to eq(
        bootstrap_contract.fetch(:expected).fetch(:non_interactive_mode)
      )
      expect(bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths).to_h { |relative_path|
        [relative_path, File.exist?(File.join(root, relative_path)) ? File.read(File.join(root, relative_path)) : nil]
      }).to eq(selected)
      expect(third_apply.fetch(:changed_files)).not_to include(
        *bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths)
      )
    end
  end

  it "hard-fails malformed Ruby project entrypoints during preflight" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    parser_error_paths = bootstrap_contract.fetch(:expected).fetch(:parser_error_paths)

    parser_error_paths.each do |relative_path|
      Dir.mktmpdir("kettle-jem-bootstrap-preflight", tmp_root) do |root|
        files = {
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
              spec.required_ruby_version = ">= 4.0"
            end
          RUBY
        }
        files["Gemfile"] = "source \"https://gem.coop\"\n" if relative_path == "example.gemspec"
        files[relative_path] = "if true\n"
        write_tree(root, files)

        expect {
          described_class.plan_project(root, env: {}, run_options: { accept: true })
        }.to raise_error(Kettle::Jem::Error, /Preflight failed for #{Regexp.escape(relative_path)}/)
      end
    end
  end

  it "hard-fails invalid kettle config shape before later discovery" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    {
      "root_scalar" => ["true\n", /root must be a mapping/],
      "templates_scalar" => ["templates: packaged\n", /templates must be a mapping/],
      "entries_scalar" => ["templates:\n  entries: README.md\n", /templates\.entries must be a list/],
    }.each do |case_name, (config, message)|
      Dir.mktmpdir("kettle-jem-config-validation-#{case_name}", tmp_root) do |root|
        write_tree(root, {
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
            end
          RUBY
          ".kettle-jem.yml" => config,
        })

        expect {
          described_class.plan_project(root, env: {})
        }.to raise_error(Kettle::Jem::Error, message)
      end
    end
  end

  it "classifies template entries with files and patterns strategy config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-strategy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          patterns:
            - path: "certs/**"
              strategy: raw_copy
          files:
            README.md:
              strategy: keep_destination
          templates:
            root: packaged
            apply: true
            entries:
              - README.md
              - source: certs/pboling.pem.example
                target: certs/pboling.pem
        YAML
        "README.md" => "# destination\n",
      })

      packaged_cert = File.read(File.join(__dir__, "../lib/kettle/jem/templates/certs/pboling.pem.example"))
      plan = described_class.plan_project(root, env: {})
      readme_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      cert_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_certs_pboling_pem"
      end
      expect(readme_report.fetch(:changed)).to be(false)
      expect(readme_report.fetch(:final_content)).to eq("# destination\n")
      expect(readme_report.dig(:metadata, :template_source_preference)).to include(strategy: "keep_destination")
      expect(cert_report.fetch(:changed)).to be(true)
      expect(cert_report.fetch(:final_content)).to eq(packaged_cert)
      expect(cert_report.dig(:metadata, :template_source_preference)).to include(strategy: "raw_copy")
    end
  end

  it "projects full per-file merge options into recipe metadata and runtime context" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-merge-option-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          defaults:
            preference: template
            add_template_only_nodes: true
            freeze_token: kettle-jem
            max_recursion_depth: 7
          files:
            config:
              settings.yml:
                strategy: merge
                file_type: yaml
                freeze_token: destination-token
                skip_unresolved_scan: true
          templates:
            root: template
            apply: true
            entries:
              - config/settings.yml
        YAML
        "config/settings.yml" => <<~YAML,
          enabled: false
        YAML
        "template/config/settings.yml.example" => <<~YAML,
          enabled: true
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      expected_policy = {
        strategy: "merge",
        file_type: "yaml",
        preference: "template",
        add_template_only_nodes: true,
        freeze_token: "destination-token",
        skip_unresolved_scan: true,
        max_recursion_depth: "7",
      }

      expect(report.dig(:metadata, :template_source_preference)).to include(expected_policy)
      expect(report.dig(:request_envelope, :request, :runtime_context, :template_source_preference)).to include(expected_policy)
    end
  end

  it "plans packaged template inventory when entries are omitted" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-inventory-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
          patterns:
            - path: "certs/**"
              strategy: raw_copy
          files:
            AGENTS.md:
              strategy: accept_template
          templates:
            root: packaged
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      preferences = plan.dig(:facts, :templates, :source_preferences)
      expect(preferences.size).to be > 100

      agents = preferences.find { |preference| preference.fetch(:target_path) == "AGENTS.md" }
      cert = preferences.find { |preference| preference.fetch(:target_path) == "certs/pboling.pem" }
      envrc = preferences.find { |preference| preference.fetch(:target_path) == ".envrc" }
      env_local = preferences.find { |preference| preference.fetch(:target_path) == ".env.local.example" }
      gemspec = preferences.find { |preference| preference.fetch(:target_path) == "example.gemspec" }

      expect(agents).to include(selected_source: "AGENTS.md.example", strategy: "accept_template")
      expect(cert).to include(selected_source: "certs/pboling.pem.example", strategy: "raw_copy")
      expect(envrc).to include(selected_source: ".envrc.no-osc.example")
      expect(env_local).to include(configured_source: ".env.local", selected_source: ".env.local.example")
      expect(gemspec).to include(configured_source: "gem.gemspec", selected_source: "gem.gemspec.example")
    end
  end

  it "applies remaining-files copy-only and legacy destination policies" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-remaining-files-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
              - .github/copilot_instructions.md
        YAML
        "bin/setup" => "custom setup\n",
        ".github/COPILOT_INSTRUCTIONS.md" => "legacy copilot instructions\n",
      })

      plan = described_class.plan_project(root, env: {})
      setup_preference = plan.dig(:facts, :templates, :source_preferences).find do |preference|
        preference.fetch(:target_path) == "bin/setup"
      end
      setup_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_bin_setup"
      end
      legacy_cleanup = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_legacy_destination_cleanup_github_COPILOT_INSTRUCTIONS_md"
      end

      expect(setup_preference).to include(
        strategy: "keep_destination",
        policy: "copy_only_when_missing"
      )
      expect(setup_report.fetch(:changed)).to be(false)
      expect(setup_report.fetch(:final_content)).to eq("custom setup\n")
      expect(legacy_cleanup.dig(:metadata, :delete_file)).to be(true)
      expect(legacy_cleanup.dig(:report_envelope, :report, :step_reports, 0, :metadata)).to include(
        policy_kind: "delete_legacy_destination_file",
        deleted_file: ".github/COPILOT_INSTRUCTIONS.md"
      )

      apply = described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "bin/setup"))).to eq("custom setup\n")
      expect(File.exist?(File.join(root, ".github/copilot_instructions.md"))).to be(true)
      expect(File.exist?(File.join(root, ".github/COPILOT_INSTRUCTIONS.md"))).to be(false)
      expect(apply.fetch(:changed_files)).to include(".github/COPILOT_INSTRUCTIONS.md")
    end
  end

  it "runs install as active apply plus local post-template checks" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-post-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup", quiet: true, skip_commit: true},
        command_runner: command_runner
      )
      setup_path = File.join(root, "bin", "setup")

      expect(install.fetch(:mode)).to eq("install")
      expect(install.fetch(:installed)).to be(true)
      expect(install.fetch(:changed_files)).to eq(["bin/setup"])
      expect(install.fetch(:install_steps)).to include(
        name: "bin_setup_executable",
        path: "bin/setup",
        status: "updated"
      )
      expect(install.fetch(:install_steps)).to include(
        name: "bin_setup",
        command: ["bin/setup", "--quiet"],
        status: "succeeded",
        exitstatus: 0
      )
      expect(install.fetch(:install_steps)).to include(
        name: "bundle_binstubs",
        command: %w[bundle binstubs --all],
        status: "succeeded",
        exitstatus: 0
      )
      expect(install.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        command: ["bundle", "exec", "kettle-jem", "--skip-commit", "--quiet", "--only", "bin/setup"],
        status: "succeeded",
        exitstatus: 0,
        reason: "executed"
      )
      expect(install.fetch(:install_steps)).to include(
        name: "bootstrap_commit",
        status: "skipped",
        reason: "skip_commit"
      )
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        steps: include("bin_setup_executable", "bin_setup", "bundle_binstubs"),
        statuses: hash_including(
          "bin_setup_executable" => "updated",
          "bin_setup" => "succeeded",
          "bundle_binstubs" => "succeeded"
        )
      ))
      expect(install.fetch(:install_phase_reports)).to include(
        phase: "orchestration",
        steps: %w[bundled_handoff bootstrap_commit],
        statuses: {
          "bundled_handoff" => "succeeded",
          "bootstrap_commit" => "skipped"
        }
      )
      expect(commands.map { |entry| entry.fetch(:command) }).to eq([
        ["bin/setup", "--quiet"],
        %w[bundle binstubs --all],
        ["bundle", "exec", "kettle-jem", "--skip-commit", "--quiet", "--only", "bin/setup"],
      ])
      expect(commands).to all(include(chdir: root, env: {}, quiet: true))
      expect(File).to exist(setup_path)
      expect(File.executable?(setup_path)).to be(true)

      commands.clear
      second = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup", quiet: true},
        command_runner: command_runner
      )
      expect(second.fetch(:changed_files)).to eq([])
      expect(second.fetch(:install_steps)).to include(
        name: "bin_setup_executable",
        path: "bin/setup",
        status: "already_executable"
      )
      expect(second.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        command: ["bundle", "exec", "kettle-jem", "--quiet", "--only", "bin/setup"],
        status: "succeeded",
        exitstatus: 0,
        reason: "executed"
      )
      second_commit_step = second.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }
      expect(second_commit_step.fetch(:status)).to satisfy { |status| %w[clean_noop succeeded].include?(status) }
      expect(second_commit_step.fetch(:reason, "executed")).to eq("executed") if second_commit_step.fetch(:status) == "succeeded"
      expect(commands.map { |entry| entry.fetch(:command) }.take(3)).to eq([
        ["bin/setup", "--quiet"],
        %w[bundle binstubs --all],
        ["bundle", "exec", "kettle-jem", "--quiet", "--only", "bin/setup"],
      ])

      bootstrap_install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup", bootstrap_mode: true},
        command_runner: command_runner
      )
      expect(bootstrap_install.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        status: "skipped",
        reason: "bootstrap_mode"
      )

      expect(system("git", "init", root, out: File::NULL, err: File::NULL)).to be(true)
      git_ready = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "bin/setup"},
        command_runner: command_runner
      )
      expect(git_ready.fetch(:install_steps)).to include(hash_including(
        name: "bootstrap_commit",
        status: "succeeded",
        commands: [
          %w[git add -A],
          ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"],
        ],
        command_results: [
          {command: %w[git add -A], exitstatus: 0},
          {command: ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"], exitstatus: 0},
        ],
        reason: "executed"
      ))
      expect(git_ready.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }.fetch(:dirty_entries)).not_to be_empty

      Dir.mktmpdir("kettle-jem-install-monorepo", tmp_root) do |repo_root|
        expect(system("git", "init", repo_root, out: File::NULL, err: File::NULL)).to be(true)
        gem_root = File.join(repo_root, "gems", "example")
        write_tree(gem_root, {
          "Gemfile" => <<~RUBY,
            source "https://rubygems.org"
            gemspec
          RUBY
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
            end
          RUBY
          ".kettle-jem.yml" => <<~YAML,
            templates:
              root: packaged
              apply: true
              entries:
                - bin/setup
          YAML
        })

        commands.clear
        inherited_env = {"BUNDLE_GEMFILE" => File.join(repo_root, "Gemfile")}
        monorepo_install = Kettle::Jem::Tasks::InstallTask.run(
          project_root: gem_root,
          env: inherited_env,
          run_options: {only: "bin/setup"},
          command_runner: command_runner
        )
        expect(monorepo_install.fetch(:git_preflight)).to include(git_repository: true)
        expect(monorepo_install.fetch(:install_steps)).to include(hash_including(
          name: "bootstrap_commit",
          status: "succeeded",
          reason: "executed"
        ))
        expect(commands.map { |entry| entry.fetch(:env).fetch("BUNDLE_GEMFILE") }.uniq).to eq([File.join(gem_root, "Gemfile")])
        expect(monorepo_install.fetch(:install_steps)).to include(hash_including(
          name: "bundled_handoff",
          status: satisfy { |status| %w[succeeded already_bundled].include?(status) }
        ))

        commands.clear
        binstub_runner = lambda do |command, chdir:, env:, quiet:|
          commands << {command: command, chdir: chdir, env: env, quiet: quiet}
          if command == %w[bundle binstubs --all]
            FileUtils.mkdir_p(File.join(chdir, "bin"))
            File.write(File.join(chdir, "bin", "rake"), "#!/usr/bin/env ruby\nputs 'rake binstub'\n")
            FileUtils.chmod("+x", File.join(chdir, "bin", "rake"))
          end
          {success: true, exitstatus: 0, stdout: "", stderr: ""}
        end
        validated_install = Kettle::Jem::Tasks::InstallTask.run(
          project_root: gem_root,
          env: inherited_env,
          run_options: {only: "bin/setup", skip_commit: true},
          command_runner: binstub_runner
        )
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "bundle_binstub_location_validation",
          status: "succeeded",
          reason: "destination_bin_has_binstubs",
          destination_bin: "bin",
          destination_binstubs: include("rake")
        ))
        expect(commands.find { |entry| entry.fetch(:command) == %w[bundle binstubs --all] }).to include(
          chdir: gem_root,
          env: include("BUNDLE_GEMFILE" => File.join(gem_root, "Gemfile"))
        )
      end
    end
  end

  it "runs setup commands when the caller passes Ruby ENV" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        "Gemfile" => "source \"https://gem.coop\"\n",
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      command_envs = []
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(quiet).to be(true)
        command_envs << env
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      expect {
        Kettle::Jem::Tasks::InstallTask.run(
          project_root: root,
          env: ENV,
          run_options: {only: "bin/setup", quiet: true, skip_commit: true},
          command_runner: command_runner
        )
      }.not_to raise_error

      expect(command_envs).not_to be_empty
      expect(command_envs).to all(be_a(Hash))
      expect(command_envs).to all(include("BUNDLE_GEMFILE" => File.join(root, "Gemfile")))
    end
  end

  it "honors install ENV skip-commit and normalizes lockfiles without templating env overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-skip-lock", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            arm64-darwin
            ruby
            x86_64-darwin

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      env = {
        "KETTLE_JEM_SKIP_COMMIT" => "true",
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_RB_DEV" => "/workspace/kettle-rb",
        "GALTZO_FLOSS_DEV" => "/workspace/galtzo-floss",
        "SMORG_RB_DEV" => "/workspace/smorg-rb",
      }
      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: env,
        run_options: {only: "bin/setup"},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "bootstrap_commit",
        status: "skipped",
        reason: "skip_commit"
      )
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundle_lock_normalization",
        command: %w[bundle lock --add-platform arm64-darwin ruby x86_64-darwin],
        status: "succeeded",
        reason: "executed"
      ))
      lock_command = commands.find { |entry| entry.fetch(:command).first(2) == %w[bundle lock] }
      expect(lock_command).not_to be_nil
      expect(lock_command.fetch(:env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "false",
        "KETTLE_RB_DEV" => "false",
        "GALTZO_FLOSS_DEV" => "false",
        "SMORG_RB_DEV" => "false"
      )
      expect(commands.map { |entry| entry.fetch(:command) }).not_to include(%w[git add -A])
    end
  end

  it "normalizes lockfiles from the template task without templating env overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-lock-normalization", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            arm64-darwin
            ruby
            x86_64-darwin

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries: []
        YAML
      })

      env = {
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_RB_DEV" => "/workspace/kettle-rb",
        "GALTZO_FLOSS_DEV" => "/workspace/galtzo-floss",
        "SMORG_RB_DEV" => "/workspace/smorg-rb",
      }
      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      report = Kettle::Jem::Tasks::TemplateTask.run(
        project_root: root,
        env: env,
        run_options: {quiet: true},
        command_runner: command_runner
      )

      expect(report.fetch(:template_steps)).to include(hash_including(
        name: "bundle_lock_normalization",
        command: %w[bundle lock --add-platform arm64-darwin ruby x86_64-darwin],
        status: "succeeded",
        reason: "executed"
      ))
      lock_command = commands.find { |entry| entry.fetch(:command).first(2) == %w[bundle lock] }
      expect(lock_command).not_to be_nil
      expect(lock_command.fetch(:env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "false",
        "KETTLE_RB_DEV" => "false",
        "GALTZO_FLOSS_DEV" => "false",
        "SMORG_RB_DEV" => "false"
      )
    end
  end

  it "reports gemspec dependency sync through the install task" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-gemspec-sync", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: example.gemspec
                target: example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "template"
            spec.summary = "Template gem"
            spec.add_development_dependency "rake", "~> 13.0"
          end
        RUBY
      })
      command_runner = lambda do |_command, **|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "example.gemspec", skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "gemspec_dependency_sync",
        path: "example.gemspec",
        status: "applied",
        development_dependencies: ["rake"]
      )
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.add_development_dependency "rake", "~> 13.0"')
    end
  end

  it "ports old install post-template project cleanup and safety checks" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-post-processing", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "🥘 Example gem"
            spec.description = "Example description"
            spec.homepage = "\#{homepage}"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🔧"
          templates:
            root: packaged
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          # 🍲 Example

          | Runtime | Works |
          | --- | --- |
          | Works with MRI Ruby | [![ruby-2.7][💎ruby-2.7i]][🚎2.7] <br/> [![ruby-3.2][💎ruby-3.2i]][🚎3.2] <br/> [![ruby-current][💎ruby-c-i]][🚎current] |

          [💎ruby-2.7i]: https://img.shields.io/badge/Ruby-2.7-red.svg
          [💎ruby-3.2i]: https://img.shields.io/badge/Ruby-3.2-red.svg
          [💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-red.svg
          [🚎2.7]: https://github.com/example-org/example/actions/workflows/ruby-2.7.yml
          [🚎3.2]: https://github.com/example-org/example/actions/workflows/ruby-3.2.yml
          [🚎current]: https://github.com/example-org/example/actions/workflows/current.yml
        MARKDOWN
        ".github/workflows/ruby-3.2.yml" => "name: Ruby 3.2\n",
        "mise.toml" => "[tools]\nruby = \"3.4.1\"\n",
        ".ruby-version" => "3.4.1\n",
        ".tool-versions" => "ruby 3.4.1\n",
        ".env.local.example" => "KETTLE_RB_DEV=false\n",
        ".gitignore" => "tmp/\n",
      })
      command_runner = lambda do |_command, **|
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"FORGE_ORG" => "example-org"},
        run_options: {only: "README.md", skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "legacy_ruby_version_file_cleanup",
        status: "applied",
        removed_files: [".ruby-version", ".tool-versions"]
      )
      expect(install.fetch(:install_steps)).to include(
        name: "gemspec_homepage_literal",
        path: "example.gemspec",
        status: "applied",
        homepage: "https://github.com/example-org/example"
      )
      expect(install.fetch(:install_steps)).to include(
        name: "env_local_gitignore",
        path: ".gitignore",
        status: "applied"
      )
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "readme_gemspec_grapheme_sync",
        paths: ["README.md", "example.gemspec"],
        status: "applied",
        grapheme: "🔧"
      ))
      expect(File).not_to exist(File.join(root, ".ruby-version"))
      expect(File).not_to exist(File.join(root, ".tool-versions"))
      gemspec = File.read(File.join(root, "example.gemspec"))
      expect(gemspec).to include('spec.homepage = "https://github.com/example-org/example"')
      expect(gemspec).to include('spec.summary = "🔧 Example gem"')
      expect(gemspec).to include('spec.description = "🔧 Example description"')
      expect(File.read(File.join(root, ".gitignore"))).to include(".env.local")
      readme = File.read(File.join(root, "README.md"))
      expect(readme).to include("# 🔧 Example")
      expect(readme).not_to include("ruby-2.7")
      expect(readme).to include("ruby-3.2")
      expect(readme).not_to include("ruby-current")
      expect(readme).not_to include("[🚎current]:")
      expect(readme).to include("[🚎ruby-3.2-wf]:")
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        statuses: hash_including(
          "legacy_ruby_version_file_cleanup" => "applied",
          "readme_compatibility_badges" => satisfy { |status| %w[applied already_current].include?(status) },
          "readme_gemspec_grapheme_sync" => "applied",
          "gemspec_homepage_literal" => "applied",
          "env_local_gitignore" => "applied"
        )
      ))
      expect(install.fetch(:install_summary)).to include(
        steps: install.fetch(:install_steps).length,
        statuses: include("applied" => be >= 4),
        summary: include("install steps")
      )
    end
  end

  it "uses dotenv structural merge for environment template files" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-dotenv-template-merge", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: .env.local
                target: .env.local.example
        YAML
        "template/.env.local.example" => <<~ENV,
          # Shared development defaults
          KETTLE_RB_DEV=false
          DEBUG=false # keep debugging disabled by default
        ENV
        ".env.local.example" => <<~ENV,
          # Local documentation must survive
          KETTLE_RB_DEV=true
        ENV
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == ".env.local.example" }

      expect(report.fetch(:final_content)).to eq(<<~ENV)
        # Local documentation must survive
        KETTLE_RB_DEV=true
        DEBUG=false # keep debugging disabled by default
      ENV
    end
  end

  it "uses JSON structural merge for JSON template files" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-json-template-merge", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: devcontainer.json
                target: .devcontainer/devcontainer.json
        YAML
        "template/devcontainer.json.example" => <<~JSON,
          {
            "name": "template",
            "features": {
              "ghcr.io/devcontainers/features/git:1": {}
            }
          }
        JSON
        ".devcontainer/devcontainer.json" => <<~JSON,
          {
            "name": "destination"
          }
        JSON
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == ".devcontainer/devcontainer.json" }

      expect(report.fetch(:final_content)).to include('"name": "destination"')
      expect(report.fetch(:final_content)).to include('"ghcr.io/devcontainers/features/git:1": {}')
    end
  end

  it "uses JSONC structural merge for JSONC template files" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-jsonc-template-merge", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: settings.jsonc
                target: .vscode/settings.jsonc
        YAML
        "template/settings.jsonc.example" => <<~JSONC,
          {
            // Shared editor defaults
            "editor.tabSize": 2,
            "files.trimTrailingWhitespace": true
          }
        JSONC
        ".vscode/settings.jsonc" => <<~JSONC,
          {
            // Local documentation must survive
            "editor.tabSize": 4
          }
        JSONC
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == ".vscode/settings.jsonc" }

      expect(report.fetch(:final_content)).to eq(<<~JSONC)
        {
          // Local documentation must survive
          "editor.tabSize": 4,
          "files.trimTrailingWhitespace": true
        }
      JSONC
    end
  end

  it "uses RBS structural merge for RBS template files" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rbs-template-merge", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: sig/example/version.rbs
                target: sig/example/version.rbs
        YAML
        "template/sig/example/version.rbs.example" => <<~RBS,
          module Example
            module Version
              VERSION: String
            end

            VERSION: String
          end
        RBS
        "sig/example/version.rbs" => <<~RBS,
          module Example
            module Version
              VERSION: "1.2.3"
            end
          end
        RBS
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == "sig/example/version.rbs" }

      expect(report.fetch(:final_content)).to include('VERSION: "1.2.3"')
      expect(report.fetch(:final_content)).to include("VERSION: String")
    end
  end

  it "loudly rejects explicit Bash structural routing when the node parser is unavailable" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-bash-template-gate", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            scripts:
              setup:
                strategy: merge
                file_type: bash
          templates:
            root: template
            apply: true
            entries:
              - source: setup
                target: scripts/setup
        YAML
        "template/setup.example" => <<~BASH,
          #!/usr/bin/env bash
          bundle install
        BASH
        "scripts/setup" => <<~BASH,
          #!/usr/bin/env bash
          bundle check || bundle install
        BASH
      })
      availability = Bash::Merge::Availability.new(
        grammar_path: nil,
        language_pack_process: true,
        node_parser: false,
        diagnostics: [{ kind: "bash_node_parser_unavailable", message: "missing node adapter" }]
      )
      allow(Bash::Merge).to receive(:availability).and_return(availability)

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /failed to merge bash template scripts\/setup: bash structural merge is unavailable/)
    end
  end

  it "refreshes mise trust after templating mise.toml when mise is available" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-mise-trust", tmp_root) do |root|
      fake_bin = File.join(root, "fake-bin")
      FileUtils.mkdir_p(fake_bin)
      fake_mise = File.join(fake_bin, "mise")
      File.write(fake_mise, "#!/usr/bin/env sh\nexit 0\n")
      FileUtils.chmod(0o755, fake_mise)
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - mise.toml
        YAML
        "template/mise.toml.example" => <<~TOML,
          [tools]
          ruby = "3.4.1"
        TOML
      })

      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end
      env = {"PATH" => "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", "")}"}

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: env,
        run_options: {only: "mise.toml", bootstrap_mode: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(
        name: "mise_trust",
        path: "mise.toml",
        command: ["mise", "trust", "-C", root],
        status: "succeeded",
        reason: "executed",
        exitstatus: 0
      )
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        statuses: hash_including("mise_trust" => "succeeded")
      ))
      expect(commands).to include(["mise", "trust", "-C", root])
    end
  end

  it "bootstraps version_gem touchpoints before bundled setup" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-bootstrap", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: example-gem.gemspec
                target: example-gem.gemspec
        YAML
        "template/example-gem.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.9"
          end
        RUBY
      })
      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "example-gem.gemspec", skip_commit: true},
        command_runner: command_runner
      )
      version_path = File.join(root, "lib", "example/gem/version.rb")
      entrypoint_path = File.join(root, "lib", "example/gem.rb")

      expect(install.fetch(:install_steps)).to include(
        name: "version_gem_bootstrap",
        status: "applied",
        changed_files: ["lib/example/gem/version.rb", "lib/example/gem.rb", "sig/example/gem/version.rbs"],
        version_path: "lib/example/gem/version.rb",
        entrypoint_path: "lib/example/gem.rb",
        signature_path: "sig/example/gem/version.rbs"
      )
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        statuses: hash_including("version_gem_bootstrap" => "applied")
      ))
      expect(File.read(version_path)).to include("module Example")
      expect(File.read(version_path)).to include("module Gem")
      expect(File.read(version_path)).to include('VERSION = "1.2.3"')
      expect(File.read(entrypoint_path)).to include('require "version_gem"')
      expect(File.read(entrypoint_path)).to include('require_relative "gem/version"')
      expect(File.read(entrypoint_path)).to include("Example::Gem::Version.class_eval do")
      signature = File.read(File.join(root, "sig", "example", "gem", "version.rbs"))
      expect(signature).to include("module Example")
      expect(signature).to include("module Gem")
      expect(signature).to include("module Version")
      expect(signature).to include("VERSION: String")
      expect(commands).to eq([
        %w[bundle binstubs --all],
        ["bundle", "exec", "kettle-jem", "--skip-commit", "--only", "example-gem.gemspec"],
      ])
    end
  end

  it "places version_gem entrypoint requires from top-level Ruby structure" do
    content = <<~RUBY
      # frozen_string_literal: true

      def setup
        require "version_gem"
      end
    RUBY

    updated = described_class.send(
      :version_gem_bootstrap_entrypoint_content,
      content,
      namespace: "Example::Gem",
      entrypoint_require: "example/gem"
    )

    expect(updated).to start_with(<<~RUBY)
      # frozen_string_literal: true

      require "version_gem"
      require_relative "gem/version"

      def setup
        require "version_gem"
      end
    RUBY
    expect(updated).to include("Example::Gem::Version.class_eval do")
  end

  it "anchors version_gem relative entrypoint requires after an existing top-level version_gem require" do
    content = <<~RUBY
      # frozen_string_literal: true

      require "version_gem"

      module Example
        module Gem
        end
      end
    RUBY

    updated = described_class.send(
      :version_gem_bootstrap_entrypoint_content,
      content,
      namespace: "Example::Gem",
      entrypoint_require: "example/gem"
    )

    expect(updated).to include(<<~RUBY)
      require "version_gem"
      require_relative "gem/version"

      module Example
    RUBY
  end

  it "reports setup execution context without load-path inspection" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-setup-context-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(env).to eq("BUNDLE_GEMFILE" => File.join(root, "Gemfile"))
        expect(quiet).to be(true)
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      bundled = described_class.setup_project(
        root,
        env: {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")},
        run_options: {only: "bin/setup", quiet: true},
        command_runner: command_runner
      )
      expect(bundled.fetch(:setup_execution_context)).to eq(
        bundled: true,
        source: "BUNDLE_GEMFILE",
        bundle_gemfile: File.join(root, "Gemfile")
      )
      expect(bundled.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        status: "already_bundled",
        bundle_gemfile: File.join(root, "Gemfile")
      )

      bootstrap = described_class.setup_project(
        root,
        env: {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")},
        run_options: {only: "bin/setup", bootstrap_mode: true}
      )
      expect(bootstrap.fetch(:setup_execution_context)).to eq(
        bundled: false,
        source: "bootstrap_mode",
        bundle_gemfile: nil
      )
    end
  end

  it "preserves configured README sections during merge template application" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            preserve_sections:
              - synopsis
              - basic usage
              - custom section
            preserve_patterns:
              - "note:*"
            section_aliases:
              usage: basic usage
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          # 1️⃣ Example

          ## Synopsis

          Destination synopsis.

          ### Details

          Destination nested detail.

          ```console
          # DANGER: keep this code comment inside the Synopsis branch.
          bundle exec rake kettle:jem:install allowed=true force=true
          ```

          ## Usage

          Destination usage.

          ## Custom Section

          Destination custom.

          ## Note: Local

          Destination note.

          ## Installation

          Old install.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Template synopsis.

          ## 🔧 Basic Usage

          Template usage.

          ## Custom Section

          Template custom.

          ## Note: Local

          Template note.

          ## Installation

          Template install.
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      readme_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = readme_report.fetch(:final_content)
      expect(final_content).to include("# 💎 Example")
      expect(final_content).to include("## 🌻 Synopsis\n\nDestination synopsis.")
      expect(final_content).to include("### Details\n\nDestination nested detail.")
      expect(final_content).to include("# DANGER: keep this code comment inside the Synopsis branch.")
      expect(final_content).to include("bundle exec rake kettle:jem:install allowed=true force=true")
      expect(final_content).to include("## 🔧 Basic Usage\n\nDestination usage.")
      expect(final_content).to include("## Custom Section\n\nDestination custom.")
      expect(final_content).to include("## Note: Local\n\nDestination note.")
      expect(final_content).to include("## Installation\n\nTemplate install.")
      expect(final_content).not_to include("Template synopsis.")
      expect(final_content).not_to include("Template usage.")
      expect(final_content).not_to include("Template custom.")
      expect(final_content).not_to include("Template note.")
      expect(File.read(File.join(root, "README.md"))).to eq(final_content)
    end
  end

  it "merges YAML and TOML template applications with destination values" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            config:
              explicit.yml:
                strategy: merge
                file_type: yaml
          templates:
            root: template
            apply: true
            entries:
              - .github/dependabot.yml
              - config/settings.yml
              - config/tool.toml
              - config/explicit.yml
        YAML
        ".github/dependabot.yml" => <<~YAML,
          updates:
            - package-ecosystem: bundler
              directory: /
          version: 1
        YAML
        "config/settings.yml" => <<~YAML,
          engines:
            - ruby
          nested:
            value: destination
          version: 1
        YAML
        "config/tool.toml" => <<~TOML,
          title = "destination"

          [settings]
          retries = 1
        TOML
        "config/explicit.yml" => <<~YAML,
          destination_only: keep
          nested:
            value: destination
        YAML
        "template/.github/dependabot.yml.example" => <<~YAML,
          schedule:
            interval: weekly
          updates:
            - package-ecosystem: github-actions
              directory: /
          version: 2
        YAML
        "template/config/settings.yml.example" => <<~YAML,
          engines:
            - ruby
            - jruby
          nested:
            template_only: true
            value: template
          version: 2
        YAML
        "template/config/tool.toml.example" => <<~TOML,
          title = "template"

          [settings]
          retries = 3
          timeout = 30
        TOML
        "template/config/explicit.yml.example" => <<~YAML,
          nested:
            value: template
            template_only: true
          template_only: added
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      dependabot_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_github_dependabot_yml"
      end
      yaml_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      toml_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_tool_toml"
      end
      explicit_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_explicit_yml"
      end

      expect(YAML.safe_load(dependabot_report.fetch(:final_content))).to eq(
        "schedule" => { "interval" => "weekly" },
        "updates" => [
          {
            "directory" => "/",
            "package-ecosystem" => "bundler",
          },
        ],
        "version" => 1
      )
      expect(YAML.safe_load(yaml_report.fetch(:final_content))).to eq(
        "engines" => ["ruby"],
        "nested" => {
          "template_only" => true,
          "value" => "destination",
        },
        "version" => 1
      )
      expect(toml_report.fetch(:final_content)).to eq(<<~TOML)
        title = "destination"

        [settings]
        retries = 1
        timeout = 30
      TOML
      expect(YAML.safe_load(explicit_report.fetch(:final_content))).to eq(
        "destination_only" => "keep",
        "nested" => {
          "template_only" => true,
          "value" => "destination",
        },
        "template_only" => "added"
      )
      expect(explicit_report.dig(:metadata, :template_source_preference)).to include(file_type: "yaml")
    end
  end

  it "restores documentation comments from YAML templates when destination config stripped them" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-yaml-template-comment-restore", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - .kettle-jem.yml
        YAML
        "template/.kettle-jem.yml.example" => <<~YAML,
          # kettle-jem configuration file
          templates:
            # Template root directory.
            root: template
            # Apply templates during setup.
            apply: true
            # Template entries to apply.
            entries:
              - .kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_kettle_jem_yml"
      end
      final_content = report.fetch(:final_content)

      expect(final_content).to include("# kettle-jem configuration file")
      expect(final_content).to include("# Template root directory.")
      expect(final_content).to include("# Apply templates during setup.")
      expect(final_content).to include("# Template entries to apply.")
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(final_content)
    end
  end

  it "allows YAML template recipes to keep git-style destination comment policy" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-yaml-template-comment-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - config/settings.yml
          files:
            config:
              settings.yml:
                strategy: merge
                file_type: yaml
                comment_merge_policy: preserve_destination
        YAML
        "config/settings.yml" => <<~YAML,
          project:
            name: example
        YAML
        "template/config/settings.yml.example" => <<~YAML,
          # project settings
          project:
            # Project display name.
            name: example
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      final_content = report.fetch(:final_content)

      expect(final_content).not_to include("# project settings")
      expect(final_content).not_to include("# Project display name.")
      expect(final_content).to include("project:")
      expect(final_content).to include("  name: example")
    end
  end

  it "merges Ruby-family template applications with destination declarations and DSL calls" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ruby-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
              - Rakefile
              - lib/example.rb
        YAML
        "Gemfile" => <<~RUBY,
          source "https://rubygems.org"
          gem "rspec"
          gem "example", path: "../example"
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
        "Rakefile" => <<~RUBY,
          desc "Default"
          task :default do
            puts "destination"
          end
        RUBY
        "lib/example.rb" => <<~RUBY,
          require "set"

          class Existing
            def keep
              :destination
            end
          end
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          source "https://gem.coop"
          gemspec
          eval_gemfile "gemfiles/modular/style.gemfile" if ENV.fetch("K_JEM_STYLE", "false").casecmp("true").zero?
          gem "appraisal"
          gem "example", path: "."
          gem "rake"
        RUBY
        "template/Rakefile.example" => <<~RUBY,
          desc "Default"
          task :default do
            puts "template"
          end

          desc "CI"
          task :ci do
            sh "bundle exec rspec"
          end
        RUBY
        "template/lib/example.rb.example" => <<~RUBY,
          require "json"

          class Existing
            def keep
              :template
            end
          end

          class Added
            def call
              :template_only
            end
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      ruby_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_lib_example_rb"
      end
      gemfile_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Gemfile"
      end
      rakefile_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Rakefile"
      end
      final_content = ruby_report.fetch(:final_content)

      expect(final_content).to include('require "set"')
      expect(final_content).not_to include('require "json"')
      expect(final_content).to include("def keep\n    :destination\n  end")
      expect(final_content).to include("class Added")
      expect(final_content).to include(":template_only")
      expect(File.read(File.join(root, "lib/example.rb"))).to eq(final_content)

      gemfile_content = gemfile_report.fetch(:final_content)
      expect(gemfile_content).to include('source "https://gem.coop"')
      expect(gemfile_content).to include("gemspec")
      expect(gemfile_content).to include('eval_gemfile "gemfiles/modular/style.gemfile" if ENV.fetch("K_JEM_STYLE", "false").casecmp("true").zero?')
      expect(gemfile_content).to include('gem "rspec"')
      expect(gemfile_content).to include('gem "rake"')
      expect(gemfile_content).not_to include('gem "appraisal"')
      expect(gemfile_content).not_to include('gem "example"')
      expect(gemfile_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "gemfile",
        operations: include(
          include(operation: "delete_dependency_declarations", deleted_gems: contain_exactly("appraisal", "example"))
        )
      )

      rakefile_content = rakefile_report.fetch(:final_content)
      expect(rakefile_content.scan(/task\s+:default/).size).to eq(1)
      expect(rakefile_content).to include('puts "destination"')
      expect(rakefile_content).to include("task :ci")
    end
  end

  it "passes Ruby method move policy through per-file template strategy config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ruby-method-move-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            lib:
              example.rb:
                strategy: merge
                file_type: ruby
                method_move_policy: destination_order
          templates:
            root: template
            apply: true
            entries:
              - lib/example.rb
        YAML
        "lib/example.rb" => <<~RUBY,
          class Greeter
            def beta
              :beta
            end

            def alpha
              :alpha
            end
          end
        RUBY
        "template/lib/example.rb.example" => <<~RUBY,
          class Greeter
            def alpha
              :template_alpha
            end

            def beta
              :template_beta
            end

            def gamma
              :gamma
            end
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |entry|
        entry.fetch(:recipe_name) == "template_source_application_lib_example_rb"
      end
      final_content = report.fetch(:final_content)

      expect(final_content.index("def beta")).to be < final_content.index("def alpha")
      expect(final_content.scan("def alpha").size).to eq(1)
      expect(final_content.scan("def beta").size).to eq(1)
      expect(final_content.scan("def gamma").size).to eq(1)
      expect(report.dig(:metadata, :template_source_preference)).to include(
        file_type: "ruby",
        method_move_policy: "destination_order"
      )
    end
  end

  it "applies Appraisals template policy with self-dependency and minimum Ruby pruning" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisals-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "Appraisals" => <<~RUBY,
          # frozen_string_literal: true

          appraise "ruby-2-7" do
            gem "example"
            eval_gemfile "gemfiles/modular/x_std_libs/r2/libs.gemfile"
          end

          appraise "ruby-3-2" do
            gem "example", path: "../example"
            eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "coverage" do
            gem "simplecov"
          end
        RUBY
        "template/Appraisals.example" => <<~RUBY,
          # frozen_string_literal: true

          appraise "ruby-3-2" do
            eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "path-gems" do
            %w[
              example
              support-gem
            ].each do |gem_name|
              gem gem_name, path: "../\#{gem_name}"
            end
          end

          appraise "style" do
            eval_gemfile "gemfiles/modular/style.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      appraisals_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Appraisals"
      end
      appraisals_content = appraisals_report.fetch(:final_content)

      expect(appraisals_content).not_to include('appraise "ruby-2-7"')
      expect(appraisals_content).not_to include('gem "example"')
      expect(appraisals_content).to include('appraise "ruby-3-2"')
      expect(appraisals_content).to include('eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"')
      expect(appraisals_content).to include('appraise "coverage"')
      expect(appraisals_content).to include('gem "simplecov"')
      expect(appraisals_content).to include('appraise "path-gems"')
      expect(appraisals_content).to include("support-gem")
      expect(appraisals_content).not_to match(/^\s+example$/)
      expect(appraisals_content).to include('appraise "style"')
      expect(appraisals_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "appraisals",
        operations: include(
          include(operation: "merge_appraisal_blocks", inserted_appraisals: include("style")),
          include(operation: "delete_self_dependency_declarations", deleted_dependency_count: 2),
          include(operation: "prune_minimum_ruby_appraisals", deleted_appraisals: include("ruby-2-7"))
        )
      )
      expect(File.read(File.join(root, "Appraisals"))).to eq(appraisals_content)
    end
  end

  it "ports old Appraisals template behavior without losing custom destination blocks" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:appraisals_custom_blocks)

    Dir.mktmpdir("kettle-jem-old-appraisals-policy", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "test gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "Appraisals" => <<~RUBY,
          appraise "#{contract_case.fetch(:destination_appraisal)}" do
            gem "local-only"
          end
        RUBY
        "template/Appraisals.example" => <<~RUBY,
          appraise "#{contract_case.fetch(:template_appraisal)}" do
            gemfile "gemfiles/ruby_4.0.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = report.fetch(:final_content)

      expect(appraisals_content).to include(%(appraise "#{contract_case.fetch(:template_appraisal)}"))
      expect(appraisals_content).to include(%(appraise "#{contract_case.fetch(:destination_appraisal)}"))
      expect(appraisals_content).to include('gem "local-only"')
      expect(report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(
          operation: "merge_appraisal_blocks",
          inserted_appraisals: include(contract_case.fetch(:template_appraisal)),
          preserved_destination_appraisals: include(contract_case.fetch(:destination_appraisal))
        )
      )
    end
  end

  it "prunes GitHub workflow appraisal matrix entries below minimum Ruby" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisal-workflow-prune", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - .github/workflows/appraisals.yml
        YAML
        "template/.github/workflows/appraisals.yml.example" => <<~YAML,
          name: Appraisals
          on:
            pull_request:
          jobs:
            test:
              strategy:
                matrix:
                  include:
                    - ruby: "2.7"
                      appraisal: "ruby-2-7"
                      exec_cmd: "rake spec"
                    - ruby: "3.2"
                      appraisal: "ruby-3-2"
                      exec_cmd: "rake spec"
              steps:
                - run: bundle exec appraisal ${{ matrix.appraisal }} bundle exec ${{ matrix.exec_cmd }}
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      workflow_report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/appraisals.yml"
      end
      workflow_content = workflow_report.fetch(:final_content)

      expect(workflow_content).not_to include('ruby: "2.7"')
      expect(workflow_content).not_to include('appraisal: "ruby-2-7"')
      expect(workflow_content).to include('ruby: "3.2"')
      expect(workflow_content).to include('appraisal: "ruby-3-2"')
    end
  end

  it "ports old modular Gemfile ruby-bucket eval_gemfile replacement" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:modular_gemfile_ruby_bucket)
    relative_path = contract_case.fetch(:path)

    Dir.mktmpdir("kettle-jem-old-modular-gemfile-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - #{relative_path}
        YAML
        relative_path => contract_case.fetch(:obsolete_eval_paths).map { |path| %(eval_gemfile "#{path}") }.join("\n") +
          "\n" + %(eval_gemfile "../../benchmark/r4/v0.5.gemfile"\n),
        "template/#{relative_path}.example" => contract_case.fetch(:template_eval_paths).map do |path|
          %(eval_gemfile "#{path}")
        end.join("\n") + "\n"
      })

      apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == relative_path }
      content = report.fetch(:final_content)

      contract_case.fetch(:template_eval_paths).each do |path|
        expect(content.scan(%(eval_gemfile "#{path}")).size).to eq(1)
      end
      contract_case.fetch(:obsolete_eval_paths).each do |path|
        expect(content).not_to include(%(eval_gemfile "#{path}"))
      end
      expect(File.read(File.join(root, relative_path))).to eq(content)
    end
  end

  it "removes the destination package from the main Gemfile" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-self-dependency", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example Gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
        YAML
        "Gemfile" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"
          gem "example-gem"
          gem "destination-only"
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          dependency_root = ENV["DEPENDENCY_ROOT"].to_s.strip

          if !dependency_root.empty?
            %w[
              example-gem
              helper-gem
            ].each do |gem_name|
              gem gem_name, path: File.join(dependency_root, gem_name)
            end
          else
            gem "example-gem", ">= 1.0"
          end

          gem "shared-tool"
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Gemfile" }
      content = report.fetch(:final_content)

      expect(content).to include("helper-gem")
      expect(content).to include('gem "shared-tool"')
      expect(content).not_to match(/^\s+example-gem$/)
      expect(content).not_to match(/^\s*gem\s+["']example-gem["']/)
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "merges modular local Gemfile dependency lists while removing the destination package" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-local-gemfile-policy", tmp_root) do |root|
      write_tree(root, {
        "kettle-jem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-jem"
            spec.summary = "Kettle Jem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - gemfiles/modular/templating_local.gemfile
        YAML
        "gemfiles/modular/templating_local.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          local_gems = %w[
            local-only
            rubocop-ruby2_3
            kettle-jem
          ]
        RUBY
        "template/gemfiles/modular/templating_local.gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          local_gems = %w[
            tree_haver
            ast-merge
            rubocop-ruby2_4
            kettle-jem
          ]
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/templating_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).to include("tree_haver")
      expect(content).to include("ast-merge")
      expect(content).to include("rubocop-ruby2_4")
      expect(content).to include("local-only")
      expect(content).not_to include("rubocop-ruby2_3")
      expect(content).not_to include("kettle-jem")
      expect(File.read(File.join(root, "gemfiles/modular/templating_local.gemfile"))).to eq(content)
    end
  end

  it "treats packaged local Gemfiles as template-owned by default" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-local-gemfile-default-strategy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/style_local.gemfile
        YAML
        "gemfiles/modular/style_local.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          local_gems = %w[
            local-only
            rubocop-ruby2_3
          ]
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/style_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(report.dig(:metadata, :template_source_preference)).to include(strategy: "accept_template")
      expect(content).to include("rubocop-ruby")
      expect(content).not_to include("local-only")
      expect(content).not_to include("rubocop-ruby2_3")
    end
  end

  it "removes the destination package from arbitrary modular Gemfile dependency lists" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-modular-gemfile-self-dependency", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example Gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - gemfiles/modular/debug.gemfile
          files:
            gemfiles:
              modular:
                debug.gemfile:
                  strategy: accept_template
        YAML
        "gemfiles/modular/debug.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          gem "existing"
        RUBY
        "template/gemfiles/modular/debug.gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          dependency_root = ENV["DEPENDENCY_ROOT"].to_s.strip

          if !dependency_root.empty?
            %w[
              debug
              example-gem
            ].each do |gem_name|
              gem gem_name, path: File.join(dependency_root, gem_name)
            end
          else
            gem "example-gem", ">= 1.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/debug.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).to include("debug")
      expect(content).not_to match(/^\s+example-gem$/)
      expect(content).not_to match(/^\s*gem\s+["']example-gem["']/)
      expect(File.read(File.join(root, "gemfiles/modular/debug.gemfile"))).to eq(content)
    end
  end

  it "generates shunted.gemfile entries from resolved development dependency Ruby floors" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    resolver = Class.new do
      def versions(gem_name, requirements: nil)
        case gem_name
        when "debug"
          [{ number: "1.9.2", ruby_version: ">= 3.3" }]
        when "rake"
          [{ number: "13.2.1", ruby_version: ">= 2.6" }]
        else
          []
        end
      end

      def min_ruby_version(gem_name, _version)
        gem_name == "debug" ? Gem::Version.new("3.3") : Gem::Version.new("2.6")
      end

      def parse_min_ruby(requirement)
        Kettle::Jem::RubyGemsResolver.new.parse_min_ruby(requirement)
      end
    end.new

    Dir.mktmpdir("kettle-jem-shunted-gemfile", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 3.2"
            spec.add_development_dependency "debug", "~> 1.9"
            spec.add_development_dependency "rake", "~> 13.0"
          end
        RUBY
        "gemfiles/modular/shunted.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          # local notes remain outside the generated block
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: { rubygems_resolver: resolver })
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/shunted.gemfile"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:request_envelope).fetch(:request).fetch(:provider_family)).to eq("ruby")
      expect(report.fetch(:request_envelope).fetch(:request).fetch(:provider_backend)).to eq("ast-crispr-ruby-prism")
      expect(report.fetch(:report_envelope).fetch(:report).fetch(:step_reports).first.fetch(:metadata).fetch(:provider_family)).to eq("ruby")
      expect(content).to include("# local notes remain outside the generated block")
      expect(content).to include('gem "debug", "~> 1.9" # ruby >= 3.3')
      expect(content).not_to include('gem "rake"')
      expect(File.read(File.join(root, "gemfiles/modular/shunted.gemfile"))).to eq(content)

      described_class.apply_project(root, env: {}, run_options: { rubygems_resolver: resolver })
      reapplied = File.read(File.join(root, "gemfiles/modular/shunted.gemfile"))
      expect(reapplied.lines.count { |line| line.include?(Kettle::Jem::MANAGED_BLOCK_OPEN) }).to be <= 1
      expect(reapplied.lines.count { |line| line.include?(Kettle::Jem::MANAGED_BLOCK_CLOSE) }).to be <= 1
      expect(reapplied).to include("# local notes remain outside the generated block")

      described_class.apply_project(root, env: {}, run_options: { rubygems_resolver: resolver })
      expect(File.read(File.join(root, "gemfiles/modular/shunted.gemfile"))).to eq(reapplied)
    end
  end

  it "ports old Gemfile comment preservation, token resolution, and commented dependency policy" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:gemfile_comment_and_token_policy)
    important_block = <<~COMMENT
      #### IMPORTANT #######################################################
      # #{contract_case.fetch(:important_phrase)}; Gemfile is NOT loaded in CI #
      ####################################################### IMPORTANT ####
    COMMENT

    Dir.mktmpdir("kettle-jem-old-gemfile-comment-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{contract_case.fetch(:resolved_gem_name)}"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
              - gemfiles/modular/debug.gemfile
        YAML
        "Gemfile" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          #{important_block}
          # Include dependencies from #{contract_case.fetch(:resolved_gem_name)}.gemspec
          gemspec
        RUBY
        "gemfiles/modular/debug.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          # Ex-Standard Library gems
          gem "#{contract_case.fetch(:commented_dependency)}", "~> 1.15", ">= 1.15.2" # removed from stdlib in 3.5

          platform :mri do
            gem "#{contract_case.fetch(:active_dependency)}", ">= 1.1"
          end
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          #{important_block}
          # Include dependencies from #{contract_case.fetch(:token)}.gemspec
          gemspec
        RUBY
        "template/gemfiles/modular/debug.gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          # Ex-Standard Library gems
          # #{contract_case.fetch(:commented_dependency)} is included in main Gemfile (and unlocked_deps Appraisal), so it can't be included here.
          # gem "#{contract_case.fetch(:commented_dependency)}", "~> 1.15", ">= 1.15.2" # removed from stdlib in 3.5

          platform :mri do
            gem "#{contract_case.fetch(:active_dependency)}", ">= 1.1"
          end
        RUBY
      })

      first_apply = described_class.apply_project(root, env: {})
      second_apply = described_class.apply_project(root, env: {})
      gemfile_report = first_apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "Gemfile" }
      debug_report = first_apply.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == "gemfiles/modular/debug.gemfile"
      end
      gemfile_content = gemfile_report.fetch(:final_content)
      debug_content = debug_report.fetch(:final_content)

      expect(gemfile_content).to include(contract_case.fetch(:important_phrase))
      expect(gemfile_content).to include("dependencies from #{contract_case.fetch(:resolved_gem_name)}.gemspec")
      expect(gemfile_content).not_to include(contract_case.fetch(:token))
      expect(debug_content).to include("#{contract_case.fetch(:commented_dependency)} is included in main Gemfile")
      expect(debug_content).to include(%(# gem "#{contract_case.fetch(:commented_dependency)}", "~> 1.15", ">= 1.15.2"))
      expect(debug_content).not_to match(/^gem "#{Regexp.escape(contract_case.fetch(:commented_dependency))}"/)
      expect(debug_content.scan(/^\s*# gem "#{Regexp.escape(contract_case.fetch(:commented_dependency))}"/).count).to eq(1)
      expect(debug_content.scan(/^\s*gem "#{Regexp.escape(contract_case.fetch(:active_dependency))}"/).count).to eq(1)
      expect(File.read(File.join(root, "Gemfile"))).to eq(gemfile_content)
      expect(File.read(File.join(root, "gemfiles/modular/debug.gemfile"))).to eq(debug_content)
      expect(second_apply.fetch(:changed_files)).not_to include("Gemfile", "gemfiles/modular/debug.gemfile")
    end
  end

  it "normalizes preserved gemspec lines to the template block receiver" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-receiver-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 3.2"
            gem.add_runtime_dependency "json", ">= 2.7"
            gem.add_development_dependency "rubocop", "~> 1.70"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 3.1"
            spec.add_runtime_dependency "json", ">= 2.0"
            spec.add_development_dependency "rspec", "~> 3.13"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include('spec.summary = "Real summary"')
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 3.2"')
      expect(gemspec_content).to include('spec.add_runtime_dependency "json", ">= 2.7"')
      expect(gemspec_content).to include('spec.add_development_dependency "rubocop", "~> 1.70"')
      expect(gemspec_content).not_to include("gem.summary")
      expect(gemspec_content).not_to include("gem.add_runtime_dependency")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "gemspec",
        operations: include(
          include(operation: "preserve_project_fields", preserved_fields: include("required_ruby_version", "summary")),
          include(operation: "preserve_dependency_declarations", preserved_dependencies: include("json", "rubocop")),
          include(operation: "normalize_gemspec_receiver", from: "gem", to: "spec")
        )
      )
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "inlines gemspec version loading when minimum Ruby is at least 3.1" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-modern-version-loader-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          # coding: utf-8
          # frozen_string_literal: true

          gem_version =
            if Gem.ruby_version >= Gem::Version.new("3.1")
              Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/my/gem/version.rb", mod) }::My::Gem::Version::VERSION
            else
              lib = File.expand_path("lib", __dir__)
              $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
              require "my/gem/version"
              My::Gem::Version::VERSION
            end

          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = gem_version
            gem.summary = "Modern loader"
            gem.required_ruby_version = ">= 3.2"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY,
          # coding: utf-8
          # frozen_string_literal: true

          gem_version =
            if Gem.ruby_version >= Gem::Version.new("3.1")
              Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/{KJ|GEM_NAME_PATH}/version.rb", mod) }::{KJ|NAMESPACE}::Version::VERSION
            else
              lib = File.expand_path("lib", __dir__)
              $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
              require "{KJ|GEM_NAME_PATH}/version"
              {KJ|NAMESPACE}::Version::VERSION
            end

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = gem_version
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).not_to include("gem_version =")
      expect(gemspec_content).not_to include('if RUBY_VERSION >= "3.1"')
      expect(gemspec_content).not_to include("Gemspec/RubyVersionGlobalsUsage")
      expect(gemspec_content).not_to include("$LOAD_PATH.unshift(lib)")
      expect(gemspec_content).not_to include('require "my/gem/version"')
      expect(gemspec_content).to include('spec.version = Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/my/gem/version.rb", mod) }::My::Gem::Version::VERSION')
      version_loader_operation = gemspec_report.dig(
        :report_envelope,
        :report,
        :step_reports,
        0,
        :metadata,
        :ruby_template_policy,
        :operations,
      ).find { |operation| operation[:operation] == "rewrite_version_loader" }
      expect(version_loader_operation).to include(mode: "modern", legacy_preamble_removed: true)
      expect(Gem::Version.new(version_loader_operation.fetch(:min_ruby))).to be >= Gem::Version.new("3.1")
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps gemspec legacy version loading when minimum Ruby is below 3.1" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-legacy-version-loader-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = "0.1.0"
            gem.summary = "Legacy loader"
            gem.required_ruby_version = ">= 3.0"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include("gem_version =")
      expect(gemspec_content).to include('if Gem.ruby_version >= Gem::Version.new("3.1")')
      expect(gemspec_content).not_to include("Gemspec/RubyVersionGlobalsUsage")
      expect(gemspec_content).to include('require "my/gem/version"')
      expect(gemspec_content).to include("My::Gem::Version::VERSION")
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "rewrite_version_loader", min_ruby: "3.0", mode: "legacy", legacy_preamble_present: true)
      )
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "preserves missing runtime gemspec dependencies above the development dependency separator" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-runtime-dependency-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 4.0"
            gem.add_dependency("json", "~> 2.10")
            gem.add_development_dependency("rubocop", "~> 1.70")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 4.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.9")

            # NOTE: It is preferable to list development dependencies in the gemspec due to increased
            #       visibility and discoverability.

            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)
      runtime_index = gemspec_content.index(%(spec.add_dependency("json", "~> 2.10")))
      separator_index = gemspec_content.index("# NOTE: It is preferable")
      development_index = gemspec_content.index(%(spec.add_development_dependency("rubocop", "~> 1.70")))

      expect(gemspec_content).to include(%(spec.add_dependency("json", "~> 2.10")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("rubocop", "~> 1.70")))
      expect(runtime_index).to be < separator_index
      expect(development_index).to be > separator_index
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "sorts runtime gemspec dependencies with RuboCop-compatible gem name ordering" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-rubocop-order-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 4.0"
            gem.add_dependency("rspec", "~> 3.0")
            gem.add_dependency("rspec-block_is_expected", "~> 1.0")
            gem.add_dependency("rspec-pending_for", "~> 0.1")
            gem.add_dependency("rspec-stubbed_env", "~> 1.0")
            gem.add_dependency("rspec_junit_formatter", "~> 0.6")
            gem.add_dependency("silent_stream", "~> 1.0")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 4.0"
            spec.add_dependency("rspec", "~> 3.0")
            spec.add_dependency("rspec-block_is_expected", "~> 1.0")
            spec.add_dependency("rspec-pending_for", "~> 0.1")
            spec.add_dependency("rspec-stubbed_env", "~> 1.0")
            spec.add_dependency("rspec_junit_formatter", "~> 0.6")
            spec.add_dependency("silent_stream", "~> 1.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)
      junit_index = gemspec_content.index(%(spec.add_dependency("rspec_junit_formatter", "~> 0.6")))
      pending_index = gemspec_content.index(%(spec.add_dependency("rspec-pending_for", "~> 0.1")))
      stubbed_index = gemspec_content.index(%(spec.add_dependency("rspec-stubbed_env", "~> 1.0")))

      expect(junit_index).to be < pending_index
      expect(pending_index).to be < stubbed_index
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "ports old gemspec emoji field replacement without duplicating the Gem::Specification block" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:gemspec_emoji_block_integrity)
    package_name = contract_case.fetch(:package_name)

    Dir.mktmpdir("kettle-jem-old-gemspec-emoji-policy", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          # coding: utf-8
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.version = "2.0.0"
            spec.authors = ["Kettle Maintainer"]
            spec.email = ["maintainer@example.com"]
            spec.summary = "#{contract_case.fetch(:summary)}"
            spec.description = "#{contract_case.fetch(:description)}"
            spec.homepage = "https://github.com/structuredmerge/#{package_name}"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 4.0"
            spec.require_paths = ["lib"]
            spec.bindir = "exe"
            spec.executables = ["#{contract_case.fetch(:executable)}"]
            spec.add_development_dependency("gitmoji-regex", "~> 1.0")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY,
          # coding: utf-8
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "1.0.0"
            spec.authors = ["Template Author"]
            spec.email = ["template@example.com"]
            spec.summary = "🍲 "
            spec.description = "🍲 "
            spec.homepage = "https://github.com/structuredmerge/{KJ|GEM_NAME}"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 2.3.0"
            spec.require_paths = ["lib"]
            spec.bindir = "exe"
            spec.executables = []
            spec.add_development_dependency("{KJ|GEM_NAME}", "~> 1.0")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "#{package_name}.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content.scan(/Gem::Specification\.new\s+do/).count).to eq(1)
      expect(gemspec_content.scan(/^\s*spec\.name\s*=/).count).to eq(1)
      expect(gemspec_content).not_to match(/^spec\./)
      expect(gemspec_content).to include(contract_case.fetch(:summary))
      expect(gemspec_content).to include(contract_case.fetch(:description))
      expect(gemspec_content).to include(%(spec.executables = ["#{contract_case.fetch(:executable)}"]))
      expect(gemspec_content).to include(%(spec.add_development_dependency("gitmoji-regex", "~> 1.0")))
      expect(gemspec_content).not_to include("# Hence.")
      expect(gemspec_content).not_to include("add_development_dependency(\"#{package_name}\"")
      expect(File.read(File.join(root, "#{package_name}.gemspec"))).to eq(gemspec_content)
    end
  end

  it "ports old gemspec freeze block location preservation" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:freeze_block_location)
    package_name = contract_case.fetch(:package_name)

    Dir.mktmpdir("kettle-jem-old-gemspec-freeze-block-policy", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.version = gem_version
            spec.summary = "Freeze gem"
            spec.bindir = "exe"

            #{contract_case.fetch(:open_marker)}
            # Custom dependencies
            # spec.add_dependency("#{contract_case.fetch(:custom_dependency)}")
            #{contract_case.fetch(:close_marker)}

            spec.require_paths = ["lib"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY,
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "2.0.0"
            spec.summary = "Template summary"
            spec.bindir = "exe"
            spec.executables = []
            spec.require_paths = ["lib"]
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "#{package_name}.gemspec" }
      gemspec_content = report.fetch(:final_content)
      lines = gemspec_content.lines
      gemspec_line = lines.find_index { |line| line.include?("Gem::Specification.new") }
      freeze_line = lines.find_index { |line| line.include?(contract_case.fetch(:open_marker)) }
      close_line = lines.find_index { |line| line.include?(contract_case.fetch(:close_marker)) }
      block_end_line = lines.each_index.select { |index| lines[index].strip == "end" }.last

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(freeze_line).to be > gemspec_line
      expect(close_line).to be > freeze_line
      expect(close_line).to be < block_end_line
      expect(gemspec_content).to include(%(# spec.add_dependency("#{contract_case.fetch(:custom_dependency)}")))
      expect(gemspec_content).not_to include("To retain during kettle-jem templating")
      expect(File.read(File.join(root, "#{package_name}.gemspec"))).to eq(gemspec_content)
    end
  end

  it "ports old gemspec self-dependency removal while preserving project fields" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:gemspec_self_dependency)
    package_name = contract_case.fetch(:package_name)

    Dir.mktmpdir("kettle-jem-old-gemspec-policy", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.summary = "Destination summary"
            spec.description = "🧪 Destination description"
            spec.homepage = "https://github.com/acme/#{package_name}"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🧬"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "Template summary"
            spec.description = "Template description"
            spec.homepage = "https://template.example"
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency("{KJ|GEM_NAME}", "~> 1.0")
            spec.add_dependency '{KJ|GEM_NAME}'
            spec.add_development_dependency("{KJ|GEM_NAME}")
            spec.add_development_dependency '{KJ|GEM_NAME}', ">= 0"
            spec.add_dependency("#{contract_case.fetch(:preserved_dependency)}", ">= 2.8", "< 3")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: { accept: true })
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "#{package_name}.gemspec"
      end
      gemspec_content = report.fetch(:final_content)

      expect(gemspec_content).to include(%(spec.name = "#{package_name}"))
      expect(gemspec_content).to include('spec.summary = "🧬 Destination summary"')
      expect(gemspec_content).to include('spec.description = "🧬 Destination description"')
      expect(gemspec_content).to include(%(spec.homepage = "https://github.com/acme/#{package_name}"))
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 4.0"')
      expect(gemspec_content).to include(%(spec.add_dependency("#{contract_case.fetch(:preserved_dependency)}", ">= 2.8", "< 3")))
      expect(gemspec_content).not_to match(
        /add_(?:development_)?dependency\s*\(?\s*["']#{Regexp.escape(contract_case.fetch(:removed_dependency))}["']/
      )
      expect(report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "delete_self_dependency_declarations", deleted_dependency_count: 4)
      )
    end
  end

  it "renders deterministic appraisal helper outputs" do
    matrix_entries = [
      {
        name: described_class.appraisal_name(
          tier1_gem: "activerecord",
          tier1_version: "7.1",
          tier2_gem: "omniauth",
          tier2_version: "2.1",
          ruby_series: "r3"
        ),
        ruby_series: "r3",
        tier1_gemfile: "gemfiles/modular/activerecord/r3/v7.1.gemfile",
        tier2_gemfile: "gemfiles/modular/omniauth/r3/v2.1.gemfile",
        x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r3/libs.gemfile",
      },
      {
        name: described_class.appraisal_name(
          tier1_gem: "mail",
          tier1_version: "2.8",
          ruby_series: "r2"
        ),
        ruby_series: "r2",
        tier1_gemfile: "gemfiles/modular/mail/r2/v2.8.gemfile",
        x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r2/libs.gemfile",
      },
    ]
    bucket_ranges = {
      "r2" => { floor: "2.7", ceiling: "2.99" },
      "r3" => { floor: "3.2", ceiling: "3.99" },
    }

    expect(described_class.appraisal_gem_abbreviation("activerecord")).to eq("ar")
    expect(described_class.appraisal_gem_abbreviation("unknown")).to eq("unknown")
    expect(described_class.appraisal_format_version("7.1.5")).to eq("7-1-5")
    expect(matrix_entries.map { |entry| entry.fetch(:name) }).to eq(["kja-ar-7-1-oa-2-1-r3", "kja-mail-2-8-r2"])
    expect(described_class.appraisal_modular_gemfile_path(gem_name: "activerecord", version: "7.1", ruby_series: "r3")).to eq(
      "gemfiles/modular/activerecord/r3/v7.1.gemfile"
    )
    expect(described_class.appraisal_modular_gemfile_content(
      gem_name: "activerecord",
      version: "7.1",
      sub_dependencies: { "sqlite3" => "1.6.9" }
    )).to eq(<<~RUBY)
      # frozen_string_literal: true

      # Generated by kettle-jem

      gem "activerecord", "~> 7.1.0"
      gem "sqlite3", "~> 1.6.9"
    RUBY

    appraisals = described_class.appraisal_file_content(matrix_entries)
    expect(appraisals).to include('appraise "kja-ar-7-1-oa-2-1-r3" do')
    expect(appraisals).to include('eval_gemfile "gemfiles/modular/activerecord/r3/v7.1.gemfile"')
    expect(appraisals).to include('appraise "kja-mail-2-8-r2" do')

    groups = described_class.appraisal_workflow_groups(matrix_entries, bucket_ranges: bucket_ranges)
    expect(groups).to eq(
      "supported" => [
        {
          ruby: "3.2",
          appraisal: "kja-ar-7-1-oa-2-1-r3",
          exec_cmd: "kettle-test",
          gemfile: "Appraisal.root",
          rubygems: "latest",
          bundler: "latest",
        },
      ],
      "unsupported" => [
        {
          ruby: "2.7",
          appraisal: "kja-mail-2-8-r2",
          exec_cmd: "kettle-test",
          gemfile: "Appraisal.root",
          rubygems: "latest",
          bundler: "latest",
        },
      ]
    )
    expect(described_class.appraisal_workflow_yaml_snippets(matrix_entries, bucket_ranges: bucket_ranges).fetch("supported")).to include(
      'appraisal: "kja-ar-7-1-oa-2-1-r3"'
    )
    expect(described_class.appraisal_x_stdlib_exclusions(<<~RUBY)).to eq(["erb", "mutex_m", "version_gem"])
      eval_gemfile "../erb/vHEAD.gemfile"
      eval_gemfile "../mutex_m/vHEAD.gemfile"
    RUBY
  end

  it "plans deterministic appraisal matrices from supplied version metadata" do
    versions = %w[5.0.0 5.1.0 5.2.0 6.0.0 6.1.0 7.0.0 7.1.0 7.2.0].map do |number|
      { number: number }
    end

    expect(described_class.appraisal_select_versions(versions, mode: "major")).to eq(["5.2", "6.1", "7.2"])
    expect(described_class.appraisal_select_versions(versions, mode: "minor")).to eq(
      ["5.0", "5.1", "5.2", "6.0", "6.1", "7.0", "7.1", "7.2"]
    )
    expect(described_class.appraisal_select_versions(versions, mode: "patch")).to eq(
      ["5.0.0", "5.1.0", "5.2.0", "6.0.0", "6.1.0", "7.0.0", "7.1.0", "7.2.0"]
    )
    expect(described_class.appraisal_select_versions(versions, mode: "minor-minmax")).to eq(
      ["5.0", "5.2", "6.0", "6.1", "7.0", "7.1", "7.2"]
    )
    expect(described_class.appraisal_select_versions(versions, mode: "semver")).to eq(["5.2", "6.1", "7.0", "7.1", "7.2"])
    expect(described_class.appraisal_select_versions(versions, mode: "minor", requirements: [">= 6.0", "< 7.0"])).to eq(["6.0", "6.1"])

    entries = described_class.appraisal_matrix_entries(
      tier1_gems: [
        {
          name: "activerecord",
          assignments: [
            { version: "6.1", bucket: "r2" },
            { version: "7.2", bucket: "r3" },
          ],
        },
      ],
      tier2_gems: [
        { name: "omniauth", versions: ["2.1"] },
      ]
    )

    expect(entries).to eq(
      [
        {
          name: "kja-ar-6-1-oa-2-1-r2",
          tier1_gemfile: "gemfiles/modular/activerecord/r2/v6.1.gemfile",
          tier2_gemfile: "gemfiles/modular/omniauth/r2/v2.1.gemfile",
          x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r2/libs.gemfile",
          ruby_series: "r2",
        },
        {
          name: "kja-ar-7-2-oa-2-1-r3",
          tier1_gemfile: "gemfiles/modular/activerecord/r3/v7.2.gemfile",
          tier2_gemfile: "gemfiles/modular/omniauth/r3/v2.1.gemfile",
          x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r3/libs.gemfile",
          ruby_series: "r3",
        },
      ]
    )
  end

  it "detects appraisal Ruby seams and assigns selected versions to buckets" do
    versions = [
      { number: "5.2.8", min_ruby: "2.3" },
      { number: "6.0.6", min_ruby: "2.5" },
      { number: "6.1.7", min_ruby: "2.5" },
      { number: "7.0.8", min_ruby: "2.7" },
      { number: "7.1.5", min_ruby: "2.7" },
      { number: "7.2.2", min_ruby: "3.1" },
    ]

    seams = described_class.appraisal_find_ruby_seams(versions)
    expect(seams).to eq(
      [
        { version: "5.2", min_ruby: Gem::Version.new("2.3") },
        { version: "6.0", min_ruby: Gem::Version.new("2.5") },
        { version: "7.0", min_ruby: Gem::Version.new("2.7") },
        { version: "7.2", min_ruby: Gem::Version.new("3.1") },
      ]
    )

    series = described_class.appraisal_ruby_series(versions)
    expect(series.fetch(:buckets)).to eq(["r2.4", "r2.6", "r2", "r3"])

    assignments = described_class.appraisal_assign_version_buckets(
      selected_versions: ["5.2", "6.1", "7.2"],
      seams: seams,
      buckets: series.fetch(:buckets),
      bucket_ranges: series.fetch(:bucket_ranges),
      all_versions: ["5.2", "6.0", "6.1", "7.0", "7.1", "7.2"]
    )
    expect(assignments).to eq(
      [
        { version: "5.2", bucket: "r2.4" },
        { version: "6.1", bucket: "r2.6" },
        { version: "7.1", bucket: "r2", filler: true },
        { version: "7.2", bucket: "r3" },
      ]
    )
  end

  it "resolves appraisal sub-dependencies from supplied metadata" do
    resolved = described_class.appraisal_resolve_sub_dependencies(
      parent_gem: "activerecord",
      parent_version: "7.1",
      ruby_min: "3.0",
      excluded_gems: ["erb", "version_gem"],
      parent_versions: [
        {
          number: "7.1.3",
          runtime_dependencies: [
            { name: "sqlite3", requirements: "~> 1.6" },
            { name: "erb", requirements: ">= 0" },
          ],
        },
      ],
      dependency_versions: {
        "sqlite3" => [
          { number: "1.6.8", min_ruby: "2.7" },
          { number: "1.6.9", min_ruby: "3.0" },
          { number: "1.7.0", min_ruby: "3.2" },
        ],
      }
    )

    expect(resolved).to eq("sqlite3" => "1.6.9")
  end

  it "resolves RubyGems version metadata through a cacheable Kettle/Jem resolver" do
    response = Struct.new(:code, :body)
    calls = []
    http_get = lambda do |uri|
      calls << uri.to_s
      case uri.to_s
      when "https://example.test/api/v1/versions/active+record.json"
        response.new("200", JSON.dump([
          { "number" => "7.1.0.beta1", "ruby_version" => ">= 3.0", "prerelease" => true, "created_at" => "2024-01-01" },
          { "number" => "6.1.7", "ruby_version" => ">= 2.5", "prerelease" => false, "created_at" => "2023-01-01" },
          { "number" => "7.1.3", "ruby_version" => ">= 2.7", "prerelease" => false, "created_at" => "2024-02-01" },
        ]))
      when "https://example.test/api/v2/rubygems/active+record/versions/7.1.3.json"
        response.new("200", JSON.dump({
          "number" => "7.1.3",
          "ruby_version" => ">= 2.7",
          "dependencies" => {
            "runtime" => [
              { "name" => "sqlite3", "requirements" => "~> 1.6" },
            ],
          },
        }))
      else
        response.new("404", "{}")
      end
    end

    resolver = described_class::RubyGemsResolver.new(
      http_get: http_get,
      v1_api_base: "https://example.test/api/v1",
      v2_api_base: "https://example.test/api/v2/rubygems"
    )

    expect(resolver.versions("active record", requirements: ">= 7.0")).to eq(
      [
        { number: "7.1.3", ruby_version: ">= 2.7", created_at: "2024-02-01", prerelease: false },
      ]
    )
    expect(resolver.versions("active record", include_prerelease: true).map { |entry| entry.fetch(:number) }).to eq(
      ["6.1.7", "7.1.0.beta1", "7.1.3"]
    )
    expect(resolver.min_ruby_version("active record", "7.1.3")).to eq(Gem::Version.new("2.7"))
    expect(resolver.minor_versions_by_major("active record")).to eq(
      [
        { major: 6, minors: ["6.1"] },
        { major: 7, minors: ["7.1"] },
      ]
    )
    expect(resolver.version_info("active record", "7.1.3")).to eq(
      {
        number: "7.1.3",
        ruby_version: ">= 2.7",
        runtime_dependencies: [
          { name: "sqlite3", requirements: "~> 1.6" },
        ],
      }
    )
    expect(resolver.version_info("active record", "7.1.3")).to be_a(Hash)
    expect(calls.tally).to eq(
      "https://example.test/api/v1/versions/active+record.json" => 1,
      "https://example.test/api/v2/rubygems/active+record/versions/7.1.3.json" => 1
    )
  end

  it "ports appraisal CLI config orchestration helpers into Kettle/Jem" do
    gemspec_content = <<~RUBY
      Gem::Specification.new do |spec|
        spec.add_dependency "activerecord", "~> 7.1"
        spec.add_runtime_dependency("erb", ">= 0")
        # spec.add_dependency "ignored"
        spec.add_runtime_dependency "sequel", ">= 5.0"
      end
    RUBY

    scaffold = described_class.appraisal_scaffold_config(
      gemspec_content: gemspec_content,
      existing_config: {
        appraisal_matrix: {
          gems: {
            tier2: [
              { name: "omniauth" },
            ],
          },
        },
      },
      exclusions: ["erb"],
      freshness_ttl: 86_400
    )

    expect(scaffold.fetch("appraisal_matrix")).to include(
      "mode" => "semver",
      "freshness_ttl" => 86_400,
    )
    expect(scaffold.dig("appraisal_matrix", "gems", "tier1")).to eq(
      [
        { "name" => "activerecord" },
        { "name" => "sequel" },
      ]
    )
    expect(scaffold.dig("appraisal_matrix", "gems", "tier2")).to eq([{ "name" => "omniauth" }])

    expect(described_class.appraisal_matrix_has_versions?(
      "gems" => {
        "tier1" => [{ "name" => "activerecord", "versions" => [] }],
        "tier2" => [{ "name" => "omniauth", "versions" => ["2.1"] }],
      }
    )).to be true
    expect(described_class.appraisal_matrix_fresh?({ "resolved_at" => 100, "freshness_ttl" => 50 }, now: 149)).to be true
    expect(described_class.appraisal_matrix_fresh?({ "resolved_at" => 100, "freshness_ttl" => 50 }, now: 150)).to be false
    expect(described_class.appraisal_time_ago(0, now: 90_000)).to eq("1d")
    expect(described_class.appraisal_finalize_versions(%w[7.1.0 7.1.1], include_versions: ["6.0.9"], exclude_versions: ["7.1.0"])).to eq(
      %w[6.0.9 7.1.1]
    )

    resolver = Class.new do
      def versions(gem_name, requirements: nil)
        case [gem_name, requirements]
        when ["activerecord", [">= 7.1", "< 7.2"]]
          [{ number: "7.1.0" }, { number: "7.1.1" }]
        when ["omniauth", nil]
          [{ number: "2.0.0" }, { number: "2.1.3" }]
        else
          []
        end
      end

      def minor_versions_by_major(gem_name, requirements: nil)
        case [gem_name, requirements]
        when ["sequel", nil]
          [{ major: 5, minors: ["5.0", "5.9"] }]
        else
          []
        end
      end

      def min_ruby_version(gem_name, version)
        return Gem::Version.new("3.2") if gem_name == "omniauth" && version == "2.1.3"

        Gem::Version.new("2.7")
      end
    end.new

    expect(described_class.appraisal_all_versions_for(
      resolver: resolver,
      gem_name: "activerecord",
      mode: "patch",
      requirements: [">= 7.1", "< 7.2"],
      include_versions: ["6.0.9"],
      exclude_versions: ["7.1.0"]
    )).to eq(%w[6.0.9 7.1.1])
    expect(described_class.appraisal_all_versions_for(resolver: resolver, gem_name: "sequel", mode: "major")).to eq(%w[5.0 5.9])
    expect(described_class.appraisal_compatible_version_for_bucket?(
      resolver: resolver,
      gem_name: "omniauth",
      version: "2.1",
      ruby_series: "r3.1",
      bucket_ranges: { "r3.1" => { floor: "3.0", ceiling: "3.1" } }
    )).to be false
  end

  it "plans stale flat appraisal gemfile cleanup paths" do
    stale_paths = described_class.appraisal_stale_gemfile_paths(
      existing_paths: [
        "gemfiles/kja-ar-7-1-r3.gemfile",
        "gemfiles/kja-ar-6-1-r2.gemfile",
        "gemfiles/manual.gemfile",
        "gemfiles/modular/activerecord/r3/v7.1.gemfile",
      ],
      current_entries: [
        { name: "kja-ar-7-1-r3" },
      ]
    )

    expect(stale_paths).to eq(["gemfiles/kja-ar-6-1-r2.gemfile"])
  end

  it "honors author template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-author-token-override-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            author:
              name: Config Person
              given_names: Config
              family_names: Person
              email: config@example.test
              domain: config.example.test
              orcid: "{KJ|AUTHOR:ORCID}"
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Author: {KJ|AUTHOR:NAME}
          Given: {KJ|AUTHOR:GIVEN_NAMES}
          Family: {KJ|AUTHOR:FAMILY_NAMES}
          Email: {KJ|AUTHOR:EMAIL}
          Domain: {KJ|AUTHOR:DOMAIN}
          ORCID: {KJ|AUTHOR:ORCID}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_AUTHOR_NAME" => "Env A Writer",
          "KJ_AUTHOR_EMAIL" => "env@example.test",
          "KJ_AUTHOR_DOMAIN" => "env.example.test",
          "KJ_AUTHOR_ORCID" => "0000-0002-1825-0097",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Author: Env A Writer
        Given: Config
        Family: Person
        Email: env@example.test
        Domain: env.example.test
        ORCID: 0000-0002-1825-0097
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|AUTHOR:DOMAIN" => "env.example.test",
        "KJ|AUTHOR:EMAIL" => "env@example.test",
        "KJ|AUTHOR:FAMILY_NAMES" => "Person",
        "KJ|AUTHOR:GIVEN_NAMES" => "Config",
        "KJ|AUTHOR:NAME" => "Env A Writer",
        "KJ|AUTHOR:ORCID" => "0000-0002-1825-0097"
      )
    end
  end

  it "honors forge user template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-forge-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            forge:
              gh_user: config-gh
              gl_user: config-gl
              cb_user: "{KJ|CB:USER}"
              sh_user: config-sh
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          GitHub: {KJ|GH:USER}
          GitLab: {KJ|GL:USER}
          Codeberg: {KJ|CB:USER}
          SourceHut: {KJ|SH:USER}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_GH_USER" => "env-gh",
          "KJ_CB_USER" => "env-cb",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        GitHub: env-gh
        GitLab: config-gl
        Codeberg: env-cb
        SourceHut: config-sh
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|CB:USER" => "env-cb",
        "KJ|GH:USER" => "env-gh",
        "KJ|GL:USER" => "config-gl",
        "KJ|SH:USER" => "config-sh"
      )
    end
  end

  it "honors funding platform template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-funding-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            funding:
              patreon: config-patreon
              kofi: config-kofi
              paypal: "{KJ|FUNDING:PAYPAL}"
              buymeacoffee: config-bmac
              polar: config-polar
              liberapay: config-liberapay
              issuehunt: config-issuehunt
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Patreon: {KJ|FUNDING:PATREON}
          Ko-fi: {KJ|FUNDING:KOFI}
          PayPal: {KJ|FUNDING:PAYPAL}
          BuyMeACoffee: {KJ|FUNDING:BUYMEACOFFEE}
          Polar: {KJ|FUNDING:POLAR}
          Liberapay: {KJ|FUNDING:LIBERAPAY}
          IssueHunt: {KJ|FUNDING:ISSUEHUNT}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_FUNDING_PATREON" => "env-patreon",
          "KJ_FUNDING_PAYPAL" => "env-paypal",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Patreon: env-patreon
        Ko-fi: config-kofi
        PayPal: env-paypal
        BuyMeACoffee: config-bmac
        Polar: config-polar
        Liberapay: config-liberapay
        IssueHunt: config-issuehunt
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|FUNDING:BUYMEACOFFEE" => "config-bmac",
        "KJ|FUNDING:ISSUEHUNT" => "config-issuehunt",
        "KJ|FUNDING:KOFI" => "config-kofi",
        "KJ|FUNDING:LIBERAPAY" => "config-liberapay",
        "KJ|FUNDING:PATREON" => "env-patreon",
        "KJ|FUNDING:PAYPAL" => "env-paypal",
        "KJ|FUNDING:POLAR" => "config-polar"
      )
    end
  end

  it "honors social template token config and environment overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-social-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          tokens:
            social:
              mastodon: config-mastodon
              bluesky: config-bluesky
              linktree: "{KJ|SOCIAL:LINKTREE}"
              devto: config-devto
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Mastodon: {KJ|SOCIAL:MASTODON}
          Bluesky: {KJ|SOCIAL:BLUESKY}
          Linktree: {KJ|SOCIAL:LINKTREE}
          Dev.to: {KJ|SOCIAL:DEVTO}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_SOCIAL_MASTODON" => "env-mastodon",
          "KJ_SOCIAL_LINKTREE" => "env-linktree",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Mastodon: env-mastodon
        Bluesky: config-bluesky
        Linktree: env-linktree
        Dev.to: config-devto
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|SOCIAL:BLUESKY" => "config-bluesky",
        "KJ|SOCIAL:DEVTO" => "config-devto",
        "KJ|SOCIAL:LINKTREE" => "env-linktree",
        "KJ|SOCIAL:MASTODON" => "env-mastodon"
      )
    end
  end

  it "projects license template tokens from configured licenses" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-license-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.licenses = ["MIT"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          licenses:
            - AGPL-3.0-only
            - PolyForm-Small-Business-1.0.0
            - LicenseRef-Big-Time-Public-License
          readme:
            package_family: structuredmerge
          templates:
            root: packaged
            apply: true
            entries:
              - LICENSE.md
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_LICENSE_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(plan.dig(:facts, :license, :spdx)).to eq(
        ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0", "LicenseRef-Big-Time-Public-License"]
      )
      expect(plan.dig(:facts, :package, :license_expression)).to eq(
        "AGPL-3.0-only OR PolyForm-Small-Business-1.0.0 OR LicenseRef-Big-Time-Public-License"
      )
      expect(final_content).to include("[AGPL-3.0-only](AGPL-3.0-only.md)")
      expect(final_content).to include("[PolyForm-Small-Business-1.0.0](PolyForm-Small-Business-1.0.0.md)")
      expect(final_content).to include("[Big-Time-Public-License](Big-Time-Public-License.md)")
      expect(final_content).to include("## Use-case guide")
      expect(final_content).to include("Required Notice: Copyright")
      expect(final_content).to include("Jane Q Public")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|COPYRIGHT_PREFIX" => "Required Notice: ",
        "KJ|LICENSE:PRIMARY_SPDX" => "AGPL-3.0-only",
        "KJ|LICENSE_EYE:PRIMARY_SPDX" => "AGPL-3.0-only",
        "KJ|LICENSE_EYE:MODE" => "resolve",
        "KJ|LICENSE_EYE:FLAGS" => ""
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|LICENSE_MD_CONTENT")).to include(
        "This project is made available under the following licenses."
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:LICENSE_BADGE")).to eq(
        "[![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0 OR LicenseRef-Big-Time-Public-License][📄license-img]][📄license]"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:LICENSE_REFS")).to include(
        "[📄license-ref]: LICENSE.md"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:LICENSE_REFS")).to include(
        "License-AGPL--3.0--only_OR_PolyForm--Small--Business--1.0.0_OR_LicenseRef--Big--Time--Public--License"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:FAMILY_INTRO_BACKEND_MATRIX")).to include(
        "https://github.com/structuredmerge/structuredmerge-ruby#package-family"
      )
      expect(template_report.dig(:metadata, :template_tokens, "KJ|README:FAMILY_INTRO_BACKEND_MATRIX")).to include(
        "StructuredMerge Ruby package family"
      )
    end
  end

  it "uses MIT as the License-Eye compatibility license when MIT is configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-license-eye-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.licenses = ["AGPL-3.0-only"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          licenses:
            - AGPL-3.0-only
            - MIT
          license_eye:
            dependency_licenses:
              - name: simplecov-rcov
                version: 0.3.7
                license: MIT
          templates:
            root: packaged
            apply: true
            entries:
              - .licenserc.yaml
              - .github/workflows/license-eye.yml
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      licenserc_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == ".licenserc.yaml"
      end
      workflow_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == ".github/workflows/license-eye.yml"
      end

      expect(licenserc_report.fetch(:final_content)).to include('spdx-id: "MIT"')
      expect(licenserc_report.fetch(:final_content)).to include("  licenses:\n    - name: \"simplecov-rcov\"\n      version: \"0.3.7\"\n      license: \"MIT\"")
      expect(workflow_report.fetch(:final_content)).to include('mode: "check"')
      expect(workflow_report.fetch(:final_content)).to include('flags: "--weak-compatible"')
    end
  end

  it "formats README metadata SPDX license identifiers as code spans" do
    block = described_class.readme_metadata_block(
      package: {
        name: "example",
        description: "Example gem",
        homepage_url: "https://example.test",
        source_url: "https://example.test/source",
        license_expression: "AGPL-3.0-only OR PolyForm-Small-Business-1.0.0",
      },
      license: {
        spdx: ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"],
      },
      funding: {
        urls: [],
      }
    )

    expect(block).to include("| License | `AGPL-3.0-only` OR `PolyForm-Small-Business-1.0.0` |")
  end

  it "applies configured licenses to merged gemspec output" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        spec.homepage = "https://example.test"
        spec.licenses = ["MIT"]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        spec.homepage = "https://example.test"
        spec.licenses = ["AGPL-3.0-only"]
      end
    RUBY
    facts = {
      package: {name: "example"},
      license: {spdx: ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]},
    }

    output = described_class.merge_gemspec_template_source(template, destination, facts: facts)

    expect(output).to include('spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]')
  end

  it "preserves README metadata during template-source README application" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-metadata-order", tmp_root) do |root|
      metadata_block = described_class.readme_metadata_block(
        package: {
          name: "example",
          description: "Example gem",
          homepage_url: "https://example.test",
          source_url: "https://github.com/structuredmerge/structuredmerge-ruby",
          license_expression: "MIT",
        },
        license: {spdx: ["MIT"]},
        funding: {urls: ["https://tidelift.com/funding/github/rubygems/example"]}
      )
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://example.test"
            spec.license = "MIT"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          # Example

          Destination body.

          #{metadata_block}
        MARKDOWN
        "template/README.md.example" => "# {KJ|NAMESPACE}\n\nTemplate body.\n",
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true})
      first_readme = File.read(File.join(root, "README.md"))
      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true})

      expect(first_readme).to include("<!-- kettle-jem:metadata:start -->")
      expect(first_readme).to include("| Package | example |")
      expect(File.read(File.join(root, "README.md"))).to eq(first_readme)
    end
  end

  it "applies and prunes root license files from configured licenses" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-license-file-prune-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["MIT"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          licenses:
            - AGPL-3.0-only
            - PolyForm-Small-Business-1.0.0
          templates:
            root: packaged
            apply: true
            entries:
              - LICENSE.md
              - AGPL-3.0-only.md
              - MIT.md
              - PolyForm-Noncommercial-1.0.0.md
              - PolyForm-Small-Business-1.0.0.md
              - Big-Time-Public-License.md
        YAML
        "MIT.md" => "obsolete MIT license\n",
        "PolyForm-Noncommercial-1.0.0.md" => "obsolete PolyForm NC license\n",
        "Big-Time-Public-License.md" => "obsolete Big Time license\n",
      })

      apply = described_class.apply_project(root, env: {})
      recipe_names = apply[:recipe_reports].map { |report| report.fetch(:recipe_name) }

      expect(apply.dig(:facts, :license, :spdx)).to eq(["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"])
      expect(recipe_names).to include("template_source_application_AGPL_3_0_only_md")
      expect(recipe_names).to include("template_source_application_PolyForm_Small_Business_1_0_0_md")
      expect(recipe_names).not_to include("template_source_application_MIT_md")
      expect(recipe_names).not_to include("template_source_application_PolyForm_Noncommercial_1_0_0_md")
      expect(recipe_names).not_to include("template_source_application_Big_Time_Public_License_md")
      expect(apply[:changed_files]).to include(
        "MIT.md",
        "PolyForm-Noncommercial-1.0.0.md",
        "Big-Time-Public-License.md",
        "AGPL-3.0-only.md",
        "PolyForm-Small-Business-1.0.0.md"
      )
      expect(File).to exist(File.join(root, "AGPL-3.0-only.md"))
      expect(File).to exist(File.join(root, "PolyForm-Small-Business-1.0.0.md"))
      expect(File).not_to exist(File.join(root, "MIT.md"))
      expect(File).not_to exist(File.join(root, "PolyForm-Noncommercial-1.0.0.md"))
      expect(File).not_to exist(File.join(root, "Big-Time-Public-License.md"))
    end
  end

  it "projects copyright holders from git blame into license templates" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-copyright-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Fallback Author"]
            spec.email = ["fallback@example.test"]
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "lib/example.rb" => <<~RUBY,
          module Example
            VERSION = "0.1.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - LICENSE.md
              - README.md
        YAML
        "templates/LICENSE.md.example" => <<~MARKDOWN,
          {KJ|LICENSE_MD_CONTENT}

          {KJ|LICENSE_COPYRIGHT_NOTICE}
        MARKDOWN
        "templates/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Template synopsis.

          ## 📄 License

          {KJ|README:LICENSE_INTRO}

          ### © Copyright

          {KJ|README:COPYRIGHT_NOTICE}

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.
        MARKDOWN
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## 🌻 Synopsis

          Project synopsis.

          ## ⚙️ Configuration

          Project configuration.

          ## 🔧 Basic Usage

          Project usage.
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "config", "user.name", "Jane Contributor")).to be(true)
      expect(system("git", "-C", root, "config", "user.email", "jane@example.test")).to be(true)
      expect(system("git", "-C", root, "add", ".")).to be(true)
      commit_env = {
        "GIT_AUTHOR_NAME" => "Jane Contributor",
        "GIT_AUTHOR_EMAIL" => "jane@example.test",
        "GIT_AUTHOR_DATE" => "#{Time.now.utc.year}-01-02T00:00:00Z",
        "GIT_COMMITTER_NAME" => "Jane Contributor",
        "GIT_COMMITTER_EMAIL" => "jane@example.test",
        "GIT_COMMITTER_DATE" => "#{Time.now.utc.year}-01-02T00:00:00Z",
      }
      tree = IO.popen(["git", "-C", root, "write-tree"], &:read).strip
      commit = IO.popen(commit_env, ["git", "-C", root, "commit-tree", tree, "-m", "initial"], &:read).strip
      expect(commit).to match(/\A[0-9a-f]{40}\z/)
      expect(system("git", "-C", root, "update-ref", "refs/heads/main", commit)).to be(true)
      expect(system("git", "-C", root, "symbolic-ref", "HEAD", "refs/heads/main")).to be(true)

      plan = described_class.plan_project(root, env: {})
      license_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "template_source_application_LICENSE_md" }
      readme_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "template_source_application_README_md" }
      expected_line = "Copyright (c) #{Time.now.utc.year} Jane Contributor"
      expect(plan.dig(:facts, :copyright, :lines)).to eq([expected_line])
      expect(license_report.fetch(:final_content)).to include("## Copyright Notice")
      expect(license_report.fetch(:final_content)).to include(expected_line)
      expect(readme_report.fetch(:final_content)).to include("Copyright holders")
      expect(readme_report.fetch(:final_content)).to include("- #{expected_line}")
      expect(license_report.dig(:metadata, :template_tokens, "KJ|LICENSE_COPYRIGHT_NOTICE")).to include(expected_line)
    end
  end

  it "falls back to configured author copyright sections when git blame is unavailable" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-copyright-author-fallback", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Peter H. Boling"]
            spec.email = ["floss@galtzo.com"]
            spec.licenses = ["AGPL-3.0-only"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          licenses:
            - AGPL-3.0-only
            - PolyForm-Small-Business-1.0.0
          tokens:
            author:
              given_names: Peter H.
              family_names: Boling
              email: floss@galtzo.com
          templates:
            root: template
            apply: true
            entries:
              - LICENSE.md
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        "README.md" => "# Example\n",
        "template/LICENSE.md.example" => "{KJ|LICENSE_MD_CONTENT}\n\n{KJ|LICENSE_COPYRIGHT_NOTICE}\n",
        "template/README.md.example" => "# Example\n\n## 📄 License\n\n{KJ|README:COPYRIGHT_NOTICE}\n",
      })

      plan = described_class.plan_project(root, env: {})
      license_report = plan[:recipe_reports].find { |report| report.fetch(:relative_path) == "LICENSE.md" }
      readme_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "template_source_application_README_md" }
      expected_line = "Required Notice: Copyright (c) #{Time.now.utc.year} Peter H. Boling"

      expect(plan.fetch(:facts)).not_to have_key(:copyright)
      expect(license_report.fetch(:final_content)).to include("## Copyright Notice")
      expect(license_report.fetch(:final_content)).to include(expected_line)
      expect(readme_report.fetch(:final_content)).to include("Copyright holders")
      expect(readme_report.fetch(:final_content)).to include("- #{expected_line}")
    end
  end

  it "projects project runtime template tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-project-runtime-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "2.4.6"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          min_divergence_threshold: "{KJ|MIN_DIVERGENCE_THRESHOLD}"
          defaults:
            freeze_token: custom-freeze
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Gem shield: {KJ|GEM_SHIELD}
          Major: {KJ|GEM_MAJOR}
          GitHub org: {KJ|GH_ORG}
          Namespace shield: {KJ|NAMESPACE_SHIELD}
          Min dev Ruby: {KJ|MIN_DEV_RUBY}
          Freeze: {KJ|FREEZE_TOKEN}
          Version: {KJ|KETTLE_JEM_VERSION}
          Date: {KJ|TEMPLATE_RUN_DATE}
          Year: {KJ|TEMPLATE_RUN_YEAR}
          Dev gem: {KJ|KETTLE_DEV_GEM}
          YARD: {KJ|YARD_HOST}
          Homepage URI: {KJ|HOMEPAGE_URI}
          Emoji: {KJ|PROJECT_EMOJI}
          Divergence: {KJ|MIN_DIVERGENCE_THRESHOLD}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_MIN_DIVERGENCE_THRESHOLD" => "12",
          "KJ_YARD_HOST" => "docs.example.test",
          "KJ_HOMEPAGE_URI" => "https://homepage.example.test",
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Gem shield: example--gem")
      expect(final_content).to include("Major: 2")
      expect(final_content).to include("GitHub org: acme")
      expect(final_content).to include("Namespace shield: Example%3A%3AGem")
      expect(final_content).to include("Min dev Ruby: 3.2")
      expect(final_content).to include("Freeze: custom-freeze")
      expect(final_content).to include("Version: #{Kettle::Jem::VERSION}")
      expect(final_content).to include("Date: #{Time.now.strftime("%Y-%m-%d")}")
      expect(final_content).to include("Year: #{Time.now.year}")
      expect(final_content).to include("Dev gem: kettle-dev")
      expect(final_content).to include("YARD: docs.example.test")
      expect(final_content).to include("Homepage URI: https://homepage.example.test")
      expect(final_content).to include("Emoji: 🫖")
      expect(final_content).to include("Divergence: 12")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|FREEZE_TOKEN" => "custom-freeze",
        "KJ|GEM_MAJOR" => "2",
        "KJ|GEM_SHIELD" => "example--gem",
        "KJ|GH_ORG" => "acme",
        "KJ|MIN_DEV_RUBY" => "3.2",
        "KJ|MIN_DIVERGENCE_THRESHOLD" => "12",
        "KJ|NAMESPACE_SHIELD" => "Example%3A%3AGem",
        "KJ|PROJECT_EMOJI" => "🫖",
        "KJ|HOMEPAGE_URI" => "https://homepage.example.test",
        "KJ|YARD_HOST" => "docs.example.test"
      )
    end
  end

  it "honors configured project runtime URI tokens when ENV is absent" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-project-runtime-uri-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          yard_host: docs.config.test
          homepage_uri: https://homepage.config.test
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "YARD: {KJ|YARD_HOST}\nHomepage URI: {KJ|HOMEPAGE_URI}\n",
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(template_report.fetch(:final_content)).to eq("YARD: docs.config.test\nHomepage URI: https://homepage.config.test\n")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|HOMEPAGE_URI" => "https://homepage.config.test",
        "KJ|YARD_HOST" => "docs.config.test"
      )
    end
  end

  it "syncs ENV-backed values back into .kettle-jem.yml during templating" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-env-config-sync", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          min_divergence_threshold: 5 # ENV override: KJ_MIN_DIVERGENCE_THRESHOLD
          yard_host: docs.config.test # ENV override: KJ_YARD_HOST
          homepage_uri: https://homepage.config.test # ENV override: KJ_HOMEPAGE_URI
          kettle-jem:
            version: "1.0.0"
          tokens:
            forge:
              gh_user: config-user # GitHub username only. ENV: KJ_GH_USER
          templates:
            root: packaged
            apply: true
            entries:
              - .kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(
        root,
        env: {
          "KJ_MIN_DIVERGENCE_THRESHOLD" => "12",
          "KJ_YARD_HOST" => "docs.env.test",
          "KJ_HOMEPAGE_URI" => "https://homepage.env.test",
          "KJ_GH_USER" => "env-user",
        },
        run_options: {skip_commit: true}
      )
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.fetch("min_divergence_threshold")).to eq(12)
      expect(config.fetch("yard_host")).to eq("docs.env.test")
      expect(config.fetch("homepage_uri")).to eq("https://homepage.env.test")
      expect(config.dig("kettle-jem", "version")).to eq(Kettle::Jem::Version::VERSION)
      expect(config.dig("tokens", "forge", "gh_user")).to eq("env-user")
      expect(report.fetch(:final_content)).to include("min_divergence_threshold: 12 # ENV override: KJ_MIN_DIVERGENCE_THRESHOLD")
      expect(report.fetch(:final_content)).to include('yard_host: "docs.env.test" # ENV override: KJ_YARD_HOST')
      expect(report.fetch(:final_content)).to include('homepage_uri: "https://homepage.env.test" # ENV override: KJ_HOMEPAGE_URI')
      expect(report.fetch(:final_content)).to include(%(version: "#{Kettle::Jem::Version::VERSION}"))
      expect(report.fetch(:final_content)).to include('gh_user: "env-user" # GitHub username only. ENV: KJ_GH_USER')
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "prunes legacy kettle config keys after their replacement exists" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-legacy-config-key-cleanup", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          # README top logo mode.
          # Controls whether the generated README header includes the GitHub org logo,
          # the project logo, or both after the shared Galtzo and ruby-lang logos.
          # Supported values: org, project, org_and_project
          # Default (when key is absent): org_and_project
          readme:
            top_logos: related-org,ruby,org
            top_logo_mode: org_and_project
          templates:
            root: packaged
            apply: true
            entries:
              - .kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.dig("readme", "top_logos")).to eq("related-org,ruby,org")
      expect(config.fetch("readme")).not_to have_key("top_logo_mode")
      expect(report.fetch(:final_content)).not_to include("top_logo_mode:")
      expect(report.fetch(:final_content)).to include("# README top logos.")
      expect(report.fetch(:final_content)).to include("# Supported values: related-org, ruby, org, project")
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "preserves explicit kettle config values while refreshing the config template" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-destination-values", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          defaults:
            preference: template
            add_template_only_nodes: true
          project_emoji: "🫖"
          repository:
            topology: standalone
          readme:
            top_logos: related-org,ruby,org,project
          templates:
            root: packaged
            apply: true
            entries:
              - .kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.fetch("project_emoji")).to eq("🫖")
      expect(config.dig("repository", "topology")).to eq("standalone")
      expect(config.dig("readme", "top_logos")).to eq("related-org,ruby,org,project")
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "derives source and forge tokens from git origin when gemspec metadata is absent" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-origin-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Source: {KJ|GH_ORG}
          GitHub user: {KJ|GH:USER}
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:acme/example.git")).to be(true)

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(plan.dig(:facts, :package, :source_url)).to eq("https://github.com/acme/example")
      expect(template_report.fetch(:final_content)).to include("Source: acme")
      expect(template_report.fetch(:final_content)).to include("GitHub user: acme")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|GH_ORG" => "acme",
        "KJ|GH:USER" => "acme"
      )
    end
  end

  it "projects README top logo template tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-logo-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Galtzo FLOSS Logo")
      expect(final_content).to include("ruby-lang Logo")
      expect(final_content).to include("[![acme Logo by Aboling0, CC BY-SA 4.0][🖼️acme-i]][🖼️acme]")
      expect(final_content).to include("[![example-gem Logo by Aboling0, CC BY-SA 4.0][🖼️acme-example-gem-i]][🖼️acme-example-gem]")
      expect(final_content).to include("[🖼️acme-i]: https://logos.galtzo.com/assets/images/acme/avatar-128px.svg")
      expect(final_content).to include("[🖼️acme-example-gem-i]: https://logos.galtzo.com/assets/images/acme/example-gem/avatar-128px.svg")
      expect(final_content).to include("[🖼️acme-example-gem]: https://github.com/acme/example-gem")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|README:TOP_LOGO_REFS" => a_string_including("https://github.com/acme/example-gem"),
        "KJ|README:TOP_LOGO_ROW" => a_string_including("example-gem Logo by Aboling0")
      )
    end
  end

  it "separates full template profile from monorepo sub-project URL topology" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-monorepo-url-topology-slice", tmp_root) do |root|
      gem_root = File.join(root, "gems", "kettle-jem")
      write_tree(gem_root, {
        "kettle-jem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-jem"
            spec.summary = "Kettle gem templater"
            spec.metadata["source_code_uri"] = "https://github.com/structuredmerge/kettle-jem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: project
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:structuredmerge/structuredmerge-ruby.git")).to be(true)

      plan = described_class.plan_project(
        gem_root,
        env: {
          "KETTLE_JEM_TEMPLATE_PROFILE" => "full",
          "KJ_REPOSITORY_TOPOLOGY" => "monorepo-subproject",
        }
      )
      expect(plan.dig(:facts, :template_profile)).to eq("full")
      expect(plan.dig(:facts, :repository, :mode)).to eq("monorepo_subproject")
      expect(plan.dig(:facts, :readme_logo, :top_logo_refs)).to include("[🖼️structuredmerge-structuredmerge-ruby-kettle-jem-i]: https://logos.galtzo.com/assets/images/structuredmerge/structuredmerge-ruby/kettle-jem/avatar-192px.svg")
      expect(plan.dig(:facts, :readme_logo, :top_logo_refs)).to include("[🖼️structuredmerge-structuredmerge-ruby-kettle-jem]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem")
    end
  end

  it "projects README logo row entries from named logo options" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-named-logo-options-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: related-org,ruby,org,project,unknown
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-floss-i]][🖼️galtzo-floss]")
      expect(final_content).to include("[![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang]")
      expect(final_content).to include("[![acme Logo by Aboling0, CC BY-SA 4.0][🖼️acme-i]][🖼️acme]")
      expect(final_content).to include("[![example-gem Logo by Aboling0, CC BY-SA 4.0][🖼️acme-example-gem-i]][🖼️acme-example-gem]")
      expect(final_content).to include("[🖼️galtzo-floss]: https://discord.gg/3qme4XHNKN")
      expect(final_content).to include("[🖼️acme-i]: https://logos.galtzo.com/assets/images/acme/avatar-128px.svg")
      expect(final_content).to include("[🖼️acme-example-gem]: https://github.com/acme/example-gem")
      expect(final_content).not_to include("unknown")
    end
  end

  it "deduplicates README logos by asset while preserving the related-org link" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-duplicate-logo-assets-slice", tmp_root) do |root|
      write_tree(root, {
        "turbo_tests2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "turbo_tests2"
            spec.summary = "Turbo tests"
            spec.metadata["source_code_uri"] = "https://github.com/galtzo-floss/turbo_tests2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: related-org,ruby,org,project
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("[🖼️galtzo-floss]: https://discord.gg/3qme4XHNKN")
      expect(final_content).not_to include("[🖼️galtzo-floss]: https://github.com/galtzo-floss")
      expect(final_content.scan("galtzo-floss/avatar-192px.svg").length).to eq(1)
      expect(final_content).to include("[![turbo_tests2 Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-floss-turbo_tests2-i]][🖼️galtzo-floss-turbo_tests2]")
    end
  end

  it "maps legacy README top logo modes to named logo options" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-legacy-logo-mode-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logo_mode: org
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Galtzo FLOSS Logo")
      expect(final_content).to include("ruby-lang Logo")
      expect(final_content).to include("acme Logo")
      expect(final_content).not_to include("example-gem Logo")
    end
  end

  it "projects configured README logo row entries by normalized logo type" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-typed-logo-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            logo_row:
              enabled: true
              logos:
                - type: language
                  slug: ruby-lang
                  alt: Ruby language logo
                - type: org
                  slug: acme
                  alt: Acme org logo
                - type: affiliated_project
                  slug: tree-sitter/tree-sitter
                  alt: Tree-sitter project logo
                - type: project
                  slug: acme/ignored
                  alt: Ignored fourth logo
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("[![Ruby language Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang]")
      expect(final_content).to include("[![Acme org Logo by Aboling0, CC BY-SA 4.0][🖼️acme-i]][🖼️acme]")
      expect(final_content).to include("[![Tree-sitter project Logo by Aboling0, CC BY-SA 4.0][🖼️tree-sitter-tree-sitter-i]][🖼️tree-sitter-tree-sitter]")
      expect(final_content).to include("[![Ignored fourth Logo by Aboling0, CC BY-SA 4.0][🖼️acme-ignored-i]][🖼️acme-ignored]")
      expect(final_content).to include("[🖼️tree-sitter-tree-sitter-i]: https://logos.galtzo.com/assets/images/tree-sitter/tree-sitter/avatar-128px.svg")
    end
  end

  it "omits the deprecated secure installation section from packaged README templates" do
    template_root = described_class::PACKAGED_TEMPLATE_ROOT

    expect(File.read(File.join(template_root, "README.md.example"))).not_to include("### 🔒 Secure Installation")
  end

  it "projects RuboCop LTS template tokens from minimum Ruby" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubocop-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.1"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/style.gemfile
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_gemfiles_modular_style_gemfile"
      end
      expect(template_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: "gemfiles/modular/style.gemfile.example",
        source_relative_path: "gemfiles/modular/style.gemfile.example",
        source_root: "packaged"
      )
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include(
        "We run rubocop on the latest version of Ruby"
      )
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-lts", "~> 22.0"')
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-ruby3_1"')
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|RUBOCOP_LTS_CONSTRAINT" => "~> 22.0",
        "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby3_1"
      )
    end
  end

  it "fails fast when template application leaves unresolved tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-unresolved-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN,
          # {KJ|UNKNOWN}
        MARKDOWN
      })

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /unresolved kettle-jem template tokens: \{KJ\|UNKNOWN\}/)
    end
  end

  it "reports template checksum drift" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-drift-slice", tmp_root) do |root|
      write_tree(root, {
        "templates/README.md.example" => "# Example\n",
        "templates/.github/FUNDING.yml.example" => "github: [example]\n",
        ".kettle-jem.yml" => <<~YAML,
          project: example

          kettle-jem:
            version: "0.1.0"
            checksums:
              "README.md.example": "old"
              "removed.md.example": "gone"
        YAML
      })

      current = described_class::TemplateChecksums.compute(template_root: File.join(root, "templates"))
      stored = described_class::TemplateChecksums.load_stored(config_path: File.join(root, ".kettle-jem.yml"))
      drift = described_class::TemplateChecksums.diff(current: current, stored: stored)

      expect(current.keys).to eq([".github/FUNDING.yml.example", "README.md.example"])
      expect(drift).to eq(
        added: [".github/FUNDING.yml.example"],
        changed: ["README.md.example"],
        removed: ["removed.md.example"]
      )
      expect(described_class::TemplateChecksums.diff_count(drift)).to eq(3)
      expect(described_class::TemplateChecksums.summary(drift)).to eq(
        "3 template file(s) since last run: 1 added, 1 changed, 1 removed"
      )
      expect(described_class::TemplateChecksums.detail_lines(drift)).to eq([
        "  + .github/FUNDING.yml.example",
        "  ~ README.md.example",
        "  - removed.md.example",
      ])

      described_class::TemplateChecksums.write_to_config(
        config_path: File.join(root, ".kettle-jem.yml"),
        checksums: current,
        version: "1.2.3"
      )
      rewritten = YAML.safe_load_file(File.join(root, ".kettle-jem.yml"))
      expect(rewritten.fetch("kettle-jem").fetch("version")).to eq("1.2.3")
      expect(rewritten.fetch("kettle-jem").fetch("checksums")).to eq(current)
    end
  end

  it "reports duplicate drift during template apply runs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-duplicate-drift-apply", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "# Example\n",
      })
      calls = []
      runner = lambda do |project_root:, template_dir:|
        calls << { project_root: project_root, template_dir: template_dir }
        {
          warning_count: 1,
          json_path: File.join(project_root, "tmp", "kettle-jem", "dup-check.json"),
          lock_path: File.join(project_root, ".kettle-drift.lock"),
          exit_code: 1,
        }
      end

      apply = described_class.apply_project(root, env: {}, run_options: { duplicate_drift_runner: runner })

      expect(calls).to eq([{ project_root: root, template_dir: File.join(root, "template") }])
      expect(apply.fetch(:duplicate_drift)).to include(
        available: true,
        warning_count: 1,
        json_path: File.join(root, "tmp", "kettle-jem", "dup-check.json"),
        lock_path: File.join(root, ".kettle-drift.lock"),
        exit_code: 1
      )
    end
  end

  it "exposes template root and manifest metadata for adjacent tools" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-manifest", tmp_root) do |root|
      write_tree(root, {
        "template/README.md.example" => "# Example\n",
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      expect(described_class.packaged_template_root).to eq(described_class::PACKAGED_TEMPLATE_ROOT)
      expect(described_class.template_root_path(root)).to eq(File.join(root, "template"))

      manifest = described_class.template_manifest(project_root: root)
      expect(manifest).to include(
        kind: "kettle_jem_template_manifest",
        version: 1,
        template_root: File.join(root, "template")
      )
      expect(manifest.fetch(:checksums).keys).to eq(["README.md.example"])
    end
  end

  it "renders self-test and templating diagnostics reports" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-self-test-report-slice", tmp_root) do |root|
      before = File.join(root, "before")
      after = File.join(root, "after")
      write_tree(before, {
        "same.txt" => "same\n",
        "changed.txt" => "before\n",
        "removed.txt" => "removed\n",
      })
      write_tree(after, {
        "same.txt" => "same\n",
        "changed.txt" => "after\n",
        "added.txt" => "added\n",
      })

      comparison = described_class::SelfTest::Manifest.compare(
        described_class::SelfTest::Manifest.generate(before),
        described_class::SelfTest::Manifest.generate(after)
      ).merge(skipped: ["lib/internal.rb"])
      expect(comparison).to include(
        matched: ["same.txt"],
        changed: ["changed.txt"],
        added: ["added.txt"],
        removed: ["removed.txt"],
        skipped: ["lib/internal.rb"]
      )

      snapshot = {
        workspace_root: root,
        kettle_jem: {
          name: "kettle-jem",
          version: "1.2.3",
          path: File.join(root, "installed", "kettle-jem"),
          local_path: false,
          loaded: true,
        },
        merge_gems: [
          {
            name: "ast-merge",
            version: "2.0.0",
            path: File.join(root, "ast-merge"),
            local_path: true,
            loaded: true,
          },
          {
            name: "json-merge",
            version: nil,
            path: nil,
            local_path: false,
            loaded: false,
          },
        ],
      }

      self_test_report = described_class::SelfTest::Reporter.summary(
        comparison,
        output_dir: File.join(root, "output"),
        templating_environment: snapshot,
        diff_count: 1,
        now: Time.utc(2026, 5, 14, 12, 0, 0)
      )
      expect(self_test_report).to include("**Score**: 25.0% (1/4 files unchanged)")
      expect(self_test_report).to include("**Divergence**: 75.0% (3/4 files changed, added, or missing)")
      expect(self_test_report).to include("## Changed Files (1)")
      expect(self_test_report).to include("## New Files (1)")
      expect(self_test_report).to include("## Not Templated - Unexpected (1)")
      expect(self_test_report).to include("<summary>Not Templated (1 files) - source-only files not produced by the template task</summary>")
      expect(self_test_report).to include("| ast-merge | 2.0.0 | local path |")
      expect(self_test_report).to include("| json-merge | _not loaded_ | not loaded |")

      run_report = described_class::TemplatingReport.render_markdown(
        project_root: root,
        snapshot: snapshot,
        run_started_at: Time.utc(2026, 5, 14, 12, 0, 0),
        finished_at: Time.utc(2026, 5, 14, 12, 1, 0),
        status: "failed",
        warnings: ["missing service", "missing service"],
        error: RuntimeError.new("boom"),
        template_diff: {added: ["new.md"], changed: ["README.md"], removed: ["old.md"]},
        template_commit_sha: "abc123"
      )
      expect(run_report).to include("# kettle-jem Templating Run Report")
      expect(run_report).to include("**Status**: `failed`")
      expect(run_report).to include("**Template commit**: `abc123`")
      expect(run_report.scan("- missing service").length).to eq(1)
      expect(run_report).to include("## Template File Changes")
      expect(run_report).to include("3 template file(s) since last run: 1 added, 1 changed, 1 removed")
      expect(run_report).to include("RuntimeError: boom")
    end
  end

  it "derives run stats from recipe reports" do
    stats = described_class.recipe_run_stats(
      [
        {changed: true, metadata: {destination_existed: false}},
        {changed: true, metadata: {destination_existed: true}},
        {changed: false, metadata: {destination_existed: true}},
        {changed: true, metadata: {delete_file: true, destination_existed: true}},
      ],
      diagnostics: [
        {kind: "plugin_file_change", path: "PLUGIN.md", action: "replace"},
      ]
    )

    expect(stats).to eq(
      recipes: 4,
      created: 1,
      pre_existing: 2,
      identical: 1,
      changed: 1,
      deleted: 1,
      plugin_file_changes: 1,
      summary: "recipes 4 created 1 pre_existing 2 identical 1 changed 1 deleted 1 plugin_file_changes 1"
    )
  end

  it "reports the Kettle/Jem non-interactive decision policy and recipe defaults" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-decision-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
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
        "README.md" => "# Example\n\nDestination README.\n",
      })

      plan = described_class.plan_project(root, env: {"force" => "true"})
      expect(plan.fetch(:decision_policy)).to include(
        mode: "accept",
        non_interactive: true,
        accept: true,
        interactive: false,
        failure_mode: "error"
      )
      readme_decision = plan.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(readme_decision).to include(
        category: "apply_template_source",
        file: "README.md",
        default_action: "replace",
        selected_action: "replace",
        source: "default",
        severity: "advisory",
        blocking: false
      )
      expect(readme_decision.fetch(:diagnostics)).to include(
        "Non-interactive runs apply the configured template source default and report the decision."
      )

      apply = described_class.apply_project(root, env: {"force" => "false"})
      expect(apply.fetch(:decision_policy)).to include(
        mode: "interactive",
        non_interactive: false,
        accept: false,
        interactive: true
      )
      expect(apply.fetch(:decision_evaluations).map { |decision| decision.fetch(:selected_action) }).to include("replace")
      interactive_readme_decision = apply.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(interactive_readme_decision).to include(
        source: "interactive_default",
        prompt_required: true
      )
      expect(interactive_readme_decision.fetch(:prompt)).to include(
        id: "recipe:template_source_application_README_md",
        category: "apply_template_source",
        file: "README.md",
        default_action: "replace",
        choices: include("create", "replace", "keep", "skip")
      )
      expect(apply.fetch(:prompt_requests)).to include(interactive_readme_decision.fetch(:prompt))
      expect(interactive_readme_decision.fetch(:diagnostics)).to include(
        "Interactive prompt transport is active; selected the configured default pending an external response."
      )

      File.write(File.join(root, "README.md"), "# Example\n\nDestination README.\n")
      answered_apply = described_class.apply_project(
        root,
        env: {},
        run_options: {
          interactive: true,
          prompt_answers: {
            "recipe:readme_metadata" => "keep",
            "recipe:template_source_application_README_md" => "keep",
          },
        }
      )
      answered_decision = answered_apply.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(answered_apply.fetch(:decision_policy)).to include(
        mode: "interactive",
        prompt_answers: {
          "recipe:readme_metadata" => "keep",
          "recipe:template_source_application_README_md" => "keep",
        }
      )
      expect(answered_decision).to include(
        selected_action: "keep",
        source: "interactive_answer",
        prompt_required: true
      )
      expect(answered_decision.fetch(:diagnostics)).to include(
        "Interactive prompt answer supplied through the shared decision policy input contract."
      )
      expect(answered_apply.fetch(:changed_files)).not_to include("README.md")
      expect(File.read(File.join(root, "README.md"))).to eq("# Example\n\nDestination README.\n")
    end
  end

  it "hard-fails decision evaluation only when no fatal default is available" do
    policy = described_class::DecisionPolicy.from_env({"force" => "true"})
    expect do
      policy.resolve(
        id: "parser:README.md",
        category: "parse",
        file: "README.md",
        default_action: nil,
        severity: :fatal
      )
    end.to raise_error(Kettle::Jem::Error, /No safe default decision/)
  end

  it "reports git preflight state and lets skip-commit bypass clean-worktree enforcement" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-preflight", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)

      expect do
        described_class.plan_project(root, env: {"KETTLE_JEM_REQUIRE_CLEAN" => "true"})
      end.to raise_error(Kettle::Jem::Error, /worktree is not clean/)

      plan = described_class.plan_project(root, env: {
        "KETTLE_JEM_REQUIRE_CLEAN" => "true",
        "KETTLE_JEM_SKIP_COMMIT" => "true",
      })
      expect(plan.fetch(:template_selection)).to include(skip_commit: true)
      expect(plan.fetch(:git_preflight)).to include(
        git_repository: true,
        clean_worktree: false,
        skip_commit: true
      )
      expect(plan.fetch(:git_preflight).fetch(:dirty_entries)).not_to be_empty
    end
  end

  it "loads configured plugins and runs apply-time phase hooks" do
    plugin_module = Module.new do
      class << self
        def register_kettle_jem_plugin(registrar)
          registrar.before_phase(:github_workflows) do |context:, phase:, **|
            path = File.join(context.project_root, ".github/FUNDING.yml")
            context.out.report_detail("before #{phase}: funding exists=#{File.exist?(path)}")
          end

          registrar.after_phase(:github_workflows) do |context:, phase:, **|
            path = File.join(context.project_root, ".github/FUNDING.yml")
            context.out.report_detail("after #{phase}: funding exists=#{File.exist?(path)}")
          end

          registrar.after_phase(:remaining_files) do |context:, phase:, phase_stats:, plugin_name:, **|
            path = File.join(context.project_root, "PLUGIN.md")
            File.write(path, "plugin=#{plugin_name}; phase=#{phase}; recipes=#{phase_stats.fetch(:recipe_count)}\n")
            context.helpers.record_template_result(path, :replace)
            context.out.report_detail("plugin hook ran")
          end
        end
      end
    end
    stub_const("Example::Plugin", plugin_module)
    allow(described_class::PluginLoader).to receive(:require).with("example/plugin").and_return(true)

    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-plugin-lifecycle", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          plugins:
            - example-plugin
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(File.exist?(File.join(root, "PLUGIN.md"))).to be(false)
      plan_lifecycle = plan.fetch(:diagnostics).find { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }
      expect(plan_lifecycle).to include(
        loaded_plugins: ["example-plugin"],
        callbacks_run: false
      )
      expect(plan_lifecycle.fetch(:active_runner_phases)).to eq([])
      expect(plan.fetch(:phase_reports).map { |phase_report| phase_report.fetch(:phase) }).to include(
        "github_workflows",
        "remaining_files"
      )
      github_phase = plan.fetch(:phase_reports).find { |phase_report| phase_report.fetch(:phase) == "github_workflows" }
      expect(github_phase.fetch(:changed_files)).to include(".github/FUNDING.yml")
      expect(plan.fetch(:run_stats).fetch(:plugin_file_changes)).to eq(0)

      apply = described_class.apply_project(root, env: {})
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "before github_workflows: funding exists=false"
      )
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "after github_workflows: funding exists=true"
      )
      expect(File.read(File.join(root, "PLUGIN.md"))).to include("plugin=example-plugin; phase=remaining_files; recipes=")
      expect(apply.fetch(:changed_files)).to include("PLUGIN.md")
      expect(apply.fetch(:run_stats).fetch(:plugin_file_changes)).to eq(1)
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_file_change",
        path: "PLUGIN.md",
        action: "replace"
      )
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "plugin hook ran"
      )
      apply_lifecycle = apply.fetch(:diagnostics).select { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }.last
      expect(apply_lifecycle).to include(
        loaded_plugins: ["example-plugin"],
        callbacks_run: true
      )
      expect(apply_lifecycle.fetch(:active_runner_phases)).to eq(described_class::PHASE_ORDER.map(&:to_s))
      expect(apply_lifecycle.fetch(:registered_hooks)).to contain_exactly(
        {
          plugin_name: "example-plugin",
          phase: "github_workflows",
          timing: "before"
        },
        {
          plugin_name: "example-plugin",
          phase: "github_workflows",
          timing: "after"
        },
        {
          plugin_name: "example-plugin",
          phase: "remaining_files",
          timing: "after"
        }
      )
    end
  end
end
