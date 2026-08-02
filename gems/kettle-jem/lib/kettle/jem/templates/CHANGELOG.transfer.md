# kettle-jem Transferable Changelog

This file contains **destination release notes**, not a record of every template
implementation change. Add an entry only when applying the template change
changes behavior, configuration, compatibility, packaging, documentation, or
developer workflow for a destination gem. A replayed entry is intentionally
inserted into that gem's `Unreleased` section and must make it pending for
release. Do not add entries for internal template refactors, merge mechanics,
or other changes with no destination user or developer impact.

`kettle-jem-template-YYYYMMDD-NNN` is a stable replay identifier, not metadata
that exempts the entry from the destination changelog or release state.

An entry may declare destination-only applicability immediately after its
identifier: `[if field=value & other.field!=value]`. Kettle/Jem evaluates these
filters against a fixed project context, never transfers them to a destination
changelog, and rejects unknown fields, values, and operators. Use filters only
for genuine destination applicability boundaries.

Available fields are `profile`, `topology`, `ruby.min`, `engine.jruby`,
`engine.truffleruby`, `engine.alternates`, `feature.appraisals`,
`feature.rubyforum`, `feature.rubyforum_project_tag`,
`feature.corporate_sponsors`, `feature.organization_logo`,
`feature.structuredmerge_driver`, `feature.dedicated_version_gem`,
`workflow.dep_heads`, `workflow.jruby_94`, and `version_gem.mode`. Boolean
fields accept `true` or `false`; `ruby.min` accepts normal version comparisons;
the other fields accept `=` or `!=`.

## Added

- kettle-jem-template-20260720-001 [if feature.corporate_sponsors=true] - READMEs can now display configured
  corporate sponsor logos.
- kettle-jem-template-20260720-005 - README Support & Community links now
  include RubyForum.
- kettle-jem-template-20260726-001 - Projects now include YARD lint
  configuration and documentation dependencies so documentation issues fail
  before generated docs are refreshed.
- kettle-jem-template-20260727-001 - Spec harness documentation now lists the
  RSpec helpers provided by `kettle-test`.
- kettle-jem-template-20260729-005 [if feature.rubyforum_project_tag=true] - Gemspec metadata now publishes this
  project's RubyForum tag as `mailing_list_uri`, and support docs link to the
  tagged RubyForum community alongside Discord.

## Changed

- kettle-jem-template-20260716-002 - Gemspecs now ship fewer repository-only
  files, reducing package noise for downstream packagers.
- kettle-jem-template-20260720-002 - Development Gemfiles now use the released
  `tree_sitter_language_pack` gem 1.13.3 or newer by default.
- kettle-jem-template-20260725-002 - Version specs now use `anonymous_loader` to
  cover `version.rb` without redefining constants, or are removed when version
  specs are not managed for the project.
- kettle-jem-template-20260728-001 [if feature.appraisals=true] - Generated Ruby workflows now use clearer
  setup-ruby-flash planning and can prepare appraisal-only jobs without
  installing the main Gemfile bundle.
- kettle-jem-template-20260801-001 - Generated README gem dashboard links now
  use ClickGems instead of BestGems.

## Fixed

- kettle-jem-template-20260802-001 - Devcontainer JSON files now merge as JSONC,
  preserving comments and trailing commas during template updates.
- kettle-jem-template-20260801-004 - Generated organization README logos now
  use GitHub's stable organization avatar endpoint instead of assuming a
  matching Galtzo-hosted asset exists.
- kettle-jem-template-20260801-003 - Generated project metadata and
  documentation now normalize configured underscore hostnames to valid
  hyphenated hostnames.
- kettle-jem-template-20260801-002 - Generated RSpec helpers now normalize
  managed configuration block bindings structurally, preventing mixed block
  parameter names from producing invalid configuration after a merge.
- kettle-jem-template-20260716-001 [if profile=shim] - Shim gems now package `LICENSE.md` instead
  of a missing `LICENSE.txt` file.
- kettle-jem-template-20260720-003 [if feature.structuredmerge_driver=true] - StructuredMerge Git diff driver config now
  uses the installed `smorg-rb` driver command.
- kettle-jem-template-20260720-004 [if engine.alternates=false] - MRI-only projects now omit JRuby and
  TruffleRuby workflow jobs.
- kettle-jem-template-20260725-001 [if engine.alternates=true] - Release pull request branches beginning
  with `feature/release` now run JRuby and TruffleRuby workflows.
- kettle-jem-template-20260726-002 - Generated version files now document their
  version namespace and constants, reducing warning-only YARD lint output.
- kettle-jem-template-20260726-003 - Coverage upload steps now treat Coveralls,
  QLTY, and Codecov as optional, so provider outages do not fail CI when local
  coverage thresholds still pass.
- kettle-jem-template-20260728-002 - Generated RuboCop configs now ignore the
  same `gemfiles/vendor/bundle` tree as `.gitignore`, so vendored dependency
  installs are not reported as project lint debt.
- kettle-jem-template-20260728-003 [if workflow.dep_heads=true & engine.truffleruby=true] - Generated dep-heads workflows now run
  TruffleRuby jobs with current RubyGems and Bundler, avoiding setup failures
  before the test suite starts.
- kettle-jem-template-20260728-004 [if workflow.dep_heads=true & feature.appraisals=true] - Generated dep-heads workflows now use the
  setup-ruby Bundler install path for direct appraisal Gemfiles, avoiding rv
  lockfile parser failures on Git and path dependencies.
- kettle-jem-template-20260728-005 - VersionGem bootstrap now creates the
  missing canonical version spec when a project only has shim namespace version
  specs.
- kettle-jem-template-20260729-001 [if workflow.jruby_94=true] - Generated JRuby 9.4 workflows now use the
  legacy manual bundle install path, avoiding setup-time Bundler full-index
  failures against `gem.coop`.
- kettle-jem-template-20260729-002 [if feature.dedicated_version_gem=true] - VersionGem bootstrap now preserves
  and templates dedicated `version_gem.rb` entrypoints even when the gemspec
  dependency is intentionally omitted, and generated anonymous-loader specs
  cover both `version.rb` and `version_gem.rb`.
- kettle-jem-template-20260729-003 [if ruby.min<2.2] - Old-Ruby gems below the VersionGem runtime
  floor now get managed minimal `version.rb` files and anonymous-loader version
  specs without adding `version_gem`.
- kettle-jem-template-20260730-001 - Gemspec package file enumeration now runs
  relative to the gemspec directory, so release package contents stay correct
  even when the gemspec is loaded from another working directory.
