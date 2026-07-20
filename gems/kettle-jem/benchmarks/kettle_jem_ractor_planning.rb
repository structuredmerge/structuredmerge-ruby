#!/usr/bin/env ruby
# frozen_string_literal: true

require "etc"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"

BENCHMARK_ROOT = File.expand_path(__dir__)
PROJECT_ROOT = File.expand_path("..", BENCHMARK_ROOT)
FIXTURE_ROOT = File.join(BENCHMARK_ROOT, "fixtures", "skeleton")
WORK_PARENT = File.join(PROJECT_ROOT, "tmp", "benchmarks", "work")
WORKTREE = File.join(WORK_PARENT, "skeleton")
REPORT_ROOT = File.join(PROJECT_ROOT, "tmp", "benchmarks", "reports")
SUMMARY_PATH = File.join(PROJECT_ROOT, "tmp", "benchmarks", "summary.json")
RESULTS_README = File.join(BENCHMARK_ROOT, "results", "README.md")
KETTLE_JEM_EXE = File.join(PROJECT_ROOT, "exe", "kettle-jem")
SUMMARIZE_ONLY = ARGV.delete("--summarize-only")
STDOUT.sync = true

RUNS = Integer(ENV.fetch("KETTLE_JEM_BENCHMARK_RUNS", "3"))
WORKER_COUNTS = ENV.fetch("KETTLE_JEM_BENCHMARK_WORKERS", [2, Etc.nprocessors].min.to_s)
  .split(",")
  .map { |value| Integer(value.strip) }
  .uniq
COMMAND = ENV.fetch("KETTLE_JEM_BENCHMARK_COMMAND", "template")

raise "KETTLE_JEM_BENCHMARK_RUNS must be positive" unless RUNS.positive?
raise "KETTLE_JEM_BENCHMARK_WORKERS must include at least one value" if WORKER_COUNTS.empty?
unless WORKER_COUNTS.all?(&:positive?)
  raise "KETTLE_JEM_BENCHMARK_WORKERS values must be positive"
end
raise "Missing fixture skeleton at #{FIXTURE_ROOT}" unless Dir.exist?(FIXTURE_ROOT)
unless %w[plan apply template install].include?(COMMAND)
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
  "KJ_MIN_RUBY" => ENV.fetch("KETTLE_JEM_BENCHMARK_MIN_RUBY", "1.8.7"),
  "allowed" => "true",
  "force" => "true",
  "git_drivers" => "false",
  "hook_templates" => "false"
}.freeze

def benchmark_variants
  variants = [
    {
      name: "baseline-main",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0"
      }
    }
  ]

  WORKER_COUNTS.each do |workers|
    variants << {
      name: "planning-ractor-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => workers.to_s,
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0"
      }
    }
    next if COMMAND == "plan"

    variants << {
      name: "file-ractor-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => workers.to_s
      }
    }
    variants << {
      name: "combined-ractor-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => workers.to_s,
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => workers.to_s
      }
    }
  end
  variants
end

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

def progress(message)
  puts "[#{Time.now.iso8601}] #{message}"
end

def report_snapshot(path)
  report = JSON.parse(File.read(path))
  planning_execution = report.fetch("recipe_planning_execution", {})
  file_execution = report.fetch("file_work_execution", {})
  {
    strategy: report["recipe_planning_strategy"],
    planning_workers: report["recipe_planning_workers"],
    file_workers: report.fetch("file_work_workers", 0),
    worker_safe_recipes: planning_execution.fetch("worker_safe_recipes", 0),
    main_only_recipes: planning_execution.fetch("main_only_recipes", 0),
    ractor_spawns: planning_execution.fetch("ractor_spawn_count", 0),
    ractor_recipes: planning_execution.fetch("ractor_recipe_count", 0),
    file_work_units: file_execution.fetch("file_work_units", 0),
    file_ractor_spawns: file_execution.fetch("file_ractor_spawn_count", 0),
    file_ractor_units: file_execution.fetch("file_ractor_units", 0),
    recipes: Array(report["recipe_reports"]).length,
    changed: Array(report["changed_files"]).length
  }
end

def run_variant(variant, index)
  report_path = File.join(REPORT_ROOT, "#{variant.fetch(:name)}-#{index}.json")
  env = ENV.to_h.merge(BASE_ENV).merge(variant.fetch(:env))
  command = benchmark_command(report_path)

  progress("starting #{variant.fetch(:name)} run #{index}/#{RUNS}")
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

  snapshot = report_snapshot(report_path)
  progress(
    format(
      "finished %<variant>s run %<index>d/%<runs>d in %<elapsed>.3fs (%<recipes>d recipes, %<changed>d changed, %<plan_ractor>d planning ractor recipes, %<file_ractor>d file ractor units)",
      variant: variant.fetch(:name),
      index: index,
      runs: RUNS,
      elapsed: elapsed,
      recipes: snapshot.fetch(:recipes),
      changed: snapshot.fetch(:changed),
      plan_ractor: snapshot.fetch(:ractor_recipes),
      file_ractor: snapshot.fetch(:file_ractor_units)
    )
  )
  [elapsed, snapshot]
ensure
  reset_worktree
end

def benchmark_command(report_path)
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
  command
end

def format_seconds(value)
  format("%.3fs", value)
end

def summary_payload(results, generated_at: Time.now)
  {
    generated_at: generated_at.iso8601,
    fixture: FIXTURE_ROOT,
    command: "kettle-jem #{COMMAND}",
    runs: RUNS,
    worker_counts: WORKER_COUNTS,
    min_ruby: BASE_ENV.fetch("KJ_MIN_RUBY"),
    report_root: REPORT_ROOT,
    variants: results.transform_values do |result|
      {
        times: result.fetch(:times),
        summary: result.fetch(:summary),
        snapshot: result.fetch(:snapshot)
      }
    end
  }
end

def write_summary_json(payload)
  FileUtils.mkdir_p(File.dirname(SUMMARY_PATH))
  File.write(SUMMARY_PATH, "#{JSON.pretty_generate(payload)}\n")
end

def read_summary_json
  raise "Missing benchmark summary at #{SUMMARY_PATH}" unless File.file?(SUMMARY_PATH)

  JSON.parse(File.read(SUMMARY_PATH))
end

def build_results_readme(payload)
  variants = payload.fetch("variants")
  lines = [
    "# kettle-jem benchmark results",
    "",
    "Last generated: `#{payload.fetch("generated_at")}`",
    "",
    "| Setting | Value |",
    "| --- | --- |",
    "| Fixture | `#{payload.fetch("fixture")}` |",
    "| Command | `#{payload.fetch("command")}` |",
    "| Runs per variant | `#{payload.fetch("runs")}` |",
    "| Worker counts | `#{payload.fetch("worker_counts").join(", ")}` |",
    "| Minimum Ruby | `#{payload.fetch("min_ruby")}` |",
    "| Source reports | `#{payload.fetch("report_root")}` |",
    "",
    "| Variant | Min | Median | Mean | Max | Plan workers | File workers | Safe recipes | Plan spawns | Plan Ractor recipes | File units | File spawns | File Ractor units | Recipes | Changed |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
  ]
  variants.each do |name, result|
    summary = result.fetch("summary")
    snapshot = result.fetch("snapshot")
    lines << format(
      "| `%<name>s` | %<min>s | %<median>s | %<mean>s | %<max>s | %<plan>d | %<file>d | %<safe>d | %<plan_spawns>d | %<plan_ractor_recipes>d | %<file_units>d | %<file_spawns>d | %<file_ractor_units>d | %<recipes>d | %<changed>d |",
      name: name,
      min: format_seconds(summary.fetch("min")),
      median: format_seconds(summary.fetch("median")),
      mean: format_seconds(summary.fetch("mean")),
      max: format_seconds(summary.fetch("max")),
      plan: snapshot.fetch("planning_workers"),
      file: snapshot.fetch("file_workers"),
      safe: snapshot.fetch("worker_safe_recipes"),
      plan_spawns: snapshot.fetch("ractor_spawns"),
      plan_ractor_recipes: snapshot.fetch("ractor_recipes"),
      file_units: snapshot.fetch("file_work_units"),
      file_spawns: snapshot.fetch("file_ractor_spawns"),
      file_ractor_units: snapshot.fetch("file_ractor_units"),
      recipes: snapshot.fetch("recipes"),
      changed: snapshot.fetch("changed")
    )
  end
  lines << ""
  lines << "These results are generated by `ruby benchmarks/kettle_jem_ractor_planning.rb`."
  lines << "Regenerate this README from the saved summary without rerunning the benchmark with:"
  lines << ""
  lines << "```bash"
  lines << "ruby benchmarks/kettle_jem_ractor_planning.rb --summarize-only"
  lines << "```"
  lines << ""
  "#{lines.join("\n")}\n"
end

def write_results_readme(payload)
  FileUtils.mkdir_p(File.dirname(RESULTS_README))
  File.write(RESULTS_README, build_results_readme(payload))
end

if SUMMARIZE_ONLY
  payload = read_summary_json
  write_results_readme(payload)
  puts "results README: #{RESULTS_README}"
  exit
end

FileUtils.rm_rf(REPORT_ROOT)
FileUtils.mkdir_p(REPORT_ROOT)
reset_worktree

variants = benchmark_variants
puts "kettle-jem Ractor planning benchmark"
puts "fixture: #{FIXTURE_ROOT}"
puts "command: kettle-jem #{COMMAND}"
puts "runs: #{RUNS}"
puts "worker counts: #{WORKER_COUNTS.join(", ")}"
puts "variants: #{variants.length}"
puts
results = variants.to_h do |variant|
  times = []
  snapshots = []
  RUNS.times do |index|
    elapsed, snapshot = run_variant(variant, index + 1)
    times << elapsed
    snapshots << snapshot
  end
  [variant.fetch(:name), {times: times, summary: summarize(times), snapshot: snapshots.last}]
end

puts
puts "summary"
puts
puts format(
  "%-28s %8s %8s %8s %8s %7s %7s %7s %7s %7s %7s %7s %7s %7s %7s",
  "variant",
  "min",
  "median",
  "mean",
  "max",
  "plan_w",
  "file_w",
  "safe",
  "p_spawn",
  "p_jobs",
  "f_units",
  "f_spawn",
  "f_jobs",
  "recipes",
  "changed"
)
results.each do |name, result|
  summary = result.fetch(:summary)
  snapshot = result.fetch(:snapshot)
  puts format(
    "%-28s %8.3fs %8.3fs %8.3fs %8.3fs %7d %7d %7d %7d %7d %7d %7d %7d %7d %7d",
    name,
    summary.fetch(:min),
    summary.fetch(:median),
    summary.fetch(:mean),
    summary.fetch(:max),
    snapshot.fetch(:planning_workers),
    snapshot.fetch(:file_workers),
    snapshot.fetch(:worker_safe_recipes),
    snapshot.fetch(:ractor_spawns),
    snapshot.fetch(:ractor_recipes),
    snapshot.fetch(:file_work_units),
    snapshot.fetch(:file_ractor_spawns),
    snapshot.fetch(:file_ractor_units),
    snapshot.fetch(:recipes),
    snapshot.fetch(:changed)
  )
end

payload = summary_payload(results)
write_summary_json(payload)
write_results_readme(JSON.parse(JSON.generate(payload)))

puts
puts "reports: #{REPORT_ROOT}"
puts "summary: #{SUMMARY_PATH}"
puts "results README: #{RESULTS_README}"
