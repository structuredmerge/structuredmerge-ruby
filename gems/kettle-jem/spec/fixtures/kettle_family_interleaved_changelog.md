# Changelog

[![SemVer 2.0.0][semver-img]][semver] [![Keep-A-Changelog 1.0.0][keep-changelog-img]][keep-changelog]

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

### Changed

- The `kettle-family` executable startup header is now shown only when
  `--verbose` is passed; `-v` and `--version` still print just the executable
  version and exit.

### Deprecated

### Removed

### Fixed

### Security

## [1.1.9] - 2026-07-25

- TAG: [v1.1.9][1.1.9t]
- COVERAGE: 95.23% -- 3197/3357 lines in 25 files
- BRANCH COVERAGE: 77.20% -- 1192/1544 branches in 25 files
- 28.16% documented

### Added

- `kettle-family state` now marks mismatched GitHub release tags and reports
  kettle-jem transfer changelog replay lag in a `T📰` column.

### Changed

- Bare `kettle-family bump` now defaults to `--only bump`, and bare
  `kettle-family release` now defaults to `--only pending`.

- kettle-jem-template-20260725-002 - Generated gemspec templates now include
  `anonymous_loader` as a development dependency, and version specs use it to
  execute generated `version.rb` files for coverage without redefining package
  constants. Managed version specs are removed when `version_gem` is disabled
  or incompatible with the project's runtime Ruby floor.

### Fixed

- Monorepo templating now passes a shared Git operation lock to `kettle-jem`,
  allowing template workers to serialize repo-wide Git config/index mutations
  instead of only bootstrap commits.

## [1.1.6] - 2026-07-25

- TAG: [v1.1.6][1.1.6t]
- COVERAGE: 95.19% -- 3084/3240 lines in 25 files
- BRANCH COVERAGE: 76.80% -- 1132/1474 branches in 25 files
- 28.68% documented

### Fixed

- Release summaries now count only members that reached a release terminal
  phase as succeeded, so dependency-floor side effects do not appear as
  published gems after an earlier failure.

### Changed

- kettle-jem-template-20260725-001 - Generated JRuby and TruffleRuby workflow
  files now run when pull request head branches start with `feature/release`,
  so release CI monitoring does not report intentionally skipped engine
  workflows as failures.

## [1.1.5] - 2026-07-25

- TAG: [v1.1.5][1.1.5t]
- COVERAGE: 94.64% -- 3021/3192 lines in 25 files
- BRANCH COVERAGE: 76.45% -- 1110/1452 branches in 25 files
- 28.68% documented

### Added

- Release orchestration now passes `--events` through to `kettle-release` and
  maps release NDJSON events into the family progress display.

### Changed

- kettle-jem-template-initial - Initial templating by kettle-jem.

### Fixed

- Failed release command reports now summarize release NDJSON diagnostics and
  final status instead of dumping the raw event stream into the human report.

## [1.0.2] - 2026-07-21

- TAG: [v1.0.2][1.0.2t]
- COVERAGE: 95.51% -- 2637/2761 lines in 23 files
- BRANCH COVERAGE: 77.98% -- 928/1190 branches in 23 files
- 28.63% documented

### Added

- `kettle-family template` now passes family-level `readme.corporate_sponsors`
  config into member `kettle-jem` runs for template-managed README sponsor logos.
- `kettle-family state` is now an alias for `kettle-family release-state`.

### Changed

- `kettle-family release-state` now reports the checked-out branch and displays
  release distance as local/remote ahead and behind counts.
- kettle-jem-template-20260720-001 - Generated READMEs can now render
  template-managed corporate sponsor logos from project or family config.
- kettle-jem-template-20260720-002 - Generated development Gemfiles now use the
  released `tree_sitter_language_pack` gem 1.13.3 or newer by default.
- kettle-jem-template-20260720-003 - Generated StructuredMerge Git diff driver
  config now uses the installed `smorg-rb` Ruby driver name.
- kettle-jem-template-20260720-004 - Generated multi-engine workflow files now
  omit JRuby and TruffleRuby jobs when project config declares MRI-only engines.
- kettle-jem-template-20260720-005 - Generated README Support & Community rows
  now include a RubyForum help badge.

### Fixed

- Default member discovery now excludes benchmark fixture gemspecs so benchmark
  projects are not treated as install/template/release family members.
- Generated HEAD and runtime dependency HEAD CI workflows no longer include
  JRuby or TruffleRuby jobs for this MRI-only gem.

## [1.0.0] - 2026-07-17

- TAG: [v1.0.0][1.0.0t]
- COVERAGE: 95.22% -- 2370/2489 lines in 23 files
- BRANCH COVERAGE: 76.87% -- 801/1042 branches in 23 files
- 29.29% documented

### Added

- `kettle-family release` now accepts `--ci-workflows` and forwards the
  comma-separated workflow subset to member `kettle-release` runs.

### Changed

- Promoted the gems that provide built-in `kettle-family` workflow commands to
  runtime dependencies: `kettle-dev` for release/changelog/SHA-pin/version
  tooling and `kettle-test` for test runs.

- kettle-jem-template-20260716-001 - Shim gemspec manifests now include
  `LICENSE.md` instead of nonexistent `LICENSE.txt`.
- kettle-jem-template-20260716-002 - Generated gemspec manifests now ship fewer
  repository-only files by default to reduce downstream distro packaging churn.

### Fixed

- Root-mode family changelog release commands now pass the configured family
  name to `kettle-changelog`, allowing shared root changelogs to run from
  repositories that do not have a root gemspec.

[semver]: https://semver.org/spec/v2.0.0.html
[semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat
