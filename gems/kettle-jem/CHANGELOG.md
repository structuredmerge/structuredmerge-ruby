# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- Added a default-off `readme.badges.fossa` template option for managed FOSSA
  README badges.
- Added explicit `ruby.test_minimum` template configuration, defaulting to
  Ruby 2.4, for generated CI workflow and Appraisal floors.

### Changed

- Documented `kettle-jem install` as the canonical full templating entrypoint
  and marked generated `kettle:jem:*` rake tasks as internal orchestration targets.
- Bare `kettle-jem template` now aliases to the full install path; use
  `kettle-jem template --only PATH` or `--include PATH` for scoped file updates.
- `kettle-jem` project fact discovery now uses `Kettle::Jem::GemSpecReader`
  and RubyGems specification objects instead of parsing gemspec source.
- README and CONTRIBUTING templates now document the effective
  `ruby.test_minimum` value used when the project was templated.

### Deprecated

### Removed

### Fixed

- Same-named Appraisal blocks now merge destination-only `gem` and
  `eval_gemfile` entries into the templated block, so framework/appraisal tools
  can enrich standard `ruby-X-Y` appraisals without losing template updates.
- Simple `workflows.framework_matrix` version entries can now target an
  existing appraisal with `appraisal`, `appraisal_name`, or
  `standard_appraisal`, allowing explicit collapse onto standard appraisals.
- README merge preservation now keeps configured destination-only sections
  instead of dropping them when the packaged README template has no matching
  heading.
- Added `KETTLE_JEM_SKIP_LOCK_NORMALIZATION` for self-templating unreleased
  gems whose dependencies cannot yet resolve from remote sources.
- Added a native `Kettle::Jem::GemSpecReader` for gemspec metadata so tooling
  built on `kettle-jem` no longer needs to call into `kettle-dev` for project
  Ruby floors and gemspec facts.
- Kept malformed destination gemspecs from leaving template tokens unresolved
  by falling back to filename-derived gem identity inside `GemSpecReader`.
- Fixed generated appraisal `eval_gemfile` paths so Appraisal2 resolves
  modular gemfiles relative to `gemfiles/` instead of `gemfiles/gemfiles/`.
- Fixed generated Appraisals content so it does not end with an extra blank line.
- Fixed generated framework workflow YAML indentation so `framework:` remains
  under `strategy.matrix`.
- Removed duplicate generated `spec.homepage` assignments when destination
  gemspecs already carry the configured homepage.
- `kettle-jem install --hook-templates l` now activates the generated
  project-local `.git-hooks` by setting `core.hooksPath` to `.git-hooks` and
  ensuring the generated hook scripts are executable.
- Removed stale `continue-on-error` handling from the generated style workflow
  so RuboCop Gradual failures are enforced by default.
- Removed stale `continue-on-error` handling from the generated current workflow.
- Marked generated workflow files as template-owned by default to prevent stale
  YAML keys from surviving future template runs.
- Replaced generated Appraisal workflow matrix Gemfile indirection with a
  fixed `Appraisal.root.gemfile` job environment so Appraisal never falls back
  to the root development `Gemfile`.
- Changed packaged GitHub workflow templates to whole-file replacement so stale
  job steps from older matrix formats cannot accumulate beside new steps.
- Preserved destination coverage thresholds when replacing generated coverage
  workflows.
- Preserved the current gem in local modular gemfile workspace arrays when the
  generated local dependency wiring needs to include it.
- Excluded the current gem from generated `eval_nomono_gems` calls so local
  workspace lists do not conflict with the root `gemspec` dependency.
- Excluded already-declared gemspec dependencies from generated local
  `eval_nomono_gems` calls so local modular gemfiles do not conflict with
  development dependencies declared by the project gemspec.
- Changed post-template lockfile normalization to run `bundle update` with
  templating and local sibling overrides disabled, so dependency template
  updates are fully re-resolved against released gems.
- Added curated `rbs` and `rspec-core` binstubs because generated CI templates
  call `bin/rbs` and `bin/rspec` directly through appraisals.
- Updated the generated coverage bundle to require `kettle-soup-cover` 1.1.3 or newer.
- Updated the generated documentation bundle to require `yard-fence` 0.9.1 or newer.
- Removed `--plugin timekeeper` from generated `.yardopts` because
  yard-timekeeper is installed through the rake `yard` task hook.
- Escaped generated README metadata table cells so multiline gemspec
  descriptions render with `<br>` instead of breaking table rows.
- Updated the generated contributing guide to refresh the `REEK` backlog with
  `bin/rake reek:update` instead of redirecting the raw `reek` executable.
- Replaced `bundle binstubs --all` during template install with curated
  binstubs for documented project entrypoints, and prune stale Bundler-generated
  development-tool binstubs such as `bin/reek`.
- Added `kettle-test` to the curated generated binstub set, and preserve
  `kettle-drift` binstubs when they already exist from local/plugin installs
  without requiring unreleased `kettle-drift` in every generated gemspec.
- Added `kettle-drift` to generated templating Gemfiles, resolved remotely in
  templating mode and via `KETTLE_RB_DEV` locally, separate from the
  `SMORG_RB_DEV` StructuredMerge local gem set.
- Refreshed generated README metadata blocks after template README merging so
  version-derived gemspec metadata such as `source_code_uri` does not stay stale.
- Added `yard-yaml` to generated local documentation Gemfiles so local
  `GALTZO_FLOSS_DEV` runs match the released documentation plugin set.
- Updated the generated development dependency on `kettle-test` to require
  2.0.1 or newer.
- Updated the generated development dependency on `kettle-dev` to require
  2.0.1 or newer.
- Generated framework CI now uses an explicit framework matrix axis instead
  of GitHub Actions `include` expansion.
- Scrubbed parent Bundler activation variables before the post-template
  lockfile normalization command runs in the destination project.
- Preserved multiline heredoc gemspec assignments as whole fields during
  gemspec template merging.
- Generated two-segment framework requirements as patch-bounded pessimistic
  constraints, e.g. `~> 7.0.0`, so framework appraisals do not drift to
  later minor versions.
- Removed generated gemspec development dependencies when the destination
  already declares the same gem as a runtime dependency.
- Preserved zero-byte generated template outputs such as `REEK` instead of
  normalizing them to a single blank line.
- Added `workflows.recording` to `.kettle-jem.yml` so generated Appraisals only
  include VCR/WebMock recording gemfiles for projects that opt in.

### Security

## [7.0.0] - 2026-05-05
- TAG: [v7.0.0][7.0.0t]
### Added
- Released kettle-jem as part of the initial StructuredMerge Ruby 7.0.0 gem set.
- Included packaged templates and parser-backed merge support for Ruby gem templating.

[Unreleased]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.0.0...HEAD
[7.0.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/0aae485e7ca20583b73f8c146f467a64e526ca41...v7.0.0
[7.0.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.0.0
