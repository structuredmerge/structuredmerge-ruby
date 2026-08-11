<a href="https://github.com/structuredmerge"><img alt="structuredmerge Logo by GitHub" src="https://github.com/structuredmerge.png?size=192" width="14%" align="right"/></a>

# ☯️ Markdown::Merge

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

Markdown::Merge provides **intelligent Markdown file merging** using tree\_haver backends. It can be used standalone or through parser-specific wrappers.

**Direct usage** (with auto-detected or specified backend):

```ruby
require "markdown/merge"

# Auto-detect available backend (commonmarker or markly)
merger = Markdown::Merge::SmartMerger.new(template_content, dest_content)
result = merger.merge

# Or specify a backend explicitly
merger = Markdown::Merge::SmartMerger.new(template_content, dest_content, backend: :markly)
```

**Via parser-specific wrappers** (for hard dependencies and backend-specific defaults):

- [commonmarker-merge][commonmarker-merge] - Uses Comrak (Rust) via Commonmarker
- [markly-merge][markly-merge] - Uses libcmark-gfm (C) via Markly

### Key Features

- **Multiple Backends**: Supports Commonmarker and Markly through tree\_haver's unified API
- **Type Normalization**: Canonical node types (`:heading`, `:paragraph`, etc.) work across all backends
- **Extensible**: Register custom backends via `NodeTypeNormalizer.register_backend`
- **Structure-Aware**: Understands headings, paragraphs, lists, code blocks, tables, and other block elements
- **Freeze Block Support**: Respects freeze markers (default: `markdown-merge:freeze` / `markdown-merge:unfreeze`) for template merge control - customizable to match your project's conventions
- **Inner-Merge Code Blocks**: Optionally merge fenced code blocks using language-specific mergers (Ruby → prism-merge, YAML → psych-merge, JSON → json-merge, TOML → toml-merge)
- **Table Match Refiner**: Fuzzy matching algorithm for tables with similar but not identical headers
- **Full Provenance**: Tracks origin of every node
- **Customizable**:
    - `backend` - select `:commonmarker`, `:markly`, or `:auto`
    - `signature_generator` - callable custom signature generators
    - `preference` - setting of `:template`, `:destination`, or a Hash for per-node-type preferences
    - `add_template_only_nodes` - setting to retain sections that do not exist in destination
    - `freeze_token` - customize freeze block markers (default: `"markdown-merge"`)
    - `inner_merge_code_blocks` - enable language-aware code block merging
    - `match_refiner` - fuzzy matching for unmatched nodes (e.g., `TableMatchRefiner`)

### Supported Node Types

Signatures computed by default for common Markdown block elements:

| Node Type           | Signature Format                        | Matching Behavior                                   |
|---------------------|-----------------------------------------|-----------------------------------------------------|
| Heading             | `[:heading, level, text]`               | Headings match by level and text content            |
| Paragraph           | `[:paragraph, content_hash]`            | Paragraphs match by content hash                    |
| List                | `[:list, type, item_count]`             | Lists match by type (bullet/ordered) and item count |
| Code Block          | `[:code_block, language, content_hash]` | Code blocks match by language and content           |
| Block Quote         | `[:blockquote, content_hash]`           | Block quotes match by content hash                  |
| Table               | `[:table, row_count, header_hash]`      | Tables match by structure and header content        |
| HTML Block          | `[:html, content_hash]`                 | HTML blocks match by content hash                   |
| Thematic Break      | `[:hrule]`                              | Horizontal rules always match                       |
| Footnote Definition | `[:footnote_definition, label]`         | Footnotes match by label/name                       |

[commonmarker-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge
[markly-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge

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
bundle add markdown-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install markdown-merge
```

## ⚙️ Configuration

### SmartMerger Configuration

The `SmartMerger` class is the main entry point for merging Markdown files:

```ruby
require "markdown/merge"

merger = Markdown::Merge::SmartMerger.new(
  template_content,
  dest_content,

  # Backend selection (default: :auto)
  # :auto - auto-detect available backend (tries commonmarker first, then markly)
  # :commonmarker - use Commonmarker (comrak Rust parser)
  # :markly - use Markly (cmark-gfm C library)
  backend: :auto,

  # Which version to prefer when nodes match but differ
  # :destination (default) - keep destination content (preserves customizations)
  # :template - use template content (applies updates)
  preference: :destination,

  # Whether to add template-only nodes to the result
  # false (default) - only include sections that exist in destination
  # true - include all template sections
  add_template_only_nodes: false,

  # Token for freeze block markers
  # Default: "markdown-merge"
  # Looks for: <!-- markdown-merge:freeze --> / <!-- markdown-merge:unfreeze -->
  freeze_token: "markdown-merge",

  # Enable inner-merge for fenced code blocks
  # false (default) - use standard conflict resolution for code blocks
  # true - merge code block contents using language-specific mergers
  # CodeBlockMerger instance - use custom CodeBlockMerger
  inner_merge_code_blocks: false,

  # Match refiner for fuzzy matching of unmatched nodes
  # nil (default) - exact matching only
  # TableMatchRefiner.new - enable fuzzy table matching
  match_refiner: nil,

  # Custom signature generator (optional)
  # Receives a node (wrapped with canonical merge_type), returns a signature array or nil
  # Return the node itself to fall through to default signature
  signature_generator: nil,

  # Backend-specific options (passed through to parser)
  # For commonmarker: options: {}
  # For markly: flags: Markly::DEFAULT, extensions: [:table]
)
```

### Text Matching Behavior

**Important**: When matching nodes by text content (such as for anchor patterns in
`PartialTemplateMerger`), the `.text` method returns **plain text without markdown formatting**.

This means:

- Markdown: `` ### The `*-merge` Gem Family ``
- `.text` returns: `"The *-merge Gem Family\n"`

The backticks around `*-merge` are stripped because they are inline formatting, not content.
This is true for both Commonmarker and Markly backends.

**Anchor pattern examples**:

```ruby
# ❌ WRONG - backticks are stripped, so this won't match
anchor: { type: :heading, text: /`\*-merge` Gem Family/ }

# ✅ CORRECT - match the plain text content
anchor: { type: :heading, text: /\*-merge.*Gem Family/ }

# ✅ CORRECT - use beginning anchor for exact heading match
anchor: { type: :heading, text: /^The \*-merge Gem Family/ }
```

**Other markdown formatting that is stripped from `.text`**:

- Bold: `**text**` → `text`
- Italic: `*text*` or `_text_` → `text`
- Code: `` `code` `` → `code`
- Links: `[text](url)` → `text`
- Images: `![alt](src)` → `alt`

**Note**: Different parsers may have other idiosyncrasies. For example:

- Trailing newlines may or may not be present
- Whitespace normalization may differ
- Entity encoding may vary

Always test your patterns against actual parsed content when building merge recipes.

### Node Type Normalization

markdown-merge normalizes node types across backends so merge rules are portable:

```ruby
# These are equivalent regardless of backend
# Markly's :header becomes :heading
# Markly's :hrule becomes :thematic_break
# etc.

# Register a custom backend's type mappings
Markdown::Merge::NodeTypeNormalizer.register_backend(:my_parser, {
  h1: :heading,
  h2: :heading,
  para: :paragraph,
  # ...
})
```

### Parser-Specific Wrappers

For convenience, parser-specific wrappers provide backend-specific defaults:

```ruby
# commonmarker-merge (freeze_token: "commonmarker-merge", inner_merge_code_blocks: false)
require "commonmarker/merge"
merger = Commonmarker::Merge::SmartMerger.new(template, dest, options: {})

# markly-merge (freeze_token: "markly-merge", inner_merge_code_blocks: true)
require "markly/merge"
merger = Markly::Merge::SmartMerger.new(template, dest, flags: Markly::DEFAULT, extensions: [:table])
```

### Freeze Blocks

Freeze blocks protect sections from being modified during merges. They are marked
with HTML comments that are invisible when the Markdown is rendered:

```markdown
<!-- markdown-merge:freeze -->

## This Section Is Protected

Any content here will be preserved exactly as-is during merges.
The merge tool will not modify, replace, or remove this content.

<!-- markdown-merge:unfreeze -->
```

Add an optional frozen reason to document why:

```markdown
<!-- markdown-merge:freeze Custom table - manually maintained -->
| Feature | Status |
|---------|--------|
| Custom  | ✅     |
<!-- markdown-merge:unfreeze -->
```

### Inner-Merge Code Blocks

When enabled, fenced code blocks are merged using language-specific `*-merge` gems:

```ruby
merger = SomeParser::Merge::SmartMerger.new(
  template,
  destination,
  inner_merge_code_blocks: true,
)
```

Supported languages and their mergers:

| Language | Fence Info | Merger |
| --- | --- | --- |
| Ruby | `ruby`, `rb` | prism-merge |
| YAML | `yaml`, `yml` | psych-merge |
| JSON | `json` | json-merge |
| TOML | `toml` | toml-merge |

Example with a Ruby code block:

````markdown
```ruby

# Template

class MyClass
  def new_method
    puts "from template"
  end
end
```
````

When merged(with:

````markdown
```ruby

# Destination

class MyClass
  def existing_method
    puts "custom"
  end
end)
```
````

Result (with `inner_merge_code_blocks: true`):

````markdown
```ruby
class MyClass
  def existing_method
    puts "custom"
  end

  def new_method
    puts "from template"
  end
end
```
````

### Table Match Refiner

When tables don't match by exact signature, the `TableMatchRefiner` uses
fuzzy matching to pair tables with similar structure:

```ruby
refiner = Markdown::Merge::TableMatchRefiner.new(
  threshold: 0.5,  # Minimum similarity (0.0-1.0)
  algorithm_options: {
    weights: {
      header_match: 0.25,  # Header cell similarity
      first_column: 0.20,  # Row label similarity
      row_content: 0.25,   # Row content overlap
      total_cells: 0.15,   # Overall cell matching
      position: 0.15,      # Position distance
    },
  },
)

merger = SomeParser::Merge::SmartMerger.new(
  template,
  destination,
  match_refiner: refiner,
)
```

### Debug Logging

Enable debug logging to see merge decisions:

```bash
export MARKDOWN_MERGE_DEBUG=1
```

## 🔧 Basic Usage

**Note:** This gem provides base classes for implementers. End users should use
[commonmarker-merge][commonmarker-merge] or
[markly-merge][markly-merge] instead.

### For End Users

Use a parser-specific implementation:

#### Option 1: Using commonmarker-merge (Comrak/Rust)

```ruby
require "commonmarker/merge"

template = File.read("template.md")
destination = File.read("destination.md")

merger = Commonmarker::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.md", result.content)
```

#### Option 2: Using markly-merge (libcmark-gfm/C)

```ruby
require "markly/merge"

template = File.read("template.md")
destination = File.read("destination.md")

merger = Markly::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.md", result.to_markdown)
```

### For Implementers

Creating a new parser-specific implementation:

```ruby
require "markdown/merge"

module MyParser
  module Merge
    class FileAnalysis < Markdown::Merge::FileAnalysisBase
      def parse_document(source)
        # Parse source and return root document node
        MyParser.parse(source)
      end

      def next_sibling(node)
        # Return the next sibling of a node
        node.next_sibling
      end

      def compute_parser_signature(node)
        # Compute signature for parser-specific nodes
        # Or call super for default implementation
        super
      end
    end

    class SmartMerger < Markdown::Merge::SmartMergerBase
      def create_file_analysis(content, **options)
        FileAnalysis.new(content, **options)
      end

      def node_to_source(node, analysis)
        case node
        when Markdown::Merge::FreezeNode
          node.full_text
        else
          # Convert node back to source text
          node.to_markdown
        end
      end
    end
  end
end
```

### Freeze Block Protection

Both implementations support freeze blocks for protecting customized sections:

```markdown

# My Project

## Installation

<!-- markdown-merge:freeze Custom install instructions -->
This installation section has been customized and will be preserved
during template merges, regardless of what the template contains.
<!-- markdown-merge:unfreeze -->

## Usage

Standard usage section - can be updated from template.
```

Content between freeze markers is always preserved from the destination file,
even when the template has different content for that section.

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
spec.add_dependency("markdown-merge", "~> 7.0")
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
[✉️ruby-forum]: https://www.rubyforum.org/tag/structuredmerge
[✇bundle-group-pattern]: https://gist.github.com/pboling/4564780
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Markdown::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://clickgems.clickhouse.com/dashboard/markdown-merge
[⛳️name-img]: https://img.shields.io/badge/name-markdown--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/markdown-merge
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-markdown-merge?utm_source=rubygems-markdown-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/markdown-merge
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/markdown-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=GitHub&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://clickgems.clickhouse.com/dashboard/markdown-merge
[👽dl-ranki]: https://img.shields.io/gem/dt/markdown-merge.svg
[👽version]: https://clickgems.clickhouse.com/dashboard/markdown-merge
[👽versioni]: https://img.shields.io/gem/v/markdown-merge.svg
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
[🧮kloc-img]: https://img.shields.io/badge/KLOC-4.086-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
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
[🚎yard-current]: http://rubydoc.info/gems/markdown-merge
[🚎yard-head]: https://markdown-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
