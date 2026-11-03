# Repository guidance

## TSLP specs on Ruby head

Tree-sitter Language Pack (TSLP) uses native gems with a released Ruby ABI. Ruby head is permanently unsupported by that policy. Every spec that would invoke a TSLP-backed grammar must skip on Ruby head with:

```ruby
skip_for(engine: "ruby", versions: "head", reason: "Ruby head is permanently unsupported by tree_sitter_language_pack's released-ABI-only native gem policy")
```

Apply this to every TSLP-backed grammar and backend across the entire StructuredMerge Ruby family, including specs that select TSLP indirectly through a provider's default backend.

The `kreuzberg-language-pack` backend is an alias for TSLP and follows this same rule.

## Local setup (bundler in a gem under `gems/`)

Sibling gems and `structuredmerge-core` are not on the registry at matching versions, so `bundle install` fails unless they are wired as local paths. Set both variables first:

```sh
export STRUCTUREDMERGE_DEV=/path/to/ruby/gems            # this repo's gems/ directory
git clone --depth 1 https://github.com/structuredmerge/structuredmerge.git /path/to/core
export STRUCTUREDMERGE_CORE_DEV=/path/to/core            # contains packages/ruby
cd gems/<gem> && gem install nomono && bundle install && bundle exec rspec
```

- Ruby version comes from `mise.toml` (`mise install`, then `mise trust`).
- `STRUCTUREDMERGE_CORE_DEV` is resolved relative to `$HOME` unless absolute.
- `bundle install` rewrites `Gemfile.lock`; do not commit those changes.
- Some `psych-merge` fixture specs read `/code/fixtures/...` from the core repo and fail without it; this is environmental.
