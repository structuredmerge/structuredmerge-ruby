# kettle-jem benchmarks

This directory contains a repeatable benchmark harness for comparing
`kettle-jem` recipe planning and phase-gated file work with and without opt-in
Ractor workers.

The fixture at `fixtures/skeleton/` is generated from a standard
`bundle gem skeleton --git` run, with the generated `.git/` directory removed
so the skeleton can be committed as project data. Benchmark runs never mutate
that fixture directly. Each measured run copies it into `tmp/benchmarks/work/`,
runs one-shot templating from that copied gem root, writes reports under
`tmp/benchmarks/reports/`, writes a machine-readable timing summary to
`tmp/benchmarks/summary.json`, updates `results/README.md`, and resets the
copied skeleton before and after the run.

Run the benchmark from the `kettle-jem` project root:

```bash
mise exec -C /path/to/kettle-jem -- ruby benchmarks/kettle_jem_ractor_planning.rb
```

Useful environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `KETTLE_JEM_BENCHMARK_RUNS` | `3` | Number of measured runs for each variant. |
| `KETTLE_JEM_BENCHMARK_WORKERS` | `min(2, Etc.nprocessors)` | Comma-separated worker counts for Ractor and thread variants. |
| `KETTLE_JEM_BENCHMARK_COMMAND` | `template` | Public `kettle-jem` command to benchmark: `plan`, `apply`, `template`, or `install`. |
| `KETTLE_JEM_BENCHMARK_MIN_RUBY` | `1.8.7` | Minimum Ruby value passed through `KJ_MIN_RUBY` to broaden generated workflow/gemfile coverage. |

The default `template` benchmark compares:

- baseline classified planning with no Ractor workers
- planning-only Ractor workers via `KETTLE_JEM_RACTOR_WORKERS`
- planning-only thread workers via `KETTLE_JEM_THREAD_WORKERS`
- file-only Ractor workers via `KETTLE_JEM_RACTOR_FILE_WORKERS`
- file-only thread workers via `KETTLE_JEM_THREAD_FILE_WORKERS`
- combined planning and file Ractor workers
- combined planning and file thread workers

Benchmark summaries include planning execution counters from each report:
worker-safe recipe count, Ractor/thread spawn count, and recipe count actually
executed by planning Ractors or threads. They also include file-work counters:
file work units, file-worker Ractor/thread spawns, and file work units committed
in Ractors or threads. These counters distinguish "workers were enabled" from
"work actually ran concurrently".

Long runs print timestamped progress lines before and after each measured
variant run, including elapsed seconds, recipe/change counts, planning Ractor
and thread recipe counts, and file Ractor/thread unit counts for completed runs.

For `plan`, file-worker variants are skipped because no filesystem apply phase
runs. The default `template --accept-config` run exercises kettle-jem's
supported one-shot flow: environment variables seed `.structuredmerge/kettle-jem.yml`,
the config bootstrap is written, and the install/template task continues through
the follow-up apply against that config.

The latest committed benchmark summary lives at `results/README.md`. If the
full benchmark has already run and `tmp/benchmarks/summary.json` still exists,
regenerate only that committed summary without rerunning templating:

```bash
mise exec -C /path/to/kettle-jem -- ruby benchmarks/kettle_jem_ractor_planning.rb --summarize-only
```
