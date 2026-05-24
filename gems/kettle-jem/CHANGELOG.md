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
### Deprecated
### Removed
### Fixed
- Removed stale `continue-on-error` handling from the generated style workflow
  so RuboCop Gradual failures are enforced by default.
- Removed stale `continue-on-error` handling from the generated current workflow.
- Marked generated workflow files as template-owned by default to prevent stale
  YAML keys from surviving future template runs.
- Updated the generated coverage bundle to require `kettle-soup-cover` 1.1.2 or newer.
- Updated the generated documentation bundle to require `yard-fence` 0.9.0 or newer.
### Security

## [7.0.0] - 2026-05-05
- TAG: [v7.0.0][7.0.0t]
### Added
- Released kettle-jem as part of the initial StructuredMerge Ruby 7.0.0 gem set.
- Included packaged templates and parser-backed merge support for Ruby gem templating.

[Unreleased]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.0.0...HEAD
[7.0.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/0aae485e7ca20583b73f8c146f467a64e526ca41...v7.0.0
[7.0.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.0.0
