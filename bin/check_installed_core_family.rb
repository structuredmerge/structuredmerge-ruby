#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the configured Ruby family as gems, then prove the complete runtime
# graph and the explicitly selected Rust parser from a fresh GEM_HOME.
require "bundler"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "rbconfig"
require "rubygems/package"
require "set"
require "tmpdir"
require "yaml"
require_relative "core_family_checkpoint"

options = {run_family_tests: false}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: check_installed_core_family.rb --core-gem LOCAL_GEM [--run-family-tests] [--only GEMS]"
  opts.on("--core-gem PATH") { |value| options[:core_gem] = value }
  opts.on("--run-family-tests") { options[:run_family_tests] = true }
  opts.on("--checkpoint-dir PATH", "Resume verified member suites from this directory") { |value| options[:checkpoint_dir] = value }
  opts.on("--only GEMS", "Run selected member suites (partial verification)") { |value| options[:only] = value.split(",").map(&:strip) }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
begin
  parser.parse!
  raise OptionParser::MissingArgument, "--core-gem" if options[:core_gem].to_s.empty?
  raise OptionParser::InvalidArgument, "--only requires --run-family-tests" if options[:only] && !options[:run_family_tests]
  raise OptionParser::InvalidArgument, "--checkpoint-dir requires --run-family-tests" if options[:checkpoint_dir] && !options[:run_family_tests]
  raise OptionParser::InvalidArgument, "--only must name at least one member" if options[:only]&.empty? || options[:only]&.any?(&:empty?)
  raise OptionParser::InvalidArgument, ARGV.join(" ") unless ARGV.empty?
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 1
end
run_family_tests = options.fetch(:run_family_tests)

root = File.expand_path("..", __dir__)
if run_family_tests
  # Member suites and mise trust mutate their checkout. Only the wrapper's
  # disposable linked worktree may run them; never touch the caller's checkout.
  git_dir, git_status = Open3.capture2("git", "-C", root, "rev-parse", "--absolute-git-dir")
  common_dir, common_status = Open3.capture2("git", "-C", root, "rev-parse", "--git-common-dir")
  disposable = ENV["STRUCTUREDMERGE_GATE_WORKTREE"] == File.realpath(root) &&
    git_status.success? && common_status.success? &&
    File.realpath(git_dir.strip) != File.realpath(File.expand_path(common_dir.strip, root))
  abort "family suites require the disposable worktree created by bin/test_installed_core_family.rb" unless disposable
end
core_gem = File.realpath(options.fetch(:core_gem))
core_package = Gem::Package.new(core_gem)
core_package.verify
core_spec = core_package.spec
abort "expected structuredmerge-core archive" unless core_spec.name == "structuredmerge-core"

family = YAML.safe_load(File.read(File.join(root, ".kettle-family.yml")), aliases: true)
member_roots = family.fetch("members").fetch("roots").map { |path| File.expand_path(path, root) }
abort "no family members configured" if member_roots.empty?
members = member_roots.map do |member_root|
  gemspecs = Dir.glob(File.join(member_root, "*.gemspec"))
  abort "expected one gemspec in #{member_root}" unless gemspecs.one?

  spec = Gem::Specification.load(gemspecs.fetch(0))
  abort "could not load gemspec #{gemspecs.fetch(0)}" unless spec
  [member_root, gemspecs.fetch(0), spec]
end

all_names = members.map { |entry| entry.last.name }
selected_names = options[:only] || all_names
unknown_names = selected_names - all_names
abort "unknown family members: #{unknown_names.join(', ')}" unless unknown_names.empty?
selected_names = selected_names.uniq

tree_haver = members.map(&:last).find { |spec| spec.name == "tree_haver" }
abort "tree_haver is not in the configured family" unless tree_haver
unless tree_haver.runtime_dependencies.any? { |dependency| dependency.name == "structuredmerge-core" }
  abort "tree_haver does not declare structuredmerge-core as a runtime dependency"
end

Bundler.with_unbundled_env do
  Dir.mktmpdir("structuredmerge-installed-family-") do |stage|
    package_dir = File.join(stage, "packages")
    gem_home = File.join(stage, "gem-home")
    consumer = File.join(stage, "consumer")
    FileUtils.mkdir_p([package_dir, gem_home, consumer])

    family_archives = members.map do |member_root, gemspec, spec|
      archive = File.join(package_dir, "#{spec.full_name}.gem")
      command = [RbConfig.ruby, "-S", "gem", "build", "--norc", File.basename(gemspec), "--output", archive]
      # Avoid inheriting the developer's RubyGems config or signing credentials.
      build_env = {
        "GEMRC" => "/dev/null",
        "SKIP_GEM_SIGNING" => "true",
        "GEM_CERT_PATH" => nil, "GEM_SIGNING_KEY" => nil
      }
      output, status = Open3.capture2e(build_env, *command, chdir: member_root)
      unless status.success?
        warn output
        raise "gem build failed for #{spec.full_name}"
      end
      abort "gem build omitted #{archive}" unless File.file?(archive)
      archive
    end

    install_env = {
      "GEM_HOME" => gem_home, "GEM_PATH" => gem_home,
      "RUBYLIB" => nil, "RUBYOPT" => nil,
      "BUNDLE_GEMFILE" => nil, "BUNDLE_PATH" => nil,
      "BUNDLE_APP_CONFIG" => nil, "BUNDLE_USER_HOME" => nil,
      "STRUCTUREDMERGE_DEV" => nil
    }
    ([core_gem] + family_archives).each do |archive|
      output, status = Open3.capture2e(install_env, RbConfig.ruby, "-S", "gem", "install",
        "--local", "--no-document", "--ignore-dependencies", archive)
      unless status.success?
        warn output
        raise "local gem installation failed for #{File.basename(archive)}"
      end
    end

    gemfile = File.join(consumer, "Gemfile")
    dependencies = members.map { |_dir, _gemspec, spec| %(gem #{spec.name.inspect}, #{spec.version.to_s.inspect}) }
    dependencies << %(gem "structuredmerge-core", #{core_spec.version.to_s.inspect})
    File.write(gemfile, "source \"https://rubygems.org\"\n#{dependencies.join("\n")}\n")
    bundle_env = install_env.merge(
      "BUNDLE_GEMFILE" => gemfile,
      "BUNDLE_APP_CONFIG" => File.join(consumer, ".bundle"),
      "BUNDLE_USER_HOME" => File.join(consumer, ".bundle-user")
    )
    output, status = Open3.capture2e(bundle_env, RbConfig.ruby, "-S", "bundle", "install", "--jobs", "2",
      chdir: consumer)
    unless status.success?
      warn output
      raise "installed family dependency resolution failed"
    end

    expected = members.map { |_dir, _gemspec, spec| [spec.name, spec.version.to_s] }
    expected << ["structuredmerge-core", core_spec.version.to_s]
    contract = File.join(consumer, "verify.rb")
    File.write(contract, <<~'VERIFY')
      require "json"
      require "rubygems"
      expected = JSON.parse(File.read(ARGV.fetch(0)))
      gem_home = File.realpath(ENV.fetch("GEM_HOME"))
      inside_home = ->(path) { File.realpath(path).start_with?(gem_home + File::SEPARATOR) }
      expected.each do |name, version|
        spec = Gem.loaded_specs.fetch(name) { abort "#{name} is missing from the installed bundle" }
        abort "#{name} has version #{spec.version}, expected #{version}" unless spec.version.to_s == version
        abort "#{name} escaped GEM_HOME: #{spec.full_gem_path}" unless inside_home.call(spec.full_gem_path)
      end
      core = Gem.loaded_specs.fetch("structuredmerge-core")
      require "structuredmerge_core"
      require "tree_haver"
      require "tree_haver/backends/rust_tslp"
      abort "typed core operation API is missing" unless StructuredmergeCore.respond_to?(:execute_operation)
      abort "Rust TSLP backend is unavailable: #{TreeHaver::Backends::RustTslp.unavailable_reason}" unless
        TreeHaver::Backends::RustTslp.available?
      tree = TreeHaver.with_backend(:rust_tslp) do
        TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
        TreeHaver.parser_for(:json).parse("{\"answer\": 42}\n")
      end
      abort "installed Rust parser provenance is wrong" unless
        tree.provenance.dig("backend_ref", "id") == "tree_haver.rust_tslp.json" &&
        tree.provenance.fetch("runtime") == "rust"
      native_paths = $LOADED_FEATURES.select { |path| path.include?("structuredmerge_core_rb") }
      abort "native extension did not load from GEM_HOME" unless native_paths.any? { |path| inside_home.call(path) }
      puts JSON.generate({
        "status" => "passed", "family_gems" => expected.length - 1,
        "core_version" => core.version.to_s, "installed_gem_home" => gem_home,
        "rust_parser" => tree.provenance.dig("backend_ref", "id"),
        "native_extension_paths" => native_paths
      })
    VERIFY
    expected_path = File.join(consumer, "expected.json")
    File.write(expected_path, JSON.generate(expected))
    output, status = Open3.capture2e(bundle_env, RbConfig.ruby, "-S", "bundle", "exec",
      RbConfig.ruby, contract, expected_path, chdir: consumer)
    puts output
    raise "installed consumer verification failed" unless status.success?

    if run_family_tests
      core_consumers = Set.new(["structuredmerge-core"])
      loop do
        added = members.filter_map do |_member_root, _gemspec, spec|
          next if core_consumers.include?(spec.name)
          next unless spec.runtime_dependencies.any? { |dependency| core_consumers.include?(dependency.name) }

          spec.name
        end
        break if added.empty?

        core_consumers.merge(added)
      end
      consumer_names = members.filter_map { |_dir, _gemspec, spec| spec.name if core_consumers.include?(spec.name) }
      family_config_path = File.join(stage, "kettle-family.yml")
      family_config = YAML.safe_load(File.read(File.join(root, ".kettle-family.yml")), aliases: true)
      family_config["test"] ||= {}
      family_config["test"]["monorepo_mode"] = "worktrees"
      # Kettle Family's default string runs through a login shell, which may
      # replace mise's selected Ruby PATH. An argv preserves the same command.
      family_config["commands"] ||= {}
      family_config["commands"]["test"] ||= ["bundle", "exec", "kettle-test"]
      File.write(family_config_path, YAML.dump(family_config))
      checker = File.join(stage, "verify-installed-core.rb")
      File.write(checker, <<~'RUBY')
        require "rubygems"
        member = File.basename(Dir.pwd)
        members = ENV.fetch("STRUCTUREDMERGE_FAMILY_MEMBERS").split(",")
        test_process = ENV.key?("STRUCTUREDMERGE_FAMILY_TEST_LOG") &&
          ENV["BUNDLE_GEMFILE"] &&
          File.expand_path(ENV["BUNDLE_GEMFILE"], Dir.pwd) == File.join(Dir.pwd, "Gemfile")
        if members.include?(member) && test_process
          ENV["BUNDLE_GEMFILE"] = File.join(Dir.pwd, "Gemfile")
          require "bundler/setup"
          File.open(ENV.fetch("STRUCTUREDMERGE_FAMILY_TEST_LOG"), "a") { |file| file.puts(member) }
          consumers = ENV.fetch("STRUCTUREDMERGE_CORE_CONSUMERS").split(",")
          if consumers.include?(member)
            home = File.realpath(ENV.fetch("STRUCTUREDMERGE_EXPECT_GEM_HOME"))
            spec = Gem.loaded_specs["structuredmerge-core"] || abort("structuredmerge-core is not in this consumer bundle")
            abort("wrong core version: #{spec.version}") unless spec.version.to_s == ENV.fetch("STRUCTUREDMERGE_EXPECT_VERSION")
            path = File.realpath(spec.full_gem_path)
            abort("consumer loaded core outside clean GEM_HOME: #{path}") unless path.start_with?(home + File::SEPARATOR)
            require "structuredmerge_core"
            abort("typed core operation API is unavailable") unless StructuredmergeCore.respond_to?(:execute_operation)
            File.open(ENV.fetch("STRUCTUREDMERGE_CORE_TEST_LOG"), "a") do |file|
              file.puts("#{member}\t#{spec.version}\t#{path}")
            end
          end
        end
      RUBY
      system_gem_paths = Gem.path.reject do |path|
        Dir.glob(File.join(path, "specifications", "structuredmerge-core-*.gemspec")).any?
      end
      common_dir, common_dir_status = Open3.capture2("git", "-C", root, "rev-parse", "--git-common-dir")
      raise "cannot resolve original Ruby checkout from test worktree" unless common_dir_status.success?

      workspace_root = File.dirname(File.expand_path(common_dir.strip, root))
      default_kettle_dev_root = File.expand_path("../../kettle-dev", workspace_root)
      kettle_dev_root = ENV.fetch("KETTLE_DEV_DEV") { File.directory?(default_kettle_dev_root) ? default_kettle_dev_root : "false" }
      source_gem_home = system_gem_paths.find { |path| File.directory?(File.join(path, "bundler", "gems")) }
      raise "could not find the existing Bundler git checkout cache" unless source_gem_home

      bundled_git_cache = File.join(gem_home, "bundler", "gems")
      FileUtils.mkdir_p(File.dirname(bundled_git_cache))
      FileUtils.ln_s(File.join(source_gem_home, "bundler", "gems"), bundled_git_cache)

      test_env = {
        "GEM_HOME" => gem_home,
        "GEM_PATH" => ([gem_home] + system_gem_paths).join(File::PATH_SEPARATOR),
        # Kettle Family starts member commands with a clean environment. Keep
        # this gate's Ruby executable available when GEM_HOME is isolated.
        "PATH" => ([File.dirname(RbConfig.ruby), ENV["PATH"]].compact.join(File::PATH_SEPARATOR)),
        "STRUCTUREDMERGE_DEV" => File.join(root, "gems"),
        "STRUCTUREDMERGE_CORE_DEV" => "false",
        "STRUCTUREDMERGE_EXPECT_GEM_HOME" => gem_home,
        "STRUCTUREDMERGE_EXPECT_VERSION" => core_spec.version.to_s,
        "STRUCTUREDMERGE_CORE_CONSUMERS" => consumer_names.join(","),
        "STRUCTUREDMERGE_FAMILY_MEMBERS" => members.map { |entry| entry.last.name }.join(","),
        "STRUCTUREDMERGE_FAMILY_TEST_LOG" => File.join(stage, "family-tests.log"),
        "STRUCTUREDMERGE_CORE_TEST_LOG" => File.join(stage, "installed-core-tests.log"),
        "K_JEM_TEMPLATING" => "true",
        "KETTLE_TEST_TURBO_PROCESSES" => ENV.fetch("KETTLE_TEST_TURBO_PROCESSES", "2"),
        "KETTLE_DEV_DEV" => kettle_dev_root,
        "RUBYOPT" => "-r#{checker}"
      }
      report_path = File.join(stage, "family-test-report.json")
      checkpoint = if options[:checkpoint_dir]
        head, head_status = Open3.capture2("git", "-C", root, "rev-parse", "HEAD")
        raise "cannot identify family revision" unless head_status.success?
        CoreFamilyCheckpoint.new(
          directory: File.expand_path(options.fetch(:checkpoint_dir)),
          identity: {
            "schema" => 1, "family_revision" => head.strip,
            "core_sha256" => Digest::SHA256.file(core_gem).hexdigest,
            "ruby_engine" => RUBY_ENGINE, "ruby_version" => RUBY_VERSION,
            "ruby_platform" => RUBY_PLATFORM
          },
          members: all_names
        )
      end
      puts "Family checkpoint: #{checkpoint.path}" if checkpoint
      pending_names = selected_names - (checkpoint&.completed || [])
      command_env = test_env.merge("BUNDLE_GEMFILE" => "Gemfile")
      mise_configs = [File.join(root, "mise.toml")] + member_roots.filter_map do |member_root|
        path = File.join(member_root, "mise.toml")
        path if File.file?(path)
      end
      trusted_configs = []
      begin
        mise_configs.each do |config_path|
          trust_output, trust_status = Open3.capture2e(test_env, "mise", "trust", config_path, chdir: root)
          puts trust_output
          raise "could not trust disposable family config #{config_path}" unless trust_status.success?
          trusted_configs << config_path
        end
        pending_names.each_with_index do |name, index|
          puts "Testing #{name} (#{index + 1}/#{pending_names.length})"
          $stdout.flush
          command = [RbConfig.ruby, "-S", "bundle", "exec", "kettle-family", "test",
            "--execute", "--jobs", "1", "--only=#{name}", "--report=#{report_path}", "--config=#{family_config_path}"]
          command_env.each { |key, value| command << "--env=#{key}=#{value}" }
          output, status = Open3.capture2e(test_env, *command, chdir: root)
          puts output
          raise "installed-core suite failed: #{name}" unless status.success?
          raise "Kettle Family did not write its test report" unless File.file?(report_path)
          results = JSON.parse(File.read(report_path)).fetch("results")
          successful = results.select { |result| result["success"] && !result["skipped"] }.map { |result| result.fetch("member") }
          raise "family suite result mismatch for #{name}: #{successful.inspect}" unless successful == [name]
          test_log = File.join(stage, "family-tests.log")
          tested = File.file?(test_log) ? File.readlines(test_log, chomp: true) : []
          raise "family suite did not start: #{name}" unless tested.include?(name)
          if consumer_names.include?(name)
            core_log = File.join(stage, "installed-core-tests.log")
            verified = File.file?(core_log) ? File.readlines(core_log, chomp: true).map { |line| line.split("\t", 2).first } : []
            raise "installed core was not verified by #{name}" unless verified.include?(name)
          end
          checkpoint&.record(name)
        end
      ensure
        trusted_configs.each do |config_path|
          untrust_output, untrust_status = Open3.capture2e(test_env, "mise", "trust", "--untrust", config_path, chdir: root)
          warn untrust_output unless untrust_status.success?
        end
      end
      completed = checkpoint ? checkpoint.completed : pending_names
      full = options[:only].nil? && (all_names - completed).empty?
      puts JSON.generate({
        "family_suites" => completed.length,
        "suite_mode" => (full ? "all-members" : "partial-members"),
        "selected_members" => selected_names,
        "checkpoint" => checkpoint&.path
      })
    end
  end
end
