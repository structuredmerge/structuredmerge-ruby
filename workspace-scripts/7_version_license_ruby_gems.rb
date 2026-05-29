#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubygems"

RUBY_REPO = File.expand_path("..", __dir__)
STRUCTUREDMERGE_ROOT = File.expand_path("..", RUBY_REPO)
WORKSPACE_ROOT = File.expand_path("..", STRUCTUREDMERGE_ROOT)

ACTIVE_RUBY_GEMS = %w[
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

LIVE_ADJACENT_GEMS = %w[
  kettle-dev
  kettle-drift
  kettle-jem-appraisals
].freeze

REFERENCE_GEMS = %w[
  ast-crispr
  ast-merge
  commonmarker-merge
  json-merge
  jsonc-merge
  kettle-jem
  markdown-merge
  markly-merge
  prism-merge
  psych-merge
  toml-merge
  tree_haver
].freeze

def gem_entries
  active = ACTIVE_RUBY_GEMS.map do |name|
    {
      lane: "active",
      repo: name,
      dir: File.join(RUBY_REPO, "gems", name),
    }
  end

  adjacent = LIVE_ADJACENT_GEMS.map do |name|
    {
      lane: "vendor/live",
      repo: name,
      dir: File.join(WORKSPACE_ROOT, "vendor", name),
    }
  end

  reference = REFERENCE_GEMS.map do |name|
    {
      lane: "reference",
      repo: name,
      dir: File.join(WORKSPACE_ROOT, "reference", name),
    }
  end

  active + adjacent + reference
end

def gemspec_for(repo_dir, repo)
  exact = File.join(repo_dir, "#{repo}.gemspec")
  return exact if File.file?(exact)

  matches = Dir.glob(File.join(repo_dir, "*.gemspec")).sort
  return matches.first if matches.size == 1

  raise "no gemspec found" if matches.empty?

  raise "multiple gemspecs found: #{matches.map { |path| File.basename(path) }.join(', ')}"
end

def load_spec(entry)
  repo_dir = entry.fetch(:dir)
  raise "missing directory: #{repo_dir}" unless Dir.exist?(repo_dir)

  gemspec_path = gemspec_for(repo_dir, entry.fetch(:repo))
  spec = Dir.chdir(repo_dir) { Gem::Specification.load(gemspec_path) }
  raise "failed to load gemspec: #{File.basename(gemspec_path)}" unless spec

  licenses = Array(spec.licenses).compact.map(&:to_s).map(&:strip).reject(&:empty?)
  licenses = [spec.license.to_s.strip] if licenses.empty? && spec.respond_to?(:license) && !spec.license.to_s.strip.empty?
  authors = Array(spec.authors).compact.map(&:to_s).map(&:strip).reject(&:empty?)
  required_ruby_version = spec.required_ruby_version ? spec.required_ruby_version.to_s.strip : ""

  {
    lane: entry.fetch(:lane),
    repo: entry.fetch(:repo),
    gem: spec.name.to_s,
    version: spec.version.to_s,
    required_ruby_version: required_ruby_version.empty? ? "(none)" : required_ruby_version,
    licenses: licenses.empty? ? "(none)" : licenses.join(", "),
    authors: authors.empty? ? "(none)" : authors.join(", "),
  }
end

def print_table(rows)
  columns = %i[lane repo gem version required_ruby_version licenses authors]
  widths = columns.to_h do |column|
    values = rows.map { |row| row.fetch(column).to_s }
    [column, ([column.to_s.length] + values.map(&:length)).max]
  end

  separator = "+-#{columns.map { |column| "-" * widths.fetch(column) }.join("-+-")}-+"
  puts separator
  puts "| #{columns.map { |column| column.to_s.upcase.ljust(widths.fetch(column)) }.join(" | ")} |"
  puts separator
  rows.each do |row|
    puts "| #{columns.map { |column| row.fetch(column).to_s.ljust(widths.fetch(column)) }.join(" | ")} |"
  end
  puts separator
end

rows = []
failures = []

gem_entries.each do |entry|
  rows << load_spec(entry)
rescue StandardError => e
  failures << entry.merge(error: e.message)
end

print_table(rows)

unless failures.empty?
  warn
  warn "=== FAILURES ==="
  failures.each do |failure|
    warn "#{failure.fetch(:lane)}/#{failure.fetch(:repo)}: #{failure.fetch(:error)}"
  end
  exit 1
end
