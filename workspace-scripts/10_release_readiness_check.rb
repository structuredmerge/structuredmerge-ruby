#!/usr/bin/env ruby
# frozen_string_literal: true

RUBY_REPO = File.expand_path("..", __dir__)
GEMS_ROOT = File.join(RUBY_REPO, "gems")
CANONICAL_KETTLE_CONFIG = ".structuredmerge/kettle-jem.yml"
LEGACY_KETTLE_CONFIG = ".kettle-jem.yml"
LOCKFILE_LOCAL_REMOTE = %r{^\s{2}remote:\s+/(?:home|var/home|srv)/.+/kettle-rb/}.freeze
ROOT_REQUIRED_DOCS = %w[
  CHANGELOG.md
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  FUNDING.md
  LICENSE.md
  SECURITY.md
].freeze
README_SHARED_LINKS = {
  "CHANGELOG.md" => "CHANGELOG.md",
  "CODE_OF_CONDUCT.md" => "CODE_OF_CONDUCT.md",
  "CONTRIBUTING.md" => "CONTRIBUTING.md",
  "SECURITY.md" => "SECURITY.md",
}.freeze
GEM_RELEASE_HARNESS_FILES = %w[
  Gemfile
  Gemfile.lock
  Rakefile
  .rspec
  .simplecov
  .yardignore
  .yardopts
  bin/setup
  spec/spec_helper.rb
  gemfiles/modular/documentation.gemfile
  gemfiles/modular/x_std_libs.gemfile
].freeze
GEM_RELEASE_BINSTUBS = %w[
  bin/gem_checksums
  bin/kettle-changelog
  bin/kettle-pre-release
  bin/kettle-release
  bin/kettle-test
  bin/rake
  bin/rspec
  bin/yard
].freeze
STANDALONE_ONLY_DIRS = %w[
  .devcontainer
  .git-hooks
  .github
  .idea
  .qlty
].freeze

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

def tracked_path?(path)
  relative = relative_path(path)
  system("git", "-C", RUBY_REPO, "ls-files", "--error-unmatch", relative, out: File::NULL, err: File::NULL)
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

ROOT_REQUIRED_DOCS.each do |doc|
  path = File.join(RUBY_REPO, doc)
  failures << "#{doc}: missing required root shared document" unless File.file?(path)
end

gem_dirs.each do |dir|
  %w[README.md LICENSE.md].each do |doc|
    path = File.join(dir, doc)
    failures << "#{relative_path(path)}: missing required packaged gem document" unless File.file?(path)
  end

  GEM_RELEASE_HARNESS_FILES.each do |relative|
    path = File.join(dir, relative)
    failures << "#{relative_path(path)}: missing per-gem release harness file" unless File.file?(path)
  end

  GEM_RELEASE_BINSTUBS.each do |relative|
    path = File.join(dir, relative)
    failures << "#{relative_path(path)}: missing per-gem release binstub" unless File.file?(path)
    failures << "#{relative_path(path)}: release binstub is not executable" if File.file?(path) && !File.executable?(path)
  end

  docs_dir = File.join(dir, "docs")
  failures << "#{relative_path(docs_dir)}: missing generated YARD docs; run workspace-scripts/6_docs_ruby_gems.sh" unless Dir.exist?(docs_dir)

  next if File.basename(dir) == "kettle-jem"

  STANDALONE_ONLY_DIRS.each do |relative|
    path = File.join(dir, relative)
    failures << "#{relative_path(path)}: standalone-only directory should not be committed in monorepo release profile" if Dir.exist?(path) && tracked_path?(path)
  end

  readme = File.join(dir, "README.md")
  next unless File.file?(readme)

  content = File.read(readme)
  README_SHARED_LINKS.each do |label, target|
    next if content.include?("/#{target}") || content.include?("../../#{target}") || content.include?("../#{target}")

    failures << "#{relative_path(readme)}: missing link to root #{label}"
  end
end

if failures.empty?
  puts "Ruby release readiness checks passed."
else
  warn "Ruby release readiness checks failed:"
  failures.each { |failure| warn "  - #{failure}" }
  exit 1
end
