# Ast::Merge RSpec Support

`Ast::Merge::RSpec` provides shared examples, dependency tags, and merge-gem registration helpers for the `*-merge` family.

## Entry points

### Downstream merge gems

Most gems should load the combined entry point:

```ruby
require "ast/merge/rspec"
```

That loads:

- TreeHaver backend dependency tags
- Ast::Merge merge-gem dependency tags
- Shared conformance fixture helpers
- Portable provider snapshot and differential replay helpers
- Ast::Merge shared examples

### Split loading for `ast-merge` itself or registration-heavy suites

If a suite needs to declare merge-gem tags before RSpec config runs, use the split loading pattern:

```ruby
require "ast/merge"
require "ast/merge/rspec/setup"

Ast::Merge::RSpec::MergeGemRegistry.register_known_gem(
  :markly_merge,
  require_path: "markly/merge",
  merger_class: "Markly::Merge::SmartMerger",
  test_source: "# Test\n\nParagraph",
  category: :markdown,
)

Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(
  :markly_merge,
)

require "ast/merge/rspec/dependency_tags_config"
require "ast/merge/rspec/shared_examples"
```

This is the pattern used by `spec/spec_helper.rb` in this repository.

## Dependency tags

Ast::Merge tags let specs opt into format-specific dependencies.

Available merge-gem tags include:

- `:markly_merge`
- `:commonmarker_merge`
- `:markdown_merge`
- `:prism_merge`
- `:bash_merge`
- `:rbs_merge`
- `:json_merge`
- `:toml_merge`
- `:psych_merge`
- `:dotenv_merge`
- `:any_markdown_merge`

Example:

```ruby
RSpec.describe(MyMarkdownFeature, :markly_merge) do
  it "runs only when markly-merge is available" do
    # ...
  end
end
```

TreeHaver backend tags are loaded alongside these helpers; see the TreeHaver RSpec docs for backend-specific tags.

## Shared conformance fixtures

`Ast::Merge::RSpec::ConformanceFixtures` is spec-harness support for merge gems that import shared fixtures from the sibling `fixtures` repository.

Use it to document implementation gaps without hiding imported shared fixture cases:

```ruby
support = support_for_conformance_fixture(
  "delegated_child_operations",
  pending_roles: {
    delegated_child_operations: {
      reason: "parser-backed child delegation is not implemented yet",
    },
  },
)

apply_conformance_fixture_support!(support)
```

`pending` support calls RSpec `pending`, so the example fails as fixed once it unexpectedly passes. `unsupported` and `skipped` support call RSpec `skip`.

## MergeGemRegistry

`Ast::Merge::RSpec::MergeGemRegistry` tracks loaded and bootstrap-declared `*-merge` gems and exposes availability checks for dependency tags.

### Registering a gem

A merge gem can self-register when it is loaded:

```ruby
if defined?(Ast::Merge::RSpec::MergeGemRegistry)
  Ast::Merge::RSpec::MergeGemRegistry.register(
    :my_merge,
    require_path: "my/merge",
    merger_class: "My::Merge::SmartMerger",
    test_source: "sample content",
    category: :other,
  )
end
```

Supported categories are `:markdown`, `:data`, `:code`, `:config`, and `:other`.

### Registering known gems explicitly

Suites that need deterministic registration order should first predeclare the tag metadata, then activate the tags they need:

```ruby
Ast::Merge::RSpec::MergeGemRegistry.register_known_gem(
  :prism_merge,
  require_path: "prism/merge",
  merger_class: "Prism::Merge::SmartMerger",
  test_source: "def foo; end",
  category: :code,
)

Ast::Merge::RSpec::MergeGemRegistry.register_known_gems(
  :prism_merge,
)
```

## Shared examples

The combined shared-examples loader exposes these examples:

- `"Ast::Merge::Comment::Attachment"`
- `"Ast::Merge::Comment::Augmenter"`
- `"Ast::Merge::Comment::Region"`
- `"Ast::Merge::ConflictResolverBase"`
- `"Ast::Merge::DebugLogger"`
- `"Ast::Merge::FileAnalyzable"`
- `"Ast::Merge::FreezeNodeBase"`
- `"Ast::Merge::MergeResultBase"`
- `"Ast::Merge::MergerConfig"`
- `"Ast::Merge::Recipe::PresetContract"`
- `"Ast::Merge::RemovalModeCompliance"`
- `"a reproducible merge"`
- `"a reproducible partial merge"`

Load them all:

```ruby
require "ast/merge/rspec/shared_examples"
```

Or load a single file if you only need one example.

### Reproducible merge fixtures

`"a reproducible merge"` expects fixture-driven scenarios and verifies both expected output and idempotency.

Typical setup:

```ruby
RSpec.describe(My::Merge::SmartMerger) do
  it_behaves_like "a reproducible merge" do
    let(:fixtures_path) { File.expand_path("../fixtures/merge_cases", __dir__) }
    let(:merger_class) { described_class }
    let(:file_extension) { ".myfmt" }
  end
end
```

### Recipe preset contract

`"Ast::Merge::Recipe::PresetContract"` verifies the shared recipe-preset surface:

- `Ast::Merge::Recipe::Preset.load`
- `Preset#to_h`
- companion-script resolution through `Ast::Merge::Recipe::ScriptLoader`

Typical setup:

```ruby
RSpec.describe("my recipe preset") do
  it_behaves_like "Ast::Merge::Recipe::PresetContract" do
    let(:preset_config) do
      {
        "name" => "my_recipe",
        "parser" => "psych",
        "merge" => {
          "preference" => "destination",
          "signature_generator" => "signature_generator.rb",
        },
      }
    end

    let(:preset_script_files) do
      {
        "signature_generator.rb" => "->(node) { [:sig, node] }\n",
      }
    end

    let(:verify_loaded_preset) do
      lambda do |preset|
        expect(preset.signature_generator.call("node")).to(eq([:sig, "node"]))
      end
    end
  end
end
```

### Reproducible partial merges

`"a reproducible partial merge"` verifies parser-family partial mergers produce the expected merged content and remain idempotent.

Typical setup:

```ruby
RSpec.describe(Markdown::Merge::PartialTemplateMerger, :markly_merge) do
  it_behaves_like "a reproducible partial merge" do
    let(:partial_merger_class) { described_class }
    let(:template_content) { "New section\n" }
    let(:destination_content) { "# Intro\n\n## Target\nOld section\n" }
    let(:partial_merge_options) do
      {
        anchor: {type: :heading, text: /Target/},
        backend: :markly,
      }
    end
    let(:expected_merged_content) { "# Intro\n\n## Target\nNew section\n" }
  end
end
```

## What belongs here

Use this namespace for test support shared across the merge-gem family:

- dependency-tag setup
- merge-gem availability checks
- shared examples for common contracts

Format-specific parser fixtures and merge behavior specs belong in the corresponding `*-merge` gem.

## Provider snapshots

`Ast::Merge::RSpec::ProviderSnapshot` captures the versioned parse and analysis
projections used by the cross-runtime fixture repository. Parsing always enters
through an explicitly selected TreeHaver backend. The capture harness only
reads the normalized TreeHaver node contract; a provider suite supplies a
callback for parser-native evidence:

```ruby
snapshot = Ast::Merge::RSpec::ProviderSnapshot.new(
  snapshot_id: "snapshot.prism.ruby",
  provider: Prism::Merge.merge_provider,
  source: source,
  language: :ruby,
  dialect: :ruby,
  backend_id: :prism,
  parser_contract: :prism,
  backend_identity: {
    id: :prism,
    family: :native,
    host_runtime: :ruby,
    package: :prism,
    parser: :Prism,
    capabilities: %i[comments directives exact_source_spans normalized_tree],
  },
  extension_builder: lambda do |tree:, **|
    {
      schema: "structuredmerge.extension/ruby-prism/v1",
      namespace: "ruby-prism",
      capabilities: %w[magic-comments],
      payload: {magic_comments: tree.magic_comments.map(&:to_s)},
    }
  end,
)

artifacts = snapshot.capture
```

The extension callback is intentionally provider-owned. The common harness
does not reflect over native parser objects or flatten their capabilities.
`#differential_replay` serializes a provider request through canonical JSON,
replays it, and reports whether the provider result and output bytes remain
identical.
