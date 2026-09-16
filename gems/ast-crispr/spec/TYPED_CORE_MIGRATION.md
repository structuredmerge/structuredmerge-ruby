# Typed core consumer verification

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

Verified locally on Ruby 4.0.6/Linux: 44 examples, zero failures, using core gem
SHA-256 `f9978879f38b9f0f79f47a1480426bd336b655a4345fab72044a6df6694700f0`.
Integration tests assert the prototype gem is not activated, cover every report
kind, and preserve explicit-edit success/rejection and exact Unicode/BOM/CRLF
output. Invalid request normalization retains RuntimeError classification;
exact historical error-message equivalence is not asserted for all malformed
inputs.

This is not the full downstream acceptance gate. Full applicable kettle-jem and
other downstream suites, lint/coverage, registry installation and hosted CI still
need validation. The normal released-package gate now names structuredmerge-core
but is not bypassed by the artifact bundle. No package publication, default
authority change, or native selector replacement is implied.
