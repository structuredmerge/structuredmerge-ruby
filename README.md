# Structured Merge Ruby

Monorepo for the new Ruby implementation of the Structured Merge library
family.

This repository is a fresh implementation aligned to the current
cross-language spec and fixture corpus. The older Ruby gems in this workspace
remain reference material only.

Initial planned Ruby packages:

- `tree-haver`
- `ast-merge`
- `text-merge`
- `json-merge`
- `toml-merge`
- `yaml-merge`
- `typescript-merge`
- `rust-merge`
- `go-merge`
- `ruby-merge`

## Development

This repository follows the same slice-by-slice conformance path used by the
TypeScript, Rust, and Go monorepos.

Integration tests should consume the shared fixture corpus from the sibling
`../fixtures` repository rather than copying fixture data into this monorepo.

Bundler path gems are the default isolation mechanism inside this monorepo.
When this repository needs to consume sibling workspace projects outside the
monorepo itself, prefer `nomono`-driven Bundler wiring rather than manual Ruby
load-path changes.
