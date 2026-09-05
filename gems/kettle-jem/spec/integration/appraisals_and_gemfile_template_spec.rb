# frozen_string_literal: true

RSpec.describe Kettle::Jem, "Appraisals and Gemfile templating" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "applies Appraisals template policy with self-dependency and minimum Ruby pruning" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
      fingerprint_payload = described_class.template_input_fingerprint_payload(root, appraisals_report)

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
      expect(fingerprint_payload).to include(appraisals_template_policy_fingerprint_version: 2)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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

  it "removes legacy standard library gem declarations when an appraisal uses the managed aggregate" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-appraisals-managed-stdlibs", tmp_root) do |root|
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
          appraise "coverage" do
            # Legacy declarations conflict with modular/x_std_libs on Ruby 4.
            gem "mutex_m", "~> 0.2"
            gem "stringio", "~> 3.0"
            gem "benchmark", "~> 0.4", ">= 0.4.1"
            gem "simplecov"
          end
        RUBY
        "template/Appraisals.example" => <<~RUBY
          appraise "coverage" do
            eval_gemfile "modular/coverage.gemfile"
            eval_gemfile "modular/x_std_libs.gemfile"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Appraisals" }
      appraisals_content = report.fetch(:final_content)

      expect(appraisals_content).to include('eval_gemfile "modular/x_std_libs.gemfile"')
      expect(appraisals_content).to include('gem "simplecov"')
      expect(appraisals_content).not_to include('gem "mutex_m"')
      expect(appraisals_content).not_to include('gem "stringio"')
      expect(appraisals_content).not_to include('gem "benchmark"')
    end
  end

  it "collapses framework appraisals onto standard appraisals without overwriting kept framework gemfiles" do
    tmp_root = File.expand_path("../tmp", __dir__)
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

  it "replaces framework appraisal blocks when configured support gemfiles are removed" do
    content = <<~RUBY
      appraise "rdoc-6-11" do
        eval_gemfile "modular/rdoc/v6_11.gemfile"
        eval_gemfile "modular/documentation.gemfile"
        eval_gemfile "modular/x_std_libs.gemfile"
      end

      appraise "current" do
        eval_gemfile "modular/x_std_libs.gemfile"
      end
    RUBY
    facts = {
      ci: {
        framework_matrix: {
          appraisals: [{
            name: "rdoc-6-11",
            eval_gemfiles: ["modular/rdoc/v6_11.gemfile", "modular/x_std_libs.gemfile"]
          }]
        }
      }
    }

    output = described_class.send(:merge_framework_matrix_appraisals, content, facts)

    expect(appraisals_eval_gemfile_paths(output, "rdoc-6-11")).to contain_exactly(
      "modular/rdoc/v6_11.gemfile",
      "modular/x_std_libs.gemfile"
    )
    expect(appraisals_eval_gemfile_paths(output, "current")).to contain_exactly("modular/x_std_libs.gemfile")
  end

  it "adds configured support gemfiles to standard test Appraisal blocks" do
    tmp_root = File.expand_path("../tmp", __dir__)
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

  it "manages the default local test bundle separately from Appraisals" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-default-test-bundle", tmp_root) do |root|
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
          test_bundle:
            gemfiles:
              - path: gemfiles/rails_7_2.gemfile
                replaces:
                  - combustion
                  - actionmailer
                  - railties
            gems:
              - name: activerecord
                requirement: "~> 7.2"
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
        YAML
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"

          gemspec

          gem "combustion", "~> 1.5"
          gem "actionmailer", "~> 7.2.2"
          gem "railties", "~> 7.2.2"
          gem "activerecord", "~> 7.1"

          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
        "template/Gemfile.example" => <<~RUBY
          source "https://gem.coop"

          gemspec

          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      content = apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "Gemfile" }.fetch(:final_content)

      expect(content).to include("# Default local test bundle")
      expect(content).to include('eval_gemfile "gemfiles/rails_7_2.gemfile"')
      expect(content).to include('gem "activerecord", "~> 7.2"')
      expect(content).not_to include('gem "combustion"')
      expect(content).not_to include('gem "actionmailer"')
      expect(content).not_to include('gem "railties"')
      expect(content).not_to include('gem "activerecord", "~> 7.1"')
    end
  end

  it "uses one framework-matrix default version for the default local test bundle" do
    config = {
      "workflows" => {
        "preset" => "framework",
        "framework_matrix" => {
          "dimension" => "rails",
          "gem" => "rails",
          "gemfile_pattern" => "rails_{version}.gemfile",
          "versions" => [
            {"label" => "7.2", "slug" => "7_2", "requirement" => "~> 7.2.2", "default" => true}
          ]
        }
      }
    }

    framework_matrix = described_class.send(:github_actions_framework_matrix, config)
    bundle = described_class.send(:default_test_bundle_config, config, framework_matrix)

    expect(bundle).to include(gemfiles: ["gemfiles/rails_7_2.gemfile"], gems: [], managed_gems: [])
  end

  it "does not add broad standard support gemfiles to collapsed framework appraisals" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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

  it "preserves configured per-engine workflow commands" do
    workflow = described_class.send(
      :apply_github_actions_engine_exec_cmd_overrides,
      <<~YAML,
        strategy:
          matrix:
            include:
              - ruby: "truffleruby-22.3"
                appraisal: "ruby-3-0"
                exec_cmd: "kettle-test"
              - ruby: "truffleruby-23.0"
                appraisal: "ruby-3-1"
                exec_cmd: "kettle-test"
      YAML
      {ci: {engine_exec_cmds: {"truffleruby-22.3" => "kettle-test --tag ~type:acceptance"}}}
    )

    expect(workflow).to include('exec_cmd: "kettle-test --tag ~type:acceptance"')
    expect(workflow.scan('exec_cmd: "kettle-test"').size).to eq(1)
  end

  it "includes per-engine workflow commands in the template checksum fingerprint" do
    report = {
      recipe_name: "template_source_application_github_workflows_truffleruby_23_0_yml",
      relative_path: ".github/workflows/truffleruby-23.0.yml",
      request_envelope: {
        request: {
          recipe_name: "supplied_template_source_application",
          recipe_version: "1",
          runtime_context: {
            ci: {engine_exec_cmds: {"truffleruby-23.0" => "kettle-test --tag ~type:acceptance"}}
          }
        }
      },
      metadata: {
        template_source_preference: {
          source_root_path: project_root.to_s,
          source_relative_path: "lib/kettle/jem/templates/.github/workflows/truffleruby-23.0.yml.example"
        }
      }
    }

    payload = described_class.template_input_fingerprint_payload(project_root, report)

    expect(payload).to include(
      github_workflow_engine_exec_cmds: {"truffleruby-23.0" => "kettle-test --tag ~type:acceptance"}
    )
  end

  it "runs every dep-heads job directly from the generated appraisal gemfile" do
    template = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/dep-heads.yml.example"))
    workflow = YAML.safe_load(template, permitted_classes: [], aliases: true)
    jobs = workflow.fetch("jobs")

    expect(template).to include("BUNDLE_GEMFILE: ${{ github.workspace }}/${{ matrix.bundle_gemfile || 'Appraisal.root.gemfile' }}")
    expect(template).to include('BUNDLE_LOCKFILE="${RUNNER_TEMP}/kettle-jem-lockfiles/${{ matrix.appraisal }}-${{ matrix.ruby }}.lock"')
    expect(template).to include('bundle lock --lockfile="$BUNDLE_LOCKFILE"')
    expect(template).not_to include('cp "${BUNDLE_GEMFILE}.lock" "$BUNDLE_LOCKFILE"')
    expect(template).not_to include("bundle exec appraisal ${{ matrix.appraisal }}")
    expect(template).to include("run: bundle exec ${{ matrix.exec_cmd }}")
    expect(template).to include('use-setup-ruby: "3.2 3.3 3.4 4.0"')
    expect(template).to include("bundler-cache: ${{ matrix.ruby != 'jruby' }}")
    expect(template).to include("bundle lock --lockfile=\"$BUNDLE_LOCKFILE\" --add-platform=universal-java --update")
    expect(template).to include("run: bundle install --jobs 4")

    expect(jobs.keys).to include("ruby", "truffleruby", "jruby")
    jobs.each_value do |job|
      entry = job.fetch("strategy").fetch("matrix").fetch("include").first

      expect(entry.fetch("appraisal")).to eq("dep-heads")
      expect(entry.fetch("bundle_gemfile")).to eq("gemfiles/dep_heads.gemfile")
      expect(entry.fetch("direct_bundle")).to be(true)
    end
  end

  it "serializes legacy Ruby setup-ruby workaround in generated CI workflows" do
    ci = {
      default_branch: "main",
      exec_cmd: "kettle-test",
      ruby_versions: ["ruby-2.7", "truffleruby-25.0", "jruby-9.2", "jruby-9.3", "jruby-9.4"]
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
    coverage_workflow = described_class.send(:synchronize_github_actions_coverage_ci, "", {
      ci: ci.merge(coverage: {appraisal: "ruby_3_2", command: "kettle-test"})
    })
    existing_workflow = <<~YAML
      name: Existing
      on:
        push:
          branches:
            - "main"
            - "*-stable"
            - "r*_*-*-v*"
    YAML
    preserved_workflows = [
      described_class.send(:synchronize_github_actions_ci, existing_workflow, {package: {name: "example"}, ci: ci}),
      described_class.send(:synchronize_github_actions_framework_ci, existing_workflow, {
        ci: ci.merge(
          framework_matrix: {
            dimension: "rails",
            include: [{framework_version: "7.2", appraisal: "rails_7_2"}]
          }
        )
      }),
      described_class.send(:synchronize_github_actions_coverage_ci, existing_workflow, {
        ci: ci.merge(coverage: {appraisal: "ruby_3_2", command: "kettle-test"})
      })
    ]

    expect(workflows + [coverage_workflow]).not_to include(include('      - "r*_*-*-v*"'))
    expect(preserved_workflows).to all(include('      - "r*_*-*-v*"'))
    expect(workflows).to all(include("bundler-cache: ${{ matrix.ruby != 'ruby-2.4' && matrix.ruby != 'ruby-2.5' && matrix.ruby != 'ruby-2.6' && matrix.ruby != 'ruby-2.7' && matrix.ruby != 'truffleruby-25.0' && matrix.ruby != 'jruby-9.2' && matrix.ruby != 'jruby-9.3' && matrix.ruby != 'jruby-9.4' }}"))
    expect(workflows).to all(include("      - name: Bundle install for legacy Ruby engine"))
    expect(workflows).to all(include("        if: ${{ matrix.ruby == 'ruby-2.4' || matrix.ruby == 'ruby-2.5' || matrix.ruby == 'ruby-2.6' || matrix.ruby == 'ruby-2.7' || matrix.ruby == 'truffleruby-25.0' || matrix.ruby == 'jruby-9.2' || matrix.ruby == 'jruby-9.3' || matrix.ruby == 'jruby-9.4' }}"))
    expect(workflows).to all(include('          bundle config set --local path "${RUNNER_TEMP}/bundle"'))
    expect(workflows).to all(include("          bundle config set --local mirror.https://gem.coop https://rubygems.org"))
    expect(workflows).to all(include("          bundle install --jobs 1"))

    %w[2.4 2.5 2.6 2.7].each do |version|
      packaged_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/ruby-#{version}.yml.example"))
      expect(packaged_workflow).to include("bundler-cache: false")
      expect(packaged_workflow).to include("      - name: Bundle install for Ruby #{version}")
      expect(packaged_workflow).to include('          bundle config set --local path "${RUNNER_TEMP}/bundle"')
      expect(packaged_workflow).to include("          bundle config set --local mirror.https://gem.coop https://rubygems.org")
      expect(packaged_workflow).to include("          bundle install --jobs 1")
    end

    packaged_rubocop = File.read(project_root.join("lib/kettle/jem/templates/.rubocop.yml.example"))
    expect(packaged_rubocop).to include("    - gemfiles/vendor/**/*")
    expect(packaged_rubocop).to include('    - "**/vendor/**/*"')
    packaged_gitignore = File.read(project_root.join("lib/kettle/jem/templates/.gitignore.example"))
    expect(packaged_gitignore).to include("/gemfiles/vendor/")
    expect(packaged_gitignore).to include("/gemfiles/**/*.gemfile.lock")

    packaged_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/truffleruby-25.0.yml.example"))
    expect(packaged_workflow).to include("bundler-cache: false")
    expect(packaged_workflow).to include("      - name: Bundle install for TruffleRuby 25.0")
    expect(packaged_workflow).to include('          bundle config set --local path "${RUNNER_TEMP}/bundle"')
    expect(packaged_workflow).to include("          bundle config set --local mirror.https://gem.coop https://rubygems.org")
    expect(packaged_workflow).to include("          bundle install --jobs 1")

    packaged_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/jruby-9.2.yml.example"))
    expect(packaged_workflow).to include("bundler-cache: false")
    expect(packaged_workflow).to include("      - name: Bundle install for JRuby 9.2")
    expect(packaged_workflow).to include('          bundle config set --local path "${RUNNER_TEMP}/bundle"')
    expect(packaged_workflow).to include("          bundle config set --local mirror.https://gem.coop https://rubygems.org")
    expect(packaged_workflow).to include("          bundle install --jobs 1")

    packaged_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/jruby-9.3.yml.example"))
    expect(packaged_workflow).to include("bundler-cache: false")
    expect(packaged_workflow).to include("      - name: Bundle install for JRuby 9.3")
    expect(packaged_workflow).to include('          bundle config set --local path "${RUNNER_TEMP}/bundle"')
    expect(packaged_workflow).to include("          bundle config set --local mirror.https://gem.coop https://rubygems.org")
    expect(packaged_workflow).to include("          bundle install --jobs 1")

    packaged_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/jruby-9.4.yml.example"))
    expect(packaged_workflow).to include("bundler-cache: false")
    expect(packaged_workflow).to include("      - name: Bundle install for JRuby 9.4")
    expect(packaged_workflow).to include('          bundle config set --local path "${RUNNER_TEMP}/bundle"')
    expect(packaged_workflow).to include("          bundle config set --local mirror.https://gem.coop https://rubygems.org")
    expect(packaged_workflow).to include("          bundle install --jobs 1")
  end

  it "serializes RSpec status cache steps in generated CI workflows" do
    ci = {
      default_branch: "main",
      exec_cmd: "kettle-test",
      ruby_versions: ["ruby", "jruby", "truffleruby-25.0"]
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
      }),
      described_class.send(:synchronize_github_actions_coverage_ci, "", {
        ci: ci.merge(coverage: {appraisal: "ruby_3_2", command: "kettle-test"})
      })
    ]

    expect(workflows).to all(include("      - name: Restore RSpec status log"))
    expect(workflows).to all(include("        uses: actions/cache@"))
    expect(workflows).to all(include("          path: .rspec_status"))
    expect(workflows).to all(include("${{hashFiles('**/Gemfile.lock','Appraisal.root.gemfile','gemfiles/**/*.gemfile')}}"))
    expect(workflows).to all(include("${{github.run_id}}-${{github.run_attempt}}"))

    current_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/current.yml.example"))
    jruby_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/jruby.yml.example"))
    truffleruby_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/truffleruby-25.0.yml.example"))
    framework_workflow = File.read(project_root.join("lib/kettle/jem/templates/.github/workflows/framework-ci.yml.example"))

    expect(current_workflow).to include("rspec-status-current-${{matrix.ruby}}-${{matrix.appraisal}}-")
    expect(jruby_workflow).to include("rspec-status-jruby-${{matrix.ruby}}-${{matrix.appraisal}}-")
    expect(jruby_workflow).to include("startsWith(github.head_ref, 'jruby/')")
    expect(jruby_workflow).to include("startsWith(github.head_ref, 'feature/release')")
    expect(truffleruby_workflow).to include("rspec-status-truffleruby-25.0-${{matrix.ruby}}-${{matrix.appraisal}}-")
    expect(truffleruby_workflow).to include("startsWith(github.head_ref, 'truffleruby/')")
    expect(truffleruby_workflow).to include("startsWith(github.head_ref, 'feature/release')")
    expect(framework_workflow).to include(
      "rspec-status-framework-ci-${{matrix.ruby}}-${{matrix.framework_version}}-${{matrix.gemfile}}-"
    )
  end

  it "keeps compatibility install settings on every cached setup-ruby-flash template step" do
    workflow_paths = Dir[project_root.join("lib/kettle/jem/templates/.github/workflows/*.yml.example")]
    setup_steps = workflow_paths.flat_map do |path|
      lines = File.readlines(path, chomp: true)
      lines.each_index.filter_map do |index|
        next unless lines[index].include?("uses: appraisal-rb/setup-ruby-flash@")

        following_steps = lines[(index + 1)..]
        next_step_offset = following_steps.find_index { |line| line.start_with?("      - ") }
        step_lines = lines[index, next_step_offset ? next_step_offset + 1 : lines.length]
        [path, step_lines.join("\n")]
      end
    end

    expect(setup_steps).not_to be_empty
    setup_steps.each do |_path, step|
      expect_pinned_action(step, "appraisal-rb/setup-ruby-flash")
    end

    cached_setup_steps = setup_steps.select { |_path, step| step.include?("bundler-cache: true") }
    expect(cached_setup_steps).not_to be_empty
    cached_setup_steps.each do |_path, step|
      expect(step).to include("manual-compatibility-bundle: true")
      expect(step).to include("gem-install-retries: 7")
    end
  end

  it "ports old modular Gemfile ruby-bucket eval_gemfile replacement" do
    tmp_root = File.expand_path("../tmp", __dir__)
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

  it "preserves destination-only main Gemfile ruby-bucket eval_gemfile entries" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-destination-evals", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 3.0"
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

          # Code Coverage
          eval_gemfile "gemfiles/modular/coverage.gemfile"

          # Test HTTP Interaction Recording
          eval_gemfile "gemfiles/modular/recording/r3/recording.gemfile"

          # Linting
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
        "template/Gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          source "https://gem.coop"

          # Code Coverage
          eval_gemfile "gemfiles/modular/coverage.gemfile"

          # Linting
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Gemfile" }
      content = report.fetch(:final_content)

      expect(content).to include("# Test HTTP Interaction Recording")
      expect(content.scan('eval_gemfile "gemfiles/modular/recording/r3/recording.gemfile"').size).to eq(1)
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "removes duplicate main Gemfile eval_gemfile declarations for the same path" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-duplicate-eval-gemfile", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 3.0"
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

          # Modular sibling dependencies
          eval_gemfile "gemfiles/modular/coverage.gemfile"

          # Debugging
          eval_gemfile "gemfiles/modular/debug.gemfile"

          # Code Coverage
          eval_gemfile "gemfiles/modular/coverage.gemfile"
        RUBY
        "template/Gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          source "https://gem.coop"

          # Debugging
          eval_gemfile "gemfiles/modular/debug.gemfile"

          # Code Coverage
          eval_gemfile "gemfiles/modular/coverage.gemfile"
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Gemfile" }
      content = report.fetch(:final_content)

      expect(content.scan('eval_gemfile "gemfiles/modular/coverage.gemfile"').size).to eq(1)
      expect(content).not_to include("# Modular sibling dependencies")
      expect(content).to include("# Code Coverage")
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "repairs missing main Gemfile recording evals from configured Appraisals" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-recording-repair", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 3.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
        YAML
        "Appraisals" => <<~RUBY,
          appraise "current" do
            eval_gemfile "modular/recording/r4/recording.gemfile"
            eval_gemfile "modular/x_std_libs.gemfile"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          # Code Coverage
          eval_gemfile "gemfiles/modular/coverage.gemfile"

          # Linting
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
        "template/Gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          source "https://gem.coop"

          # Code Coverage
          eval_gemfile "gemfiles/modular/coverage.gemfile"

          # Linting
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Gemfile" }
      content = report.fetch(:final_content)

      expect(content).to include("# Test HTTP Interaction Recording")
      expect(content.scan('eval_gemfile "gemfiles/modular/recording/r4/recording.gemfile"').size).to eq(1)
      expect(content.index("# Test HTTP Interaction Recording")).to be < content.index("# Linting")
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "removes the destination package from the main Gemfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
      expect(content).not_to include("tree_sitter_language_pack")
      expect(File.read(File.join(root, "gemfiles/modular/templating_local.gemfile"))).to eq(content)
    end
  end

  it "removes obsolete TSLP local wiring from StructuredMerge local gem lists" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-stale-tslp-local-wiring", tmp_root) do |root|
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
              - gemfiles/modular/templating_local.gemfile
        YAML
        "gemfiles/modular/templating_local.gemfile" => <<~RUBY,
          structuredmerge_local_gems = %w[
            tree_sitter_language_pack
            tree_haver
            kettle-jem
          ]

          eval_nomono_gems(
            gems: structuredmerge_local_gems,
            path_env: "STRUCTUREDMERGE_DEV"
          )
        RUBY
        "template/gemfiles/modular/templating_local.gemfile.example" => <<~RUBY
          structuredmerge_local_gems = %w[
            tree_haver
            kettle-jem
          ]

          eval_nomono_gems(
            gems: structuredmerge_local_gems,
            path_env: "STRUCTUREDMERGE_DEV"
          )
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/templating_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).not_to include("tree_sitter_language_pack")
      expect(content).to include("tree_haver")
      expect(content).to include("kettle-jem")
      expect(File.read(File.join(root, "gemfiles/modular/templating_local.gemfile"))).to eq(content)
    end
  end

  it "preserves local Gemfile array indentation when removing the destination package" do
    source = <<~RUBY
      structuredmerge_local_gems = %w[
        tree_haver
        kettle-jem
      ]
    RUBY

    content = described_class.send(:remove_gemfile_percent_w_entries, source, ["kettle-jem"])

    expect(content).to include("structuredmerge_local_gems = %w[\n  tree_haver\n]")
    expect(content).not_to include("structuredmerge_local_gems =                              %w[")
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

    expect(tokens.fetch("KJ|KETTLE_DEV_LOCAL_GEMS")).to eq("kettle-dev kettle-family kettle-test kettle-soup-cover kettle-changelog kettle-drift")
    expect(tokens.fetch("KJ|MAIN_GEMFILE_KETTLE_FAMILY_GEM")).to include('gem "kettle-family"')
    expect(tokens.fetch("KJ|MAIN_GEMFILE_NOMONO_BOOTSTRAP")).to include('gem "nomono"')
    expect(tokens.fetch("KJ|PACKAGE_NAME")).to eq("example")
  end

  it "keeps kettle-dev local overrides available for kettle-jem transitive runtime dependencies" do
    template = File.read(File.expand_path("../../lib/kettle/jem/templates/gemfiles/modular/templating_local.gemfile.example", __dir__))

    expect(template).to include("  html-merge\n")
    expect(template).to include(
      "structuredmerge_local_gems_to_eval = structuredmerge_local_gems - %w[{KJ|PACKAGE_NAME}]"
    )
    expect(template).not_to include(
      "structuredmerge_local_gems_to_eval = structuredmerge_local_gems - %w[{KJ|PACKAGE_NAME}] - declared_gems"
    )
    expect(template).to include(
      "kettle_dev_local_gems_to_eval = kettle_dev_local_gems - %w[{KJ|PACKAGE_NAME}] - (declared_gems - %w[kettle-dev])"
    )
    expect(template).not_to include("platform :mri do")
  end

  it "omits kettle-family from its own main Gemfile dependency token" do
    runtime = described_class.send(
      :project_runtime_facts,
      {},
      {},
      package_name: "kettle-family",
      source_url: "https://github.com/kettle-dev/kettle-family",
      author_domain: "example.test",
      min_ruby: ">= 3.2",
      test_min_ruby: Gem::Version.new("3.2"),
      version: "1.2.0"
    )
    tokens = described_class.send(:project_runtime_template_tokens, runtime)

    expect(tokens.fetch("KJ|KETTLE_DEV_LOCAL_GEMS")).to include("kettle-family")
    expect(tokens.fetch("KJ|MAIN_GEMFILE_KETTLE_FAMILY_GEM")).to eq("")
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
    tmp_root = File.expand_path("../tmp", __dir__)
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
      expect(content).to include("installs harness helpers documented in spec/README.md")
      expect(content.scan('require "example/custom"').size).to eq(1)
    end
  end

  it "preserves destination spec helper support wiring while adding template bootstrap" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
          files:
            spec:
              spec_helper.rb:
                strategy: merge
                preference: destination
                add_template_only_nodes: false
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

      # add_template_only_nodes: false keeps coverage bootstrap out of a
      # destination-owned helper while preserving its existing harness wiring.
      expect(content).not_to include('require "kettle-soup-cover"')
      expect(content).not_to include("Kettle::Soup::Cover::DO_COV")
      expect(content).not_to include('require "simplecov"')
      expect(content.scan('require "kettle/test/rspec"').size).to eq(1)
      expect(content).to include("installs harness helpers documented in spec/README.md")
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

  it "adds the kettle-test helper documentation comment when merging an existing spec helper" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-spec-helper-helper-doc-merge", tmp_root) do |root|
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
            entrypoint_require: "example"
          templates:
            root: packaged
            apply: true
            entries:
              - spec/spec_helper.rb
          files:
            spec:
              spec_helper.rb:
                strategy: merge
                preference: destination
                add_template_only_nodes: false
        YAML
        "spec/spec_helper.rb" => <<~RUBY
          # frozen_string_literal: true

          # External RSpec & related config
          require "kettle/test/rspec"

          require "example"

          RSpec.configure do |config|
            config.example_status_persistence_file_path = ".rspec_status"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "spec/spec_helper.rb"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:changed)).to be(true)
      expect(content).to include(<<~RUBY)
        require "kettle/test/rspec"
        # `kettle/test/rspec` installs harness helpers documented in spec/README.md.
      RUBY
      expect(content).not_to include("config.disable_monkey_patching!")
      expect(File.read(File.join(root, "spec", "spec_helper.rb"))).to eq(content)
    end
  end

  it "treats packaged local Gemfiles as template-owned by default" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
      expect(content).to include("declared_gems = instance_variable_get(:@dependencies).to_a.map(&:name)")
      expect(content).to include("local_gems_to_eval = local_gems -")
      expect(content).to include("declared_gems")
      expect(content).to include("gems: local_gems_to_eval")
      expect(content).to include('require "nomono/bundler"')
      expect(content).to include("nomono_activation_requirements")
      expect(content).to include("nomono_lockfile")
      expect(content).to include("Bundler::LockfileParser")
      expect(content).not_to include("local-only")
      expect(content).not_to include("rubocop-ruby2_3")
    end
  end

  it "normalizes obsolete nomono activation ceremony in merged local Gemfiles" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-local-gemfile-nomono-loader-cleanup", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            gemfiles/modular/coverage_local.gemfile:
              strategy: merge
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/coverage_local.gemfile
        YAML
        "gemfiles/modular/coverage_local.gemfile" => <<~RUBY
          # frozen_string_literal: true

          # Local path overrides for development.
          # Loaded by the associated non-local gemfile when KETTLE_DEV_DEV != "false".

          # Bootstrapping nomono here cannot rely on a plain `gem "nomono", ...` line.
          # Bundler records that dependency during Gemfile evaluation, but it does not
          # activate that exact version before the immediate `require "nomono/bundler"`.
          nomono_activation_requirements = ["~> 1.0", ">= 1.0.8"]
          nomono_lockfile = File.expand_path("../../Gemfile.lock", __dir__)
          if File.file?(nomono_lockfile)
            nomono_locked_spec = Bundler::LockfileParser
              .new(Bundler.read_file(nomono_lockfile))
              .specs
              .find { |spec| spec.name == "nomono" }
            nomono_locked = nomono_locked_spec &&
              Gem::Requirement.new(nomono_activation_requirements).satisfied_by?(nomono_locked_spec.version)
            if nomono_locked
              nomono_activation_requirements = ["= \#{nomono_locked_spec.version}"]
            end
          end
          Kernel.send(:gem, "nomono", *nomono_activation_requirements)
          require "nomono/bundler"

          local_gems = %w[
            custom-local
          ]
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/coverage_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content.scan(/^require "nomono\/bundler"$/).size).to eq(1)
      expect(content).to match(/nomono_activation_requirements = \["~> 1\.1", ">= 1\.1\.\d+"\]/)
      expect(content).to include('nomono_already_activated = Gem.loaded_specs["nomono"]')
      expect(content).to include("!nomono_already_activated || !nomono_requirement.satisfied_by?(nomono_already_activated.version)")
      expect(content).to include("nomono_lockfile")
      expect(content).to include("Bundler::LockfileParser")
      expect(content).to include('Gem::Specification.find_all_by_name("nomono")')
      expect(content).to include('Kernel.send(:gem, "nomono"')
      expect(content).to include('root: ["src", "my", "kettle-dev"]')
    end
  end

  it "loads nomono's own local Gemfiles from the local source tree" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-nomono-local-gemfile-self-loader", tmp_root) do |root|
      write_tree(root, {
        "nomono.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "nomono"
            spec.summary = "Nomono"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/coverage_local.gemfile
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/coverage_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).to include('require "nomono/bundler"')
      expect(content).not_to include("require_relative")
      expect(content).to include("nomono_activation_requirements")
      expect(content).to include("nomono_lockfile")
      expect(content).to include("Bundler::LockfileParser")
      expect(content).to include('root: ["src", "my", "kettle-dev"]')
    end
  end

  it "excludes the current gem and already declared gems from documentation local path overrides" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-documentation-local-gemfile-self-exclusion", tmp_root) do |root|
      write_tree(root, {
        "yard-yaml.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "yard-yaml"
            spec.summary = "YARD YAML"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/documentation_local.gemfile
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/documentation_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).to include("local_gems = %w[yard-fence yard-timekeeper]")
      expect(content).to include("declared_gems = instance_variable_get(:@dependencies).to_a.map(&:name)")
      expect(content).to include("local_gems_to_eval = local_gems - %w[] - declared_gems")
      expect(content).to include("gems: local_gems_to_eval")
    end
  end

  it "excludes the current gem from every local path override word array" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-local-gemfile-galtzo-self-exclusion", tmp_root) do |root|
      write_tree(root, {
        "turbo_tests2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "turbo_tests2"
            spec.summary = "Turbo Tests"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - gemfiles/modular/coverage_local.gemfile
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/coverage_local.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).not_to include("gems: %w[turbo_tests2]")
      expect(content).not_to include("- turbo_tests2")
    end
  end

  it "generates nomono in the main Gemfile before local workspace overrides need it" do
    tmp_root = File.expand_path("../tmp", __dir__)
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

      expect(content).to include('gem "nomono"')
      expect(content).not_to include("nomono_requirements")
      expect(content.index('gem "nomono"')).to be < content.index('eval_gemfile "gemfiles/modular/templating.gemfile"')
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "does not generate a duplicate nomono dependency in nomono's own main Gemfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-nomono-self", tmp_root) do |root|
      write_tree(root, {
        "nomono.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "nomono"
            spec.summary = "Nomono"
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
      content = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Gemfile" }.fetch(:final_content)

      expect(content).not_to include('gem "nomono"')
      expect(content).not_to include("nomono_requirements =")
      expect(File.read(File.join(root, "Gemfile"))).to eq(content)
    end
  end

  it "adds nomono bootstrap to existing main Gemfiles before templating local overrides" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-existing-nomono", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          gemspec

          eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
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
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(apply.fetch(:changed_files)).to include("Gemfile")
      expect(gemfile).to include('gem "nomono"')
      expect(gemfile).not_to include("nomono_requirements")
      expect(gemfile.index('gem "nomono"')).to be < gemfile.index('eval_gemfile "gemfiles/modular/templating.gemfile"')
    end
  end

  it "treats falsey TSLP_DEV values as unset rather than as local paths" do
    template = File.read(File.expand_path("../../lib/kettle/jem/templates/gemfiles/modular/templating.gemfile.example", __dir__))

    expect(template).to include("tslp_dev = nil if tslp_dev.empty? || %w[false 0 no off].include?(tslp_dev.downcase)")
    expect(template).to include("tslp_requirements = if tslp_dev.to_s.empty?")
    expect(template).to include('gem "tree_sitter_language_pack", *tslp_requirements')
  end

  it "treats packaged CITATION.cff as template-owned metadata by default" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
    tmp_root = File.expand_path("../tmp", __dir__)
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

      expect(content).to include("debug")
      expect(content).not_to match(/^\s+example-gem$/)
      expect(content).not_to match(/^\s*gem\s+["']example-gem["']/)
      expect(File.read(File.join(root, "gemfiles/modular/debug.gemfile"))).to eq(content)
    end
  end

  it "removes gemspec runtime dependencies from modular Gemfile dependency lists" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-modular-gemfile-runtime-dependency", tmp_root) do |root|
      write_tree(root, {
        "yard-yaml.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "yard-yaml"
            spec.summary = "YARD YAML"
            spec.add_dependency("yaml-converter", "~> 0.2")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - gemfiles/modular/documentation.gemfile
          files:
            gemfiles:
              modular:
                documentation.gemfile:
                  strategy: accept_template
        YAML
        "template/gemfiles/modular/documentation.gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          # Documentation
          gem "kramdown", "~> 2.5", ">= 2.5.1", require: false
          gem "yaml-converter", "~> 0.2", ">= 0.2.3", require: false
          gem "yard", "~> 0.9", ">= 0.9.44", require: false
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/documentation.gemfile"
      end
      content = report.fetch(:final_content)

      expect(content).to include('gem "kramdown"')
      expect(content).to include('gem "yard"')
      expect(content).not_to include('gem "yaml-converter"')
      expect(File.read(File.join(root, "gemfiles/modular/documentation.gemfile"))).to eq(content)
    end
  end

  it "keeps a named modular dependency when materializing a missing Gemfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-modular-gemfile-materialization", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example Gem"
            spec.add_dependency("mutex_m", "~> 0.2")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - gemfiles/modular/mutex_m/r4/v0.3.gemfile
          files:
            gemfiles:
              modular:
                mutex_m/r4/v0.3.gemfile:
                  strategy: accept_template
        YAML
        "template/gemfiles/modular/mutex_m/r4/v0.3.gemfile.example" => <<~RUBY
          # Ruby >= 2.5
          gem "mutex_m", "~> 0.2"
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "gemfiles/modular/mutex_m/r4/v0.3.gemfile"
      end
      content = report.fetch(:final_content)

      expect(report.fetch(:changed)).to be(true)
      expect(content).to include('gem "mutex_m", "~> 0.2"')
      expect(File.read(File.join(root, "gemfiles/modular/mutex_m/r4/v0.3.gemfile"))).to eq(content)
    end
  end

  it "keeps YARD linting in the documentation modular Gemfile" do
    content = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, "gemfiles", "modular", "documentation.gemfile.example"))

    expect_gem_dependency_declared(content, "yard-lint")
    expect(content).not_to include('gem "rdoc"')
    expect(content).not_to include("Gem::Version.new(RUBY_VERSION)")
  end

  it "generates shunted.gemfile entries from resolved development dependency Ruby floors" do
    tmp_root = File.expand_path("../tmp", __dir__)
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
      expect_gem_dependency_declared(content, "debug")
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
end
