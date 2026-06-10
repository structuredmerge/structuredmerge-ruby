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

- Added the repo-local `bin/kettle-jem-workflow-pins` maintenance script to
  update the GitHub Actions SHA pin index used by generated workflow templates
  via `kettle-gha-sha-pins`.
- `kettle-jem install` now generates a curated `bin/appraisal` binstub for the
  `appraisal2` executable.
- Added a default-off `readme.badges.fossa` template option for managed FOSSA
  README badges.
- Added explicit `ruby.test_minimum` template configuration, defaulting to
  Ruby 2.4, for generated CI workflow and Appraisal floors.
- Added `rake spec:dependency_floors` as a fast validation slice for recurring
  non-StructuredMerge dependency floor bumps.

### Changed

- Gem templates and generated templating Gemfiles now require `kettle-dev` >= 2.2.3.
- The packaged gemspec template now uses the same `kettle-dev` 2.2.3 floor as
  generated Gemfile tooling.
- Gem templates now require `kettle-test` >= 2.0.4.
- Generated coverage Gemfiles now require `kettle-soup-cover` >= 2.0.2.
- Gem templates now require `turbo_tests2` >= 3.1.2 for the default
  `kettle-test` runner dependency.
- Gemfile and gemspec source checks now prefer Prism-backed call records instead
  of regex/string fallback matching for dependency and project-name decisions.
- Appraisals template merging now delegates same-name DSL call reconciliation to
  `Prism::Merge` instead of custom source-line dependency comparison.
- Generated gemspec version-loader fallbacks now use `require_relative` for
  gems whose runtime Ruby floor is 2.2 or newer, reserving `$LOAD_PATH`
  mutation for gems that still target older Rubies.
- Generated gemspec version-loader guards now use `Gem.ruby_version`, avoiding
  RuboCop `Gemspec/RubyVersionGlobalsUsage` violations.
- Generated auto-assign workflows now pin `pozil/auto-assign-issue` to the
  immutable SHA for v4.
- Generated GitHub Actions workflow templates now pin `actions/checkout` to
  the peeled commit SHA for v6.0.3 and `qltysh/qlty-action/coverage` to the
  immutable SHA for v2.2.1.
- Generated GitHub Actions workflow templates now refresh pins for
  `coverallsapp/github-action`, `codecov/codecov-action`, and
  `kettle-rb/ts-grammar-action`.
- Generated workflow templates now pin `coverallsapp/github-action`,
  `codecov/codecov-action`, and `kettle-rb/ts-grammar-action` to resolvable
  release SHAs instead of stripped SemVer strings.
- Generated GitHub Actions workflow templates now refresh `ruby/setup-ruby` to
  the immutable SHA for v1.312.0 and `codecov/codecov-action` to the latest
  v7.0.0 release comment.
- Generated coverage workflows now publish QLTY coverage with GitHub OIDC so
  repositories do not require `QLTY_COVERAGE_TOKEN` to be configured.
- Generated README and FUNDING OpenCollective links now use the configured
  OpenCollective slug instead of assuming it matches the GitHub organization.
- Generated coverage workflow uploads now share the same template token as
  custom workflow injection, avoiding duplicate coverage upload step templates.
- Generated coverage workflows no longer gain an extra blank line after the
  shared coverage upload step token is expanded at end of file.
- Generated Appraisal/RuboCop templates now use Appraisal2 3.1.1's `plugin`
  and `generator_only` DSLs to provide the full style toolchain from modern
  Appraisal root bundles without leaking style dependencies into old-Ruby
  appraisal bundles, while still evaluating the style toolchain for Bundler.
- Generated Appraisals no longer add a separate `cgi >= 0.5` declaration to
  the `head` appraisal because the extracted stdlib gemfiles already provide
  the Ruby-specific `cgi` dependency.
- Generated Appraisal root Gemfiles now load the style toolchain only on Ruby
  3.2+, matching the current RuboCop-LTS dependency floor.
- Generated Open Collective backers workflows now skip the README update step
  when `README_UPDATER_TOKEN` is not configured instead of failing the workflow.
- Generated style toolchains now use `appraisal2-rubocop` 0.2.0 as their floor.
- Generated style toolchains now include `rubocop-minitest` so projects with
  preserved Minitest RuboCop config can run `rubocop_gradual`.
- Template strategy documentation now clarifies that `raw_copy` is a bootstrap
  path that bypasses token resolution and StructuredMerge normalization.
- Generated EOL TruffleRuby 22.3, 23.0, and 23.1 workflows now mark their
  matrix entries experimental so native extension build failures do not fail
  the whole workflow.
- Documented `kettle-jem install` as the canonical full templating entrypoint
  and marked generated `kettle:jem:*` rake tasks as internal orchestration targets.
- Bare `kettle-jem template` now aliases to the full install path; use
  `kettle-jem template --only PATH` or `--include PATH` for scoped file updates.
- `kettle-jem` project fact discovery now uses `Kettle::Jem::GemSpecReader`
  and RubyGems specification objects instead of parsing gemspec source.
- `kettle-jem` namespace discovery now prefers existing source-tree version
  namespaces before stale gemspec metadata so non-standard acronym namespaces
  such as `OAuth2` and `OmniAuth` are preserved.
- README and CONTRIBUTING templates now document the effective
  `ruby.test_minimum` value used when the project was templated.
- README templates now list Ruby 2.3 as supported but untested, matching Ruby
  2.2 and older, instead of rendering a Ruby 2.3 CI workflow badge.
- README templates now include a closing note that identifies kettle-jem and
  StructuredMerge as the templating and merge-contract tooling.
- Generated gemspec summary and description assignments now use package
  metadata tokens instead of emoji-only placeholders.
- README logo templating now splits config-driven `top_logos` from
  `h2_synopsis_logos`, renders logos as aligned HTML images, and normalizes logo
  assets to 128px.
- README logo config now accepts optional per-logo widths with `type|width`
  entries, such as `org|12%` or `ruby|96px`.
- README Ruby language logos now link to Ruby Toolbox.
- Documented `rubygems.min_ruby` in the generated `.kettle-jem.yml` so projects
  can make the published runtime Ruby floor explicit.
- Documentation templates now require `yard-yaml` >= 0.2.0.
- Documentation templates now require `yard-fence` >= 0.9.3.
- Documentation templates now require `yard-timekeeper` >= 0.2.1.
- Gem templates and generated templating Gemfiles now require `kettle-dev` >= 2.1.1.
- Gem templates now require `kettle-test` >= 2.0.3.
- Gem templates now require `appraisal2` >= 3.1.1.
- Gem templates now require `version_gem` >= 1.1.11.
- Generated templating Gemfiles now require `kettle-drift` >= 1.0.1.
- Runtime dependency `token-resolver` now requires the released 2.x line.
- Development lockfile generation now uses Bundler 4.0.12.
- Rake task specs now run from a sandboxed temporary project root.
- Ruby, engine, Bundler, RubyGems, RuboCop, and Rails compatibility choices now
  come from an `RRRRB_MATRIX` source of truth so generated workflows and
  appraisals can select the newest stable compatible toolchain per Ruby.
- Generated JRuby 9.1 and 9.2 workflows now install RubyGems 3.3.27 and
  Bundler 2.3.27 instead of using the default JRuby toolchain versions.
- Generated TruffleRuby 23.1 workflows now bootstrap from the Ruby 3.2
  appraisal Gemfile so Ruby 3.2-specific dependency restrictions apply before
  Bundler cache installation, then run tests directly under that bundle instead
  of regenerating the active appraisal Gemfile.
- Generated Ruby 3.0 and Ruby 3.2 appraisal Gemfiles now include
  TruffleRuby-only `json` modules that pin to the default `json` gem shipped
  with EOL TruffleRuby releases instead of constraining MRI Ruby bundles.
- Generated main Gemfiles now install `nomono` >= 1.0.2 so local workspace
  override Gemfiles can load `nomono/bundler` from the released gem.
- Generated coverage workflows now pass `K_SOUP_COV_MIN_LINE` and
  `K_SOUP_COV_MIN_BRANCH` through to Code Coverage Summary thresholds instead
  of hardcoding `100 100`.
- Default semantic Git driver setup now writes repo-local `diff.smorg-*`
  command config as well as managed `.gitattributes`, so local `git diff`
  can actually invoke StructuredMerge drivers after templating.
- Runtime dependency `token-resolver` now requires 2.0.1 or newer.
- Generated gemspecs now require `version_gem` >= 1.1.11 while allowing the
  released 1.1 line.
- Gem templates now require `gitmoji-regex` >= 2.0.1.
- Gem templates now require `turbo_tests2` >= 3.1.1 for the default
  `kettle-test` runner.
- Generated style Gemfiles now use the latest released `rubocop-ruby*`
  wrapper patch constraints for the RuboCop-LTS family.
- Generated style Gemfiles now use the latest released `rubocop-lts` track
  constraints for every supported Ruby floor.
- Generated style Gemfiles now treat style dependency floors as latest-Ruby
  task dependencies, independent from the gemspec runtime Ruby floor.
- Generated coverage Gemfiles now require `kettle-soup-cover` >= 2.0.1.

### Deprecated

### Removed

### Fixed

- Explicit `rubygems.min_ruby: "0"` template configuration now renders the
  zero runtime floor consistently while omitting `required_ruby_version` and
  runtime dependencies that cannot support Ruby 1.x.
- Generated Ruby 4/head extracted-stdlib Gemfiles now include `cgi` and
  `webrick` so legacy suites that require extracted standard libraries can run
  on modern Rubies.
- `kettle-jem install` now ensures curated Bundler binstubs are executable,
  including legacy `bin/rake` and rewritten `bin/yard` binstubs used by
  `kettle-changelog`.
- Generated `LICENSE.md` copyright notice lines now render as a Markdown list.
- Appraisals templating now treats `eval_gemfile "path"` and
  `eval_gemfile("path")` as the same dependency when merging same-named
  appraisal blocks.
- Generated freeze-marker guidance now consistently names `kettle-jem` as the
  templating tool instead of substituting the destination gem name.
- Templating now prunes legacy dashed Ruby workflow filenames such as
  `ruby-2-4.yml` when replacing them with dotted packaged workflow filenames.
- Gemspec freeze-block preservation now honors configured custom
  `defaults.freeze_token` values.
- RuboCop config templating now removes destination `AllCops.TargetRubyVersion`
  settings so Ruby target selection remains owned by the `rubocop-lts` family.
- Coverage workflow templating now preserves `K_SOUP_COV_MIN_LINE` and
  `K_SOUP_COV_MIN_BRANCH` from `mise.toml`, keeping the generated SimpleCov
  hard gate aligned with the project's configured thresholds.
- Framework CI workflow templating no longer emits duplicate matrix environment
  keys when generated matrix entries are visited through overlapping YAML nodes.
- Gemspec templating no longer preserves stale `kettle-soup-cover` development
  dependencies now that coverage dependencies are owned by the modular coverage
  Gemfile.
- Workflow action pin normalization now keeps `pozil/auto-assign-issue` on the
  pinned v4 ref.
- Workflow templating no longer rewrites coverage summary thresholds back to
  literal numbers after applying destination-specific coverage env values.
- Generated coverage workflows now keep Codecov upload failures non-gating, so
  generated coverage reports remain the authoritative CI gate.
- Generated style workflows now run `rbs validate` through the appraisal bundle
  instead of the project `bin/rbs` wrapper.
- Workflow templating now normalizes obsolete Appraisal-relative `kettle-test`
  commands to the canonical project-root `kettle-test` command.
- Local override Gemfile and gemspec templates no longer emit RuboCop-Gradual
  regressions from trailing commas or unnecessary encoding comments.
- README logo templating now preserves generated Synopsis H2 logo HTML during
  README heading normalization, migrates legacy combined `top_logos` config into
  `top_logos` plus `h2_synopsis_logos`, and removes unused old logo link
  definitions.
- Ruby template merges now preserve template-only require/bootstrap nodes and
  place them at their template anchor instead of deleting them after merge.
- Ruby template merges now preserve coverage bootstrap ordering when the
  package name and entrypoint require path differ, avoiding duplicate or
  pre-coverage library requires in generated spec helpers.
- Generated style Gemfiles now include released `rubocop-lts-rspec` in the
  non-local RuboCop-LTS bundle instead of requiring `rubocop-rspec` directly.
- Fixed generated documentation URLs for standalone gems so template-owned
  citation and documentation links do not retain monorepo `gems/` paths.
- Monorepo-root templating now applies without a root gemspec, detects root
  license files ahead of stale config values, installs the generated Rakefile
  task plumbing, and syncs root Gemfile tooling dependencies without duplicating
  local nomono declarations.
- Generated `gemfiles/modular/x_std_libs.gemfile` now selects the extracted
  stdlib dependency set from the active Ruby version, so dependency solvers
  running on Ruby 3.1 do not receive Ruby 4-only stdlib requirements.
- README merging now preserves a destination front `## Important`/warning
  section before Synopsis when that section encloses the badge cloud.
- Same-named destination gemspecs loaded from different project directories no
  longer bleed metadata into one another during templating.
- `kettle-jem install` now strips inherited Bundler activation variables before
  running destination setup commands, so generated `bin/setup` can run
  `bundle install` even when the destination lockfile references gems that are
  not installed yet.
- Generated `bin/yard` now routes through `bin/rake yard` so documentation
  plugins installed by the templated rake task, such as yard-timekeeper, run
  consistently.
- GemSpec template merging now keeps the greater version requirement between
  template-managed dependencies and destination dependencies, allowing newer
  destination constraints to remain while still upgrading stale template-owned
  floors.
- Generated evergreen JRuby workflows now mark the current JRuby and
  `dep-heads` JRuby jobs experimental, so JRuby 10/arjdbc incompatibilities
  remain visible without blocking release CI.
- Same-named Appraisal blocks now merge destination-only `gem` and
  `eval_gemfile` entries into the templated block, so framework/appraisal tools
  can enrich standard `ruby-X-Y` appraisals without losing template updates.
- Standard test Appraisal blocks now include configured
  `appraisal_matrix.appraisal_gemfiles`, allowing kettle-jem-appraisals to
  model required framework dependencies without duplicating the simple
  framework matrix.
- Standard Appraisal gemfile injection now skips blocks already enriched by a
  collapsed framework/appraisal matrix dependency gemfile, avoiding duplicate
  broad and version-pinned framework dependency declarations.
- Standard Appraisal gemfile injection now distinguishes ordinary modular
  support gemfiles from framework matrix fragments, so coverage and dependency
  test appraisals still receive required framework dependencies.
- TOML recipe merging now loads the concrete TOML backend provider with
  kettle-jem, so `.toml` template merges have a registered parser in ordinary
  bundle contexts.
- The generated `.kettle-jem.yml` keeps `Appraisal.root.gemfile`
  template-owned so stale root-appraisal content is replaced cleanly.
- Simple `workflows.framework_matrix` version entries can now target an
  existing appraisal with `appraisal`, `appraisal_name`, or
  `standard_appraisal`, allowing explicit collapse onto standard appraisals.
- Collapsed `workflows.framework_matrix` appraisals now preserve configured
  per-version environment variables, can skip framework workflow generation,
  respect `keep_destination` framework gemfiles, and remove replaced standalone
  framework appraisal blocks.
- Collapsed framework matrix environment variables now render into generated
  GitHub workflow matrices instead of mutating `ENV` from `Appraisals`, so each
  appraisal run receives its own framework version without definition-order
  leakage.
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
- Fixed generated version-gem Ruby and RBS files so whole-file template tokens
  do not add an extra blank line at EOF.
- Generated Rakefiles now install a `kettle:jem:selftest` fallback when the
  installed `kettle-jem` package lacks rake task support.
- Generated Rakefile merging now normalizes section spacing so template-added
  task blocks do not introduce RuboCop `Layout/EmptyLines` offenses.
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
- `kettle-jem install --accept-config` now immediately applies the newly
  bootstrapped canonical config before running bundle setup and bundled handoff,
  so first-time templating installs generate the Gemfile templating wiring that
  makes `bundle exec kettle-jem` available.
- First-time config bootstrap now seeds `project_emoji` from the destination
  gemspec summary or description when the README does not expose a leading H1
  emoji.
- Generated `mise.toml` files now preserve existing coverage thresholds from
  the destination `mise.toml` or legacy coverage workflow, so local
  `kettle-test` runs keep the project's established coverage floor.
- Added curated `rbs` and `rspec-core` binstubs because generated CI templates
  call `bin/rbs` and `bin/rspec` directly through appraisals.
- Generated optional Gemfiles now include `rbs` and `stone_checksums`,
  matching the curated binstubs generated during `kettle-jem install`.
- Updated the generated coverage bundle to require `kettle-soup-cover` 2.0.0 or newer.
- Removed the generated CodeQL workflow so templated repositories can rely on
  GitHub CodeQL default setup instead of failing from duplicate advanced setup.
- Generated workflow pruning now treats TruffleRuby 23.1 as Ruby 3.1
  compatible, matching README compatibility pruning and removing that stale
  workflow from Ruby 3.2+ projects.
- Generated JRuby 9.3 workflows now use RubyGems 3.4.22 and Bundler 2.4.22,
  matching Ruby 2.6 compatibility workflows and avoiding default-gem activation
  conflicts during Appraisal setup.
- Monorepo-root template bootstrap now falls back to package-derived namespace
  and entrypoint tokens when no gemspec-backed RubyGems config is present.
- Updated the generated documentation bundle to require `yard-fence` 0.9.1 or newer.
- Removed `--plugin timekeeper` from generated `.yardopts` because
  yard-timekeeper is installed through the rake `yard` task hook.
- Escaped generated README metadata table cells so multiline gemspec
  descriptions render with `<br>` instead of breaking table rows.
- Fixed gemspec emoji normalization so multiline quoted summaries and
  descriptions remain valid Ruby after templating.
- Fixed version-gem bootstrap so an explicit `rubygems.namespace` in
  `.kettle-jem.yml` wins over stale inferred entrypoint namespaces.
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
  2.0.5 or newer.
- Monorepo-root bootstrap now keeps existing changelogs instead of replacing
  release history with a blank generated template.
- Monorepo-root Rakefiles no longer lose existing RSpec/default tasks during
  scaffold cleanup before plugin task injection runs.
- StructuredMerge family templating now runs child gem updates under the
  kettle-jem bundle so child directories without a Gemfile do not inherit the
  workspace root bundle.
- StructuredMerge family templating now uses a gitmoji-prefixed default commit
  message so scripted commits satisfy the local commit hook.
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
- Applied configured `rubygems.min_ruby` to generated gemspec
  `required_ruby_version` instead of preserving a stale destination value.
- Preserved heredoc gemspec descriptions when applying project emoji
  normalization so templating does not corrupt valid `<<~` assignments.
- Generated local templating Gemfiles now wire `tree_sitter_language_pack` from
  the sibling StructuredMerge checkout when iterating on unreleased
  `kettle-jem`, avoiding broken released native gem materialization.
- Generated `spec/spec_helper.rb` now starts `kettle-soup-cover`/SimpleCov
  before loading the library so `kettle-test` produces the canonical
  `coverage/coverage.json` consumed by `kettle-changelog`.
- VersionGem-managed `version.rb` and `version.rbs` packaged template targets
  now default to whole-file replacement, preventing legacy version constants
  from being merged into the generated shape.

### Security

## [7.0.0] - 2026-05-05

- TAG: [v7.0.0][7.0.0t]

### Added

- Released kettle-jem as part of the initial StructuredMerge Ruby 7.0.0 gem set.
- Included packaged templates and parser-backed merge support for Ruby gem templating.

[Unreleased]: https://github.com/structuredmerge/structuredmerge-ruby/compare/v7.0.0...HEAD
[7.0.0]: https://github.com/structuredmerge/structuredmerge-ruby/compare/0aae485e7ca20583b73f8c146f467a64e526ca41...v7.0.0
[7.0.0t]: https://github.com/structuredmerge/structuredmerge-ruby/releases/tag/v7.0.0
