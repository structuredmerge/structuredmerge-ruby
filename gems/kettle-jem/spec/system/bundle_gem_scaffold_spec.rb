# frozen_string_literal: true

require "open3"
require "pathname"
require "rake"
require "rbs"

RSpec.describe "bundle gem scaffold + kettle-jem", :system do
  let(:sandbox_root) { File.expand_path("../../../tmp/sandbox", __dir__) }
  let(:gem_root) { File.join(sandbox_root, "dummy-gem") }
  let(:env) do
    {
      "FUNDING_ORG" => "acme",
      "KJ_MIN_DIVERGENCE_THRESHOLD" => "5"
    }
  end
  let(:expected_hidden_directories) do
    %w[
      .config
      .config/mise
      .devcontainer
      .devcontainer/apt-install
      .devcontainer/scripts
      .git-hooks
      .github
      .github/workflows
      .qlty
    ]
  end
  let(:expected_hidden_files) do
    %w[
      .config/mise/env.sh
      .devcontainer/apt-install/devcontainer-feature.json
      .devcontainer/apt-install/install.sh
      .devcontainer/devcontainer.json
      .devcontainer/scripts/setup-tree-sitter.sh
      .git-hooks/commit-msg
      .git-hooks/footer-template.erb.txt
      .git-hooks/prepare-commit-msg
      .github/.codecov.yml
      .github/copilot_instructions.md
      .github/dependabot.yml
      .github/workflows/templating.yml
      .qlty/qlty.toml
    ]
  end

  before do
    FileUtils.rm_rf(gem_root)
    FileUtils.mkdir_p(sandbox_root)
    scaffold_bundle_gem!
    normalize_scaffold_gemspec!
  end

  after do
    FileUtils.rm_rf(gem_root)
  end

  def scaffold_bundle_gem!
    clean_env = ENV.to_h.tap do |env|
      env.keys.grep(/\ABUNDLE_/).each { |key| env[key] = nil }
      env.keys.grep(/\ABUNDLER_/).each { |key| env[key] = nil }
      %w[RUBYLIB RUBYOPT].each { |key| env[key] = nil }
    end
    stdout, stderr, status = Open3.capture3(
      clean_env,
      "bundle",
      "gem",
      "dummy-gem",
      "--no-git",
      "--no-ci",
      "--no-mit",
      "--no-coc",
      "--no-ext",
      "--test=rspec",
      "--no-changelog",
      "--no-linter",
      "--no-github-username",
      chdir: sandbox_root
    )
    expect(status.success?).to be(true), "bundle gem failed\nstdout=#{stdout}\nstderr=#{stderr}"
  end

  def normalize_scaffold_gemspec!
    path = File.join(gem_root, "dummy-gem.gemspec")
    content = File.read(path)
    content = content.sub('spec.authors = ["TODO: Write your name"]', 'spec.authors = ["Test User"]')
    content = content.sub('spec.email = ["TODO: Write your email address"]', 'spec.email = ["test@example.com"]')
    content = content.sub(
      'spec.summary = "TODO: Write a short summary, because RubyGems requires one."',
      'spec.summary = "Dummy gem"'
    )
    content = content.sub(
      'spec.description = "TODO: Write a longer description or delete this line."',
      'spec.description = "Dummy gem for kettle-jem system testing."'
    )
    content = content.sub(
      'spec.homepage = "TODO: Put your gem\'s website or public repo URL here."',
      'spec.homepage = "https://github.com/acme/dummy-gem"'
    )
    content = content.sub(
      'spec.metadata["source_code_uri"] = "TODO: Put your gem\'s public repo URL here."',
      'spec.metadata["source_code_uri"] = "https://github.com/acme/dummy-gem"'
    )
    content = content.sub(
      /^end$/,
      <<~RUBY.chomp
            # Destination runtime dependency
            spec.add_dependency("json", "~> 2.7") # preserve custom runtime dependency
            spec.add_development_dependency("rake", "~> 13.1") # preserve destination rake policy
        end
      RUBY
    )
    File.write(path, content)
  end

  def expect_gem_dependency_declared(content, gem_name)
    declared = Kettle::Jem.ruby_call_records(content, :gem).any? do |call|
      argument = call.arguments&.arguments&.first
      argument.is_a?(Prism::StringNode) && argument.unescaped == gem_name
    end

    expect(declared).to be(true), "expected Gemfile dependency #{gem_name.inspect}"
  end

  def enable_packaged_templates!
    path = File.join(gem_root, ".structuredmerge/kettle-jem.yml")
    content = File.read(path)
    content = content.sub('project_emoji: ""', 'project_emoji: "💎"')
    File.write(path, content)
  end

  def seed_destination_readme!
    File.write(File.join(gem_root, "README.md"), <<~MARKDOWN)
      # 1️⃣ Dummy::Gem

      ## Synopsis

      Destination synopsis from the scaffolded project.

      ## Usage

      Destination usage from the scaffolded project.

      ## Note: Local

      Destination note from the scaffolded project.

      ## Installation

      Old scaffold installation notes.
    MARKDOWN
  end

  def seed_destination_dependabot!
    FileUtils.mkdir_p(File.join(gem_root, ".github"))
    File.write(File.join(gem_root, ".github/dependabot.yml"), <<~YAML)
      updates:
        - package-ecosystem: bundler
          directory: "/"
          schedule:
            interval: daily
    YAML
  end

  it "bootstraps config and applies selected packaged templates to a fresh scaffold" do
    bootstrap = Kettle::Jem.apply_project(gem_root, env: env)
    bootstrap_report = bootstrap.fetch(:recipe_reports).find do |report|
      report.fetch(:recipe_name) == "kettle_config_bootstrap"
    end
    expect(bootstrap_report.fetch(:changed)).to be(true)
    kettle_config = File.read(File.join(gem_root, ".structuredmerge/kettle-jem.yml"))
    expect(kettle_config).to include("# kettle-jem configuration file")
    expect(kettle_config).to include("min_divergence_threshold: 5")
    expect(kettle_config).to include("  Rakefile:\n    strategy: merge")
    expect(kettle_config).to include("    preference: destination")
    expect(kettle_config).to include("    add_template_only_nodes: true")
    expect(bootstrap.fetch(:changed_files)).to include(
      ".github/FUNDING.yml",
      ".structuredmerge/kettle-jem.yml",
      "Rakefile"
    )
    expect(bootstrap.fetch(:changed_files)).not_to include(".github/workflows/ci.yml")

    enable_packaged_templates!
    seed_destination_readme!
    seed_destination_dependabot!

    apply = Kettle::Jem.apply_project(gem_root, env: env)
    expect(apply.fetch(:changed_files)).to include(".github/dependabot.yml", "Gemfile", "README.md")
    expect(File).to exist(File.join(gem_root, ".github/FUNDING.yml"))
    expect(File).not_to exist(File.join(gem_root, ".github/workflows/ci.yml"))
    expect(File).to exist(File.join(gem_root, ".github/workflows/current.yml"))
    expect(File).to exist(File.join(gem_root, ".github/workflows/ruby-3.2.yml"))
    expect(File).to exist(File.join(gem_root, ".github/workflows/style.yml"))

    root_signature = File.read(File.join(gem_root, "sig/dummy/gem.rbs"))
    expect(root_signature).to include("module Version")
    expect(root_signature).to include("VERSION: String")
    loader = RBS::EnvironmentLoader.new
    loader.add(path: Pathname(File.join(gem_root, "sig")))
    expect { RBS::Environment.from_loader(loader).resolve_type_names }.not_to raise_error

    rakefile = File.read(File.join(gem_root, "Rakefile"))
    expect(rakefile).to include("Kettle::Dev.install_tasks")
    expect(rakefile).to include("Kettle::Jem.install_tasks")

    readme = File.read(File.join(gem_root, "README.md"))
    expect(readme).to include("# 💎 Dummy::Gem")
    expect(readme).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis from the scaffolded project\./)
    expect(readme).to include("## 🔧 Basic Usage\n\nDestination usage from the scaffolded project.")
    expect(readme).not_to include("Old scaffold installation notes.")
    expect(readme).to include("Compatible with MRI Ruby 3.2.0+")
    expect(readme).to include("https://github.com/acme/dummy-gem")

    dependabot = YAML.safe_load_file(File.join(gem_root, ".github/dependabot.yml"))
    expect(dependabot).to eq(
      "updates" => [
        {
          "directory" => "/",
          "ignore" => [
            {
              "dependency-name" => "rubocop-lts"
            }
          ],
          "open-pull-requests-limit" => 5,
          "package-ecosystem" => "bundler",
          "schedule" => {"interval" => "daily"}
        }
      ],
      "version" => 2
    )

    style_gemfile = File.read(File.join(gem_root, "gemfiles/modular/style.gemfile"))
    expect_gem_dependency_declared(style_gemfile, "rubocop-lts")
    expect_gem_dependency_declared(style_gemfile, "rubocop-lts-rspec")
    expect(style_gemfile).not_to include('gem "rubocop-rspec"')
    expect_gem_dependency_declared(style_gemfile, "rubocop-ruby3_2")
    expect(style_gemfile).to include('unless declared_gems.include?("rubocop-ruby3_2")')

    gemfile = File.read(File.join(gem_root, "Gemfile"))
    expect(gemfile).to include('source "https://gem.coop"')
    expect(gemfile.scan('source "https://gem.coop"').size).to eq(1)
    expect(gemfile.scan(/^gemspec$/).size).to eq(1)
    expect(gemfile.scan('eval_gemfile "gemfiles/modular/style.gemfile"').size).to eq(1)
    expect(gemfile).to include('gem "irb"')

    gemspec = File.read(File.join(gem_root, "dummy-gem.gemspec"))
    expect(gemspec.scan("Gem::Specification.new").size).to eq(1)
    expect(gemspec).to include('spec.name = "dummy-gem"')
    expect(gemspec).to include('spec.summary = "💎 Dummy gem"')
    expect(gemspec).to include('spec.description = "💎 Dummy gem for kettle-jem system testing."')
    expect(gemspec).to include('spec.homepage = "https://github.com/acme/dummy-gem"')
    expect(gemspec).to include('spec.required_ruby_version = ">= 3.2.0"')
    expect(gemspec).to include("spec.metadata[\"source_code_uri\"] = \"\#{spec.homepage}/tree/v\#{spec.version}\"")
    expect(gemspec).to include('spec.add_dependency("json", "~> 2.7") # preserve custom runtime dependency')
    expect(gemspec).to include('spec.add_development_dependency("rake", "~> 13.1") # preserve destination rake policy')
    expect(gemspec.scan('spec.add_development_dependency("rake"').size).to eq(1)

    rakefile = File.read(File.join(gem_root, "Rakefile"))
    expect(rakefile).to include('require "bundler/gem_tasks"')
    expect(rakefile).to include('require "kettle/dev"')
    expect(rakefile).to include('Kettle::Dev.install_tasks unless Kettle::Dev::RUNNING_AS == "rake"')
    expect(rakefile).to include("Kettle::Jem.install_tasks")
    expect(rakefile).to include("rescue LoadError")
    previous_significant = nil
    orphaned_task_requires = rakefile.lines.filter_map do |line|
      required = line[/^\s*require\s+["']([^"']+)["']\s*$/, 1]
      orphaned = required && %w[kettle/dev kettle/jem stone_checksums].include?(required) && previous_significant != "begin"
      stripped = line.strip
      previous_significant = stripped unless stripped.empty? || stripped.start_with?("#")
      line if orphaned
    end
    expect(orphaned_task_requires).to be_empty
    expect(rakefile.scan(/^task\s+:default\b/).size).to eq(1)
    expect(rakefile).to include('desc "Default tasks aggregator"')
    expect(rakefile.index('desc "Default tasks aggregator"')).to be < rakefile.index("task :default do")
    expect(rakefile.scan('task("kettle:jem:selftest")').size).to eq(1)
    expect(rakefile.scan('task("build:generate_checksums")').size).to eq(1)
    expect(rakefile).not_to include('desc("(stub) kettle:jem:template is unavailable")')

    FileUtils.mkdir_p(File.join(gem_root, "lib", "dummy", "gem"))
    File.write(File.join(gem_root, "lib", "dummy", "gem", "version.rb"), <<~RUBY)
      module Dummy
        module Gem
          module Version
            VERSION = "0.1.0"
          end
        end
      end
    RUBY

    previous_rake_application = Rake.application
    Rake.application = Rake::Application.new
    begin
      allow(Dir).to receive(:pwd).and_return(gem_root)
      load File.join(gem_root, "Rakefile")
      expect(Rake::Task.task_defined?("kettle:jem:prepare")).to be(true)
      expect(Rake::Task.task_defined?("kettle:jem:template")).to be(true)
      expect(Rake::Task.task_defined?("kettle:jem:install")).to be(true)
      expect(Rake::Task.task_defined?("kettle:jem:selftest")).to be(true)
    ensure
      Rake.application = previous_rake_application
    end

    aggregate_failures "hidden packaged template directories" do
      expected_hidden_directories.each do |relative_path|
        expect(Dir).to exist(File.join(gem_root, relative_path)), "expected #{relative_path} to exist"
      end
    end

    aggregate_failures "hidden packaged template files" do
      expected_hidden_files.each do |relative_path|
        expect(File).to exist(File.join(gem_root, relative_path)), "expected #{relative_path} to exist"
      end
    end

    selected_template_paths = [
      ".github/copilot_instructions.md",
      ".github/dependabot.yml",
      ".qlty/qlty.toml",
      "Gemfile",
      "certs/pboling.pem",
      "dummy-gem.gemspec",
      "gemfiles/modular/style.gemfile"
    ]
    before_second_apply = selected_template_paths.to_h do |relative_path|
      [relative_path, File.read(File.join(gem_root, relative_path))]
    end

    Kettle::Jem.apply_project(gem_root, env: env)

    expect(selected_template_paths.to_h { |relative_path|
      [relative_path, File.read(File.join(gem_root, relative_path))]
    }).to eq(before_second_apply)

    readme_after_second_apply = File.read(File.join(gem_root, "README.md"))
    expect(readme_after_second_apply).to include("# 💎 Dummy::Gem")
    expect(readme_after_second_apply).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis from the scaffolded project\./)

    rakefile_after_second_apply = File.read(File.join(gem_root, "Rakefile"))
    expect(rakefile_after_second_apply).to include('require "bundler/gem_tasks"')
    expect(rakefile_after_second_apply).to include('require "kettle/dev"')
    expect(rakefile_after_second_apply).to include('Kettle::Dev.install_tasks unless Kettle::Dev::RUNNING_AS == "rake"')
    expect(rakefile_after_second_apply).to include("rescue LoadError")
    expect(rakefile_after_second_apply.scan('task("kettle:jem:selftest")').size).to eq(1)
    expect(rakefile_after_second_apply.scan('task("build:generate_checksums")').size).to eq(1)
  end
end
