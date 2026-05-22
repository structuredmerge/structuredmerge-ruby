#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "rubygems"
require "tsort"

RUBY_REPO = File.expand_path("..", __dir__)
GEMS_ROOT = File.join(RUBY_REPO, "gems")
MONOREPO_TEMPLATE_PROFILE = "monorepo-subgem"
FULL_TEMPLATE_GEMS = %w[kettle-jem].freeze

ORDER_HINT = [
  "tree_haver",
  "ast-merge",
  "ast-crispr",
  "ast-crispr-ruby-prism",
  "ast-crispr-markdown-markly",
  "ast-merge-git",
  "plain-merge",
  "bash-merge",
  "dotenv-merge",
  "rbs-merge",
  "json-merge",
  "yaml-merge",
  "toml-merge",
  "markdown-merge",
  "ruby-merge",
  "go-merge",
  "rust-merge",
  "typescript-merge",
  "ast-template",
  "binary-merge",
  "zip-merge",
  "psych-merge",
  "citrus-toml-merge",
  "parslet-toml-merge",
  "commonmarker-merge",
  "kramdown-merge",
  "markly-merge",
  "prism-merge",
  "smorg-rb",
  "kettle-jem",
].freeze

options = {
  commit: true,
  json: false,
  normalize_lock: true,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: template_ruby_gems.rb [options]"

  opts.on("--only GEM", "Template only one gem directory.") do |gem_name|
    options[:only] = gem_name
  end

  opts.on("--start-at GEM", "Start at a gem directory in sorted order.") do |gem_name|
    options[:start_at] = gem_name
  end

  opts.on("--json", "Print a JSON report.") do
    options[:json] = true
  end

  opts.on("--[no-]commit", "Commit all template results once from the repository root after all selected gems. Default: true.") do |value|
    options[:commit] = value
  end

  opts.on("--[no-]normalize-lock", "After each templating run, run bundle install without templating/local-path env to restore release-compatible lockfiles. Default: true.") do |value|
    options[:normalize_lock] = value
  end
end

if (child_index = ARGV.index("--child"))
  options[:child] = true
  ARGV.delete_at(child_index)
end

if (gem_dir_index = ARGV.index("--gem-dir"))
  raise OptionParser::MissingArgument, "--gem-dir requires a directory" unless ARGV[gem_dir_index + 1]

  options[:gem_dir] = ARGV[gem_dir_index + 1]
  ARGV.slice!(gem_dir_index, 2)
end

parser.parse!

def run_kettle_jem_for_gem(gem_dir, options)
  require "kettle-jem"

  template_run_options = template_run_options_for_gem(gem_dir)
  env = ENV.to_h

  bootstrap = nil
  config_path = File.join(gem_dir, ".kettle-jem.yml")
  unless File.exist?(config_path)
    bootstrap = Kettle::Jem.setup_project(
      gem_dir,
      env: env,
      run_options: {bootstrap_mode: true, skip_commit: true, quiet: true}.merge(template_run_options)
    )
  end

  run_options = {accept: true, force: true, skip_commit: true, quiet: true}.merge(template_run_options)
  result = Kettle::Jem.apply_project(gem_dir, env: env, run_options: run_options)

  {
    gem: File.basename(gem_dir),
    root: gem_dir,
    template_profile: template_run_options.fetch(:template_profile, ""),
    bootstrap_status: bootstrap && bootstrap[:setup_status],
    mode: result.fetch(:mode),
    changed_files: result.fetch(:changed_files, []),
    post_apply_steps: result.fetch(:post_apply_steps, []),
    diagnostics: result.fetch(:diagnostics, []),
  }.compact
end

def gemspec_for(gem_dir)
  candidates = Dir[File.join(gem_dir, "*.gemspec")]
  raise "Expected one gemspec in #{gem_dir}, found #{candidates.length}" unless candidates.length == 1

  candidates.first
end

def template_profile_for_gem(gem_name)
  return nil if FULL_TEMPLATE_GEMS.include?(gem_name)

  MONOREPO_TEMPLATE_PROFILE
end

def template_run_options_for_gem(gem_dir)
  profile = template_profile_for_gem(File.basename(gem_dir))
  profile ? {template_profile: profile} : {}
end

def template_kind_for_gem(gem_name)
  profile = template_profile_for_gem(gem_name)
  profile || "full"
end

def local_gem_dirs
  Dir.glob(File.join(GEMS_ROOT, "*", "*.gemspec"))
    .map { |gemspec| File.dirname(gemspec) }
    .uniq
end

def order_hint_for(gem_name)
  ORDER_HINT.index(gem_name) || ORDER_HINT.length
end

def ordered_gem_dirs
  dirs_by_name = local_gem_dirs.to_h { |dir| [File.basename(dir), dir] }
  specs_by_name = dirs_by_name.to_h do |name, dir|
    spec = Gem::Specification.load(gemspec_for(dir))
    raise "Could not load gemspec for #{name}" unless spec

    [name, spec]
  end

  graph = specs_by_name.to_h do |name, spec|
    local_dependencies = spec.dependencies
      .map(&:name)
      .select { |dependency_name| dirs_by_name.key?(dependency_name) }
      .sort_by { |dependency_name| [order_hint_for(dependency_name), dependency_name] }
    [name, local_dependencies]
  end

  sorter = Class.new do
    include TSort

    def initialize(graph)
      @graph = graph
    end

    def tsort_each_node(&block)
      @graph.keys.sort_by { |name| [order_hint_for(name), name] }.each(&block)
    end

    def tsort_each_child(node, &block)
      @graph.fetch(node).each(&block)
    end
  end

  sorter.new(graph).tsort.map { |name| dirs_by_name.fetch(name) }
rescue TSort::Cyclic => error
  raise "Local gem dependency cycle prevents dependency-first templating: #{error.message}"
end

def normalize_lockfile_for_gem(gem_dir)
  return unless File.exist?(File.join(gem_dir, "Gemfile"))

  env = ENV.to_h
  env["K_JEM_TEMPLATING"] = "false"
  env["SMORG_RB_DEV"] = "false"
  env["KETTLE_RB_DEV"] = "false"
  command = ["mise", "exec", "-C", gem_dir, "--", "bundle", "install"]
  _stdout, stderr, status = Open3.capture3(env, *command)
  return if status.success?

  warn stderr unless stderr.empty?
  raise "Lock normalization failed for #{File.basename(gem_dir)}: #{command.join(" ")}"
end

def git_status_entries
  stdout, stderr, status = Open3.capture3("git", "-C", RUBY_REPO, "status", "--porcelain")
  raise "Git status failed: #{stderr}" unless status.success?

  stdout.lines.map(&:chomp).reject(&:empty?)
end

def ensure_clean_worktree_for_commit!
  entries = git_status_entries
  return if entries.empty?

  raise <<~MESSAGE
    Refusing to template with commit enabled because the repository worktree is not clean.
    Commit or discard existing changes first, or rerun with --no-commit.
    Dirty entries:
    #{entries.join("\n")}
  MESSAGE
end

def commit_template_results
  entries = git_status_entries
  return {status: "clean_noop"} if entries.empty?

  add_stdout, add_stderr, add_status = Open3.capture3("git", "-C", RUBY_REPO, "add", "-A")
  raise "Git add failed: #{add_stderr.empty? ? add_stdout : add_stderr}" unless add_status.success?

  message = "chore: apply kettle-jem templates"
  commit_stdout, commit_stderr, commit_status = Open3.capture3("git", "-C", RUBY_REPO, "commit", "-m", message)
  raise "Git commit failed: #{commit_stderr.empty? ? commit_stdout : commit_stderr}" unless commit_status.success?

  sha_stdout, sha_stderr, sha_status = Open3.capture3("git", "-C", RUBY_REPO, "rev-parse", "--short", "HEAD")
  raise "Git rev-parse failed: #{sha_stderr}" unless sha_status.success?

  {status: "committed", message: message, sha: sha_stdout.strip, changed_entries: entries}
end

def option_state(value)
  value ? "enabled" : "disabled"
end

def banner_value(label, value, flag)
  "#{label}: #{value} [#{flag}]"
end

def render_options_banner(options, gem_dirs)
  selected = if options[:only]
    "only #{options[:only]}"
  elsif options[:start_at]
    "from #{options[:start_at]} through end"
  else
    "all gems"
  end

  lines = [
    "== StructuredMerge Ruby monorepo templating ==",
    "Action: apply kettle-jem templates and write changed files",
    "Template kind: #{MONOREPO_TEMPLATE_PROFILE} for sub-project gems; full template for #{FULL_TEMPLATE_GEMS.join(", ")}",
    "Missing .kettle-jem.yml: auto-bootstrap before templating",
    banner_value("Commit template result", option_state(options[:commit]), "toggle: --commit / --no-commit"),
    banner_value("Normalize lockfiles", option_state(options[:normalize_lock]), "toggle: --normalize-lock / --no-normalize-lock"),
    banner_value("Selection", "#{selected} (#{gem_dirs.length} gem#{gem_dirs.length == 1 ? "" : "s"})", "limit: --only GEM or --start-at GEM"),
  ]
  lines << "JSON output: enabled" if options[:json]
  puts lines.join("\n")
end

if options[:child]
  raise OptionParser::MissingArgument, "--gem-dir is required with --child" unless options[:gem_dir]

  puts JSON.generate(run_kettle_jem_for_gem(File.expand_path(options[:gem_dir]), options))
  exit
end

gem_dirs = ordered_gem_dirs

if options[:only]
  gem_dirs.select! { |path| File.basename(path) == options[:only] }
  raise "Unknown gem for --only: #{options[:only]}" if gem_dirs.empty?
end

if options[:start_at]
  start_index = gem_dirs.index { |path| File.basename(path) == options[:start_at] }
  raise "Unknown gem for --start-at: #{options[:start_at]}" unless start_index

  gem_dirs = gem_dirs.drop(start_index)
end

render_options_banner(options, gem_dirs) unless options[:json]
ensure_clean_worktree_for_commit! if options[:commit]

results = gem_dirs.map do |gem_dir|
  gem_name = File.basename(gem_dir)
  puts "\n== #{gem_name} ==" unless options[:json]

  command = [
    "mise", "exec", "-C", gem_dir, "--",
    "bundle", "exec", "ruby", File.expand_path(__FILE__),
    "--child",
    "--gem-dir", gem_dir,
  ]
  child_env = ENV.to_h
  child_env["SMORG_RB_DEV"] = GEMS_ROOT unless child_env.key?("SMORG_RB_DEV")
  child_env["K_JEM_TEMPLATING"] = "true"
  stdout, stderr, status = Open3.capture3(child_env, *command)
  unless status.success?
    warn stderr unless stderr.empty?
    raise "Template command failed for #{gem_name}: #{command.join(" ")}"
  end

  result = JSON.parse(stdout, symbolize_names: true)
  if options[:normalize_lock]
    normalize_lockfile_for_gem(gem_dir)
  end

  changed_files = result.fetch(:changed_files, [])
  puts "apply (#{template_kind_for_gem(gem_name)} template): #{changed_files.length} changed file#{changed_files.length == 1 ? "" : "s"}" unless options[:json]
  changed_files.each { |path| puts "  #{path}" } unless options[:json]

  result
end

commit_report = options[:commit] ? commit_template_results : {status: "skipped", reason: "no_commit"}
unless options[:json]
  case commit_report.fetch(:status)
  when "committed"
    puts "\nCommit: #{commit_report.fetch(:sha)} #{commit_report.fetch(:message)}"
  when "clean_noop"
    puts "\nCommit: clean noop"
  else
    puts "\nCommit: skipped (#{commit_report.fetch(:reason)})"
  end
end

puts JSON.pretty_generate({kind: "ruby_gem_template_report", gems: results, commit: commit_report}) if options[:json]
