#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "set"
require "rubygems"
require "shellwords"
require "tsort"

SCRIPT_DIR = File.expand_path(__dir__)
RUBY_WORKSPACE = File.expand_path("..", SCRIPT_DIR)
KETTLE_ROOT = File.expand_path("../..", RUBY_WORKSPACE)
DEFAULT_ROOTS = [
  File.join(RUBY_WORKSPACE, "gems"),
  File.join(KETTLE_ROOT, "kettle-rb"),
  File.join(KETTLE_ROOT, "galtzo-floss"),
  File.expand_path("~/src/galtzo-floss"),
].uniq.freeze

DEFAULT_GEMS = %w[
  tree_haver
  ast-crispr
  ast-crispr-markdown-markly
  ast-crispr-ruby-prism
  ast-merge
  ast-merge-git
  ast-template
  bash-merge
  binary-merge
  citrus-toml-merge
  commonmarker-merge
  dotenv-merge
  go-merge
  json-merge
  kettle-dev
  kettle-drift
  kettle-jem
  kettle-jem-appraisals
  kettle-soup-cover
  kettle-test
  kramdown-merge
  markdown-merge
  markly-merge
  nomono
  parslet-toml-merge
  plain-merge
  prism-merge
  psych-merge
  rbs-merge
  ruby-merge
  rust-merge
  smorg-rb
  stone_checksums
  token-resolver
  toml-merge
  turbo_tests2
  typescript-merge
  yaml-converter
  yaml-merge
  yard-fence
  yard-timekeeper
  yard-yaml
  zip-merge
].freeze

ORDER_HINT = DEFAULT_GEMS.each_with_index.to_h.freeze

options = {
  destination: nil,
  gem_names: DEFAULT_GEMS.dup,
  roots: DEFAULT_ROOTS.select { |path| Dir.exist?(path) },
  install: true,
  template: false,
  template_args: %w[install --skip-commit],
  template_env: {},
}

OptionParser.new do |opts|
  opts.banner = "Usage: install_local_template_stack.rb [options]"

  opts.on("--destination PATH", "Destination gem to template after installing the local stack.") do |path|
    options[:destination] = File.expand_path(path)
    options[:template] = true
  end

  opts.on("--root PATH", "Add a root whose immediate children may be local gem repos. May be repeated.") do |path|
    options[:roots] << File.expand_path(path)
  end

  opts.on("--gem NAME", "Add one local gem name to the install set. May be repeated.") do |name|
    options[:gem_names] << name
  end

  opts.on("--gems x,y,z", Array, "Replace the default install set with a comma-separated gem list.") do |names|
    options[:gem_names] = names
  end

  opts.on("--install-only", "Build and install local gems, but do not run kettle-jem.") do
    options[:template] = false
  end

  opts.on("--template-only", "Run kettle-jem without rebuilding local gems first.") do
    options[:install] = false
    options[:template] = true
  end

  opts.on("--template-args ARGS", "Arguments passed to kettle-jem. Default: install --skip-commit") do |args|
    options[:template_args] = Shellwords.split(args)
  end

  opts.on("--env KEY=VALUE", "Environment variable for the kettle-jem templating command. May be repeated.") do |pair|
    key, value = pair.split("=", 2)
    raise OptionParser::InvalidArgument, "--env requires KEY=VALUE" if key.to_s.empty? || value.nil?

    options[:template_env][key] = value
  end
end.parse!

def run!(argv, env: {}, chdir: nil)
  options = {}
  options[:chdir] = chdir if chdir
  stdout, stderr, status = Open3.capture3(env, *argv, **options)
  return stdout if status.success?

  warn stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  raise "Command failed (#{status.exitstatus}): #{argv.shelljoin}"
end

def gemspecs_under(root)
  Dir.glob(File.join(root, "*", "*.gemspec")).sort
end

def load_spec(path)
  spec = Gem::Specification.load(path)
  raise "Could not load gemspec: #{path}" unless spec

  spec
end

def local_specs(roots, selected_names)
  selected_names = selected_names.to_set
  roots.each_with_object({}) do |root, result|
    next unless Dir.exist?(root)

    gemspecs_under(root).each do |gemspec|
      next unless selected_names.include?(File.basename(File.dirname(gemspec)))

      spec = load_spec(gemspec)
      next unless selected_names.include?(spec.name)

      result[spec.name] ||= {spec: spec, gemspec: gemspec, dir: File.dirname(gemspec)}
    end
  end
end

def dependency_order(selected, specs_by_name)
  graph = selected.to_h do |name|
    spec = specs_by_name.fetch(name).fetch(:spec)
    deps = spec.dependencies.select { |dep| dep.type == :runtime }.map(&:name).select { |dep| selected.include?(dep) }
    [name, deps.sort_by { |dep| [ORDER_HINT.fetch(dep, ORDER_HINT.length), dep] }]
  end

  sorter = Class.new do
    include TSort

    def initialize(graph)
      @graph = graph
    end

    def tsort_each_node(&block)
      @graph.keys.sort_by { |name| [ORDER_HINT.fetch(name, ORDER_HINT.length), name] }.each(&block)
    end

    def tsort_each_child(node, &block)
      @graph.fetch(node).each(&block)
    end
  end

  sorter.new(graph).tsort
end

def build_and_install(entry)
  dir = entry.fetch(:dir)
  gemspec = entry.fetch(:gemspec)
  spec = entry.fetch(:spec)
  out_dir = File.join(dir, "tmp", "local-gem-install")
  FileUtils.mkdir_p(out_dir)
  gem_path = File.join(out_dir, "#{spec.name}-#{spec.version}.gem")
  FileUtils.rm_f(gem_path)

  puts "== build #{spec.name} #{spec.version}"
  run!(["gem", "build", gemspec, "--output", gem_path], env: {"SKIP_GEM_SIGNING" => "true"}, chdir: dir)
  puts "== install #{File.basename(gem_path)}"
  run!(["gem", "install", "--force", "--no-document", "--local", gem_path])
end

specs_by_name = local_specs(options.fetch(:roots).uniq, options.fetch(:gem_names).uniq)
missing = options.fetch(:gem_names).uniq.reject { |name| specs_by_name.key?(name) }
warn "Skipping missing local gems: #{missing.join(", ")}" unless missing.empty?
selected = options.fetch(:gem_names).uniq & specs_by_name.keys
ordered = dependency_order(selected, specs_by_name)

if options.fetch(:install)
  ordered.each { |name| build_and_install(specs_by_name.fetch(name)) }
end

if options.fetch(:template)
  destination = options.fetch(:destination)
  raise OptionParser::MissingArgument, "--destination is required when templating is enabled" if destination.nil?
  raise "Destination does not exist: #{destination}" unless Dir.exist?(destination)

  puts "== template #{destination}"
  command = ["kettle-jem", *options.fetch(:template_args)]
  puts run!(command, env: {"SKIP_GEM_SIGNING" => "true"}.merge(options.fetch(:template_env)), chdir: destination)
end
