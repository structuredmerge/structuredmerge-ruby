#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "rubygems"
require "tsort"

RUBY_REPO = File.expand_path("..", __dir__)
GEMS_ROOT = File.join(RUBY_REPO, "gems")

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
  bootstrap_missing_config: false,
  json: false,
  mode: "converge",
  normalize_lock: true,
  profile: nil,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: template_ruby_gems.rb [options]"

  opts.on("--mode MODE", "Run mode: plan, converge, or apply. Default: converge.") do |mode|
    raise OptionParser::InvalidArgument, "mode must be plan, converge, or apply" unless %w[plan converge apply].include?(mode)

    options[:mode] = mode
  end

  opts.on("--only GEM", "Template only one gem directory.") do |gem_name|
    options[:only] = gem_name
  end

  opts.on("--start-at GEM", "Start at a gem directory in sorted order.") do |gem_name|
    options[:start_at] = gem_name
  end

  opts.on("--profile PROFILE", "Template profile to pass to kettle-jem, e.g. monorepo-subgem.") do |profile|
    options[:profile] = profile
  end

  opts.on("--[no-]bootstrap-missing-config", "Write initial .kettle-jem.yml before applying packaged templates. Default: false.") do |value|
    options[:bootstrap_missing_config] = value
  end

  opts.on("--json", "Print a JSON report.") do
    options[:json] = true
  end

  opts.on("--[no-]normalize-lock", "After each templating run, run bundle install without templating/local-path env to restore release-compatible lockfiles. Default: true.") do |value|
    options[:normalize_lock] = value
  end

  opts.on("--child", "Run one gem in child mode.") do
    options[:child] = true
  end

  opts.on("--gem-dir DIR", "Gem directory for child mode.") do |dir|
    options[:gem_dir] = dir
  end
end

parser.parse!

def run_kettle_jem_for_gem(gem_dir, options)
  require "kettle-jem"

  profile_run_options = options[:profile] ? {template_profile: options[:profile]} : {}
  env = ENV.to_h

  bootstrap = nil
  config_path = File.join(gem_dir, ".kettle-jem.yml")
  if options[:mode] == "apply" && options[:bootstrap_missing_config] && !File.exist?(config_path)
    bootstrap = Kettle::Jem.setup_project(
      gem_dir,
      env: env,
      run_options: {bootstrap_mode: true, skip_commit: true, quiet: true}.merge(profile_run_options)
    )
  end

  run_options = {accept: true, force: true, skip_commit: true, quiet: true}.merge(profile_run_options)
  result = if options[:mode] == "plan"
    Kettle::Jem.plan_project(gem_dir, env: env, run_options: run_options)
  elsif options[:mode] == "converge"
    plan = Kettle::Jem.plan_project(gem_dir, env: env, run_options: run_options)
    post_apply_steps = Kettle::Jem.post_apply_steps(gem_dir, plan)
    changed_files = post_apply_steps.flat_map { |step| step.fetch(:changed_files, []) }.uniq.sort
    plan.merge(mode: "converge", changed_files: changed_files, post_apply_steps: post_apply_steps)
  else
    Kettle::Jem.apply_project(gem_dir, env: env, run_options: run_options)
  end

  {
    gem: File.basename(gem_dir),
    root: gem_dir,
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

results = gem_dirs.map do |gem_dir|
  gem_name = File.basename(gem_dir)
  puts "\n== #{gem_name} ==" unless options[:json]

  command = [
    "mise", "exec", "-C", gem_dir, "--",
    "bundle", "exec", "ruby", File.expand_path(__FILE__),
    "--child",
    "--gem-dir", gem_dir,
    "--mode", options[:mode],
  ]
  command.concat(["--profile", options[:profile]]) if options[:profile]
  command << "--bootstrap-missing-config" if options[:bootstrap_missing_config]
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
  puts "#{options[:mode]}: #{changed_files.length} changed file#{changed_files.length == 1 ? "" : "s"}" unless options[:json]
  changed_files.each { |path| puts "  #{path}" } unless options[:json]

  result
end

puts JSON.pretty_generate({kind: "ruby_gem_template_report", gems: results}) if options[:json]
