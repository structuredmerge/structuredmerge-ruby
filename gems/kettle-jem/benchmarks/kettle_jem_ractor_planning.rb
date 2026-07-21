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
KETTLE_JEM_GEMFILE = File.join(PROJECT_ROOT, "Gemfile")
SUMMARIZE_ONLY = ARGV.delete("--summarize-only")
STDOUT.sync = true

RUNS = Integer(ENV.fetch("KETTLE_JEM_BENCHMARK_RUNS", "3"))
NPROCESSORS = Etc.nprocessors
HALF_NPROCESSORS = [1, NPROCESSORS / 2].max
DEFAULT_WORKER_COUNTS = [1, [4, HALF_NPROCESSORS].min, [8, HALF_NPROCESSORS].min, NPROCESSORS].uniq
WORKER_COUNTS = ENV.fetch("KETTLE_JEM_BENCHMARK_WORKERS", DEFAULT_WORKER_COUNTS.join(","))
  .split(",")
  .map { |value| Integer(value.strip) }
  .uniq
COMMAND = ENV.fetch("KETTLE_JEM_BENCHMARK_COMMAND", "template")
BENCHMARK_MODE = ENV.fetch("KETTLE_JEM_BENCHMARK_MODE", "install-template")

raise "KETTLE_JEM_BENCHMARK_RUNS must be positive" unless RUNS.positive?
raise "KETTLE_JEM_BENCHMARK_WORKERS must include at least one value" if WORKER_COUNTS.empty?
unless WORKER_COUNTS.all?(&:positive?)
  raise "KETTLE_JEM_BENCHMARK_WORKERS values must be positive"
end
raise "Missing fixture skeleton at #{FIXTURE_ROOT}" unless Dir.exist?(FIXTURE_ROOT)
unless %w[plan apply template install].include?(COMMAND)
  raise "Unsupported benchmark command #{COMMAND.inspect}"
end
unless %w[install-template raw-template].include?(BENCHMARK_MODE)
  raise "Unsupported benchmark mode #{BENCHMARK_MODE.inspect}"
end
if COMMAND != "template" && BENCHMARK_MODE != "install-template"
  raise "KETTLE_JEM_BENCHMARK_MODE=#{BENCHMARK_MODE} requires KETTLE_JEM_BENCHMARK_COMMAND=template"
end

BASE_ENV = {
  "BUNDLE_GEMFILE" => KETTLE_JEM_GEMFILE,
  "STRUCTUREDMERGE_DEV" => ENV.fetch("STRUCTUREDMERGE_DEV", File.expand_path("..", PROJECT_ROOT)),
  "KETTLE_JEM_ACCEPT_CONFIG" => "true",
  "KETTLE_JEM_SKIP_COMMIT" => "true",
  "KETTLE_JEM_SKIP_DRIFT_CHECK" => "true",
  "KETTLE_JEM_SKIP_RUBOCOP_GRADUAL" => "true",
  "KETTLE_JEM_SKIP_BINSTUBS" => "true",
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
        "KETTLE_JEM_THREAD_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0",
        "KETTLE_JEM_THREAD_FILE_WORKERS" => "0"
      }
    }
  ]

  WORKER_COUNTS.each do |workers|
    variants << {
      name: "planning-ractor-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => workers.to_s,
        "KETTLE_JEM_THREAD_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0",
        "KETTLE_JEM_THREAD_FILE_WORKERS" => "0"
      }
    }
    variants << {
      name: "planning-thread-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => "0",
        "KETTLE_JEM_THREAD_WORKERS" => workers.to_s,
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0",
        "KETTLE_JEM_THREAD_FILE_WORKERS" => "0"
      }
    }
    next if COMMAND == "plan"

    variants << {
      name: "file-ractor-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => "0",
        "KETTLE_JEM_THREAD_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => workers.to_s,
        "KETTLE_JEM_THREAD_FILE_WORKERS" => "0"
      }
    }
    variants << {
      name: "file-thread-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => "0",
        "KETTLE_JEM_THREAD_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0",
        "KETTLE_JEM_THREAD_FILE_WORKERS" => workers.to_s
      }
    }
    variants << {
      name: "combined-ractor-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => workers.to_s,
        "KETTLE_JEM_THREAD_WORKERS" => "0",
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => workers.to_s,
        "KETTLE_JEM_THREAD_FILE_WORKERS" => "0"
      }
    }
    variants << {
      name: "combined-thread-#{workers}",
      env: {
        "KETTLE_JEM_RECIPE_PLANNING_STRATEGY" => "classified",
        "KETTLE_JEM_RACTOR_WORKERS" => "0",
        "KETTLE_JEM_THREAD_WORKERS" => workers.to_s,
        "KETTLE_JEM_RACTOR_FILE_WORKERS" => "0",
        "KETTLE_JEM_THREAD_FILE_WORKERS" => workers.to_s
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
  phase_timings = Array(report["phase_timings"])
  install_steps = Array(report["install_steps"]) + Array(report["template_steps"])
  command_duration_ms = install_steps.sum do |step|
    command_results = Array(step["command_results"])
    if command_results.empty?
      step.fetch("duration_ms", 0).to_f
    else
      command_results.sum { |result| result.fetch("duration_ms", 0).to_f }
    end
  end
  readme_timings = report_readme_timings(report)
  {
    strategy: report["recipe_planning_strategy"],
    planning_workers: report["recipe_planning_workers"],
    planning_thread_workers: report.fetch("recipe_planning_thread_workers", 0),
    file_workers: report.fetch("file_work_workers", 0),
    file_thread_workers: report.fetch("file_work_thread_workers", 0),
    worker_safe_recipes: planning_execution.fetch("worker_safe_recipes", 0),
    main_only_recipes: planning_execution.fetch("main_only_recipes", 0),
    ractor_spawns: planning_execution.fetch("ractor_spawn_count", 0),
    ractor_recipes: planning_execution.fetch("ractor_recipe_count", 0),
    thread_spawns: planning_execution.fetch("thread_spawn_count", 0),
    thread_recipes: planning_execution.fetch("thread_recipe_count", 0),
    file_work_units: file_execution.fetch("file_work_units", 0),
    file_ractor_spawns: file_execution.fetch("file_ractor_spawn_count", 0),
    file_ractor_units: file_execution.fetch("file_ractor_units", 0),
    file_thread_spawns: file_execution.fetch("file_thread_spawn_count", 0),
    file_thread_units: file_execution.fetch("file_thread_units", 0),
    phase_duration_ms: phase_timings.sum { |entry| entry.fetch("duration_ms", 0).to_f }.round(3),
    recipes_duration_ms: phase_timings.select { |entry| entry.fetch("phase", "") == "recipes" }.sum { |entry| entry.fetch("duration_ms", 0).to_f }.round(3),
    apply_duration_ms: phase_timings.select { |entry| entry.fetch("phase", "") == "apply" }.sum { |entry| entry.fetch("duration_ms", 0).to_f }.round(3),
    command_duration_ms: command_duration_ms.round(3),
    readme_duration_ms: readme_timings.sum { |entry| entry.fetch(:duration_ms, 0).to_f }.round(3),
    readme_timings: readme_timings,
    recipes: Array(report["recipe_reports"]).length,
    changed: Array(report["changed_files"]).length
  }
end

def report_readme_timings(report)
  timings = Array(report["recipe_reports"]).flat_map do |recipe_report|
    next [] unless recipe_report["relative_path"].to_s == "README.md"

    Array(recipe_report.dig("metadata", "readme_timings"))
  end.compact
  grouped = timings.each_with_object({}) do |timing, groups|
    name = timing.fetch("name").to_s
    group = groups[name] ||= {name: name, count: 0, duration_ms: 0.0}
    group[:count] += 1
    group[:duration_ms] += timing.fetch("duration_ms", 0).to_f
  end
  grouped.values
    .map { |entry| entry.merge(duration_ms: entry.fetch(:duration_ms).round(3)) }
    .sort_by { |entry| -entry.fetch(:duration_ms) }
end

def run_variant(variant, index)
  report_path = File.join(REPORT_ROOT, "#{variant.fetch(:name)}-#{index}.json")
  env = ENV.to_h.merge(BASE_ENV).merge(variant.fetch(:env))
  command = benchmark_command(report_path)

  progress("starting #{variant.fetch(:name)} run #{index}/#{RUNS}")
  reset_worktree
  prepare_raw_template_worktree(env) if raw_template_mode?
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
      "finished %<variant>s run %<index>d/%<runs>d in %<elapsed>.3fs (%<recipes>d recipes, %<changed>d changed, plan ractor/thread %<plan_ractor>d/%<plan_thread>d, file ractor/thread %<file_ractor>d/%<file_thread>d)",
      variant: variant.fetch(:name),
      index: index,
      runs: RUNS,
      elapsed: elapsed,
      recipes: snapshot.fetch(:recipes),
      changed: snapshot.fetch(:changed),
      plan_ractor: snapshot.fetch(:ractor_recipes),
      plan_thread: snapshot.fetch(:thread_recipes),
      file_ractor: snapshot.fetch(:file_ractor_units),
      file_thread: snapshot.fetch(:file_thread_units)
    )
  )
  [elapsed, snapshot]
ensure
  reset_worktree
end

def benchmark_command(report_path)
  command = [
    "bundle",
    "exec",
    "env",
    "K_JEM_TEMPLATING=true",
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
  command.concat(raw_template_command_options) if raw_template_mode?
  command
end

def prepare_raw_template_worktree(env)
  report_path = File.join(REPORT_ROOT, "raw-template-bootstrap.json")
  command = [
    "bundle",
    "exec",
    "env",
    "K_JEM_TEMPLATING=true",
    RbConfig.ruby,
    KETTLE_JEM_EXE,
    "template",
    "--force",
    "--quiet",
    "--accept-config",
    "--skip-commit",
    "--report",
    report_path,
    "--only",
    ".structuredmerge/kettle-jem.yml"
  ]
  _stdout, stderr, status = Open3.capture3(env, *command, chdir: WORKTREE)
  return if status.success?

  raise <<~MESSAGE
    Raw-template benchmark bootstrap failed with status #{status.exitstatus}.
    Command: #{command.join(" ")}
    STDERR:
    #{stderr}
  MESSAGE
end

def raw_template_mode?
  COMMAND == "template" && BENCHMARK_MODE == "raw-template"
end

def raw_template_command_options
  ["--only", "**/*"]
end

def benchmark_command_label
  label = "kettle-jem #{COMMAND}"
  label = "#{label} #{raw_template_command_options.join(" ")}" if raw_template_mode?
  label
end

def format_seconds(value)
  format("%.3fs", value)
end

def format_baseline_delta(value, baseline)
  return "n/a" if baseline.to_f.zero?

  format("%+.1f%%", ((value - baseline) / baseline) * 100.0)
end

def format_share(value, total)
  return "n/a" if total.to_f.zero?

  format("%.1f%%", (value / total) * 100.0)
end

def timing_entry_value(entry, key, default = nil)
  entry.fetch(key.to_s) { entry.fetch(key.to_sym, default) }
end

def summary_payload(results, generated_at: Time.now)
  {
    generated_at: generated_at.iso8601,
    fixture: FIXTURE_ROOT,
    command: benchmark_command_label,
    mode: BENCHMARK_MODE,
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
  snapshot_count = ->(snapshot, key) { snapshot.fetch(key, 0) }
  baseline_median = variants.fetch("baseline-main").fetch("summary").fetch("median")
  baseline_readme_timings = Array(variants.fetch("baseline-main").fetch("snapshot").fetch("readme_timings", []))
  lines = [
    "# kettle-jem benchmark results",
    "",
    "Last generated: `#{payload.fetch("generated_at")}`",
    "",
    "| Setting | Value |",
    "| --- | --- |",
    "| Fixture | `#{payload.fetch("fixture")}` |",
    "| Command | `#{payload.fetch("command")}` |",
    "| Mode | `#{payload.fetch("mode", "install-template")}` |",
    "| Runs per variant | `#{payload.fetch("runs")}` |",
    "| Worker counts | `#{payload.fetch("worker_counts").join(", ")}` |",
    "| Minimum Ruby | `#{payload.fetch("min_ruby")}` |",
    "| Source reports | `#{payload.fetch("report_root")}` |",
    "",
    "| Variant | +/- baseline | Min | Median | Mean | Max | Recipe phase | Command steps | Plan Ractors | Plan threads | File Ractors | File threads | Safe recipes | Plan Ractor jobs | Plan thread jobs | File units | File Ractor units | File thread units | Recipes | Changed |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
  ]
  variants.each do |name, result|
    summary = result.fetch("summary")
    snapshot = result.fetch("snapshot")
    lines << format(
      "| `%<name>s` | %<baseline_delta>s | %<min>s | %<median>s | %<mean>s | %<max>s | %<recipe_phase>s | %<command_steps>s | %<plan_ractors>d | %<plan_threads>d | %<file_ractors>d | %<file_threads>d | %<safe>d | %<plan_ractor_recipes>d | %<plan_thread_recipes>d | %<file_units>d | %<file_ractor_units>d | %<file_thread_units>d | %<recipes>d | %<changed>d |",
      name: name,
      baseline_delta: format_baseline_delta(summary.fetch("median"), baseline_median),
      min: format_seconds(summary.fetch("min")),
      median: format_seconds(summary.fetch("median")),
      mean: format_seconds(summary.fetch("mean")),
      max: format_seconds(summary.fetch("max")),
      recipe_phase: format_seconds(snapshot_count.call(snapshot, "recipes_duration_ms") / 1000.0),
      command_steps: format_seconds(snapshot_count.call(snapshot, "command_duration_ms") / 1000.0),
      plan_ractors: snapshot_count.call(snapshot, "planning_workers"),
      plan_threads: snapshot_count.call(snapshot, "planning_thread_workers"),
      file_ractors: snapshot_count.call(snapshot, "file_workers"),
      file_threads: snapshot_count.call(snapshot, "file_thread_workers"),
      safe: snapshot_count.call(snapshot, "worker_safe_recipes"),
      plan_ractor_recipes: snapshot_count.call(snapshot, "ractor_recipes"),
      plan_thread_recipes: snapshot_count.call(snapshot, "thread_recipes"),
      file_units: snapshot_count.call(snapshot, "file_work_units"),
      file_ractor_units: snapshot_count.call(snapshot, "file_ractor_units"),
      file_thread_units: snapshot_count.call(snapshot, "file_thread_units"),
      recipes: snapshot_count.call(snapshot, "recipes"),
      changed: snapshot_count.call(snapshot, "changed")
    )
  end
  unless baseline_readme_timings.empty?
    baseline_readme_total = baseline_readme_timings.sum { |entry| timing_entry_value(entry, :duration_ms, 0).to_f }
    lines << ""
    lines << "## Baseline README timing breakdown"
    lines << ""
    lines << "| Step | Duration | Share | Count |"
    lines << "| --- | ---: | ---: | ---: |"
    baseline_readme_timings.each do |entry|
      duration_ms = timing_entry_value(entry, :duration_ms, 0).to_f
      count = timing_entry_value(entry, :count, 0)
      lines << format(
        "| `%<name>s` | %<duration>s | %<share>s | %<count>d |",
        name: timing_entry_value(entry, :name),
        duration: format_seconds(duration_ms / 1000.0),
        share: format_share(duration_ms, baseline_readme_total),
        count: count
      )
    end
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
puts "command: #{benchmark_command_label}"
puts "mode: #{BENCHMARK_MODE}"
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
baseline_median = results.fetch("baseline-main").fetch(:summary).fetch(:median)
puts format(
  "%-28s %8s %8s %8s %8s %8s %8s %8s %4s %4s %4s %4s %4s %4s %4s %4s %4s %4s %7s %7s",
  "variant",
  "+/-",
  "min",
  "median",
  "mean",
  "max",
  "recipes",
  "cmds",
  "pr",
  "pt",
  "fr",
  "ft",
  "safe",
  "f_units",
  "pr_job",
  "pt_job",
  "fr_job",
  "ft_job",
  "recipes",
  "changed"
)
results.each do |name, result|
  summary = result.fetch(:summary)
  snapshot = result.fetch(:snapshot)
  puts format(
    "%-28s %8s %8.3fs %8.3fs %8.3fs %8.3fs %8.3fs %8.3fs %4d %4d %4d %4d %4d %4d %4d %4d %4d %4d %7d %7d",
    name,
    format_baseline_delta(summary.fetch(:median), baseline_median),
    summary.fetch(:min),
    summary.fetch(:median),
    summary.fetch(:mean),
    summary.fetch(:max),
    snapshot.fetch(:recipes_duration_ms) / 1000.0,
    snapshot.fetch(:command_duration_ms) / 1000.0,
    snapshot.fetch(:planning_workers),
    snapshot.fetch(:planning_thread_workers),
    snapshot.fetch(:file_workers),
    snapshot.fetch(:file_thread_workers),
    snapshot.fetch(:worker_safe_recipes),
    snapshot.fetch(:file_work_units),
    snapshot.fetch(:ractor_recipes),
    snapshot.fetch(:thread_recipes),
    snapshot.fetch(:file_ractor_units),
    snapshot.fetch(:file_thread_units),
    snapshot.fetch(:recipes),
    snapshot.fetch(:changed)
  )
end
baseline_readme_timings = Array(results.fetch("baseline-main").fetch(:snapshot).fetch(:readme_timings, []))
unless baseline_readme_timings.empty?
  baseline_readme_total = baseline_readme_timings.sum { |entry| entry.fetch(:duration_ms).to_f }
  puts
  puts "baseline README timings"
  puts
  puts format("%-44s %10s %8s %5s", "step", "duration", "share", "count")
  baseline_readme_timings.each do |entry|
    puts format(
      "%-44s %10.3fs %8s %5d",
      entry.fetch(:name),
      entry.fetch(:duration_ms) / 1000.0,
      format_share(entry.fetch(:duration_ms), baseline_readme_total),
      entry.fetch(:count)
    )
  end
end

payload = summary_payload(results)
write_summary_json(payload)
write_results_readme(JSON.parse(JSON.generate(payload)))

puts
puts "reports: #{REPORT_ROOT}"
puts "summary: #{SUMMARY_PATH}"
puts "results README: #{RESULTS_README}"
