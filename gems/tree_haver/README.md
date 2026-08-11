<a href="https://github.com/structuredmerge"><img alt="structuredmerge Logo by GitHub" src="https://github.com/structuredmerge.png?size=192" width="12%" align="right"/></a> <a href="https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver"><img alt="tree_haver Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/structuredmerge/structuredmerge-ruby/tree_haver/avatar-128px.svg" width="12%" align="right"/></a>

# 🌴 TreeHaver

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

TreeHaver is a cross-Ruby adapter for the [tree-sitter](https://tree-sitter.github.io/tree-sitter/), [Citrus][citrus], and [Parslet][parslet] parsing libraries and other dedicated parsing tools that works seamlessly across MRI Ruby, JRuby, and TruffleRuby. It provides a unified API for parsing source code using grammars, regardless of your Ruby implementation.

### The Adapter Pattern: Like Faraday, but for Parsing

If you've used [Faraday](https://github.com/lostisland/faraday), [multi\_json](https://github.com/intridea/multi_json), or [multi\_xml](https://github.com/sferik/multi_xml), you'll feel right at home with TreeHaver. These gems share a common philosophy:

| Gem             | Unified API for | Backend Examples                                                          |
|-----------------|-----------------|---------------------------------------------------------------------------|
| **Faraday**     | HTTP requests   | Net::HTTP, Typhoeus, Patron, Excon                                        |
| **multi\_json** | JSON parsing    | Oj, Yajl, JSON gem                                                        |
| **multi\_xml**  | XML parsing     | Nokogiri, LibXML, Ox                                                      |
| **TreeHaver**   | Code parsing    | TSLP, MRI, Rust, FFI, Java, Prism, Psych, Commonmarker, Markly, RBS, Citrus, Parslet, Kaitai |

**Learn once, write anywhere.**

**Write once, run anywhere.**

Just as Faraday lets you swap HTTP adapters without changing your code, TreeHaver lets merge providers report and select parsing backends through one registry. The high-level StructuredMerge providers default to the tree-sitter language-pack path when it supports the requested language, while the lower-level `TreeHaver::Parser` facade can still use native tree-sitter adapters and Ruby parser backends directly.

```ruby
# Your code stays the same regardless of backend
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Language.from_library("/path/to/grammar.so")
tree = parser.parse(source_code)

# TreeHaver::Parser automatically picks the best available parser facade backend:
# - MRI: ruby_tree_sitter, tree_stump, ffi, prism, psych, citrus, parslet
# - JRuby: java-tree-sitter / jtreesitter, ffi, prism, psych, citrus, parslet
# - TruffleRuby: prism, psych, citrus, parslet
#   (the FFI tree-sitter adapter is not used on TruffleRuby because of struct-by-value limits)
```

### Key Features

- **Universal Ruby Support**: Works on MRI Ruby, JRuby, and TruffleRuby
- **Backend Registry** - Choose the right backend for your needs:
    - **Tree-sitter Backends** (high-performance, incremental parsing):
        - **Tree-sitter Language Pack (TSLP)**: Default provider path for StructuredMerge language-family gems that use `tree-sitter-language-pack`
        - **MRI Backend**: Leverages [`ruby_tree_sitter`][ruby_tree_sitter] gem (C extension, fastest on MRI)
        - **Rust Backend**: Uses [`tree_stump`][tree_stump] gem (Rust with precompiled binaries)
            - **Note**: Use `tree_stump` v0.2.0 or newer (fixes are released).
        - **FFI Backend**: Pure Ruby FFI bindings to `libtree-sitter` (JRuby only; TruffleRuby's FFI doesn't support tree-sitter's struct-by-value returns)
        - **Java Backend**: Native Java integration for JRuby with [`java-tree-sitter`](https://github.com/tree-sitter/java-tree-sitter) / [`jtreesitter`][jtreesitter] grammar JARs
    - **Language-Specific Backends** (native parser integration):
        - **Prism Backend**: Ruby's official parser ([Prism][prism], stdlib in Ruby 3.4+)
        - **Psych Backend**: Ruby's YAML parser ([Psych][psych], stdlib)
        - **Commonmarker Backend**: Fast Markdown parser ([Commonmarker][commonmarker], comrak Rust)
        - **Markly Backend**: GitHub Flavored Markdown ([Markly][markly], cmark-gfm C)
        - **RBS Backend**: Official RBS parser integration registered by `rbs-merge`
    - **Pure Ruby Provider Backends**:
        - **Citrus Backend**: Pure Ruby PEG parsing via [`citrus`][citrus] (no native dependencies)
        - **Parslet Backend**: Pure Ruby PEG parsing via [`parslet`][parslet] (no native dependencies)
    - **Binary Schema Support**:
        - **Kaitai Struct Backend**: Backend reference and capability profile for binary schema analysis
- **Automatic Backend Selection**: Intelligently selects the best backend for your Ruby implementation
- **Language Agnostic**: Parse any language - Ruby, Markdown, YAML, JSON, Bash, TOML, JavaScript, etc.
- **Grammar Discovery**: Built-in `GrammarFinder` utility for registration-first tree-sitter grammar resolution
- **Unified Position API**: Consistent `start_line`, `end_line`, `source_position` across all backends
- **Thread-Safe**: Built-in language registry with thread-safe caching
- **Minimal API Surface**: Simple, focused API that covers the most common use cases

### Backend Requirements

TreeHaver has minimal dependencies and automatically selects the best backend for your Ruby implementation. Each backend has specific version requirements:

#### MRI Backend (ruby\_tree\_sitter, C extensions)

**Requires `ruby_tree_sitter` v2.0+**

TreeHaver normalizes backend failures behind `TreeHaver::Error` subclasses, which inherit from `StandardError`.

**Exception Mapping**: TreeHaver catches `TreeSitter::TreeSitterError` and its subclasses where the MRI adapter exposes them, converting them to `TreeHaver::NotAvailable` while preserving the original error message. This provides a consistent exception API across backends:

| ruby\_tree\_sitter Exception      | TreeHaver Exception       | When It Occurs                               |
|-----------------------------------|---------------------------|----------------------------------------------|
| `TreeSitter::ParserNotFoundError` | `TreeHaver::NotAvailable` | Parser library file cannot be loaded         |
| `TreeSitter::LanguageLoadError`   | `TreeHaver::NotAvailable` | Language symbol loads but returns nothing    |
| `TreeSitter::SymbolNotFoundError` | `TreeHaver::NotAvailable` | Symbol not found in library                  |
| `TreeSitter::ParserVersionError`  | `TreeHaver::NotAvailable` | Parser version incompatible with tree-sitter |
| `TreeSitter::QueryCreationError`  | `TreeHaver::NotAvailable` | Query creation fails                         |

```ruby
# MRI tree-sitter backend
gem "ruby_tree_sitter", "~> 2.0", require: false
```

#### Rust Backend (tree\_stump)

**MRI Ruby only** - Does not work on JRuby or TruffleRuby.

The Rust backend uses [tree\_stump][tree_stump], which is a Rust native extension built with [magnus](https://github.com/matsadler/magnus) and [rb-sys](https://github.com/oxidize-rb/rb-sys). These libraries are only compatible with MRI Ruby's C API.

- **JRuby**: Cannot load native `.so` extensions (runs on JVM)
- **TruffleRuby**: magnus/rb-sys are incompatible with TruffleRuby's C API emulation

```ruby
# Rust tree-sitter backend (MRI only)
gem "tree_stump", "~> 0.2.0"
```

#### FFI Backend

**MRI and JRuby only** - Does not work on TruffleRuby.

Requires the `ffi` gem and a system installation of `libtree-sitter`.

- **TruffleRuby**: TruffleRuby's FFI implementation doesn't support `STRUCT_BY_VALUE` return types, which tree-sitter's C API uses for functions like `ts_tree_root_node` and `ts_node_child`.

```ruby
# Add to your Gemfile for FFI backend (MRI and JRuby)
gem "ffi", ">= 1.15", "< 2.0"
```

```bash
# Install libtree-sitter on your system:
# macOS
brew install tree-sitter

# Ubuntu/Debian
apt-get install libtree-sitter0 libtree-sitter-dev

# Fedora
dnf install tree-sitter tree-sitter-devel
```

#### Citrus Backend

Pure Ruby PEG parser with no native dependencies:

```ruby
# Add to your Gemfile for Citrus backend
gem "citrus", "~> 3.0"
```

#### Parslet Backend

Pure Ruby PEG parser with no native dependencies:

```ruby
# Add to your Gemfile for Parslet backend
gem "parslet", "~> 2.0"
```

#### Java Backend (JRuby only)

**Requires jtreesitter \>= 0.26.0** from Maven Central. Older versions are not supported due to breaking API changes.

```ruby
# No gem dependency - uses JRuby's built-in Java integration
# Download the JAR:
# curl -L -o jtreesitter-0.26.0.jar \
#   "https://repo1.maven.org/maven2/io/github/tree-sitter/jtreesitter/0.26.0/jtreesitter-0.26.0.jar"

# Set environment variable:
# export TREE_SITTER_JAVA_JARS_DIR=/path/to/jars
```

**Also requires**:

- Tree-sitter runtime library (`libtree-sitter.so`) version 0.26+ (must match jtreesitter version)
- Grammar `.so` files built against tree-sitter 0.26+ (or rebuilt with `tree-sitter generate`)

### Version Requirements for Tree-Sitter Backends

#### tree-sitter Runtime Library

All tree-sitter backends (MRI, Rust, FFI, Java) require the tree-sitter runtime library. **Version 0.26+ is required** for the Java backend (to match jtreesitter 0.26.0). Other backends may work with 0.24+, but 0.26+ is recommended for consistency.

```bash
# Check your tree-sitter version
tree-sitter --version  # Should be 0.26.0 or newer for Java backend

# macOS
brew install tree-sitter

# Ubuntu/Debian
apt-get install libtree-sitter0 libtree-sitter-dev

# Fedora
dnf install tree-sitter tree-sitter-devel
```

#### jtreesitter (Java Backend)

**The Java backend requires jtreesitter \>= 0.26.0.** This version introduced breaking API changes:

- `Parser.parse()` returns `Optional<Tree>` instead of `Tree`
- `Tree.getRootNode()` returns `Node` directly (not `Optional<Node>`)
- `Node.getChild()`, `getParent()`, `getNextSibling()`, `getPrevSibling()` return `Optional<Node>`
- `Language.load(name)` was removed; use `SymbolLookup` API instead
  Older versions of jtreesitter are **NOT supported**.

```bash
# Download jtreesitter 0.26.0 from Maven Central
curl -L -o jtreesitter-0.26.0.jar \
  "https://repo1.maven.org/maven2/io/github/tree-sitter/jtreesitter/0.26.0/jtreesitter-0.26.0.jar"

# Or use the provided setup script
bin/setup-jtreesitter
```

Set the environment variable to point to your JAR directory:

```bash
export TREE_SITTER_JAVA_JARS_DIR=/path/to/jars
```

#### Grammar ABI Compatibility

**CRITICAL**: Grammars must be built against a compatible tree-sitter version.

Tree-sitter 0.24+ changed how language ABI versions are reported (from `ts_language_version()` to `ts_language_abi_version()`). For the Java backend with jtreesitter 0.26.0, grammars must be built against tree-sitter 0.26+. If you get errors like:

    Failed to load tree_sitter_toml
    Version mismatch detected: The grammar was built against tree-sitter < 0.26

You need to rebuild the grammar from source:

```bash
# Use the provided build script
bin/build-grammar toml

# Or manually:
git clone https://github.com/tree-sitter-grammars/tree-sitter-toml
cd tree-sitter-toml
tree-sitter generate  # Regenerates parser.c for your tree-sitter version
cc -shared -fPIC -o libtree-sitter-toml.so src/parser.c src/scanner.c -I src
```

**Grammar sources for common languages:**

| Language | Repository                                       |
|----------|--------------------------------------------------|
| TOML     | [tree-sitter-grammars/tree-sitter-toml][ts-toml] |
| JSON     | [tree-sitter/tree-sitter-json][ts-json]          |
| JSONC    | [WhyNotHugo/tree-sitter-jsonc][ts-jsonc]         |
| Bash     | [tree-sitter/tree-sitter-bash][ts-bash]          |

#### TruffleRuby Limitations

TruffleRuby has **no working tree-sitter backend**:

- **FFI**: TruffleRuby's FFI doesn't support `STRUCT_BY_VALUE` return types (used by `ts_tree_root_node`, `ts_node_child`, etc.)
- **MRI/Rust**: C and Rust extensions require MRI's C API internals (`RBasic.flags`, `rb_gc_writebarrier`, etc.) that TruffleRuby doesn't expose
  TruffleRuby users should use: **Prism** (Ruby), **Psych** (YAML), **Citrus/Parslet** (e.g., TOML via toml-rb/toml), or potentially **Commonmarker/Markly** (Markdown).

#### JRuby Limitations

JRuby runs on the JVM and **cannot load native `.so` extensions via Ruby's C API**:

- **MRI/Rust**: C and Rust extensions simply cannot be loaded
- **FFI**: Works\! JRuby has excellent FFI support
- **Java**: Works\! The Java backend uses jtreesitter (requires \>= 0.26.0)
  JRuby users should use: **Java backend** (best performance, full API) or **FFI backend** for tree-sitter, plus **Prism**, **Psych**, **Citrus/Parslet** for other formats.

### Why TreeHaver?

tree-sitter is a powerful parser generator that creates incremental parsers for many programming languages. However, integrating it into Ruby applications can be challenging:

- MRI-based C extensions don't work on JRuby
- FFI-based solutions may not be optimal for MRI
- Managing different backends for different Ruby implementations is cumbersome
  TreeHaver solves these problems by providing a unified API that automatically selects the appropriate backend for your Ruby implementation, allowing you to write code once and run it anywhere.

### Comparison with Other Ruby AST / Parser Bindings

| Feature                   | [tree\_haver][📜src-gh] (this gem)              | [ruby\_tree\_sitter][ruby_tree_sitter] | [tree\_stump][tree_stump] | [citrus][citrus] | [parslet][parslet] |
|---------------------------|-------------------------------------------------|----------------------------------------|---------------------------|------------------|--------------------|
| **MRI Ruby**              | ✅ Yes                                           | ✅ Yes                                  | ✅ Yes                     | ✅ Yes            | ✅ Yes              |
| **JRuby**                 | ✅ Yes (FFI, Java, Citrus, or Parslet backend)   | ❌ No                                   | ❌ No                      | ✅ Yes            | ✅ Yes              |
| **TruffleRuby**           | ✅ Yes (FFI, Citrus, or Parslet)                 | ❌ No                                   | ❓ Unknown                 | ✅ Yes            | ✅ Yes              |
| **Backend**               | Multi (MRI C, Rust, FFI, Java, Citrus, Parslet) | C extension only                       | Rust extension            | Pure Ruby        | Pure Ruby          |
| **Incremental Parsing**   | ✅ Via MRI C/Rust/Java backend                   | ✅ Yes                                  | ✅ Yes                     | ❌ No             | ❌ No               |
| **Query API**             | ⚡ Via MRI/Rust/Java backend                     | ✅ Yes                                  | ✅ Yes                     | ❌ No             | ❌ No               |
| **Grammar Discovery**     | ✅ Built-in `GrammarFinder`                      | ❌ Manual                               | ❌ Manual                  | ❌ Manual         | ❌ Manual           |
| **Security Validations**  | ✅ `PathValidator`                               | ❌ No                                   | ❌ No                      | ❌ No             | ❌ No               |
| **Language Registration** | ✅ Thread-safe registry                          | ❌ No                                   | ❌ No                      | ❌ No             | ❌ No               |
| **Native Performance**    | ⚡ Backend-dependent                             | ✅ Native C                             | ✅ Native Rust             | ❌ Pure Ruby      | ❌ Pure Ruby        |
| **Precompiled Binaries**  | ⚡ Via Rust backend                              | ✅ Yes                                  | ✅ Yes                     | ✅ Pure Ruby      | ✅ Pure Ruby        |
| **Zero Native Deps**      | ⚡ Via Citrus/Parslet backend                    | ❌ No                                   | ❌ No                      | ✅ Yes            | ✅ Yes              |
| **Minimum Ruby**          | 3.2+                                            | 3.0+                                   | 3.1+                      | 0+               | 0+                 |

**Note:** Java backend works with grammar `.so` files built against tree-sitter 0.24+. The grammars must be rebuilt with `tree-sitter generate` if they were compiled against older tree-sitter versions. FFI is recommended for JRuby as it's easier to set up.

**Note:** TreeHaver can use `ruby_tree_sitter` (MRI) or `tree_stump` (MRI) as backends, or `java-tree-sitter` / `jtreesitter` \>= 0.26.0 ([docs](https://tree-sitter.github.io/java-tree-sitter/), [maven][jtreesitter], [source](https://github.com/tree-sitter/java-tree-sitter), JRuby), or FFI on any backend, giving you TreeHaver's unified API, grammar discovery, and security features, plus full access to incremental parsing when using those backends.

**Note:** Use `tree_stump` v0.2.0 or newer (fixes are released).

#### When to Use Each

**Choose TreeHaver when:**

- You need JRuby or TruffleRuby support
- You're building a library that should work across Ruby implementations
- You want automatic grammar discovery and security validations
- You want flexibility to switch backends without code changes
- You need incremental parsing with a unified API

**Choose ruby\_tree\_sitter directly when:**

- You only target MRI Ruby
- You need the full Query API without abstraction
- You want the most battle-tested C bindings
- You don't need TreeHaver's grammar discovery

**Choose tree\_stump directly when:**

- You only target MRI Ruby
- You prefer Rust-based native extensions
- You want precompiled binaries without system dependencies
- You don't need TreeHaver's grammar discovery
- **Note:** Use `tree_stump` v0.2.0 or newer (fixes are released).

**Choose citrus or parslet directly when:**

- You need zero native dependencies (pure Ruby)
- You're using a Citrus or Parslet grammar (not tree-sitter grammars)
- Performance is less critical than portability
- You don't need TreeHaver's unified API

[citrus]: https://github.com/mjackson/citrus
[parslet]: https://github.com/kschiess/parslet
[ruby_tree_sitter]: https://github.com/Faveod/ruby-tree-sitter
[tree_stump]: https://github.com/joker1007/tree_stump
[jtreesitter]: https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter
[prism]: https://github.com/ruby/prism
[psych]: https://github.com/ruby/psych
[commonmarker]: https://github.com/gjtorikian/commonmarker
[markly]: https://github.com/ioquatix/markly
[ts-toml]: https://github.com/tree-sitter-grammars/tree-sitter-toml
[ts-json]: https://github.com/tree-sitter/tree-sitter-json
[ts-jsonc]: https://gitlab.com/WhyNotHugo/tree-sitter-jsonc
[ts-bash]: https://github.com/tree-sitter/tree-sitter-bash

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
bundle add tree_haver
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install tree_haver
```

## ⚙️ Configuration

### Available Backends

TreeHaver exposes a backend registry for parser facades, language-family providers, and binary schema support. The high-level StructuredMerge providers default to `tslp` / `kreuzberg-language-pack` when the language pack supports the requested format; the low-level `TreeHaver::Parser` facade uses `auto` to select among parser modules that expose the Parser/Language/Tree API.

#### Tree-sitter Backends (Universal Parsing)

| Backend | Description | Performance | Portability |
|---------|-------------|-------------|-------------|
| **TSLP** | `tree-sitter-language-pack`; default StructuredMerge provider path | Fast | Universal where the gem supports the language |
| **Kreuzberg Language Pack** | Stable provider id alias used by StructuredMerge family gems | Fast | Universal where `tree-sitter-language-pack` is available |
| **Auto** | Auto-selects the best `TreeHaver::Parser` facade backend | Varies | Universal |
| **MRI** | C extension via ruby\_tree\_sitter | Fastest | MRI only |
| **Rust** | Precompiled via tree\_stump | Very fast | MRI only |
| **FFI** | Dynamic linking via FFI | Fast | MRI/JRuby where `libtree-sitter` is available |
| **Java** | JNI bindings (jtreesitter \>= 0.26.0) | Very fast | JRuby only |

#### Language-Specific Backends (Native Parser Integration)

| Backend | Description | Performance | Portability |
|---------|-------------|-------------|-------------|
| **Prism** | Ruby's official parser | Very fast | Universal |
| **Psych** | Ruby's YAML parser (stdlib) | Very fast | Universal |
| **Commonmarker** | Markdown via comrak (Rust) | Very fast | MRI/JRuby/TruffleRuby where the gem is available |
| **Markly** | GFM via cmark-gfm (C) | Very fast | MRI/JRuby/TruffleRuby where the gem is available |
| **RBS** | Official RBS parser integration | Fast | Universal where the `rbs` gem is available |
| **Citrus** | Pure Ruby parsing | Slower | Universal |
| **Parslet** | Pure Ruby parsing | Slower | Universal |

#### Binary Schema Support

| Backend | Description | Performance | Portability |
|---------|-------------|-------------|-------------|
| **Kaitai Struct** | Backend reference and feature profile for binary schema analysis | Varies | Universal once a schema adapter is supplied |

**`TreeHaver::Parser` Auto-selection contract:** `:auto` never means
unregistered parser discovery. It selects the first registered TreeHaver backend
module whose availability check passes. Built-in tree-sitter facade priority is
MRI/Rust/FFI on MRI and Java/FFI on JRuby, followed by registered provider
modules such as Prism, Psych, Citrus, and Parslet when those providers have been
registered for the requested language. Explicit backend requests fail closed if
that backend is unavailable or has no parser registered for the requested
language.

**Known Issues:**

- \*MRI + Bash: ABI incompatibility (use FFI instead)
- \*Rust + Bash: Version mismatch (use FFI instead)
  **Backend Requirements:**

```ruby
# Tree-sitter backends
gem "tree-sitter-language-pack"      # TSLP / Kreuzberg language-pack provider
gem "ruby_tree_sitter", "~> 2.0"  # MRI backend
gem "tree_stump"                   # Rust backend
gem "ffi", ">= 1.15", "< 2.0"     # FFI backend
# Java backend: no gem required (uses JRuby's built-in JNI)

# Language-specific backends
gem "prism", "~> 1.0"              # Ruby parsing (stdlib in Ruby 3.4+)
# Psych: no gem required (Ruby stdlib)
gem "commonmarker", ">= 0.23"      # Markdown parsing (comrak)
gem "markly", "~> 0.11"            # GFM parsing (cmark-gfm)
gem "rbs"                           # RBS parsing

# Pure Ruby fallbacks
gem "citrus", "~> 3.0"             # Citrus backend
gem "parslet", "~> 2.0"            # Parslet backend
# Plus grammar gems: toml-rb (citrus), toml (parslet), dhall, finitio, etc.
```

**Force Specific Backend:**

```ruby
# Tree-sitter backends
TreeHaver.backend = :tslp   # Force tree-sitter-language-pack where supported
TreeHaver.backend = :mri    # Force MRI backend (ruby_tree_sitter)
TreeHaver.backend = :rust   # Force Rust backend (tree_stump)
TreeHaver.backend = :ffi    # Force FFI backend
TreeHaver.backend = :java   # Force Java backend (JRuby only)

# Language-specific backends
TreeHaver.backend = :prism        # Force Prism (Ruby parsing)
TreeHaver.backend = :psych        # Force Psych (YAML parsing)
TreeHaver.backend = :commonmarker # Force Commonmarker (Markdown)
TreeHaver.backend = :markly       # Force Markly (GFM Markdown)
TreeHaver.backend = :rbs          # Force RBS parser integration
TreeHaver.backend = :citrus       # Force Citrus (Pure Ruby PEG)
TreeHaver.backend = :parslet      # Force Parslet (Pure Ruby PEG)

# Auto-selection (default)
TreeHaver.backend = :auto   # Let TreeHaver choose
```

**Block-based Backend Switching:**

Use `with_backend` to temporarily switch backends for a specific block of code.
This is thread-safe and supports nesting—the previous backend is automatically
restored when the block exits (even if an exception is raised).

```ruby
# Temporarily use a specific backend
TreeHaver.with_backend(:mri) do
  parser = TreeHaver::Parser.new
  tree = parser.parse(source)
  # All operations in this block use the MRI backend
end
# Backend is restored to its previous value here

# Nested blocks work correctly
TreeHaver.with_backend(:rust) do
  # Uses :rust
  TreeHaver.with_backend(:citrus) do
    # Uses :citrus
    parser = TreeHaver::Parser.new
  end
  # Back to :rust
  TreeHaver.with_backend(:parslet) do
    # Uses :parslet
    parser = TreeHaver::Parser.new
  end
  # Back to :rust
end
# Back to original backend
```

This is particularly useful for:

- **Testing**: Test the same code with different backends
- **Performance comparison**: Benchmark different backends
- **Backend-selection scenarios**: Exercise each registered backend explicitly
- **Thread isolation**: Each thread can use a different backend safely

```ruby
# Example: Testing with multiple backends
[:mri, :rust, :citrus, :parslet].each do |backend_name|
  TreeHaver.with_backend(backend_name) do
    parser = TreeHaver::Parser.new
    result = parser.parse(source)
    puts "#{backend_name}: #{result.root_node.type}"
  end
end
```

**Check Backend Capabilities:**

```ruby
TreeHaver.backend              # => :ffi
TreeHaver.backend_module       # => TreeHaver::Backends::FFI
TreeHaver.capabilities         # => { backend: :ffi, parse: true, query: false, ... }
```

For runnable scenario examples, see the implementation-level [examples directory](../../examples/). Those examples are user-level scripts rather than backend-count smoke tests.

### Security Considerations

**⚠️ Loading shared libraries (.so/.dylib/.dll) executes arbitrary native code.**

TreeHaver provides defense-in-depth validations, but you should understand the risks:

#### Attack Vectors Mitigated

TreeHaver's `PathValidator` module protects against:

- **Path traversal**: Paths containing `/../` or `/./` are rejected
- **Null byte injection**: Paths containing null bytes are rejected
- **Non-absolute paths**: Relative paths are rejected to prevent CWD-based attacks
- **Invalid extensions**: Only `.so`, `.dylib`, and `.dll` files are accepted
- **Malicious filenames**: Filenames must match a safe pattern (alphanumeric, hyphens, underscores)
- **Invalid language names**: Language names must be lowercase alphanumeric with underscores
- **Invalid symbol names**: Symbol names must be valid C identifiers

#### Secure Usage

```ruby
# Standard usage - paths from ENV are validated
finder = TreeHaver::GrammarFinder.new(:toml)
path = finder.find_library_path  # Validates ENV path before returning

# Maximum security - only trusted system directories
path = finder.find_library_path_safe  # Ignores ENV, only /usr/lib etc.

# Manual validation
if TreeHaver::PathValidator.safe_library_path?(user_provided_path)
  language = TreeHaver::Language.from_library(user_provided_path)
end

# Get validation errors for debugging
errors = TreeHaver::PathValidator.validation_errors(path)
# => ["Path is not absolute", "Path contains traversal sequence"]
```

#### Trusted Directories

The `find_library_path_safe` method only returns paths in trusted directories.

**Default trusted directories:**

- `/usr/lib`, `/usr/lib64`
- `/usr/lib/x86_64-linux-gnu`, `/usr/lib/aarch64-linux-gnu`
- `/usr/local/lib`
- `/opt/homebrew/lib`, `/opt/local/lib`
  **Adding custom trusted directories:**
  For non-standard installations (Homebrew on Linux, luarocks, mise, asdf, etc.), register additional trusted directories:

```ruby
# Programmatically at application startup
TreeHaver::PathValidator.add_trusted_directory("/home/linuxbrew/.linuxbrew/Cellar")
TreeHaver::PathValidator.add_trusted_directory("~/.local/share/mise/installs/lua")

# Or via environment variable (comma-separated, in your shell profile)
export TREE_HAVER_TRUSTED_DIRS = "/home/linuxbrew/.linuxbrew/Cellar,~/.local/share/mise/installs/lua"
```

**Example: Fedora Silverblue with Homebrew and luarocks**

```bash
# In ~/.bashrc or ~/.zshrc
export TREE_HAVER_TRUSTED_DIRS="/home/linuxbrew/.linuxbrew/Cellar,~/.local/share/mise/installs/lua"

# tree-sitter runtime library
export TREE_SITTER_RUNTIME_LIB=/home/linuxbrew/.linuxbrew/Cellar/tree-sitter/0.26.3/lib/libtree-sitter.so

# Language grammar (luarocks-installed)
export TREE_SITTER_TOML_PATH=~/.local/share/mise/installs/lua/5.4.8/luarocks/lib/luarocks/rocks-5.4/tree-sitter-toml/0.0.31-1/parser/toml.so
```

#### Recommendations

1.  **Production**: Consider using `find_library_path_safe` to ignore ENV overrides
2.  **Development**: Standard `find_library_path` is convenient for testing
3.  **User Input**: Always validate paths before passing to `Language.from_library`
4.  **CI/CD**: Be cautious of ENV vars that could be set by untrusted sources
5.  **Custom installs**: Register trusted directories via `TREE_HAVER_TRUSTED_DIRS` or `add_trusted_directory`

### Backend Selection

TreeHaver can select an available registered backend for you, but you can
override this behavior:

```ruby
# Automatic backend selection (default)
TreeHaver.backend = :auto

# Force a specific backend
TreeHaver.backend = :mri     # Use ruby_tree_sitter (MRI only, C extension)
TreeHaver.backend = :rust    # Use tree_stump (MRI, Rust extension with precompiled binaries)
                             # Note: Use tree_stump v0.2.0 or newer (fixes are released).
TreeHaver.backend = :ffi     # Use FFI bindings (works on MRI and JRuby)
TreeHaver.backend = :java    # Use Java bindings (JRuby only)
TreeHaver.backend = :citrus  # Use Citrus pure Ruby parser
                             # NOTE: Portable, all Ruby implementations
                             # CAVEAT: few major language grammars, but many esoteric grammars
TreeHaver.backend = :parslet # Use Parslet pure Ruby parser
                             # NOTE: Portable, all Ruby implementations
                             # CAVEAT: few major language grammars, but many esoteric grammars
```

**Auto-selection rule:** `:auto` uses the registered backend list and chooses
the first backend module that is allowed by environment configuration and reports
itself available. It does not call parser libraries directly, search for
language-specific fallback parsers outside the registry, or hide an explicit
backend failure by silently switching to a different backend.

**Built-in facade priority on MRI:** MRI → Rust → FFI → Citrus → Parslet

You can also set the backend via environment variable:

```bash
export TREE_HAVER_BACKEND=rust
```

### Backend Registry

TreeHaver provides a `BackendRegistry` module that allows external gems to register their backend availability checkers. This enables dynamic backend detection without hardcoding dependencies.

#### Registering a Backend Availability Checker

External gems (like `commonmarker-merge`, `markly-merge`, `rbs-merge`) can register their availability checker when loaded:

```ruby
# In your gem's backend module
TreeHaver::BackendRegistry.register_availability_checker(:my_backend) do
  # Return true if backend is available
  require "my_backend_gem"
  true
rescue LoadError
  false
end
```

#### Checking Backend Availability

```ruby
# Check if a backend is available
TreeHaver::BackendRegistry.available?(:commonmarker)  # => true/false
TreeHaver::BackendRegistry.available?(:markly)        # => true/false
TreeHaver::BackendRegistry.available?(:rbs)           # => true/false

# Check if a checker is registered
TreeHaver::BackendRegistry.registered?(:my_backend)   # => true/false

# Get all registered backend names
TreeHaver::BackendRegistry.registered_backends        # => [:mri, :rust, :ffi, ...]
```

#### How It Works

1. Built-in backends (MRI, Rust, FFI, Java, Prism, Psych, Citrus, Parslet) automatically register their checkers when loaded
2. External gems register their checkers when their backend module is loaded
3. `TreeHaver::RSpec::DependencyTags` uses the registry to dynamically detect available backends
4. Results are cached for performance (use `clear_cache!` to reset)

#### RSpec Integration

The `BackendRegistry` is used by `TreeHaver::RSpec::DependencyTags` to configure RSpec exclusion filters:

```ruby
# In your spec_helper.rb
require "tree_haver/rspec/dependency_tags"

# Then in specs, use tags to skip tests when backends aren't available
it "requires commonmarker", :commonmarker_backend do
  # This test only runs when commonmarker is available
end

it "requires markly", :markly_backend do
  # This test only runs when markly is available
end
```

### Environment Variables

TreeHaver recognizes several environment variables for configuration:

**Note**: All path-based environment variables are validated before use. Invalid paths are ignored.

#### Security Configuration

- **`TREE_HAVER_TRUSTED_DIRS`**: Comma-separated list of additional trusted directories for grammar libraries

  ```bash
  # For Homebrew on Linux and luarocks
  export TREE_HAVER_TRUSTED_DIRS="/home/linuxbrew/.linuxbrew/Cellar,~/.local/share/mise/installs/lua"
  ```

  Tilde (`~`) is expanded to the user's home directory. Directories listed here are considered safe for `find_library_path_safe`.

#### Core Runtime Library

- **`TREE_SITTER_RUNTIME_LIB`**: Absolute path to the core `libtree-sitter` shared library
  ```bash
  export TREE_SITTER_RUNTIME_LIB=/usr/local/lib/libtree-sitter.so
  ```

If not set, TreeHaver tries these names in order:

- `tree-sitter`
- `libtree-sitter.so.0`
- `libtree-sitter.so`
- `libtree-sitter.dylib`
- `libtree-sitter.dll`

#### Language Symbol Resolution

When loading a language grammar, if you don't specify the `symbol:` parameter, TreeHaver resolves it in this precedence:

1.  **`TREE_SITTER_LANG_SYMBOL`**: Explicit symbol override
2.  Guessed from filename (e.g., `libtree-sitter-toml.so` → `tree_sitter_toml`)
3.  Default fallback (`tree_sitter_toml`)

```bash
export TREE_SITTER_LANG_SYMBOL=tree_sitter_toml
```

#### Language Library Paths

For specific languages, you can set environment variables to point to grammar libraries:

```bash
export TREE_SITTER_TOML_PATH=/usr/local/lib/libtree-sitter-toml.so
export TREE_SITTER_JSON_PATH=/usr/local/lib/libtree-sitter-json.so
```

#### JRuby-Specific: Java Backend Configuration

For the Java backend on JRuby, you need:

1.  **jtreesitter \>= 0.26.0** JAR from Maven Central
2.  **Tree-sitter runtime library** (`libtree-sitter.so`) version 0.26+
3.  **Grammar `.so` files** built against tree-sitter 0.26+

```bash
# Download jtreesitter JAR (or use bin/setup-jtreesitter)
export TREE_SITTER_JAVA_JARS_DIR=/path/to/java-tree-sitter/jars

# Point to tree-sitter runtime (must be 0.26+)
export TREE_SITTER_RUNTIME_LIB=/usr/local/lib/libtree-sitter.so

# Point to grammar libraries (must be built for tree-sitter 0.26+)
export TREE_SITTER_TOML_PATH=/path/to/libtree-sitter-toml.so
```

**Building grammars for Java backend:**

If you get "version mismatch" errors, rebuild the grammar:

```bash
# Use the provided build script
bin/build-grammar toml

# This regenerates parser.c for your tree-sitter version and compiles it
```

For more see [docs](https://tree-sitter.github.io/java-tree-sitter/), [maven][jtreesitter], and [source](https://github.com/tree-sitter/java-tree-sitter).

### Language Registration

Register languages once at application startup for convenient access:

```ruby
# Register a TOML grammar
TreeHaver.register_language(
  :toml,
  path: "/usr/local/lib/libtree-sitter-toml.so",
  symbol: "tree_sitter_toml",  # optional, will be inferred if omitted
)

# Now you can use the convenient helper
language = TreeHaver::Language.toml

# Or still override path/symbol per-call
language = TreeHaver::Language.toml(
  path: "/custom/path/libtree-sitter-toml.so",
)
```

### Grammar Discovery with GrammarFinder

For libraries that need to automatically locate tree-sitter grammars (like the
`*-merge` family of gems), TreeHaver provides the `GrammarFinder` utility
class. It resolves explicit registrations first and then uses
`tree_sitter_language_pack` as the normalized on-demand provisioning path for
tree-sitter grammars. Parser-specific non-tree-sitter backends should be
registered by the owning merge gem rather than hardcoded in TreeHaver.

```ruby
# Create a finder for any language
finder = TreeHaver::GrammarFinder.new(:toml)

# Check if the grammar is available
if finder.available?
  puts "TOML grammar found at: #{finder.find_library_path}"
else
  puts finder.not_found_message
  # => "tree-sitter toml grammar not found. Searched: /.../libtree_sitter_toml.so, ..."
end

# Register the language if available
finder.register! if finder.available?

# Now use the registered language
language = TreeHaver::Language.toml
```

#### Registration Bootstrap

TreeHaver is the shared registry. It is not the owner of parser-family policy.

- Tree-sitter grammars should be normalized through `GrammarFinder` and
  `tree_sitter_language_pack` or an explicit registration.
- Non-tree-sitter backends should be registered by the merge gem that owns
  that parser family.
- Tools that load multiple merge gems should invoke each gem's registration
  bootstrap so TreeHaver sees the full set of available grammars before
  `parser_for` is called.

```ruby
# In a tool that uses several merge gems
require "tree_haver"
require "toml-merge"
require "markdown-merge"

Toml::Merge.register_backend!
Markdown::Merge.register_backend!

parser = TreeHaver.parser_for(:toml)
```

Once those registrations have run, `TreeHaver.parser_for` can resolve any
registered tree-sitter grammar plus any registered backend-specific grammar for
the active backend mode. If a merge depends on a grammar that has not been
registered and cannot be provisioned through `tree_sitter_language_pack`,
TreeHaver raises `TreeHaver::NotAvailable`.

#### GrammarFinder Automatic Derivation

Given just the language name, `GrammarFinder` automatically derives:

| Property         | Derived Value (for `:toml`)                         |
|------------------|-----------------------------------------------------|
| ENV var          | `TREE_SITTER_TOML_PATH`                             |
| Library filename | `libtree_sitter_toml.so` (Linux) or `.dylib` (macOS) |
| Symbol name      | `tree_sitter_toml`                                  |

#### Search Order

`GrammarFinder` searches for grammars in this order:

1.  **Environment variable**: `TREE_SITTER_<LANG>_PATH` (highest priority)
2.  **Existing TreeHaver registration**: previously-registered tree-sitter grammar path
3.  **Extra paths**: explicit paths provided at initialization
4.  **`tree_sitter_language_pack`**: parser API availability through its on-demand grammar loader

#### TSLP Cold-Cache Troubleshooting

`tree_sitter_language_pack` loads bundled grammars on demand. A cold install may
not have a populated shared-library cache before the first parse, so
`GrammarFinder` must not treat cache contents as the source of truth for TSLP
availability.

For TSLP-backed languages, check availability through the TSLP parser API and
then register the language with the TreeHaver TSLP backend:

```ruby
finder = TreeHaver::GrammarFinder.new(:toml)
finder.register! if finder.available?

TreeHaver.with_backend("kreuzberg-language-pack") do
  TreeHaver.parser_for(:toml).parse("title = \"example\"\n")
end
```

If this fails from a cold start, inspect `finder.search_info` and confirm that
the `tree-sitter-language-pack` gem is in the bundle being used. Do not add a
merge-gem parser fallback to hide the failure; fix the TreeHaver registration
or the TSLP grammar binding instead.

#### Usage in \*-merge Gems

The `GrammarFinder` pattern enables clean integration in language-specific
merge gems:

```ruby
# In a substrate merge gem
finder = TreeHaver::GrammarFinder.new(:toml)
finder.register! if finder.available?
```

Parser-specific gems should register their own TreeHaver backend wrappers:

```ruby
# In a TOML parser provider gem
TreeHaver.register_language(
  :toml,
  backend_module: Citrus::Toml::Merge::Backend,
  backend_type: :citrus,
  gem_name: "toml-rb",
)
```

Each gem uses the same API. TreeHaver owns the shared registration surface;
merge gems own parser-specific backend registrations and any explicit bootstrap
hook they expose to register them.

#### Adding Custom Search Paths

For non-standard standalone grammar builds, provide extra search paths:

```ruby
finder = TreeHaver::GrammarFinder.new(:toml, extra_paths: [
  "/opt/custom/lib",
  "/home/user/.local/lib",
])
```

#### Debug Information

Get detailed information about the grammar search:

```ruby
finder = TreeHaver::GrammarFinder.new(:toml)
puts finder.search_info
# => {
#      language: :toml,
#      env_var: "TREE_SITTER_TOML_PATH",
#      env_value: nil,
#      symbol: "tree_sitter_toml",
#      library_filename: "libtree_sitter_toml.so",
#      search_paths: ["/custom/lib/libtree_sitter_toml.so", "/.../tree-sitter-language-pack/..."],
#      found_path: "/.../libtree_sitter_toml.so",
#      available: true
#    }
```

### Checking Capabilities

Different backends may support different features:

```ruby
TreeHaver.capabilities
# => { backend: :mri, query: true, bytes_field: true }
# or
# => { backend: :ffi, parse: true, query: false, bytes_field: true }
# or
# => { backend: :citrus, parse: true, query: false, bytes_field: false }
# or
# => { backend: :parslet, parse: true, query: false, bytes_field: false }
```

### Error Handling Model

TreeHaver does not ship a `TreeSitter::*` compatibility namespace. Use the `TreeHaver::*` API directly, and rescue `TreeHaver::Error` or a more specific subclass when parser setup can fail.

**TreeHaver Exception Hierarchy:**

    StandardError
    └── TreeHaver::Error              # Base error class
        ├── TreeHaver::NotAvailable   # Backend/grammar not available
        └── TreeHaver::BackendConflict # Backend incompatibility detected

**Best Practices:**

1.  **Rescue TreeHaver errors explicitly when backend setup can fail:**

    ```ruby
    begin
      finder = TreeHaver::GrammarFinder.new(:toml)
      finder.register! if finder.available?
      language = TreeHaver::Language.toml
    rescue TreeHaver::NotAvailable => e
      warn("TOML grammar not available: #{e.message}")
      # Select another registered TreeHaver backend explicitly, or fail gracefully
    end
    ```

2.  **Prefer specific handling** for `TreeHaver::NotAvailable` when a backend or grammar is optional.

## 🔧 Basic Usage

### Quick Start

The simplest way to parse code is with `TreeHaver.parser_for`, which handles
language loading, grammar resolution, and backend selection:

```ruby
require "tree_haver"

# Parse TOML - resolves any registered tree-sitter grammar and any registered
# non-tree-sitter backend for the active backend mode
parser = TreeHaver.parser_for(:toml)
tree = parser.parse("[package]\nname = \"my-app\"")

# Parse JSON
parser = TreeHaver.parser_for(:json)
tree = parser.parse('{"key": "value"}')

# Parse Bash
parser = TreeHaver.parser_for(:bash)
tree = parser.parse("#!/bin/bash\necho hello")

# With explicit library path
parser = TreeHaver.parser_for(:toml, library_path: "/custom/path/libtree-sitter-toml.so")

# With explicit Citrus provider configuration
parser = TreeHaver.parser_for(
  :toml,
  citrus_config: {gem_name: "toml-rb", grammar_const: "TomlRB::Document"},
)
```

`TreeHaver.parser_for` handles:

1.  Checking if the language is already registered
2.  Auto-discovering tree-sitter grammar via `GrammarFinder`
3.  Using any registered backend-specific grammar for the active backend
4.  Creating and configuring the parser
5.  Raising `NotAvailable` with a helpful message if nothing works

### Manual Parser Setup

For more control, you can create parsers manually:

TreeHaver works with many languages through its registry of tree-sitter adapters, language-pack providers, native parsers, PEG parsers, and binary schema support. Here are examples for different parsing needs:

#### Parsing with Tree-sitter (Universal Languages)

```ruby
require "tree_haver"

# Load a tree-sitter grammar (works with MRI, Rust, FFI, or Java backend)
language = TreeHaver::Language.from_library(
  "/usr/local/lib/libtree-sitter-toml.so",
  symbol: "tree_sitter_toml",
)

# Create a parser
parser = TreeHaver::Parser.new
parser.language = language

# Parse source code
source = <<~TOML
  [package]
  name = "my-app"
  version = "1.0.0"
TOML

tree = parser.parse(source)

# Access the unified Position API (works across all backends)
root = tree.root_node
puts "Root type: #{root.type}"              # => "document"
puts "Start line: #{root.start_line}"       # => 1 (1-based)
puts "End line: #{root.end_line}"           # => 3
puts "Position: #{root.source_position}"    # => {start_line: 1, end_line: 3, ...}

# Traverse the tree
root.each do |child|
  puts "Child: #{child.type} at line #{child.start_line}"
end
```

#### Parsing Ruby with Prism

```ruby
require "tree_haver"

TreeHaver.backend = :prism
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Backends::Prism::Language.ruby

source = <<~RUBY
  class Example
    def hello
      puts "Hello, world!"
    end
  end
RUBY

tree = parser.parse(source)
root = tree.root_node

# Find all method definitions
def find_methods(node, results = [])
  results << node if node.type == "def_node"
  node.children.each { |child| find_methods(child, results) }
  results
end

methods = find_methods(root)
methods.each do |method_node|
  pos = method_node.source_position
  puts "Method at lines #{pos[:start_line]}-#{pos[:end_line]}"
end
```

#### Parsing YAML with Psych

```ruby
require "tree_haver"

TreeHaver.backend = :psych
parser = TreeHaver::Parser.new
parser.language = TreeHaver::Backends::Psych::Language.yaml

source = <<~YAML
  database:
    host: localhost
    port: 5432
YAML

tree = parser.parse(source)
root = tree.root_node

# Navigate YAML structure
def show_structure(node, indent = 0)
  prefix = "  " * indent
  puts "#{prefix}#{node.type} (line #{node.start_line})"
  node.children.each { |child| show_structure(child, indent + 1) }
end

show_structure(root)
```

#### Parsing Markdown with Commonmarker or Markly

```ruby
require "tree_haver"

# Choose your backend
TreeHaver.backend = :commonmarker  # or :markly for GFM

parser = TreeHaver::Parser.new
parser.language = TreeHaver::Backends::Commonmarker::Language.markdown

source = <<~MARKDOWN
  # My Document

  ## Section

  - Item 1
  - Item 2
MARKDOWN

tree = parser.parse(source)
root = tree.root_node

# Find all headings
def find_headings(node, results = [])
  results << node if node.type == "heading"
  node.children.each { |child| find_headings(child, results) }
  results
end

headings = find_headings(root)
headings.each do |heading|
  level = heading.header_level
  text = heading.children.map(&:text).join
  puts "H#{level}: #{text} (line #{heading.start_line})"
end
```

### Using Language Registration

For cleaner code, register languages at startup:

```ruby
# At application initialization
TreeHaver.register_language(
  :toml,
  path: "/usr/local/lib/libtree-sitter-toml.so",
)

TreeHaver.register_language(
  :json,
  path: "/usr/local/lib/libtree-sitter-json.so",
)

# Later in your code
toml_language = TreeHaver::Language.toml
json_language = TreeHaver::Language.json

parser = TreeHaver::Parser.new
parser.language = toml_language
tree = parser.parse(toml_source)
```

#### Flexible Language Names

The `name` parameter in `register_language` is an arbitrary identifier you choose—it doesn't
need to match the actual language name. The actual grammar identity comes from the `path`
and `symbol` parameters (for tree-sitter) or `grammar_module` (for Citrus/Parslet).

This flexibility is useful for:

- **Aliasing**: Register the same grammar under multiple names
- **Versioning**: Register different grammar versions (e.g., `:ruby_2`, `:ruby_3`)
- **Testing**: Use unique names to avoid collisions between tests
- **Context-specific naming**: Use names that make sense for your application

```ruby
# Register the same TOML grammar under different names for different purposes
TreeHaver.register_language(
  :config_parser,  # Custom name for your app
  path: "/usr/local/lib/libtree-sitter-toml.so",
  symbol: "tree_sitter_toml",
)

TreeHaver.register_language(
  :toml_v1,  # Version-specific name
  path: "/usr/local/lib/libtree-sitter-toml.so",
  symbol: "tree_sitter_toml",
)

# Use your custom names
config_lang = TreeHaver::Language.config_parser
versioned_lang = TreeHaver::Language.toml_v1
```

### Parsing Different Languages

TreeHaver works with any tree-sitter grammar:

```ruby
# Parse Ruby code
ruby_lang = TreeHaver::Language.from_library(
  "/path/to/libtree-sitter-ruby.so",
)
parser = TreeHaver::Parser.new
parser.language = ruby_lang
tree = parser.parse("class Foo; end")

# Parse JavaScript
js_lang = TreeHaver::Language.from_library(
  "/path/to/libtree-sitter-javascript.so",
)
parser.language = js_lang  # Reuse the same parser
tree = parser.parse("const x = 42;")
```

### Walking the AST

TreeHaver provides simple node traversal:

```ruby
tree = parser.parse(source)
root = tree.root_node

# Recursive tree walk
def walk_tree(node, depth = 0)
  puts "#{"  " * depth}#{node.type}"
  node.each { |child| walk_tree(child, depth + 1) }
end

walk_tree(root)
```

### Incremental Parsing

TreeHaver supports incremental parsing when using the MRI or Rust backends. This is a major performance optimization for editors and IDEs that need to re-parse on every keystroke.

```ruby
# Check if current backend supports incremental parsing
if TreeHaver.capabilities[:incremental]
  puts "Incremental parsing is available!"
end

# Initial parse
parser = TreeHaver::Parser.new
parser.language = language
tree = parser.parse_string(nil, "x = 1")

# User edits the source: "x = 1" -> "x = 42"
# Mark the tree as edited (tell tree-sitter what changed)
tree.edit(
  start_byte: 4,           # edit starts at byte 4
  old_end_byte: 5,         # old text "1" ended at byte 5
  new_end_byte: 6,         # new text "42" ends at byte 6
  start_point: {row: 0, column: 4},
  old_end_point: {row: 0, column: 5},
  new_end_point: {row: 0, column: 6},
)

# Re-parse incrementally - tree-sitter reuses unchanged nodes
new_tree = parser.parse_string(tree, "x = 42")
```

**Note:** Incremental parsing requires the MRI (`ruby_tree_sitter`), Rust (`tree_stump`), or Java (`java-tree-sitter` / `jtreesitter`) backend. The FFI, Citrus, and Parslet backends do not support incremental parsing. You can check support with:

```ruby
tree.supports_editing?  # => true if edit() is available
```

### Error Handling

```ruby
begin
  language = TreeHaver::Language.from_library("/path/to/grammar.so")
rescue TreeHaver::NotAvailable => e
  puts "Failed to load grammar: #{e.message}"
end

# Check if a backend is available
if TreeHaver.backend_module.nil?
  puts "No TreeHaver backend is available!"
  puts "Install tree-sitter-language-pack, ruby_tree_sitter, tree_stump, ffi with libtree-sitter, or a Ruby parser backend such as prism, psych, citrus, or parslet"
end
```

### Platform-Specific Examples

#### MRI Ruby

On MRI, TreeHaver uses `ruby_tree_sitter` by default:

```ruby
# Gemfile
gem "tree_haver"
gem "ruby_tree_sitter"  # MRI backend

# Code - no changes needed, TreeHaver auto-selects MRI backend
parser = TreeHaver::Parser.new
```

#### JRuby

On JRuby, TreeHaver can use the FFI backend, Java backend, Citrus backend, or Parslet backend:

##### Option 1: FFI Backend (recommended for tree-sitter grammars)

```ruby
# Gemfile
gem "tree_haver"
gem "ffi"  # Required for FFI backend

# Ensure libtree-sitter is installed on your system
# On macOS with Homebrew:
#   brew install tree-sitter

# On Ubuntu/Debian:
#   sudo apt-get install libtree-sitter0 libtree-sitter-dev

# Code - TreeHaver auto-selects FFI backend on JRuby
parser = TreeHaver::Parser.new
```

##### Option 2: Java Backend (native JVM performance)

```bash
# 1. Download java-tree-sitter JAR from Maven Central
mkdir -p vendor/jars
curl -fSL -o vendor/jars/jtreesitter-0.26.0.jar \
  "https://repo1.maven.org/maven2/io/github/tree-sitter/jtreesitter/0.26.0/jtreesitter-0.26.0.jar"

# 2. Set environment variables
export CLASSPATH="$(pwd)/vendor/jars:$CLASSPATH"
export LD_LIBRARY_PATH="/path/to/libtree-sitter/lib:$LD_LIBRARY_PATH"

# 3. Run with JRuby (requires Java 22+ for Foreign Function API)
JAVA_OPTS="--enable-native-access=ALL-UNNAMED" jruby your_script.rb
```

```ruby
# Force Java backend
TreeHaver.backend = :java

# Check if Java backend is available
if TreeHaver::Backends::Java.available?
  puts "Java backend is ready!"
  puts TreeHaver.capabilities
  # => { backend: :java, parse: true, query: true, bytes_field: true, incremental: true }
end
```

**⚠️ Java Backend Limitation: Symbol Resolution**

The Java backend uses Java's Foreign Function & Memory (FFM) API which loads libraries in isolation. Unlike the system's dynamic linker (`dlopen`), FFM's `SymbolLookup.or()` chains symbol lookups but doesn't resolve dynamic library dependencies.

This means grammar `.so` files with unresolved references to `libtree-sitter.so` symbols won't load correctly. Most grammars from luarocks, npm, or other sources have these dependencies.

**Recommended approach for JRuby:** Use the **FFI backend**:

```ruby
# On JRuby, use FFI backend (recommended)
TreeHaver.backend = :ffi
```

The FFI backend uses Ruby's FFI gem which relies on the system's dynamic linker, correctly resolving symbol dependencies between `libtree-sitter.so` and grammar libraries.

The Java backend will work with:

- Grammar JARs built specifically for java-tree-sitter / jtreesitter (self-contained, [docs](https://tree-sitter.github.io/java-tree-sitter/), [maven][jtreesitter], [source](https://github.com/tree-sitter/java-tree-sitter))
- Grammar `.so` files that statically link tree-sitter

##### Option 3: Citrus Backend (pure Ruby, portable)

```ruby
# Gemfile
gem "tree_haver"
gem "citrus"  # Pure Ruby parser, zero native dependencies

# Code - Force Citrus backend for maximum portability
TreeHaver.backend = :citrus

# Check if Citrus backend is available
if TreeHaver::Backends::Citrus.available?
  puts "Citrus backend is ready!"
  puts TreeHaver.capabilities
  # => { backend: :citrus, parse: true, query: false, bytes_field: false }
end
```

**⚠️ Citrus Backend Limitations:**

- Uses Citrus grammars (not tree-sitter grammars)
- No incremental parsing support
- No query API
- Pure Ruby performance (slower than native backends)
- Best for: prototyping, environments without native extension support, teaching

##### Option 4: Parslet Backend (pure Ruby, portable)

```ruby
# Gemfile
gem "tree_haver"
gem "parslet"  # Pure Ruby parser, zero native dependencies

# Code - Force Parslet backend for maximum portability
TreeHaver.backend = :parslet

# Check if Parslet backend is available
if TreeHaver::Backends::Parslet.available?
  puts "Parslet backend is ready!"
  puts TreeHaver.capabilities
  # => { backend: :parslet, parse: true, query: false, bytes_field: false }
end
```

**⚠️ Parslet Backend Limitations:**

- Uses Parslet grammars (not tree-sitter grammars)
- No incremental parsing support
- No query API
- Pure Ruby performance (slower than native backends)
- Best for: prototyping, environments without native extension support, teaching

#### TruffleRuby

TruffleRuby can use Ruby-native parser backends such as Prism, Psych, Citrus, or Parslet. The FFI tree-sitter backend is not selected on TruffleRuby because tree-sitter's struct-by-value API is incompatible with the current FFI path.

```ruby
# Use Prism for Ruby source
TreeHaver.backend = :prism

# Or use Psych for YAML
TreeHaver.backend = :psych

# Use Citrus backend for zero native dependencies
TreeHaver.backend = :citrus

# Or use Parslet backend for zero native dependencies
TreeHaver.backend = :parslet
```

### Advanced: Thread-Safe Backend Switching

TreeHaver provides `with_backend` for thread-safe, temporary backend switching. This is
essential for testing, benchmarking, and applications that need different backends in
different contexts.

#### Testing with Multiple Backends

Test the same code path with different backends using `with_backend`:

```ruby
# In your test setup
RSpec.describe("MyParser") do
  # Test with each available backend
  [:mri, :rust, :citrus, :parslet].each do |backend_name|
    context "with #{backend_name} backend" do
      it "parses correctly" do
        TreeHaver.with_backend(backend_name) do
          parser = TreeHaver::Parser.new
          result = parser.parse("x = 42")
          expect(result.root_node.type).to(eq("document"))
        end
        # Backend automatically restored after block
      end
    end
  end
end
```

#### Thread Isolation

Each thread can use a different backend safely—`with_backend` uses thread-local storage:

```ruby
threads = []

threads << Thread.new do
  TreeHaver.with_backend(:mri) do
    # This thread uses MRI backend
    parser = TreeHaver::Parser.new
    100.times { parser.parse("x = 1") }
  end
end

threads << Thread.new do
  TreeHaver.with_backend(:citrus) do
    # This thread uses Citrus backend simultaneously
    parser = TreeHaver::Parser.new
    100.times { parser.parse("x = 1") }
  end
end

threads << Thread.new do
  TreeHaver.with_backend(:parslet) do
    # This thread uses Parslet backend simultaneously
    parser = TreeHaver::Parser.new
    100.times { parser.parse("x = 1") }
  end
end

threads.each(&:join)
```

#### Nested Blocks

`with_backend` supports nesting—inner blocks override outer blocks:

```ruby
TreeHaver.with_backend(:rust) do
  puts TreeHaver.effective_backend  # => :rust

  TreeHaver.with_backend(:citrus) do
    puts TreeHaver.effective_backend  # => :citrus
  end

  TreeHaver.with_backend(:parslet) do
    puts TreeHaver.effective_backend  # => :parslet
  end

  puts TreeHaver.effective_backend  # => :rust (restored)
end
```

#### Explicit Backend Selection Pattern

Try registered TreeHaver backends explicitly when you want controlled provider
selection. Structured merge gems should fail closed when no registered TreeHaver
backend can parse the requested language.

```ruby
def parse_with_backend(source, backend_name)
  TreeHaver.with_backend(backend_name) do
    TreeHaver::Parser.new.tap { |p| p.language = load_language }.parse(source)
  end
end
```

### Complete Real-World Example

Here's a practical example that extracts package names from a TOML file:

```ruby
require "tree_haver"

# Setup
TreeHaver.register_language(
  :toml,
  path: "/usr/local/lib/libtree-sitter-toml.so",
)

def extract_package_name(toml_content)
  # Create parser
  parser = TreeHaver::Parser.new
  parser.language = TreeHaver::Language.toml

  # Parse
  tree = parser.parse(toml_content)
  root = tree.root_node

  # Find [package] table
  root.each do |child|
    next unless child.type == "table"

    child.each do |table_elem|
      if table_elem.type == "pair"
        # Look for name = "..." pair
        key = table_elem.each.first&.type
        # In a real implementation, you'd extract the text value
        # This is simplified for demonstration
      end
    end
  end
end

# Usage
toml = <<~TOML
  [package]
  name = "awesome-app"
  version = "2.0.0"
TOML

package_name = extract_package_name(toml)
```

### 🧪 RSpec Integration

TreeHaver provides shared RSpec helpers for conditional test execution based on dependency availability. This is useful for testing code that uses optional backends.

```ruby
# In your spec_helper.rb
require "tree_haver/rspec"
```

This automatically configures RSpec with exclusion filters for all TreeHaver dependencies. Use tags to conditionally run tests:

```ruby
# Runs only when FFI backend is available
it "parses with FFI", :ffi do
  # ...
end

# Runs only when ruby_tree_sitter gem is available
it "uses MRI backend", :mri_backend do
  # ...
end

# Runs only when tree-sitter-toml grammar works
it "parses TOML", :tree_sitter_toml do
  # ...
end

# Runs only when any markdown backend is available
it "parses markdown", :markdown_backend do
  # ...
end
```

**Available Tags:**

Tags follow a naming convention:

- `*_backend` = TreeHaver backend availability checks (tslp, mri, rust, ffi, java, prism, psych, commonmarker, markly, citrus, parslet, rbs)
- `*_engine` = Ruby engines (mri, jruby, truffleruby)
- `*_grammar` = tree-sitter grammar files (.so)
- `*_parsing` = any parsing capability for a language (combines multiple backends/grammars)
- `*_gem` = specific library gems

| Tag                     | Description                                                               |
|-------------------------|---------------------------------------------------------------------------|
| **Backend Tags**        |                                                                           |
| `:ffi_backend`          | FFI backend available (dynamic check)                                     |
| `:ffi_backend_only`     | FFI backend in isolation (won't trigger MRI check)                        |
| `:mri_backend`          | ruby\_tree\_sitter gem available                                          |
| `:mri_backend_only`     | MRI backend in isolation (won't trigger FFI check)                        |
| `:rust_backend`         | tree\_stump gem available                                                 |
| `:java_backend`         | Java backend available (JRuby + jtreesitter)                              |
| `:prism_backend`        | Prism gem available                                                       |
| `:psych_backend`        | Psych available (stdlib)                                                  |
| `:commonmarker_backend` | commonmarker gem available                                                |
| `:markly_backend`       | markly gem available                                                      |
| `:citrus_backend`       | Citrus gem available                                                      |
| `:parslet_backend`      | Parslet gem available                                                     |
| `:tslp_backend`         | tree-sitter-language-pack available                                       |
| `:rbs_backend`          | RBS gem available (official RBS parser)                                   |
| **Engine Tags**         |                                                                           |
| `:mri_engine`           | Running on MRI (CRuby)                                                    |
| `:jruby_engine`         | Running on JRuby                                                          |
| `:truffleruby_engine`   | Running on TruffleRuby                                                    |
| **Grammar Tags**        |                                                                           |
| `:libtree_sitter`       | libtree-sitter.so is loadable via FFI                                     |
| `:bash_grammar`         | tree-sitter-bash grammar available and parsing works                      |
| `:toml_grammar`         | tree-sitter-toml grammar available and parsing works                      |
| `:json_grammar`         | tree-sitter-json grammar available and parsing works                      |
| `:jsonc_grammar`        | tree-sitter-jsonc grammar available and parsing works                     |
| `:rbs_grammar`          | tree-sitter-rbs grammar available and parsing works                       |
| **Parsing Tags**        |                                                                           |
| `:toml_parsing`         | Any TOML parser available (tree-sitter OR toml-rb/Citrus OR toml/Parslet) |
| `:markdown_parsing`     | Any markdown parser available (commonmarker OR markly)                    |
| `:rbs_parsing`          | Any RBS parser available (rbs gem OR tree-sitter-rbs)                     |
| `:native_parsing`       | Native tree-sitter backend and grammar available                          |
| **Library Tags**        |                                                                           |
| `:toml_rb_gem`          | toml-rb gem available (Citrus backend for TOML)                           |
| `:toml_gem`             | toml gem available (Parslet backend for TOML)                             |
| `:rbs_gem`              | rbs gem available (official RBS parser)                                   |

All tags have negated versions (e.g., `:not_mri_backend`, `:not_jruby_engine`, `:not_toml_parsing`) for testing fallback behavior.

**Debug Output:**

Set `TREE_HAVER_DEBUG=1` to print a dependency summary at the start of your test suite:

```bash
TREE_HAVER_DEBUG=1 bundle exec rspec
```

## 🔐 Security

See [SECURITY.md][🔐security].

## 🤝 Contributing

If you need some ideas of where to help, you could work on adding more code coverage,
or if it is already 💯 (see [below](#code-coverage)) check [issues][🤝gh-issues] or [PRs][🤝gh-pulls],
or use the gem and think about how it could be better.

We [![Keep A Changelog][📗keep-changelog-img]][📗keep-changelog] so if you make changes, remember to update it.

See [CONTRIBUTING.md][🤝contributing] for more detailed instructions.

## 📌 Versioning

This library follows [![Semantic Versioning 2.0.0][📌semver-img]][📌semver] for its public API where practical.
For most applications, prefer the [Pessimistic Version Constraint][📌pvc] with two digits of precision.

For example:

```ruby
spec.add_dependency("tree_haver", "~> 7.0")
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
[✉️ruby-forum]: https://www.rubyforum.org/tag/tree_haver
[✇bundle-group-pattern]: https://gist.github.com/pboling/4564780
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver
[⛳️namespace-img]: https://img.shields.io/badge/namespace-TreeHaver-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://clickgems.clickhouse.com/dashboard/tree_haver
[⛳️name-img]: https://img.shields.io/badge/name-tree__haver-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/tree_haver
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-tree_haver?utm_source=rubygems-tree_haver&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/tree_haver
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/tree_haver
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=GitHub&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://clickgems.clickhouse.com/dashboard/tree_haver
[👽dl-ranki]: https://img.shields.io/gem/dt/tree_haver.svg
[👽version]: https://clickgems.clickhouse.com/dashboard/tree_haver
[👽versioni]: https://img.shields.io/gem/v/tree_haver.svg
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
[🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
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
[🚎yard-current]: http://rubydoc.info/gems/tree_haver
[🚎yard-head]: https://tree-haver.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
