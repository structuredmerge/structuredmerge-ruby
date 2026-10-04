# Typed Git provider migration

The compatibility class `Ast::Merge::Git::RustHostProvider` now selects
`kernel.git.json.v1` through `structuredmerge-core`. It has no prototype require
or whole-operation JSON string transport. Shared request/result conversion lives
in `Ast::Merge::TypedCoreProvider`; JSON uses the same converter. Ruby supplies
source identities, selects the existing TreeHaver parser registration and
projects records. Rust owns classification, merge decisions and marker rendering.

Only merge3 is advertised. All four protocol methods still exist, with other
operations explicitly unsupported. Provider registration now permits nonempty
known capability subsets; registry selection still filters by operation.

Git argv marker widths are converted to integers, and label keys to strings.
Rust validates marker/label policy. Canonical conflicts and full typed results
remain portable Ruby values; the render report labels unresolved review artifacts
and the existing limitation that ours is retained outside conflicts. There is no
blanket preservation or reparse claim for conflict output. Clean output retains
actual Rust verification. The Git adapter owns file writes and exit status only.

Use `gemfiles/typed_core.gemfile` with an installed development core artifact,
`STRUCTUREDMERGE_DEV` pointing to this worktree's gems, and `kettle-test`. For the
full suite, both `BUNDLE_GEMFILE` and `KETTLE_FAMILY_BUNDLE_GEMFILE` must be absolute
paths to this artifact Gemfile, because Git-driver subprocesses change directory.
This is separate from released-package, lint/coverage and hosted CI gates.

Focused coverage includes clean and conflict writes, leave-ours, unrenderable
conflict write errors, malformed input, custom markers/labels, invalid options,
explicit command-provider registration, canonical alternatives and JSON-portable
evidence. See the plan evidence log for current full-suite results and limitations.
