#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "io/console"
require "json"
require "net/http"
require "open3"
require "optparse"
require "pty"
require "rubygems"
require "shellwords"
require "uri"

RUBY_REPO = File.expand_path("..", __dir__)

GEMS = [
  ["tree_haver", "tree_haver", "tree_haver/version", "TreeHaver::Version::VERSION"],
  ["ast-merge", "ast-merge", "ast/merge/version", "Ast::Merge::Version::VERSION"],
  ["ast-crispr", "ast-crispr", "ast/crispr/version", "Ast::Crispr::Version::VERSION"],
  ["ast-crispr-ruby-prism", "ast-crispr-ruby-prism", "ast/crispr/ruby/prism/version", "Ast::Crispr::Ruby::Prism::Version::VERSION"],
  ["ast-crispr-markdown-markly", "ast-crispr-markdown-markly", "ast/crispr/markdown/markly/version", "Ast::Crispr::Markdown::Markly::Version::VERSION"],
  ["ast-merge-git", "ast-merge-git", "ast/merge/git/version", "Ast::Merge::Git::Version::VERSION"],
  ["plain-merge", "plain-merge", "plain/merge/version", "Plain::Merge::Version::VERSION"],
  ["bash-merge", "bash-merge", "bash/merge/version", "Bash::Merge::Version::VERSION"],
  ["dotenv-merge", "dotenv-merge", "dotenv/merge/version", "Dotenv::Merge::Version::VERSION"],
  ["rbs-merge", "rbs-merge", "rbs/merge/version", "Rbs::Merge::Version::VERSION"],
  ["json-merge", "json-merge", "json/merge/version", "Json::Merge::Version::VERSION"],
  ["yaml-merge", "yaml-merge", "yaml/merge/version", "Yaml::Merge::Version::VERSION"],
  ["toml-merge", "toml-merge", "toml/merge/version", "Toml::Merge::Version::VERSION"],
  ["markdown-merge", "markdown-merge", "markdown/merge/version", "Markdown::Merge::Version::VERSION"],
  ["ruby-merge", "ruby-merge", "ruby/merge/version", "Ruby::Merge::Version::VERSION"],
  ["go-merge", "go-merge", "go/merge/version", "Go::Merge::Version::VERSION"],
  ["rust-merge", "rust-merge", "rust/merge/version", "Rust::Merge::Version::VERSION"],
  ["typescript-merge", "typescript-merge", "typescript/merge/version", "TypeScript::Merge::Version::VERSION"],
  ["ast-template", "ast-template", "ast/template/version", "Ast::Template::Version::VERSION"],
  ["binary-merge", "binary-merge", "binary/merge/version", "Binary::Merge::Version::VERSION"],
  ["zip-merge", "zip-merge", "zip/merge/version", "Zip::Merge::Version::VERSION"],
  ["psych-merge", "psych-merge", "psych/merge/version", "Psych::Merge::Version::VERSION"],
  ["citrus-toml-merge", "citrus-toml-merge", "citrus/toml/merge/version", "Citrus::Toml::Merge::Version::VERSION"],
  ["parslet-toml-merge", "parslet-toml-merge", "parslet/toml/merge/version", "Parslet::Toml::Merge::Version::VERSION"],
  ["commonmarker-merge", "commonmarker-merge", "commonmarker/merge/version", "Commonmarker::Merge::Version::VERSION"],
  ["kramdown-merge", "kramdown-merge", "kramdown/merge/version", "Kramdown::Merge::Version::VERSION"],
  ["markly-merge", "markly-merge", "markly/merge/version", "Markly::Merge::Version::VERSION"],
  ["prism-merge", "prism-merge", "prism/merge/version", "Prism::Merge::Version::VERSION"],
  ["smorg-rb", "smorg-rb", "smorg/rb/version", "Smorg::RB::Version::VERSION"],
  ["kettle-jem", "kettle-jem", "kettle/jem/version", "Kettle::Jem::Version::VERSION"],
].freeze

options = {
  push: true,
  push_git: false,
  skip_tests: false,
  tag: false,
  local_path_gems: false,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: release_ruby_gems.rb [options]"

  opts.on("--push", "Push each built gem to RubyGems after local verification (default)") do
    options[:push] = true
  end

  opts.on("--no-push", "--dry-run", "Build and verify locally without uploading to RubyGems") do
    options[:push] = false
  end

  opts.on("--push-git", "After all releases are live, push the Ruby repo branch and release tag") do
    options[:push_git] = true
  end

  opts.on("--tag", "After all selected releases are live, create the shared vVERSION tag") do
    options[:tag] = true
  end

  opts.on("--skip-tests", "Skip per-gem bundle exec rspec checks") do
    options[:skip_tests] = true
  end

  opts.on("--local-path-gems", "Use local workspace path gems during validation. Default is released gems only.") do
    options[:local_path_gems] = true
  end

  opts.on("--only GEM", "Release only one gem from the publish order") do |gem_name|
    options[:only] = gem_name
  end

  opts.on("--start-at GEM", "Start at a gem in the publish order") do |gem_name|
    options[:start_at] = gem_name
  end
end

parser.parse!

def sh(cmd)
  Shellwords.join(cmd)
end

def run!(cmd, chdir:, env: nil)
  puts "\n$ #{sh(cmd)}"
  return if env ? system(env, *cmd, chdir: chdir) : system(*cmd, chdir: chdir)

  raise "Command failed: #{sh(cmd)}"
end

def capture!(cmd, chdir:, env: nil)
  output, status = env ? Open3.capture2e(env, *cmd, chdir: chdir) : Open3.capture2e(*cmd, chdir: chdir)
  raise "Command failed: #{sh(cmd)}\n#{output}" unless status.success?

  output
end

def run_with_signing_key!(cmd, chdir:, signing_key_passphrase:, env: nil)
  puts "\n$ #{sh(cmd)}"
  prompt_pattern = /pass\s*(?:phrase|word)|signing key|private key/i
  last_sent_at = Time.at(0)

  spawn_args = env ? [env, *cmd, {chdir: chdir}] : [*cmd, {chdir: chdir}]
  PTY.spawn(*spawn_args) do |reader, writer, pid|
    begin
      loop do
        chunk = reader.readpartial(4096)
        print chunk

        next unless chunk.match?(prompt_pattern)
        next if Time.now - last_sent_at < 0.25

        writer.write(signing_key_passphrase)
        writer.write("\n")
        last_sent_at = Time.now
      end
    rescue EOFError, Errno::EIO
      # PTY closes this way after the child exits on several platforms.
    ensure
      writer.close unless writer.closed?
    end

    _, status = Process.wait2(pid)
    raise "Command failed: #{sh(cmd)}" unless status.success?
  end
end

def release_env(local_path_gems:)
  env = ENV.to_h
  unless local_path_gems
    env["SMORG_RB_DEV"] = "false"
    env["KETTLE_RB_DEV"] = "false"
  end
  env
end

def gemspec_for(gem_dir)
  candidates = Dir[File.join(gem_dir, "*.gemspec")]
  raise "Expected one gemspec in #{gem_dir}, found #{candidates.length}" unless candidates.length == 1

  candidates.first
end

def load_spec(gem_dir)
  spec = Gem::Specification.load(gemspec_for(gem_dir))
  raise "Could not load gemspec in #{gem_dir}" unless spec

  spec
end

def ensure_clean_git!
  status = capture!(%w[git status --porcelain], chdir: RUBY_REPO)
  return if status.empty?

  raise "Ruby repo has uncommitted changes; commit before releasing.\n#{status}"
end

def gem_dir_for(gem_name)
  File.join(RUBY_REPO, "gems", gem_name)
end

def gem_bundle_env(base_env, gem_dir)
  gemfile = File.join(gem_dir, "Gemfile")
  return base_env unless File.exist?(gemfile)

  base_env.merge("BUNDLE_GEMFILE" => gemfile)
end

def prepare_gem_bundle!(gem_name, env:)
  gem_dir = gem_dir_for(gem_name)
  return unless File.exist?(File.join(gem_dir, "Gemfile"))

  run!(%w[bundle install], chdir: gem_dir, env: gem_bundle_env(env, gem_dir))
end

def rubygems_version_released?(name, version)
  uri = URI("https://rubygems.org/api/v1/versions/#{URI.encode_www_form_component(name)}.json")
  response = Net::HTTP.get_response(uri)
  return false if response.is_a?(Net::HTTPNotFound)

  unless response.is_a?(Net::HTTPSuccess)
    raise "Could not check RubyGems release state for #{name}: HTTP #{response.code}"
  end

  JSON.parse(response.body).any? { |released_version| released_version.fetch("number") == version }
end

def tag_exists?(tag_name)
  system("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag_name}",
    chdir: RUBY_REPO, out: File::NULL, err: File::NULL)
end

def version_minor(version)
  match = version.match(/\A(\d+)\.(\d+)\.\d+(?:[-+].*)?\z/)
  raise "Gem version #{version.inspect} is not a simple semver version" unless match

  "#{match[1]}.#{match[2]}"
end

def ensure_one_minor_version!(versions)
  minor_versions = versions.group_by { |_name, version| version_minor(version) }
  return if minor_versions.one?

  details = minor_versions.map do |minor, grouped_versions|
    "#{minor}: #{grouped_versions.map { |name, version| "#{name}@#{version}" }.join(", ")}"
  end
  raise "Ruby gems must share one major.minor version before release.\n#{details.join("\n")}"
end

selected_gems = GEMS.dup
if options[:only]
  selected_gems.select! { |gem_name, _require_path, _version_require_path, _version_expr| gem_name == options[:only] }
  raise "Unknown gem for --only: #{options[:only]}" if selected_gems.empty?
end

if options[:start_at]
  start_index = selected_gems.index { |gem_name, _require_path, _version_require_path, _version_expr| gem_name == options[:start_at] }
  raise "Unknown gem for --start-at: #{options[:start_at]}" unless start_index

  selected_gems = selected_gems.drop(start_index)
end

unless Dir.exist?(RUBY_REPO)
  raise "Could not find ruby repo at #{RUBY_REPO}"
end

versions = GEMS.to_h do |gem_name, _require_path, _version_require_path, _version_expr|
  gem_dir = File.join(RUBY_REPO, "gems", gem_name)
  spec = load_spec(gem_dir)
  [gem_name, spec.version.to_s]
end

ensure_one_minor_version!(versions)

release_version = versions.values.uniq
raise "Expected one release version, found: #{release_version.join(", ")}" unless release_version.one?

release_version = release_version.first
tag_name = "v#{release_version}"

puts "Ruby gem release version: #{release_version}"
puts "Selected gems: #{selected_gems.map(&:first).join(", ")}"
puts "RubyGems push: #{options[:push] ? "enabled; pass --no-push for local validation only" : "disabled; local validation only"}"
puts "Dependency mode: #{options[:local_path_gems] ? "local path gems" : "released gems only"}"

if options[:push]
  print "Gem signing key passphrase: "
  signing_key_passphrase = STDIN.noecho(&:gets)&.chomp.to_s
  puts
  raise "Gem signing key passphrase cannot be empty" if signing_key_passphrase.empty?
else
  ENV["SKIP_GEM_SIGNING"] = "true"
  signing_key_passphrase = nil
end

command_env = release_env(local_path_gems: options[:local_path_gems])

ensure_clean_git! if options[:push] || options[:push_git] || options[:tag]

FileUtils.mkdir_p(File.join(RUBY_REPO, "tmp", "release-ruby-gems"))
uploaded_gems = []
skipped_gems = []

selected_gems.each do |gem_name, require_path, version_require_path, version_expr|
  gem_dir = gem_dir_for(gem_name)
  spec = load_spec(gem_dir)
  version = spec.version.to_s
  gem_file = "#{spec.name}-#{version}.gem"
  gem_path = File.join(gem_dir, gem_file)

  puts "\n=== #{gem_name} #{version} ==="

  if options[:push] && rubygems_version_released?(spec.name, version)
    puts "Skipping #{spec.name} #{version}; already released on RubyGems."
    skipped_gems << spec.name
    next
  end

  unless options[:local_path_gems]
    prepare_gem_bundle!(gem_name, env: command_env)
    ensure_clean_git! if options[:push] || options[:push_git] || options[:tag]
  end

  FileUtils.rm_f(gem_path)

  spec_dir = File.join(gem_dir, "spec")
  if options[:skip_tests] || !Dir.exist?(spec_dir)
    puts "Skipping tests for #{gem_name}"
  else
    rspec_chdir, rspec_env =
      if File.exist?(File.join(gem_dir, "Gemfile")) && !options[:local_path_gems]
        [gem_dir, gem_bundle_env(command_env, gem_dir)]
      else
        [RUBY_REPO, command_env]
      end
    spec_helper = File.join(gem_dir, "spec", "spec_helper.rb")
    rspec_cmd = ["bundle", "exec", "rspec", "--options", "/dev/null"]
    rspec_cmd.concat(["--require", spec_helper]) if File.exist?(spec_helper)
    rspec_cmd << spec_dir
    run!(rspec_cmd, chdir: rspec_chdir, env: rspec_env)
  end

  if signing_key_passphrase
    run_with_signing_key!(["gem", "build", File.basename(gemspec_for(gem_dir))],
      chdir: gem_dir,
      signing_key_passphrase: signing_key_passphrase,
      env: command_env)
  else
    run!(["gem", "build", File.basename(gemspec_for(gem_dir))], chdir: gem_dir, env: command_env)
  end
  raise "Expected build artifact #{gem_path}" unless File.exist?(gem_path)

  run!(["gem", "specification", gem_path, "name", "version", "summary", "files"], chdir: RUBY_REPO, env: command_env)
  run!(["gem", "install", "--force", "--local", gem_path], chdir: RUBY_REPO, env: command_env)
  version_check = "require #{require_path.inspect}; require #{version_require_path.inspect}; abort #{version_expr}.inspect unless #{version_expr} == #{version.inspect}; puts #{version_expr}"
  run!(["ruby", "-e", version_check], chdir: File.join(RUBY_REPO, "tmp", "release-ruby-gems"), env: command_env)
  run!(["gem", "contents", spec.name, "-v", version, "--no-prefix"], chdir: RUBY_REPO, env: command_env)

  if options[:push]
    print "RubyGems MFA OTP for #{spec.name} #{version}: "
    otp_code = STDIN.gets&.chomp.to_s
    raise "RubyGems MFA OTP cannot be empty" if otp_code.empty?

    run!(["gem", "push", gem_path, "--otp", otp_code], chdir: RUBY_REPO, env: command_env)
    run!(["gem", "info", spec.name, "--remote", "-v", version], chdir: RUBY_REPO, env: command_env)
    uploaded_gems << spec.name
  end
end

if options[:push]
  selected_gems.each do |gem_name, _require_path, _version_require_path, _version_expr|
    spec = load_spec(File.join(RUBY_REPO, "gems", gem_name))
    next if rubygems_version_released?(spec.name, spec.version.to_s)

    raise "Release confirmation failed: #{spec.name} #{spec.version} is not live on RubyGems."
  end

  if options[:tag]
    run!(["git", "tag", "-a", tag_name, "-m", "Release Ruby gems #{release_version}"], chdir: RUBY_REPO, env: command_env) unless tag_exists?(tag_name)
  end

  if options[:push_git]
    run!(%w[git push origin HEAD], chdir: RUBY_REPO, env: command_env)
    run!(["git", "push", "origin", tag_name], chdir: RUBY_REPO, env: command_env) if options[:tag]
  end

  puts "\nReleased #{uploaded_gems.length} gem(s) to RubyGems: #{uploaded_gems.join(", ")}"
  puts "Skipped #{skipped_gems.length} already-released gem(s): #{skipped_gems.join(", ")}" unless skipped_gems.empty?
else
  puts "\nLocal validation complete for #{selected_gems.length} gem(s); no gems were pushed. Re-run without --no-push to upload."
  puts "Skipping release tag creation because --no-push cannot confirm live releases." if options[:tag]
end
