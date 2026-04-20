# Ruby PLAN

## Objective

Build a new Ruby implementation of the Structured Merge stack as a monorepo of
publishable gems, aligned to the current shared spec and fixture corpus.

This repository is expected to supersede the older Ruby merge-family gems over
time. Those existing gems remain prior art, not the implementation baseline.

## License

Planned dual license for all new Ruby merge-stack packages:

- `AGPL-3.0-only`
- `PolyForm-Small-Business-1.0.0`

Reference:

- `../plans/LICENSE_TEMPLATE_PLAN.md`

## Scope Boundary

This plan does not attempt to port the legacy Ruby gems line for line.

Initial focus:

1. parser/runtime adapter
2. merge core abstractions
3. shared-fixture conformance runner
4. JSON, text, TOML, and YAML merge parity
5. source-language family parity

Deferred:

- migration tooling from the older Ruby gems
- templating/scaffolding beyond what the shared spec requires
- compatibility shims for legacy APIs

## Proposed Gem Family

Initial gem candidates:

- `tree-haver`
- `ast-merge`
- `text-merge`
- `json-merge`
- `toml-merge`
- `yaml-merge`

Possible later gems:

- `ruby-merge`
- `markdown-merge`
- `merge-ruleset`

## Prior Art Mapping

Reference siblings to study as prior art only:

- `tree_haver`
- `ast-merge`
- `json-merge`
- `toml-merge`
- `psych-merge`
- `markdown-merge`

The new Ruby stack should prefer the current spec, fixtures, and proven
cross-language contracts over legacy implementation detail.

## MVP Deliverables

### 1. `tree-haver`

- parser registry/loading abstraction
- normalized parse result wrapper
- diagnostics for parse errors

### 2. `ast-merge`

- shared merge result model
- diagnostics model
- policy and conformance vocabulary
- review/replay transport

### 3. Family gems

- `text-merge`
- `json-merge`
- `toml-merge`
- `yaml-merge`

Each family gem should catch up through the current shared fixture slices
before deeper Ruby-specific extensions are considered.

## Non-Goals For V1

- reproducing legacy gem internals
- preserving old API shapes for compatibility
- using the old Ruby implementation as anything other than reference material

## Decisions

- Use one monorepo workspace with multiple publishable gems.
- Treat the current spec and shared fixtures as the primary source of truth.
- Use the dynamic-language perspective to pressure contracts that may be too
  type-shaped today.
