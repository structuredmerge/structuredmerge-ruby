# Opt-in JSON typed-core migration

`Json::Merge::RustHostProvider` keeps its compatibility name and `rust.json`
provider ID, but now delegates all four operations to `structuredmerge-core`.
It no longer inherits `Ast::Merge::RustHostProvider`, loads the prototype gem,
compares owner fragments, or searches source text for locations. Parser
registration uses TreeHaver's existing typed Rust language-pack adapter and its
owned-registration cache; it does not introduce another registry or fallback.

Requests use explicit roles, UTF-8 bytes/digests and the JSON core profile.
Unknown fields/selectors fail closed instead of being ignored. Binary strings
containing valid UTF-8 are copied and relabeled without transcoding; caller
strings remain unchanged. Limits are three input sources, 64 MiB aggregate
input, one million nodes and 1000 diagnostics. No default backend changes.

Compatibility changes are intentional:

- Owner identities are JSON Pointer paths, not the old non-unique member-name
  strings. Analysis includes the root, including scalar/empty roots.
- Diffs retain the Rust document summary and nested owner classifications.
  Summary and ancestor subjects overlap; these records are not an edit script.
- Lines are derived from parser byte-oriented points, never `source.index`.
- `verification.rust_core` identifies typed execution. Source preservation
  claims reflect actual core verification rather than unconditional success.
- `typed_result` retains the complete core evidence as portable Ruby values,
  including canonical conflicts/diagnostics and unknown metadata. Only a closed
  set of generated read-only record types is traversed, never executable handles.
  Open metadata values are decoded individually; requests and results do not
  travel as opaque whole-operation JSON strings. Hash order is deterministic.

The pre-publication `gemfiles/typed_core.gemfile` uses the installed core artifact
and nomono-wired local native layers. It explicitly includes the released Ruby
language-pack parser for parity checks. The artifact bundle fails if the core
cannot load. Released-package current/coverage gates remain separate and still
require publication at the plan's later gates.

Verification: the complete JSON suite passes through `kettle-test`, 93 examples,
using Ruby 4.0.6 and the installed core gem with SHA-256
`d5d11261c7954780bb2975e744b60483ea6cb73a39eed845733d5a7476c97ea2`.
The adapter tests exercise real analysis/diff/merge calls, repeated fragments,
Unicode byte spans, binary UTF-8, malformed input, conflicts, deterministic
portable evidence and explicit constraint rejection. Existing native semantic
comparisons cover JSON/JSONC/JSON5 and exact/independent/conflicting merge3 cases.
Two inappropriate negative-backend tags were removed from those parity tests:
they previously excluded the comparisons precisely when Rust was available.

Kernel logs: `tmp/json-ruby-consumer-{bundle,focused,parity,full}.log`.
This is local consumer integration, not broad Ruby golden-master authority,
lint/coverage/platform or release approval. The Git adapter and other family
adapters still require migration. No package publication or Alef push occurred.
