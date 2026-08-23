# frozen_string_literal: true

require "open3"
require "rbconfig"
require "stringio"

load File.expand_path("../../bin/kettle-jem-deps-floor", __dir__)

RSpec.describe KettleJemDepsFloor do
  let(:project_root) { Dir.mktmpdir }
  let(:resolver) do
    FakeDepsFloorResolver.new(
      "example_dep" => %w[1.2.3 1.2.9 1.3.0 2.0.0],
      "bare_embedded_dep" => %w[5.6.7 5.6.8],
      "embedded_dep" => %w[4.5.6 4.5.7],
      "other_dep" => %w[3.0.0 3.0.1 3.1.0],
      "kettle-dev" => %w[2.3.7 2.5.8],
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

        def versions(gem_name, include_prerelease: false, requirements: nil)
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
    allow(Kettle::Jem::MaintenanceChangelog).to receive(:upsert_unreleased_entry).and_return(status: "updated")
    write_file("template/valid.gemfile.example", <<~RUBY)
      # frozen_string_literal: true

      gem "example_dep", "~> 1.2", ">= 1.2.3", require: false
      spec.add_development_dependency("other_dep", "~> 3.0", ">= 3.0.0")
      spec.add_development_dependency("kettle-dev", "~> 2.3", ">= 2.3.7")
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
      %(gem "bare_embedded_dep", "~> 5.6", ">= 5.6.7"\\n)
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

  it "keeps the repository-local executable inside its bundle" do
    _stdout, stderr, status = Open3.capture3(
      {},
      RbConfig.ruby,
      File.expand_path("../../bin/kettle-jem-deps-floor", __dir__),
      "--help",
      chdir: File.expand_path("../..", __dir__)
    )

    expect(status).to be_success, stderr
  end

  it "allows dependency floor writes to opt out of default commits" do
    options = described_class.parse_options(%w[--write --no-commit --no-changelog])

    expect(options).to include(write: true, commit: false, changelog: false)
  end

  it "enables changelog entries by default" do
    expect(described_class.parse_options([])).to include(changelog: true)
  end

  it "uses a thirty-day persistent RubyGems version cache when live lookups fail", freeze: Time.utc(2026, 7, 30, 12, 0, 0) do
    cache_path = File.join(project_root, "deps-floor-cache.json")
    File.write(
      cache_path,
      JSON.generate(
        "versions" => {
          "version_gem" => {
            "cached_at" => "2026-07-01T12:00:00Z",
            "entries" => [{"number" => "1.1.14"}]
          }
        }
      )
    )
    delegate = instance_double(Kettle::Jem::RubyGemsResolver)
    allow(delegate).to receive(:versions).and_raise(Kettle::Jem::Error, "RubyGems API error for version_gem: 500")
    resolver = described_class::PersistentRubyGemsResolver.new(
      delegate: delegate,
      cache_path: cache_path,
      marker_path: File.join(project_root, "missing-marker.json")
    )

    versions = resolver.versions("version_gem", requirements: [">= 1.0"])

    expect(versions).to eq([{number: "1.1.14"}])
    expect(delegate).not_to have_received(:versions)
  end

  it "refreshes only gems with fresh kettle-release markers while keeping untouched gems cached", freeze: Time.utc(2026, 7, 30, 12, 0, 0) do
    cache_path = File.join(project_root, "deps-floor-cache.json")
    marker_path = File.join(project_root, "rubygems-cache-bust.json")
    File.write(
      cache_path,
      JSON.generate(
        "versions" => {
          "released-gem" => {
            "cached_at" => "2026-07-01T12:00:00Z",
            "entries" => [{"number" => "1.0.0"}]
          },
          "untouched-gem" => {
            "cached_at" => "2026-07-01T12:00:00Z",
            "entries" => [{"number" => "2.0.0"}]
          }
        }
      )
    )
    File.write(
      marker_path,
      JSON.generate(
        "releases" => {
          "released-gem" => {"version" => "1.1.0", "released_at" => "2026-07-30T11:59:00Z"}
        }
      )
    )
    delegate = FakeDepsFloorResolver.new("released-gem" => %w[1.0.0 1.1.0])
    resolver = described_class::PersistentRubyGemsResolver.new(
      delegate: delegate,
      cache_path: cache_path,
      marker_path: marker_path
    )

    expect(resolver.versions("released-gem", requirements: [">= 1.0"])).to eq([{number: "1.0.0"}, {number: "1.1.0"}])
    expect(resolver.versions("untouched-gem", requirements: [">= 1.0"])).to eq([{number: "2.0.0"}])
    expect(delegate.requests).to eq([["released-gem", nil]])
  end

  it "reports patch updates without writing files" do
    result = described_class.new(project_root: project_root, resolver: resolver, options: {upgrade: "patch"}).run

    expect(result[:updates]).to eq(7)
    expect(result[:updated_dependencies]).to eq(%w[bare_embedded_dep embedded_dep example_dep nomono other_dep yard-timekeeper])
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

  it "prints dry-run mode and a write hint when stale floors are found" do
    out = StringIO.new
    err = StringIO.new
    allow(described_class).to receive(:new)
      .and_return(described_class.new(project_root: project_root, resolver: resolver, options: {upgrade: "patch"}))

    status = described_class.run(%w[--upgrade patch], out: out, err: err)

    expect(status).to eq(0)
    expect(out.string).to include("deps-floor: mode=dry-run upgrade=patch")
    expect(out.string).to include("hint: rerun with --write --upgrade patch")
    expect(err.string).to eq("")
  end

  it "updates parseable Ruby and tokenized template files when writing" do
    result = described_class.new(project_root: project_root, resolver: resolver, options: {write: true, upgrade: "minor"}).run

    expect(result[:updates]).to eq(8)
    expect(result[:commit]).to include(status: "unavailable", reason: "not_git_repository")
    expect(read_file("lib/embedded.rb")).to include('{name: "embedded_dep", source: %(gem "embedded_dep", "~> 4.5", ">= 4.5.7"\\n)}')
    expect(read_file("lib/embedded.rb")).to include('%(gem "bare_embedded_dep", "~> 5.6", ">= 5.6.8"\\n)')
    expect(read_file("lib/embedded.rb")).to include('nomono_requirements = ["~> 1.0", ">= 1.0.9"]')
    expect(read_file("template/valid.gemfile.example")).to include('gem "example_dep", "~> 1.3", ">= 1.3.0"')
    expect(read_file("template/valid.gemfile.example")).to include('spec.add_development_dependency("other_dep", "~> 3.1", ">= 3.1.0")')
    expect(read_file("template/valid.gemfile.example")).to include('spec.add_development_dependency("kettle-dev", "~> 2.5", ">= 2.5.8")')
    expect(read_file("template/valid.gemfile.example")).to include('# gem "ignored_dep", "~> 1.0", ">= 1.0.0"')
    expect(read_file("template/tokenized.gemspec.example")).to include('spec.add_development_dependency("example_dep", "~> 1.3", ">= 1.3.0")')
    expect(read_file("template/tokenized.gemspec.example")).to include('spec.add_development_dependency("{KJ|TOKENIZED_GEM}", "~> 9.0", ">= 9.0.0")')
    expect(read_file("template/local.gemfile.example")).to include('require "nomono/bundler"')
    expect(read_file("template/documentation.gemfile.example")).to include('gem "yard-timekeeper", "~> 0.2", ">= 0.2.4", require: false')
  end

  it "adds one Changed entry describing written dependency floor updates" do
    described_class.new(project_root: project_root, resolver: resolver, options: {write: true, commit: false, upgrade: "minor"}).run

    expect(Kettle::Jem::MaintenanceChangelog).to have_received(:upsert_unreleased_entry).with(
      project_root: project_root,
      section: "Changed",
      key: "kettle-jem-deps-floor",
      legacy_prefixes: ["Update kettle-jem template dependency floors:"],
      entry: kind_of(Proc)
    )
  end

  it "renders one nested dependency detail while preserving its earliest baseline" do
    tool = described_class.new(project_root: project_root, resolver: resolver)
    entry = tool.send(
      :dependency_changelog_entry,
      [{name: "kettle-family", current_floor_version: Gem::Version.new("1.2.51"), new_floor_version: Gem::Version.new("1.2.52")}],
      existing_entries: [{source: "- [kc] kettle-jem-deps-floor: Previous.\n  - kettle-family (>= 1.2.50 -> >= 1.2.51)\n"}]
    )

    expect(entry).to eq("Update kettle-jem template dependency floors:\n  - kettle-family (>= 1.2.50 -> >= 1.2.52)")
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

  it "commits written updates from a project nested below the git worktree root" do
    monorepo_root = Dir.mktmpdir
    nested_project_root = File.join(monorepo_root, "gems", "kettle-jem")
    FileUtils.mkdir_p(nested_project_root)
    begin
      described_class::SOURCE_GLOBS.each do |pattern|
        source = File.join(project_root, pattern)
        next unless File.file?(source)

        destination = File.join(nested_project_root, pattern)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
      end
      run_git("init", monorepo_root)
      run_git("-C", monorepo_root, "config", "user.name", "Spec User")
      run_git("-C", monorepo_root, "config", "user.email", "spec@example.com")
      run_git("-C", monorepo_root, "add", ".")
      run_git("-C", monorepo_root, "commit", "-m", "initial")

      result = described_class.new(project_root: nested_project_root, resolver: resolver, options: {write: true, upgrade: "minor"}).run
      stdout, _stderr, status = Open3.capture3("git", "-C", monorepo_root, "status", "--short")

      expect(result[:commit]).to include(status: "committed")
      expect(result[:commit].fetch(:files)).to include("lib/embedded.rb")
      expect(stdout).to eq("")
      expect(status).to be_success
    ensure
      FileUtils.rm_rf(monorepo_root)
    end
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

    expect(result[:discovered_dependencies]).to eq(%w[bare_embedded_dep embedded_dep example_dep kettle-dev nomono other_dep yard-timekeeper])
  end

  it "rejects unsupported upgrade levels" do
    expect {
      described_class.new(project_root: project_root, resolver: resolver, options: {upgrade: "micro"}).run
    }.to raise_error(ArgumentError, /Invalid --upgrade value/)
  end
end
