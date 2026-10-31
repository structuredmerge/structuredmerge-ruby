# kettle-jem / kettle-rusty parity inventory

Status: initial inventory for phased work in structuredmerge-ruby issues #92 and
#96éÝyø§yÓ#98. This is not a parity claim and is not complete until every public API
and behavior test has a disposition.

## Scope distinction

- `kettle-jem` scaffolds and maintains Ruby gems and monorepos.
- `kettle-rusty` discovers Cargo projects and applies Rust project, packaged
  template, and README style recipes.
- The tools have different ecosystem outputs. Only equivalent planning,
  ownership, rendering, reporting, and convergence semantics are candidates
  for shared fixtures. Ruby gem metadata and Cargo package metadata are
  ecosystem-specific.

## Initial behavior map

| Surface | kettle-jem | kettle-rusty | Current disposition | Evidence / next step |
| --- | --- | --- | --- | --- |
| Project discovery | Ruby gemspec, Gemfile, repository and monorepo facts; optional configuration and environment | Cargo package facts, Cargo dependency facts, GitHub workflow paths; root package or one explicit workspace member | Similar purpose, ecosystem-specific schemas | Ruby `discover_facts` / Rust `discover_facts`; inventory all discovery inputs and failures in #96 |
| Configuration | `.structuredmerge/kettle-jem.yml`, legacy config, locks, workflow/platform controls | `kettle.yml` with template and README settings | Separate schemas; overlapping selection semantics need fixtures | Compare defaults, unknown keys, invalid values, and precedence in #96 |
| Template selection | Packaged template profiles, local roots, filters, include/only patterns, bootstrap | Packaged inventory and configured local entries/profile | Partial overlap | Add common source/target selection fixtures in #98 |
| File ownership | Template destination comparison, managed blocks, lock and checksum skips, per-run decisions | Existing destination preservation, managed README blocks, conflict diagnostics | Candidate for shared ownership fixtures | Compare generated/current/baseline states, conflict reasons, and preserved bytes in #98 |
| Dependency generation | Ruby gemspec, Gemfile, appraisal and dependency-floor templates | Cargo runtime/dev dependencies are discovered; Rust packaging templates are applied | Different output contracts | Keep ecosystem outputs distinct; inventory Ruby-owned generators in #96 |
| Workflow generation | GitHub Actions matrices, platform and version policy, workflow pins | Existing GitHub workflow facts and packaged Rust CI template | Some reporting overlap, different generation policy | Compare path discovery/reporting only; classify Ruby workflow policy as Ruby-only unless a Rust equivalent is identified |
| README generation | Ruby gem README templates and package-directory section sync | Rust README style/profile renderer with preservation, badges, license, and managed blocks | Partial overlap in section preservation and idempotent rendering | Create shared minimal section-preservation fixture in #98 |
| Apply and convergence | Template application, changelog updates, maintenance locks, checksums, selected post-apply tasks | Project/template/README plan and apply; repeated apply can be a no-op | Candidate for shared plan/apply invariants | Compare exact changed paths, bytes, conflicts, and second-run no-op in #98 |
| CLI and reporting | Interactive/noninteractive decisions, many run policies, scoped execution, text/debug/report output | `plan`, `apply`, template and README plan/apply commands with JSON reporting | Different CLI contracts; share failure and report invariants only | Inventory options, stdout/stderr, exit statuses, and JSON in #98 |
| Post-apply integrations | RuboCop, drift checks, changelog, binstubs, Git driver setup, hooks and commits | No equivalent execution pipeline identified | Ruby-only unless a Rust requirement is established | Record each behavior and test as Ruby-only in #96 |

## Current Rust workspace boundary

`kettle-rusty` accepts a root Cargo package or a workspace with exactly one
explicit member. Empty workspaces return a missing-package diagnostic;
multi-package workspaces return an ambiguity diagnostic; traversal and glob
members fail closed. Selecting one member from a multi-package workspace is
not implemented. Issue #97 owns the selection contract and any implementation.

## Evidence already available

- Ruby implementation: `lib/kettle/jem.rb`, `lib/kettle/jem/cli.rb`,
  `lib/kettle/jem/tasks/`, and `spec/`.
- Rust implementation: `rust/crates/kettle-rusty/src/lib.rs`,
  `rust/crates/kettle-rusty/src/bin/kettle-rusty.rs`, and
  `rust/crates/kettle-rusty/tests/thin_slice.rs`.
- Rust focused suite currently passes 4 CLI tests and 16 fixture/integration
  tests. This establishes Rust behavior only; shared Ruby comparisons remain
  a separate gate.
