# frozen_string_literal: true

RSpec.describe Kettle::Jem, "GitHub workflow templating" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "does not synthesize a standalone coverage workflow outside the packaged template inventory" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
        ".kettle-jem.yml" => <<~YAML
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

  it "removes legacy tests workflow files as obsolete GitHub Actions workflows" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-obsolete-tests-workflow-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => [
          "templates:",
          "  root: packaged",
          "  apply: true",
          "  entries: []",
          ""
        ].join("\n"),
        ".github/workflows/tests.yml" => <<~YAML
          name: Tests
          on:
            pull_request:
              branches:
                - '!*'
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".github/workflows/tests.yml" }

      expect(report.fetch(:recipe_name)).to eq("github_actions_obsolete_workflow_cleanup_github_workflows_tests_yml")
      expect(report.fetch(:metadata).fetch(:delete_file)).to be(true)
      expect(File).not_to exist(File.join(root, ".github/workflows/tests.yml"))
    end
  end

  it "projects configured workflow exec_cmd into GitHub workflow templates" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
        ".kettle-jem.yml" => [
          "workflows:",
          "  exec_cmd: rake spec",
          "templates:",
          "  root: template",
          "  apply: true",
          "  entries:",
          "    - .github/workflows/current.yml",
          ""
        ].join("\n"),
        "template/.github/workflows/current.yml.example" => <<~YAML
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

      apply = described_class.apply_project(root, env: {"KJ_EXEC_CMD" => "kettle-test"})
      workflow_report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/current.yml"
      end

      expect(workflow_report.fetch(:final_content)).to include('exec_cmd: "kettle-test"')
    end
  end

  it "normalizes obsolete Appraisal-relative workflow exec_cmd values" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-obsolete-exec-cmd-slice", tmp_root) do |root|
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
            exec_cmd: env KETTLE_TEST_RUNNER=rspec kettle-test -I ../spec --options ../.rspec ../spec
          templates:
            root: template
            apply: true
            entries:
              - .github/workflows/current.yml
        YAML
        "template/.github/workflows/current.yml.example" => <<~YAML
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

      apply = described_class.apply_project(root, env: {})
      workflow_report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/current.yml"
      end

      expect(workflow_report.fetch(:final_content)).to include('exec_cmd: "kettle-test"')
    end
  end

  it "fails closed for GitHub YAML template merges when the YAML provider reports a ProcessResult adapter failure" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
        "template/.kettle-jem.yml.example" => <<~YAML
          project: template
          generated: true
        YAML
      })
      allow(Psych::Merge).to receive(:merge_yaml).and_return(
        ok: false,
        diagnostics: [{
          severity: "error",
          category: "unsupported_feature",
          message: "undefined method '[]' for an instance of TreeSitterLanguagePack::ProcessResult"
        }],
        policies: []
      )

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /failed to merge yaml template \.github\/FUNDING\.yml: provider adapter failure/)
    end
  end

  it "fails closed for Gemfile template merges when Prism cannot merge the Ruby DSL" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
              strategy: merge
        YAML
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"
          gem "example", path: "."
        RUBY
        "template/Gemfile.example" => <<~RUBY
          source "https://gem.coop"
          gemspec
          gem "beta-tool"
        RUBY
      })
      allow(Prism::Merge).to receive(:merge_ruby).and_return(
        ok: false,
        diagnostics: [{
          severity: "error",
          category: "unsupported_feature",
          message: "undefined method '[]' for an instance of TreeSitterLanguagePack::ProcessResult"
        }],
        policies: []
      )

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /failed to merge gemfile template Gemfile: provider adapter failure/)
    end
  end

  it "strictly merges arbitrary top-level Gemfile dependencies from a template directory" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-arbitrary-dependency-merge", tmp_root) do |root|
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
              - gemfiles/modular/custom.gemfile
        YAML
        "gemfiles/modular/custom.gemfile" => <<~RUBY,
          source "https://example.invalid"

          gem "alpha-tool", ">= 0.alpha"
        RUBY
        "template/gemfiles/modular/custom.gemfile.example" => <<~RUBY
          source "https://example.invalid"

          gem "alpha-tool", ">= 0.template"
          gem "beta-tool", "~> 0.beta", require: false
        RUBY
      })

      report = described_class.apply_project(root, env: {}).fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_gemfiles_modular_custom_gemfile"
      end

      expect(report.fetch(:final_content)).to eq(<<~RUBY)
        source "https://example.invalid"

        gem "alpha-tool", ">= 0.template"
        gem "beta-tool", "~> 0.beta", require: false
      RUBY
    end
  end

  it "strictly merges arbitrary Gemfile dependency blocks and comments from a template directory" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-arbitrary-block-merge", tmp_root) do |root|
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
              - gemfiles/modular/custom.gemfile
        YAML
        "gemfiles/modular/custom.gemfile" => <<~RUBY,
          source "https://example.invalid"

          # destination alpha comment
          gem "alpha-tool", ">= 0.alpha"

          group :test do
            gem "alpha-test", ">= 0.alpha-test"
          end
        RUBY
        "template/gemfiles/modular/custom.gemfile.example" => <<~RUBY
          source "https://example.invalid"

          # template beta comment
          gem "beta-tool", "~> 0.beta", require: false

          group :test do
            gem "alpha-test", ">= 0.template-test"
            gem "beta-test", "~> 0.beta-test"
          end

          platforms :ruby do
            gem "beta-runtime", ">= 0.beta-runtime"
          end
        RUBY
      })

      report = described_class.apply_project(root, env: {}).fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_gemfiles_modular_custom_gemfile"
      end

      expect(report.fetch(:final_content)).to eq(<<~RUBY)
        source "https://example.invalid"

        # template beta comment
        gem "beta-tool", "~> 0.beta", require: false

        # destination alpha comment
        gem "alpha-tool", ">= 0.alpha"

        group :test do
          gem "alpha-test", ">= 0.template-test"
          gem "beta-test", "~> 0.beta-test"
        end

        platforms :ruby do
          gem "beta-runtime", ">= 0.beta-runtime"
        end
      RUBY
    end
  end

  it "merges custom workflow YAML snippets without replacing destination jobs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-custom-workflow-yaml-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".github/workflows/custom-ci.yml" => <<~YAML
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
      expect_pinned_action(content, "actions/checkout")
      expect_pinned_action(content, "ruby/setup-ruby")
      expect_pinned_action(content, "actions/upload-artifact")
      expect_pinned_action(content, "codecov/codecov-action")
      expect_pinned_action(content, "coverallsapp/github-action")
      expect_pinned_action(content, "actions/dependency-review-action")
      expect_pinned_action(content, "github/codeql-action/init")
      expect_pinned_action(content, "github/codeql-action/autobuild")
      expect_pinned_action(content, "github/codeql-action/analyze")
      expect_pinned_action(content, "pozil/auto-assign-issue")
      expect_pinned_action(content, "apache/skywalking-eyes/dependency")
      expect_pinned_action(content, "sarisia/actions-status-discord")
      expect(content).to include("Project-specific check")
      expect(content).to include("bundle exec rake custom")
      expect(content).to end_with("\n")
    end
  end

  it "normalizes GitHub Action refs when merging packaged workflow templates" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-workflow-action-pin-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.4"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          ruby:
            test_minimum: "2.4"
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.4.yml
        YAML
        ".github/workflows/ruby-2.4.yml" => <<~YAML
          name: Ruby 2.4
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
        candidate.fetch(:relative_path) == ".github/workflows/ruby-2.4.yml"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:recipe_name)).to start_with("template_source_application_")
      expect_pinned_action(content, "actions/checkout")
      expect_pinned_action(content, "ruby/setup-ruby")
      expect(content).not_to include("actions/checkout@v6")
      expect(content).not_to include("ruby/setup-ruby@v1")
    end
  end

  it "preserves newer destination GitHub Action SHA pins when accepting workflow templates" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-action-pin-preserve-slice", tmp_root) do |root|
      newer_checkout_sha = "1111111111111111111111111111111111111111"
      template_checkout_sha = "9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
      destination_setup_ruby_sha = "2222222222222222222222222222222222222222"
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
            root: template
            apply: true
            entries:
              - .github/workflows/current.yml
          patterns:
            - path: ".github/workflows/**"
              strategy: accept_template
        YAML
        ".github/workflows/current.yml" => <<~YAML,
          name: Current
          jobs:
            test:
              steps:
                - uses: actions/checkout@#{newer_checkout_sha} # v7.0.0
                - uses: ruby/setup-ruby@#{destination_setup_ruby_sha} # v1.0.0
        YAML
        "template/.github/workflows/current.yml.example" => <<~YAML
          name: Current
          jobs:
            test:
              steps:
                - uses: actions/checkout@#{template_checkout_sha} # v7.0.0
                - uses: ruby/setup-ruby@v1
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/current.yml"
      end
      content = report.fetch(:final_content)

      expect(report.dig(:metadata, :template_source_preference)).to include(strategy: "accept_template")
      expect(content).to include("actions/checkout@#{newer_checkout_sha} # v7.0.0")
      expect(content).not_to include("actions/checkout@#{template_checkout_sha} # v7.0.0")
      expect_pinned_action(content, "ruby/setup-ruby")
      expect(content).not_to include("ruby/setup-ruby@v1")
      expect(report.dig(:metadata, :stale_github_workflow_template_pins)).to contain_exactly(
        include(
          path: ".github/workflows/current.yml",
          action: "actions/checkout",
          version: "v7.0.0",
          preserved_sha: newer_checkout_sha,
          template_sha: template_checkout_sha
        )
      )
      expect(plan.fetch(:warnings)).to contain_exactly(
        include("GitHub Actions template pins appear stale for .github/workflows/current.yml")
      )
    end
  end

  it "normalizes GitHub Action refs in existing workflows outside the active recipe set" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-unmanaged-workflow-action-pin-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.4"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          repository:
            topology: monorepo-subproject
        YAML
        ".github/workflows/current.yml" => <<~YAML
          name: Current MRI
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - name: Checkout
                  uses: actions/checkout@v6
                - name: Setup Ruby
                  uses: ruby/setup-ruby@v1
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      content = File.read(File.join(root, ".github/workflows/current.yml"))
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "github_actions_pin_sync" }

      expect(post_step).to include(
        status: "applied",
        changed_files: [".github/workflows/current.yml"]
      )
      expect_pinned_action(content, "actions/checkout")
      expect_pinned_action(content, "ruby/setup-ruby")
      expect(content).not_to include("actions/checkout@v6")
      expect(content).not_to include("ruby/setup-ruby@v1")
    end
  end

  it "deletes skipped packaged workflows that already exist" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
          ruby:
            test_minimum: "2.3"
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.3.yml
        YAML
        ".github/workflows/ruby-2.3.yml" => <<~YAML
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

  it "deletes legacy dashed Ruby workflow files when dotted packaged workflows replace them" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-legacy-dashed-ruby-workflow-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.4"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          ruby:
            test_minimum: "2.4"
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.4.yml
        YAML
        ".github/workflows/ruby-2-4.yml" => <<~YAML
          name: MRI 2.4
          jobs:
            test:
              runs-on: ubuntu-22.04
              steps:
                - uses: actions/checkout@v6
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/ruby-2-4.yml"
      end

      expect(report.fetch(:recipe_name)).to start_with("github_actions_inactive_packaged_workflow_cleanup_")
      expect(report.fetch(:metadata)).to include(delete_file: true)
    end
  end

  it "does not allow generated CI Ruby floor below 2.4" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ci-floor-minimum-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          ruby:
            test_minimum: "2.3"
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.3.yml
        YAML
        ".github/workflows/ruby-2.3.yml" => <<~YAML
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
      expect(plan.dig(:facts, :ci, :test_min_ruby)).to eq("2.4")
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".github/workflows/ruby-2.3.yml"
      end

      expect(report.fetch(:recipe_name)).to start_with("github_actions_inactive_packaged_workflow_cleanup_")
      expect(report.fetch(:metadata)).to include(delete_file: true)
    end
  end

  it "deletes skipped packaged workflows for monorepo subgem profiles" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-subgem-skipped-workflow-slice", tmp_root) do |root|
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
            profile: monorepo-subgem
            root: packaged
            apply: true
            entries:
              - .github/workflows/ruby-2.3.yml
        YAML
        ".github/workflows/ruby-2.3.yml" => <<~YAML
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
        ".github/workflows/discord-notifier.yml" => "name: stale notifier\n"
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
        run_options: {include: ".github/workflows/discord-notifier.yml"}
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
        ".github/workflows/framework-ci.yml" => "name: stale framework\n"
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
            gem: rails
            versions:
              - "7.0"
              - label: "7.1+"
                slug: "7_1"
                requirement: ">= 7.1"
                appraisal: ruby-3-2
            gemfile_pattern: rails_{version}
        templates:
          root: packaged
          apply: true
          entries:
            - Appraisals
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
      expect(content).to include("        framework:")
      expect(content).to include('          - framework_version: "7.0"')
      expect(content).to include('            appraisal: "rails-7-0"')
      expect(content).to include('          - framework_version: "7.1+"')
      expect(content).to include('            appraisal: "ruby-3-2"')
      expect(YAML.safe_load(content)).to be_a(Hash)
      expect(content).to include("Appraisal.root.gemfile")
      expect(content).to include("framework:")

      appraisals_report = configured_plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "Appraisals"
      end
      appraisals_content = appraisals_report.fetch(:final_content)
      expect(appraisals_content).to include('appraise "ruby-3-2" do')
      expect(appraisals_content).to include('eval_gemfile "rails_7_1"')
      expect(content).to include("bundle exec appraisal ${{ matrix.framework.appraisal }} install")
      expect(content).not_to include("framework_version: []")
      expect(content).not_to include("gemfile: []")

      gemfile_report = configured_plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/rails_7_1"
      end
      expect(gemfile_report.fetch(:final_content)).not_to include("eval_gemfile")
      expect(gemfile_report.fetch(:final_content)).to include('gem "rails", ">= 7.1"')

      default_requirement_report = configured_plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/rails_7_0"
      end
      expect(default_requirement_report.fetch(:final_content)).to include('gem "rails", "~> 7.0.0"')

      appraisals_report = configured_plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "Appraisals"
      end
      expect(appraisals_report.fetch(:final_content)).to include('appraise "ruby-3-2" do')
      expect(appraisals_report.fetch(:final_content)).to include('eval_gemfile "rails_7_1"')
    end
  end

  it "prunes packaged workflow files by configured engines and minimum Ruby" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
        ".kettle-jem.yml" => <<~YAML
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

  it "prunes disabled engine jobs from packaged multi-engine workflows" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-job-prune-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          engines:
            - ruby
          templates:
            root: packaged
            apply: true
            entries:
              - .github/workflows/heads.yml
              - .github/workflows/dep-heads.yml
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      reports = plan.fetch(:recipe_reports).each_with_object({}) do |report, index|
        index[report.fetch(:relative_path)] = report
      end

      %w[.github/workflows/heads.yml .github/workflows/dep-heads.yml].each do |path|
        content = reports.fetch(path).fetch(:final_content)
        workflow = YAML.safe_load(content, permitted_classes: [], aliases: true)

        expect(workflow.fetch("jobs").keys).to eq(["ruby"])
        expect(content).not_to include("  truffleruby:")
        expect(content).not_to include("  jruby:")
      end
    end
  end

  it "prunes versioned engine workflows below minimum Ruby compatibility" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
              - .github/workflows/jruby-10.0.yml
              - .github/workflows/truffleruby-23.0.yml
              - .github/workflows/truffleruby-23.1.yml
              - .github/workflows/truffleruby-33.0.yml
        YAML
        ".github/workflows/truffleruby-23.2.yml" => <<~YAML
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
      expect(paths).to include(".github/workflows/jruby-10.0.yml")
      expect(paths).not_to include(".github/workflows/truffleruby-23.0.yml")
      expect(paths).not_to include(".github/workflows/truffleruby-23.1.yml")
      expect(paths).to include(".github/workflows/truffleruby-33.0.yml")
      expect(stale_report).to include(
        recipe_name: "github_actions_inactive_packaged_workflow_cleanup_github_workflows_truffleruby_23_2_yml",
        changed: true
      )
      expect(stale_report.dig(:metadata, :delete_file)).to be(true)
    end
  end

  it "prunes packaged gemfile templates below minimum Ruby" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
        "gemfiles/modular/x_std_libs/r2.3/libs.gemfile" => "stale ruby 2.3 gemfile\n"
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

  it "prunes packaged recording gemfile templates unless recording is configured" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-recording-gemfile-slice", tmp_root) do |root|
      recording_path = "gemfiles/modular/recording/r4/recording.gemfile"
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
              - #{recording_path}
        YAML
        recording_path => "stale recording gemfile\n"
      })

      plan = described_class.plan_project(root, env: {})
      cleanup_report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == recording_path
      end
      expect(cleanup_report.fetch(:recipe_name)).to start_with("template_inactive_packaged_cleanup_")
      expect(cleanup_report.fetch(:metadata)).to include(delete_file: true)

      write_tree(root, {
        ".kettle-jem.yml" => <<~YAML
          workflows:
            recording: true
          templates:
            root: packaged
            apply: true
            entries:
              - #{recording_path}
        YAML
      })

      opted_in = described_class.plan_project(root, env: {})
      paths = opted_in.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }
      expect(paths).to include(recording_path)
      expect(opted_in.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == recording_path }.fetch(:recipe_name)).not_to start_with("template_inactive_packaged_cleanup_")
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

  it "updates root templating bootstrap dependencies before generated templating workflow commands run" do
    workflow = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, ".github/workflows/templating.yml.example"))

    expect(workflow).to include("- name: Update templating bootstrap dependencies")
    expect(workflow).to include("BUNDLE_GEMFILE: ${{ github.workspace }}/Gemfile")
    expect(workflow).to include("K_JEM_TEMPLATING: \"true\"")
    expect(workflow).to include("run: bundle update nomono")
    expect(workflow.index("Update templating bootstrap dependencies")).to be < workflow.index("[Attempt 1] Appraisal")
  end
end
