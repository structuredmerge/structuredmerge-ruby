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

- Refresh the RuboCop Gradual baseline after template-driven source and configuration changes.

- Apply safe RuboCop autocorrections in ast-merge source and specs.

- Exclude source-shaped conformance fixture lines from generic line-length lint while retaining the remaining fixture lint checks.

### Security

## [7.1.0] - 2026-08-07

- TAG: [v7.1.0][7.1.0t]
- COVERAGE: 47.23% -- 1579/3343 lines in 37 files
- BRANCH COVERAGE: 13.61% -- 188/1381 branches in 37 files
- 73.97% documented

### Added

- `ast-crispr` now provides `Ast::Crispr::DeleteBatch` for deleting matches from
  multiple structural selectors through one parsed document context.
- `zip-merge` now registers a Kaitai-backed `TreeHaver.parser_for(:zip)` path
  for ZIP inventory analysis.
- `plain-merge` now registers `TreeHaver.parser_for(:text)` and
  `TreeHaver.parser_for(:plain)` line-backed parser paths for normalized text
  block analysis.
- `dotenv-merge` now registers `TreeHaver.parser_for(:dotenv)` and
  `TreeHaver.parser_for(:env)` line-backed parser paths built on the
  `plain-merge` line substrate.
- `zip-merge` now depends on `binary-merge` for shared Kaitai/binary-family
  report and diagnostic construction.
- Added `html-merge` as a StructuredMerge Ruby family member with TreeHaver
  HTML parsing, feature profile reporting, and an initial ast-crispr-backed HTML
  structural edit adapter.
- TreeHaver RSpec dependency tags now support parser capability checks, and
  `ruby-merge` exposes TSLP Ruby capability tags for import records, top-level
  call records, and namespace-form equivalence.
- `kettle-jem` benchmark results now include README timing breakdowns for both
  the baseline and fastest non-baseline variant.

- json-merge now supports JSON5 parsing and structural merging.

- JSON5 files and fenced code blocks are routed through json-merge.

- kettle-jem recognizes and structurally merges JSON5 template files.

### Changed

- StructuredMerge Ruby gemspec manifests now exclude repository-only files from
  release packages, including local signing certificates, governance documents,
  recursive signatures, and `extra_rdoc_files`.
- `kettle-jem` monorepo subgem package profiles now merge gemspec template
  updates instead of preserving stale generated package manifests.
- Documented the StructuredMerge Ruby merge-gem family model, including
  substrate/provider behavior sharing and the requirement that partial document
  insertion, replacement, and removal flow through `ast-crispr` instead of
  parser-specific object round-trips.
- Clarified that `zip-merge` is a Kaitai-family binary AST integration and
  should not be categorized with byte or line oriented merge gems.
- Clarified that `binary-merge` is the Kaitai/binary-family substrate for
  concrete schema parser gems such as `zip-merge`.
- The `smorg-rb` executable now supports `-v` / `--version` and prints a
  standard startup header on normal runs.
- `kettle-jem` now migrates existing SimpleCov bootstrap files for packaged
  monorepo subgems even when the selected template profile does not otherwise
  manage per-gem harness files.
- `kettle-jem` RuboCop guidance now treats `.rubocop_gradual.lock` as a work
  list rather than a baseline, and documents explicit config and inline
  exceptions for intentional style deviations.
- Current CI now detects changed monorepo gems and runs each changed gem's own
  `kettle-test` suite instead of installing the root aggregate bundle.
- The monorepo root Gemfile now includes the same development tooling stack used
  by templated gem Gemfiles, so aggregate release coverage runs can load and
  collate SimpleCov output.
- The monorepo root spec configuration now excludes member `spec/tmp` fixture
  trees, preventing generated destination project specs from being loaded during
  aggregate release coverage runs.
- `kettle-jem` templating now defaults no-option runs to classified thread
  planning and file work with half of the available CPU cores.
- `kettle-jem` Ractor-backed file work now batches file units by worker count
  instead of spawning one Ractor per file.
- `kettle-jem` README processing now reuses structural owner scans and batches
  several Markdown deletions to reduce repeated parser passes.
- `kettle-jem` main Gemfile templating now removes repeated direct sibling
  execution blocks left behind by older `nomono` bootstrap output while applying
  the simplified `require "nomono/bundler"` loader.
- `html-merge` now follows the shared root changelog used by the other
  monorepo `*-merge` gems instead of carrying a member-local changelog.
- `smorg-rb` diff-driver output now appends a unified review hunk with exact
  removed and added source text after the semantic structured-diff summary.
- Retemplated generated project metadata, support documentation, CI workflows,
  binstubs, and development dependency floors across the StructuredMerge Ruby
  gem family with `kettle-jem` v7.0.0.
- StructuredMerge Ruby now configures `kettle-family` for its root changelog,
  release readiness, release env, and family changelog phase instead of relying
  on bespoke workspace scripts.
- `kettle-jem` gem templates now require `kettle-dev` 2.0.8 or newer.
- `ast-merge` now requires `token-resolver` 2.0.1 or newer.
- `ast-merge` now provides shared comment/layout emission helpers for root
  boundary text, leading segments, retained blank lines, and equivalent-region
  ownership checks, and RBS, Bash, dotenv, and Psych merges now use that common
  path where their semantics are format-neutral. Those helpers reuse shared
  line-range normalization instead of duplicating owner location handling.
- RBS, Bash, and dotenv removal-mode comment promotion now uses the shared
  `ast-merge` removed-owner preservation path for leading segments, trailing
  regions, and fallback layout gaps.
- `ast-merge` now provides shared source-region report helpers for comment-block
  attachment and blank interstitial ownership, and `ruby-merge` uses those
  helpers for its Ruby fixture/report APIs instead of carrying local copies of
  format-neutral ownership mechanics. The shared helpers now also cover
  interstitial region construction, public owner projection, source spans,
  source content slices, and attached leading comment regions.
- `kettle-jem` benchmark runs now support `--only` and
  `KETTLE_JEM_BENCHMARK_ONLY` selectors so combined worker variants can be
  measured without also running planning-only and file-only split variants.
- Root architecture specs now guard merge emission files against new ad hoc
  comment or blank-line ownership scans, keeping the remaining cleanup debt
  explicit while shared ast-merge attachment and layout helpers are adopted.
- Development Gemfiles for gems that use `tree_sitter_language_pack` now default
  to the StructuredMerge fork branch with the Ruby ABI platform-gem fix until
  that fix is released upstream.
- Structured merge gems now fail closed when no registered TreeHaver backend is
  available instead of falling back to direct parser-library paths outside the
  TreeHaver and ast-merge stack.
- `TreeHaver.parser_for` now accepts backend-type and contract constraints so
  substrate gems can request normalized tree-sitter semantics without being
  hijacked by parser-specific provider gems registered for the same language.
- `yaml-merge` now routes merge emission through TreeHaver/TSLP-backed AST
  owners and ast-merge result mechanics instead of canonicalizing merged YAML
  through Ruby object rendering.

- Replace legacy byebug-named Gemfile dependencies with debug during templating.

### Removed

- Removed the bespoke StructuredMerge Ruby family workflow scripts and migrated
  generated family Rake tasks to `kettle-family`.

### Fixed

- `kettle-jem` bootstrap commits now stage with `git add -A -- .` from the
  project root instead of repository-global `git add -A`, preventing monorepo
  member bootstrap commits from sweeping unrelated sibling changes.
- StructuredMerge Ruby's aggregate release test bundle now includes
  `html-merge`, preventing root release checks from failing to load HTML merge
  specs.
- `kettle-jem` gemspec packaging now enumerates package files relative to the
  gemspec directory, so release packaging specs see shipped template assets even
  when the gemspec is loaded from the monorepo root.
- `kettle-jem` no longer packages local gem signing certificates, while
  configured extra package-file globs remain relative to the gemspec directory.
- TOML array-of-table fixture specs now assert that the losing template driver
  description is absent instead of rejecting the retained destination driver
  name they also require.
- `prism-merge` now preserves template-owned trailing comment lines attached to
  matched Ruby statements, including comments adjacent to generated `require`
  calls during template merges.
- `kettle-jem` local Gemfile templating now removes obsolete nomono activation
  ceremony from existing destination files while retaining the simple
  `require "nomono/bundler"` loader.
- `kettle-jem` bootstrap commits can now be serialized by monorepo family
  templating, preventing concurrent member template jobs from racing while
  updating the shared `HEAD`.
- TreeHaver now smoke-tests `tree_sitter_language_pack` parser execution for the
  requested language before registering the TSLP backend, so broken native gem
  artifacts fail closed with a useful reason instead of surfacing parser
  self-conversion `TypeError`s during JSON merges.
- `json-merge` file analysis now registers its TreeHaver JSON backend before
  direct parsing, preventing templating from failing with `No parser registered
  for json` when JSON smart merges instantiate file analysis directly.
- RBS recursive member merges no longer duplicate destination-owned comments
  before matched nested declarations across repeated templating runs.
- RBS merges now preserve retained declaration and nested member blank-line
  gaps, preventing templating from compacting existing `.rbs` whitespace.
- Bash merges now preserve floating first-owner and removed-node comment gaps,
  and avoid duplicating a comment block that was already promoted from a removed
  destination-only node.
- Bash and RBS removal-mode merges no longer duplicate a blank gap when a
  removed destination-only owner preserves the same gap later seen as a retained
  matched owner's leading gap.
- Bash, dotenv, and RBS merges now share a retained blank-gap compliance
  contract and preserve destination-owned blank gaps between retained matched
  owners, including template-preferred matched output.
- RBS recursive member merges now use a shared retained blank-gap contract and
  preserve destination-owned nested member separators when template-preferred
  member bodies are emitted.
- TOML template-preferred merges now preserve destination-owned retained blank
  gaps for matched top-level keys and keys inside matched tables.
- JSON template-preferred merges now preserve destination-owned retained blank
  gaps for matched top-level and nested object pairs.
- Ruby merges now preserve destination-owned retained blank gaps between matched
  top-level declarations when emitting TSLP-backed merge results.
- YAML merges now preserve comments, blank lines, anchors, aliases,
  multi-document separators, and scalar spelling for the shared formatting
  preservation fixture while retaining destination-owned sequence values.
- Markdown backend feature fixtures now account for optional provider backends
  that are only available after their provider gems register concrete TreeHaver
  integrations in the current process.
- Ast-merge changed-gem CI no longer times out or fails when exercising
  isolated fixture integrations that require Prism-backed Ruby merging.
- TreeHaver's Prism parser backend no longer depends on the removed upstream
  `Prism.available?` API, allowing Prism 1.9+ to parse during templating.
- Changed-gem CI suites now pass in isolated gem bundles by loading required
  adapter gems explicitly, avoiding Ruby 4 `Pathname#find` assumptions, and
  keeping Prism merge tests on the local TreeHaver capability registry.
- Ruby merges now fail closed for TSLP-backed namespace-form equivalence gaps
  instead of duplicating alternate namespace declarations, while preserving
  template-only direct methods during scoped intra-owner declaration merges.
- TreeHaver now normalizes nested object fields from tree-sitter-language-pack
  process results, including span objects, before building parser analysis.
- `bash-merge` now routes explicit `parser_path:` overrides through scoped
  TreeHaver language registration instead of passing parser library paths
  directly to parser construction.

- Byte-offset rewrites in `kettle-jem` and `prism-merge` now splice source with
  byte-aware slicing so non-ASCII content before an edited AST node does not
  corrupt Ruby output.
- Current CI now aligns the root Gemfile dependency floors with local path
  gemspec floors and uses an explicit setup-ruby Bundler cache version to avoid
  stale bundle restores after dependency floor changes.
- Root aggregate RSpec runs now load subgem support helpers consistently and
  skip Bash parser-dependent examples when no native TreeHaver Bash parser is
  available.
- Current CI now runs the root aggregate RSpec suite with progress output to
  avoid excessive documentation-format logs.
- Current CI bounds the root aggregate RSpec command so long-running shutdown
  or parser hangs produce actionable failure logs instead of indefinite jobs.
- `kettle-jem` JRuby 9.4 workflow templates now install RubyGems 3.6.9 and
  Bundler 2.6.9 instead of using the default JRuby toolchain.
- Local template stack reinstalls now uninstall the selected StructuredMerge Ruby
  gems before reinstalling them, and no longer install sibling `kettle-dev` or
  `galtzo-floss` gems by default.
- Ruby merges now place template-only top-level nodes at their template anchor by
  default instead of appending them to the destination tail.
- Ruby merges now defer template-only top-level groups behind later destination
  matches and skip crossed duplicate require aliases, preventing library
  requires from moving ahead of coverage bootstrap code.
- Shared layout handling now prunes blank-line gaps owned by removed or skipped
  nodes, so semantic Ruby merges do not leave duplicate interstitial blank lines
  after de-duplicating requires.
- `ast-merge` now declares its runtime `token-resolver` dependency explicitly.
- `tree_haver` now passes string language names to ruby_tree_sitter when loading
  MRI backend grammars, fixing Ruby 4 parser setup for local shared-library
  grammars.
- `json-merge` now accepts devcontainer-style JSONC files with comments and
  trailing commas through its synthetic parser fallback.
- `prism-merge` now treats empty Ruby block bodies as non-mergeable instead of
  raising during recursive merge policy checks.
- `kettle-jem` now normalizes GitHub Actions pins for all existing workflow
  files after templating, including workflows outside the active recipe set.
- `kettle-jem install` now completes raw `bundle gem` skeleton bootstrap by
  generating the modular Gemfiles required by the generated Gemfile before
  running setup, and skips RuboCop Gradual autocorrect when the destination does
  not define that task.

- TreeHaver normalizes JSON5 parser node names for portable JSON dialect consumers.

- json-merge supports JSONC comments and trailing commas while rejecting JSON5-only syntax.

- kettle-jem preserves explicit version_gem template dependencies and avoids introducing missing version requires.

- kettle-jem emits valid whitespace-free empty values for optional configuration tokens.

- kettle-jem loads runtime dependencies before generated version namespaces.

- kettle-jem preserves class-based outer namespaces in generated version files.

- kettle-jem preserves host token placeholders during configuration normalization.

- Prevent Ruby merges from duplicating identical leading comments when template and destination already contain the same comment.

- Version bootstrap repairs remove stale package-name requires when the discovered Ruby entrypoint uses a different require path.

- Restore VERSION loading through the public ast/merge entrypoint.

- Restore version constants through public namespace entrypoints across the merge gems.

- Restore version loading for AST Crispr adapter entrypoints.

- Make the TreeHaver documentation examples pass YARD lint.

- Ensure monorepo subgems receive JSON coverage formatter settings in mise.toml.

- Synchronize the RuboCop Gradual baseline with the parser implementation so releases pass lint validation.

- Updated monorepo CI templating bootstraps to install nomono 1.1.4, matching the generated Gemfile requirement.

- Installed the nomono templating bootstrap inside Bundler's isolated path so CI can load nomono/bundler.

- Use setup-ruby-flash pre-bundle gem support for the monorepo nomono bootstrap instead of pinning a CI install path or version.

- Point setup-ruby-flash at each monorepo gem before installing pre-bundle templating gems.

- Keep setup-ruby-flash preinstalled templating gems visible during monorepo Bundler evaluation.

## [7.0.0] - 2026-05-05

- TAG: [v7.0.0][7.0.0t]

### Added

- Released the initial StructuredMerge Ruby gem set at version 7.0.0.
- Published the parser-backed merge gems and kettle-jem templating tool from this monorepo.

[Unreleased]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.1.0...HEAD
[7.1.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.0.0...v7.1.0
[7.1.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.1.0
[7.0.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/0aae485e7ca20583b73f8c146f467a64e526ca41...v7.0.0
[7.0.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.0.0
