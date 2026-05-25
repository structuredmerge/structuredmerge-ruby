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
### Changed
- Documented `kettle-jem template` as the canonical templating entrypoint and
  marked generated `kettle:jem:*` rake tasks as internal orchestration targets.
- `kettle-jem` project fact discovery now uses `Kettle::Dev::GemSpecReader`
  and RubyGems specification objects instead of parsing gemspec source.
### Deprecated
### Removed
### Fixed
- `kettle-jem template --hook-templates l` now activates the generated
  project-local `.git-hooks` by setting `core.hooksPath` to `.git-hooks` and
  ensuring the generated hook scripts are executable.
- Removed stale `continue-on-error` handling from the generated style workflow
  so RuboCop Gradual failures are enforced by default.
- Removed stale `continue-on-error` handling from the generated current workflow.
- Marked generated workflow files as template-owned by default to prevent stale
  YAML keys from surviving future template runs.
- Updated the generated coverage bundle to require `kettle-soup-cover` 1.1.2 or newer.
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
- Added `kettle-test` and `kettle-drift` to the curated generated binstub set,
  and added `kettle-drift` to generated gemspec development dependencies so the
  documented drift plugin executable is available.
### Security

## [7.0.0] - 2026-05-05
- TAG: [v7.0.0][7.0.0t]
### Added
- Released kettle-jem as part of the initial StructuredMerge Ruby 7.0.0 gem set.
- Included packaged templates and parser-backed merge support for Ruby gem templating.

[Unreleased]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.0.0...HEAD
[7.0.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/0aae485e7ca20583b73f8c146f467a64e526ca41...v7.0.0
[7.0.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.0.0
