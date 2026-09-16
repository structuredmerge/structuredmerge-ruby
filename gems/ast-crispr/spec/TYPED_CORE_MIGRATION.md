# Typed core consumer verification

## Current artifact revalidation (2026-09-16)

This migration is now integrated into local Ruby main (fast-forward through
`0a1f4ee32`). The consumer passes 51 examples via `kettle-test` against
the latest installed core gem, SHA-256
`96291c720058b22cc80d2992943f65878faf36808639ebfc06f52ec24b71209e`.
The full kettle-jem downstream suite also passes 681 examples. Runs used the
pre-publication bundles in `ruby/tmp/worktrees/typed-crispr-consumer`, whose
committed consumer code is identical to the integrated revision. Test logs are
under each gem's `tmp/kettle-test/`; the downstream run is
`turbo_tests2-20260916-104302-1248551.log`.

This refreshes the historical artifact evidence below. It does not close hosted,
registry, full lint/coverage or remaining downstream gates, authorize prototype
publication, or move structural selection/filesystem apply out of Ruby.

`RustHostProvider` retains its opt-in identity and existing Hash reports, but
loads `structuredmerge_core` and calls generated typed operations. The adapter
only normalizes transport fields and projects returned DTOs. It does not select
AST nodes, classify structural profiles, render edits itself, or write files.
`backend: :rust_tslp` remains legacy capability metadata for compatibility; these
report/edit operations do not invoke a parser.

`gemfiles/typed_core.gemfile` is the pre-publication artifact test bundle. Supply
`STRUCTUREDMERGE_DEV` pointing at the worktree's `gems/`, and use a GEM_HOME with
the isolated, built `structuredmerge-core` platform gem installed. With
`BUNDLE_GEMFILE=gemfiles/typed_core.gemfile`, run `bundle install` and
`K_SOUP_COV_DO=false bundle exec kettle-test` from this gem. No manual Ruby
load-path changes are used. The existing fixture tests expect the fixtures
checkout adjacent to the Ruby worktree; nested worktrees need that fixture path
provided separately. The environment-specific lockfile is intentionally local.

Verified locally on Ruby 4.0.6/Linux: 51 examples, zero failures, using core gem
SHA-256 `f9978879f38b9f0f79f47a1480426bd336b655a4345fab72044a6df6694700f0`.
Integration tests assert the prototype gem is not activated, cover every report
kind, and preserve explicit-edit success/rejection and exact Unicode/BOM/CRLF
output. The shared-fixture integration suite also compares complete boundary,
match, selection, destination, operation and ordered batch reports, plus every
valid limit description and invalid limit rejection in slices 916–921 and 923.
Invalid request normalization retains RuntimeError classification;
exact historical error-message equivalence is not asserted for all malformed
inputs.

The full kettle-jem suite also passes locally: 681 examples, zero failures.
Its temporary bundle is `gems/kettle-jem/tmp/typed_core.gemfile`, containing
`eval_gemfile '../Gemfile'` and `gem 'structuredmerge-core', '= 0.2.0'`.
Run through `mise exec -C <worktree>/gems/kettle-jem --`, with the same GEM_HOME,
GEM_PATH and STRUCTUREDMERGE_DEV used above, BUNDLE_GEMFILE pointing at that file,
and STRUCTUREDMERGE_RUST_DEV, STRUCTUREDMERGE_RUST_HOST_PUBLISHED,
K_JEM_TEMPLATING and K_SOUP_COV_DO explicitly false. Run `bundle install`, then
`bundle exec kettle-test`. Keeping the temporary Gemfile beneath kettle-jem is
important: kettle-test derives its project root from BUNDLE_GEMFILE, so a bundle
under the monorepo's tmp directory selects the wrong suite. This is regression
evidence, not proof that each downstream operation invokes the typed core.

This is not the full downstream acceptance gate. Other applicable downstream
suites, lint/coverage, registry installation and hosted CI still need validation.
The normal ast-crispr released-package gate now names structuredmerge-core
but is not bypassed by the artifact bundle. No package publication, default
authority change, or native selector replacement is implied.
