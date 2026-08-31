<a href="https://github.com/structuredmerge"><img alt="structuredmerge Logo by GitHub" src="https://github.com/structuredmerge.png?size=192" width="14%" align="right"/></a>

# ☯️ Ast::Merge

[![Version][👽versioni]][👽version] [![Ruby Users Forum][✉️ruby-forum-top-img]][✉️ruby-forum] [![GitHub tag (latest SemVer)][⛳️tag-img]][⛳️tag] [![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0][📄license-img]][📄license] [![Total downloads][👽dl-ranki]][👽dl-rank] [![CI Current][🚎11-c-wfi]][🚎11-c-wf]

`if ci_badges.map(&:color).detect { it != "green"}` ☝️ [let me know on Discord][✉️discord-invite] or [RubyForum][✉️ruby-forum], as I may have missed the notification.

---

`if ci_badges.map(&:color).all? { it == "green"}` 👇️ send money so I can do more of this. FLOSS maintenance is now my full-time job.

[![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]

<details markdown="1">
 <summary>👣 How will this project approach the September 2025 hostile takeover of RubyGems? 🚑️</summary>

I've summarized my thoughts in [this blog post](https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo).

</details>

## 🌻 Synopsis <a href="https://discord.gg/3qme4XHNKN"><img alt="Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/avatar-128px.svg" width="8%" align="right"/></a> <a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="8%" align="right"/></a>

Ast::Merge is **not typically used directly** - instead, use one of the format-specific gems built on top of it.

### Architecture: tree\_haver + ast-merge

The `*-merge` gem family is built on a two-layer architecture:

#### Layer 1: tree\_haver (Parsing Foundation)

[tree\_haver][tree_haver] provides cross-Ruby parsing capabilities:

- **Universal Backend Support**: Automatically selects the best parsing backend for your Ruby implementation (MRI, JRuby, TruffleRuby)
- **Backend Registry**: Tracks tree-sitter adapters (`mri`, `rust`, `ffi`, `java`, `tslp`, `kreuzberg-language-pack`), native parsers (`prism`, `psych`, `commonmarker`, `markly`, `rbs`), PEG parsers (`citrus`, `parslet`), and binary schema support (`kaitai-struct`)
- **Unified API**: Write parsing code once, run on any Ruby implementation
- **Grammar Discovery**: Built-in `GrammarFinder` for platform-aware grammar library discovery
- **Thread-Safe**: Language registry with thread-safe caching

#### Layer 2: ast-merge (Merge Infrastructure)

Ast::Merge builds on tree\_haver to provide:

- **Base Classes**: `FreezeNode`, `MergeResult` base classes with unified constructors
- **Shared Modules**: `FileAnalysisBase`, `FileAnalyzable`, `MergerConfig`, `DebugLogger`
- **Freeze Block Support**: Configurable marker patterns for multiple comment syntaxes (preserve sections during merge)
- **Node Typing System**: `NodeTyping` for canonical node type identification across different parsers
- **Conflict Resolution**: `ConflictResolverBase` with pluggable strategies
- **Error Classes**: `ParseError`, `TemplateParseError`, `DestinationParseError`
- **Region Detection**: `RegionDetectorBase`, `FencedCodeBlockDetector` for text-based analysis
- **RSpec Shared Examples**: Test helpers for implementing new merge gems

### Merge Gem Backend and Behavior Patterns

Every merge gem in this family must enter parsing through `tree_haver`. Do not add direct parser fallbacks in merge gems. If a requested backend or grammar is unavailable, fail closed with an unsupported feature or parse diagnostic instead of switching to another parser outside `tree_haver`.

Merge gems also form language or format families. Each family has a substrate
gem that owns shared merge behavior for that language or format. Provider gems
register alternate AST backends and delegate family-specific behavior back to the
substrate. This keeps parser differences behind TreeHaver while preserving one
place for the merge semantics that make a format peculiar.

These are two separate axes:

- **Behavior role** answers where shared merge semantics live. A substrate gem
  owns common behavior for a language or format family. A provider gem exposes a
  backend and delegates family behavior to the substrate when one exists.
- **Backend role** answers how parsing is registered. A gem may register a
  TSLP/tree-sitter grammar, a native/provider backend, both, or no parser at all
  for byte or line oriented merge behavior.

Current examples:

- **Substrate with TSLP/tree-sitter registration**: `markdown-merge`,
  `yaml-merge`, `ruby-merge`, and `toml-merge` register tree-sitter grammar
  paths and host shared family behavior. `json-merge`, `bash-merge`,
  `go-merge`, `html-merge`, `rust-merge`, and `typescript-merge` currently use
  the same TSLP-backed shape for formats without alternate provider gems.
- **Provider backed by a native or Ruby parser**: `commonmarker-merge`,
  `kramdown-merge`, and `markly-merge` provide Markdown backends and share
  behavior with `markdown-merge`; `psych-merge` provides a YAML backend and
  should share behavior with `yaml-merge`; `prism-merge` provides a Ruby backend
  and shares behavior with `ruby-merge`; `citrus-toml-merge` and
  `parslet-toml-merge` provide TOML backends and share behavior with
  `toml-merge`.
- **Dual-backend single gem**: `rbs-merge` registers the official RBS parser
  backend and the tree-sitter RBS grammar in one gem because both surfaces are
  intentional and tested there.
- **Kaitai/binary family**: `binary-merge` is the shared substrate for
  schema-aware binary merge behavior: byte ranges, preservation reports, unsafe
  diagnostics, render policies, and nested dispatch conventions. Concrete
  parser gems such as `zip-merge` depend on that substrate, register their
  schema parser path, and produce normalized TreeHaver binary report nodes.
- **Synthetic line AST merge gems**: `plain-merge` registers `:text` and
  `:plain` line-backed parser paths for normalized block analysis, and
  `dotenv-merge` registers `:dotenv` and `:env` parser paths that build dotenv
  ownership on the plain line substrate.
- **Thin substrates are still substrates**: `binary-merge` is intentionally thin
  while ZIP is the only Kaitai-backed family member. Shared binary behavior
  should move there as additional binary schema gems prove common patterns.

Backend fallback inside `tree_haver` is allowed when it is explicit TreeHaver backend selection. Backend fallback outside `tree_haver` is not allowed, because it bypasses owner identity, backend diagnostics, parser capability reporting, and shared merge-stack behavior.

Partial document insertion, replacement, and removal belong in `ast-crispr`.
`PartialTemplateMerger` classes should be adapters over structural owners and
source-preserving edit plans, not native object round-trips. A YAML partial merge
must not parse to Ruby Hashes and emit with `Psych.dump`; a Markdown partial
merge must not slice headings with regular expressions; and a tree-sitter-backed
merge must not call the grammar library directly outside TreeHaver.

### Creating a New Merge Gem

Pick the merge-gem shape before writing parser code:

- Use a substrate gem when the format needs shared behavior across one or more
  backends. Register the TSLP/tree-sitter grammar there when that backend is
  supported, parse through `TreeHaver.parser_for`, and keep shared merge
  behavior in the substrate.
- Use a provider gem when the gem exists to expose one concrete parser backend. Register that backend with `TreeHaver.register_language`, then delegate shared language or format behavior back to the substrate gem.
- Use a dual-backend gem only when both the native provider and TSLP/tree-sitter path are intentional, tested TreeHaver backends in that same gem.

Merge gems should not call parser libraries directly during merge analysis. Direct parser calls belong inside TreeHaver backend adapters.

```ruby
require "tree_haver"
require "ast/merge"

module MyFormat
  module Merge
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(
      id: "kreuzberg-language-pack",
      family: "tree-sitter"
    ).freeze

    def self.register_backend!
      TreeHaver::GrammarFinder.new(:my_format).register!
    end

    # Inherit from base classes and pass **options for forward compatibility

    class SmartMerger < Ast::Merge::SmartMergerBase
      DEFAULT_FREEZE_TOKEN = "myformat-merge"

      def initialize(template, dest, my_custom_option: nil, **options)
        @my_custom_option = my_custom_option
        super(template, dest, **options)
      end

      protected

      def analysis_class
        FileAnalysis
      end

      def default_freeze_token
        DEFAULT_FREEZE_TOKEN
      end

      def perform_merge
        # Implement format-specific merge logic
        # Returns a MergeResult
      end
    end

    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      def initialize(source, freeze_token: nil, signature_generator: nil, **options)
        @source = source
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        Merge.register_backend!
        @tree = TreeHaver.parser_for(:my_format).parse(source)
        # Project TreeHaver nodes into merge ownership records.
      end

      def compute_node_signature(node)
        # Return signature array for node matching
      end
    end

    class ConflictResolver < Ast::Merge::ConflictResolverBase
      def initialize(template_analysis, dest_analysis, preference: :destination,
        add_template_only_nodes: false, match_refiner: nil, **options)
        super(
          strategy: :batch,  # or :node, :boundary
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          match_refiner: match_refiner,
          **options
        )
      end

      protected

      def resolve_batch(result)
        # Implement batch resolution logic
      end
    end

    class MergeResult < Ast::Merge::MergeResultBase
      def initialize(**options)
        super(**options)
        @statistics = {merged_count: 0}
      end

      def to_my_format
        to_s
      end
    end

    class MatchRefiner < Ast::Merge::MatchRefinerBase
      def initialize(threshold: 0.7, node_types: nil, **options)
        super(threshold: threshold, node_types: node_types, **options)
      end

      def similarity(template_node, dest_node)
        # Return similarity score between 0.0 and 1.0
      end
    end
  end
end
```

### Base Classes Reference

| Base Class             | Purpose                     | Key Methods to Implement               |
|------------------------|-----------------------------|----------------------------------------|
| `SmartMergerBase`      | Main merge orchestration    | `analysis_class`, `perform_merge`      |
| `ConflictResolverBase` | Resolve node conflicts      | `resolve_batch` or `resolve_node_pair` |
| `MergeResultBase`      | Track merge results         | `to_s`, format-specific output         |
| `MatchRefinerBase`     | Fuzzy node matching         | `similarity`                           |
| `ContentMatchRefiner`  | Text content fuzzy matching | Ready to use                           |
| `FileAnalyzable`       | File parsing/analysis       | `compute_node_signature`               |

### ContentMatchRefiner

`Ast::Merge::ContentMatchRefiner` is a built-in match refiner for fuzzy text content matching using Levenshtein distance. Unlike signature-based matching which requires exact content hashes, this refiner allows matching nodes with similar (but not identical) content.

```ruby
# Basic usage - match nodes with 70% similarity
refiner = Ast::Merge::ContentMatchRefiner.new(threshold: 0.7)

# Only match specific node types
refiner = Ast::Merge::ContentMatchRefiner.new(
  threshold: 0.6,
  node_types: [:paragraph, :heading],
)

# Custom weights for scoring
refiner = Ast::Merge::ContentMatchRefiner.new(
  threshold: 0.7,
  weights: {
    content: 0.8,   # Levenshtein similarity (default: 0.7)
    length: 0.1,    # Length similarity (default: 0.15)
    position: 0.1,   # Position in document (default: 0.15)
  },
)

# Custom content extraction
refiner = Ast::Merge::ContentMatchRefiner.new(
  threshold: 0.7,
  content_extractor: ->(node) { node.text_content.downcase.strip },
)

# Use with a merger
merger = MyFormat::SmartMerger.new(
  template,
  destination,
  preference: :template,
  match_refiner: refiner,
)
```

This is particularly useful for:

- Paragraphs with minor edits (typos, rewording)
- Headings with slight changes
- Comments with updated text
- Any text-based node that may have been slightly modified

### JaccardSimilarity

`Ast::Merge::JaccardSimilarity` provides set-based fuzzy matching of text blocks using Jaccard index with bigram and token overlap metrics. This is the foundation for detecting renamed or refactored nodes that share similar content.

```ruby
# Calculate similarity between two text strings
Ast::Merge::JaccardSimilarity.jaccard("def process_users(data)", "def handle_users(data)")
# => 0.75 (high overlap due to shared tokens)

# Extract tokens from text for comparison
tokens = Ast::Merge::JaccardSimilarity.extract_tokens("data.each { |u| validate(u) }")
# => ["data", "each", "validate"]
```

### TokenMatchRefiner

`Ast::Merge::TokenMatchRefiner` extends `MatchRefinerBase` for Jaccard-based fuzzy refinement of unmatched node pairs during alignment. It uses greedy best-first matching to pair orphan nodes that have similar body text.

```ruby
refiner = Ast::Merge::TokenMatchRefiner.new(
  threshold: 0.6,                  # Minimum Jaccard similarity (default: 0.6)
  node_types: [:def, :class],       # Only match these node types
)

merger = MyFormat::SmartMerger.new(
  template,
  destination,
  match_refiner: refiner,
)
```

### CompositeMatchRefiner

`Ast::Merge::CompositeMatchRefiner` chains multiple refiners sequentially, enabling multi-strategy matching in a single alignment pass. Each refiner operates on the residual unmatched nodes from the previous refiner.

```ruby
composite = Ast::Merge::CompositeMatchRefiner.new(refiners: [
  Ast::Merge::ContentMatchRefiner.new(threshold: 0.8),  # strict text match first
  Ast::Merge::TokenMatchRefiner.new(threshold: 0.5),    # then looser token match
])

merger = MyFormat::SmartMerger.new(
  template,
  destination,
  match_refiner: composite,
)
```

### Namespace Reference

The `Ast::Merge` module is organized into several namespaces, each with detailed documentation:

| Namespace              | Purpose                            | Documentation                                                        |
|------------------------|------------------------------------|----------------------------------------------------------------------|
| `Ast::Merge::Detector` | Region detection and merging       | [lib/ast/merge/detector/README.md](lib/ast/merge/detector/README.md) |
| `Ast::Merge::Recipe`   | YAML-based merge recipes           | [lib/ast/merge/recipe/README.md](lib/ast/merge/recipe/README.md)     |
| `Ast::Merge::Comment`  | Comment parsing and representation | [lib/ast/merge/comment/README.md](lib/ast/merge/comment/README.md)   |
| `Ast::Merge::Text`     | Plain text AST parsing             | [lib/ast/merge/text/README.md](lib/ast/merge/text/README.md)         |
| `Ast::Merge::RSpec`    | Shared RSpec examples              | [lib/ast/merge/rspec/README.md](lib/ast/merge/rspec/README.md)       |

**Key Classes by Namespace:**

- **Detector**: `Region`, `Base`, `Mergeable`, `FencedCodeBlock`, `YamlFrontmatter`, `TomlFrontmatter`
- **Recipe**: `Config`, `Runner`, `ScriptLoader`
- **Comment**: `Line`, `Block`, `Empty`, `Parser`, `Style`
- **Text**: `SmartMerger`, `FileAnalysis`, `LineNode`, `WordNode`, `Section`
- **RSpec**: Shared examples and dependency tags for testing `*-merge` implementations

[tree_haver]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver

## 💡 Info you can shake a stick at

| Tokens to Remember | [![Gem name][⛳️name-img]][⛳️gem-name] [![Gem namespace][⛳️namespace-img]][⛳️gem-namespace] |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Works with MRI Ruby 4 | [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf]|
| Support & Community | [![Join Me on Daily.dev's RubyFriends][✉️ruby-friends-img]][✉️ruby-friends] [![Get help from RubyForum][✉️ruby-forum-img]][✉️ruby-forum] [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite] [![Get help from me on Upwork][👨🏼‍🏫expsup-upwork-img]][👨🏼‍🏫expsup-upwork] [![Get help from me on Codementor][👨🏼‍🏫expsup-codementor-img]][👨🏼‍🏫expsup-codementor] |
| Source | [![Source on GitLab.com][📜src-gl-img]][📜src-gl] [![Source on CodeBerg.org][📜src-cb-img]][📜src-cb] [![Source on GitHub.com][📜src-gh-img]][📜src-gh] [![The best SHA: dQw4w9WgXcQ!][🧮kloc-img]][🧮kloc] |
| Documentation | [![Current release on RubyDoc.info][📜docs-cr-rd-img]][🚎yard-current] [![YARD on Galtzo.com][📜docs-head-rd-img]][🚎yard-head] [![Maintainer Blog][🚂maint-blog-img]][🚂maint-blog] [![GitLab Wiki][📜gl-wiki-img]][📜gl-wiki] [![GitHub Wiki][📜gh-wiki-img]][📜gh-wiki] |
| Compliance | [![License: AGPL-3.0-only OR PolyForm-Small-Business-1.0.0][📄license-img]][📄license] [![Apache license compatibility: Category X][📄license-compat-img]][📄license-compat] [![📄ilo-declaration-img]][📄ilo-declaration] [![Security Policy][🔐security-img]][🔐security] [![Contributor Covenant 2.1][🪇conduct-img]][🪇conduct] [![SemVer 2.0.0][📌semver-img]][📌semver] |
| Style | [![Enforced Code Style Linter][💎rlts-img]][💎rlts] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog] [![Gitmoji Commits][📌gitmoji-img]][📌gitmoji] [![Compatibility appraised by: appraisal2][💎appraisal2-img]][💎appraisal2] |
| Maintainer 🎖️ | [![Follow Me on LinkedIn][💖🖇linkedin-img]][💖🖇linkedin] [![Follow Me on Ruby.Social][💖🐘ruby-mast-img]][💖🐘ruby-mast] [![Follow Me on Bluesky][💖🦋bluesky-img]][💖🦋bluesky] [![Contact Maintainer][🚂maint-contact-img]][🚂maint-contact] [![My technical writing][💖💁🏼‍♂️devto-img]][💖💁🏼‍♂️devto] |
| `...` 💖 | [![Find Me on WellFound:][💖✌️wellfound-img]][💖✌️wellfound] [![Find Me on CrunchBase][💖💲crunchbase-img]][💖💲crunchbase] [![My LinkTree][💖🌳linktree-img]][💖🌳linktree] [![More About Me][💖💁🏼‍♂️aboutme-img]][💖💁🏼‍♂️aboutme] [🧊][💖🧊berg] [🐙][💖🐙hub] [🛖][💖🛖hut] [🧪][💖🧪lab] |

### Compatibility

Compatible with MRI Ruby 4.0.0+, JRuby, and TruffleRuby.
CI workflows and Appraisals are generated for MRI Ruby 4.0.0+.
This test floor is configured by `ruby.test_minimum` in `.kettle-jem.yml` and
may be higher than the gem's runtime compatibility floor when legacy Rubies are
not practical for the current toolchain.

<a href="https://github.com/kettle-dev"><img alt="kettle-dev Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/kettle-dev/avatar-128px.svg" width="14%" align="right"/></a>

The _amazing_ test matrix is powered by the kettle-dev stack.

<details markdown="1">
<summary>How kettle-dev manages complexity in tests</summary>

| Gem | Source | Role | Total downloads |
|-----|--------|------|---------------------|
| [appraisal2](https://clickgems.clickhouse.com/dashboard/appraisal2) | [GitHub](https://github.com/appraisal-rb/appraisal2) | multi-dependency Appraisal matrix generation | [![Total downloads for appraisal2](https://img.shields.io/gem/dt/appraisal2.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/appraisal2) |
| [appraisal2-rubocop](https://clickgems.clickhouse.com/dashboard/appraisal2-rubocop) | [GitHub](https://github.com/appraisal-rb/appraisal2-rubocop) | RuboCop Appraisal generator integration | [![Total downloads for appraisal2-rubocop](https://img.shields.io/gem/dt/appraisal2-rubocop.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/appraisal2-rubocop) |
| [kettle-dev](https://clickgems.clickhouse.com/dashboard/kettle-dev) | [GitHub](https://github.com/kettle-dev/kettle-dev) | development, release, and CI workflow tooling | [![Total downloads for kettle-dev](https://img.shields.io/gem/dt/kettle-dev.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/kettle-dev) |
| [kettle-jem](https://clickgems.clickhouse.com/dashboard/kettle-jem) | [GitHub](https://github.com/kettle-dev/kettle-jem) | Appraisals & CI workflow templates | [![Total downloads for kettle-jem](https://img.shields.io/gem/dt/kettle-jem.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/kettle-jem) |
| [kettle-soup-cover](https://clickgems.clickhouse.com/dashboard/kettle-soup-cover) | [GitHub](https://github.com/kettle-dev/kettle-soup-cover) | SimpleCov coverage policy and reporting | [![Total downloads for kettle-soup-cover](https://img.shields.io/gem/dt/kettle-soup-cover.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/kettle-soup-cover) |
| [kettle-test](https://clickgems.clickhouse.com/dashboard/kettle-test) | [GitHub](https://github.com/kettle-dev/kettle-test) | standard test runner and coverage harness | [![Total downloads for kettle-test](https://img.shields.io/gem/dt/kettle-test.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/kettle-test) |
| [rubocop-lts](https://clickgems.clickhouse.com/dashboard/rubocop-lts) | [GitHub](https://github.com/rubocop-lts/rubocop-lts) | Ruby-version-aware linting | [![Total downloads for rubocop-lts](https://img.shields.io/gem/dt/rubocop-lts.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/rubocop-lts) |
| [turbo_tests2](https://clickgems.clickhouse.com/dashboard/turbo_tests2) | [GitHub](https://github.com/galtzo-floss/turbo_tests2) | parallel test execution | [![Total downloads for turbo_tests2](https://img.shields.io/gem/dt/turbo_tests2.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/turbo_tests2) |

</details>

## ✨ Installation

Install the gem and add to the application's Gemfile by executing:

```console
bundle add ast-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install ast-merge
```

## ⚙️ Configuration

`ast-merge` provides base classes and shared interfaces for building format-specific merge tools.
Each implementation (like `prism-merge`, `psych-merge`, etc.) has its own SmartMerger with format-specific configuration.

### Common Configuration Options

All SmartMerger implementations share these configuration options:

```ruby
merger = SomeFormat::Merge::SmartMerger.new(
  template,
  destination,
  # When conflicts occur, prefer template or destination values
  preference: :template,            # or :destination (default), or a Hash for per-node-type
  # Add nodes that only exist in template (Boolean or callable filter)
  add_template_only_nodes: true,    # default: false, or ->(node, entry) { ... }
  # Custom node type handling
  node_typing: {},                # optional, for per-node-type preference
)
```

### Signature Match Preference

Control which source wins when both files have the same structural element:

- **`:template`** - Template values replace destination values
- **`:destination`** (default) - Destination values are preserved
- **Hash** - Per-node-type preference (see Advanced Configuration)

### Template-Only Nodes

Control whether to add nodes that only exist in the template:

- **`true`** - Add all template-only nodes
- **`false`** (default) - Skip template-only nodes
- **Callable** - Filter which template-only nodes to add

#### Callable Filter

When you need fine-grained control over which template-only nodes are added, pass a callable (Proc/Lambda) that receives `(node, entry)` and returns truthy to add or falsey to skip:

```ruby
# Only add nodes with gem_family signatures
merger = SomeFormat::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: ->(node, entry) {
    sig = entry[:signature]
    sig.is_a?(Array) && sig.first == :gem_family
  },
)

# Only add link definitions that match a pattern
merger = Markly::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: ->(node, entry) {
    entry[:template_node].type == :link_definition &&
      entry[:signature]&.last&.include?("gem")
  },
)
```

The `entry` hash contains:

- `:template_node` - The node being considered for addition
- `:signature` - The node's signature (Array or other value)
- `:template_index` - Index in the template statements
- `:dest_index` - Always `nil` for template-only nodes

## 🔧 Basic Usage

### Using Shared Examples in Tests

```ruby
# spec/spec_helper.rb
require "ast/merge/rspec/shared_examples"

# spec/my_format/merge/freeze_node_spec.rb
RSpec.describe(MyFormat::Merge::FreezeNode) do
  it_behaves_like "Ast::Merge::FreezeNode" do
    let(:freeze_node_class) { described_class }
    let(:default_pattern_type) { :hash_comment }
    let(:build_freeze_node) do
      lambda { |start_line:, end_line:, **opts|
        # Build a freeze node for your format
      }
    end
  end
end
```

### Available Shared Examples

- `"Ast::Merge::FreezeNode"` - Tests for FreezeNode implementations
- `"Ast::Merge::MergeResult"` - Tests for MergeResult implementations
- `"Ast::Merge::DebugLogger"` - Tests for DebugLogger implementations
- `"Ast::Merge::FileAnalysisBase"` - Tests for FileAnalysis implementations
- `"Ast::Merge::MergerConfig"` - Tests for SmartMerger implementations

## 🔐 Security

See [SECURITY.md][🔐security].

## 🤝 Contributing

If you need some ideas of where to help, you could work on adding more code coverage,
check [issues][🤝gh-issues] or [PRs][🤝gh-pulls], or use the gem and think about how it could be better.

We [![Keep A Changelog][📗keep-changelog-img]][📗keep-changelog] so if you make changes, remember to update it.

See [CONTRIBUTING.md][🤝contributing] for more detailed instructions.

## 📌 Versioning

This library follows [![Semantic Versioning 2.0.0][📌semver-img]][📌semver] for its public API where practical.
For most applications, prefer the [Pessimistic Version Constraint][📌pvc] with two digits of precision.

For example:

```ruby
spec.add_dependency("ast-merge", "~> 7.0")
```

<details markdown="1">
<summary>📌 Is "Platform Support" part of the public API? More details inside.</summary>

Dropping support for a platform can be a breaking change for affected users.
If a release changes supported platforms, it should be called out clearly in the changelog and versioned with that impact in mind.

To get a better understanding of how SemVer is intended to work over a project's lifetime,
read this article from the creator of SemVer:

- ["Major Version Numbers are Not Sacred"][📌major-versions-not-sacred]

</details>

See [CHANGELOG.md][📌changelog] for a list of releases.

## 📄 License

The gem is available under the following licenses: [AGPL-3.0-only](https://github.com/structuredmerge/structuredmerge-ruby/blob/main/AGPL-3.0-only.md), [PolyForm-Small-Business-1.0.0](https://github.com/structuredmerge/structuredmerge-ruby/blob/main/PolyForm-Small-Business-1.0.0.md).
See [LICENSE.md][📄license] for details.

If none of the available licenses suit your use case, please [contact us](mailto:floss@galtzo.com) to discuss a custom commercial license.

[⛳liberapay-img]: https://img.shields.io/liberapay/goal/pboling.svg?logo=liberapay&color=a51611&style=flat
[⛳liberapay-bottom-img]: https://img.shields.io/liberapay/goal/pboling.svg?style=for-the-badge&logo=liberapay&color=a51611
[⛳liberapay]: https://liberapay.com/pboling/donate
[🖇sponsor-img]: https://img.shields.io/badge/Sponsor_Me!-pboling.svg?style=social&logo=github
[🖇sponsor-bottom-img]: https://img.shields.io/badge/Sponsor_Me!-pboling-blue?style=for-the-badge&logo=github
[🖇sponsor]: https://github.com/sponsors/pboling
[🖇kofi-img]: https://img.shields.io/badge/ko--fi-%E2%9C%93-a51611.svg?style=flat
[🖇kofi]: https://ko-fi.com/pboling
[🖇buyme-small-img]: https://img.shields.io/badge/buy_me_a_coffee-%E2%9C%93-a51611.svg?style=flat
[🖇buyme-img]: https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20latte&emoji=&slug=pboling&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff
[🖇buyme]: https://www.buymeacoffee.com/pboling
[🖇paypal-img]: https://img.shields.io/badge/donate-paypal-a51611.svg?style=flat&logo=paypal
[🖇paypal-bottom-img]: https://img.shields.io/badge/donate-paypal-a51611.svg?style=for-the-badge&logo=paypal&color=0A0A0A
[🖇paypal]: https://www.paypal.com/paypalme/peterboling
[🖇floss-funding.dev]: https://floss-funding.dev
[🖇floss-funding-gem]: https://github.com/galtzo-floss/floss_funding
[✉️discord-invite]: https://discord.gg/3qme4XHNKN
[✉️discord-invite-img-ftb]: https://img.shields.io/discord/1373797679469170758?style=for-the-badge&logo=discord
[✉️ruby-friends-img]: https://img.shields.io/badge/daily.dev-%F0%9F%92%8E_Ruby_Friends-0A0A0A?style=for-the-badge&logo=dailydotdev&logoColor=white
[✉️ruby-friends]: https://app.daily.dev/squads/rubyfriends
[✉️ruby-forum-top-img]: https://img.shields.io/discourse/topics?server=https%3A%2F%2Fwww.rubyforum.org&style=flat&logo=discourse&label=Ruby%20Users%20Forum
[✉️ruby-forum-img]: https://img.shields.io/discourse/topics?server=https%3A%2F%2Fwww.rubyforum.org&style=for-the-badge&logo=discourse&label=Ruby%20Users%20Forum
[✉️ruby-forum]: https://www.rubyforum.org/tag/ast-merge
[✇bundle-group-pattern]: https://gist.github.com/pboling/4564780
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Ast::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://clickgems.clickhouse.com/dashboard/ast-merge
[⛳️name-img]: https://img.shields.io/badge/name-ast--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/ast-merge
[🚂maint-blog-img]: https://img.shields.io/badge/blog-railsbling-0093D0.svg?style=for-the-badge&logo=rubyonrails&logoColor=orange
[🚂maint-contact]: http://www.railsbling.com/contact
[🚂maint-contact-img]: https://img.shields.io/badge/Contact-Maintainer-0093D0.svg?style=flat&logo=rubyonrails&logoColor=red
[💖🖇linkedin]: http://www.linkedin.com/in/peterboling
[💖🖇linkedin-img]: https://img.shields.io/badge/LinkedIn-Profile-0B66C2?style=flat&logo=newjapanprowrestling
[💖✌️wellfound]: https://wellfound.com/u/peter-boling
[💖✌️wellfound-img]: https://img.shields.io/badge/peter--boling-orange?style=flat&logo=wellfound
[💖💲crunchbase]: https://www.crunchbase.com/person/peter-boling
[💖💲crunchbase-img]: https://img.shields.io/badge/peter--boling-purple?style=flat&logo=crunchbase
[💖🐘ruby-mast]: https://ruby.social/@galtzo
[💖🐘ruby-mast-img]: https://img.shields.io/mastodon/follow/109447111526622197?domain=https://ruby.social&style=flat&logo=mastodon&label=Ruby%20@galtzo
[💖🦋bluesky]: https://bsky.app/profile/galtzo.com
[💖🦋bluesky-img]: https://img.shields.io/badge/@galtzo.com-0285FF?style=flat&logo=bluesky&logoColor=white
[💖🌳linktree]: https://linktr.ee/galtzo
[💖🌳linktree-img]: https://img.shields.io/badge/galtzo-purple?style=flat&logo=linktree
[💖💁🏼‍♂️devto]: https://dev.to/galtzo
[💖💁🏼‍♂️devto-img]: https://img.shields.io/badge/dev.to-0A0A0A?style=flat&logo=devdotto&logoColor=white
[💖💁🏼‍♂️aboutme]: https://about.me/peter.boling
[💖💁🏼‍♂️aboutme-img]: https://img.shields.io/badge/about.me-0A0A0A?style=flat&logo=aboutme&logoColor=white
[💖🧊berg]: https://codeberg.org/pboling
[💖🐙hub]: https://github.org/pboling
[💖🛖hut]: https://sr.ht/~galtzo/
[💖🧪lab]: https://gitlab.com/pboling
[👨🏼‍🏫expsup-upwork]: https://www.upwork.com/freelancers/~014942e9b056abdf86?mp_source=share
[👨🏼‍🏫expsup-upwork-img]: https://img.shields.io/badge/UpWork-13544E?style=for-the-badge&logo=Upwork&logoColor=white
[👨🏼‍🏫expsup-codementor]: https://www.codementor.io/peterboling?utm_source=github&utm_medium=button&utm_term=peterboling&utm_campaign=github
[👨🏼‍🏫expsup-codementor-img]: https://img.shields.io/badge/CodeMentor-Get_Help-1abc9c?style=for-the-badge&logo=CodeMentor&logoColor=white
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-ast-merge?utm_source=rubygems-ast-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/ast-merge
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/ast-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=GitHub&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://clickgems.clickhouse.com/dashboard/ast-merge
[👽dl-ranki]: https://img.shields.io/gem/dt/ast-merge.svg
[👽version]: https://clickgems.clickhouse.com/dashboard/ast-merge
[👽versioni]: https://img.shields.io/gem/v/ast-merge.svg
[🚎11-c-wf]: https://github.com/structuredmerge/structuredmerge-ruby/actions/workflows/current.yml
[🚎11-c-wfi]: https://github.com/structuredmerge/structuredmerge-ruby/actions/workflows/current.yml/badge.svg
[💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-CC342D?style=for-the-badge&logo=ruby&logoColor=green
[🤝gh-issues]: https://github.com/structuredmerge/structuredmerge-ruby/issues
[🤝gh-pulls]: https://github.com/structuredmerge/structuredmerge-ruby/pulls
[🤝gl-issues]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/issues
[🤝gl-pulls]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/merge_requests
[🤝cb-issues]: https://codeberg.org/structuredmerge/structuredmerge-ruby/issues
[🤝cb-pulls]: https://codeberg.org/structuredmerge/structuredmerge-ruby/pulls
[🤝cb-donate]: https://donate.codeberg.org/
[🤝contributing]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CONTRIBUTING.md
[🖐contrib-rocks]: https://contrib.rocks
[🖐contributors]: https://github.com/structuredmerge/structuredmerge-ruby/graphs/contributors
[🖐contributors-img]: https://contrib.rocks/image?repo=structuredmerge/structuredmerge-ruby
[🪇conduct]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CODE_OF_CONDUCT.md
[🪇conduct-img]: https://img.shields.io/badge/Contributor_Covenant-2.1-259D6C.svg
[📌pvc]: http://guides.rubygems.org/patterns/#pessimistic-version-constraint
[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-259D6C.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📌changelog]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CHANGELOG.md
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-34495e.svg?style=flat
[📌gitmoji]: https://gitmoji.dev
[📌gitmoji-img]: https://img.shields.io/badge/gitmoji_commits-%20%F0%9F%98%9C%20%F0%9F%98%8D-34495e.svg?style=flat-square
[🧮kloc]: https://www.youtube.com/watch?v=dQw4w9WgXcQ
[🧮kloc-img]: https://img.shields.io/badge/KLOC-0.000-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
[🔐security]: https://github.com/structuredmerge/structuredmerge-ruby/blob/main/SECURITY.md
[🔐security-img]: https://img.shields.io/badge/security-policy-259D6C.svg?style=flat
[📄copyright-notice-explainer]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year
[📄license]: LICENSE.md
[📄license-ref]: LICENSE.md
[📄license-img]: https://img.shields.io/badge/License-AGPL--3.0--only_OR_PolyForm--Small--Business--1.0.0-259D6C.svg
[📄license-compat]: https://www.apache.org/legal/resolved.html#category-x
[📄license-compat-img]: https://img.shields.io/badge/Apache_Incompatible:_Category_X-%E2%9C%97-C0392B.svg?style=flat&logo=Apache
[📄ilo-declaration]: https://www.ilo.org/declaration/lang--en/index.htm
[📄ilo-declaration-img]: https://img.shields.io/badge/ILO_Fundamental_Principles-✓-259D6C.svg?style=flat
[🚎yard-current]: http://rubydoc.info/gems/ast-merge
[🚎yard-head]: https://ast-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
