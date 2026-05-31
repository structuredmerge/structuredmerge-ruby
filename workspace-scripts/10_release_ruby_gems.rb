#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "shellwords"

SCRIPT_DIR = __dir__
RUBY_REPO = File.expand_path("..", SCRIPT_DIR)
GEMS_ROOT = File.join(RUBY_REPO, "gems")

GEMS = %w[
  tree_haver
  ast-merge
  ast-crispr
  ast-crispr-ruby-prism
  ast-crispr-markdown-markly
  ast-merge-git
  plain-merge
  bash-merge
  dotenv-merge
  rbs-merge
  json-merge
  yaml-merge
  toml-merge
  markdown-merge
  ruby-merge
  go-merge
  rust-merge
  typescript-merge
  ast-template
  binary-merge
  zip-merge
  psych-merge
  citrus-toml-merge
  parslet-toml-merge
  commonmarker-merge
  kramdown-merge
  markly-merge
  prism-merge
  smorg-rb
  kettle-jem
].freeze

options = {
  execute: false,
  local_path_gems: false,
  readiness: true,
  start_step: nil,
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: 10_release_ruby_gems.rb [options]"

  opts.on("--execute", "Run kettle-release for each selected gem. Default is plan-only.") do
    options[:execute] = true
  end

  opts.on("--only GEM", "Release only one gem from the publish order.") do |gem_name|
    options[:only] = gem_name
  end

  opts.on("--start-at GEM", "Start at a gem in the publish order.") do |gem_name|
    options[:start_at] = gem_name
  end

  opts.on("--start-step N", Integer, "Pass start_step=N through to kettle-release.") do |step|
    options[:start_step] = step
  end

  opts.on("--local-path-gems", "Allow local workspace path gems. Default is released gems only.") do
    options[:local_path_gems] = true
  end

  opts.on("--[no-]readiness", "Run release-readiness checks before release planning/execution. Default: true.") do |value|
    options[:readiness] = value
  end
end

parser.parse!

def sh(command)
  Shellwords.join(command)
end

def selected_gems(options)
  gems = GEMS.dup
  if options[:only]
    gems.select! { |gem_name| gem_name == options[:only] }
    raise "Unknown gem for --only: #{options[:only]}" if gems.empty?
  end

  if options[:start_at]
    index = gems.index(options[:start_at])
    raise "Unknown gem for --start-at: #{options[:start_at]}" unless index

    gems = gems.drop(index)
  end
  gems
end

def release_env(local_path_gems:)
  return {} if local_path_gems

  {
    "GALTZO_FLOSS_DEV" => "false",
    "KETTLE_RB_DEV" => "false",
    "SMORG_RB_DEV" => "false",
    "TREE_SITTER_LANGUAGE_PACK_DEV" => "",
  }
end

def run!(command, chdir:, env: nil)
  puts "$ #{sh(command)}"
  return if env ? system(env, *command, chdir: chdir) : system(*command, chdir: chdir)

  raise "Command failed: #{sh(command)}"
end

if options[:readiness]
  run!([File.join(SCRIPT_DIR, "11_release_readiness_check.rb")], chdir: RUBY_REPO)
end

command_env = release_env(local_path_gems: options[:local_path_gems])
release_args = ["bundle", "exec", "kettle-release"]
release_args << "start_step=#{options[:start_step]}" if options[:start_step]

selected = selected_gems(options)
puts "Selected gems: #{selected.join(", ")}"
puts "Dependency mode: #{options[:local_path_gems] ? "local path gems" : "released gems only"}"
puts "Execution: #{options[:execute] ? "enabled" : "plan only; pass --execute to run"}"

selected.each do |gem_name|
  gem_dir = File.join(GEMS_ROOT, gem_name)
  raise "Missing gem directory: #{gem_dir}" unless Dir.exist?(gem_dir)

  command = ["mise", "exec", "-C", gem_dir, "--", *release_args]
  if options[:execute]
    run!(command, chdir: RUBY_REPO, env: command_env.empty? ? nil : command_env)
  else
    env_prefix = command_env.map { |key, value| "#{key}=#{value}" }
    puts sh([*env_prefix, *command])
  end
end
