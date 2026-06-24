# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Kettle::Jem do
  around do |example|
    tmp_root = File.join(__dir__, "tmp")
    previous_ceiling = ENV.fetch("GIT_CEILING_DIRECTORIES", nil)
    isolated_env_keys = ENV.keys.grep(/\AKJ_|KETTLE_JEM_|OPENCOLLECTIVE_HANDLE|FUNDING_ORG|K_JEM_TEMPLATING/)
    previous_env = isolated_env_keys.to_h { |key| [key, ENV[key]] }
    # rubocop:disable Env/Assign
    isolated_env_keys.each { |key| ENV.delete(key) }
    ENV["GIT_CEILING_DIRECTORIES"] = [previous_ceiling, tmp_root].compact.reject(&:empty?).join(File::PATH_SEPARATOR)
    # rubocop:enable Env/Assign
    described_class::GemSpecReader.clear_cache!
    example.run
  ensure
    described_class::GemSpecReader.clear_cache!
    # rubocop:disable Env/Assign
    isolated_env_keys.to_a.each { |key| ENV.delete(key) }
    previous_env.to_h.each { |key, value| ENV[key] = value }
    if previous_ceiling.nil?
      ENV.delete("GIT_CEILING_DIRECTORIES")
    else
      ENV["GIT_CEILING_DIRECTORIES"] = previous_ceiling
    end
    # rubocop:enable Env/Assign
  end

  def json_ready(value)
    JSON.parse(JSON.generate(value), symbolize_names: true)
  end

  def kettle_jem_handoff_command(*args)
    [
      "bundle",
      "exec",
      "ruby",
      "-e",
      %(load Gem.bin_path("kettle-jem", "kettle-jem")),
      "--",
      *args
    ]
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

  def normalize_workflow_pins_for_spec(value)
    case value
    when Hash
      value.to_h { |key, item| [key, normalize_workflow_pins_for_spec(item)] }
    when String
      value.gsub(%r{([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?@)[a-f0-9]{40}(\s+#\s+v?[^\s]+)}, "\\1<sha> # <version>")
    else
      value
    end
  end

  def expect_pinned_action(content, action)
    expect(content).to match(%r{#{Regexp.escape(action)}@[a-f0-9]{40}\s+#\s+v?[^\s]+})
  end

  def prism_string_argument(call, index = 0)
    argument = call&.arguments&.arguments&.[](index)
    argument.unescaped if argument.is_a?(::Prism::StringNode)
  end

  def appraisals_eval_gemfile_paths(content, appraisal_name)
    result = ::Prism.parse(content.to_s)
    raise "invalid Appraisals fixture" unless result.success?

    calls = result.value.breadth_first_search_all { |node| node.is_a?(::Prism::CallNode) }
    appraise = calls.find { |call| call.name == :appraise && prism_string_argument(call) == appraisal_name }
    return [] unless appraise

    calls.filter_map do |call|
      next unless call.name == :eval_gemfile
      next unless call.location.start_line >= appraise.location.start_line
      next unless call.location.end_line <= appraise.location.end_line

      prism_string_argument(call)
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

  it "removes obsolete SimpleCov setup calls from .simplecov while preserving local config" do
    content = <<~RUBY
      # kettle-jem:freeze
      # local coverage note
      # kettle-jem:unfreeze
      require "kettle/soup/cover/config"

      SimpleCov.configure do
        track_files "lib/**/*.rb"
        custom_setting "kept"
      end

      SimpleCov.start do
        track_files "lib/**/*.rb"
        track_files "exe/*.rb"
      end

      custom_after_config
    RUBY

    output = described_class.send(:normalize_simplecov_template_source, content)

    expect(output).to include("# local coverage note")
    expect(output).to include("SimpleCov.configure do")
    expect(output).to include('cover "lib/**/*.rb"')
    expect(output).to include('custom_setting "kept"')
    expect(output).to include("custom_after_config")
    expect(output).not_to include('require "kettle/soup/cover/config"')
    expect(output).not_to include("SimpleCov.start")
    expect(output).not_to include("track_files")
  end

  it "removes obsolete .simplecov keep_destination config during config sync" do
    content = <<~YAML
      defaults:
        preference: "template"
      files:
        AGENTS.md:
          strategy: accept_template
        .simplecov:
          strategy: keep_destination
        Rakefile:
          strategy: accept_template
    YAML

    output = described_class.send(:sync_kettle_config_env_overrides, content, {})

    expect(output).to include("AGENTS.md:")
    expect(output).to include("Rakefile:")
    expect(output).not_to include(".simplecov:")
  end

  it "normalizes stale spec helper SimpleCov bootstrap without dropping local wiring" do
    content = <<~RUBY
      # frozen_string_literal: true

      require_relative "support/local"

      begin
        require "kettle-soup-cover"
        if Kettle::Soup::Cover::DO_COV
          require "simplecov"
          SimpleCov.start
        end
        require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
      rescue LoadError => error
        raise error unless error.message.include?("kettle")
      end

      require "kettle/test/rspec"
      require "example"
    RUBY

    output = described_class.send(:normalize_spec_helper_simplecov_template_source, content)

    expect(output).to include('require_relative "support/local"')
    expect(output.scan('require "simplecov"').size).to eq(1)
    expect(output.index('require "simplecov"')).to be < output.index('require "kettle/soup/cover/config"')
    expect(output.index('require "kettle/soup/cover/config"')).to be < output.index("SimpleCov.start")
    expect(output).not_to include("`.simplecov` is run here")
  end

  it "updates old generated SimpleCov files in the same templating pass that removes keep_destination" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-simplecov-migration", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML,
          project_emoji: 🧪
          templates:
            root: packaged
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
              - .simplecov
              - spec/spec_helper.rb
          rubygems:
            entrypoint_require: "example"
            namespace: "Example"
          files:
            .simplecov:
              strategy: keep_destination
        YAML
        ".simplecov" => <<~RUBY,
          require "kettle/soup/cover/config"

          SimpleCov.start do
            track_files "lib/**/*.rb"
          end
        RUBY
        "spec/spec_helper.rb" => <<~RUBY
          # frozen_string_literal: true

          begin
            require "kettle-soup-cover"
            if Kettle::Soup::Cover::DO_COV
              require "simplecov"
              SimpleCov.start
            end
            require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
          rescue LoadError => error
            raise error unless error.message.include?("kettle")
          end

          require "example"
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      simplecov = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".simplecov" }
      spec_helper = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "spec/spec_helper.rb" }
      kettle_config = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }

      expect(simplecov.fetch(:final_content)).to include('cover "lib/**/*.rb"')
      expect(simplecov.fetch(:final_content)).not_to include("SimpleCov.start")
      expect(simplecov.fetch(:final_content)).not_to include('require "kettle/soup/cover/config"')
      expect(spec_helper.fetch(:final_content).scan('require "simplecov"').size).to eq(1)
      expect(spec_helper.fetch(:final_content)).to include('require "kettle/soup/cover/config"')
      expect(kettle_config.fetch(:final_content)).not_to include(".simplecov:")
    end
  end

  it "converts an implementation-shaped gem into a shim profile gem" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-shim-slice", tmp_root) do |root|
      write_tree(
        root,
        {
          ".structuredmerge/kettle-jem.yml" => <<~YAML,
            project_emoji: "*"

            rubygems:
              name: legacy-shim
              entrypoint_require: legacy/shim
              namespace: Legacy::Shim
              min_ruby: "2.2"

            shim:
              replacement_gem: legacy-shim2
              replacement_require: legacy-shim2
              legacy_requires:
                - legacy/strategies/shim

            templates:
              root: packaged
              apply: true
              profile: shim

            tokens:
              author:
                name: Ada Lovelace
                email: ada@example.com
          YAML
          "legacy-shim.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "legacy-shim"
              spec.version = "0.1.0"
              spec.authors = ["Ada Lovelace"]
              spec.email = ["ada@example.com"]
              spec.summary = "Legacy implementation"
              spec.description = "Legacy implementation"
              spec.homepage = "https://github.com/example/legacy-shim"
              spec.licenses = ["MIT"]
              spec.required_ruby_version = ">= 2.2"
              spec.add_dependency "old-implementation"
            end
          RUBY
          "README.md" => "# Old implementation README\n",
          "Gemfile" => "source \"https://rubygems.org\"\n",
          "Rakefile" => "task :old\n",
          "lib/legacy/shim.rb" => "require \"old-implementation\"\n",
          "lib/legacy/shim/version.rb" => "module Legacy; module Shim; VERSION = \"0.1.0\"; end; end\n",
          "lib/legacy/strategies/shim.rb" => "class OldStrategy; end\n",
          "spec/lib/legacy/strategies/shim_spec.rb" => "RSpec.describe OldStrategy\n",
          "spec/support/helper.rb" => "# old helper\n",
          "gemfiles/legacy.gemfile" => "gem \"old-implementation\"\n",
          ".github/workflows/coverage.yml" => "name: Coverage\n"
        }
      )
      system("git", "-C", root, "init", "--quiet")
      system("git", "-C", root, "add", "legacy-shim.gemspec", "lib/legacy/shim/version.rb")

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :shim, :replacement_gem)).to eq("legacy-shim2")
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe[:name] }
      expect(recipe_names).to include("template_source_application_legacy_shim_gemspec")
      expect(recipe_names).to include("template_shim_profile_cleanup_gemfiles_legacy_gemfile")
      expect(recipe_names).to include("template_shim_profile_cleanup_spec_lib_legacy_strategies_shim_spec_rb")

      described_class.apply_project(root, env: {})

      generated = project_files(
        root,
        [
          "legacy-shim.gemspec",
          "lib/legacy/shim.rb",
          "lib/legacy/shim/version.rb",
          "lib/legacy/strategies/shim.rb",
          "spec/shim_spec.rb",
          "README.md",
          "Gemfile",
          "gemfiles/modular/templating.gemfile",
          "gemfiles/modular/templating_local.gemfile",
          "gemfiles/legacy.gemfile",
          "spec/lib/legacy/strategies/shim_spec.rb",
          ".github/workflows/coverage.yml"
        ]
      )
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.version = "0.1.0"))
      expect(generated[:"legacy-shim.gemspec"]).not_to include(%(load "lib/legacy/shim/version.rb"))
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.add_dependency "legacy-shim2"))
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.add_development_dependency("kettle-dev", "~> 2.2", ">= 2.2.18")))
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.add_development_dependency("kettle-test", "~> 2.0", ">= 2.0.7")))
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.add_development_dependency("stone_checksums", "~> 1.0", ">= 1.0.3")))
      expect(generated[:Gemfile]).to include(%(source "https://gem.coop"))
      expect(generated[:Gemfile]).to include(%(gem "nomono", "~> 1.0", ">= 1.0.6"))
      expect(generated[:Gemfile]).to include(%(eval_gemfile "gemfiles/modular/templating.gemfile"))
      expect(generated[:Gemfile]).not_to include("git:")
      expect(generated[:"gemfiles/modular/templating.gemfile"]).to include(%(gem "appraisal2-rubocop", "~> 0.2", ">= 0.2.2", require: false))
      expect(generated[:"gemfiles/modular/templating.gemfile"]).to include(%(gem "kettle-jem", ">= 7.0"))
      expect(generated[:"gemfiles/modular/templating_local.gemfile"]).to include(%(smorg_rb_local_gems = %w[))
      expect(generated[:"legacy-shim.gemspec"]).not_to include("old-implementation")
      expect(generated[:"lib/legacy/shim.rb"]).to include(%(require "legacy-shim2"))
      expect(generated[:"lib/legacy/strategies/shim.rb"]).to include(%(require "legacy/shim"))
      expect(generated[:"spec/shim_spec.rb"]).to include(%(require("legacy-shim2")))
      expect(generated[:"README.md"]).to include("compatibility shim for `legacy-shim2`")
      expect(generated[:"gemfiles/legacy.gemfile"]).to be_nil
      expect(generated[:"spec/lib/legacy/strategies/shim_spec.rb"]).to be_nil
      expect(generated[:".github/workflows/coverage.yml"]).to be_nil

      File.write(File.join(root, "legacy-shim.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          load "lib/legacy/shim/version.rb"
          spec.name = "legacy-shim"
          spec.version = Legacy::Shim::Version::VERSION
          spec.authors = ["Ada Lovelace"]
          spec.email = ["ada@example.com"]
          spec.summary = "Legacy implementation"
          spec.description = "Legacy implementation"
          spec.homepage = "https://github.com/example/legacy-shim"
          spec.licenses = ["MIT"]
          spec.required_ruby_version = ">= 2.2"
        end
      RUBY
      expect { described_class.plan_project(root, env: {}) }.not_to raise_error
    end
  end

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
      expect_pinned_action(custom_ci_report.fetch(:final_content), "actions/checkout")
      expect_pinned_action(custom_ci_report.fetch(:final_content), "ruby/setup-ruby")
      expect(custom_ci_report.fetch(:final_content)).to include("Upload coverage to Coveralls")
      expect_pinned_action(custom_ci_report.fetch(:final_content), "qltysh/qlty-action/coverage")
      expect(custom_ci_report.fetch(:final_content)).to include("oidc: true")
      expect(custom_ci_report.fetch(:final_content)).not_to include("QLTY_COVERAGE_TOKEN")
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
      expect(normalize_workflow_pins_for_spec(project_files(root, fixture.fetch(:expected).fetch(:files).keys.map(&:to_s)))).to eq(
        normalize_workflow_pins_for_spec(fixture.fetch(:expected).fetch(:files))
      )
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
    tmp_root = File.join(__dir__, "tmp")
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
    tmp_root = File.join(__dir__, "tmp")
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
          source "https://gem.coop"
          gem "example", path: "."
        RUBY
        "template/Gemfile.example" => <<~RUBY
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
          message: "undefined method '[]' for an instance of TreeSitterLanguagePack::ProcessResult"
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
    tmp_root = File.join(__dir__, "tmp")
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
    tmp_root = File.join(__dir__, "tmp")
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
    tmp_root = File.join(__dir__, "tmp")
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
    tmp_root = File.join(__dir__, "tmp")
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
    tmp_root = File.join(__dir__, "tmp")
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
        "README.md" => <<~MARKDOWN
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
      expect(report.dig(:metadata, :readme_style, :disabled_integrations)).to contain_exactly("coveralls", "skywalking-eyes")
      expect(report.dig(:metadata, :readme_style, :missing_integrations)).to contain_exactly("codecov", "qlty", "codeql")
    end
  end

  it "creates a package README through the packaged README style API" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-api-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
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
        "CHANGELOG.md" => <<~MARKDOWN
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
        "README.md" => <<~MARKDOWN
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
        ".kettle-jem.yml" => <<~YAML
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
      expect(plan.fetch(:final_content)).to include("K_JEM_TEMPLATING=true kettle-jem install")
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
        ".github/workflows/opencollective.yml" => <<~YAML
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
        ".kettle-jem.yml" => <<~YAML
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
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|GEM_NAME}

          spec.add_dependency("{KJ|GEM_NAME}", "~> {KJ|GEM_MAJOR}.0")

          [🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).to include("KLOC-4.000-FFDD67.svg")
      expect(readme).to include('spec.add_dependency("example", "~> 1.0")')
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "keeps shim-only template files out of full profile inventory" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-inventory-profile-slice", tmp_root) do |root|
      template_root = File.join(root, "template")
      write_tree(template_root, {
        "README.md.example" => "readme",
        "shim/.structuredmerge/kettle-jem.yml.example" => "{KJ|SHIMMED_GEM_NAME}"
      })

      full_entries = described_class.send(
        :template_inventory_entries,
        root,
        template_root,
        templates: {"profile" => "full"}
      )
      shim_entries = described_class.send(
        :template_inventory_entries,
        root,
        template_root,
        templates: {"profile" => "shim"}
      )

      expect(full_entries).to include("README.md")
      expect(full_entries).not_to include("shim/.structuredmerge/kettle-jem.yml")
      expect(shim_entries).to include("shim/.structuredmerge/kettle-jem.yml")
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
              - FUNDING.md
          files:
            README.md:
              strategy: accept_template
        YAML
        ".github/workflows/current.yml" => "name: Current\n"
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)
      funding = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_FUNDING_md"
      end.fetch(:final_content)

      expect(readme).not_to include("Open Source Helpers")
      expect(readme).not_to include("codetriage")
      expect(readme).not_to include("OpenCollective Backers")
      expect(readme).not_to include("OpenCollective Sponsors")
      expect(readme).not_to include("opencollective")
      expect(funding).not_to include("OpenCollective Backers")
      expect(funding).not_to include("OpenCollective Sponsors")
      expect(funding).not_to include("opencollective")
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
        ".opencollective.yml" => <<~YAML
          collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: {"OPENCOLLECTIVE_HANDLE" => "NO"})
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
        ".github/FUNDING.yml" => <<~YAML
          github: [example]
          open_collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: {"FUNDING_ORG" => "0"})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/example")
    end
  end

  it "uses explicit Open Collective config as the template token source" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-config-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          funding:
            open_collective: config-org
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("config-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("config.funding.open_collective")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/config-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "config-org")
    end
  end

  it "uses GitHub funding Open Collective config as the template token source" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-github-funding-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".github/FUNDING.yml" => <<~YAML,
          open_collective: "github-funding-org"
        YAML
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("github-funding-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq(".github/FUNDING.yml")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/github-funding-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include(
        "KJ|OPENCOLLECTIVE_ORG" => "github-funding-org"
      )
    end
  end

  it "defaults Open Collective template content to galtzo-floss when no org can be resolved" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-default-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            entries:
              - .opencollective.yml
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be_nil
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("galtzo-floss")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("fallback.default")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/galtzo-floss")
      expect(plan.dig(:facts, :templates, :tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "galtzo-floss")
      expect(plan.fetch(:warnings)).to be_empty
    end
  end

  it "warns when the default Open Collective org differs from the GitHub org" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-default-org-warning-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/example-org/example"
            spec.metadata["source_code_uri"] = "https://github.com/example-org/example"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("galtzo-floss")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("fallback.default")
      expect(plan.fetch(:warnings)).to contain_exactly(
        'OpenCollective funding org defaulted to "galtzo-floss", but the GitHub org is "example-org". Configure funding.open_collective or FUNDING_ORG if this is not intended.'
      )
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
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {"FUNDING_ORG" => "env-org"})
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
        ".opencollective.yml" => <<~YAML
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
        "template/README.md.example" => <<~MARKDOWN
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
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          funding:
            open_collective: collective-acme
          tokens:
            forge:
              gh_user: acme
              gl_user: acme
              cb_user: acme
              sh_user: acme
            funding:
              kofi: acme
              paypal: acme
              buymeacoffee: acme
              liberapay: acme
            social:
              mastodon: "@acme@example.social"
              bluesky: acme.example
              linktree: acme
              devto: acme
          templates:
            apply: true
            entries:
              - README.md
              - FUNDING.md
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
      expect(template_report.fetch(:final_content)).to include("https://github.com/acme/example")
      expect(template_report.fetch(:final_content)).to include("Sponsor collective-acme/example on Open Source Collective")
      expect(template_report.fetch(:final_content)).to include("https://opencollective.com/collective-acme")
      expect(template_report.fetch(:final_content)).not_to include("https://opencollective.com/acme")

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
      expect(File.read(File.join(root, "FUNDING.md"))).to include(
        "Sponsor collective-acme/example on Open Source Collective"
      )
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
        "template/README.md.example" => <<~MARKDOWN
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

  it "keeps Ruby 2.3 in the untested README support badge set" do
    template = File.read(File.join(__dir__, "..", "lib", "kettle", "jem", "templates", "README.md.example"))
    ruby_2_line = template.lines.find { |line| line.start_with?("| Works with MRI Ruby 2") }

    expect(ruby_2_line).to include("![Ruby 2.2 Compat][💎ruby-2.2i] ![Ruby 2.3 Compat][💎ruby-2.3i] <br/>")
    expect(ruby_2_line).not_to include("[![Ruby 2.3 Compat][💎ruby-2.3i]][🚎ruby-2.3-wf]")
    expect(template).to include("[💎ruby-2.3i]: https://img.shields.io/badge/Ruby-2.3_(%F0%9F%9A%ABCI)-AABBCC")
    expect(template).not_to include("[🚎ruby-2.3-wf]:")
    expect(template).not_to include("[🚎ruby-2.3-wfi]:")
  end

  it "keeps current runtime badges distinct from prior-current engine badges" do
    template = File.read(File.join(__dir__, "..", "lib", "kettle", "jem", "templates", "README.md.example"))
    ruby_4_line = template.lines.find { |line| line.start_with?("| Works with MRI Ruby 4") }
    jruby_line = template.lines.find { |line| line.start_with?("| Works with JRuby") }
    truffleruby_line = template.lines.find { |line| line.start_with?("| Works with Truffle Ruby") }

    expect(ruby_4_line).to include("[![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf]")
    expect(ruby_4_line).not_to include("Ruby 4.0 Compat")
    expect(jruby_line).to include("[![JRuby 10.0 Compat][💎jruby-10.0i]][🚎jruby-10.0-wf]")
    expect(jruby_line).to include("[![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf]")
    expect(truffleruby_line).to include("[![Truffle Ruby 33.0 Compat][💎truby-33.0i]][🚎truby-33.0-wf]")
    expect(truffleruby_line).to include("[![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf]")
    expect(truffleruby_line).to include("[![Truffle Ruby HEAD Compat][💎truby-headi]][🚎3-hd-wf]")
  end

  it "adds missing compatible versioned engine README badges when workflows exist" do
    readme = <<~MARKDOWN
      # Example

      | Works with JRuby | [![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf] [![JRuby HEAD Compat][💎jruby-headi]][🚎3-hd-wf]|
      | Works with Truffle Ruby | [![Truffle Ruby 24.2 Compat][💎truby-24.2i]][🚎truby-24.2-wf] [![Truffle Ruby 25.0 Compat][💎truby-25.0i]][🚎truby-25.0-wf] [![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf] [![Truffle Ruby HEAD Compat][💎truby-headi]][🚎3-hd-wf]|

      [🚎10-j-wf]: https://github.com/acme/example/actions/workflows/jruby.yml
      [🚎3-hd-wf]: https://github.com/acme/example/actions/workflows/heads.yml
      [🚎9-t-wf]: https://github.com/acme/example/actions/workflows/truffle.yml
      [🚎truby-24.2-wf]: https://github.com/acme/example/actions/workflows/truffleruby-24.2.yml
      [🚎truby-25.0-wf]: https://github.com/acme/example/actions/workflows/truffleruby-25.0.yml
      [💎jruby-c-i]: https://img.shields.io/badge/JRuby-current-FBE742
      [💎jruby-headi]: https://img.shields.io/badge/JRuby-HEAD-FBE742
      [💎truby-24.2i]: https://img.shields.io/badge/Truffle_Ruby-24.2-34BCB1
      [💎truby-25.0i]: https://img.shields.io/badge/Truffle_Ruby-25.0-34BCB1
      [💎truby-c-i]: https://img.shields.io/badge/Truffle_Ruby-current-34BCB1
      [💎truby-headi]: https://img.shields.io/badge/Truffle_Ruby-HEAD-34BCB1
    MARKDOWN

    processed = described_class::ReadmePostProcessor.process(
      content: readme,
      min_ruby: Gem::Version.new("3.2"),
      engines: %w[ruby jruby truffleruby],
      workflow_paths: %w[
        .github/workflows/jruby.yml
        .github/workflows/jruby-10.0.yml
        .github/workflows/truffle.yml
        .github/workflows/truffleruby-24.2.yml
        .github/workflows/truffleruby-25.0.yml
        .github/workflows/truffleruby-33.0.yml
        .github/workflows/heads.yml
      ]
    )

    expect(processed).to include("[![JRuby 10.0 Compat][💎jruby-10.0i]][🚎jruby-10.0-wf]")
    expect(processed).to include("[![Truffle Ruby 33.0 Compat][💎truby-33.0i]][🚎truby-33.0-wf]")
    expect(processed).to include("[🚎jruby-10.0-wf]: https://github.com/acme/example/actions/workflows/jruby-10.0.yml")
    expect(processed).to include("[🚎truby-33.0-wf]: https://github.com/acme/example/actions/workflows/truffleruby-33.0.yml")
    expect(processed).to include("[💎jruby-10.0i]: https://img.shields.io/badge/JRuby-10.0-FBE742")
    expect(processed).to include("[💎truby-33.0i]: https://img.shields.io/badge/Truffle_Ruby-33.0-34BCB1")
  end

  it "keeps same-minor Ruby compatibility badges for patch-level runtime floors" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-patch-floor-badge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.2.2"
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
        "template/README.md.example" => <<~MARKDOWN
          # Example

          | Works with MRI Ruby 1 | ![Ruby 1.8 Compat][💎ruby-1.8i] ![Ruby 1.9 Compat][💎ruby-1.9i] |
          | Works with MRI Ruby 2 | ![Ruby 2.1 Compat][💎ruby-2.1i] ![Ruby 2.2 Compat][💎ruby-2.2i] ![Ruby 2.3 Compat][💎ruby-2.3i] |

          [💎ruby-1.8i]: https://example/ruby-18
          [💎ruby-1.9i]: https://example/ruby-19
          [💎ruby-2.1i]: https://example/ruby-21
          [💎ruby-2.2i]: https://example/ruby-22
          [💎ruby-2.3i]: https://example/ruby-23
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = report.fetch(:final_content)
      ruby_2_line = final_content.lines.find { |line| line.start_with?("| Works with MRI Ruby 2") }

      expect(final_content).not_to include("Works with MRI Ruby 1")
      expect(ruby_2_line).not_to include("ruby-2.1i")
      expect(ruby_2_line).to include("ruby-2.2i")
      expect(ruby_2_line).to include("ruby-2.3i")
      expect(final_content).not_to match(/^\[💎ruby-2\.1i\]:/)
      expect(final_content).to match(/^\[💎ruby-2\.2i\]:/)
      expect(final_content).to match(/^\[💎ruby-2\.3i\]:/)
    end
  end

  it "keeps the Ruby 1.8 compatibility badge for a Ruby 1.8.7 runtime floor" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-ruby-18-badge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 1.8.7"
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
        "template/README.md.example" => <<~MARKDOWN
          # Example

          | Works with MRI Ruby 1 | ![Ruby 1.8 Compat][💎ruby-1.8i] ![Ruby 1.9 Compat][💎ruby-1.9i] |

          [💎ruby-1.8i]: https://example/ruby-18
          [💎ruby-1.9i]: https://example/ruby-19
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = report.fetch(:final_content)
      mri_line = final_content.lines.find { |line| line.start_with?("| Works with MRI Ruby 1") }

      expect(mri_line).to include("ruby-1.8i")
      expect(mri_line).to include("ruby-1.9i")
      expect(final_content).to match(/^\[💎ruby-1\.8i\]:/)
      expect(final_content).to match(/^\[💎ruby-1\.9i\]:/)
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
        "template/README.md.example" => "# Example\n"
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
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {"KJ_MIN_DIVERGENCE_THRESHOLD" => "7"})
      bootstrap_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      expect(bootstrap_report.fetch(:changed)).to be(true)
      expect(bootstrap_report.fetch(:relative_path)).to eq(".structuredmerge/kettle-jem.yml")
      expect(bootstrap_report.dig(:metadata, :bootstrap_file)).to be(true)
      expect(bootstrap_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: ".structuredmerge/kettle-jem.yml.example",
        source_relative_path: ".structuredmerge/kettle-jem.yml.example",
        source_root: "packaged"
      )
      expect(bootstrap_report.fetch(:final_content)).to include("# kettle-jem configuration file")
      expect(bootstrap_report.fetch(:final_content)).to include("min_divergence_threshold: 7")
      expect(bootstrap_report.fetch(:final_content)).to include("#   tokens    - values for {KJ|...} placeholders used across template files")

      described_class.apply_project(root, env: {"KJ_MIN_DIVERGENCE_THRESHOLD" => "7"})
      expect(File.read(File.join(root, ".structuredmerge/kettle-jem.yml"))).to eq(bootstrap_report.fetch(:final_content))
    end
  end

  it "removes explicit RuboCop TargetRubyVersion when templating rubocop-lts config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubocop-target-ruby-version-cleanup", tmp_root) do |root|
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
              - .rubocop.yml
        YAML
        ".rubocop.yml" => <<~YAML,
          inherit_gem:
            rubocop-lts: config/rubygem_rspec.yml
          AllCops:
            Exclude:
              - tmp/**/*
            TargetRubyVersion: 3.2
          Style/StringLiterals:
            EnforcedStyle: double_quotes
        YAML
        "template/.rubocop.yml.example" => <<~YAML
          inherit_gem:
            rubocop-lts: config/rubygem_rspec.yml
          AllCops:
            Exclude:
              - vendor/**/*
          RBS:
            Enabled: true
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".rubocop.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(report.fetch(:changed)).to be(true)
      expect(config.fetch("AllCops")).not_to have_key("TargetRubyVersion")
      expect(config.dig("AllCops", "Exclude")).to eq(["tmp/**/*"])
      expect(config.dig("Style/StringLiterals", "EnforcedStyle")).to eq("double_quotes")
      expect(config.dig("RBS", "Enabled")).to be(true)
      expect(report.fetch(:final_content)).not_to include("TargetRubyVersion")
      expect(File.read(File.join(root, ".rubocop.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "seeds bootstrap config licenses from the gemspec" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-licenses", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
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

  it "seeds bootstrap config minimum Ruby from the gemspec" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-min-ruby", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2.0"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)

      expect(content).to include(<<~YAML)
        ruby:
          # Lowest MRI Ruby version for generated CI workflows, Appraisals, and
          # test/development dependency assumptions. This is intentionally separate
          # from the gemspec required_ruby_version, which describes the published
          # runtime contract. Effective CI minimum is max(gemspec minimum, this value).
          test_minimum: "3.2.0"
      YAML
      expect(content).to include(<<~YAML)
        rubygems:
          # Published runtime Ruby floor used for generated gemspec metadata and README
          # compatibility text. Omit this to derive the value from the gemspec.
          min_ruby: "3.2.0"
      YAML
      expect(content).not_to include('min_ruby: "2.4"')
    end
  end

  it "seeds bootstrap config CI minimum Ruby no lower than 2.4" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-ci-min-ruby", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)

      expect(content).to include('test_minimum: "2.4"')
      expect(content).to include('min_ruby: "2.3"')
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
        "README.md" => "# 💎 Tree::Haver\n\nExisting README.\n"
      })

      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )
      config = File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".structuredmerge/kettle-jem.yml")
      expect(config).to include("project_emoji: 💎\n")
      expect(config_yaml.dig("templates", "root")).to eq("packaged")
      expect(config_yaml.dig("templates", "apply")).to be(true)
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-subgem-package")
      expect(config_yaml.dig("templates", "entries")).to include(
        "README.md",
        {"source" => "gem.gemspec", "target" => "tree_haver.gemspec"},
        "LICENSE.md"
      )
      expect(config).to include(
        "    - source: lib/gem/version.rb\n      " \
          "target: lib/tree_haver/version.rb\n    " \
          "- source: sig/gem/version.rbs\n      " \
          "target: sig/tree_haver/version.rbs\n"
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

  it "bootstraps a monorepo subgem release profile with per-gem harness entries" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-subgem-release", tmp_root) do |root|
      write_tree(root, {
        "tree_haver.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "tree_haver"
            spec.summary = "Example gem"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem-release", skip_commit: true}
      )
      config = File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".structuredmerge/kettle-jem.yml")
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-subgem-release")
      expect(config_yaml.dig("templates", "entries")).to include(
        "Gemfile",
        "Rakefile",
        ".rspec",
        ".simplecov",
        ".yardopts",
        ".yardignore",
        "bin/setup",
        "spec/spec_helper.rb",
        "gemfiles/modular/documentation.gemfile"
      )
      expect(config_yaml.dig("files", "tree_haver.gemspec", "strategy")).to eq("merge")

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})
      expect(apply.fetch(:changed_files)).to include("Gemfile", ".yardopts", ".yardignore", "bin/setup")
      expect(File).to exist(File.join(root, "Rakefile"))
      expect(File).to exist(File.join(root, "Gemfile"))
      expect(File).to exist(File.join(root, ".yardopts"))
      updated_config = YAML.safe_load_file(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      expect(updated_config.dig("templates", "profile")).to eq("monorepo-subgem-release")
      expect(updated_config.dig("templates", "entries")).to include("Rakefile", ".yardopts")
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
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.13"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
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
      expect(version_rb).not_to end_with("\n\n")
      version_rbs = File.read(File.join(root, "sig", "example", "gem", "version.rbs"))
      expect(version_rbs).to include("module Example")
      expect(version_rbs).to include("module Gem")
      expect(version_rbs).to include("VERSION: String")
      expect(version_rbs).not_to end_with("\n\n")
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "version_gem_bootstrap" }
      expect(post_step.fetch(:changed_files)).to eq(["lib/example/gem.rb"])
    end
  end

  it "replaces legacy version files with the packaged version_gem template" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-accept-template", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.13"
          end
        RUBY
        "lib/example/gem/version.rb" => <<~RUBY,
          module Example
            module Gem
              VERSION = "1.2.3"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
                target: lib/example/gem/version.rb
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/example/gem/version.rb")
      version_rb = File.read(File.join(root, "lib", "example", "gem", "version.rb"))
      expect(version_rb).to include("# frozen_string_literal: true")
      expect(version_rb).to include("module Version")
      expect(version_rb).to include('VERSION = "1.2.3"')
      expect(version_rb).to include("VERSION = Version::VERSION # Traditional Constant Location")
      expect(version_rb).not_to include("module Gem\n    VERSION")
      expect(version_rb).not_to end_with("\n\n")
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
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.13"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
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
      config = File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".structuredmerge/kettle-jem.yml")
      expect(config_yaml.dig("templates", "root")).to eq("packaged")
      expect(config_yaml.dig("templates", "apply")).to be(true)
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-root")
      expect(config_yaml.dig("templates", "entries")).to include(
        "CHANGELOG.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "FUNDING.md",
        "Gemfile",
        "IRP.md",
        "LICENSE.md",
        "AGPL-3.0-only.md",
        "PolyForm-Small-Business-1.0.0.md",
        "RUBOCOP.md",
        "Rakefile",
        "SECURITY.md",
        ".github/FUNDING.yml",
        ".structuredmerge/git-drivers.toml"
      )
      expect(config_yaml.dig("files", "CHANGELOG.md", "strategy")).to eq("keep_destination")
      expect(config_yaml.dig("files", "Gemfile", "strategy")).to eq("keep_destination")
      expect(config.lines.count { |line| line == "  .github:\n" }).to eq(1)
    end
  end

  it "templates a monorepo root without a gemspec and syncs root Gemfile tooling dependencies" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-root-apply", tmp_root) do |root|
      write_tree(root, {
        "AGPL-3.0-only.md" => "AGPL\n",
        "PolyForm-Small-Business-1.0.0.md" => "PolyForm\n",
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🍲"
          licenses:
            - MIT
          templates:
            root: packaged
            apply: true
            profile: monorepo-root
            entries:
              - Gemfile
              - Rakefile
              - LICENSE.md
              - AGPL-3.0-only.md
              - PolyForm-Small-Business-1.0.0.md
          files:
            Gemfile:
              strategy: keep_destination
            Rakefile:
              strategy: accept_template
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          # gem "kettle-dev"
          warn "kettle-test" if false
          gemspec path: "gems/kettle-jem"
          gem "rake"
        RUBY
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, template_profile: "monorepo-root", skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))
      rakefile = File.read(File.join(root, "Rakefile"))

      expect(report.fetch(:changed_files)).to include("Gemfile", "LICENSE.md")
      expect(report.fetch(:facts).dig(:license, :spdx)).to eq(["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"])
      expect(gemfile).to include('gemspec path: "gems/kettle-jem"')
      expect(gemfile).not_to include('gem "kettle-jem", "~> 7.0"')
      expect(gemfile).to include('gem "kettle-dev", "~> 2.2", ">= 2.2.18"')
      expect(gemfile).to include('gem "kettle-test", "~> 2.0", ">= 2.0.7"')
      expect(gemfile.lines.count { |line| line.start_with?('gem "kettle-dev"') }).to eq(1)
      expect(gemfile.lines.count { |line| line.start_with?('gem "kettle-test"') }).to eq(1)
      expect(gemfile).to include('gem "turbo_tests2", "~> 3.1", ">= 3.1.5"')
      expect(rakefile).to include('require "kettle/dev"')
      expect(rakefile).to include("Kettle::Dev.install_tasks")
      expect(rakefile).to include("namespace :family do")
      expect(rakefile).to include('run_kettle_family("check")')
    end
  end

  it "adds released root Gemfile tooling even when local nomono overrides are present" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-root-gemfile-released-tooling", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🍲"
          licenses:
            - MIT
          templates:
            root: packaged
            apply: true
            profile: monorepo-root
            entries:
              - Gemfile
          files:
            Gemfile:
              strategy: keep_destination
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          unless ENV.fetch("KETTLE_RB_DEV", "false").casecmp("false").zero?
            require "nomono/bundler"

            eval_nomono_gems(
              gems: %w[kettle-dev kettle-test],
              prefix: "KETTLE_RB",
              path_env: "KETTLE_RB_DEV",
              vendored_gems_env: "VENDORED_GEMS",
              vendor_gem_dir_env: "VENDOR_GEM_DIR",
              debug_env: "KETTLE_DEV_DEBUG",
            )
          end
        RUBY
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, template_profile: "monorepo-root", skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(report.fetch(:changed_files)).to include("Gemfile")
      expect(gemfile).to include('gem "kettle-dev", "~> 2.2", ">= 2.2.18"')
      expect(gemfile).to include('gem "kettle-test", "~> 2.0", ">= 2.0.7"')
      expect(gemfile).to include('gem "turbo_tests2", "~> 3.1", ">= 3.1.5"')
    end
  end

  it "guards preserved main Gemfile local workspace overrides during templating" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-templating-local-guard", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "Demo"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          gemspec

          unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
            require "nomono/bundler"

            eval_nomono_gems(
              gems: %w[auth-sanitizer oauth-tty snaky_hash version_gem],
              prefix: "RUBY_OAUTH",
              path_env: "RUBY_OAUTH_DEV",
              root: %w[code src ruby-oauth],
              debug_env: "RUBY_OAUTH_DEBUG"
            )
          end
        RUBY
      })

      report = described_class.apply_project(root, env: {}, run_options: {accept: true, force: true, skip_commit: true})
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(report.fetch(:changed_files)).to include("Gemfile")
      expect(gemfile).to include('eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?')
      expect(gemfile).to include(<<~RUBY.rstrip)
        unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
          unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
            require "nomono/bundler"

            eval_nomono_gems(
      RUBY
      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true, skip_commit: true})
      reapplied_gemfile = File.read(File.join(root, "Gemfile"))
      guard_line = %(unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?\n)
      expect(reapplied_gemfile.lines.count(guard_line)).to eq(1)
    end
  end

  it "collapses duplicate templating guards around main Gemfile local workspace overrides" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-templating-local-guard-collapse", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "Demo"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          gemspec

          unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
            unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
              unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
                require "nomono/bundler"

                eval_nomono_gems(
                  gems: %w[version_gem],
                  prefix: "RUBY_OAUTH",
                  path_env: "RUBY_OAUTH_DEV"
                )
              end
            end
          end
        RUBY
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true, skip_commit: true})
      gemfile = File.read(File.join(root, "Gemfile"))
      guard_line = %(unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?\n)
      expect(gemfile.lines.count(guard_line)).to eq(1)
      expect(gemfile).to include(<<~RUBY.rstrip)
        unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
          unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
            require "nomono/bundler"
      RUBY
    end
  end

  it "preserves monorepo root Rakefile tasks during scaffold cleanup" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-root-rakefile", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🍲"
          templates:
            root: packaged
            apply: true
            profile: monorepo-root
            entries: []
        YAML
        "Rakefile" => <<~RUBY
          require "rake/testtask"
          require "rspec/core/rake_task"

          RSpec::Core::RakeTask.new(:spec)

          task default: :spec
        RUBY
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, template_profile: "monorepo-root", skip_commit: true}
      )
      rakefile_report = report.fetch(:recipe_reports).find { |recipe| recipe.fetch(:recipe_name) == "rakefile_scaffold_cleanup" }

      expect(rakefile_report.dig(:request_envelope, :request, :runtime_context, :delete_selectors)).to be_empty
      expect(File.read(File.join(root, "Rakefile"))).to include("RSpec::Core::RakeTask.new(:spec)")
      expect(File.read(File.join(root, "Rakefile"))).to include("task default: :spec")
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
        "template/README.md.example" => <<~MARKDOWN
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
      checksums_url: "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums"
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
        "template/README.md.example" => <<~MARKDOWN
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

      expect(readme).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis\./)
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
        "ast-crispr.gemspec" => <<~RUBY
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

      expect(File.read(File.join(root, described_class::KETTLE_CONFIG_PATH))).to include("project_emoji: 💎\n")
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
        "README.md" => "# 💎 Json::Merge\n\nExisting README.\n"
      })

      described_class.setup_project(
        root,
        env: {"KJ_PROJECT_EMOJI" => "☯️"},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )

      expect(File.read(File.join(root, described_class::KETTLE_CONFIG_PATH))).to include("project_emoji: ☯️\n")
    end
  end

  it "seeds project emoji from gemspec summary when README has no leading H1" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-gemspec-emoji", tmp_root) do |root|
      write_tree(root, {
        "yaml-converter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "yaml-converter"
            spec.summary = "🥨 Convert annotated YAML blueprints into readable documentation."
            spec.licenses = ["MIT"]
          end
        RUBY
        "README.md" => <<~MARKDOWN
          | 📍 NOTE |
          |---------|
          | Existing preface. |

          # Yaml::Converter
        MARKDOWN
      })

      described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, skip_commit: true}
      )

      expect(File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))).to include("project_emoji: 🥨\n")
    end
  end

  it "applies bootstrap with non-interactive defaults and converges on the next run" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-bootstrap-contract", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      bootstrap_target = bootstrap_contract.fetch(:expected).fetch(:bootstrap_target)

      expect(apply.fetch(:decision_policy).fetch(:mode)).to eq(
        bootstrap_contract.fetch(:expected).fetch(:non_interactive_mode)
      )
      expect(apply.fetch(:changed_files)).to include(bootstrap_target)
      expect(File).to exist(File.join(root, bootstrap_target))

      described_class.apply_project(root, env: {}, run_options: {accept: true})
      selected = bootstrap_contract.fetch(:expected).fetch(:idempotent_selected_paths).to_h do |relative_path|
        [relative_path, File.exist?(File.join(root, relative_path)) ? File.read(File.join(root, relative_path)) : nil]
      end
      third_apply = described_class.apply_project(root, env: {}, run_options: {accept: true})

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
          "example.gemspec" => <<~RUBY
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
          described_class.plan_project(root, env: {}, run_options: {accept: true})
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
      "entries_scalar" => ["templates:\n  entries: README.md\n", /templates\.entries must be a list/]
    }.each do |case_name, (config, message)|
      Dir.mktmpdir("kettle-jem-config-validation-#{case_name}", tmp_root) do |root|
        write_tree(root, {
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
            end
          RUBY
          ".kettle-jem.yml" => config
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
        "README.md" => "# destination\n"
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
        "template/config/settings.yml.example" => <<~YAML
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
        max_recursion_depth: "7"
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
        ".kettle-jem.yml" => <<~YAML
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
        ".github/COPILOT_INSTRUCTIONS.md" => "legacy copilot instructions\n"
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
    curated_binstubs = %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover stone_checksums]
    Dir.mktmpdir("kettle-jem-install-post-template-slice", tmp_root) do |root|
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
          "  entries:",
          "    - bin/setup",
          ""
        ].join("\n"),
        "Rakefile" => "task :default\n",
        "bin/rake" => "#!/usr/bin/env ruby\n"
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
        command: curated_binstubs,
        status: "succeeded",
        exitstatus: 0
      )
      expect(install.fetch(:install_steps)).to include(
        name: "rubocop_gradual_autocorrect",
        command: ["sh", "-c", "rm -f .rubocop_gradual.lock && bin/rake rubocop_gradual:autocorrect"],
        status: "succeeded",
        exitstatus: 0,
        reason: "executed"
      )
      expect(install.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        command: kettle_jem_handoff_command("--skip-commit", "--quiet", "--only", "bin/setup"),
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
        steps: include("bin_setup_executable", "bin_setup", "bundle_binstubs", "rubocop_gradual_autocorrect"),
        statuses: hash_including(
          "bin_setup_executable" => "updated",
          "bin_setup" => "succeeded",
          "bundle_binstubs" => "succeeded",
          "rubocop_gradual_autocorrect" => "succeeded",
          "bundle_binstub_pruning" => "already_current"
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
      autocorrect_command = ["sh", "-c", "rm -f .rubocop_gradual.lock && bin/rake rubocop_gradual:autocorrect"]
      handoff_command = kettle_jem_handoff_command("--skip-commit", "--quiet", "--only", "bin/setup")
      command_names = commands.map { |entry| entry.fetch(:command) }
      expect(command_names).to include(
        ["bin/setup", "--quiet"],
        curated_binstubs,
        autocorrect_command,
        handoff_command
      )
      expect(command_names.index(autocorrect_command)).to be < command_names.index(handoff_command)
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
      expect(second.fetch(:changed_files)).to be_empty
      expect(second.fetch(:install_steps)).to include(
        name: "bin_setup_executable",
        path: "bin/setup",
        status: "already_executable"
      )
      expect(second.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        command: kettle_jem_handoff_command("--quiet", "--only", "bin/setup"),
        status: "succeeded",
        exitstatus: 0,
        reason: "executed"
      )
      second_commit_step = second.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }
      expect(second_commit_step.fetch(:status)).to eq("unavailable")
      expect(second_commit_step.fetch(:reason)).to eq("not_git_repository")
      expect(commands.map { |entry| entry.fetch(:command) }).to include(
        ["bin/setup", "--quiet"],
        curated_binstubs,
        kettle_jem_handoff_command("--quiet", "--only", "bin/setup")
      )

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
          ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"]
        ],
        command_results: [
          {command: %w[git add -A], exitstatus: 0},
          {command: ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"], exitstatus: 0}
        ],
        reason: "executed"
      ))
      expect(git_ready.fetch(:install_steps).find { |step| step.fetch(:name) == "bootstrap_commit" }.fetch(:dirty_entries)).not_to be_empty

      Dir.mktmpdir("kettle-jem-clean-bootstrap", tmp_root) do |clean_root|
        expect(system("git", "init", clean_root, out: File::NULL, err: File::NULL)).to be(true)
        stale_commit_step = Kettle::Jem::Tasks::InstallTask.send(
          :execute_ready_commands_step,
          {
            name: "bootstrap_commit",
            status: "ready",
            dirty_entries: [" M bin/setup"],
            commands: [%w[git add -A], ["git", "commit", "-m", "stale"]]
          },
          project_root: clean_root,
          env: {},
          quiet: false,
          command_runner: command_runner
        )
        expect(stale_commit_step.fetch(:status)).to eq("clean_noop")
        expect(stale_commit_step.fetch(:reason)).to eq("clean_before_execution")
      end

      Dir.mktmpdir("kettle-jem-install-monorepo", tmp_root) do |repo_root|
        expect(system("git", "init", repo_root, out: File::NULL, err: File::NULL)).to be(true)
        gem_root = File.join(repo_root, "gems", "example")
        write_tree(gem_root, {
          "Gemfile" => <<~RUBY,
            source "https://gem.coop"
            gemspec
          RUBY
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
            end
          RUBY
          ".kettle-jem.yml" => <<~YAML
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
        bundler_binstub = lambda do |gem_name, executable|
          <<~RUBY
            #!/usr/bin/env ruby
            # frozen_string_literal: true

            #
            # This file was generated by Bundler.
            #
            load Gem.bin_path("#{gem_name}", "#{executable}")
          RUBY
        end
        binstub_runner = lambda do |command, chdir:, env:, quiet:|
          commands << {command: command, chdir: chdir, env: env, quiet: quiet}
          if command == curated_binstubs
            FileUtils.mkdir_p(File.join(chdir, "bin"))
            File.write(File.join(chdir, "bin", "appraisal"), bundler_binstub.call("appraisal2", "appraisal"))
            File.write(File.join(chdir, "bin", "kettle-bump"), bundler_binstub.call("kettle-dev", "kettle-bump"))
            File.write(File.join(chdir, "bin", "rake"), bundler_binstub.call("rake", "rake"))
            File.write(File.join(chdir, "bin", "yard"), bundler_binstub.call("yard", "yard"))
            File.write(File.join(chdir, "bin", "reek"), bundler_binstub.call("reek", "reek"))
            FileUtils.chmod("+x", File.join(chdir, "bin", "appraisal"))
            FileUtils.chmod("+x", File.join(chdir, "bin", "reek"))
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
          destination_binstubs: include("appraisal", "rake")
        ))
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "yard_binstub_rake_handoff",
          status: "updated",
          reason: "yard_plugins_require_rake_yard_postprocess_hooks",
          path: "bin/yard"
        ))
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "curated_binstubs_executable",
          status: "updated",
          path: "bin",
          updated_binstubs: %w[kettle-bump rake yard]
        ))
        expect(validated_install.fetch(:install_steps)).to include(hash_including(
          name: "bundle_binstub_pruning",
          status: "pruned",
          reason: "removed_unwanted_bundler_binstubs",
          removed_binstubs: ["reek"]
        ))
        expect(File.read(File.join(gem_root, "bin", "yard"))).to include('exec("bundle", "exec", "rake", "yard")')
        expect(File).to exist(File.join(gem_root, "bin", "appraisal"))
        expect(File).to exist(File.join(gem_root, "bin", "kettle-bump"))
        expect(File.executable?(File.join(gem_root, "bin", "kettle-bump"))).to be(true)
        expect(File.executable?(File.join(gem_root, "bin", "yard"))).to be(true)
        expect(File).not_to exist(File.join(gem_root, "bin", "reek"))
        expect(commands.find { |entry| entry.fetch(:command) == curated_binstubs }).to include(
          chdir: gem_root,
          env: include("BUNDLE_GEMFILE" => File.join(gem_root, "Gemfile"))
        )
      end
    end
  end

  it "applies full templates after accepting a newly bootstrapped config before bundled handoff" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    curated_binstubs = %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover stone_checksums]
    Dir.mktmpdir("kettle-jem-install-bootstrap-followup", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"
          gemspec
        RUBY
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "💎 Example gem"
            spec.authors = ["Peter H. Boling"]
            spec.email = ["floss@galtzo.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {accept_config: true, force: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:bootstrap_followup_apply)).to eq(
        status: "applied",
        reason: "canonical_config_bootstrapped"
      )
      expect(install.fetch(:changed_files)).to include(
        ".structuredmerge/kettle-jem.yml",
        "Gemfile",
        "gemfiles/modular/templating.gemfile",
        "gemfiles/modular/templating_local.gemfile"
      )
      expect(File.read(File.join(root, "Gemfile"))).to include(
        'eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?'
      )
      expect(File.read(File.join(root, "gemfiles", "modular", "templating.gemfile"))).to include('gem "kettle-jem", ">= 7.0"')
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundled_handoff",
        command: kettle_jem_handoff_command("--accept-config", "--skip-commit", "--force"),
        status: "succeeded"
      ))
      expect(commands.map { |entry| entry.fetch(:command) }).to include(
        ["bin/setup"],
        curated_binstubs,
        kettle_jem_handoff_command("--accept-config", "--skip-commit", "--force")
      )
    end
  end

  it "generates only curated documented binstubs" do
    expect(Kettle::Jem::Tasks::InstallTask.bundle_binstubs_command).to eq(
      %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover stone_checksums]
    )
  end

  it "omits curated binstubs for gems missing from the destination bundle" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([
      "appraisal2\nrake\nrbs\nrspec-core\nkettle-dev\nkettle-test\nkettle-soup-cover\nstone_checksums\n",
      "",
      status
    ])

    expect(Kettle::Jem::Tasks::InstallTask.bundle_binstubs_command("/example", env: {})).to eq(
      %w[bundle binstubs appraisal2 rake rbs rspec-core kettle-dev kettle-test kettle-soup-cover stone_checksums]
    )
  end

  it "skips bundled handoff when kettle-jem is absent from the destination bundle" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return([
      "rake\nrspec-core\n",
      "",
      status
    ])

    expect(Kettle::Jem::Tasks::InstallTask.bundled_handoff_step(project_root: "/example", env: {}, run_options: {})).to eq(
      name: "bundled_handoff",
      status: "skipped",
      reason: "kettle_jem_not_in_bundle"
    )
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
        ".kettle-jem.yml" => <<~YAML
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

  it "runs setup commands without inherited Bundler activation" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-env-bundler-strip", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      inherited_env = {
        "BUNDLE_GEMFILE" => "/workspace/kettle-jem/Gemfile",
        "BUNDLE_BIN_PATH" => "/workspace/kettle-jem/bin/bundle",
        "BUNDLE_LOCKFILE" => "/workspace/kettle-jem/Gemfile.lock",
        "BUNDLER_SETUP" => "/workspace/kettle-jem/bundler/setup",
        "BUNDLER_VERSION" => "4.0.12",
        "RUBYLIB" => "/workspace/kettle-jem/lib",
        "RUBYOPT" => "-rbundler/setup"
      }
      command_envs = []
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(quiet).to be(true)
        command_envs << env
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: inherited_env,
        run_options: {only: "bin/setup", quiet: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(command_envs).not_to be_empty
      expect(command_envs).to all(include("BUNDLE_GEMFILE" => File.join(root, "Gemfile")))
      expect(command_envs).to all(include(
        "BUNDLE_BIN_PATH" => nil,
        "BUNDLE_LOCKFILE" => nil,
        "BUNDLER_SETUP" => nil,
        "BUNDLER_VERSION" => nil,
        "RUBYLIB" => nil,
        "RUBYOPT" => nil
      ))
    end
  end

  it "uses kettle-family local install roots for templating setup" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-family-marker", tmp_root) do |root|
      marker_path = File.join(root, "local-install.json")
      marker = {
        "members_root" => File.join(root, "structuredmerge", "ruby", "gems"),
        "local_dependencies" => [
          File.join(root, "kettle-dev", "nomono"),
          File.join(root, "kettle-dev", "kettle-dev")
        ],
        "installed_members" => ["nomono", "kettle-dev", "kettle-jem"]
      }
      FileUtils.mkdir_p(File.join(marker.fetch("members_root"), "kettle-jem"))
      File.write(marker_path, JSON.pretty_generate(marker))
      File.write(File.join(root, "Gemfile"), "source \"https://gem.coop\"\n")

      env = {
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_FAMILY_LOCAL_INSTALL_MARKER" => marker_path
      }

      expect(Kettle::Jem::Tasks::InstallTask.setup_command_env(root, env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "true",
        "SMORG_RB_DEV" => marker.fetch("members_root"),
        "KETTLE_RB_DEV" => File.join(root, "kettle-dev")
      )
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
        ".kettle-jem.yml" => <<~YAML
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
        "KETTLE_RB_DEV" => "/workspace/my",
        "GALTZO_FLOSS_DEV" => "/workspace/galtzo-floss",
        "SMORG_RB_DEV" => "/workspace/smorg-rb"
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
        command: %w[bundle update],
        status: "succeeded",
        reason: "executed"
      ))
      lock_command = commands.find { |entry| entry.fetch(:command) == %w[bundle update] }
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

  it "can skip install lockfile normalization from ENV" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-skip-lock-normalization", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => "GEM\n  remote: https://gem.coop/\n  specs:\n",
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"KETTLE_JEM_SKIP_LOCK_NORMALIZATION" => "true"},
        run_options: {only: "example.gemspec", skip_commit: true},
        command_runner: lambda { |_command, chdir:, env:, quiet:| {success: true, exitstatus: 0, stdout: "", stderr: ""} }
      )

      expect(install.fetch(:install_steps)).to include(
        name: "bundle_lock_normalization",
        status: "skipped",
        reason: "skip_lock_normalization"
      )
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
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries: []
        YAML
      })

      env = {
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_RB_DEV" => "/workspace/my",
        "GALTZO_FLOSS_DEV" => "/workspace/galtzo-floss",
        "SMORG_RB_DEV" => "/workspace/smorg-rb",
        "RUBYOPT" => "-rbundler/setup",
        "RUBYLIB" => "/workspace/kettle-jem/lib",
        "BUNDLE_BIN_PATH" => "/workspace/kettle-jem/bin/bundle",
        "BUNDLE_LOCKFILE" => "/workspace/kettle-jem/Gemfile.lock",
        "BUNDLER_SETUP" => "/workspace/kettle-jem/bundler/setup",
        "BUNDLER_VERSION" => "4.0.12"
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
        command: %w[bundle update],
        status: "succeeded",
        reason: "executed"
      ))
      lock_command = commands.find { |entry| entry.fetch(:command) == %w[bundle update] }
      expect(lock_command).not_to be_nil
      expect(lock_command.fetch(:env)).to include(
        "BUNDLE_GEMFILE" => File.join(root, "Gemfile"),
        "K_JEM_TEMPLATING" => "false",
        "KETTLE_RB_DEV" => "false",
        "GALTZO_FLOSS_DEV" => "false",
        "SMORG_RB_DEV" => "false"
      )
      expect(lock_command.fetch(:env)).to include(
        "RUBYOPT" => nil,
        "RUBYLIB" => nil,
        "BUNDLE_BIN_PATH" => nil,
        "BUNDLE_LOCKFILE" => nil,
        "BUNDLER_SETUP" => nil,
        "BUNDLER_VERSION" => nil
      )
    end
  end

  it "activates local git hooks when requested by the template task" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-hook-activation", tmp_root) do |root|
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            ruby

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries: []
        YAML
        ".git-hooks/commit-msg" => "#!/bin/sh\n",
        ".git-hooks/prepare-commit-msg" => "#!/bin/sh\n"
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      report = Kettle::Jem::Tasks::TemplateTask.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {hook_templates: "l", quiet: true},
        command_runner: command_runner
      )

      expect(report.fetch(:template_steps)).to include(hash_including(
        name: "hook_templates",
        command: %w[git config core.hooksPath .git-hooks],
        status: "succeeded",
        reason: "executed"
      ))
      expect(commands.map { |entry| entry.fetch(:command) }).to include(%w[git config core.hooksPath .git-hooks])
      expect(File.stat(File.join(root, ".git-hooks", "commit-msg")).mode & 0o111).not_to eq(0)
      expect(File.stat(File.join(root, ".git-hooks", "prepare-commit-msg")).mode & 0o111).not_to eq(0)
    end
  end

  it "plans local semantic Git driver setup by default" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "local",
      profile: "semantic-diff",
      scope: "local",
      reason: "ready_for_local_git_drivers"
    )
    expect(step.fetch(:attribute_updates)).to include(hash_including(
      pattern: "*.rb",
      attributes: {"diff" => "smorg-ruby"}
    ))
    expect(step.fetch(:commands)).to include(
      ["git", "config", "--local", "diff.smorg-ruby.command", "smorg-ruby diff-driver"],
      ["git", "config", "--local", "merge.smorg-ruby.driver", "smorg-ruby merge-driver %O %A %B %P"]
    )
  end

  it "plans builtin Git diff attributes when requested" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "builtin-diff"})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "builtin-diff",
      profile: "builtin-diff",
      scope: "local"
    )
    expect(step.fetch(:attribute_updates)).to include(hash_including(
      pattern: "*.rb",
      attributes: {"diff" => "ruby"}
    ))
  end

  it "normalizes Git driver mode aliases" do
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode(nil)).to eq("local")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("off")).to eq("none")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("yes")).to eq("local")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("g")).to eq("global")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("include")).to eq("include-file")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("b")).to eq("builtin-diff")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("check")).to eq("check")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("undo")).to eq("undo")
    expect(Kettle::Jem::Tasks::InstallTask.normalize_git_drivers_mode("custom")).to eq("custom")
  end

  it "writes managed .gitattributes and local config for local semantic Git driver setup" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-drivers", tmp_root) do |root|
      write_tree(root, {".gitattributes" => "*.md diff=markdown\n"})
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: root,
        env: {},
        run_options: {},
        command_runner: command_runner
      ).first

      expect(result).to include(status: "succeeded", changed_files: [".gitattributes"])
      expect(File.read(File.join(root, ".gitattributes"))).to eq(<<~ATTRIBUTES)
        *.md diff=markdown
        # <<structuredmerge:git-drivers>> do not edit below this line
        *.rb diff=smorg-ruby
        *.go diff=smorg-go
        *.rs diff=smorg-rs
        # <</structuredmerge:git-drivers>>
      ATTRIBUTES
      expect(commands).to include(
        ["git", "config", "--local", "diff.smorg-ruby.command", "smorg-ruby diff-driver"],
        ["git", "config", "--local", "merge.smorg-ruby.driver", "smorg-ruby merge-driver %O %A %B %P"]
      )
    end
  end

  it "reports conflicting unmanaged .gitattributes entries" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-conflict", tmp_root) do |root|
      write_tree(root, {".gitattributes" => "*.rb diff=ruby\n"})

      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})

      expect(step).to include(
        status: "blocked",
        reason: "git_driver_attribute_conflict"
      )
      expect(step.fetch(:diagnostics)).to include(hash_including(
        key: "conflicting_attributes",
        path: ".gitattributes",
        pattern: "*.rb",
        blocking: true
      ))
    end
  end

  it "plans local Git driver setup without writing attributes in dry-run mode" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-dry-run", tmp_root) do |root|
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {dry_run: true})

      expect(step).to include(
        status: "planned",
        reason: "dry_run_git_driver_attributes"
      )
    end
  end

  it "plans global Git driver command registration when requested" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "global"})

    expect(step).to include(
      name: "git_drivers",
      status: "ready",
      mode: "global",
      profile: "semantic-diff",
      scope: "global",
      reason: "ready_for_global_git_drivers"
    )
    expect(step.fetch(:commands)).to include(
      ["git", "config", "--global", "diff.smorg-ruby.command", "smorg-ruby diff-driver"],
      ["git", "config", "--global", "merge.smorg-ruby.driver", "smorg-ruby merge-driver %O %A %B %P"]
    )
    expect(step.fetch(:diagnostics)).to include(hash_including(key: "forge_ignores_external_diff_drivers"))
  end

  it "writes include-file Git driver configuration when requested" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-include", tmp_root) do |root|
      step = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {git_drivers: "include-file"})
      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      result = Kettle::Jem::Tasks::InstallTask.execute_orchestration_steps(
        [step],
        project_root: root,
        env: {},
        run_options: {},
        command_runner: command_runner
      ).first

      expect(result).to include(status: "succeeded", changed_files: [".git/smorg/config"])
      expect(commands).to include(["git", "config", "--local", "include.path", ".git/smorg/config"])
      expect(File.read(File.join(root, ".git", "smorg", "config"))).to include("[diff \"smorg-ruby\"]")
    end
  end

  it "loads project Git driver manifests for attribute and command planning" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-manifest", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1
          driver_namespace = "smorg"

          [profiles.semantic-diff]
          description = "Custom Ruby driver"

          [[profiles.semantic-diff.attributes]]
          pattern = "*.rake"
          diff = "smorg-ruby"

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-ruby.command"
          value = "bundle exec smorg-ruby diff-driver"
        TOML
      })

      local = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      global = Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {git_drivers: "global"})

      expect(local.fetch(:attribute_updates)).to eq([
        {path: ".gitattributes", pattern: "*.rake", attributes: {"diff" => "smorg-ruby"}}
      ])
      expect(global.fetch(:commands)).to eq([
        ["git", "config", "--global", "diff.smorg-ruby.command", "bundle exec smorg-ruby diff-driver"]
      ])
    end
  end

  it "rejects unsafe interpolation in committed Git driver manifests" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-unsafe-manifest", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.semantic-diff]

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-ruby.command"
          value = "smorg-ruby $(danger)"
        TOML
      })

      expect do
        Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      end.to raise_error(Kettle::Jem::Error, /unsafe command interpolation/)
    end
  end

  it "rejects cachetextconv outside explicit textconv profiles" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-cachetextconv", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.semantic-diff]

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-ruby.cachetextconv"
          value = "true"
        TOML
      })

      expect do
        Kettle::Jem::Tasks::InstallTask.git_drivers_step(root, {})
      end.to raise_error(Kettle::Jem::Error, /cachetextconv requires an explicit textconv profile/)
    end
  end

  it "keeps semantic diff commands separate from textconv projections" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-textconv-separation", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.semantic-diff]

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-ruby.command"
          value = "smorg-ruby diff-driver"

          [profiles.textconv-normalized]

          [[profiles.textconv-normalized.git_config]]
          scope = "global"
          key = "diff.smorg-json-textconv.textconv"
          value = "smorg-rb textconv --format json"

          [[profiles.textconv-normalized.git_config]]
          scope = "global"
          key = "diff.smorg-json-textconv.cachetextconv"
          value = "true"
        TOML
      })

      manifest = Kettle::Jem::Tasks::InstallTask.git_driver_manifest(root)
      semantic_commands = Kettle::Jem::Tasks::InstallTask.git_driver_global_commands(manifest, "semantic-diff")
      semantic_local_commands = Kettle::Jem::Tasks::InstallTask.git_driver_local_commands(manifest, "semantic-diff")
      textconv_commands = Kettle::Jem::Tasks::InstallTask.git_driver_global_commands(manifest, "textconv-normalized")

      expect(semantic_commands).to eq([
        ["git", "config", "--global", "diff.smorg-ruby.command", "smorg-ruby diff-driver"]
      ])
      expect(semantic_local_commands).to eq([
        ["git", "config", "--local", "diff.smorg-ruby.command", "smorg-ruby diff-driver"]
      ])
      expect(textconv_commands).to contain_exactly(
        ["git", "config", "--global", "diff.smorg-json-textconv.textconv", "smorg-rb textconv --format json"],
        ["git", "config", "--global", "diff.smorg-json-textconv.cachetextconv", "true"]
      )
    end
  end

  it "keeps textconv projections display-only and out of merge inputs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-textconv-display-only", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/git-drivers.toml" => <<~TOML
          version = 1

          [profiles.textconv-normalized]

          [[profiles.textconv-normalized.attributes]]
          pattern = "*.json"
          diff = "smorg-json-textconv"

          [[profiles.textconv-normalized.git_config]]
          scope = "global"
          key = "diff.smorg-json-textconv.textconv"
          value = "smorg-rb textconv --format json"
        TOML
      })

      manifest = Kettle::Jem::Tasks::InstallTask.git_driver_manifest(root)
      attributes = Kettle::Jem::Tasks::InstallTask.git_driver_attribute_updates(manifest, "textconv-normalized")
      commands = Kettle::Jem::Tasks::InstallTask.git_driver_global_commands(manifest, "textconv-normalized")

      expect(attributes).to eq([
        {path: ".gitattributes", pattern: "*.json", attributes: {"diff" => "smorg-json-textconv"}}
      ])
      expect(attributes.flat_map { |update| update.fetch(:attributes).keys }).not_to include("merge")
      expect(commands.map { |command| command[3] }).to contain_exactly("diff.smorg-json-textconv.textconv")
      expect(commands.map { |command| command[3] }).not_to include(a_string_matching(/\Amerge\./))
    end
  end

  it "skips Git driver setup when explicitly disabled" do
    step = Kettle::Jem::Tasks::InstallTask.git_drivers_step("/example", {git_drivers: "none"})

    expect(step).to include(
      name: "git_drivers",
      status: "skipped",
      reason: "not_requested",
      mode: "none"
    )
  end

  it "loads canonical structuredmerge kettle-jem config before legacy root config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-discovery", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => "templates:\n  root: legacy\n",
        ".structuredmerge/kettle-jem.yml" => "templates:\n  root: canonical\n"
      })

      expect(described_class.kettle_jem_config(root).fetch("templates").fetch("root")).to eq("canonical")
    end
  end

  it "migrates legacy kettle-jem config to the structuredmerge directory" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-migration", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => "templates:\n  root: packaged\n"
      })

      step = Kettle::Jem::Tasks::InstallTask.kettle_config_migration_step(root)

      expect(step).to include(
        name: "kettle_config_migration",
        status: "migrated",
        reason: "legacy_kettle_config_migrated",
        canonical_path: ".structuredmerge/kettle-jem.yml",
        legacy_path: ".kettle-jem.yml"
      )
      expect(File).not_to exist(File.join(root, ".kettle-jem.yml"))
      expect(File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))).to eq("templates:\n  root: packaged\n")
    end
  end

  it "reports a conflict when canonical and legacy kettle-jem configs both exist" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-migration-conflict", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => "templates:\n  root: legacy\n",
        ".structuredmerge/kettle-jem.yml" => "templates:\n  root: canonical\n"
      })

      step = Kettle::Jem::Tasks::InstallTask.kettle_config_migration_step(root)

      expect(step).to include(
        name: "kettle_config_migration",
        status: "blocked",
        reason: "legacy_kettle_config_conflict"
      )
      expect(step.fetch(:diagnostics)).to include(hash_including(
        key: "legacy_kettle_config_conflict",
        path: ".kettle-jem.yml",
        canonical_path: ".structuredmerge/kettle-jem.yml"
      ))
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
        "template/example.gemspec.example" => <<~RUBY
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

  it "drops retired kettle-drift gemspec development dependencies during gemspec sync" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-retired-gemspec-dev-dependency", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.add_development_dependency "kettle-drift"
            spec.add_development_dependency "rake", "~> 13.0"
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
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "template"
            spec.summary = "Template gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {}, run_options: {only: "example.gemspec"})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "example.gemspec"
      end
      content = report.fetch(:final_content)

      expect(content).not_to include("kettle-drift")
      expect(content).to include('spec.add_development_dependency "rake", "~> 13.0"')
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
        ".gitignore" => "tmp/\n"
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
      expect(gemspec.scan('spec.homepage = "https://github.com/example-org/example"').size).to eq(1)
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
        ".env.local.example" => <<~ENV
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
        ".devcontainer/devcontainer.json" => <<~JSON
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
        ".vscode/settings.jsonc" => <<~JSONC
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
        "sig/example/version.rbs" => <<~RBS
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
        "scripts/setup" => <<~BASH
          #!/usr/bin/env bash
          bundle check || bundle install
        BASH
      })
      availability = Bash::Merge::Availability.new(
        grammar_path: nil,
        language_pack_process: true,
        node_parser: false,
        diagnostics: [{kind: "bash_node_parser_unavailable", message: "missing node adapter"}]
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
        "template/mise.toml.example" => <<~TOML
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

  it "preserves coverage thresholds from an existing coverage workflow in generated mise.toml" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-mise-coverage-thresholds", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".github/workflows/coverage.yml" => <<~YAML,
          env:
            K_SOUP_COV_MIN_BRANCH: 64
            K_SOUP_COV_MIN_LINE: 90
        YAML
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - mise.toml
        YAML
        "template/mise.toml.example" => <<~TOML
          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "92"

          [tools]
          ruby = "4.0.5"
        TOML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {only: "mise.toml", skip_commit: true})
      mise = File.read(File.join(root, "mise.toml"))

      expect(apply.fetch(:changed_files)).to include("mise.toml")
      expect(mise).to include('K_SOUP_COV_MIN_BRANCH = "64"')
      expect(mise).to include('K_SOUP_COV_MIN_LINE = "90"')
    end
  end

  it "preserves coverage thresholds from mise.toml in generated coverage workflow" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-coverage-thresholds", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        "mise.toml" => <<~TOML,
          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "100"
        TOML
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: .github/workflows/coverage.yml
                target: .github/workflows/coverage.yml
        YAML
        "template/.github/workflows/coverage.yml" => <<~YAML
          name: Test Coverage

          env:
            K_SOUP_COV_MIN_BRANCH: 100
            K_SOUP_COV_MIN_LINE: 100
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {only: ".github/workflows/coverage.yml", skip_commit: true})
      workflow = File.read(File.join(root, ".github", "workflows", "coverage.yml"))

      expect(apply.fetch(:changed_files)).to include(".github/workflows/coverage.yml")
      expect(workflow).to include("K_SOUP_COV_MIN_BRANCH: 76")
      expect(workflow).to include("K_SOUP_COV_MIN_LINE: 100")
    end
  end

  it "generates QLTY coverage uploads with OIDC in the packaged coverage workflow" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-coverage-qlty-oidc", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            apply: true
            entries:
              - source: .github/workflows/coverage.yml
                target: .github/workflows/coverage.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {only: ".github/workflows/coverage.yml", skip_commit: true})
      workflow = File.read(File.join(root, ".github", "workflows", "coverage.yml"))

      expect(apply.fetch(:changed_files)).to include(".github/workflows/coverage.yml")
      expect_pinned_action(workflow, "qltysh/qlty-action/coverage")
      expect(workflow).to include("oidc: true")
      expect(workflow).not_to include("QLTY_COVERAGE_TOKEN")
      expect(workflow).not_to include("KJ|GITHUB_ACTIONS:COVERAGE_UPLOAD_STEPS")
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
        "template/example-gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.13"
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
      expect(commands).to include(
        %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover stone_checksums],
        kettle_jem_handoff_command("--skip-commit", "--only", "example-gem.gemspec")
      )
    end
  end

  it "uses configured version_gem namespace before stale entrypoint inference" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-version-gem-configured-namespace", tmp_root) do |root|
      write_tree(root, {
        "lib/oauth2/mcp.rb" => <<~RUBY,
          # frozen_string_literal: true

          module OAuth2
            module MCP
            end
          end

          Oauth2::Mcp::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/oauth2/mcp/version.rb" => <<~RUBY
          # frozen_string_literal: true

          module OAuth2
            module MCP
              VERSION = "0.1.0"
            end
          end
        RUBY
      })
      facts = {
        package: {name: "oauth2-mcp"},
        rubygems: {entrypoint_require: "oauth2/mcp", namespace: "OAuth2::MCP"},
        project_runtime: {version: "0.1.0"}
      }

      step = described_class.send(:version_gem_bootstrap_step, root, facts)
      version_file = File.read(File.join(root, "lib", "oauth2", "mcp", "version.rb"))
      signature = File.read(File.join(root, "sig", "oauth2", "mcp", "version.rbs"))

      expect(step.fetch(:status)).to eq("applied")
      expect(version_file).to include("module OAuth2")
      expect(version_file).to include("module MCP")
      expect(version_file).not_to include("module Oauth2")
      expect(signature).to include("module OAuth2")
      expect(signature).to include("module MCP")
      expect(signature).not_to include("module Oauth2")
    end
  end

  it "discovers public entrypoint version namespace before stale gemspec metadata" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-version-gem-public-entrypoint-namespace", tmp_root) do |root|
      write_tree(root, {
        "oauth2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "oauth2"
            spec.version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/oauth2/version.rb", mod) }::Oauth2::Version::VERSION
            spec.summary = "OAuth2"
            spec.required_ruby_version = ">= 2.2.0"
          end
        RUBY
        "lib/oauth2.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "oauth2/version"

          module OAuth2
          end

          OAuth2::Version.class_eval do
            extend VersionGem::Basic
          end

          Oauth2::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/oauth2/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module OAuth2
            module Version
              VERSION = "2.0.20"
            end
            VERSION = Version::VERSION
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "🔐"
          rubygems:
            min_ruby: "2.2.0"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})

      expect(facts.dig(:rubygems, :namespace)).to eq("OAuth2")
      expect(facts.dig(:rubygems, :namespace)).not_to eq("Oauth2")
    end
  end

  it "discovers nested public entrypoint namespace before stale generated version namespace" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-nested-entrypoint-namespace", tmp_root) do |root|
      write_tree(root, {
        "warden_oauth.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "warden_oauth"
            spec.version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/warden_oauth/version.rb", mod) }::WardenOauth::Version::VERSION
            spec.summary = "Warden OAuth"
            spec.required_ruby_version = ">= 1.8"
          end
        RUBY
        "lib/warden_oauth.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "warden_oauth/version"

          module Warden
            module OAuth
              autoload :Strategy, "warden_oauth/strategy"
            end
          end
        RUBY
        "lib/warden_oauth/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module WardenOauth
            module Version
              VERSION = "0.1.1"
            end
            VERSION = Version::VERSION
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "🛡️"
          rubygems:
            min_ruby: "1.8"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})
      tokens = described_class.send(:template_tokens, facts, {})

      expect(facts.dig(:rubygems, :namespace)).to eq("Warden::OAuth")
      expect(facts.dig(:rubygems, :namespace)).not_to eq("WardenOauth")
      expect(tokens.fetch("KJ|NAMESPACE_SHIELD")).to eq("Warden::OAuth")
    end
  end

  it "normalizes generated README badge image URLs consistently with pre-release checks" do
    expect(described_class.send(:shield_token, "Example::Gem")).to eq("Example::Gem")
    expect(described_class.send(:license_compat_img, :a)).to include(
      "Apache_Compatible:_Category_A-%E2%9C%93-259D6C.svg"
    )
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
        ".kettle-jem.yml" => <<~YAML
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
              - authors
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
          K_JEM_TEMPLATING=true bundle exec kettle-jem template
          ```

          ## Usage

          Destination usage.

          ## Custom Section

          Destination custom.

          ## Note: Local

          Destination note.

          ## Authors

          Destination authors.

          ## Installation

          Old install.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
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
      expect(final_content).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis\./)
      expect(final_content).to include("### Details\n\nDestination nested detail.")
      expect(final_content).to include("# DANGER: keep this code comment inside the Synopsis branch.")
      expect(final_content).to include("K_JEM_TEMPLATING=true bundle exec kettle-jem template")
      expect(final_content).to include("## 🔧 Basic Usage\n\nDestination usage.")
      expect(final_content).to include("## Custom Section\n\nDestination custom.")
      expect(final_content).to include("## Note: Local\n\nDestination note.")
      expect(final_content).to include("## Authors\n\nDestination authors.")
      expect(final_content).to include("## Installation\n\nTemplate install.")
      expect(final_content).to match(/## Note: Local\n\nDestination note\.\n\n## Authors\n\nDestination authors\.\n\n## Installation/m)
      expect(final_content).not_to include("Template synopsis.")
      expect(final_content).not_to include("Template usage.")
      expect(final_content).not_to include("Template custom.")
      expect(final_content).not_to include("Template note.")
      expect(File.read(File.join(root, "README.md"))).to eq(final_content)
    end
  end

  it "preserves a front Important section that encloses the README badge cloud" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-front-important-slice", tmp_root) do |root|
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
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## Important

          Keep this local warning.

          [![Version][version-img]][version] [![CI][ci-img]][ci]

          ## Synopsis

          Destination synopsis.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          # 💎 Example

          [![Version][version-img]][version] [![CI][ci-img]][ci]

          ## 🌻 Synopsis

          Template synopsis.

          ## ✨ Installation

          Template install.
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      readme = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).to include("## Important\n\nKeep this local warning.")
      expect(readme).to match(/\A# 💎 Example\n\n## Important/m)
      expect(readme).to match(/## Important.*\[!\[Version\]\[version-img\]\]\[version\].*## 🌻 Synopsis/m)
      expect(readme).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis\./)
      expect(readme).to include("## ✨ Installation\n\nTemplate install.")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "only preserves recognized README front sections before the first canonical section" do
    template = <<~MARKDOWN
      # Example

      Template prelude.

      ## Synopsis

      Template synopsis.
    MARKDOWN
    important_destination = <<~MARKDOWN
      # Example

      ## Important

      Keep this warning even without badges.

      ## Synopsis

      Destination synopsis.
    MARKDOWN
    unknown_destination = <<~MARKDOWN
      # Example

      ## Old Notes

      Drop this stale front section.

      ## Synopsis

      Destination synopsis.
    MARKDOWN
    no_synopsis_destination = <<~MARKDOWN
      # Example

      ## Important

      No canonical anchor exists.
    MARKDOWN

    important = described_class.send(:preserve_readme_front_sections, template, important_destination)

    expect(important).to include("## Important\n\nKeep this warning even without badges.")
    expect(described_class.send(:preserve_readme_front_sections, template, unknown_destination)).to eq(template)
    expect(described_class.send(:preserve_readme_front_sections, template, no_synopsis_destination)).to eq(template)
    expect(described_class.send(:preserve_readme_front_sections, "# Example\n", important_destination)).to eq("# Example\n")
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
        "template/config/explicit.yml.example" => <<~YAML
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
        "schedule" => {"interval" => "weekly"},
        "updates" => [
          {
            "directory" => "/",
            "package-ecosystem" => "bundler"
          }
        ],
        "version" => 1
      )
      expect(YAML.safe_load(yaml_report.fetch(:final_content))).to eq(
        "engines" => ["ruby"],
        "nested" => {
          "template_only" => true,
          "value" => "destination"
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
          "value" => "destination"
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
        "template/.kettle-jem.yml.example" => <<~YAML
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
        "template/config/settings.yml.example" => <<~YAML
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
          source "https://gem.coop"
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
        "template/lib/example.rb.example" => <<~RUBY
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
      expect(final_content).to include('require "json"')
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

  it "normalizes generated Rakefile section spacing after merge" do
    rakefile = described_class.send(:normalize_generated_rakefile, <<~RAKE)
      task :custom do
        puts "custom"
      end


      ### TEMPLATING TASKS
      task "kettle:jem:selftest"
    RAKE

    expect(rakefile).to include("\n\n### TEMPLATING TASKS\n")
    expect(rakefile).not_to include("\n\n\n### TEMPLATING TASKS")
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
        "template/lib/example.rb.example" => <<~RUBY
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
        "template/Appraisals.example" => <<~RUBY
          # frozen_string_literal: true

          appraise "ruby-3-2" do
            eval_gemfile "gemfiles/modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "head" do
            eval_gemfile "gemfiles/modular/recording/r4/recording.gemfile"
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
      expect(appraisals_content).to include('appraise "head"')
      expect(appraisals_content).not_to include('gem "cgi"')
      expect(appraisals_content).not_to include("modular/recording/")
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

  it "keeps Appraisals recording gemfiles only when configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisals-recording-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            recording: true
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "template/Appraisals.example" => <<~RUBY
          # frozen_string_literal: true

          appraise "head" do
            gem "cgi", ">= 0.5"
            eval_gemfile "gemfiles/modular/recording/r4/recording.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      appraisals_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Appraisals"
      end
      appraisals_content = appraisals_report.fetch(:final_content)

      expect(appraisals_content).not_to include('gem "cgi"')
      expect(appraisals_content).to include('eval_gemfile "gemfiles/modular/recording/r4/recording.gemfile"')
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
        "template/Appraisals.example" => <<~RUBY
          appraise "#{contract_case.fetch(:template_appraisal)}" do
            gemfile "gemfiles/ruby_4.0.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
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

  it "preserves destination additions inside same-named Appraisal blocks" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisals-same-name-merge", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "test gem"
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
          appraise "ruby-3-2" do
            eval_gemfile "modular/activerecord/r3/v8.0.gemfile"
            eval_gemfile("modular/x_std_libs/r3/libs.gemfile")
          end
        RUBY
        "template/Appraisals.example" => <<~RUBY
          appraise "ruby-3-2" do
            eval_gemfile "modular/style.gemfile"
            eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = report.fetch(:final_content)

      expect(appraisals_eval_gemfile_paths(appraisals_content, "ruby-3-2")).to contain_exactly(
        "modular/style.gemfile",
        "modular/activerecord/r3/v8.0.gemfile",
        "modular/x_std_libs/r3/libs.gemfile"
      )
    end
  end

  it "collapses framework appraisals onto standard appraisals without overwriting kept framework gemfiles" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-framework-collapse-kept-gemfiles", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "test gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            preset: framework
            framework_matrix:
              dimension: rails
              gem: rails
              gemfile_pattern: "rails_{version}.gemfile"
              workflow: false
              versions:
                - label: "7.2"
                  slug: "7_2"
                  requirement: "~> 7.2.2"
                  standard_appraisal: ruby-3-2
                  env:
                    RAILS_MAJOR_MINOR: "7.2"
          patterns:
            - path: "gemfiles/rails_*.gemfile"
              strategy: keep_destination
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
              - gemfiles/rails_7_2.gemfile
              - .github/workflows/framework-ci.yml
              - .github/workflows/ruby-3.2.yml
        YAML
        "Appraisals" => <<~RUBY,
          appraise "ruby-3-2" do
            eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "rails-7-2" do
            gem "combustion", "~> 1.5"
            gem "actionmailer", "~> 7.2.2"
            gem "railties", "~> 7.2.2"
          end
        RUBY
        "gemfiles/rails_7_2.gemfile" => <<~RUBY,
          # This file was generated by Appraisal
          gem "combustion", "~> 1.5"
          gem "actionmailer", "~> 7.2.2"
          gem "railties", "~> 7.2.2"
        RUBY
        "template/Appraisals.example" => <<~RUBY,
          appraise "ruby-3-2" do
            eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
          end
        RUBY
        "template/.github/workflows/framework-ci.yml.example" => "name: Framework CI\n",
        "template/.github/workflows/ruby-3.2.yml.example" => <<~YAML,
          name: Ruby 3.2

          jobs:
            test:
              env:
                BUNDLE_GEMFILE: ${{ github.workspace }}/Appraisal.root.gemfile
              strategy:
                matrix:
                  include:
                    - ruby: "ruby-3.2"
                      appraisal: "ruby-3-2"
                      exec_cmd: "kettle-test"
        YAML
        "template/gemfiles/rails_7_2.gemfile.example" => "gem \"rails\", \"~> 7.2.2\"\n"
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      appraisals_report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = appraisals_report.fetch(:final_content)
      workflow_report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".github/workflows/ruby-3.2.yml" }
      workflow_content = workflow_report.fetch(:final_content)

      expect(appraisals_content).not_to include("ENV[")
      expect(appraisals_content).to include('eval_gemfile "rails_7_2.gemfile"')
      expect(appraisals_content).not_to include('appraise "rails-7-2"')
      expect(workflow_content).to include("KJ_FRAMEWORK_MATRIX_GEM: ${{ matrix.KJ_FRAMEWORK_MATRIX_GEM || '' }}")
      expect(workflow_content).to include("RAILS_MAJOR_MINOR: ${{ matrix.RAILS_MAJOR_MINOR || '' }}")
      expect(workflow_content).to include('KJ_FRAMEWORK_MATRIX_GEM: "rails"')
      expect(workflow_content.scan('KJ_FRAMEWORK_MATRIX_GEM: "rails"').size).to eq(1)
      expect(workflow_content).to include('RAILS_MAJOR_MINOR: "7.2"')
      expect(File.read(File.join(root, "gemfiles/rails_7_2.gemfile"))).to include('gem "combustion", "~> 1.5"')
      expect(File).not_to exist(File.join(root, ".github/workflows/framework-ci.yml"))
    end
  end

  it "adds configured support gemfiles to standard test Appraisal blocks" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-standard-appraisal-gemfiles", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "test gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          appraisal_matrix:
            appraisal_gemfiles:
              - gemfiles/modular/activerecord_support.gemfile
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "template/Appraisals.example" => <<~RUBY
          appraise "current" do
            eval_gemfile "modular/x_std_libs.gemfile"
          end

          appraise "ruby-3-2" do
            eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
          end

          appraise "style" do
            eval_gemfile "modular/style.gemfile"
            eval_gemfile "modular/x_std_libs.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = report.fetch(:final_content)

      expect(appraisals_content).to include(<<~RUBY.strip)
        appraise "current" do
          eval_gemfile "modular/activerecord_support.gemfile"
          eval_gemfile "modular/x_std_libs.gemfile"
        end
      RUBY
      expect(appraisals_content).to include(<<~RUBY.strip)
        appraise "ruby-3-2" do
          eval_gemfile "modular/activerecord_support.gemfile"
          eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
        end
      RUBY
      expect(appraisals_content).not_to include(<<~RUBY.strip)
        appraise "style" do
          eval_gemfile "modular/style.gemfile"
          eval_gemfile "modular/activerecord_support.gemfile"
          eval_gemfile "modular/x_std_libs.gemfile"
        end
      RUBY
    end
  end

  it "does not add broad standard support gemfiles to collapsed framework appraisals" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-standard-appraisal-collapse-skip", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "test gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            standard_appraisal_gemfiles:
              - modular/activerecord_runtime.gemfile
              - modular/activerecord_support.gemfile
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "template/Appraisals.example" => <<~RUBY
          appraise "current" do
            eval_gemfile "modular/x_std_libs.gemfile"
          end

          appraise "ruby-3-2" do
            eval_gemfile "modular/activerecord/r3/v8.0.gemfile"
            eval_gemfile "modular/activerecord_support.gemfile"
            eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = report.fetch(:final_content)

      expect(appraisals_content).to include(<<~RUBY.strip)
        appraise "current" do
          eval_gemfile "modular/activerecord_runtime.gemfile"
          eval_gemfile "modular/activerecord_support.gemfile"
          eval_gemfile "modular/x_std_libs.gemfile"
        end
      RUBY
      expect(appraisals_content).to include(<<~RUBY.strip)
        appraise "ruby-3-2" do
          eval_gemfile "modular/activerecord/r3/v8.0.gemfile"
          eval_gemfile "modular/activerecord_support.gemfile"
          eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
        end
      RUBY
      expect(appraisals_content).not_to include('eval_gemfile "modular/activerecord_runtime.gemfile"' \
        "\n  eval_gemfile \"modular/activerecord/r3/v8.0.gemfile\"")
    end
  end

  it "adds standard gemfiles beside ordinary support gemfiles while respecting framework fragments" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-standard-appraisal-framework-fragments", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "test gem"
            spec.required_ruby_version = ">= 3.1"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          workflows:
            preset: framework
            standard_appraisal_gemfiles:
              - rails_7_2.gemfile
            framework_matrix:
              dimension: rails
              gem: rails
              gemfile_pattern: "rails_{version}.gemfile"
              versions:
                - label: "7.2"
                  slug: "7_2"
                  requirement: "~> 7.2.0"
                  standard_appraisal: "ruby-3-1"
                - label: "8.0"
                  slug: "8_0"
                  requirement: "~> 8.0.0"
                  standard_appraisal: "ruby-3-2"
          templates:
            root: template
            apply: true
            entries:
              - Appraisals
        YAML
        "template/Appraisals.example" => <<~RUBY
          appraise "coverage" do
            eval_gemfile "modular/coverage.gemfile"
            eval_gemfile "modular/x_std_libs.gemfile"
          end

          appraise "ruby-3-2" do
            eval_gemfile "modular/x_std_libs/r3/libs.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = report.fetch(:final_content)

      expect(appraisals_eval_gemfile_paths(appraisals_content, "coverage")).to contain_exactly(
        "modular/coverage.gemfile",
        "rails_7_2.gemfile",
        "modular/x_std_libs.gemfile"
      )
      expect(appraisals_eval_gemfile_paths(appraisals_content, "ruby-3-2")).to contain_exactly(
        "modular/x_std_libs/r3/libs.gemfile",
        "rails_8_0.gemfile"
      )
      expect(appraisals_eval_gemfile_paths(appraisals_content, "ruby-3-1")).to contain_exactly("rails_7_2.gemfile")
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
        "template/.github/workflows/appraisals.yml.example" => <<~YAML
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

  it "derives engine workflow Ruby floors from the compatibility matrix" do
    expect(described_class::RRRRB_MATRIX.fetch("truffleruby-23.1").mri).to eq("3.2")
    expect(described_class::RRRRB_MATRIX.fetch("truffleruby-23.1").workflow_ruby).to eq("3.1")
    expect(described_class::ENGINE_WORKFLOW_RUBY_COMPATIBILITY_FLOORS.fetch("truffleruby-23.1")).to eq("3.1")
    expect(described_class::RRRRB_MATRIX.fetch("jruby-10.0").mri).to eq("3.4")
    expect(described_class::ENGINE_WORKFLOW_RUBY_COMPATIBILITY_FLOORS.fetch("jruby-10.0")).to eq("3.4")
    expect(described_class::RRRRB_MATRIX.fetch("truffleruby-33.0").mri).to eq("3.3")
    expect(described_class::ENGINE_WORKFLOW_RUBY_COMPATIBILITY_FLOORS.fetch("truffleruby-33.0")).to eq("3.3")
    expect(described_class::RRRRB_MATRIX.fetch("ruby-2.4").rails_appraisals).to include("4.2.11.3", "5.2.8.1")
  end

  it "serializes legacy engine setup-ruby workaround in generated CI workflows" do
    ci = {
      default_branch: "main",
      exec_cmd: "kettle-test",
      ruby_versions: ["truffleruby-25.0", "jruby-9.3"]
    }
    workflows = [
      described_class.send(:synchronize_github_actions_ci, "", {package: {name: "example"}, ci: ci}),
      described_class.send(:synchronize_github_actions_framework_ci, "", {
        ci: ci.merge(
          framework_matrix: {
            dimension: "rails",
            include: [{framework_version: "7.2", appraisal: "rails_7_2"}]
          }
        )
      })
    ]

    expect(workflows).to all(include("bundler-cache: ${{ matrix.ruby != 'truffleruby-25.0' && matrix.ruby != 'jruby-9.3' }}"))
    expect(workflows).to all(include("      - name: Bundle install for legacy Ruby engine"))
    expect(workflows).to all(include("        if: ${{ matrix.ruby == 'truffleruby-25.0' || matrix.ruby == 'jruby-9.3' }}"))
    expect(workflows).to all(include("          bundle config set --local path vendor/bundle"))
    expect(workflows).to all(include("          bundle install --jobs 1"))

    packaged_workflow = File.read(File.join(
      __dir__,
      "../lib/kettle/jem/templates/.github/workflows/truffleruby-25.0.yml.example"
    ))
    expect(packaged_workflow).to include("bundler-cache: false")
    expect(packaged_workflow).to include("      - name: Bundle install for TruffleRuby 25.0")
    expect(packaged_workflow).to include("          bundle config set --local path vendor/bundle")
    expect(packaged_workflow).to include("          bundle install --jobs 1")

    packaged_workflow = File.read(File.join(
      __dir__,
      "../lib/kettle/jem/templates/.github/workflows/jruby-9.3.yml.example"
    ))
    expect(packaged_workflow).to include("bundler-cache: false")
    expect(packaged_workflow).to include("      - name: Bundle install for JRuby 9.3")
    expect(packaged_workflow).to include("          bundle config set --local path vendor/bundle")
    expect(packaged_workflow).to include("          bundle install --jobs 1")
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

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
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
        "template/Gemfile.example" => <<~RUBY
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

  it "merges modular local Gemfile dependency lists while preserving the destination package" do
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
        "template/gemfiles/modular/templating_local.gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          local_gems = %w[
            tree_haver
            ast-merge
            rubocop-ruby2_4
            kettle-jem
          ]

          tree_sitter_language_pack_dev = ENV.fetch("TREE_SITTER_LANGUAGE_PACK_DEV", nil)
          unless tree_sitter_language_pack_dev.to_s.empty?
            gem "tree_sitter_language_pack", path: tree_sitter_language_pack_dev
          end
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
      expect(content).to include("kettle-jem")
      expect(content).to include("TREE_SITTER_LANGUAGE_PACK_DEV")
      expect(content).to include('gem "tree_sitter_language_pack", path: tree_sitter_language_pack_dev')
      expect(File.read(File.join(root, "gemfiles/modular/templating_local.gemfile"))).to eq(content)
    end
  end

  it "adds configured kettle plugins to the kettle-rb local Gemfile overrides" do
    runtime = described_class.send(
      :project_runtime_facts,
      {"plugins" => ["kettle-drift", "example-plugin"]},
      {},
      package_name: "example",
      source_url: "https://github.com/example/example",
      author_domain: "example.test",
      min_ruby: ">= 3.2",
      test_min_ruby: Gem::Version.new("3.2"),
      version: "0.1.0"
    )
    tokens = described_class.send(:project_runtime_template_tokens, runtime)

    expect(tokens.fetch("KJ|KETTLE_RB_LOCAL_GEMS")).to eq("kettle-dev kettle-test kettle-soup-cover kettle-drift")
    expect(tokens.fetch("KJ|PACKAGE_NAME")).to eq("example")
  end

  it "exposes package summary and description tokens for generated metadata" do
    tokens = described_class.send(
      :template_tokens,
      {
        package: {
          name: "example",
          summary: "Example summary",
          description: "Example description"
        },
        rubygems: {},
        project_runtime: {}
      },
      {}
    )

    expect(tokens.fetch("KJ|PACKAGE_SUMMARY")).to eq("Example summary")
    expect(tokens.fetch("KJ|PACKAGE_DESCRIPTION")).to eq("Example description")
  end

  it "templates spec helper coverage bootstrap before loading the library" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-spec-helper-coverage", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: 🧪
          rubygems:
            entrypoint_require: "example/gem"
            namespace: "Example::Custom"
          templates:
            root: packaged
            apply: true
            entries:
              - spec/spec_helper.rb
        YAML
        "spec/spec_helper.rb" => <<~RUBY
          # frozen_string_literal: true

          require "example/custom"

          RSpec.configure do |config|
            config.example_status_persistence_file_path = ".rspec_status"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "spec/spec_helper.rb"
      end
      content = report.fetch(:final_content)

      expect(content.index('require "kettle-soup-cover"')).to be < content.index('require "example/custom"')
      expect(content).to include("if Kettle::Soup::Cover::DO_COV")
      expect(content).to include('require "simplecov"')
      expect(content.index('require "simplecov"')).to be < content.index('require "kettle/soup/cover/config"')
      expect(content.index('require "kettle/soup/cover/config"')).to be < content.index("SimpleCov.start")
      expect(content).to include("SimpleCov.start")
      expect(content).to include('require "kettle/test/rspec"')
      expect(content.scan('require "example/custom"').size).to eq(1)
    end
  end

  it "preserves destination spec helper support wiring while adding template bootstrap" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-spec-helper-custom-wiring", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: 🧪
          rubygems:
            entrypoint_require: "example/custom"
            namespace: "Example::Custom"
          templates:
            root: packaged
            apply: true
            entries:
              - spec/spec_helper.rb
        YAML
        "spec/spec_helper.rb" => <<~RUBY
          # frozen_string_literal: true

          # Internal ENV config
          require_relative "config/debug"
          require_relative "config/vcr"

          require "kettle/test/rspec"
          require "example-gem"

          # Internal RSpec & related config
          require_relative "support/shared_contexts/with_rake"
          require_relative "support/shared_contexts/with_mocked_git_adapter"

          RSpec.configure do |config|
            config.include_context "with mocked git adapter"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "spec/spec_helper.rb"
      end
      content = report.fetch(:final_content)

      expect(content).to include('require "kettle-soup-cover"')
      expect(content.index('require "kettle-soup-cover"')).to be < content.index('require "example-gem"')
      expect(content).to include("if Kettle::Soup::Cover::DO_COV")
      expect(content).to include('require "simplecov"')
      expect(content.index('require "simplecov"')).to be < content.index('require "kettle/soup/cover/config"')
      expect(content.index('require "kettle/soup/cover/config"')).to be < content.index("SimpleCov.start")
      expect(content).to include("SimpleCov.start")
      expect(content.scan('require "kettle/test/rspec"').size).to eq(1)
      expect(content.scan('require "example-gem"').size).to eq(1)
      expect(content).not_to include('require "example/gem"')
      expect(content).not_to include("require \"kettle/test/rspec\"\n\n\n# Internal ENV config")
      expect(content).to include('require_relative "config/debug"')
      expect(content).to include('require_relative "config/vcr"')
      expect(content).to include('require_relative "support/shared_contexts/with_rake"')
      expect(content).to include('require_relative "support/shared_contexts/with_mocked_git_adapter"')
      expect(content).to include('config.include_context "with mocked git adapter"')
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
        "gemfiles/modular/style_local.gemfile" => <<~RUBY
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

  it "generates nomono in the main Gemfile before local workspace overrides need it" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-nomono", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "Gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).to include('gem "nomono", "~> 1.0", ">= 1.0.6", require: false')
      expect(content.index('gem "nomono"')).to be < content.index('eval_gemfile "gemfiles/modular/templating.gemfile"')
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "treats packaged CITATION.cff as template-owned metadata by default" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-citation-default-strategy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.authors = ["Ada Lovelace"]
            spec.email = ["ada@example.com"]
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          repository:
            topology: standalone
          templates:
            root: packaged
            apply: true
            entries:
              - CITATION.cff
          tokens:
            author:
              orcid: 0000-0001-2345-6789
        YAML
        "CITATION.cff" => <<~YAML
          cff-version: 1.2.0
          title: "example"
          identifiers:
            - type: url
              value: 'https://github.com/acme/example/tree/main/gems/example'
          repository-code: 'https://github.com/acme/example/tree/main/gems/example'
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "CITATION.cff"
      end
      content = report.fetch(:final_content)

      expect(report.dig(:metadata, :template_source_preference)).to include(strategy: "accept_template")
      expect(content).to include("repository-code: 'https://github.com/acme/example'")
      expect(content).not_to include("/gems/example")
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
        "template/gemfiles/modular/debug.gemfile.example" => <<~RUBY
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
      version_content = File.read(File.join(root, "lib", "legacy", "shim", "version.rb"))

      expect(content).to include("debug")
      expect(content).not_to match(/^\s+example-gem$/)
      expect(content).not_to match(/^\s*gem\s+["']example-gem["']/)
      expect(File.read(File.join(root, "gemfiles/modular/debug.gemfile"))).to eq(content)
      expect(version_content).to include('require "legacy-shim2"')
      expect(version_content).not_to include("require_relative")
      expect(version_content).to include("Version = Legacy::Shim2::Version unless const_defined?(:Version, false)")
      expect(version_content).to include("VERSION = Legacy::Shim2::VERSION unless const_defined?(:VERSION, false)")
      expect(version_content).not_to include('VERSION = "0.1.0"')
    end
  end

  it "generates shunted.gemfile entries from resolved development dependency Ruby floors" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    resolver = Class.new do
      def versions(gem_name, requirements: nil)
        case gem_name
        when "debug"
          [{number: "1.9.2", ruby_version: ">= 3.3"}]
        when "rack-session"
          [
            {number: "1.0.1", ruby_version: ">= 2.3"},
            {number: "2.1.2", ruby_version: ">= 2.5"}
          ]
        when "rake"
          [{number: "13.2.1", ruby_version: ">= 2.6"}]
        else
          []
        end
      end

      def min_ruby_version(gem_name, version)
        case gem_name
        when "debug"
          Gem::Version.new("3.3")
        when "rack-session"
          (version == "1.0.1") ? Gem::Version.new("2.3") : Gem::Version.new("2.5")
        else
          Gem::Version.new("2.6")
        end
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
            spec.add_development_dependency "rack-session", ">= 0"
            spec.add_development_dependency "rake", "~> 13.0"
          end
        RUBY
        "gemfiles/modular/shunted.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          # local notes remain outside the generated block
        RUBY
        "gemfiles/modular/rack-session/r2.4/v2.0.gemfile" => <<~RUBY
          gem "rack-session", "< 2", github: "pboling/rack-session", branch: "fix-missing-rack-session"
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {rubygems_resolver: resolver})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/shunted.gemfile"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:request_envelope).fetch(:request).fetch(:provider_family)).to eq("ruby")
      expect(report.fetch(:request_envelope).fetch(:request).fetch(:provider_backend)).to eq("ast-crispr-ruby-prism")
      expect(report.fetch(:report_envelope).fetch(:report).fetch(:step_reports).first.fetch(:metadata).fetch(:provider_family)).to eq("ruby")
      expect(content).to include("# local notes remain outside the generated block")
      expect(content).to include('gem "debug", "~> 1.9" # ruby >= 3.3')
      expect(content).not_to include('gem "rack-session"')
      expect(content).not_to include('gem "rake"')
      expect(File.read(File.join(root, "gemfiles/modular/shunted.gemfile"))).to eq(content)

      described_class.apply_project(root, env: {}, run_options: {rubygems_resolver: resolver})
      reapplied = File.read(File.join(root, "gemfiles/modular/shunted.gemfile"))
      expect(reapplied.lines.count { |line| line.include?(Kettle::Jem::MANAGED_BLOCK_OPEN) }).to be <= 1
      expect(reapplied.lines.count { |line| line.include?(Kettle::Jem::MANAGED_BLOCK_CLOSE) }).to be <= 1
      expect(reapplied).to include("# local notes remain outside the generated block")

      described_class.apply_project(root, env: {}, run_options: {rubygems_resolver: resolver})
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
        "template/gemfiles/modular/debug.gemfile.example" => <<~RUBY
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
        "template/example.gemspec.example" => <<~RUBY
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

  it "lets configured rubygems minimum Ruby override preserved gemspec Ruby floor" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-min-ruby-config-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.required_ruby_version = ">= 1.9.3"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "2.4"
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.1"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include('spec.required_ruby_version = ">= 2.4"')
      expect(gemspec_content).not_to include('gem.required_ruby_version = ">= 1.9.3"')
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
        "template/my-gem.gemspec.example" => <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version =
            if Gem.ruby_version >= Gem::Version.new("3.1")
              Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/{KJ|GEM_NAME_PATH}/version.rb", mod) }::{KJ|NAMESPACE}::Version::VERSION
            else
              require_relative "lib/{KJ|GEM_NAME_PATH}/version"
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
      expect(gemspec_content).to include("spec.version = Module.new.tap { |mod| Kernel.load(\"\#{__dir__}/lib/my/gem/version.rb\", mod) }::My::Gem::Version::VERSION")
      version_loader_operation = gemspec_report.dig(
        :report_envelope,
        :report,
        :step_reports,
        0,
        :metadata,
        :ruby_template_policy,
        :operations
      ).find { |operation| operation[:operation] == "rewrite_version_loader" }
      expect(version_loader_operation).to include(mode: "modern", legacy_preamble_removed: true)
      expect(Gem::Version.new(version_loader_operation.fetch(:min_ruby))).to be >= Gem::Version.new("3.1")
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "rewrites preserved dependency requirements that interpolate the project version constant" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-version-dependency-slice", tmp_root) do |root|
      write_tree(root, {
        "gemserver-gem_coop.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "lib/gemserver/gem_coop/version"

          Gem::Specification.new do |spec|
            spec.name = "gemserver-gem_coop"
            spec.version = Gemserver::GemCoop::VERSION
            spec.summary = "Gem coop preset"
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency "gemserver-purl", "= \#{Gemserver::GemCoop::VERSION}"
          end
        RUBY
        "lib/gemserver/gem_coop/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Gemserver
            module GemCoop
              module Version
                VERSION = "0.1.0"
              end
              VERSION = Version::VERSION
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "3.2"
            entrypoint_require: "gemserver/gem_coop"
            namespace: "Gemserver::GemCoop"
          templates:
            root: template
            apply: true
            entries:
              - gemserver-gem_coop.gemspec
        YAML
        "template/gemserver-gem_coop.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_gemserver_gem_coop_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).not_to include('require_relative "lib/gemserver/gem_coop/version"')
      expect(gemspec_content).to include("spec.version = Module.new.tap { |mod| Kernel.load(\"\#{__dir__}/lib/gemserver/gem_coop/version.rb\", mod) }::Gemserver::GemCoop::Version::VERSION")
      expect(gemspec_content).to include(%(spec.add_dependency "gemserver-purl", "= \#{spec.version}"))
      expect(gemspec_content).not_to include("Gemserver::GemCoop::VERSION}")
      expect { load File.join(root, "gemserver-gem_coop.gemspec") }.not_to raise_error
      expect(File.read(File.join(root, "gemserver-gem_coop.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps gemspec legacy version loading with require_relative when minimum Ruby is below 3.1 and at least 2.2" do
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
        "template/my-gem.gemspec.example" => <<~RUBY
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
      expect(gemspec_content).to include('require_relative "lib/my/gem/version"')
      expect(gemspec_content).not_to include("$LOAD_PATH.unshift(lib)")
      expect(gemspec_content).not_to include('require "my/gem/version"')
      expect(gemspec_content).to include("My::Gem::Version::VERSION")
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "rewrite_version_loader", min_ruby: "3.0", mode: "legacy", legacy_preamble_present: true)
      )
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps load-path gemspec legacy version loading only when minimum Ruby is below 2.2" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-pre-require-relative-version-loader-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = "0.1.0"
            gem.summary = "Pre require_relative loader"
            gem.required_ruby_version = ">= 2.1"
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
        "template/my-gem.gemspec.example" => <<~RUBY
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
      expect(gemspec_content).to include("$LOAD_PATH.unshift(lib)")
      expect(gemspec_content).to include('lib = File.expand_path("lib", File.dirname(__FILE__))')
      expect(gemspec_content).to include('require "my/gem/version"')
      expect(gemspec_content).not_to include('require_relative "lib/my/gem/version"')
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "rewrite_version_loader", min_ruby: "2.1", mode: "legacy", legacy_preamble_present: true)
      )
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps explicit zero runtime gemspec floor dependency-free for Ruby 1.x compatibility" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-zero-runtime-floor-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = "0.1.0"
            gem.summary = "Zero floor loader"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "0"
            entrypoint_require: "my/gem"
            namespace: "My::Gem"
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include("gem_version =")
      expect(gemspec_content).to include('if Gem.ruby_version >= Gem::Version.new("3.1")')
      expect(gemspec_content).to include('lib = File.expand_path("lib", File.dirname(__FILE__))')
      expect(gemspec_content).to include('require "my/gem/version"')
      expect(gemspec_content).not_to include("required_ruby_version")
      expect(gemspec_content).not_to include("version_gem")
      expect(gemspec_content).not_to include("require_relative")
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "removes version_gem dependency and entrypoint references under an old Ruby floor" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-remove-version-gem-runtime", tmp_root) do |root|
      write_tree(root, {
        "legacy.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "legacy"
            gem.version = "0.1.0"
            gem.summary = "Legacy gem"
            gem.homepage = "https://github.com/acme/legacy"
            gem.required_ruby_version = ">= 1.8.7"
            gem.add_dependency("version_gem", "~> 1.1", ">= 1.1.10")
          end
        RUBY
        "lib/legacy.rb" => <<~RUBY,
          # frozen_string_literal: true

          require "version_gem"
          require_relative "legacy/version"

          module Legacy
          end

          Legacy::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/legacy/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Legacy
            module Version
              VERSION = "0.1.0"
            end
            VERSION = Version::VERSION # Traditional Constant Location
          end
        RUBY
        "gemfiles/modular/runtime_heads.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          # Test against HEAD of runtime dependencies so we can proactively file bugs

          # Ruby >= 2.2
          gem "version_gem", github: "ruby-oauth/version_gem", branch: "main"

          eval_gemfile("x_std_libs/vHEAD.gemfile")
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "1.8.7"
            entrypoint_require: "legacy"
            namespace: "Legacy"
          templates:
            root: template
            apply: true
            entries:
              - legacy.gemspec
              - gemfiles/modular/runtime_heads.gemfile
        YAML
        "template/legacy.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
            # Ref: https://gitlab.com/ruby-oauth/version_gem/-/issues/3
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")
          end
        RUBY
        "template/gemfiles/modular/runtime_heads.gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          # Test against HEAD of runtime dependencies so we can proactively file bugs

          # Ruby >= 2.2
          gem "version_gem", github: "ruby-oauth/version_gem", branch: "main"

          eval_gemfile("x_std_libs/vHEAD.gemfile")
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_legacy_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)
      entrypoint_content = File.read(File.join(root, "lib", "legacy.rb"))
      version_content = File.read(File.join(root, "lib", "legacy", "version.rb"))
      runtime_heads_content = File.read(File.join(root, "gemfiles", "modular", "runtime_heads.gemfile"))

      expect(gemspec_content).not_to include("version_gem")
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 1.8.7"')
      expect(apply.fetch(:post_apply_steps)).to include(hash_including(
        name: "version_gem_cleanup",
        status: "applied",
        changed_files: ["lib/legacy.rb"]
      ))
      expect(entrypoint_content).not_to include("version_gem")
      expect(entrypoint_content).not_to include("VersionGem")
      expect(entrypoint_content).to include('require_relative "legacy/version"')
      expect(entrypoint_content).not_to end_with("\n\n")
      expect(version_content).to include("module Version")
      expect(version_content).to include('VERSION = "0.1.0"')
      expect(version_content).to include("VERSION = Version::VERSION # Traditional Constant Location")
      expect(runtime_heads_content).not_to include("version_gem")
      expect(runtime_heads_content).to include('eval_gemfile("x_std_libs/vHEAD.gemfile")')
      expect(File.read(File.join(root, "legacy.gemspec"))).to eq(gemspec_content)
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
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 4.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")

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

  it "keeps the packaged gemspec template dependency floors current" do
    template = File.read(File.expand_path("../lib/kettle/jem/templates/gem.gemspec.example", __dir__))

    expect(template).to include(%(spec.add_development_dependency("{KJ|KETTLE_DEV_GEM}", "~> 2.2", ">= 2.2.18")))
    expect(template).not_to include(%(spec.add_development_dependency("{KJ|KETTLE_DEV_GEM}", "~> 2.1", ">= 2.1.1")))
  end

  it "keeps the greater version requirement for template-managed gemspec dependencies" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-template-managed-dependencies", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 3.2"
            gem.add_dependency("json", "~> 2.10")
            gem.add_development_dependency("kettle-dev", "~> 2.0")
            gem.add_development_dependency("rake", "~> 13.1")
            gem.add_development_dependency("custom-dev", ">= 1")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")

            # NOTE: It is preferable to list development dependencies in the gemspec due to increased
            #       visibility and discoverability.

            spec.add_development_dependency("kettle-dev", "~> 2.2", ">= 2.2.18")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include(%(spec.add_dependency("json", "~> 2.10")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("custom-dev", ">= 1")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("kettle-dev", "~> 2.2", ">= 2.2.18")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("rake", "~> 13.1")))
      expect(gemspec_content).not_to include(%(spec.add_development_dependency("kettle-dev", "~> 2.0")\n))
      expect(gemspec_content).not_to include(%(spec.add_development_dependency("rake", "~> 13.0")))
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "does not duplicate runtime gemspec dependencies as development dependencies" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-runtime-dev-dedup-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 2.4"
            gem.add_dependency("kettle-test", "~> 2.0", ">= 2.0.7")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 2.4"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")

            # NOTE: It is preferable to list development dependencies in the gemspec due to increased
            #       visibility and discoverability.

            spec.add_development_dependency("kettle-test", "~> 2.0", ">= 2.0.7")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content.scan('add_dependency("kettle-test"').size).to eq(1)
      expect(gemspec_content).not_to include(%(add_development_dependency("kettle-test")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("rake", "~> 13.0")))
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "preserves zero-byte template outputs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-zero-byte-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - REEK
        YAML
        "template/REEK" => "",
        "REEK" => ""
      })

      apply = described_class.apply_project(root, env: {})
      reek_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == "REEK"
      end

      expect(reek_report.fetch(:final_content)).to eq("")
      expect(File.binread(File.join(root, "REEK"))).to eq("")
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
        "template/example.gemspec.example" => <<~RUBY
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
            spec.add_development_dependency("gitmoji-regex", "~> 2.0", ">= 2.0.3")
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
        "template/gem.gemspec.example" => <<~RUBY
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

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "#{package_name}.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content.scan(/Gem::Specification\.new\s+do/).count).to eq(1)
      expect(gemspec_content.scan(/^\s*spec\.name\s*=/).count).to eq(1)
      expect(gemspec_content).not_to match(/^spec\./)
      expect(gemspec_content).to include(contract_case.fetch(:summary))
      expect(gemspec_content).to include(contract_case.fetch(:description))
      expect(gemspec_content).to include(%(spec.executables = ["#{contract_case.fetch(:executable)}"]))
      expect(gemspec_content).to include(%(spec.add_development_dependency("gitmoji-regex", "~> 2.0", ">= 2.0.3")))
      expect(gemspec_content).not_to include("# Hence.")
      expect(gemspec_content).not_to include("add_development_dependency(\"#{package_name}\"")
      expect(File.read(File.join(root, "#{package_name}.gemspec"))).to eq(gemspec_content)
    end
  end

  it "preserves multiline heredoc gemspec assignments as whole fields" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-heredoc-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.version = "1.0.0"
            gem.summary = "Existing summary"
            gem.description = <<-DESC
          First line
          Second line
            DESC
            gem.homepage = "https://github.com/acme/example"
            gem.licenses = ["MIT"]
            gem.required_ruby_version = ">= 2.3"
            gem.add_development_dependency("test-unit", ">= 3")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🧪"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: example.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.description = "Template description"
            spec.homepage = "https://github.com/acme/{KJ|GEM_NAME}"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 2.3"
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "example.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include("spec.description = <<-DESC")
      expect(gemspec_content).not_to include("spec.description = 🧪")
      expect(gemspec_content).to include("🧪 First line")
      expect(gemspec_content).to include("Second line")
      expect(gemspec_content).to include("  DESC")
      expect(gemspec_content).to include('spec.homepage = "https://github.com/acme/example"')
      expect(gemspec_content).to include('spec.add_development_dependency("test-unit", ">= 3")')
      expect(gemspec_content).not_to match(/^spec\./)
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
        "template/gem.gemspec.example" => <<~RUBY
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

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "#{package_name}.gemspec" }
      gemspec_content = report.fetch(:final_content)
      lines = gemspec_content.lines
      gemspec_line = lines.find_index { |line| line.include?("Gem::Specification.new") }
      freeze_line = lines.find_index { |line| line.include?(contract_case.fetch(:open_marker)) }
      close_line = lines.find_index { |line| line.include?(contract_case.fetch(:close_marker)) }
      block_end_line = lines.each_index.to_a.reverse.find { |index| lines[index].strip == "end" }

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(freeze_line).to be > gemspec_line
      expect(close_line).to be > freeze_line
      expect(close_line).to be < block_end_line
      expect(gemspec_content).to include(%(# spec.add_dependency("#{contract_case.fetch(:custom_dependency)}")))
      expect(gemspec_content).not_to include("To retain during kettle-jem templating")
      expect(File.read(File.join(root, "#{package_name}.gemspec"))).to eq(gemspec_content)
    end
  end

  it "preserves gemspec freeze blocks with configured custom freeze tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-custom-gemspec-freeze-block-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = "1.0.0"
            spec.summary = "Freeze gem"

            # custom-freeze:freeze
            # Custom dependencies
            # spec.add_dependency("custom_dep")
            # custom-freeze:unfreeze

            spec.require_paths = ["lib"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          defaults:
            freeze_token: custom-freeze
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: example.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "2.0.0"
            spec.summary = "Template summary"
            spec.require_paths = ["lib"]
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "example.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include("# custom-freeze:freeze")
      expect(gemspec_content).to include('# spec.add_dependency("custom_dep")')
      expect(gemspec_content).to include("# custom-freeze:unfreeze")
      expect(gemspec_content).not_to include("# kettle-jem:freeze")
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
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
        "template/gem.gemspec.example" => <<~RUBY
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

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
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

  it "keeps multiline gemspec descriptions valid when adding the project emoji" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    package_name = "oauth2-mcp"

    Dir.mktmpdir("kettle-jem-gemspec-emoji", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.summary = "OAuth 2.1 resource-server helpers for MCP servers."
            spec.description = "oauth2-mcp provides Ruby helpers for securing HTTP Model Context Protocol servers " \\
                               "with OAuth protected-resource metadata, bearer challenges, and scoped authorization."
            spec.homepage = "https://github.com/ruby-oauth/oauth2-mcp"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🔮"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "{KJ|PROJECT_EMOJI} "
            spec.description = "{KJ|PROJECT_EMOJI} "
            spec.homepage = "https://template.example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "#{package_name}.gemspec"
      end
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include('spec.summary = "🔮 OAuth 2.1 resource-server helpers for MCP servers."')
      expect(gemspec_content).to include('spec.description = "🔮 oauth2-mcp provides Ruby helpers')
      expect(gemspec_content).not_to include("spec.description = 🔮")
    end
  end

  it "keeps squiggly heredoc gemspec descriptions valid when adding the project emoji" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    package_name = "sanitize_email"

    Dir.mktmpdir("kettle-jem-gemspec-emoji-squiggly-heredoc", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.summary = "Email Condom for your Ruby Server"
            spec.description = <<~DESCRIPTION.strip
                Email Condom for your Ruby Server.
              In Rails, Sinatra, et al.
            DESCRIPTION
            spec.homepage = "https://github.com/pboling/sanitize_email"
            spec.required_ruby_version = ">= 2.3"
            spec.add_dependency(<<~GEM.strip, <<~REQ.strip)
              rake
            GEM
              ~> 13.0
            REQ
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "📧"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "{KJ|PROJECT_EMOJI} "
            spec.description = "{KJ|PROJECT_EMOJI} "
            spec.homepage = "https://template.example"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "#{package_name}.gemspec"
      end
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include("spec.description = <<~DESCRIPTION.strip")
      expect(gemspec_content).to include("Email Condom for your Ruby Server.")
      expect(gemspec_content).to include("DESCRIPTION")
      expect(gemspec_content).to include("spec.add_dependency(<<~GEM.strip, <<~REQ.strip)")
      expect(gemspec_content).to include("rake")
      expect(gemspec_content).to include("REQ")
      expect(gemspec_content).not_to include("spec.description = 📧")
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
        x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r3/libs.gemfile"
      },
      {
        name: described_class.appraisal_name(
          tier1_gem: "mail",
          tier1_version: "2.8",
          ruby_series: "r2"
        ),
        ruby_series: "r2",
        tier1_gemfile: "gemfiles/modular/mail/r2/v2.8.gemfile",
        x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r2/libs.gemfile"
      }
    ]
    bucket_ranges = {
      "r2" => {floor: "2.7", ceiling: "2.99"},
      "r3" => {floor: "3.2", ceiling: "3.99"}
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
      sub_dependencies: {"sqlite3" => "1.6.9"}
    )).to eq(<<~RUBY)
      # frozen_string_literal: true

      # Generated by kettle-jem

      gem "activerecord", "~> 7.1.0"
      gem "sqlite3", "~> 1.6.9"
    RUBY

    appraisals = described_class.appraisal_file_content(matrix_entries)
    expect(appraisals).to include('appraise "kja-ar-7-1-oa-2-1-r3" do')
    expect(appraisals).to include('eval_gemfile "modular/activerecord/r3/v7.1.gemfile"')
    expect(appraisals).not_to include('eval_gemfile "gemfiles/')
    expect(appraisals).to include('appraise "kja-mail-2-8-r2" do')
    expect(appraisals).not_to end_with("\n\n")

    groups = described_class.appraisal_workflow_groups(matrix_entries, bucket_ranges: bucket_ranges)
    expect(groups).to eq(
      "supported" => [
        {
          ruby: "3.2",
          appraisal: "kja-ar-7-1-oa-2-1-r3",
          exec_cmd: "kettle-test",
          rubygems: "latest",
          bundler: "latest"
        }
      ],
      "unsupported" => [
        {
          ruby: "2.7",
          appraisal: "kja-mail-2-8-r2",
          exec_cmd: "kettle-test",
          rubygems: "latest",
          bundler: "latest"
        }
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
      {number: number}
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
            {version: "6.1", bucket: "r2"},
            {version: "7.2", bucket: "r3"}
          ]
        }
      ],
      tier2_gems: [
        {name: "omniauth", versions: ["2.1"]}
      ]
    )

    expect(entries).to eq(
      [
        {
          name: "kja-ar-6-1-oa-2-1-r2",
          tier1_gemfile: "gemfiles/modular/activerecord/r2/v6.1.gemfile",
          tier2_gemfile: "gemfiles/modular/omniauth/r2/v2.1.gemfile",
          x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r2/libs.gemfile",
          ruby_series: "r2"
        },
        {
          name: "kja-ar-7-2-oa-2-1-r3",
          tier1_gemfile: "gemfiles/modular/activerecord/r3/v7.2.gemfile",
          tier2_gemfile: "gemfiles/modular/omniauth/r3/v2.1.gemfile",
          x_std_libs_gemfile: "gemfiles/modular/x_std_libs/r3/libs.gemfile",
          ruby_series: "r3"
        }
      ]
    )
  end

  it "detects appraisal Ruby seams and assigns selected versions to buckets" do
    versions = [
      {number: "5.2.8", min_ruby: "2.3"},
      {number: "6.0.6", min_ruby: "2.5"},
      {number: "6.1.7", min_ruby: "2.5"},
      {number: "7.0.8", min_ruby: "2.7"},
      {number: "7.1.5", min_ruby: "2.7"},
      {number: "7.2.2", min_ruby: "3.1"}
    ]

    seams = described_class.appraisal_find_ruby_seams(versions)
    expect(seams).to eq(
      [
        {version: "5.2", min_ruby: Gem::Version.new("2.4")},
        {version: "6.0", min_ruby: Gem::Version.new("2.5")},
        {version: "7.0", min_ruby: Gem::Version.new("2.7")},
        {version: "7.2", min_ruby: Gem::Version.new("3.1")}
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
        {version: "5.2", bucket: "r2.4"},
        {version: "6.1", bucket: "r2.6"},
        {version: "7.1", bucket: "r2", filler: true},
        {version: "7.2", bucket: "r3"}
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
            {name: "sqlite3", requirements: "~> 1.6"},
            {name: "erb", requirements: ">= 0"}
          ]
        }
      ],
      dependency_versions: {
        "sqlite3" => [
          {number: "1.6.8", min_ruby: "2.7"},
          {number: "1.6.9", min_ruby: "3.0"},
          {number: "1.7.0", min_ruby: "3.2"}
        ]
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
          {"number" => "7.1.0.beta1", "ruby_version" => ">= 3.0", "prerelease" => true, "created_at" => "2024-01-01"},
          {"number" => "6.1.7", "ruby_version" => ">= 2.5", "prerelease" => false, "created_at" => "2023-01-01"},
          {"number" => "7.1.3", "ruby_version" => ">= 2.7", "prerelease" => false, "created_at" => "2024-02-01"}
        ]))
      when "https://example.test/api/v2/rubygems/active+record/versions/7.1.3.json"
        response.new("200", JSON.dump({
          "number" => "7.1.3",
          "ruby_version" => ">= 2.7",
          "dependencies" => {
            "runtime" => [
              {"name" => "sqlite3", "requirements" => "~> 1.6"}
            ]
          }
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
        {number: "7.1.3", ruby_version: ">= 2.7", created_at: "2024-02-01", prerelease: false}
      ]
    )
    expect(resolver.versions("active record", include_prerelease: true).map { |entry| entry.fetch(:number) }).to eq(
      ["6.1.7", "7.1.0.beta1", "7.1.3"]
    )
    expect(resolver.min_ruby_version("active record", "7.1.3")).to eq(Gem::Version.new("2.7"))
    expect(resolver.minor_versions_by_major("active record")).to eq(
      [
        {major: 6, minors: ["6.1"]},
        {major: 7, minors: ["7.1"]}
      ]
    )
    expect(resolver.version_info("active record", "7.1.3")).to eq(
      {
        number: "7.1.3",
        ruby_version: ">= 2.7",
        runtime_dependencies: [
          {name: "sqlite3", requirements: "~> 1.6"}
        ]
      }
    )
    expect(resolver.version_info("active record", "7.1.3")).to be_a(Hash)
    expect(calls.tally).to eq(
      "https://example.test/api/v1/versions/active+record.json" => 1,
      "https://example.test/api/v2/rubygems/active+record/versions/7.1.3.json" => 1
    )
  end

  it "loads gemspec metadata through Kettle/Jem GemSpecReader" do
    Dir.mktmpdir do |project_root|
      write_tree(
        project_root,
        {
          "demo_tool.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "demo_tool"
              spec.version = "0.1.0"
              spec.authors = ["Demo Author"]
              spec.email = ["demo@example.com"]
              spec.summary = "Demo"
              spec.homepage = "https://github.com/example/demo_tool"
              spec.required_ruby_version = ">= 3.2"
              spec.add_dependency "runtime_dep", ">= 1"
              spec.add_development_dependency "dev_dep", ">= 1"
            end
          RUBY
          "lib/demo_tool/version.rb" => "module DemoTool; VERSION = '0.1.0'; end\n"
        }
      )

      described_class::GemSpecReader.clear_cache!

      metadata = described_class::GemSpecReader.load(project_root)

      expect(metadata).to include(
        gem_name: "demo_tool",
        version: "0.1.0",
        min_ruby: Gem::Version.new("3.2"),
        homepage: "https://github.com/example/demo_tool",
        gh_org: "example",
        gh_repo: "demo_tool",
        namespace: "DemoTool",
        entrypoint_require: "demo_tool"
      )
      expect(metadata.fetch(:runtime_dependencies).map(&:name)).to eq(["runtime_dep"])
      expect(metadata.fetch(:development_dependencies).map(&:name)).to eq(["dev_dep"])
    end
  ensure
    described_class::GemSpecReader.clear_cache!
  end

  it "ports appraisal CLI config orchestration helpers into Kettle/Jem" do
    gemspec_content = <<~RUBY
      Gem::Specification.new do |spec|
        spec.add_dependency "activerecord", "~> 7.1"
        spec.add_runtime_dependency("erb", ">= 0")
        # spec.add_dependency "ignored"
        spec.add_runtime_dependency "sequel", ">= 5.0"
        spec.add_development_dependency "dev_only", ">= 0"
      end
    RUBY

    scaffold = described_class.appraisal_scaffold_config(
      gemspec_content: gemspec_content,
      existing_config: {
        appraisal_matrix: {
          gems: {
            tier2: [
              {name: "omniauth"}
            ]
          }
        }
      },
      exclusions: ["erb"],
      freshness_ttl: 86_400
    )

    expect(scaffold.fetch("appraisal_matrix")).to include(
      "mode" => "semver",
      "freshness_ttl" => 86_400
    )
    expect(scaffold.dig("appraisal_matrix", "gems", "tier1")).to eq(
      [
        {"name" => "activerecord"},
        {"name" => "sequel"}
      ]
    )
    expect(scaffold.dig("appraisal_matrix", "gems", "tier2")).to eq([{"name" => "omniauth"}])

    expect(described_class.appraisal_matrix_has_versions?(
      "gems" => {
        "tier1" => [{"name" => "activerecord", "versions" => []}],
        "tier2" => [{"name" => "omniauth", "versions" => ["2.1"]}]
      }
    )).to be true
    expect(described_class.appraisal_matrix_fresh?({"resolved_at" => 100, "freshness_ttl" => 50}, now: 149)).to be true
    expect(described_class.appraisal_matrix_fresh?({"resolved_at" => 100, "freshness_ttl" => 50}, now: 150)).to be false
    expect(described_class.appraisal_time_ago(0, now: 90_000)).to eq("1d")
    expect(described_class.appraisal_finalize_versions(%w[7.1.0 7.1.1], include_versions: ["6.0.9"], exclude_versions: ["7.1.0"])).to eq(
      %w[6.0.9 7.1.1]
    )

    resolver = Class.new do
      def versions(gem_name, requirements: nil)
        case [gem_name, requirements]
        when ["activerecord", [">= 7.1", "< 7.2"]]
          [{number: "7.1.0"}, {number: "7.1.1"}]
        when ["omniauth", nil]
          [{number: "2.0.0"}, {number: "2.1.3"}]
        else
          []
        end
      end

      def minor_versions_by_major(gem_name, requirements: nil)
        case [gem_name, requirements]
        when ["sequel", nil]
          [{major: 5, minors: ["5.0", "5.9"]}]
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
      bucket_ranges: {"r3.1" => {floor: "3.0", ceiling: "3.1"}}
    )).to be false
  end

  it "plans stale flat appraisal gemfile cleanup paths" do
    stale_paths = described_class.appraisal_stale_gemfile_paths(
      existing_paths: [
        "gemfiles/kja-ar-7-1-r3.gemfile",
        "gemfiles/kja-ar-6-1-r2.gemfile",
        "gemfiles/manual.gemfile",
        "gemfiles/modular/activerecord/r3/v7.1.gemfile"
      ],
      current_entries: [
        {name: "kja-ar-7-1-r3"}
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
        "template/README.md.example" => <<~MARKDOWN
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
          "KJ_AUTHOR_ORCID" => "0000-0002-1825-0097"
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

  it "applies author email environment overrides to gemspec and destination config" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-author-email-env-sync-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["old@example.test"]
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML,
          tokens:
            author:
              name: Jane Q Public
              email: old@example.test
          templates:
            root: template
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
              - source: gem.gemspec
                target: example.gemspec
        YAML
        "template/.structuredmerge/kettle-jem.yml.example" => <<~YAML,
          tokens:
            author:
              name: Jane Q Public
              email: old@example.test
          templates:
            root: template
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
              - source: gem.gemspec
                target: example.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "Example gem"
            spec.authors = ["{KJ|AUTHOR:NAME}"]
            spec.email = ["{KJ|AUTHOR:EMAIL}"]
          end
        RUBY
      })

      apply = described_class.apply_project(
        root,
        env: {"KJ_AUTHOR_EMAIL" => "env@example.test"},
        run_options: {accept: true}
      )
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "example.gemspec" }
      config_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }

      expect(gemspec_report.fetch(:final_content)).to include('spec.email = ["env@example.test"]')
      expect(YAML.safe_load(config_report.fetch(:final_content)).dig("tokens", "author", "email")).to eq("env@example.test")
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.email = ["env@example.test"]')
      expect(YAML.safe_load_file(File.join(root, ".structuredmerge/kettle-jem.yml")).dig("tokens", "author", "email")).to eq("env@example.test")
    end
  end

  it "preserves existing multi-author gemspec metadata in packaged gemspec templates" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-multi-authors-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.description = "Example gem"
            spec.authors = ["First Author", "Second Author"]
            spec.email = ["authors@example.test"]
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - source: gem.gemspec
                target: example.gemspec
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "example.gemspec" }

      expect(gemspec_report.fetch(:final_content)).to include('spec.authors = ["First Author", "Second Author"]')
      expect(gemspec_report.dig(:metadata, :template_tokens)).to include(
        "KJ|AUTHOR:NAME" => "First Author",
        "KJ|AUTHOR:NAMES" => '["First Author", "Second Author"]'
      )
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.authors = ["First Author", "Second Author"]')
    end
  end

  it "derives author names from copyright holders when gemspec authors are absent" do
    author = described_class.send(
      :author_facts,
      {},
      {},
      copyright: {
        lines: [
          "Copyright (c) 2020 Ada Lovelace",
          "Copyright (c) 2021, 2023-2024 Grace Hopper"
        ]
      }
    )

    expect(described_class.send(:author_template_tokens, author)).to include(
      "KJ|AUTHOR:NAMES" => '["Ada Lovelace", "Grace Hopper"]'
    )
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
        "template/README.md.example" => <<~MARKDOWN
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
          "KJ_CB_USER" => "env-cb"
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

  it "honors supported funding platform template token config and environment overrides" do
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
              kofi: config-kofi
              paypal: "{KJ|FUNDING:PAYPAL}"
              buymeacoffee: config-bmac
              liberapay: config-liberapay
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Ko-fi: {KJ|FUNDING:KOFI}
          PayPal: {KJ|FUNDING:PAYPAL}
          BuyMeACoffee: {KJ|FUNDING:BUYMEACOFFEE}
          Liberapay: {KJ|FUNDING:LIBERAPAY}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_FUNDING_PAYPAL" => "env-paypal"
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        Ko-fi: config-kofi
        PayPal: env-paypal
        BuyMeACoffee: config-bmac
        Liberapay: config-liberapay
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|FUNDING:BUYMEACOFFEE" => "config-bmac",
        "KJ|FUNDING:KOFI" => "config-kofi",
        "KJ|FUNDING:LIBERAPAY" => "config-liberapay",
        "KJ|FUNDING:PAYPAL" => "env-paypal"
      )
    end
  end

  it "normalizes SECURITY.md supported version token from the gem version" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)

    {
      "0.2.0" => "0.latest",
      "2.5.7" => "2.5.latest"
    }.each do |gem_version, supported_version|
      Dir.mktmpdir("kettle-jem-security-version-token-slice", tmp_root) do |root|
        write_tree(root, {
          "example.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "example"
              spec.summary = "Example gem"
              spec.version = "#{gem_version}"
            end
          RUBY
          ".kettle-jem.yml" => <<~YAML,
            templates:
              root: template
              apply: true
              entries:
                - SECURITY.md
          YAML
          "template/SECURITY.md.example" => <<~MARKDOWN
            | Version  | Supported |
            |----------|-----------|
            | {KJ|SECURITY:SUPPORTED_VERSION} | ✅         |
          MARKDOWN
        })

        plan = described_class.plan_project(root, env: {})
        template_report = plan[:recipe_reports].find do |report|
          report.fetch(:recipe_name).start_with?("template_source_") &&
            report.fetch(:recipe_name).end_with?("_SECURITY_md")
        end
        expect(template_report.fetch(:final_content)).to include("| #{supported_version} | ✅")
        expect(template_report.dig(:metadata, :template_tokens)).to include(
          "KJ|SECURITY:SUPPORTED_VERSION" => supported_version
        )
      end
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
        "template/README.md.example" => <<~MARKDOWN
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
          "KJ_SOCIAL_LINKTREE" => "env-linktree"
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
        ".kettle-jem.yml" => <<~YAML
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
      expect(final_content).to include("- Required Notice: Copyright")
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
        ".kettle-jem.yml" => <<~YAML
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
        license_expression: "AGPL-3.0-only OR PolyForm-Small-Business-1.0.0"
      },
      license: {
        spdx: ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
      },
      funding: {
        urls: []
      }
    )

    expect(block).to include("| License | `AGPL-3.0-only` OR `PolyForm-Small-Business-1.0.0` |")
  end

  it "formats README metadata values as Markdown table cells" do
    block = described_class.readme_metadata_block(
      package: {
        name: "example",
        description: "First line\n  Second | line\r\nThird line",
        homepage_url: "https://example.test",
        source_url: "https://example.test/source",
        license_expression: "MIT"
      },
      license: {
        spdx: ["MIT"]
      },
      funding: {
        urls: []
      }
    )

    expect(block).to include("| Description | First line<br>Second \\| line<br>Third line |")
    expect(block).not_to include("First line\n")
  end

  it "renders optional FOSSA README badge tokens from configuration" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-fossa-readme-badge", tmp_root) do |root|
      disabled_style = described_class.readme_style_facts(
        root,
        {"readme" => {"badges" => {"fossa" => false}}},
        {spdx: ["MIT"]},
        repository: {slug: "galtzo-floss/example"}
      )
      enabled_style = described_class.readme_style_facts(
        root,
        {"readme" => {"badges" => {"fossa" => "git+github.com/pboling/flag_shih_tzu"}}},
        {spdx: ["MIT"]},
        repository: {slug: "galtzo-floss/flag_shih_tzu"}
      )

      expect(disabled_style[:fossa_project]).to be_nil
      tokens = described_class.readme_fossa_template_tokens(enabled_style)
      expect(tokens.fetch("KJ|README:FOSSA_BADGE")).to eq("[![FOSSA Status][🧪fossa-img]][🧪fossa]")
      expect(tokens.fetch("KJ|README:FOSSA_REFS")).to include("git%2Bgithub.com%2Fpboling%2Fflag_shih_tzu.svg?type=shield")
      expect(tokens.fetch("KJ|README:FOSSA_REFS")).to include("git%2Bgithub.com%2Fpboling%2Fflag_shih_tzu?ref=badge_shield")
    end
  end

  it "disables coverage integrations across README badges, upload steps, templates, and config cleanup" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-disabled-coverage-integrations", tmp_root) do |root|
      FileUtils.mkdir_p(File.join(root, ".github"))
      FileUtils.mkdir_p(File.join(root, ".qlty"))
      File.write(File.join(root, ".github/.codecov.yml"), "codecov:\n")
      File.write(File.join(root, ".coveralls.yml"), "service_name: github\n")
      File.write(File.join(root, ".qlty/qlty.toml"), "# qlty\n")

      config = {
        "integrations" => {
          "qlty" => false,
          "disabled" => %w[codecov coveralls]
        },
        "templates" => {
          "root" => "packaged",
          "apply" => true
        }
      }

      readme_style = described_class.readme_style_facts(
        root,
        config,
        {spdx: ["MIT"]},
        repository: {slug: "omniauth/omniauth-jwt2"}
      )
      expect(readme_style.fetch(:disabled_integrations)).to contain_exactly("codecov", "coveralls", "qlty")

      upload_steps = described_class.github_actions_coverage_steps(disabled_integrations: readme_style.fetch(:disabled_integrations))
      expect(upload_steps).not_to include("Upload coverage to Coveralls")
      expect(upload_steps).not_to include("Upload coverage to QLTY")
      expect(upload_steps).not_to include("Upload coverage to CodeCov")
      expect(upload_steps).to include("Code Coverage Summary Report")

      template_paths = described_class.template_source_preferences(root, config).map { |preference| preference.fetch(:target_path) }
      expect(template_paths).not_to include(".github/.codecov.yml", ".qlty/qlty.toml")

      cleanup_paths = described_class.inactive_packaged_template_cleanup_files(root, config).map { |cleanup| cleanup.fetch(:target_path) }
      expect(cleanup_paths).to include(".github/.codecov.yml", ".coveralls.yml", ".qlty/qlty.toml")
    end
  end

  it "keeps coverage integrations active when only README badges are disabled" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-only-coverage-badge-disable", tmp_root) do |root|
      config = {
        "readme" => {
          "badges" => {
            "disabled" => %w[qlty]
          }
        },
        "templates" => {
          "root" => "packaged",
          "apply" => true
        }
      }

      expect(described_class.disabled_coverage_integrations(config)).to be_empty

      readme_style = described_class.readme_style_facts(
        root,
        config,
        {spdx: ["MIT"]},
        repository: {slug: "omniauth/omniauth-jwt2"}
      )
      expect(readme_style.fetch(:disabled_integrations)).to contain_exactly("qlty")

      upload_steps = described_class.github_actions_coverage_steps(disabled_integrations: described_class.disabled_coverage_integrations(config))
      expect(upload_steps).to include("Upload coverage to Coveralls")
      expect(upload_steps).to include("Upload coverage to QLTY")
      expect(upload_steps).to include("Upload coverage to CodeCov")

      template_paths = described_class.template_source_preferences(root, config).map { |preference| preference.fetch(:target_path) }
      expect(template_paths).to include(".github/.codecov.yml", ".qlty/qlty.toml")
      expect(described_class.inactive_packaged_template_cleanup_files(root, config)).to be_empty
    end
  end

  it "supports partial coverage integration disablement" do
    config = {
      "integrations" => {
        "code_cov" => false,
        "qlty" => true,
        "coveralls" => "false"
      }
    }

    expect(described_class.disabled_coverage_integrations(config)).to contain_exactly("codecov", "coveralls")

    upload_steps = described_class.github_actions_coverage_steps(disabled_integrations: described_class.disabled_coverage_integrations(config))
    expect(upload_steps).not_to include("Upload coverage to Coveralls")
    expect(upload_steps).not_to include("Upload coverage to CodeCov")
    expect(upload_steps).to include("Upload coverage to QLTY")

    workflow = <<~YAML
      jobs:
        coverage:
          steps:
            - name: Existing
              run: true
    YAML
    updated = described_class.append_github_actions_coverage_steps(workflow, disabled_integrations: described_class.disabled_coverage_integrations(config))
    expect(updated).to include("Upload coverage to QLTY")
    expect(updated).not_to include("Upload coverage to Coveralls")
    expect(described_class.append_github_actions_coverage_steps(updated, disabled_integrations: [])).to eq(updated)

    workflow_without_steps = <<~YAML
      jobs:
        coverage:
          runs-on: ubuntu-latest
    YAML
    expect(described_class.append_github_actions_coverage_steps(workflow_without_steps, disabled_integrations: [])).to eq(workflow_without_steps)
  end

  it "disables SkyWalking Eyes from boolean keys and disabled lists" do
    expect(described_class.disabled_integrations(
      {
        "integrations" => {
          "skywalking_eyes" => false
        }
      },
      license: {spdx: ["MIT"]}
    )).to include("skywalking-eyes")

    expect(described_class.disabled_integrations(
      {
        "integrations" => {
          "disabled" => %w[license-eye]
        }
      },
      license: {spdx: ["MIT"]}
    )).to include("skywalking-eyes")
  end

  it "defaults SkyWalking Eyes off unless a compatible license is configured" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-skywalking-eyes-default-disable", tmp_root) do |root|
      FileUtils.mkdir_p(File.join(root, ".github/workflows"))
      File.write(File.join(root, ".licenserc.yaml"), "dependency:\n")
      File.write(File.join(root, ".github/workflows/license-eye.yml"), "name: Apache SkyWalking Eyes\n")
      config = {
        "licenses" => %w[AGPL-3.0-only],
        "templates" => {
          "root" => "packaged",
          "apply" => true
        }
      }
      license = {spdx: ["AGPL-3.0-only"]}
      template_config = described_class.template_runtime_config(config, {}, license: license)

      expect(described_class.disabled_integrations(config, license: license)).to include("skywalking-eyes")

      readme_style = described_class.readme_style_facts(
        root,
        config,
        license,
        repository: {slug: "example/example"}
      )
      expect(readme_style.fetch(:disabled_integrations)).to include("skywalking-eyes")

      template_paths = described_class.template_source_preferences(root, template_config).map { |preference| preference.fetch(:target_path) }
      expect(template_paths).not_to include(".licenserc.yaml", ".github/workflows/license-eye.yml")

      cleanup_paths = described_class.inactive_packaged_template_cleanup_files(root, template_config).map { |cleanup| cleanup.fetch(:target_path) }
      expect(cleanup_paths).to include(".licenserc.yaml")

      workflow_cleanup_paths = described_class.inactive_packaged_workflow_cleanup_files(root, template_config)
      expect(workflow_cleanup_paths).to include(".github/workflows/license-eye.yml")
    end
  end

  it "keeps SkyWalking Eyes enabled for MIT licenses and explicit opt-in" do
    mit_config = {
      "templates" => {
        "root" => "packaged",
        "apply" => true
      }
    }
    non_mit_opt_in_config = {
      "licenses" => %w[AGPL-3.0-only],
      "integrations" => {
        "skywalking-eyes" => true
      },
      "templates" => {
        "root" => "packaged",
        "apply" => true
      }
    }

    expect(described_class.disabled_integrations(mit_config, license: {spdx: ["MIT"]})).not_to include("skywalking-eyes")
    expect(described_class.disabled_integrations(non_mit_opt_in_config, license: {spdx: ["AGPL-3.0-only"]})).not_to include("skywalking-eyes")
    expect(described_class.license_eye_workflow_badge(["AGPL-3.0-only"], non_mit_opt_in_config)).to include(
      "Apache SkyWalking Eyes License Compatibility Check"
    )
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
      license: {spdx: ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]}
    }

    output = described_class.merge_gemspec_template_source(template, destination, facts: facts)

    expect(output).to include('spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]')
  end

  it "escapes and de-duplicates emoji in gemspec summary and description tokens" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-description-token", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "🔍️ Find out what your Ruby gems are worth"
            spec.description = '🔍️ Example uses repeatable scenarios called "appraisals."'
            spec.homepage = "https://github.com/example/example"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: 🔍️
          files:
            example.gemspec:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "{KJ|PROJECT_EMOJI} {KJ|GEMSPEC_PACKAGE_SUMMARY}"
            spec.description = "{KJ|PROJECT_EMOJI} {KJ|GEMSPEC_PACKAGE_DESCRIPTION}"
            spec.homepage = "https://github.com/example/example"
          end
        RUBY
      })

      described_class.apply_project(root, env: {})
      gemspec_path = File.join(root, "example.gemspec")
      gemspec = File.read(gemspec_path)

      expect(gemspec).to include('spec.summary = "🔍️ Find out what your Ruby gems are worth"')
      expect(gemspec).to include('spec.description = "🔍️ Example uses repeatable scenarios called \"appraisals.\""')
      expect(gemspec).not_to include("🔍️ 🔍️")
      expect(Gem::Specification.load(gemspec_path)).not_to be_nil
    end
  end

  it "refreshes README metadata during template-source README application" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-metadata-order", tmp_root) do |root|
      metadata_block = described_class.readme_metadata_block(
        package: {
          name: "example",
          description: "Example gem",
          homepage_url: "https://example.test",
          source_url: "https://github.com/structuredmerge/structuredmerge-ruby",
          license_expression: "MIT"
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
            spec.metadata["source_code_uri"] = "https://github.com/acme/example/tree/v1.2.3"
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
        "template/README.md.example" => "# {KJ|NAMESPACE}\n\nTemplate body.\n"
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true})
      first_readme = File.read(File.join(root, "README.md"))
      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true})

      expect(first_readme).to include("<!-- kettle-jem:metadata:start -->")
      expect(first_readme).to include("| Package | example |")
      expect(first_readme).to include("| Source | https://github.com/acme/example/tree/v1.2.3 |")
      expect(first_readme).not_to include("https://github.com/structuredmerge/structuredmerge-ruby")
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
        "Big-Time-Public-License.md" => "obsolete Big Time license\n"
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
        "README.md" => <<~MARKDOWN
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
        "GIT_COMMITTER_DATE" => "#{Time.now.utc.year}-01-02T00:00:00Z"
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
      expect(license_report.fetch(:final_content)).to include("- #{expected_line}")
      expect(readme_report.fetch(:final_content)).to include("Copyright holders")
      expect(readme_report.fetch(:final_content)).to include("- #{expected_line}")
      expect(license_report.dig(:metadata, :template_tokens, "KJ|LICENSE_COPYRIGHT_NOTICE")).to include("- #{expected_line}")
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
        "template/README.md.example" => "# Example\n\n## 📄 License\n\n{KJ|README:COPYRIGHT_NOTICE}\n"
      })

      plan = described_class.plan_project(root, env: {})
      license_report = plan[:recipe_reports].find { |report| report.fetch(:relative_path) == "LICENSE.md" }
      readme_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "template_source_application_README_md" }
      expected_line = "Required Notice: Copyright (c) #{Time.now.utc.year} Peter H. Boling"

      expect(plan.fetch(:facts)).not_to have_key(:copyright)
      expect(license_report.fetch(:final_content)).to include("## Copyright Notice")
      expect(license_report.fetch(:final_content)).to include("- #{expected_line}")
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
        "template/README.md.example" => <<~MARKDOWN
          Gem shield: {KJ|GEM_SHIELD}
          Major: {KJ|GEM_MAJOR}
          GitHub org: {KJ|GH_ORG}
          Namespace shield: {KJ|NAMESPACE_SHIELD}
          Namespace badge: https://img.shields.io/badge/namespace-{KJ|NAMESPACE_SHIELD}-3C2D2D.svg
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
          "KJ_HOMEPAGE_URI" => "https://homepage.example.test"
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Gem shield: example--gem")
      expect(final_content).to include("Major: 2")
      expect(final_content).to include("GitHub org: acme")
      expect(final_content).to include("Namespace shield: Example::Gem")
      expect(final_content).to include("Namespace badge: https://img.shields.io/badge/namespace-Example::Gem-3C2D2D.svg")
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
        "KJ|NAMESPACE_SHIELD" => "Example::Gem",
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
        "template/README.md.example" => "YARD: {KJ|YARD_HOST}\nHomepage URI: {KJ|HOMEPAGE_URI}\n"
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

  it "syncs ENV-backed values back into kettle config during templating" do
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
        ".structuredmerge/kettle-jem.yml" => <<~YAML
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
              - .structuredmerge/kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(
        root,
        env: {
          "KJ_MIN_DIVERGENCE_THRESHOLD" => "12",
          "KJ_YARD_HOST" => "docs.env.test",
          "KJ_HOMEPAGE_URI" => "https://homepage.env.test",
          "KJ_GH_USER" => "env-user"
        },
        run_options: {skip_commit: true}
      )
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == described_class::KETTLE_CONFIG_PATH }
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
      expect(File.read(File.join(root, described_class::KETTLE_CONFIG_PATH))).to eq(report.fetch(:final_content))
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
        ".kettle-jem.yml" => <<~YAML
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
              - .structuredmerge/kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.dig("readme", "top_logos")).to eq("org")
      expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
      expect(config.fetch("readme")).not_to have_key("top_logo_mode")
      expect(report.fetch(:final_content)).not_to include("top_logo_mode:")
      expect(report.fetch(:final_content)).to include("# README top logos.")
      expect(report.fetch(:final_content)).to include("# top_logos render above the title; h2_synopsis_logos render inline with the Synopsis H2.")
      expect(report.fetch(:final_content)).to include("# Supported values: related-org, ruby, org, project")
      expect(File.read(File.join(root, ".structuredmerge/kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "migrates legacy-only README top logo mode config" do
    content = <<~YAML
      readme:
        top_logo_mode: org
    YAML

    migrated = described_class.send(:sync_kettle_config_env_overrides, content, {})
    config = YAML.safe_load(migrated)

    expect(config.dig("readme", "top_logos")).to eq("org")
    expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
    expect(config.fetch("readme")).not_to have_key("top_logo_mode")
  end

  it "migrates comma-separated legacy README top logo mode config" do
    content = <<~YAML
      readme:
        top_logo_mode: org, project
    YAML

    migrated = described_class.send(:sync_kettle_config_env_overrides, content, {})
    config = YAML.safe_load(migrated)

    expect(config.dig("readme", "top_logos")).to eq("org,project")
    expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
    expect(config.fetch("readme")).not_to have_key("top_logo_mode")
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
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          defaults:
            preference: destination
            add_template_only_nodes: true
          project_emoji: "🫖"
          repository:
            topology: standalone
          readme:
            top_logos: org,project
            h2_synopsis_logos: related-org,ruby
          templates:
            root: packaged
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.fetch("project_emoji")).to eq("🫖")
      expect(config.dig("repository", "topology")).to eq("standalone")
      expect(config.dig("readme", "top_logos")).to eq("org,project")
      expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
      expect(File.read(File.join(root, ".structuredmerge/kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "normalizes combined top logo config when Synopsis H2 logos already exist" do
    content = <<~YAML
      readme:
        top_logos: related-org,ruby,org
        h2_synopsis_logos: related-org,ruby
    YAML

    migrated = described_class.send(:sync_kettle_config_env_overrides, content, {})
    config = YAML.safe_load(migrated)

    expect(config.dig("readme", "top_logos")).to eq("org")
    expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
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
        "template/README.md.example" => <<~MARKDOWN
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

  it "prefers git origin over stale generated gemspec homepage metadata" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-stale-homepage-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/pboling/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
              - README.md
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "{KJ|README:GH_REPOSITORY_URL}"
          end
        RUBY
        "template/README.md.example" => <<~MARKDOWN
          Source: {KJ|GH_ORG}
          GitHub user: {KJ|GH:USER}
          Repository: {KJ|README:GH_REPOSITORY_URL}
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:rubocop-lts/example.git")).to be(true)

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(plan.dig(:facts, :package, :source_url)).to eq("https://github.com/rubocop-lts/example")
      expect(plan.dig(:facts, :package, :homepage_url)).to eq("https://github.com/rubocop-lts/example")
      expect(template_report.fetch(:final_content)).to include("Source: rubocop-lts")
      expect(template_report.fetch(:final_content)).to include("GitHub user: rubocop-lts")
      expect(template_report.fetch(:final_content)).to include("Repository: https://github.com/rubocop-lts/example")

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to include("example.gemspec")
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.homepage = "https://github.com/rubocop-lts/example"')
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
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
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
      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="acme Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/avatar-128px.svg" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme/example-gem"><img alt="example-gem Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/example-gem/avatar-128px.svg" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://discord.gg/3qme4XHNKN"><img alt="Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).not_to include("[🖼️acme-example-gem]:")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|README:TOP_LOGO_REFS" => "",
        "KJ|README:TOP_LOGO_ROW" => a_string_including("example-gem Logo by Aboling0"),
        "KJ|README:H2_SYNOPSIS_LOGO_ROW" => a_string_including("ruby-lang Logo")
      )
    end
  end

  it "allows README logo options to override rendered widths" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-logo-width-token-slice", tmp_root) do |root|
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
            top_logos: org|96px
            h2_synopsis_logos: ruby|12%
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)

      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="acme Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/avatar-128px.svg" width="96px" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="12%" align="right"/></a>))
    end
  end

  it "keeps generated Synopsis H2 logo HTML when normalizing existing README headings and prunes stale logo refs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-synopsis-logo-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          readme:
            top_logos: org
            h2_synopsis_logos: related-org,ruby
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          [🖼️galtzo-floss]: https://discord.gg/3qme4XHNKN
          [🖼️ruby-lang]: https://ruby-toolbox.com

          # Old Title

          ## 🌻 Synopsis

          Existing synopsis.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          {KJ|README:TOP_LOGO_ROW}

          {KJ|README:TOP_LOGO_REFS}

          # {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}

          ## 🌻 Synopsis {KJ|README:H2_SYNOPSIS_LOGO_ROW}
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "README.md" }
      final_content = report.fetch(:final_content)

      expect(final_content).to include("# 🫖 Example::Gem\n")
      expect(final_content).to include("## 🌻 Synopsis <a href=\"https://discord.gg/3qme4XHNKN\"")
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo,))
      expect(final_content).not_to include("[🖼️galtzo-floss]:")
      expect(final_content).not_to include("[🖼️ruby-lang]:")
      expect(final_content).not_to include("\n\n\n")
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
        "template/README.md.example" => <<~MARKDOWN
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
          "KJ_REPOSITORY_TOPOLOGY" => "monorepo-subproject"
        }
      )
      expect(plan.dig(:facts, :template_profile)).to eq("full")
      expect(plan.dig(:facts, :repository, :mode)).to eq("monorepo_subproject")
      expect(plan.dig(:facts, :readme_logo, :top_logo_row)).to include("structuredmerge/structuredmerge-ruby/kettle-jem/avatar-128px.svg")
      expect(plan.dig(:facts, :readme_logo, :top_logo_refs).to_s).to eq("")
    end
  end

  it "does not invent a gems path for a monorepo topology when the project is the git root" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-root-monorepo-topology-slice", tmp_root) do |root|
      write_tree(root, {
        "nomono.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "nomono"
            spec.summary = "Bundler path helper"
            spec.metadata["source_code_uri"] = "https://github.com/kettle-dev/nomono"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          repository:
            topology: monorepo-subproject
          templates:
            root: template
            apply: true
            profile: full
            entries:
              - README.md
        YAML
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:kettle-dev/nomono.git")).to be(true)

      repository = described_class.send(
        :repository_facts,
        root,
        "https://github.com/kettle-dev/nomono",
        package_name: "nomono",
        repository_topology: "monorepo-subproject"
      )
      tokens = described_class.send(:readme_url_template_tokens, repository, "nomono", "kettle-rb")

      expect(repository[:mode]).to eq("monorepo_subproject")
      expect(repository).not_to have_key(:package_path)
      expect(tokens.fetch("KJ|README:GL_PACKAGE_SOURCE_URL")).to eq("https://gitlab.com/kettle-rb/nomono")
      expect(tokens.fetch("KJ|README:CB_PACKAGE_SOURCE_URL")).to eq("https://codeberg.org/kettle-rb/nomono")
      expect(tokens.fetch("KJ|README:GH_PACKAGE_SOURCE_URL")).to eq("https://github.com/kettle-dev/nomono")
      expect(tokens.values_at(
        "KJ|README:GL_PACKAGE_SOURCE_URL",
        "KJ|README:CB_PACKAGE_SOURCE_URL",
        "KJ|README:GH_PACKAGE_SOURCE_URL"
      ).join("\n")).not_to include("/gems/nomono")
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
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include(%(<a href="https://discord.gg/3qme4XHNKN"><img alt="Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="acme Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/avatar-128px.svg" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme/example-gem"><img alt="example-gem Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/example-gem/avatar-128px.svg" width="12%" align="right"/></a>))
      expect(final_content).not_to include("[🖼️galtzo-floss]:")
      expect(final_content).not_to include("[🖼️acme-example-gem]:")
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
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).not_to include("[🖼️galtzo-floss]:")
      expect(final_content).not_to include("[🖼️galtzo-floss]: https://github.com/galtzo-floss")
      expect(final_content.scan("galtzo-floss/avatar-128px.svg").length).to eq(2)
      expect(final_content).to include(%(<a href="https://github.com/galtzo-floss/turbo_tests2"><img alt="turbo_tests2 Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/turbo_tests2/avatar-128px.svg" width="12%" align="right"/></a>))
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
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
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
        "template/README.md.example" => <<~MARKDOWN
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
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="Ruby language Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="Acme org Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/avatar-128px.svg" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://logos.galtzo.com/assets/images/tree-sitter/tree-sitter/"><img alt="Tree-sitter project Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/tree-sitter/tree-sitter/avatar-128px.svg" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme/example-gem"><img alt="Ignored fourth Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/ignored/avatar-128px.svg" align="right"/></a>))
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
        ".kettle-jem.yml" => <<~YAML
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
        "Style tasks run on the latest Ruby"
      )
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-lts", "~> 22.3", ">= 22.3.0"')
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-lts-rspec", "~> 1.0", ">= 1.0.3"')
      expect(template_report.fetch(:final_content)).not_to include('gem "rubocop-rspec", "~> 3.6"')
      expect(template_report.fetch(:final_content)).to include('gem "appraisal2-rubocop", "~> 0.2", ">= 0.2.2", require: false')
      expect(template_report.fetch(:final_content)).to include('gem "rubocop-ruby3_1", "~> 3.0", ">= 3.0.2"')
      expect(template_report.fetch(:final_content)).to include(
        "declared_gems = instance_variable_get(:@dependencies).to_a.map(&:name)"
      )
      expect(template_report.fetch(:final_content)).to include(
        'gem "rubocop-ruby3_1", "~> 3.0", ">= 3.0.2" unless declared_gems.include?("rubocop-ruby3_1")'
      )
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|RUBOCOP_TARGET_RUBY" => "3.1",
        "KJ|RUBOCOP_LTS_CONSTRAINT" => "\"~> 22.3\", \">= 22.3.0\"",
        "KJ|RUBOCOP_RUBY_CONSTRAINT" => "\"~> 3.0\", \">= 3.0.2\"",
        "KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby3_1"
      )
    end
  end

  it "renders README dev and test stack table with self-exclusion" do
    example_table = described_class.send(:readme_dev_test_stack_table, "example")
    turbo_table = described_class.send(:readme_dev_test_stack_table, "turbo_tests2")
    coverage_table = described_class.send(:readme_dev_test_stack_table, "kettle-soup-cover")

    expect(example_table).to start_with("<details markdown=\"1\">\n<summary>How kettle-dev manages complexity in tests</summary>\n\n")
    expect(example_table).to end_with("\n</details>")
    expect(example_table).to include("[appraisal2](https://bestgems.org/gems/appraisal2)")
    expect(example_table).to include("[GitHub](https://github.com/appraisal-rb/appraisal2)")
    expect(example_table).to include("https://img.shields.io/gem/rd/appraisal2.svg?style=flat-square")
    expect(example_table).to include("[kettle-dev](https://bestgems.org/gems/kettle-dev)")
    expect(example_table).to include("[GitHub](https://github.com/kettle-dev/kettle-dev)")
    expect(example_table).to include("[kettle-jem](https://bestgems.org/gems/kettle-jem)")
    expect(example_table).to include("[GitHub](https://github.com/kettle-dev/kettle-jem)")
    expect(example_table).to include("Appraisals & CI workflow templates")
    expect(example_table).to include("[kettle-soup-cover](https://bestgems.org/gems/kettle-soup-cover)")
    expect(example_table).to include("[GitHub](https://github.com/kettle-dev/kettle-soup-cover)")
    expect(example_table).to include("[kettle-test](https://bestgems.org/gems/kettle-test)")
    expect(example_table).to include("[GitHub](https://github.com/kettle-dev/kettle-test)")
    expect(example_table).to include("[rubocop-lts](https://bestgems.org/gems/rubocop-lts)")
    expect(example_table).to include("[turbo_tests2](https://bestgems.org/gems/turbo_tests2)")
    expect(example_table.index("[appraisal2]")).to be < example_table.index("[appraisal2-rubocop]")
    expect(example_table.index("[appraisal2-rubocop]")).to be < example_table.index("[kettle-dev]")
    expect(example_table.index("[kettle-dev]")).to be < example_table.index("[kettle-jem]")
    expect(example_table.index("[kettle-jem]")).to be < example_table.index("[kettle-soup-cover]")
    expect(example_table.index("[kettle-soup-cover]")).to be < example_table.index("[kettle-test]")
    expect(example_table.index("[kettle-test]")).to be < example_table.index("[rubocop-lts]")
    expect(example_table.index("[rubocop-lts]")).to be < example_table.index("[turbo_tests2]")
    expect(turbo_table).not_to include("[turbo_tests2](https://bestgems.org/gems/turbo_tests2)")
    expect(turbo_table).to include("[appraisal2](https://bestgems.org/gems/appraisal2)")
    expect(turbo_table).to include("[kettle-test](https://bestgems.org/gems/kettle-test)")
    expect(coverage_table).not_to include("[kettle-soup-cover](https://bestgems.org/gems/kettle-soup-cover)")
    expect(coverage_table).to include("[kettle-test](https://bestgems.org/gems/kettle-test)")
    kettle_dev_table = described_class.send(:readme_dev_test_stack_table, "kettle-dev")
    expect(kettle_dev_table).not_to include("[kettle-dev](https://bestgems.org/gems/kettle-dev)")
    expect(kettle_dev_table).to include("[kettle-test](https://bestgems.org/gems/kettle-test)")
    kettle_jem_table = described_class.send(:readme_dev_test_stack_table, "kettle-jem")
    expect(kettle_jem_table).not_to include("[kettle-jem](https://bestgems.org/gems/kettle-jem)")
    expect(kettle_jem_table).to include("[kettle-test](https://bestgems.org/gems/kettle-test)")
  end

  it "keeps packaged Ruby templates aligned with generated RuboCop Gradual baselines" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ruby-style-slice", tmp_root) do |root|
      default_style = described_class.send(:ruby_style_facts, root)
      default_tokens = described_class.send(:rubocop_template_tokens, "2.2", ruby_style: default_style)

      expect(default_tokens).to include(
        "KJ|RUBY_STYLE:TRAILING_ARRAY_COMMA" => "",
        "KJ|RAKE:FAMILY_GEM_DIRS_ENUMERATION" => include(
          "    Dir.glob(File.join(__dir__, \"gems\", \"*\", \"*.gemspec\"))\n" \
            "      .map { |path| File.dirname(path) }\n" \
            "      .uniq\n" \
            "      .sort_by { |path| File.basename(path) }"
        )
      )

      File.write(File.join(root, ".rubocop.yml"), <<~YAML)
        Layout/DotPosition:
          EnforcedStyle: trailing

        Style/TrailingCommaInArrayLiteral:
          EnforcedStyleForMultiline: comma
      YAML
      configured_style = described_class.send(:ruby_style_facts, root)
      configured_tokens = described_class.send(:rubocop_template_tokens, "2.2", ruby_style: configured_style)

      expect(configured_tokens).to include(
        "KJ|RUBY_STYLE:TRAILING_ARRAY_COMMA" => ",",
        "KJ|RAKE:FAMILY_GEM_DIRS_ENUMERATION" => include(
          "    Dir.glob(File.join(__dir__, \"gems\", \"*\", \"*.gemspec\")).\n" \
            "      map { |path| File.dirname(path) }.\n" \
            "      uniq.\n" \
            "      sort_by { |path| File.basename(path) }"
        )
      )
    end
  end

  it "wires Appraisal2 RuboCop as a generator plugin without generated appraisal leakage" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisal-rubocop-plugin-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.4"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - Appraisals
              - Appraisal.root.gemfile
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      appraisals_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == "Appraisals"
      end
      appraisal_root_report = plan[:recipe_reports].find do |report|
        report.fetch(:relative_path) == "Appraisal.root.gemfile"
      end

      expect(appraisals_report.fetch(:final_content)).to include(
        'plugin "appraisal2-rubocop", require: "appraisal2/rubocop", optional: true'
      )
      expect(appraisals_report.fetch(:final_content)).not_to include("respond_to?(:plugin)")
      expect(appraisals_report.fetch(:final_content)).not_to include('require "appraisal2/rubocop"')
      expect(appraisal_root_report.fetch(:final_content)).to include(
        'if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2")'
      )
      expect(appraisal_root_report.fetch(:final_content)).to include(
        "if respond_to?(:generator_only)"
      )
      expect(appraisal_root_report.fetch(:final_content)).to include(
        "generator_only do"
      )
      expect(appraisal_root_report.fetch(:final_content)).to include(
        'eval_gemfile "gemfiles/modular/style.gemfile"'
      )
      expect(appraisal_root_report.fetch(:final_content)).not_to include('self.class.name.start_with?("Appraisal::")')
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
        "template/README.md.example" => <<~MARKDOWN
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
        ".kettle-jem.yml" => <<~YAML
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
        "  - removed.md.example"
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
        "template/README.md.example" => "# Example\n"
      })
      calls = []
      runner = lambda do |project_root:, template_dir:|
        calls << {project_root: project_root, template_dir: template_dir}
        {
          warning_count: 1,
          json_path: File.join(project_root, "tmp", "kettle-jem", "dup-check.json"),
          lock_path: File.join(project_root, ".kettle-drift.lock"),
          exit_code: 1
        }
      end

      apply = described_class.apply_project(root, env: {}, run_options: {duplicate_drift_runner: runner})

      expect(calls).to eq([{project_root: root, template_dir: File.join(root, "template")}])
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
        "example.gemspec" => <<~RUBY
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
        "removed.txt" => "removed\n"
      })
      write_tree(after, {
        "same.txt" => "same\n",
        "changed.txt" => "after\n",
        "added.txt" => "added\n"
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
          loaded: true
        },
        merge_gems: [
          {
            name: "ast-merge",
            version: "2.0.0",
            path: File.join(root, "ast-merge"),
            local_path: true,
            loaded: true
          },
          {
            name: "json-merge",
            version: nil,
            path: nil,
            local_path: false,
            loaded: false
          }
        ]
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
        {changed: true, metadata: {delete_file: true, destination_existed: true}}
      ],
      diagnostics: [
        {kind: "plugin_file_change", path: "PLUGIN.md", action: "replace"}
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
        "README.md" => "# Example\n\nDestination README.\n"
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
            "recipe:template_source_application_README_md" => "keep"
          }
        }
      )
      answered_decision = answered_apply.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(answered_apply.fetch(:decision_policy)).to include(
        mode: "interactive",
        prompt_answers: {
          "recipe:readme_metadata" => "keep",
          "recipe:template_source_application_README_md" => "keep"
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
        "example.gemspec" => <<~RUBY
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
        "KETTLE_JEM_SKIP_COMMIT" => "true"
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
        ".kettle-jem.yml" => <<~YAML
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
      expect(plan_lifecycle.fetch(:active_runner_phases)).to be_empty
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
      apply_lifecycle = apply.fetch(:diagnostics).reverse.find { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }
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

  it "keeps direct sibling runtime dependencies available during lockfile normalization" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-direct-sibling-lock-env", tmp_root) do |workspace|
      root = File.join(workspace, "adapter")
      sibling = File.join(workspace, "shared-core")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "shared-core.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "shared-core"
            spec.version = "0.1.0"
            spec.summary = "Shared core"
          end
        RUBY
      })
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            ruby

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/rubythems/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/rubythems/adapter"
            spec.add_dependency "shared-core", "= 0.1.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
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

      Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {"K_JEM_TEMPLATING" => "true"},
        run_options: {only: "bin/setup", skip_commit: true},
        command_runner: command_runner
      )

      lock_command = commands.find { |entry| entry.fetch(:command) == %w[bundle update] }
      expect(lock_command).not_to be_nil
      expect(lock_command.fetch(:env)).to include(
        "K_JEM_TEMPLATING" => "false",
        "RUBYTHEMS_DEV" => workspace
      )
    end
  end

  it "generates templating-aware main Gemfile nomono wiring for direct sibling runtime dependencies" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-direct-sibling-wiring", tmp_root) do |workspace|
      root = File.join(workspace, "adapter")
      sibling = File.join(workspace, "shared-core")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "shared-core.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "shared-core"
            spec.version = "0.1.0"
            spec.summary = "Shared core"
          end
        RUBY
      })
      write_tree(root, {
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/rubythems/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/rubythems/adapter"
            spec.add_dependency "shared-core", "= 0.1.0"
            spec.add_dependency "version_gem", ">= 1"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))
      direct_block = gemfile
        .split("# Direct sibling dependencies", 2).last.to_s
        .split("# Templating", 2).first.to_s

      expect(report.fetch(:changed_files)).to include("Gemfile")
      expect(direct_block).to include("direct_sibling_gems = %w[")
      expect(direct_block).to include("shared-core")
      expect(direct_block).not_to include("version_gem")
      expect(direct_block).to include(
        'direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?'
      )
      expect(gemfile).to include('nomono_requirements = ["~> 1.0", ">= 1.0.6"]')
      expect(direct_block).to include("nomono_activation_requirements = nomono_requirements")
      expect(direct_block).to include('nomono_lockfile = File.expand_path("Gemfile.lock", __dir__)')
      expect(direct_block).to include("Bundler::LockfileParser")
      expect(direct_block).to include('Kernel.send(:gem, "nomono", *nomono_activation_requirements)')
      expect(direct_block).to include('require "nomono/bundler"')
      expect(direct_block).not_to include('Gem::Specification.find_all_by_name("nomono")')
      expect(direct_block).not_to include(
        'unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?'
      )
      expect(direct_block).to include('ENV["RUBYTHEMS_DEV"] = File.expand_path("..", __dir__)')
      expect(direct_block).to include('prefix: "RUBYTHEMS"')
      expect(direct_block).to include('path_env: "RUBYTHEMS_DEV"')
      expect(direct_block).to include('root: ["src", "my", "rubythems"]')
      expect(File.read(File.join(root, "Gemfile"))).to eq(gemfile)
    end
  end
end
