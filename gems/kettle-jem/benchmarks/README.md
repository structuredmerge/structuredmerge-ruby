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

## Examples

Default install-orchestrated benchmark:

```console
cd /home/pboling/src/my/structuredmerge/ruby/gems/kettle-jem

mise exec -C . -- env \
K_JEM_TEMPLATING=true \
STRUCTUREDMERGE_DEV=/home/pboling/src/my/structuredmerge/ruby/gems \
VENDORED_GEMS= \
VENDOR_GEM_DIR= \
KETTLE_JEM_BENCHMARK_RUNS=3 \
bundle exec ruby benchmarks/kettle_jem_ractor_planning.rb
```

Raw template-only benchmark:

```console
cd /home/pboling/src/my/structuredmerge/ruby/gems/kettle-jem

mise exec -C . -- env \
K_JEM_TEMPLATING=true \
STRUCTUREDMERGE_DEV=/home/pboling/src/my/structuredmerge/ruby/gems \
VENDORED_GEMS= \
VENDOR_GEM_DIR= \
KETTLE_JEM_BENCHMARK_MODE=raw-template \
KETTLE_JEM_BENCHMARK_RUNS=3 \
bundle exec ruby benchmarks/kettle_jem_ractor_planning.rb
```

`raw-template` pre-bootstraps `.structuredmerge/kettle-jem.yml` outside the measured interval, then benchmarks scoped template `--only "**/*"` so it routes through `TemplateTask` instead of the default install-orchestrated flow.

Combined-worker-only benchmark:

```console
cd /home/pboling/src/my/structuredmerge/ruby/gems/kettle-jem

mise exec -C . -- env \
K_JEM_TEMPLATING=true \
STRUCTUREDMERGE_DEV=/home/pboling/src/my/structuredmerge/ruby/gems \
VENDORED_GEMS= \
VENDOR_GEM_DIR= \
KETTLE_JEM_BENCHMARK_RUNS=3 \
bundle exec ruby benchmarks/kettle_jem_ractor_planning.rb --only combined
```

`--only combined` retains `baseline-main` for delta calculations and skips the planning-only and file-only split variants. Multiple selectors can be comma-separated or repeated.

## ENV Variables

Useful environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `KETTLE_JEM_BENCHMARK_RUNS` | `3` | Number of measured runs for each variant. |
| `KETTLE_JEM_BENCHMARK_WORKERS` | `1,min(4,n/2),min(8,n/2),n` | Comma-separated worker counts for Ractor and thread variants, where `n` is `Etc.nprocessors`. |
| `KETTLE_JEM_BENCHMARK_COMMAND` | `template` | Public `kettle-jem` command to benchmark: `plan`, `apply`, `template`, or `install`. |
| `KETTLE_JEM_BENCHMARK_MODE` | `install-template` | Template benchmark mode: `install-template` keeps the one-shot install orchestration path; `raw-template` scopes `template` to all targets with `--only "**/*"` so it routes through `TemplateTask`. |
| `KETTLE_JEM_BENCHMARK_ONLY` | unset | Optional comma-separated variant selectors: `baseline`, `planning`, `file`, `combined`, `ractor`, or `thread`. CLI `--only` uses the same tokens and combines with this env var. |
| `KETTLE_JEM_BENCHMARK_MIN_RUBY` | `1.8.7` | Minimum Ruby value passed through `KJ_MIN_RUBY` to broaden generated workflow/gemfile coverage. |

Benchmark runs set `KETTLE_JEM_SKIP_DRIFT_CHECK=true`,
`KETTLE_JEM_SKIP_RUBOCOP_GRADUAL=true`, `KETTLE_JEM_SKIP_BINSTUBS=true`, and
`KETTLE_JEM_SKIP_LOCK_NORMALIZATION=true` so external drift/style/setup cleanup
does not pad the template timing comparison.

The harness invokes `exe/kettle-jem` through the kettle-jem development bundle
with `BUNDLE_GEMFILE` pinned to this checkout's `Gemfile`, so local sibling
StructuredMerge APIs are used while destination setup commands still sanitize
Bundler activation and select the copied fixture's own Gemfile. `K_JEM_TEMPLATING`
is applied only to the executed `kettle-jem` process, not to Bundler's Gemfile
evaluation. By default this resolves the released
`tree_sitter_language_pack` gem; set `VENDORED_GEMS=tree_sitter_language_pack`
and `VENDOR_GEM_DIR` to benchmark against a local vendored source instead.

The default `template` benchmark compares:

- baseline classified planning with no Ractor workers
- planning-only Ractor workers via `KETTLE_JEM_RACTOR_WORKERS`
- planning-only thread workers via `KETTLE_JEM_THREAD_WORKERS`
- file-only Ractor workers via `KETTLE_JEM_RACTOR_FILE_WORKERS`
- file-only thread workers via `KETTLE_JEM_THREAD_FILE_WORKERS`
- combined planning and file Ractor workers
- combined planning and file thread workers

Use `--only combined` or `KETTLE_JEM_BENCHMARK_ONLY=combined` when only the combined planning+file worker runs are useful. Baseline remains selected automatically so the summary can still show percentage deltas.

Benchmark summaries include planning execution counters from each report:
worker-safe recipe count, Ractor/thread spawn count, and recipe count actually
executed by planning Ractors or threads. They also include file-work counters:
file work units, file-worker Ractor/thread spawns, and file work units committed
in Ractors or threads. These counters distinguish "workers were enabled" from
"work actually ran concurrently".

Reports also persist phase durations and install command-step durations. The
benchmark table surfaces recipe-phase and external-command time separately so
template execution changes are not hidden by setup commands. Summary tables also
show each variant's median wall-clock percentage delta against `baseline-main`
as the second column. When README sub-step timings are present, the generated
results README also includes a baseline README timing breakdown so repeated
Markdown/AST work can be targeted directly.

Long runs print timestamped progress lines before and after each measured
variant run, including elapsed seconds, recipe/change counts, planning Ractor
and thread recipe counts, and file Ractor/thread unit counts for completed runs.

For `plan`, file-worker variants are skipped because no filesystem apply phase
runs. The default `template --accept-config` run exercises kettle-jem's
supported one-shot install flow: environment variables seed
`.structuredmerge/kettle-jem.yml`, the config bootstrap is written, and the
install/template task continues through the follow-up apply against that config.
Set `KETTLE_JEM_BENCHMARK_MODE=raw-template` to benchmark scoped
`template --only "**/*"` runs through `TemplateTask`, which isolates raw template
apply work from install orchestration. Raw-template mode first writes
`.structuredmerge/kettle-jem.yml` outside the measured interval so the timed run
uses the same accepted configuration shape without measuring install
orchestration.

The latest committed benchmark summary lives at `results/README.md`. If the
full benchmark has already run and `tmp/benchmarks/summary.json` still exists,
regenerate only that committed summary without rerunning templating:

```bash
mise exec -C /path/to/kettle-jem -- ruby benchmarks/kettle_jem_ractor_planning.rb --summarize-only
```
