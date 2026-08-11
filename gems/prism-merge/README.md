<a href="https://github.com/structuredmerge"><img alt="structuredmerge Logo by GitHub" src="https://github.com/structuredmerge.png?size=192" width="14%" align="right"/></a>

# ☯️ Prism::Merge

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

Prism::Merge intelligently merges two versions of a Ruby file using Prism AST analysis. It is built on [ast-merge][ast-merge] and [tree_haver][tree_haver], and provides the Ruby-source provider for the StructuredMerge Ruby stack.

### Key Features

- **AST-Aware**: Uses Prism parser to understand Ruby structure
- **Intelligent**: Matches nodes by structural signatures
- **Three-Phase Node Matching**: Ordered matching pipeline ensures optimal pairing:
  1. **Exact** — structural signature match (method name, parameters)
  2. **Similar** — Jaccard body-text similarity for renamed methods/refactors
  3. **Cross-depth** — finds nodes wrapped in conditionals (`if`/`unless`) at deeper AST levels
- **Moved-Node Detection**: Recognizes when a template node exists inside a destination
  control-flow block (e.g., `eval_gemfile` wrapped in `if ENV["CI"]`) and avoids duplicating it
- **Gemspec Variable Renaming**: When a legacy gemspec uses `do |gem|` but the template
  uses `do |spec|`, all receivers are AST-rewritten (not regex!) so the merged output is consistent
- **Fuzzy Method Matching**: `MethodMatchRefiner` matches similar method names and signatures
  (e.g., `process_user` ↔ `process_users`) using Levenshtein distance
- **Recursive Merge**: Automatically merges class and module bodies recursively, intelligently combining nested methods and constants
- **Partial Template Merge Support**: Can surgically replace or merge an anchored top-level Ruby section through the shared `ast-merge` recipe substrate
- **Comment-Preserving**: Comments are properly attached to relevant nodes and/or placement
- **Freeze Block Support**: Respects freeze markers (default: `prism-merge:freeze` / `prism-merge:unfreeze`) for template merge control - customizable to match your project's conventions
- **Full Provenance**: Tracks origin of every line
- **Standalone**: No dependencies other than `prism` and `version_gem` (which is a tiny tool all my gems depend on)
- **Customizable**:
  - `signature_generator` - callable custom signature generators
  - `preference` - setting of `:template`, `:destination`, or a Hash for per-node-type preferences
  - `node_typing` - Hash mapping node types to callables for per-node-type merge customization (see [ast-merge][ast-merge] docs)
  - `add_template_only_nodes` - setting to retain nodes that do not exist in destination
  - `freeze_token` - customize freeze block markers (default: `"prism-merge"`)
  - `match_refiners` - array of refiners for fuzzy matching (e.g., `MethodMatchRefiner`)

### Example

```ruby
require "prism/merge"

template = File.read("template.rb")
destination = File.read("destination.rb")

merger = Prism::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.rb", result)
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
bundle add prism-merge
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install prism-merge
```

## ⚙️ Configuration

Prism::Merge works out of the box with zero configuration, but offers customization options for advanced use cases.

### Signature Match Preference

Control which version to use when nodes have matching signatures but different content:

```ruby
# Use template version (for version files, configs where template has updates)
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  preference: :template,
)

# Use destination version (for Appraisals, configs with customizations)
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  preference: :destination,  # This is the default
)
```

**When to use each:**

- **`:template`** - Template contains canonical/updated values
  - Version files (`VERSION = "2.0.0"` should replace `VERSION = "1.0.0"`)
  - Configuration updates (`API_ENDPOINT` should be updated)
  - Conditional bodies (`if ENV["DEBUG"]` should use template's implementation)

- **`:destination`** (default) - Destination contains customizations
  - Appraisals files (destination has project-specific gem versions)
  - Project-specific configurations
  - Custom implementations

### Template-Only Nodes

Control whether to add nodes that only exist in the template:

```ruby
# Add template-only nodes (for merging new features/constants)
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: true,
)

# Skip template-only nodes (for templates with placeholder content)
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  add_template_only_nodes: false,  # This is the default
)
```

**When to use each:**

- **`true`** - Template has new content to add
  - New constants (`NAME = "myapp"` should be added to destination)
  - New methods/classes from template
  - Required configuration options

- **`false`** (default) - Template has placeholder/example content
  - Appraisals templates with ruby version blocks not in destination
  - Example configurations that shouldn't be added
  - Template-only nodes would create unwanted additions

### Combined Configuration

For different merge scenarios:

```ruby
# Scenario 1: Version file merge (template wins, add new constants)
merger = Prism::Merge::SmartMerger.new(
  template_content,
  dest_content,
  preference: :template,
  add_template_only_nodes: true,
)
# Result: VERSION updated to template value, NAME constant added

# Scenario 2: Appraisals merge (destination wins, skip template-only blocks)
merger = Prism::Merge::SmartMerger.new(
  template_content,
  dest_content,
  preference: :destination,       # default
  add_template_only_nodes: false, # default
)
# Result: Destination gem versions preserved, template-only ruby blocks skipped

# Scenario 3: Config merge (mix and match)
merger = Prism::Merge::SmartMerger.new(
  template_content,
  dest_content,
  preference: :destination,       # Keep custom values
  add_template_only_nodes: true,  # But add new required configs
)
# Result: Existing configs keep destination values, new configs added from template
```

### Recursion Depth Limit

Prism::Merge automatically detects when block bodies contain only literals or simple expressions (no mergeable statements) and treats them atomically. However, as a safety valve for edge cases, you can limit recursion depth:

```ruby
# Limit recursive merging to 3 levels deep
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  max_recursion_depth: 3,
)

# Disable recursive merging entirely (treat all nodes atomically)
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  max_recursion_depth: 0,
)
```

**When to use:**

- **`Float::INFINITY`** (default) - Normal operation, recursion terminates naturally based on content analysis.
  - NOTE: If you get `stack level too deep (SystemStackError)`, please file a [bug][🤝gh-issues]!
- **Finite value** - Safety valve if you encounter edge cases with unexpected deep recursion
- **`0`** - Disable recursive merging entirely; all matching nodes are treated atomically

### Per-Node-Type Preferences

For advanced use cases, you can specify different preferences for different node types using a Hash:

```ruby
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  preference: {
    default: :destination,    # Default for unspecified types
    lint_gem: :template,      # Use template versions for lint gems
    test_gem: :destination,   # Keep destination versions for test gems
  },
)
```

This is especially powerful when combined with the `node_typing` option (see below) to create custom node categories.

### Node Typing

The `node_typing` option allows you to transform nodes and add custom `merge_type` attributes that can be used for per-node-type preferences:

```ruby
# Define a node typing config that categorizes gem calls
node_typing = {
  CallNode: ->(node) {
    # Only process gem() calls
    return node unless node.name == :gem
    first_arg = node.arguments&.arguments&.first
    return node unless first_arg.is_a?(Prism::StringNode)

    gem_name = first_arg.unescaped

    # Categorize gems by type
    if gem_name.start_with?("rubocop", "standard")
      Ast::Merge::NodeTyping.with_merge_type(node, :lint_gem)
    elsif gem_name.start_with?("rspec", "minitest", "test-")
      Ast::Merge::NodeTyping.with_merge_type(node, :test_gem)
    else
      node  # Return unchanged for other gems
    end
  },
}

# Use the node typing with per-type preferences
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  node_typing: node_typing,
  preference: {
    default: :destination,    # Default: keep destination versions
    lint_gem: :template,      # But use template versions for linters
  },
)
```

#### How Node Typing Works

1. **Node Processing**: During analysis, each node is passed through the typing config for its type
2. **Type Wrapping**: The config can wrap nodes with `Ast::Merge::NodeTyping.with_merge_type(node, :type)`
3. **Preference Lookup**: During conflict resolution, wrapped nodes have their `merge_type` checked against the preference Hash
4. **Transparent Delegation**: Wrapped nodes delegate all methods to the original node, so existing logic works unchanged

#### Node Typing Return Values

Your typing callable can return:

- **The original node** - Node is processed normally with default preference
- **A wrapped node** (using `NodeTyping.with_merge_type`) - Node uses the type-specific preference
- **`nil`** - Node is skipped (use with caution)

#### Integration with Signature Generator

Node typing works alongside `signature_generator`. Nodes are first processed through the typing config, then the (potentially wrapped) node is passed to the signature generator:

```ruby
node_typing = {
  CallNode: ->(node) {
    # Categorize gem calls
    return node unless node.name == :gem
    gem_name = node.arguments&.arguments&.first&.unescaped
    return node unless gem_name

    if gem_name.match?(/^(rubocop|standard)/)
      Ast::Merge::NodeTyping.with_merge_type(node, :lint_gem)
    else
      node
    end
  },
}

signature_generator = ->(node) {
  # Custom signature for gem calls
  if node.is_a?(Prism::CallNode) && node.name == :gem
    first_arg = node.arguments&.arguments&.first
    return [:gem, first_arg.unescaped] if first_arg.is_a?(Prism::StringNode)
  end
  node  # Fall through to default
}

merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  node_typing: node_typing,
  signature_generator: signature_generator,
  preference: {default: :destination, lint_gem: :template},
)
```

### Method Match Refiner

When Ruby method definitions don't match by exact signature (name + parameters), the
`MethodMatchRefiner` uses fuzzy matching to pair methods with:

- Similar names (e.g., `process_user` vs `process_users`)
- Same name but different parameter signatures
- Renamed methods that perform similar functions

```ruby
# Enable method fuzzy matching
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  match_refiners: [
    Prism::Merge::MethodMatchRefiner.new(threshold: 0.6),
  ],
)
```

#### MethodMatchRefiner Options

| Option | Default | Description |
|--------|---------|-------------|
| `threshold` | 0.5 | Minimum similarity score (0.0-1.0) to accept a match |
| `name_weight` | 0.7 | Weight for method name similarity |
| `params_weight` | 0.3 | Weight for parameter similarity |

```ruby
# Custom weights for name-centric matching
refiner = Prism::Merge::MethodMatchRefiner.new(
  threshold: 0.6,
  name_weight: 0.8,   # Focus more on method names
  params_weight: 0.2,  # Less focus on parameters
)

merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  match_refiners: [refiner],
)
```

#### Fuzzy Method Matching Example

```ruby
template = <<~RUBY
  class UserService
    def process_user(user)
      validate(user)
      save(user)
    end

    def find_user_by_email(email)
      User.find_by(email: email)
    end
  end
RUBY

destination = <<~RUBY
  class UserService
    def process_users(users)
      users.each { |u| validate(u); save(u) }
    end

    def find_by_email(email)
      User.where(email: email).first
    end
  end
RUBY

# Default merge won't match methods (names/params differ)
# Use MethodMatchRefiner for fuzzy matching
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  match_refiners: [
    Prism::Merge::MethodMatchRefiner.new(threshold: 0.5),
  ],
)

# Methods are matched despite name differences:
# - process_user ↔ process_users (similar: "process_user")
# - find_user_by_email ↔ find_by_email (similar: "find", "email")
```

### Custom Signature Generator

By default, Prism::Merge uses intelligent structural signatures to match nodes. The signature determines how nodes are matched between template and destination files.

#### Default Signature Matching

| Node Type | Signature Format | Matching Behavior |
|-----------|-----------------|-------------------|
| `DefNode` | `[:def, name, params]` | Methods match by name and parameter names |
| `ClassNode` | `[:class, name]` | Classes match by name |
| `ModuleNode` | `[:module, name]` | Modules match by name |
| `SingletonClassNode` | `[:singleton_class, expr]` | Singleton classes match by expression (`class << self`) |
| `ConstantWriteNode` | `[:const, name]` | Constants match by name only (not value) |
| `ConstantPathWriteNode` | `[:const, target]` | Namespaced constants match by full path |
| `LocalVariableWriteNode` | `[:local_var, name]` | Local variables match by name |
| `InstanceVariableWriteNode` | `[:ivar, name]` | Instance variables match by name |
| `ClassVariableWriteNode` | `[:cvar, name]` | Class variables match by name |
| `GlobalVariableWriteNode` | `[:gvar, name]` | Global variables match by name |
| `MultiWriteNode` | `[:multi_write, targets]` | Multiple assignment matches by target names |
| `IfNode` / `UnlessNode` | `[:if, condition]` | Conditionals match by condition expression |
| `CaseNode` | `[:case, predicate]` | Case statements match by the expression being switched |
| `CaseMatchNode` | `[:case_match, predicate]` | Pattern matching cases match by expression |
| `WhileNode` / `UntilNode` | `[:while, condition]` | Loops match by condition |
| `ForNode` | `[:for, index, collection]` | For loops match by index variable and collection |
| `BeginNode` | `[:begin, first_stmt]` | Begin blocks match by first statement (partial) |
| `CallNode` (regular) | `[:call, name, first_arg]` | Method calls match by name and first argument |
| `CallNode` (assignment) | `[:call, :method=, receiver]` | Assignment calls (`x.y = z`) match by receiver, not value |
| `CallNode` (with block) | `[:call_with_block, name, first_arg]` | Block calls match by name and first argument |
| `SuperNode` | `[:super, :with_block]` | Super calls match by presence of block |
| `LambdaNode` | `[:lambda, params]` | Lambdas match by parameter signature |
| `PreExecutionNode` | `[:pre_execution, line]` | BEGIN blocks match by line number |
| `PostExecutionNode` | `[:post_execution, line]` | END blocks match by line number |

#### Recursive Merge Support

The following node types support **recursive body merging**, where nested content is intelligently combined:

- `ClassNode` - class bodies are recursively merged
- `ModuleNode` - module bodies are recursively merged
- `SingletonClassNode` - singleton class bodies are recursively merged
- `CallNode` with block - block bodies are recursively merged **only when the body contains mergeable statements** (e.g., `describe do ... end` with nested `it` blocks). Blocks containing only literals or simple expressions (like `git_source(:github) { |repo| "https://..." }`) are treated atomically.
- `BeginNode` - begin/rescue/ensure blocks are recursively merged

#### Custom Signature Generator

You can provide a custom signature generator to control how nodes are matched between template and destination files. The signature generator is a callable (lambda/proc) that receives a `Prism::Node` (or `FreezeNodeBase` subclass) and returns one of three types of values:

| Return Value | Behavior |
|--------------|----------|
| **Array** (e.g., `[:gem, "foo"]`) | Used as the node's signature for matching. Nodes with identical signatures are considered matches. |
| **`nil`** | The node gets no signature and won't be matched by signature. Useful for nodes you want to skip or handle specially. |
| **`Prism::Node` or `FreezeNodeBase` subclass** | Falls through to the default signature computation using the returned node. Return the original node unchanged for simple fallthrough, or return a modified node to influence default matching. |

##### Basic Example

```ruby
signature_generator = lambda do |node|
  case node
  when Prism::CallNode
    # Match method calls by name only, ignoring arguments
    [:call, node.name]
  when Prism::DefNode
    # Match method definitions by name and parameters
    [:def, node.name, node.parameters&.slice]
  when Prism::ClassNode
    # Match classes by name
    [:class, node.constant_path.slice]
  else
    # Default matching - return node to fall through
    node
  end
end
```

##### Fallthrough Example (Recommended Pattern)

The fallthrough pattern allows you to customize only specific node types while delegating everything else to the built-in signature logic:

```ruby
signature_generator = ->(node) {
  # Only customize CallNode signatures for specific methods
  if node.is_a?(Prism::CallNode)
    # source() calls - match by method name only (there's usually just one)
    return [:source] if node.name == :source

    # gem() calls - match by gem name (first argument)
    if node.name == :gem
      first_arg = node.arguments&.arguments&.first
      if first_arg.is_a?(Prism::StringNode)
        return [:gem, first_arg.unescaped]
      end
    end
  end

  # Return the node to fall through to default signature computation
  # This preserves correct handling for FreezeNodeBase subclasses, classes, modules, etc.
  node
}

merger = Prism::Merge::SmartMerger.new(
  template_content,
  destination_content,
  signature_generator: signature_generator,
  preference: :template,
  add_template_only_nodes: true,
)
```

##### Why Fallthrough Matters

When you provide a custom signature generator, it's called for **all** node types, including internal types like `FreezeNodeBase` subclasses. If your generator returns `nil` for node types it doesn't recognize, those nodes won't be matched properly:

```ruby
# ❌ Bad: Returns nil for unrecognized nodes
signature_generator = ->(node) {
  return unless node.is_a?(Prism::CallNode)  # FreezeNodeBase subclasses get nil!
  [:call, node.name]
}

# ✅ Good: Falls through for unrecognized nodes
signature_generator = ->(node) {
  if node.is_a?(Prism::CallNode)
    return [:call, node.name]
  end
  node  # FreezeNodeBase subclasses and others use default signatures
}
```

### Three-Phase Node Matching

Prism::Merge uses an ordered three-phase matching pipeline to handle renames, refactors, and moved nodes without duplication:

**Phase 1 — Exact Signature Match** (always runs first)

Nodes are paired by structural signature (e.g., `[:def, :my_method, [:arg1, :arg2]]`). This is the fastest and most precise phase. All exact matches are locked in before any fuzzy matching begins.

**Phase 2 — Body-Text Similarity** (for renamed methods)

After Phase 1, unmatched nodes at the same AST depth are compared using Jaccard body-text similarity. This catches renames — e.g., `def process_users` renamed to `def handle_users` with the same body. Only compound nodes with bodies (DefNode, ClassNode, ModuleNode) are eligible. Threshold: Jaccard > 0.6, minimum 3 body tokens.

```ruby
# Template                          # Destination
def handle_users(data)              def process_users(data)
  data.each { |u| validate(u) }      data.each { |u| validate(u) }
end                                 end
# Phase 2 recognizes these as the same method (renamed), not two separate nodes
```

**Phase 3 — Cross-Depth Search** (for moved nodes)

Remaining orphan template nodes are searched for inside destination control-flow blocks (`if`, `unless`, `begin`). This handles the common pattern where a template top-level statement exists inside a conditional in the destination:

```ruby
# Template has this at the top level:
eval_gemfile "gemfiles/modular/templating.gemfile"

# Destination has it wrapped in a conditional:
if ENV.fetch("CI", "false").casecmp("false").zero?
  eval_gemfile "gemfiles/modular/templating.gemfile"
end
# Phase 3 finds the match inside the if-block, preventing duplication
```

Phase ordering is critical: exact matches must be locked in first so that fuzzy scoring cannot consume nodes that would have exact matches at different positions.

### Gemspec Variable Renaming

When merging gemspec files where the block variable differs between template and destination (e.g., `do |spec|` vs `do |gem|`), Prism::Merge automatically rewrites receivers using AST-directed byte-offset replacement:

```ruby
# Template gemspec uses |spec|:
Gem::Specification.new do |spec|
  spec.name = "mylib"
  spec.add_development_dependency("rake", "~> 13.0")
end

# Destination gemspec uses |gem|:
Gem::Specification.new do |gem|
  gem.name = "mylib"
  gem.summary = "A great library"
  gem.metadata["funding_uri"] = "https://fund.me"
end

# After merge — all receivers use template's variable name:
Gem::Specification.new do |spec|
  spec.name = "mylib"
  spec.add_development_dependency("rake", "~> 13.0")
  spec.summary = "A great library"          # dest-only, auto-renamed
  spec.metadata["funding_uri"] = "https://fund.me"  # dest-only, auto-renamed
end
```

The renaming is performed by `Prism::Merge::GemspecVarRenamer`, which:

1. Parses the source with Prism
2. Walks the AST via `Prism::Visitor` to find all `CallNode` root receivers matching the old variable
3. Collects unique byte offsets (handles chained calls like `gem.metadata[]` and operator writes like `gem.files +=`)
4. Applies positional replacements — **no regular expressions**

### Freeze Blocks

Protect sections in the destination file from being overwritten by the template using freeze markers.

By default, Prism::Merge uses `prism-merge` as the freeze token:

```ruby
# In your destination.rb file
# prism-merge:freeze
gem "custom-gem", path: "../custom"
# Add any custom configuration you want to preserve
# prism-merge:unfreeze
```

You can customize the freeze token to match your project's conventions:

```ruby
# Use a custom freeze token (e.g., for kettle-dev projects)
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  freeze_token: "kettle-dev",  # Now uses # kettle-dev:freeze / # kettle-dev:unfreeze
)
```

Freeze blocks are **always preserved** from the destination file during merge, regardless of template content. They can be placed inside:

- Class and module bodies (`class Foo ... end`, `module Bar ... end`)
- Singleton class bodies (`class << self ... end`)
- Method definitions (`def method_name ... end`)
- Lambda/proc bodies (`-> { ... }`)
- Block-based DSLs (e.g., RSpec `describe`/`context` blocks)

This allows you to protect entire methods, portions of method implementations, or sections within DSL blocks.

#### Inline Freeze Comments

In addition to freeze blocks (with matching `freeze`/`unfreeze` markers), you can freeze a **single Ruby statement** by placing a freeze comment immediately before it:

```ruby
# prism-merge:freeze
gem "my-custom-gem", path: "../local-fork"
```

When a freeze comment appears in the leading comments of a Ruby statement, that **entire statement is frozen**. This has important implications:

##### Simple Statements

For simple statements like method calls, assignments, or single expressions, the entire line is frozen:

```ruby
# prism-merge:freeze
gem "example", "~> 1.0"  # This entire gem declaration is frozen

# prism-merge:freeze
VERSION = "1.2.3"  # This constant assignment is frozen
```

##### Block Statements

**⚠️ Important:** When a freeze comment precedes a block-based statement (like a class, module, method definition, or DSL block), the **entire block is frozen**, preventing any template updates to that section:

```ruby
# prism-merge:freeze
class MyCustomClass
  # EVERYTHING inside this class is frozen!
  # Template changes to this class will be ignored.
  def custom_method
    # ...
  end
end

# prism-merge:freeze
module MyModule
  # The entire module body is frozen
end

# prism-merge:freeze
def my_method(arg)
  # The entire method body is frozen
end

# prism-merge:freeze
describe "My Feature" do
  # All specs inside this describe block are frozen
  it "does something" do
    # ...
  end
end
```

##### Matching Behavior

Frozen statements are matched by their **structural identity**, not their content. This means:

- A frozen `gem "example"` in the destination will match `gem "example"` in the template (by gem name)
- A frozen `def my_method` will match `def my_method` in the template (by method name)
- A frozen `class Foo` will match `class Foo` in the template (by class name)

The destination's frozen version is always preserved, regardless of changes in the template.

### Integration with Existing Systems

If you're integrating with an existing system that has its own signature logic:

```ruby
# Use your existing signature function
my_signature_func = ->(node) { MySystem.calculate_signature(node) }

merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  signature_generator: my_signature_func,
)
```

## 🔧 Basic Usage

### Simple Merge

The most basic usage merges two Ruby files:

```ruby
require "prism/merge"

template = File.read("template.rb")
destination = File.read("destination.rb")

merger = Prism::Merge::SmartMerger.new(template, destination)
result = merger.merge

File.write("merged.rb", result)
```

### Understanding the Merge

Prism::Merge intelligently combines files by:

1. **Finding Anchors**: Identifies matching sections between files
2. **Detecting Boundaries**: Locates areas where files differ
3. **Resolving Conflicts**: Uses structural signatures to merge differences
4. **Preserving Context**: Maintains comments and freeze blocks

Example:

```ruby
# template.rb
VERSION = "2.0.0"

def greet(name)
  puts "Hello, #{name}!"
end

# destination.rb
VERSION = "1.0.0"

def greet(name)
  puts "Hello, #{name}!"
end

def custom_method
  # This is destination-only
end

# After merge:
# - VERSION from template (2.0.0) replaces destination (1.0.0)
# - greet method matches, template version kept
# - custom_method is preserved (destination-only)
```

### How Prism::Merge Compares to Other Merge Strategies

Prism::Merge uses a **single-pass, AST-aware** algorithm that differs fundamentally from line-based merge tools like `git merge` and IDE smart merges:

| Aspect | Git Merge (3-way) | IDE Smart Merge | Prism::Merge |
|--------|-------------------|-----------------|--------------|
| **Input** | 3 files (base, ours, theirs) | 2-3 files | 2 files (template, destination) |
| **Unit of comparison** | Lines of text | Lines + some syntax awareness | AST nodes (Ruby structures) |
| **Passes** | Multi-pass (LCS algorithm) | Multi-pass | Single-pass with anchors |
| **Conflict handling** | Manual resolution with markers (`<<<<<<<`) | Interactive resolution | Automatic via signature matching |
| **Language awareness** | None (text-only) | Basic (indentation, brackets) | Full Ruby AST understanding |
| **Comment handling** | Treated as text | Treated as text | Attached to relevant nodes |
| **Structural matching** | Line equality only | Line + heuristics | Node signatures (type + identifier) |
| **Recursive merge** | No | Sometimes | Yes (class/module bodies) |
| **Freeze blocks** | No | No | Yes (preserve destination sections) |

#### Key Differences Explained

**Git Merge (3-way merge):**

- Requires a common ancestor (base) to detect changes from each side
- Uses Longest Common Subsequence (LCS) algorithm in multiple passes
- Produces conflict markers when both sides modify the same lines
- Language-agnostic: treats Ruby, Python, and prose identically

**IDE Smart Merge:**

- Often uses 3-way merge as foundation
- Adds heuristics for common patterns (moved blocks, reformatting)
- May understand basic syntax for better conflict detection
- Still fundamentally line-based with enhancements

**Prism::Merge:**

- Uses 2 files: template (source of truth) and destination (customized version)
- Single-pass algorithm that builds a timeline of anchors (matches) and boundaries (differences)
- Matches by **structural signature** (e.g., `[:def, :method_name]`), not line content
- Automatically resolves conflicts based on configurable preference
- Never produces conflict markers - always produces valid, runnable Ruby

#### When to Use Each

| Scenario | Best Tool |
|----------|-----------|
| Merging git branches with divergent changes | Git Merge |
| Resolving complex conflicts interactively | IDE Smart Merge |
| Updating project files from a template | **Prism::Merge** |
| Maintaining customizations across template updates | **Prism::Merge** |
| Merging non-Ruby files | Git Merge / IDE |

### With Debug Information

Get detailed information about merge decisions:

```ruby
merger = Prism::Merge::SmartMerger.new(template, destination)
debug_result = merger.merge_with_debug

puts debug_result[:content]      # Final merged content
puts debug_result[:statistics]   # Decision counts
puts debug_result[:debug]        # Line-by-line provenance
```

The debug output shows:

```ruby
debug_result[:statistics]
# => {
#   kept_template: 42,        # Lines from template (no conflict)
#   kept_destination: 8,      # Lines from destination (no conflict)
#   replaced: 5,              # Template replaced matching destination
#   appended: 3,              # Destination-only content added
#   freeze_block: 2           # Lines from freeze blocks
# }
```

### Error Handling

Prism::Merge raises exceptions when files have syntax errors:

```ruby
begin
  merger = Prism::Merge::SmartMerger.new(template, destination)
  result = merger.merge
rescue Prism::Merge::TemplateParseError => e
  puts "Template has syntax errors"
  puts "Content: #{e.content}"
  puts "Parse errors: #{e.parse_result.errors}"
rescue Prism::Merge::DestinationParseError => e
  puts "Destination has syntax errors"
  puts "Content: #{e.content}"
  puts "Parse errors: #{e.parse_result.errors}"
end
```

### Validating Before Merge

Check if files are valid before attempting a merge:

```ruby
template_analysis = Prism::Merge::FileAnalysis.new(template_content)
dest_analysis = Prism::Merge::FileAnalysis.new(dest_content)

if template_analysis.valid? && dest_analysis.valid?
  merger = Prism::Merge::SmartMerger.new(template_content, dest_content)
  result = merger.merge
else
  puts "Files have syntax errors" unless template_analysis.valid?
  puts "Cannot merge"
end
```

### Working with Freeze Blocks

Protect custom sections from template updates:

```ruby
# destination.rb
class MyApp
  # prism-merge:freeze
  CUSTOM_CONFIG = {
    api_key: ENV.fetch("API_KEY"),
    endpoint: "https://custom.example.com",
  }
  # prism-merge:unfreeze

  VERSION = "1.0.0"
end

# template.rb
class MyApp
  CUSTOM_CONFIG = {}  # Template wants to reset this

  VERSION = "2.0.0"
end

# Merge with default freeze token
merger = Prism::Merge::SmartMerger.new(template, destination)
result = merger.merge

# Or use a custom freeze token if your project uses a different convention
merger = Prism::Merge::SmartMerger.new(
  template,
  destination,
  freeze_token: "kettle-dev",  # for kettle-dev projects
)
result = merger.merge

# After merge, CUSTOM_CONFIG keeps destination values
# but VERSION is updated to 2.0.0
```

### Advanced: Inspect Merge Components

For debugging or understanding the merge process:

```ruby
# Analyze files separately
template_analysis = Prism::Merge::FileAnalysis.new(template)
dest_analysis = Prism::Merge::FileAnalysis.new(destination)

puts "Template statements: #{template_analysis.statements.length}"
puts "Template freeze blocks: #{template_analysis.freeze_blocks.length}"

# See what anchors and boundaries are found
aligner = Prism::Merge::FileAligner.new(template_analysis, dest_analysis)
boundaries = aligner.align

puts "Anchors (matching sections): #{aligner.anchors.length}"
aligner.anchors.each do |anchor|
  puts "  Lines #{anchor.template_start}-#{anchor.template_end} match"
end

puts "Boundaries (differences): #{boundaries.length}"
boundaries.each do |boundary|
  puts "  Template #{boundary.template_range} vs Dest #{boundary.dest_range}"
end
```

### Integration Example

Use Prism::Merge in your own templating system:

```ruby
class MyTemplateEngine
  def merge_ruby_file(template_path, destination_path)
    template = File.read(template_path)
    destination = File.exist?(destination_path) ? File.read(destination_path) : ""

    merger = Prism::Merge::SmartMerger.new(template, destination)
    merged_content = merger.merge

    File.write(destination_path, merged_content)

    # Return statistics for reporting
    debug_result = merger.merge_with_debug
    debug_result[:statistics]
  rescue Prism::Merge::Error => e
    puts "Merge failed: #{e.message}"
    # Fall back to template only
    File.write(destination_path, template)
    nil
  end
end
```

### Testing Your Merges

Example RSpec test:

```ruby
require "prism/merge"

RSpec.describe("Ruby file merging") do
  it "updates VERSION from template" do
    template = <<~RUBY
      VERSION = "2.0.0"
      def hello; end
    RUBY

    destination = <<~RUBY
      VERSION = "1.0.0"
      def hello; end
      def custom; end
    RUBY

    merger = Prism::Merge::SmartMerger.new(template, destination)
    result = merger.merge

    # Template version wins
    expect(result).to(include('VERSION = "2.0.0"'))
    # Destination-only method preserved
    expect(result).to(include("def custom"))
  end

  it "preserves freeze blocks" do
    template = <<~RUBY
      CONFIG = {}
    RUBY

    destination = <<~RUBY
      # prism-merge:freeze
      CONFIG = { key: "secret" }
      # prism-merge:unfreeze
    RUBY

    merger = Prism::Merge::SmartMerger.new(template, destination)
    result = merger.merge

    # Freeze block content preserved
    expect(result).to(include('CONFIG = { key: "secret" }'))
  end

  it "works with custom freeze tokens" do
    template = <<~RUBY
      CONFIG = {}
    RUBY

    destination = <<~RUBY
      # my-app:freeze
      CONFIG = { key: "secret" }
      # my-app:unfreeze
    RUBY

    merger = Prism::Merge::SmartMerger.new(
      template,
      destination,
      freeze_token: "my-app",  # Match your project's freeze token
    )
    result = merger.merge

    # Freeze block content preserved
    expect(result).to(include('CONFIG = { key: "secret" }'))
  end
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
spec.add_dependency("prism-merge", "~> 7.0")
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
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Prism::Merge-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://clickgems.clickhouse.com/dashboard/prism-merge
[⛳️name-img]: https://img.shields.io/badge/name-prism--merge-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/prism-merge
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-prism-merge?utm_source=rubygems-prism-merge&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/prism-merge
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/prism-merge
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=GitHub&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://clickgems.clickhouse.com/dashboard/prism-merge
[👽dl-ranki]: https://img.shields.io/gem/dt/prism-merge.svg
[👽version]: https://clickgems.clickhouse.com/dashboard/prism-merge
[👽versioni]: https://img.shields.io/gem/v/prism-merge.svg
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
[🧮kloc-img]: https://img.shields.io/badge/KLOC-4.246-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
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
[🚎yard-current]: http://rubydoc.info/gems/prism-merge
[🚎yard-head]: https://prism-merge.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
