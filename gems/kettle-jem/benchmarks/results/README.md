# kettle-jem benchmark results

Last generated: `2026-07-20T15:52:13-06:00`

This committed snapshot records the last completed benchmark run for quick
reference. The run predates persisted timing summaries, so the recipe and
changed-file counts come from the saved JSON reports under
`tmp/benchmarks/reports/`, while the elapsed-time values below are the captured
benchmark summary from that run. Future runs write `tmp/benchmarks/summary.json`
and regenerate this README with complete per-variant min, median, mean, and max
timings automatically.

| Setting | Value |
| --- | --- |
| Fixture | `benchmarks/fixtures/skeleton` |
| Command | `kettle-jem template --force --quiet --accept-config --skip-commit --report REPORT` |
| Runs per variant | `3` |
| Worker counts | `1, 2, 4, 8, 16, 22` |
| Minimum Ruby | `1.8.7` |
| Result surface | `146` recipes / `134` changed files |

| Variant group | Result |
| --- | --- |
| `baseline-main` | Median `21.914s` |
| `planning-ractor-1` | Median `21.956s` |
| `planning-ractor-8` | Median `22.572s` |
| `planning-ractor-22` | Median `22.687s` |
| `file-ractor-*` | Median range `24.904s` to `30.147s`; `file-ractor-22` had a max outlier of `56.206s` |
| `combined-ractor-*` | Median range `24.787s` to `29.215s` |

Summary: the realistic one-shot templating benchmark did not show a performance
gain from Ractors. Planning-only Ractors were approximately even with baseline
but slightly slower, and file-worker or combined Ractors were materially slower
on this workload.

Regenerate this README after a future full run:

```bash
ruby benchmarks/kettle_jem_ractor_planning.rb --summarize-only
```
