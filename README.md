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
- `ruby-merge`

## Development

This repository is intentionally starting with a minimal scaffold. The first
implementation work should follow the same slice-by-slice conformance path used
by the TypeScript, Rust, and Go monorepos.

Integration tests should consume the shared fixture corpus from the sibling
`../fixtures` repository rather than copying fixture data into this monorepo.
