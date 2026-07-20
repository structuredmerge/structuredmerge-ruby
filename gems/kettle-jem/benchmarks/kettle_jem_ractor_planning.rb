#!/usr/bin/env ruby
# frozen_string_literal: true

require "etc"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

BENCHMARK_ROOT = File.expand_path(__dir__)
PROJECT_ROOT = File.expand_path("..", BENCHMARK_ROOT)
FIXTURE_ROOT = File.join(BENCHMARK_ROOT, "fixtures", "skeleton")
WORK_PARENT = File.join(PROJECT_ROOT, "tmp", "benchmarks", "work")
WORKTREE = File.join(WORK_PARENT, "skeleton")
REPORT_ROOT = File.join(PROJECT_ROOT, "tmp", "benchmarks", "reports")
KETTLE_JEM_EXE = File.join(PROJECT_ROOT, "exe", "kettle-jem")

RUNS = Integer(ENV.fetch("KETTLE_JEM_BENCHMARK_RUNS", "3"))
WORKERS = Integer(
  ENV.fetch("KETTLE_JEM_BENCHMARK_WORKERS", [2, Etc.nprocessors].min.to_s)
)
COMMAND = ENV.fetch("KETTLE_JEM_BENCHMARK_COMMAND", "apply")

raise "KETTLE_JEM_BENCHMARK_RUNS must be positive" unless RUNS.positive?
raise "KETTLE_JEM_BENCHMARK_WORKERS must be positive" unless WORKERS.positive?
raise "Missing fixture skeleton at #{FIXTURE_ROOT}" unless Dir.exist?(FIXTURE_ROOT)
unless %w[plan apply template].include?(COMMAND)
  raise "Unsupported benchmark command #{COMMAND.inspect}"
end

BASE_ENV = {
  "K_JEM_TEMPLATING" => "true",
  "KETTLE_JEM_ACCEPT_CONFIG" => "true",
  "KETTLE_JEM_SKIP_COMMIT" => "true",
  "KETTLE_JEM_SKIP_LOCK_NORMALIZATION" => "true",
  "KETTLE_JEM_TEMPLATE_PROFILE" => "full",
  "KJ_REPOSITORY_TOPOLOGY" => "standalone",
  "KJ_AUTHOR_NAME" => "Benchmark Author",
  "KJ_AUTHOR_EMAIL" => "benchmark@example.com",
  "KJ_AUTHOR_DOMAIN" => "example.com",
  "KJ_GH_USER" => "benchmark",
  "KJ_HOMEPAGE_URI" => "https://example.com/skeleton",
  "allowed" => "true",
  "force" => "true",
  "git_drivers" => "false",
  "hook_templates" => "false"
}.freeze

VARIANTS = [
  {
    name: "classified-main-ractor",
    env: {
      "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
      "KETTLE_JEM_RACTOR_WORKERS" => "0"
    }
  },
  {
    name: "classified-ractor-#{WORKERS}",
    env: {
      "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
      "KETTLE_JEM_RACTOR_WORKERS" => WORKERS.to_s
    }
  }
].freeze

def reset_worktree
  FileUtils.rm_rf(WORKTREE)
  FileUtils.mkdir_p(WORK_PARENT)
  FileUtils.cp_r(FIXTURE_ROOT, WORK_PARENT)
end

def percentile(values, fraction)
  sorted = values.sort
  sorted.fetch([(sorted.length - 1) * fraction, 0].max.round)
end

def summarize(times)
  {
    min: times.min,
    median: percentile(times, 0.5),
    max: times.max,
    mean: times.sum / times.length
  }
end

def report_snapshot(path)
  report = JSON.parse(File.read(path))
  {
    strategy: report["recipe_planning_strategy"],
    workers: report["recipe_planning_workers"],
    recipes: Array(report["recipe_reports"]).length,
    changed: Array(report["changed_files"]).length
  }
end

def run_variant(variant, index)
  report_path = File.join(REPORT_ROOT, "#{variant.fetch(:name)}-#{index}.json")
  env = ENV.to_h.merge(BASE_ENV).merge(variant.fetch(:env))
  command = [
    RbConfig.ruby,
    KETTLE_JEM_EXE,
    COMMAND,
    "--force",
    "--quiet",
    "--accept-config",
    "--skip-commit",
    "--report",
    report_path
  ]

  reset_worktree
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(env, *command, chdir: WORKTREE)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  raise <<~MESSAGE unless status.success?
    Benchmark variant #{variant.fetch(:name)} run #{index} failed with status
    #{status.exitstatus}.
    Command: #{command.join(" ")}
    STDOUT:
    #{stdout}
    STDERR:
    #{stderr}
  MESSAGE

  [elapsed, report_snapshot(report_path)]
ensure
  reset_worktree
end

FileUtils.rm_rf(REPORT_ROOT)
FileUtils.mkdir_p(REPORT_ROOT)
reset_worktree

results = VARIANTS.to_h do |variant|
  times = []
  snapshots = []
  RUNS.times do |index|
    elapsed, snapshot = run_variant(variant, index + 1)
    times << elapsed
    snapshots << snapshot
  end
  [variant.fetch(:name), {times: times, summary: summarize(times), snapshot: snapshots.last}]
end

puts "kettle-jem Ractor planning benchmark"
puts "fixture: #{FIXTURE_ROOT}"
puts "command: kettle-jem #{COMMAND}"
puts "runs: #{RUNS}"
puts
puts format(
  "%-26s %8s %8s %8s %8s %7s %7s",
  "variant",
  "min",
  "median",
  "mean",
  "max",
  "recipes",
  "changed"
)
results.each do |name, result|
  summary = result.fetch(:summary)
  snapshot = result.fetch(:snapshot)
  puts format(
    "%-26s %8.3fs %8.3fs %8.3fs %8.3fs %7d %7d",
    name,
    summary.fetch(:min),
    summary.fetch(:median),
    summary.fetch(:mean),
    summary.fetch(:max),
    snapshot.fetch(:recipes),
    snapshot.fetch(:changed)
  )
end

puts
puts "reports: #{REPORT_ROOT}"
