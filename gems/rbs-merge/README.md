<a href="https://github.com/structuredmerge"><img alt="structuredmerge Logo by GitHub" src="https://github.com/structuredmerge.png?size=192" width="14%" align="right"/></a>

# ☯️ Rbs::Merge

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

Rbs::Merge intelligently merges two versions of an RBS (Ruby Signature) file using the official RBS parser. It is built on [ast-merge][ast-merge] and [tree_haver][tree_haver], while registering its RBS parser support with the shared backend tag system.

### Key Features

- **RBS-Aware**: Uses the official RBS parser to understand type signature structure
- **Intelligent**: Matches declarations by structural signatures (class names, method names, type aliases)
- **Recursive Merge**: Automatically merges class and module bodies recursively, intelligently combining nested method definitions and members
- **Comment-Preserving**: Comments are properly attached to relevant declarations
- **Freeze Block Support**: Respects freeze markers (default: `rbs-merge:freeze` / `rbs-merge:unfreeze`) for merge control - customizable to match your project's conventions
- **Full Provenance**: Tracks origin of every declaration
- **StructuredMerge Native**: Depends on `rbs`, `ast-merge`, and `tree_haver`
- **Customizable**:
    - `signature_generator` - callable custom signature generators
    - `preference` - setting of `:template`, `:destination`, or a Hash for per-node-type preferences
    - `node_splitter` - Hash mapping node types to callables for per-node-type merge customization (see [ast-merge][ast-merge] docs)
    - `add_template_only_nodes` - setting to retain declarations that do not exist in destination
    - `freeze_token` - customize freeze block markers (default: `"rbs-merge"`)

### Supported RBS Declarations

| Declaration Type | Signature Format | Matching Behavior |
| --- | --- | --- |
| `Class` | `[:class, name]` | Classes match by name |
| `Module` | `[:module, name]` | Modules match by name |
| `Interface` | `[:interface, name]` | Interfaces match by name |
| `TypeAlias` | `[:type_alias, name]` | Type aliases match by name |
| `Constant` | `[:constant, name]` | Constants match by name |
| `Global` | `[:global, name]` | Global variables match by name |
| `MethodDefinition` | `[:method, name, kind]` | Methods match by name and kind (instance/singleton) |
| `Alias` | `[:alias, new_name, old_name]` | Method aliases match by both names |
| `AttrReader` | `[:attr_reader, name]` | Attr readers match by name |
| `AttrWriter` | `[:attr_writer, name]` | Attr writers match by name |
| `AttrAccessor` | `[:attr_accessor, name]` | Attr accessors match by name |
| `Include` | `[:include, name]` | Include directives match by module name |
| `Extend` | `[:extend, name]` | Extend directives match by module name |
| `Prepend` | `[:prepend, name]` | Prepend directives match by module name |
| `InstanceVariable` | `[:ivar, name]` | Instance variables match by name |
| `ClassInstanceVariable` | `[:civar, name]` | Class instance variables match by name |
| `ClassVariable` | `[:cvar, name]` | Class variables match by name |

### Example

```ruby
require "rbs/merge"

template = File.read("template.rbs")
destination = File.read("destination.rbs")

merger = Rbs::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.rbs", result.to_s)
```

[ast-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge
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
bundle add rbs-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install rbs-merge
```

## ⚙️ Configuration

Rbs::Merge works out of the box with zero configuration, but offers customization options for advanced use cases.

### Signature Match Preference

Control which version to use when declarations have matching signatures but different content:

```ruby
# Use template version (for updating type definitions from a canonical source)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  preference: :template,
)

# Use destination version (for preserving local type customizations)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  preference: :destination,  # This is the default
)
```

**When to use each:**

- **`:template`** - Template contains canonical/updated type definitions

    - Generated RBS files from `rbs prototype` that should replace older versions
    - Type definition updates from upstream libraries
    - Standardized type signatures that should be enforced

- **`:destination`** (default) - Destination contains customizations

    - Hand-tuned type definitions with more specific types
    - Local overrides for library types
    - Project-specific type annotations

### Template-Only Declarations

Control whether to add declarations that only exist in the template:

```ruby
# Add template-only declarations (for merging new type definitions)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: true,
)

# Skip template-only declarations (for templates with placeholder types)
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: false,  # This is the default
)
```

**When to use each:**

- **`true`** - Template has new type definitions to add

    - New classes/modules from updated code
    - New method signatures that need type annotations
    - Required type aliases or constants

- **`false`** (default) - Template has placeholder/example types

    - Example type definitions that shouldn't be added
    - Generated types that may not apply to destination

### Combined Configuration

For different merge scenarios:

```ruby
# Scenario 1: Update types from generated RBS (template wins, add new types)
merger = Rbs::Merge::SmartMerger.new(
  generated_rbs,
  existing_rbs,
  preference: :template,
  add_template_only_nodes: true,
)
# Result: All type definitions updated to match generated, new types added

# Scenario 2: Preserve custom types (destination wins, skip template-only)
merger = Rbs::Merge::SmartMerger.new(
  library_types,
  custom_types,
  preference: :destination,  # default
  add_template_only_nodes: false,             # default
)
# Result: Custom type refinements preserved, template-only types skipped

# Scenario 3: Merge new types but keep customizations
merger = Rbs::Merge::SmartMerger.new(
  template_types,
  project_types,
  preference: :destination,  # Keep custom type refinements
  add_template_only_nodes: true,              # But add new type definitions
)
# Result: Existing types keep destination definitions, new types added from template
```

### Custom Signature Generator

You can provide a custom signature generator to control how declarations are matched between template and destination files:

```ruby
signature_generator = lambda do |node|
  case node
  when RBS::AST::Declarations::Class
    # Match classes by name only
    [:class, node.name.to_s]
  when RBS::AST::Declarations::TypeAlias
    # Match type aliases by name
    [:type_alias, node.name.to_s]
  when RBS::AST::Members::MethodDefinition
    # Match methods by name and kind
    [:method, node.name.to_s, node.kind]
  else
    # Return node to fall through to default signature computation
    node
  end
end

merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  signature_generator: signature_generator,
)
```

### Freeze Blocks

Protect sections in the destination file from being overwritten by the template using freeze markers.

By default, Rbs::Merge uses `rbs-merge` as the freeze token:

```ruby
# In your destination.rbs file
# rbs-merge:freeze
type custom_config = { api_key: String, timeout: Integer }
# rbs-merge:unfreeze
```

You can customize the freeze token to match your project's conventions:

```ruby
# Use a custom freeze token
merger = Rbs::Merge::SmartMerger.new(
  template,
  destination,
  freeze_token: "my-project",  # Now uses # my-project:freeze / # my-project:unfreeze
)
```

Freeze blocks are **always preserved** from the destination file during merge, regardless of template content. They can be placed around:

- Type alias definitions
- Class/module declarations
- Interface definitions
- Method signatures within classes
  This allows you to protect custom type definitions that should never be overwritten by template updates.

## 🔧 Basic Usage

### Simple Merge

The most basic usage merges two RBS files:

```ruby
require "rbs/merge"

template = File.read("template.rbs")
destination = File.read("destination.rbs")

merger = Rbs::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.rbs", result.to_s)
```

### Understanding the Merge

Rbs::Merge intelligently combines files by:

1.  **Parsing RBS**: Uses the official RBS parser to understand type structure
2.  **Finding Matches**: Identifies matching declarations between files by signature
3.  **Resolving Conflicts**: Uses configurable preference to choose between versions
4.  **Preserving Context**: Maintains comments and freeze blocks
    Example:

<!-- end list -->

```ruby
# template.rbs
class Foo
  def bar: (String) -> Integer
  def new_method: () -> void
end

type my_type = String

# destination.rbs
class Foo
  def bar: (Integer) -> String  # Custom signature
  def custom_method: () -> void
end

type my_type = Integer | String  # Expanded type

# After merge with default settings (destination preference):
# - Foo#bar keeps destination signature: (Integer) -> String
# - Foo#custom_method preserved (destination-only)
# - Foo#new_method NOT added (add_template_only_nodes: false)
# - my_type keeps destination definition: Integer | String
```

### Working with Generated RBS

When merging RBS files generated by `rbs prototype`:

```ruby
require "rbs/merge"

# Generate new type signatures
generated = `rbs prototype rb lib/my_class.rb`
existing = File.read("sig/my_class.rbs")

merger = Rbs::Merge::SmartMerger.new(
  generated,
  existing,
  preference: :template,  # Use generated signatures
  add_template_only_nodes: true,          # Add new methods
)
result = merger.merge

File.write("sig/my_class.rbs", result.to_s)
```

### Protecting Custom Types

Use freeze blocks to protect hand-crafted type definitions:

```ruby
# destination.rbs
class MyAPI
  # rbs-merge:freeze
  # These types are carefully tuned and should not be overwritten
  def fetch: [T] (String path, Class[T] type) -> T
  def post: [T, U] (String path, T body, Class[U] response_type) -> U
  # rbs-merge:unfreeze

  def version: () -> String
end
```

The generic method signatures in the freeze block will be preserved even if the template has simpler signatures.

### Merge Result Information

The merge result provides detailed information about decisions made:

```ruby
merger = Rbs::Merge::SmartMerger.new(template, destination)
result = merger.merge

# Get the merged content
puts result.to_s

# Check if anything was merged
puts "Empty result" if result.empty?

# Get summary of decisions
summary = result.summary
puts "Total decisions: #{summary[:total_decisions]}"
puts "Total lines: #{summary[:total_lines]}"
puts "By decision type: #{summary[:by_decision]}"
```

### Error Handling

Rbs::Merge provides specific error types for different failure modes:

```ruby
require "rbs/merge"

begin
  merger = Rbs::Merge::SmartMerger.new(template, destination)
  result = merger.merge
rescue Rbs::Merge::TemplateParseError => e
  puts "Template has syntax errors: #{e.message}"
rescue Rbs::Merge::DestinationParseError => e
  puts "Destination has syntax errors: #{e.message}"
rescue Rbs::Merge::FreezeNode::InvalidStructureError => e
  puts "Invalid freeze block structure: #{e.message}"
  puts "  Start line: #{e.start_line}"
  puts "  End line: #{e.end_line}"
end
```

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
spec.add_dependency("rbs-merge", "~> 7.0")
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
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Rbs::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://clickgems.clickhouse.com/dashboard/rbs-merge
[⛳️name-img]: https://img.shields.io/badge/name-rbs--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/rbs-merge
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-rbs-merge?utm_source=rubygems-rbs-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/rbs-merge
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/rbs-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=GitHub&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://clickgems.clickhouse.com/dashboard/rbs-merge
[👽dl-ranki]: https://img.shields.io/gem/dt/rbs-merge.svg
[👽version]: https://clickgems.clickhouse.com/dashboard/rbs-merge
[👽versioni]: https://img.shields.io/gem/v/rbs-merge.svg
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
[🚎yard-current]: http://rubydoc.info/gems/rbs-merge
[🚎yard-head]: https://rbs-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
