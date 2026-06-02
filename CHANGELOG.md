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
- `ast-merge` now requires `token-resolver` 2.0.1 or newer.
### Deprecated
### Removed
### Fixed
- Ruby merges now place template-only top-level nodes at their template anchor by
  default instead of appending them to the destination tail.
- Ruby merges now defer template-only top-level groups behind later destination
  matches and skip crossed duplicate require aliases, preventing library
  requires from moving ahead of coverage bootstrap code.
- Shared layout handling now prunes blank-line gaps owned by removed or skipped
  nodes, so semantic Ruby merges do not leave duplicate interstitial blank lines
  after de-duplicating requires.
- `ast-merge` now declares its runtime `token-resolver` dependency explicitly.
### Security

## [7.0.0] - 2026-05-05
- TAG: [v7.0.0][7.0.0t]
### Added
- Released the initial StructuredMerge Ruby gem set at version 7.0.0.
- Published the parser-backed merge gems and kettle-jem templating tool from this monorepo.

[Unreleased]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.0.0...HEAD
[7.0.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/0aae485e7ca20583b73f8c146f467a64e526ca41...v7.0.0
[7.0.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.0.0
