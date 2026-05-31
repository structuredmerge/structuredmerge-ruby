#!/usr/bin/env ruby
# frozen_string_literal: true

RUBY_REPO = File.expand_path("..", __dir__)
GEMS_ROOT = File.join(RUBY_REPO, "gems")
CANONICAL_KETTLE_CONFIG = ".structuredmerge/kettle-jem.yml"
LEGACY_KETTLE_CONFIG = ".kettle-jem.yml"
LOCKFILE_LOCAL_REMOTE = %r{^\s{2}remote:\s+/(?:home|var/home|srv)/.+/kettle-rb/}.freeze

def gem_dirs
  Dir.glob(File.join(GEMS_ROOT, "*", "*.gemspec"))
    .map { |path| File.dirname(path) }
    .uniq
    .sort_by { |path| File.basename(path) }
end

def project_dirs
  [RUBY_REPO, *gem_dirs]
end

def relative_path(path)
  path.delete_prefix("#{RUBY_REPO}/")
end

failures = []

Dir.glob(File.join(RUBY_REPO, "**", "Gemfile.lock")).sort.each do |lockfile|
  next if lockfile.split(File::SEPARATOR).include?("tmp")

  File.readlines(lockfile, chomp: true).each_with_index do |line, index|
    next unless line.match?(LOCKFILE_LOCAL_REMOTE)

    failures << "#{relative_path(lockfile)}:#{index + 1}: release lockfile contains local kettle-rb path remote: #{line.strip}"
  end
end

project_dirs.each do |dir|
  legacy = File.join(dir, LEGACY_KETTLE_CONFIG)
  canonical = File.join(dir, CANONICAL_KETTLE_CONFIG)
  failures << "#{relative_path(legacy)}: legacy kettle-jem config must be migrated" if File.exist?(legacy)
  failures << "#{relative_path(canonical)}: missing canonical kettle-jem config" unless File.exist?(canonical)
end

root_git_drivers = File.join(RUBY_REPO, ".structuredmerge", "git-drivers.toml")
failures << "#{relative_path(root_git_drivers)}: missing root Git driver manifest" unless File.exist?(root_git_drivers)

if failures.empty?
  puts "Ruby release readiness checks passed."
else
  warn "Ruby release readiness checks failed:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end
