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

- JRuby 9.2 workflow templates now use the legacy-engine bundle install path
  instead of `ruby/setup-ruby` bundler caching so old Bundler does not fail
  setup against gem servers without the full legacy index.
- Gemspec templating now structurally merges destination `spec.files`
  collection entries with template package entries so project-specific
  packaged files are not lost when the template rewrites the generated gemspec
  structure.
- Gemspec templating now restores additional legacy Prism policy behavior for
  destination-only metadata fields, Bundler `git ls-files` package declarations,
  and empty development-dependency section cleanup after runtime dependency
  promotion.
- Added the repo-local `bin/kettle-jem-workflow-pins` maintenance script to
  update the GitHub Actions SHA pin index used by generated workflow templates
  via `kettle-gha-sha-pins`.
- `kettle-jem install` now generates a curated `bin/appraisal` binstub for the
  `appraisal2` executable.
- Added a default-off `readme.badges.fossa` template option for managed FOSSA
  README badges.
- Added explicit `ruby.test_minimum` template configuration, defaulting to
  Ruby 2.4, for generated CI workflow and Appraisal floors.
- Added top-level `integrations` configuration for disabling coverage
  integrations (`codecov`, `coveralls`, `qlty`) and the SkyWalking Eyes license
  check integration across README badges, upload/check workflow steps, packaged
  config/workflow templates, and cleanup of existing config files or workflows.
- Added `rake spec:dependency_floors` as a fast validation slice for recurring
  non-StructuredMerge dependency floor bumps.
- The fast dependency floor slice now covers `appraisal2`.
- kettle-jem's own `mise` environment now enables templating dependencies so
  templating-only floors are validated in the normal gem bundle.
- Restored `kettle-jem prepare` as a pre-flight dependency bootstrap mode for
  applying the minimal templating Gemfile payload before full templating.
- Gem templates and generated root Gemfiles now require `kettle-dev` >= 2.2.24.
- Version-gem bootstrapping now removes stale top-level RBS `VERSION`
  declarations and generated style workflows load the RBS environment so
  duplicate declarations fail in CI.
- Version-gem bootstrapping now removes literal `bundle gem` scaffold RBS
  `VERSION` declarations before writing the managed `version.rbs` signature.
- Added a destructive `shim` template profile for compatibility wrapper gems.
  Shim templating accepts the replacement gem via `--shimmed-gem` or
  `KETTLE_JEM_SHIMMED_GEM`, generates only the shim runtime/docs/specs/CI, and
  deletes obsolete implementation code, behavior specs, workflows, and gemfiles.

### Changed

- Generated pull request engine workflows now keep JRuby and TruffleRuby
  coverage available via branch opt-in prefixes: `jruby/*` runs JRuby
  workflows, `truffleruby/*` runs TruffleRuby workflows, and `engines/*` runs
  all engine workflows. Other pull request branches continue to run MRI checks
  without the alternate engine jobs.
- Generated workflow templates now evaluate skip-CI commit messages only for
  push events, and mixed head/dependency-head templates gate JRuby and
  TruffleRuby jobs before runner provisioning on pull requests.
- Template apply now restores executable bits on generated Git hook scripts.
- `require "kettle/jem"` now defers parser-backed template runtime dependencies
  until template execution so Rake task installation does not load
  `tree_sitter_language_pack` before RuboCop loads `parser`.
- `require "kettle/jem"` no longer directly loads `version_gem` by default;
  require `kettle/jem/version_gem` for the optional `VersionGem::Basic`
  extension.
- Ruby, engine, Rails, RuboCop, and RuboCop LTS compatibility choices now come
  from `Kettle::Rb::CompatMatrix` in `kettle-rb`.
- Generated `mise.toml` files no longer export `RUBOCOP_LTS_LOCAL=false`;
  local RuboCop-LTS mode is now controlled by setting the variable only when a
  local checkout should be used.
- Generated style Gemfiles now require `rubocop-lts-rspec` >= 1.0.4.
- kettle-jem now declares and loads the direct `rbs` runtime dependency used
  by its RBS signature cleanup logic.
- Version-gem bootstrapping now preserves projects that load `version_gem`
  through a dedicated `lib/<entrypoint>/version_gem.rb` file instead of forcing
  it back into the default entrypoint.
- Version-gem bootstrapping now updates existing generated version specs to
  require a dedicated `lib/<entrypoint>/version_gem.rb` entrypoint when present.
- Gem templates and generated root Gemfiles now require `kettle-dev` >= 2.3.5.
- Gem templates and generated root Gemfiles now require `kettle-test` >= 2.0.11.
- Gem templates and generated root Gemfiles now require `turbo_tests2` >= 3.1.14.
- Generated gemspecs and optional Gemfiles now require `stone_checksums` >= 1.0.6.
- Shim gemspec templates now include `LICENSE.md`, matching the generated
  license template filename, instead of the nonexistent `LICENSE.txt`.
- Monorepo subgem package templating now includes the main `Gemfile` so existing
  generated gems receive the `nomono` bootstrap required by local modular
  Gemfiles during templating-mode CI.
- Templating now applies transferable kettle-jem changelog entries to destination
  `CHANGELOG.md` files using stable `kettle-jem-template-YYYYMMDD-NNN` IDs.
- Generated gemspecs now support explicit extra package-file globs via
  `gemspec.package_files.include` in `.structuredmerge/kettle-jem.yml`.
- Version-gem templates now generate one package-level RBS file at
  `sig/<entrypoint>.rbs` and migrate legacy nested
  `sig/<entrypoint>/version.rbs` files into it.
- Generated gemspec package manifests now omit repository-only governance docs,
  signing certs, recursive signature directories, split license files, and
  `spec.extra_rdoc_files` by default.
- Generated templates now require the released floors for `kettle-dev` 2.3.0,
  `kettle-drift` 1.0.5, `kettle-test` 2.0.9, `nomono` 1.0.8, and
  `token-resolver` 2.0.4.
- Generated gemspecs now require `appraisal2` >= 3.1.4.
- Generated style Gemfiles now require `appraisal2-rubocop` >= 0.2.3.

- Generated optional Gemfiles no longer duplicate the gemspec's direct
  `stone_checksums` development dependency.

- Quiet templating orchestration now passes quiet flags and debug-suppressing
  environment to Bundler commands.
- Generated Appraisal guidance now defaults to `bin/rake appraisal:generate`,
  reserving `appraisal:update` for intentional lock refreshes.
- Gemspec templating now raises preserved `rspec-stubbed_env` dependencies to
  `>= 1.0.6`.
- Generated documentation Gemfiles now require `yard-fence` >= 0.9.6,
  `yard-timekeeper` >= 0.2.3, and `yard-yaml` >= 0.2.3.
- kettle-jem now requires `kettle-rb` >= 0.1.2.

- kettle-jem-template-20260716-001 - Shim gemspec manifests now include
  `LICENSE.md` instead of nonexistent `LICENSE.txt`.
- kettle-jem-template-20260716-002 - Generated gemspec manifests now ship fewer
  repository-only files by default to reduce downstream distro packaging churn.

### Deprecated

### Removed

### Fixed

- kettle-jem's own gemspec now includes public signing certs in packaged files.
- Generated CI workflow synchronization now emits valid YAML for matrix and
  setup-ruby sections instead of misindenting multi-line template fragments.
- Open Collective badge/funding detection now respects disabled funding policy
  without falling back to the default organization.
- Version-gem RBS consolidation now migrates all legacy nested
  `sig/<entrypoint>/**/*.rbs` content into the package-level signature and
  removes the nested files, including when the package-level signature is
  managed by a template entry.
- Generated dep-heads workflows now run current TruffleRuby directly from the
  generated `gemfiles/dep_heads.gemfile`, avoiding `Appraisal.root.gemfile`
  bootstrap failures with TruffleRuby's bundled RubyGems/Bundler and gem.coop.
- Packaged Rakefile templating now merges destination Rakefiles by default
  instead of replacing them wholesale, preserving project-specific rake tasks
  such as release or adapter test helpers.
- Version-gem namespace discovery no longer treats nested implementation
  namespaces in the public entrypoint, such as `Kettle::Dev::Tasks`, as the gem
  namespace when the existing version namespace is more specific.
- Gemfile and gemspec templating byte-offset rewrites now splice source with
  byte-aware slicing so non-ASCII content before an edited AST node does not
  corrupt generated Ruby.
- Generated legacy-engine CI workflows now install Bundler gems under
  `${RUNNER_TEMP}/bundle` instead of `vendor/bundle`, preventing Appraisal
  installs from creating nested `gemfiles/vendor` bundles.
- Generated RuboCop configs now exclude `**/vendor/**/*` so nested vendored
  dependency trees are not linted.

- Fixed `bin/kettle-jem-workflow-pins` so its default project root resolves to
  the kettle-jem gem root relative to the script instead of the caller's working
  directory.
- Generated GitHub Actions workflows now preserve existing push branch filters
  from destination workflows.
- GitHub Actions workflow templating now preserves existing destination SHA
  pins for the same action/version when accepted templates are stale, and emits
  a final warning telling maintainers to update the workflow template pins.
- SimpleCov templating now removes legacy kettle-soup-cover startup requires
  from `.simplecov` and upgrades modifier-form `spec_helper` coverage bootstraps
  to the full kettle-soup-cover `SimpleCov.start` block.
- Root Gemfile templating now keeps `nomono_requirements` before existing
  `gem "nomono", *nomono_requirements` calls when merging legacy local sibling
  wiring.
- Root Gemfile templating no longer adds generic direct-sibling path wiring for
  runtime dependencies already handled by project-specific local modular
  Gemfiles.
- Root Gemfile templating now evaluates the paired modular Gemfile for direct
  runtime dependencies handled by `*_local.gemfile` overrides, preserving
  released-vs-local switching after `accept_template` Gemfile rewrites.
- Root Gemfile templating now recognizes `eval_nomono_gems(gems: local_gems)`
  declarations in `*_local.gemfile` files before deciding whether a runtime
  dependency is already handled by paired modular local wiring.
- Local GitHub remotes now override generated gemspec `source_code_uri` tag URLs
  when deriving repository owner tokens, preventing stale homepage metadata from
  corrupting README logos and local sibling workspace env names.
- Bootstrap configs now seed runtime URI values, OpenCollective ENV overrides,
  and Gemfile template ownership so first-time full templating does not leave
  raw URI tokens or merge legacy Gemfile dependency sets into the generated
  bundle.
- Generated Gemfiles now activate the Bundler-locked `nomono` before loading
  `nomono/bundler`, avoiding global gem activation conflicts during
  templating.
- Generated Gemfiles now scope templating-only direct sibling local-path
  environment overrides to the direct dependency block so later modular
  Gemfiles do not accidentally enter local sibling mode.
- Generated style Gemfiles now skip released RuboCop-LTS gems that were already
  declared by earlier Gemfile evaluation, avoiding duplicate path/version
  declarations during templating.
- Generated documentation local Gemfiles now skip the current package and
  already declared gems before adding local family path overrides.
- Gem templates now require `appraisal2` >= 3.1.3.
- Generated style Gemfiles now require `appraisal2-rubocop` >= 0.2.2.
- Generated main Gemfiles now require `nomono` >= 1.0.6.
- Generated templating local Gemfiles now only use `TSLP_DEV` for local
  `tree_sitter_language_pack` path overrides and no longer derive that path
  from `SMORG_RB_DEV`.
- Generated gemspecs now require `version_gem` >= 1.1.14.
- Generated gemspecs now require `gitmoji-regex` >= 2.0.4.
- Generated documentation Gemfiles now require `yaml-converter` >= 0.2.3.
- Generated documentation Gemfiles now require `yard-fence` >= 0.9.5.
- Generated documentation Gemfiles now require `yard-timekeeper` >= 0.2.2.
- Generated documentation Gemfiles now require `yard-yaml` >= 0.2.2.
- Gemfile, gemspec, Appraisal, and Rakefile template merging now derives Ruby
  call source ranges and static string values from Prism nodes so heredoc
  string arguments are preserved transparently.
- Gemspec dependency preservation now rewrites project-version constant
  interpolation in dependency requirements to `spec.version` so preserved
  dependencies remain loadable after anonymous-module version loading.
- Removed retired funding links and template tokens from generated kettle-jem
  funding and README templates.
- Retemplated generated project metadata, support documentation, CI workflows,
  binstubs, and development dependency floors with `kettle-jem` v7.0.0.
- Generated README and workflow templates now treat Ruby 4.0 as MRI current,
  add discrete JRuby 10.0 and TruffleRuby 33.0 workflows/badges, and include a
  TruffleRuby HEAD badge pointing at the shared heads workflow.
- Generated CI workflows now disable `ruby/setup-ruby` Bundler caching for
  TruffleRuby 25.0 and JRuby 9.3 and run a serial Bundler install to avoid
  legacy engine setup failures.
- `kettle-jem install` now runs `rubocop_gradual:autocorrect` after templating
  and before the bootstrap commit when the destination project provides
  `bin/rake`, so project-local Ruby syntax floors can normalize generated
  files.
- `RUBOCOP_LTS_LOCAL` templating now switches the local `rubocop-lts/rubocop-lts`
  checkout to the branch matching the selected `rubocop-rubyN_N` wrapper before
  running setup and RuboCop Gradual normalization.
- Generated RuboCop-LTS local style Gemfiles now exclude the current project
  package and already-declared gems before adding local family path overrides.
- Generated funding templates now default missing OpenCollective orgs to
  `galtzo-floss` and warn when that fallback differs from the GitHub org.
- Shim gemspec templates now include the kettle-dev release/test harness
  dependencies required by `kettle-changelog`, `kettle-test`, and release tasks.
- Shim gemspec templates now resolve the generated gem version token instead of
  leaving `{KJ|GEM_VERSION}` unresolved.
- Shim and monorepo-root template profiles now include generated `.gitignore`
  files so local `.env.local` configuration is ignored consistently.
- Shim Gemfile templates now include `nomono` and the generated templating
  Gemfiles so `K_JEM_TEMPLATING=true bundle exec kettle-jem install` works.
- Shim Gemfile templates no longer add a Git-sourced replacement gem fallback;
  the released replacement gem is already declared by the generated gemspec.
- Shim Gemfile templates now use `https://gem.coop`, matching the full template
  and allowing released replacement gems to resolve without Git sources.
- Generated README compatibility sections now use prose for the test-matrix
  credit and render all generated details blocks with Markdown enabled.
- Generated README compatibility sections now pair the test-matrix credit with
  the kettle-dev logo and use a kettle-dev-specific details summary.
- The generated README dev/test stack table now includes `kettle-jem` with its
  Appraisals and CI workflow template role.
- The generated README dev/test stack table now includes `kettle-dev` and keeps
  stack gems in A-Z order while preserving self-exclusion.
- Gem templates and generated root Gemfiles now require `kettle-dev` >= 2.2.22.
- Generated SimpleCov setup now keeps `.simplecov` configuration-only and
  starts coverage explicitly from `spec/spec_helper.rb` for SimpleCov v1.
- `.simplecov` templating now removes obsolete `SimpleCov.start` blocks with a
  Prism AST cleanup pass while preserving destination-local configuration.
- `.simplecov` templating now removes the obsolete kettle-soup-cover config
  require with the same Prism AST cleanup pass so SimpleCov finishes loading
  before formatter configuration is required.
- `.simplecov` templating now migrates old generated `keep_destination`
  overrides and converts preserved `track_files` calls to `cover` calls.
- Generated spec helper templating now normalizes stale SimpleCov bootstrap
  blocks by deduplicating SimpleCov requires and restoring the formatter config
  require before `SimpleCov.start`.
- Generated spec helpers now document that requiring SimpleCov loads the
  configuration-only `.simplecov` before coverage starts.
- Generated coverage Gemfiles no longer pin SimpleCov to the pre-release-only
  `kettle-dev/simplecov` `fix-final-parallel-worker-formatting` branch.
- Generated workspace path examples now use the renamed `my` local workspace
  instead of the old `kettle-rb` checkout path.
- Generated coverage Gemfiles now require `kettle-soup-cover` >= 3.0.0.
- Generated Rakefiles now use `# simplecov:disable` / `# simplecov:enable`
  blocks instead of deprecated legacy coverage markers.
- `kettle-jem install` now uses the latest `kettle-family install` marker to
  activate locally installed template-stack source roots during templating
  setup.
- Generated Gemfiles now guard preserved runtime `eval_nomono_gems` workspace
  overrides during `K_JEM_TEMPLATING=true`, keeping templating bundles isolated
  from target runtime sibling path dependencies.
- Generated main Gemfiles now add templating-aware `nomono` wiring for direct
  runtime dependencies that exist as sibling gems in the same local family
  workspace.
- Install lockfile normalization now keeps direct sibling runtime dependencies
  available through the generated family `*_DEV` environment while still
  disabling templating-only path overrides.
- Generated kettle-jem usage instructions now use the `kettle-jem` executable as
  the bootstrap entrypoint instead of starting from `bundle exec kettle-jem`.
- Generated templating Gemfiles now resolve the local tree-sitter language pack
  workspace fork from `structuredmerge/vendor`.
- Generated Appraisals now use modern keyword hash syntax for the
  `appraisal2-rubocop` plugin declaration.
- Refreshed the generated `codecov/codecov-action` workflow pin and made
  workflow-pin specs validate immutable pin shape instead of exact live SHAs.
- Refreshed generated workflow templates to pin `actions/checkout` to the
  `v7.0.0` release.
- Gem templates and generated templating Gemfiles now require `kettle-dev` >= 2.2.12.
- The packaged gemspec template now uses the same `kettle-dev` 2.2.12 floor as
  generated Gemfile tooling.
- Generated templating Gemfiles now require `kettle-drift` >= 1.0.4.
- Gem templates now require `kettle-test` >= 2.0.8.
- Generated coverage Gemfiles now require `kettle-soup-cover` >= 2.0.2.
- Generated style Gemfiles now require `rubocop-gradual` >= 0.4.0.
- Generated style Gemfiles now require `appraisal2-rubocop` >= 0.2.1.
- Generated main Gemfiles now require `nomono` >= 1.0.4.
- Generated gemspec templates now preserve the full existing gemspec author list
  instead of replacing it with the primary author token.
- Retemplating now removes legacy `.github/workflows/tests.yml` files as
  obsolete workflows.
- Runtime dependency `token-resolver` now requires 2.0.3 or newer.
- Gem templates now require `turbo_tests2` >= 3.1.6 for the default
  `kettle-test` runner dependency.
- The README template now links `kettle-readme-backers` to the generated
  `bin/` binstub instead of a non-existent `exe/` path.
- The README template's test matrix credit now highlights the Kettle dev/test
  stack with BestGems, GitHub, and daily download rank links, excluding the
  current gem from its own stack table.
- The README dev/test stack table now includes `kettle-soup-cover`.
- Documentation templates now require `yard-yaml` >= 0.2.1.
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
  `coverallsapp/github-action` and `codecov/codecov-action`.
- Generated templating and unlocked dependency workflows no longer install the
  legacy tree-sitter action and rely on the packaged
  `tree_sitter_language_pack` runtime instead.
- Generated templating workflows and `kettle-jem prepare` now update `nomono`
  before install/selftest commands run, so stale locks do not activate old
  local-workspace wiring code.
- Generated GitHub Actions workflow templates now refresh pins for
  `github/codeql-action` sub-actions to v4.36.2.
- Generated workflow templates now pin `coverallsapp/github-action` and
  `codecov/codecov-action` to resolvable release SHAs instead of stripped
  SemVer strings.
- Generated README badge URLs now use the same URI-normalized form as
  `kettle-pre-release`, avoiding churn between encoded namespace separators
  and Unicode badge messages.
- Generated GitHub Actions workflow templates now refresh `ruby/setup-ruby` to
  the immutable SHA for v1.312.0 and `codecov/codecov-action` to the latest
  v7.0.0 release comment.
- Generated GitHub Actions workflow templates now refresh `ruby/setup-ruby`,
  `coverallsapp/github-action`, and `pozil/auto-assign-issue` pins.
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
- Documentation templates now require `yard-fence` >= 0.9.4.
- Documentation templates now require `yard-timekeeper` >= 0.2.1.
- Gem templates and generated templating Gemfiles now require `kettle-dev` >= 2.1.1.
- Gem templates now require `kettle-test` >= 2.0.3.
- Gem templates now require `appraisal2` >= 3.1.1.
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
- Generated main Gemfiles now install `nomono` >= 1.0.3 so local workspace
  override Gemfiles can load `nomono/bundler` from the released gem.
- Generated coverage workflows now pass `K_SOUP_COV_MIN_LINE` and
  `K_SOUP_COV_MIN_BRANCH` through to Code Coverage Summary thresholds instead
  of hardcoding `100 100`.
- Default semantic Git driver setup now writes repo-local `diff.smorg-*`
  command config as well as managed `.gitattributes`, so local `git diff`
  can actually invoke StructuredMerge drivers after templating.
- Runtime dependency `token-resolver` now requires 2.0.1 or newer.
- Generated gemspecs now require `version_gem` >= 1.1.12 while allowing the
  released 1.1 line.
- Gem templates now require `gitmoji-regex` >= 2.0.2.
- Gem templates now require `turbo_tests2` >= 3.1.1 for the default
  `kettle-test` runner.
- Generated style Gemfiles now use the latest released `rubocop-ruby*`
  wrapper patch constraints for the RuboCop-LTS family.
- Generated style Gemfiles now use the latest released `rubocop-lts` track
  constraints for every supported Ruby floor.
- Generated style Gemfiles now treat style dependency floors as latest-Ruby
  task dependencies, independent from the gemspec runtime Ruby floor.
- kettle-jem now requires `kettle-rb` >= 0.1.1.
- Generated coverage Gemfiles now require `kettle-soup-cover` >= 2.0.1.
- Generated documentation Gemfiles now require `yaml-converter` >= 0.2.1
  while allowing the released 0.2 line.

- Generated root Gemfiles no longer path-wire direct sibling dependencies from
  stale sibling directories whose gemspec defines a different gem name.
- Generated root Gemfiles now remove previously generated direct sibling wiring
  when the current sibling directory no longer defines the dependency gem.
- Generated RuboCop configs now activate the `rubocop-rspec` plugin for the
  packaged RSpec RuboCop overlay.
- Gemspec `spec.files` merging now supports the generated `Dir[...] + [...]`
  assignment shape on subsequent template runs instead of rejecting it as
  unsupported.
- Generated modular Gemfiles no longer redeclare runtime dependencies that are
  already supplied by the project gemspec.
- Existing generated gemspecs with splat-based `spec.files` assignments now
  retain configured root license files from the template instead of preserving
  the old splat-only assignment wholesale.
- Gemspec `spec.files` templating now fails hard for unsupported package-list
  shapes instead of silently preserving destination content.
- Generated gemspecs now package active root license files declared by the
  project license configuration.
- Gemspec templating no longer preserves frozen `spec.files` override blocks;
  `spec.files` is structurally merged so stale frozen package lists cannot
  replace the merged package payload.
- README template merging no longer duplicates preserved destination-only
  subsections when they are already inside another preserved destination
  section.
- Generated gemspecs now add an inline `Gemspec/RequiredRubyVersion` RuboCop
  disable when the published runtime Ruby floor is below 2.0.
- `kettle-jem install` no longer tries to switch the local RuboCop-LTS checkout
  while templating the RuboCop-LTS checkout itself.
- Generated style Gemfiles now require `rubocop-ruby3_2` >= 3.0.6 so
  Appraisal/RuboCop tasks do not select damaged packages missing
  packaged RuboCop-LTS configuration files.
- Gemspec `spec.files` merging now preserves `Dir[...]` glob expansion when
  merging destination glob entries into an array-based template assignment by
  generating concatenated `Dir[...] + [...]` package file expressions.
- Quiet templating orchestration no longer passes unsupported `--quiet`
  switches to Bundler subcommands such as `bundle binstubs` or `bundle lock`;
  only Bundler subcommands documented with `--quiet` receive that flag.
- Gemspec `spec.files` merging now inserts missing trailing commas when moving
  existing collection entries before appended template entries, preventing
  invalid Ruby when a destination's former last entry had no comma.
- Gemfile templating now preserves destination-only Ruby-bucket
  `eval_gemfile` entries, preventing configured recording Gemfiles from being
  dropped when the main Gemfile template is reapplied, and restores the main
  recording Gemfile eval when existing Appraisals show recording is configured.
- Generated templating Gemfiles no longer duplicate `appraisal2-rubocop`; the
  Appraisal generator formatter is provided by the style Gemfile loaded from
  `Appraisal.root.gemfile`.
- Generated local Gemfile overrides now load `nomono/bundler` without activating
  nomono's runtime dependencies during Bundler Gemfile evaluation, and bundled
  handoff no longer runs through the RubyGems `kettle-jem` wrapper.
- Gemspec template merging now preserves chained squiggly heredoc assignments
  such as `spec.description = <<~DESC.strip` instead of replacing only the
  opener line.
- Generated README post-processing now adds missing compatible JRuby 10.0 and
  TruffleRuby 33.0 compatibility badges when the matching workflow files exist.
- Shunted Gemfile generation no longer duplicates broad gemspec development
  dependencies that already have explicit modular Gemfile compatibility
  overrides, such as old-Ruby fork handling.
- `kettle-jem install` no longer fails a stale outer bootstrap commit step when
  the bundled handoff already committed the generated changes.
- Shim template discovery now recovers the package version from the git index
  or `HEAD` when a previous failed run already replaced the working-tree
  version file with replacement-gem aliases.
- Shim profile version files now alias the replacement gem version constants
  and compute the replacement version require path relative to the generated
  shim version file, fixing nested require paths such as `omniauth/jwt`
  shimming `omniauth/jwt2`.
- `kettle-jem install` now skips its bundled handoff when the destination bundle
  does not include `kettle-jem`, allowing shim-only gems to finish templating.
- Namespace discovery now detects nested module declarations in the public
  entrypoint before falling back to a stale generated version namespace, and the
  README namespace badge now uses the shield-safe namespace token.
- OpenCollective template tokens now use `.github/FUNDING.yml` as a valid org
  source, preventing empty `https://opencollective.com//...` README and
  FUNDING links when destination env variables are not loaded.
- Monorepo-root templating now uses the no-OpenCollective funding templates
  when no OpenCollective slug is configured, preventing empty generated
  OpenCollective badge URLs in root `FUNDING.md` files.
- The `kettle-jem` CLI now refuses to run from the `kettle-jem` project root
  against a different destination, so templating cannot silently use
  `kettle-jem`'s own environment instead of the target repo's environment.
- Fixed `bin/kettle-jem-workflow-pins` so its synthetic workflow is valid YAML
  and child command failures include stdout diagnostics.
- Fixed `bin/kettle-jem-workflow-pins` so sub-action updates reported under the
  parent action repository, such as `github/codeql-action`, update the full
  pinned action path instead of being silently counted as zero updates.
- Fixed `bin/kettle-jem-workflow-pins` to default to the same broad upgrade
  strategy used by family workflow pin maintenance, so minor action releases
  such as `ruby/setup-ruby` are not missed by template pin refreshes.
- README compatibility badge pruning now compares Ruby minor series so patch
  floors like `>= 1.8.7` and `>= 2.2.2` keep their matching minor badges.
- Gemspec template summary and description tokens now strip an already-present
  project emoji and escape double quotes before rendering inside Ruby strings.
- Templates now remove `version_gem` dependencies and entrypoint references for
  gems whose minimum Ruby is below 2.2 while keeping the standard
  `<Namespace>::Version::VERSION` constant shape.
- Curated Bundler binstub pruning now keeps any executable owned by the curated
  binstub gems, so newly added executables such as `kettle-bump` are retained
  without hardcoding every executable name.
- Gem templates now require `appraisal2` >= 3.1.2.
- Gemspec merging now lets explicit `KJ_AUTHOR_EMAIL` and `KJ_AUTHOR_NAME`
  environment overrides replace destination `spec.email` and `spec.authors`
  metadata instead of preserving stale project fields over resolved template
  tokens.
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
