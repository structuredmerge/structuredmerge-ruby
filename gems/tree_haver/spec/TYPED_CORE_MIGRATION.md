# Typed Rust parser consumer verification

The explicit `rust_tslp` backend now loads `structuredmerge_core`, registers a
Rust-owned language-pack provider in TreeHaver's shared registry and calls
`parse_sources` with typed requests/results. It no longer requires or invokes
the host-prototype gem. GrammarFinder's optional package requirement and the
development/released-package Gemfile branches name `structuredmerge-core`.
Parser defaults and native-parser preferences are unchanged.

The adapter keeps TreeHaver's node/tree methods, JSON5 type aliases, string
diagnostics and Hash provenance surface. Provenance now identifies the actual
registered provider (`tree_haver.rust_tslp.<language>`) instead of the generic
legacy ID. Diagnostic wording comes directly from the typed provider. Text is
sliced from an immutable source copy using validated byte spans; topology,
field names, missing/error flags come directly from typed Rust facts. Only the
versioned open extension payload uses JSON: `tree-haver.tree-sitter.node/v1`
under namespace `tree-sitter` contains the native boolean `extra` flag. No
comment attachment, incremental parsing or query implementation is invented.

Registration is serialized and cached only for IDs created by this adapter.
Foreign duplicate IDs fail; the adapter never adopts or overwrites them.
`reset!` resets package availability only, not registry ownership. External
removal of an adapter-owned ID causes subsequent parses to fail closed, not
silently re-register or fall back. The synchronous adapter uses limits of one
input, 64 MiB input, one million nodes and 1000 diagnostics; it does not expose
per-call cancellation/deadline configuration. Native in-flight parsing is not
preemptively cancellable.

On Ruby 4.0.6/Linux, `bundle exec kettle-test` passes all 90 examples with the
isolated installed core gem SHA-256
`8301d87287df163c3991292026b9d7779fa4e960661f7d6a00b36745b55911ea`.
The real-parser matrix covers Bash, Go, JSON, JSON5, Markdown, Ruby, Rust, TOML,
TypeScript and YAML. Tests include syntax-error partial trees, field navigation,
native extra flags, Unicode/CRLF bytes and source mutation isolation. The
integration gate verifies the prototype module is not loaded. Test log:
`tmp/kettle-test/turbo_tests2-20260916-110936-1294023.log`.

Reproduce from this gem with `BUNDLE_GEMFILE=gemfiles/typed_core.gemfile`,
`STRUCTUREDMERGE_DEV` pointing at this worktree's `gems/`, `GEM_HOME`/`GEM_PATH`
including the isolated installed core artifact, and `K_SOUP_COV_DO=false`.
Run `bundle install`, then `bundle exec kettle-test` via `mise exec -C`.
Set `TREE_HAVER_LANGUAGE_PACK_CACHE_DIR` to the kernel's `tmp/typed-tslp-cache`.
Nested worktrees need the shared fixtures checkout adjacent to the worktree.
The environment-specific generated bundle lock remains local. No load-path
mutation is needed.

This is a pre-publication artifact gate, not registry-install, hosted CI,
coverage, full lint, platform ABI or release approval. Other consumers and the
legacy facade's final retirement remain separate migration work.
