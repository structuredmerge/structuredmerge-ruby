# kettle-jem benchmarks

This directory contains a repeatable benchmark harness for comparing
`kettle-jem` recipe planning and phase-gated file work with and without opt-in
Ractor workers.

The fixture at `fixtures/skeleton/` is generated from a standard
`bundle gem skeleton --git` run, with the generated `.git/` directory removed
so the skeleton can be committed as project data. Benchmark runs never mutate
that fixture directly. Each measured run copies it into `tmp/benchmarks/work/`,
runs one-shot templating from that copied gem root, writes reports under
`tmp/benchmarks/reports/`, and resets the copied skeleton before and after the
run.

Run the benchmark from the `kettle-jem` project root:

```bash
mise exec -C /path/to/kettle-jem -- ruby benchmarks/kettle_jem_ractor_planning.rb
```

Useful environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `KETTLE_JEM_BENCHMARK_RUNS` | `3` | Number of measured runs for each variant. |
| `KETTLE_JEM_BENCHMARK_WORKERS` | `min(2, Etc.nprocessors)` | Comma-separated worker counts for Ractor variants. |
| `KETTLE_JEM_BENCHMARK_COMMAND` | `apply` | Public `kettle-jem` command to benchmark: `plan`, `apply`, or `template`. |

The default `apply` benchmark compares:

- baseline classified planning with no Ractor workers
- planning-only Ractor workers via `KETTLE_JEM_RACTOR_WORKERS`
- file-only Ractor workers via `KETTLE_JEM_RACTOR_FILE_WORKERS`
- combined planning and file Ractor workers

For `plan`, file-worker variants are skipped because no filesystem apply phase
runs. The harness sets the first-run `kettle-jem` config values through
environment variables so the copied skeleton can be templated non-interactively.
