# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Kettle::Jem do
  include_context "with isolated kettle-jem environment"

  it "omits the deprecated secure installation section from packaged README templates" do
    template_root = described_class::PACKAGED_TEMPLATE_ROOT

    expect(File.read(File.join(template_root, "README.md.example"))).not_to include("### Secure Installation")
  end

  it "includes RubyForum in the packaged README support row" do
    template_root = described_class::PACKAGED_TEMPLATE_ROOT
    readme_template = File.read(File.join(template_root, "README.md.example"))

    expect(readme_template).to include("[![Get help from RubyForum][✉️ruby-forum-img]][✉️ruby-forum]")
    expect(readme_template).to include("[✉️ruby-forum]: https://www.rubyforum.org/c/help/8")
    expect(readme_template).to include(
      "[✉️ruby-forum-img]: https://img.shields.io/badge/RubyForum-Help-CC342D"
    )
  end

  it "projects RuboCop LTS template tokens from minimum Ruby" do
    tmp_root = File.join(__dir__, "../tmp")
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
      template_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_gemfiles_modular_style_gemfile"
      end
      final_content = template_report.fetch(:final_content)

      expect(template_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: "gemfiles/modular/style.gemfile.example",
        source_relative_path: "gemfiles/modular/style.gemfile.example",
        source_root: "packaged"
      )
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include(
        "Style tasks run on the latest Ruby"
      )
      expect_gem_dependency_declared(final_content, "rubocop-lts")
      expect_gem_dependency_declared(final_content, "rubocop-lts-rspec")
      expect(final_content).not_to include('gem "rubocop-rspec"')
      expect_gem_dependency_declared(final_content, "appraisal2-rubocop")
      expect_gem_dependency_declared(final_content, "rubocop-ruby3_1")
      expect(final_content).to include(
        "declared_gems = instance_variable_get(:@dependencies).to_a.map(&:name)"
      )
      expect(final_content).to include(
        'unless declared_gems.include?("rubocop-ruby3_1")'
      )
      template_tokens = template_report.dig(:metadata, :template_tokens)
      expect(template_tokens.keys).to include(
        "KJ|RUBOCOP_TARGET_RUBY",
        "KJ|RUBOCOP_LTS_CONSTRAINT",
        "KJ|RUBOCOP_RUBY_CONSTRAINT",
        "KJ|RUBOCOP_RUBY_GEM"
      )
      expect(template_tokens).to include("KJ|RUBOCOP_RUBY_GEM" => "rubocop-ruby3_1")
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
    tmp_root = File.join(__dir__, "../tmp")
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
    tmp_root = File.join(__dir__, "../tmp")
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
      appraisals_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == "Appraisals"
      end
      appraisal_root_report = plan.fetch(:recipe_reports).find do |report|
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
end
