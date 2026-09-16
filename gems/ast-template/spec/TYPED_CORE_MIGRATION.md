# Typed template consumer verification

## Current artifact revalidation (2026-09-16)

This migration is now integrated into local Ruby main (fast-forward through
`0a1f4ee32`). The consumer passes 78 examples via `kettle-test` against
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

The opt-in `RustHostProvider` now calls generated `structuredmerge-core` typed
options, profile and read-only directory-plan operations. It retains its provider
identity, top-level symbol keys, nested string keys, enum strings and historical
nil omission rules. Request normalization and report projection are transport
work only: configuration resolution, planning and preview generation stay in
Rust. Ruby template application and filesystem writes are unchanged. The legacy
`:rust_tslp` capability label is retained; these report APIs do not select a parser.

No prototype fallback or dependency is added. `gemfiles/typed_core.gemfile` is a
pre-publication test bundle using Bundler/nomono for local siblings and the built
core platform gem. Run from this gem with `STRUCTUREDMERGE_DEV` set to the
worktree's `gems/`, GEM_HOME/GEM_PATH including the installed core artifact,
`BUNDLE_GEMFILE=gemfiles/typed_core.gemfile`, and `K_SOUP_COV_DO=false`:
`bundle install`, then `bundle exec kettle-test`. The fixture checkout must be
adjacent to the Ruby worktree, as required by existing fixture tests. The local
bundle lock is ignored, not substituted for normal released-package locks.

Verification on Ruby 4.0.6/Linux: 78 examples pass, including full Slice 367
options/profile reports and the Slice 362 plan golden; both directory trees are
checked for unchanged bytes. Additional tests cover no prototype activation,
token configuration, nil omission, input immutability, malformed input rejection
and refusing apply mode in the planner. Automatic optional-backend test filters
remain in effect. Exact historical malformed-input error messages are not
promised; transport validation retains RuntimeError failures.

The core artifact has SHA-256
`52715ecc508a4db02d702feab8b138114276d11ad81bb564eb44ad7f46e50a25`.
This is local consumer evidence, not registry/platform acceptance, full
lint/coverage, hosted CI or permission to change the default provider. The
directory planner inherits the documented local filesystem limitations in the
kernel's `contracts/TYPED_TEMPLATE_REPORTS.md`; it is not a sandbox or apply API.
