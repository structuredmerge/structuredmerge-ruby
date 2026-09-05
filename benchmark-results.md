<!-- structuredmerge-benchmark-report:start -->
## StructuredMerge Benchmark

| Property | Value |
| --- | --- |
| Profile | competitive |
| Selection mode | all |
| Competitor policy | configured |
| Corpus | corpus.local-paired.authored.v1 |
| Selected cases | 24 |
| Executed cases | 23 |
| Unsupported cases | 1 |
| Changed paths | 0 |
| Hard gates | PASS |

### Selection

| Group | Count |
| --- | --- |
| Selected | 24 |
| Directly affected | 0 |
| Deterministic neighbors | 0 |
| Excluded | 0 |

<details>
<summary>Selected case IDs</summary>

| Case ID |
| --- |
| case.merge3.json.independent-fields.v1 |
| case.merge3.json.same-owner-conflict.v1 |
| case.merge3.json.malformed-ours.v1 |
| case.merge2.jsonc.current-layout-preservation.v1 |
| case.merge2.yaml.nested-mapping-leaf.v1 |
| case.merge2.ruby.class-method.v1 |
| case.merge2.markdown.heading-sections.v1 |
| case.merge2.rbs.declarations-comments.v1 |
| case.merge2.toml.nested-table-leaf.v1 |
| case.merge3.jsonc.comment-preservation.v1 |
| case.merge3.json5.order-format.v1 |
| case.merge3.ruby.prism-independent-methods.v1 |
| case.merge3.yaml.delete-modify.v1 |
| case.merge3.toml.independent-tables.v1 |
| case.merge3.markdown.independent-headings.v1 |
| case.merge3.html.independent-ids.v1 |
| case.merge3.python.generic-independent-functions.v1 |
| case.merge3.bash.independent-functions.v1 |
| case.merge3.typescript.independent-functions.v1 |
| case.merge3.go.independent-functions.v1 |
| case.merge3.rust.independent-functions.v1 |
| case.merge3.json.duplicate-identity.v1 |
| case.metamorphic.json.reorder-format.v1 |
| case.metamorphic.jsonc.comment-format.v1 |

</details>

### Quality Gates

| Gate | Result | Details |
| --- | --- | --- |
| Safety | PASS | eligible: 23 |
| Preservation | PASS | eligible: 23 |
| Reliability | PASS | errors: 0 |
| Coverage | REVIEW | unsupported: 1 |

### Effectiveness

| Outcome | Count |
| --- | --- |
| correct_clean | 24 |
| error | 0 |
| excluded_ambiguous | 0 |
| false_auto_merge | 6 |
| false_conflict | 11 |
| true_conflict | 6 |
| unsupported | 1 |

### Performance

| Adapter | Samples | Total |
| --- | --- | --- |
| ast-merge-git | 15 | 4.941s |
| ast-merge-provider.diff2 | 2 | 0.708s |
| ast-merge-provider.merge2 | 6 | 1.907s |
| git.diff | 2 | 0.004s |
| git.merge-file | 16 | 0.033s |
| structuredmerge.unsupported | 0 | 0.000s |
| template.overwrite | 6 | 0.000s |
<!-- structuredmerge-benchmark-report:end -->
