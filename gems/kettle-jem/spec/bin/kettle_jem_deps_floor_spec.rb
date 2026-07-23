# frozen_string_literal: true

require "open3"

load File.expand_path("../../bin/kettle-jem-deps-floor", __dir__)

RSpec.describe KettleJemDepsFloor do
  let(:project_root) { Dir.mktmpdir }
  let(:resolver) do
    FakeDepsFloorResolver.new(
      "example_dep" => %w[1.2.3 1.2.9 1.3.0 2.0.0],
      "embedded_dep" => %w[4.5.6 4.5.7],
      "other_dep" => %w[3.0.0 3.0.1 3.1.0],
      "nomono" => %w[1.0.8 1.0.9],
      "yard-timekeeper" => %w[0.2.3 0.2.4]
    )
  end

  before do
    stub_const(
      "FakeDepsFloorResolver",
      Class.new do
        def initialize(versions)
          @versions = versions
          @requests = []
        end

        attr_reader :requests

        def versions(gem_name, requirements: nil)
          @requests << [gem_name, requirements]
          requirement = Gem::Requirement.new(requirements || [">= 0"])
          Array(@versions.fetch(gem_name)).select do |version|
            requirement.satisfied_by?(Gem::Version.new(version))
          end.map { |version| {number: version} }
        end
      end
    )
    stub_const(
      "#{described_class}::SOURCE_GLOBS",
      [
        "template/valid.gemfile.example",
        "template/tokenized.gemspec.example",
        "template/local.gemfile.example",
        "template/documentation.gemfile.example",
        "lib/embedded.rb"
      ]
    )
    stub_const(
      "#{described_class}::EXTRA_SOURCE_FILES",
      []
    )
    write_file("template/valid.gemfile.example", <<~RUBY)
      # frozen_string_literal: true

      gem "example_dep", "~> 1.2", ">= 1.2.3", require: false
      spec.add_development_dependency("other_dep", "~> 3.0", ">= 3.0.0")
      # gem "ignored_dep", "~> 1.0", ">= 1.0.0"
    RUBY
    write_file("template/tokenized.gemspec.example", <<~RUBY)
      # frozen_string_literal: true

      {KJ|TOKEN}
      spec.add_development_dependency("{KJ|TOKENIZED_GEM}", "~> 9.0", ">= 9.0.0")
      spec.add_development_dependency("example_dep", "~> 1.2", ">= 1.2.3")
    RUBY
    write_file("template/local.gemfile.example", <<~RUBY)
      # frozen_string_literal: true

      require "nomono/bundler"
    RUBY
    write_file("template/documentation.gemfile.example", <<~RUBY)
      # frozen_string_literal: true

      gem "yard-timekeeper", "~> 0.2", ">= 0.2.3", require: false
    RUBY
    write_file("lib/embedded.rb", <<~RUBY)
      # frozen_string_literal: true

      {name: "embedded_dep", source: %(gem "embedded_dep", "~> 4.5", ">= 4.5.6"\\n)}
      nomono_requirements = ["~> 1.0", ">= 1.0.8"]
    RUBY
  end

  after do
    FileUtils.rm_rf(project_root)
  end

  def write_file(relative_path, content)
    path = File.join(project_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def read_file(relative_path)
    File.read(File.join(project_root, relative_path))
  end

  def init_git_repository
    run_git("init", project_root)
    run_git("-C", project_root, "config", "user.name", "Spec User")
    run_git("-C", project_root, "config", "user.email", "spec@example.com")
    run_git("-C", project_root, "add", ".")
    run_git("-C", project_root, "commit", "-m", "initial")
  end

  def run_git(*args)
    _stdout, stderr, status = Open3.capture3("git", *args)
    raise stderr unless status.success?
  end

  def git_status
    stdout, _stderr, status = Open3.capture3("git", "-C", project_root, "status", "--short")
    raise "git status failed" unless status.success?

    stdout
  end

  def git_subject
    stdout, _stderr, status = Open3.capture3("git", "-C", project_root, "log", "-1", "--format=%s")
    raise "git log failed" unless status.success?

    stdout.chomp
  end

  it "defaults the project root to the gem root relative to the bin script" do
    options = described_class.parse_options([])

    expect(options.fetch(:project_root)).to eq(File.expand_path("../..", __dir__))
  end

  it "allows dependency floor writes to opt out of default commits" do
    options = described_class.parse_options(%w[--write --no-commit])

    expect(options).to include(write: true, commit: false)
  end

  it "reports patch updates without writing files" do
    result = described_class.new(project_root: project_root, resolver: resolver, options: {upgrade: "patch"}).run

    expect(result[:updates]).to eq(6)
    expect(result[:updated_dependencies]).to eq(%w[embedded_dep example_dep nomono other_dep yard-timekeeper])
    expect(result[:planned_changes]).to include(
      hash_including(
        name: "example_dep",
        relative_path: "template/valid.gemfile.example",
        current_floor: "1.2.3",
        new_floor: "1.2.9",
        new_pessimistic: "~> 1.2"
      )
    )
    expect(result[:planned_changes]).to include(
      hash_including(
        name: "yard-timekeeper",
        relative_path: "template/documentation.gemfile.example",
        current_floor: "0.2.3",
        new_floor: "0.2.4"
      )
    )
    expect(read_file("template/valid.gemfile.example")).to include('gem "example_dep", "~> 1.2", ">= 1.2.3"')
  end

  it "updates parseable Ruby and tokenized template files when writing" do
    result = described_class.new(project_root: project_root, resolver: resolver, options: {write: true, upgrade: "minor"}).run

    expect(result[:updates]).to eq(6)
    expect(result[:commit]).to include(status: "unavailable", reason: "not_git_repository")
    expect(read_file("lib/embedded.rb")).to include('{name: "embedded_dep", source: %(gem "embedded_dep", "~> 4.5", ">= 4.5.7"\\n)}')
    expect(read_file("lib/embedded.rb")).to include('nomono_requirements = ["~> 1.0", ">= 1.0.9"]')
    expect(read_file("template/valid.gemfile.example")).to include('gem "example_dep", "~> 1.3", ">= 1.3.0"')
    expect(read_file("template/valid.gemfile.example")).to include('spec.add_development_dependency("other_dep", "~> 3.1", ">= 3.1.0")')
    expect(read_file("template/valid.gemfile.example")).to include('# gem "ignored_dep", "~> 1.0", ">= 1.0.0"')
    expect(read_file("template/tokenized.gemspec.example")).to include('spec.add_development_dependency("example_dep", "~> 1.3", ">= 1.3.0")')
    expect(read_file("template/tokenized.gemspec.example")).to include('spec.add_development_dependency("{KJ|TOKENIZED_GEM}", "~> 9.0", ">= 9.0.0")')
    expect(read_file("template/local.gemfile.example")).to include('require "nomono/bundler"')
    expect(read_file("template/documentation.gemfile.example")).to include('gem "yard-timekeeper", "~> 0.2", ">= 0.2.4", require: false')
  end

  it "commits written updates by default inside git repositories" do
    init_git_repository

    result = described_class.new(project_root: project_root, resolver: resolver, options: {write: true, upgrade: "minor"}).run

    expect(result[:commit]).to include(status: "committed")
    expect(result[:commit].fetch(:files)).to include(
      "lib/embedded.rb",
      "template/documentation.gemfile.example",
      "template/tokenized.gemspec.example",
      "template/valid.gemfile.example"
    )
    expect(git_status).to eq("")
    expect(git_subject).to eq("⬆️ Raise kettle-jem dependency floors")
  end

  it "leaves written updates uncommitted when commit is disabled" do
    init_git_repository

    result = described_class.new(project_root: project_root, resolver: resolver, options: {write: true, commit: false, upgrade: "minor"}).run

    expect(result[:commit]).to be_nil
    expect(git_status).to include(" M lib/embedded.rb")
  end

  it "refuses to commit when target files were already dirty before writing" do
    init_git_repository
    write_file("template/valid.gemfile.example", "#{read_file("template/valid.gemfile.example")}\n# local edit\n")

    expect {
      described_class.new(project_root: project_root, resolver: resolver, options: {write: true, upgrade: "minor"}).run
    }.to raise_error(RuntimeError, /target files were already dirty/)
  end

  it "allows the caller to select major updates" do
    result = described_class.new(project_root: project_root, resolver: resolver, options: {write: true, upgrade: "major"}).run

    expect(result[:planned_changes]).to include(
      hash_including(
        name: "example_dep",
        new_floor: "2.0.0",
        new_pessimistic: "~> 2.0"
      )
    )
    expect(read_file("template/valid.gemfile.example")).to include('gem "example_dep", "~> 2.0", ">= 2.0.0"')
  end

  it "fails check mode when managed floors are stale" do
    expect {
      described_class.new(project_root: project_root, resolver: resolver, options: {check: true}).run
    }.to raise_error(RuntimeError, /Managed dependency floors are stale/)
  end

  it "reports discovered dependencies without requiring an allow-list" do
    result = described_class.new(project_root: project_root, resolver: resolver, options: {upgrade: "patch"}).run

    expect(result[:discovered_dependencies]).to eq(%w[embedded_dep example_dep nomono other_dep yard-timekeeper])
  end

  it "rejects unsupported upgrade levels" do
    expect {
      described_class.new(project_root: project_root, resolver: resolver, options: {upgrade: "micro"}).run
    }.to raise_error(ArgumentError, /Invalid --upgrade value/)
  end
end
