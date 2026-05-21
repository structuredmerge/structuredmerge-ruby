# StructuredMerge Ruby Examples

These examples are user-level scripts for the Ruby implementation. They are not
the tiny conformance snippets from `structuredmerge/fixtures`; they are meant to
show realistic merge tasks that a person can run, inspect, and adapt.

Run them from `structuredmerge/ruby` with the repository bundle:

```console
bundle exec ruby examples/bin/run
bundle exec ruby examples/json_merge/package_manifest_merge.rb
```

The scripts intentionally use the public gem APIs. They avoid local load-path
mutation, so dependency resolution stays under Bundler and the root Gemfile.

## Examples

| Example | What it demonstrates |
|---|---|
| `json_merge/package_manifest_merge.rb` | Merging a template package manifest into a destination manifest while preserving destination values. |
| `markdown_merge/readme_template_merge.rb` | Applying README template sections without replacing destination-owned sections. |
| `ruby_merge/plugin_class_merge.rb` | Adding template requires and methods while preserving destination method bodies. |
| `toml_merge/tool_config_merge.rb` | Merging tool configuration tables while preserving local overrides. |
| `tree_haver/backend_report.rb` | Reporting available merge-family backend profiles and parser wiring. |

## Shared Scenarios

The cross-language scenario runner lives in `structuredmerge/spec/examples`.
It delegates the Ruby implementation to `examples/bin/run-scenario`.
Go, Rust, and TypeScript adapters use the same scenario directory contract.
