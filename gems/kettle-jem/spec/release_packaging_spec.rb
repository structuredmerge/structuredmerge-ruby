# frozen_string_literal: true

require "open3"
require "rubygems/package"

RSpec.describe Kettle::Jem do
  let(:gem_root) { Pathname(__dir__).join("..").expand_path }

  def load_gemspec(gem_root)
    Gem::Specification.load(gem_root.join("kettle-jem.gemspec").to_s)
  end

  def clean_subprocess_env(overrides = {})
    ENV.to_h.tap do |env|
      env.keys.grep(/\ABUNDLE_/).each { |key| env[key] = nil }
      env.keys.grep(/\ABUNDLER_/).each { |key| env[key] = nil }
      %w[RUBYLIB RUBYOPT].each { |key| env[key] = nil }
      env["BUNDLE_GEMFILE"] = ENV["BUNDLE_GEMFILE"] if ENV["BUNDLE_GEMFILE"]
    end.merge(overrides)
  end

  it "packages runtime template assets used by packaged template application" do
    spec = load_gemspec(gem_root)
    gemspec_source = File.read(gem_root.join("kettle-jem.gemspec"))
    files = spec.files
    expected_template_files = Dir.glob(gem_root.join("lib/kettle/jem/templates/**/*").to_s, File::FNM_DOTMATCH)
      .filter_map do |path|
        next unless File.file?(path) && ![".", ".."].include?(File.basename(path))

        Pathname(path).relative_path_from(gem_root).to_s
      end

    expect(gemspec_source).to include("Module.new.tap")
    expect(gemspec_source).to include("spec.metadata[\"news_uri\"]")
    expect(gemspec_source).to include("spec.rdoc_options +=")
    expect(spec.summary).to eq("🔮 Gem templating engine using AST-based merging and configurable token resolution.")
    expect(spec.homepage).to eq("https://github.com/structuredmerge/structuredmerge-ruby")
    expect(spec.metadata["homepage_uri"]).to eq("https://structuredmerge.org")
    expect(spec.executables).to eq(["kettle-jem"])
    changelog_dependency = spec.runtime_dependencies.find { |dependency| dependency.name == "kettle-changelog" }
    expect(changelog_dependency.requirement).to eq(Gem::Requirement.new(["~> 1.0", ">= 1.0.1"]))
    expect(File.executable?(gem_root.join("exe/kettle-jem"))).to be(true)
    expect(File.executable?(gem_root.join("bin/kettle-jem-deps-floor"))).to be(true)
    expect(File.executable?(gem_root.join("bin/kettle-jem-workflow-pins"))).to be(true)
    expect(expected_template_files).not_to be_empty
    expect(files).to include(*expected_template_files)
    expect(files).not_to include("bin/kettle-jem-deps-floor")
    expect(files).not_to include("bin/kettle-jem-workflow-pins")
    expect(files).to include(
      "lib/kettle/jem/tasks.rb",
      "lib/kettle/jem/rakelib/prepare.rake",
      "lib/kettle/jem/rakelib/template.rake",
      "lib/kettle/jem/rakelib/install.rake",
      "lib/kettle/jem/rakelib/selftest.rake"
    )
    expect(files).not_to include("certs/pboling.pem")
    expect(spec.extra_rdoc_files).to be_empty
  end

  it "builds an artifact that can run kettle-jem from unpacked package files" do
    tmp_root = gem_root.join("spec/tmp/release-packaging")
    FileUtils.rm_rf(tmp_root)
    FileUtils.mkdir_p(tmp_root)
    gem_path = tmp_root.join("kettle-jem.gem")

    stdout, stderr, status = Open3.capture3(
      clean_subprocess_env("SKIP_GEM_SIGNING" => "1"),
      Gem.ruby,
      "-rbundler/setup",
      "-S",
      "gem",
      "build",
      "kettle-jem.gemspec",
      "--output",
      gem_path.to_s,
      chdir: gem_root.to_s
    )
    expect(status.success?).to be(true), "gem build failed\nstdout=#{stdout}\nstderr=#{stderr}"

    package = Gem::Package.new(gem_path.to_s)
    package_spec = package.spec
    expected_template = "lib/kettle/jem/templates/.structuredmerge/kettle-jem.yml.example"
    expect(package_spec.executables).to include("kettle-jem")
    expect(package_spec.files).to include(expected_template)
    expect(package_spec.files).to include("lib/kettle/jem/rakelib/selftest.rake")

    unpack_root = tmp_root.join("unpacked")
    FileUtils.mkdir_p(unpack_root)
    package.extract_files(unpack_root.to_s)
    exe = unpack_root.join("exe/kettle-jem")
    expect(File).to exist(exe)
    expect(File).to exist(unpack_root.join(expected_template))
    expect(File).to exist(unpack_root.join("lib/kettle/jem/rakelib/selftest.rake"))

    version_stdout, version_stderr, version_status = Open3.capture3(
      clean_subprocess_env("RUBYLIB" => unpack_root.join("lib").to_s),
      Gem.ruby,
      "-rbundler/setup",
      exe.to_s,
      "version"
    )
    expect(version_status.success?).to be(true), "artifact executable failed\nstdout=#{version_stdout}\nstderr=#{version_stderr}"
    expect(version_stdout).to eq("#{Kettle::Jem::Version::VERSION}\n")

    help_stdout, help_stderr, help_status = Open3.capture3(
      clean_subprocess_env("RUBYLIB" => unpack_root.join("lib").to_s),
      Gem.ruby,
      "-rbundler/setup",
      exe.to_s,
      "--help"
    )
    expect(help_status.success?).to be(true), "artifact help failed\nstdout=#{help_stdout}\nstderr=#{help_stderr}"
    expect(help_stdout).to include("kettle-jem install")
    expect(help_stdout).to include("kettle-jem selftest")

    project_root = tmp_root.join("project")
    FileUtils.mkdir_p(project_root)
    File.write(project_root.join("example.gemspec"), <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "example"
        spec.summary = "Example gem"
        spec.required_ruby_version = ">= 4.0"
      end
    RUBY
    plan_stdout, plan_stderr, plan_status = Open3.capture3(
      clean_subprocess_env("RUBYLIB" => unpack_root.join("lib").to_s),
      Gem.ruby,
      "-rbundler/setup",
      exe.to_s,
      "plan",
      project_root.to_s,
      "--json"
    )
    expect(plan_status.success?).to be(true), "artifact plan failed\nstdout=#{plan_stdout}\nstderr=#{plan_stderr}"
    expect(JSON.parse(plan_stdout).fetch("mode")).to eq("plan")
  end
end
