#!/usr/bin/env ruby
# frozen_string_literal: true

# Build a local platform gem, verify the packaged family runtime graph, then
# run every family suite against that installed artifact with core path wiring off.
require "bundler"
require "fileutils"
require "open3"
require "optparse"
require "rbconfig"
require "tmpdir"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: test_installed_core_family.rb [--only GEMS] (set STRUCTUREDMERGE_CORE_DEV)"
  opts.on("--checkpoint-dir PATH", "Store per-member results for resume") { |value| options[:checkpoint_dir] = value }
  opts.on("--only GEMS", "Run selected member suites (partial verification)") { |value| options[:only] = value }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
begin
  parser.parse!
  raise OptionParser::InvalidArgument, ARGV.join(" ") unless ARGV.empty?
  raise OptionParser::InvalidArgument, "--only must name at least one member" if options[:only] && options[:only].split(",").reject { |name| name.strip.empty? }.empty?
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 1
end

root = File.expand_path("..", __dir__)
core_root_value = ENV.fetch("STRUCTUREDMERGE_CORE_DEV", File.expand_path("../../structuredmerge", root))
abort "STRUCTUREDMERGE_CORE_DEV must name the structuredmerge checkout" if
  core_root_value.strip.empty? || %w[false 0 no off].include?(core_root_value.strip.downcase)
core_root = File.realpath(File.expand_path(core_root_value, Dir.home))
core_package = File.join(core_root, "packages/ruby")
abort "core package is missing: #{core_package}" unless File.file?(File.join(core_package, "Gemfile"))

def run!(env, command, chdir:)
  puts "+ #{command.join(" ")}"
  status = nil
  Open3.popen2e(env, *command, chdir: chdir) do |stdin, output, wait|
    stdin.close
    output.each_line { |line| $stdout.write(line) }
    status = wait.value
  end
  raise "command failed: #{command.first(4).join(" ")}" unless status.success?
end

stdout, stderr, status = Open3.capture3("git", "-C", root, "status", "--porcelain")
abort stderr unless status.success?
abort "commit or stash Ruby family changes before the isolated installed-core run" unless stdout.empty?

stage = Dir.mktmpdir("structuredmerge-local-core-family-")
workspace_root = File.dirname(root)
test_root = File.join(workspace_root, "ruby-core-installed-test-#{Process.pid}")
abort "temporary test worktree already exists: #{test_root}" if File.exist?(test_root) || File.symlink?(test_root)
begin
  stdout, stderr, status = Open3.capture3("git", "-C", root, "worktree", "add", "--detach", test_root, "HEAD")
  puts stdout
  abort stderr unless status.success?
  artifact_dir = File.join(stage, "artifact")
  FileUtils.mkdir_p(artifact_dir)
  core_env = Bundler.unbundled_env.merge(
    "BUNDLE_GEMFILE" => File.join(core_package, "Gemfile"),
    "STRUCTUREDMERGE_CORE_DEV" => core_root
  )
  run!(core_env, [RbConfig.ruby, "-S", "bundle", "exec", "rake", "compile"], chdir: core_package)
  run!(core_env, [RbConfig.ruby, "-S", "bundle", "exec", "ruby",
    File.join(core_root, "workspace-scripts/check_core_ruby_artifact.rb"),
    "--package-only", artifact_dir], chdir: core_package)
  archives = Dir.glob(File.join(artifact_dir, "*.gem"))
  abort "expected exactly one local core package, got #{archives.length}" unless archives.one?
  command = [RbConfig.ruby, File.join(test_root, "bin/check_installed_core_family.rb"),
    "--core-gem", archives.fetch(0), "--run-family-tests"]
  command.concat(["--only", options.fetch(:only)]) if options[:only]
  checkpoint_dir = File.expand_path(options.fetch(:checkpoint_dir, File.join(root, "tmp/core-family-gate")), Dir.pwd)
  command.concat(["--checkpoint-dir", checkpoint_dir])
  run!(Bundler.unbundled_env.merge("STRUCTUREDMERGE_CORE_DEV" => core_root,
    "STRUCTUREDMERGE_GATE_WORKTREE" => File.realpath(test_root)), command, chdir: test_root)
ensure
  if File.directory?(test_root)
    output, status = Open3.capture2e("git", "-C", root, "worktree", "remove", "--force", test_root)
    puts output
    raise "failed to remove owned Ruby family test worktree" unless status.success?
  end
  FileUtils.remove_entry(stage) if File.exist?(stage)
end
