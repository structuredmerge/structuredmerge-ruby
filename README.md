[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang] [![structuredmerge Logo by Aboling0, CC BY-SA 4.0][🖼️structuredmerge-i]][🖼️structuredmerge]

[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg
[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN
[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg
[🖼️ruby-lang]: https://www.ruby-lang.org/
[🖼️structuredmerge-i]: https://logos.galtzo.com/assets/images/structuredmerge/avatar-192px.svg
[🖼️structuredmerge]: https://github.com/structuredmerge

# StructuredMerge Ruby

StructuredMerge Ruby provides Ruby gems for building merge-aware tools that need
portable structured-merge contracts, fixture-backed behavior, and Ruby-native
integration points.

The monorepo includes the core AST/review contracts, parser substrate support,
format-specific merge gems, binary/ZIP planning helpers, provider adapters, and
a Ruby packaging recipe gem.

Project links:

- Website: <https://structuredmerge.org>
- Implementations: <https://structuredmerge.org/implementations.html>
- Specification: <https://github.com/structuredmerge/structuredmerge-spec>
- Shared fixtures: <https://github.com/structuredmerge/structuredmerge-fixtures>

## Package Family

StructuredMerge Ruby is a layered gem family. The lower layers provide parser,
range, AST, merge, and template contracts; format gems apply those contracts to
specific languages and data formats; provider gems bind a format family to a
parser or serializer; workflow gems package the behavior for Git drivers,
release automation, and monorepo maintenance.

Package README files keep this section short and link here. This root guide is
the implementation inventory for Ruby users who need to choose gems, understand
backend coverage, or wire a focused backend into a test suite.

### Core and Workflow Gems

| Gem | Layer | What it provides |
| --- | --- | --- |
| [`tree_haver`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver) | Parser substrate | Parser backend registry, byte ranges, node wrappers, source locations, binary tree contracts, and backend selection helpers. |
| [`ast-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge) | Merge substrate | AST merge contracts, diagnostics, structural edit plans, review/replay vocabulary, nested merge orchestration, backend provider registration, and shared spec helpers. |
| [`ast-template`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template) | Template substrate | Template/session transport objects used by recipe tooling and language-specific templating layers. |
| [`ast-merge-git`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge-git) | Git integration | Merge-driver, diff-driver, conflict inspection, language registry, and command plumbing for `smorg-rb`. |
| [`smorg-rb`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/smorg-rb) | Command package | Ruby implementation command packaging and executable entry points. |
| [`kettle-jem`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem) | Recipe tooling | Template recipes, monorepo root materialization, gem maintenance helpers, and StructuredMerge Ruby release support. |

### Transformation Gems

| Gem | Layer | What it provides |
| --- | --- | --- |
| [`ast-crispr`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr) | Generic AST edits | Structured document surgery recipes for generated blocks and template-owned regions. |
| [`ast-crispr-ruby-prism`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr-ruby-prism) | Ruby AST edits | Prism-backed Ruby source edits, including require insertion and template-managed Ruby regions. |
| [`ast-crispr-markdown-markly`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr-markdown-markly) | Markdown AST edits | Markly-backed Markdown block replacement and README recipe support. |

### Format Gems

| Gem | Family | What it provides |
| --- | --- | --- |
| [`plain-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge) | Text | Plain-text fallback contracts and conflict-preserving merge behavior. |
| [`json-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge) | JSON and JSONC | Object/array-aware JSON merge behavior using the shared StructuredMerge merge substrate. |
| [`yaml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/yaml-merge) | YAML | YAML-family merge contracts, shared provider tags, and provider-neutral behavior. |
| [`toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/toml-merge) | TOML | TOML-family merge contracts and provider-neutral behavior. |
| [`dotenv-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/dotenv-merge) | dotenv | Environment-file merge behavior for key/value configuration files. |
| [`markdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge) | Markdown | Markdown-family merge contracts, heading/table/list matching, and provider-neutral behavior. |
| [`ruby-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ruby-merge) | Ruby source | Ruby source merge contracts and parser-backed source-language behavior. |
| [`rbs-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge) | RBS | Ruby signature merge behavior, declaration matching, and template-owned signature updates. |
| [`bash-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/bash-merge) | Bash source | Shell source merge contracts and parser-backed shell-language behavior. |
| [`go-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/go-merge) | Go source | Go source merge contracts for the cross-language StructuredMerge family. |
| [`rust-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rust-merge) | Rust source | Rust source merge contracts for the cross-language StructuredMerge family. |
| [`typescript-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/typescript-merge) | TypeScript source | TypeScript source merge contracts for the cross-language StructuredMerge family. |
| [`binary-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/binary-merge) | Binary | Binary tree planning contracts and structured binary merge helpers. |
| [`zip-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/zip-merge) | Archives | ZIP archive planning helpers and archive-aware merge contracts. |

### Provider Gems

Provider gems register themselves with the backend tag system used by
`ast-merge` and `tree_haver`. That registry lets a spec suite run against a
single selected backend, lets a format gem ask for a capability instead of a
hard dependency, and keeps parser-specific behavior out of provider-neutral
merge gems.

| Gem | Provides | Runtime notes |
| --- | --- | --- |
| [`psych-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge) | YAML provider | Uses Ruby's Psych parser and emitter. |
| [`citrus-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge) | TOML provider | Uses a Citrus grammar and pure-Ruby parser path. |
| [`parslet-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge) | TOML provider | Uses Parslet and pure-Ruby parser path. |
| [`commonmarker-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge) | Markdown provider | Uses CommonMarker for CommonMark-oriented Markdown parsing. |
| [`kramdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge) | Markdown provider | Uses Kramdown for Ruby-native Markdown parsing. |
| [`markly-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge) | Markdown provider | Uses Markly for cmark-gfm-backed Markdown parsing and README templating support. |
| [`prism-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge) | Ruby provider | Uses Prism for Ruby source parsing and Ruby-specific merge refiners. |

### Ruby Backend Notes

Ruby has the broadest backend surface in the StructuredMerge implementation set.
`tree_haver` owns the parser backend registry and byte-range contracts;
`ast-merge` owns provider registration and merge orchestration. The backend
tags are capability names, not package preferences.

| Backend or provider path | Used by | Notes |
| --- | --- | --- |
| `:TSLP` | source-family gems | Uses `tree-sitter-language-pack` / Kreuzberg-language-pack style parser aggregation where available. This is the preferred tree-sitter provider path for broad language coverage. |
| `:MRI` | source-family gems | Uses `ruby_tree_sitter`; retained as the MRI-native tree-sitter backend name. |
| `:rust` | source-family gems | Uses `tree_stump` where that native Rust-backed parser path is selected. |
| `:ffi` | source-family gems | Uses FFI bindings to libtree-sitter; suitable where the runtime and native library support the needed ABI. |
| `:java` | source-family gems | Uses JVM tree-sitter bindings for JRuby-oriented parser runs. |
| Prism | `ruby-merge`, `prism-merge`, `ast-crispr-ruby-prism` | Ruby-native parser path for Ruby source and structured Ruby source edits. |
| Psych | `yaml-merge`, `psych-merge` | Ruby standard YAML parser/emitter path. |
| RBS | `rbs-merge` | Ruby signature parser path. |
| CommonMarker, Markly, Kramdown | `markdown-merge` providers | Markdown parser families with different CommonMark/GFM/Ruby-native tradeoffs. |
| Citrus, Parslet | `toml-merge` providers | Pure-Ruby TOML parser families used as provider-specific backend paths. |
| Kaitai Struct | `binary-merge` | Schema-oriented binary parsing support for structured binary work. |

## Install

Install the gems your tool needs:

```sh
bundle add ast-merge json-merge
```

## Command

The Ruby implementation ships the implementation-specific `smorg-rb` command.
Use that name in git configuration unless a package manager or local install has
provided a `smorg` symlink.

Package-manager formulas may expose the selected implementation as `smorg`.
For a local user-created symlink:

```sh
ln -s "$(command -v smorg-rb)" ~/.local/bin/smorg
```

```sh
git config merge.smorg-rb.driver 'smorg-rb merge-driver %O %A %B %P'
git config diff.smorg-rb.command 'smorg-rb diff-driver'
smorg-rb conflicts diff path/to/file-with-conflicts.go
smorg-rb languages --gitattributes
```

`merge-driver` updates Git's `%A` file by default, or writes to `--output` when
used outside git. `diff-driver` accepts both the two-argument local form and the
seven- or nine-argument forms Git passes to external diff commands.
`conflicts diff` reports conflict-marker regions in a file that already contains
Git conflict markers.

Semantic merge-driver coverage is fixture-backed for JSON. Other language and
format paths are git-compatible command surfaces without semantic driver
coverage.

## Gems

Core:

- [`tree_haver`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver) - parser substrate, byte ranges, backend adapters, and binary tree contracts.
- [`ast-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge) - AST merge contracts, diagnostics, planning, review, replay, and nested-merge vocabulary.
- [`ast-template`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template) - template/session transport contracts.

Format libraries:

- [`plain-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge)
- [`json-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge)
- [`yaml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/yaml-merge)
- [`toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/toml-merge)
- [`markdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge)
- [`ruby-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ruby-merge)
- [`go-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/go-merge)
- [`rust-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rust-merge)
- [`typescript-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/typescript-merge)
- [`binary-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/binary-merge)
- [`zip-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/zip-merge)

Provider and recipe gems:

- [`psych-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge)
- [`citrus-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge)
- [`parslet-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge)
- [`commonmarker-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge)
- [`kramdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge)
- [`markly-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge)
- [`prism-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge)
- [`kettle-jem`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem)

## Portability

The Ruby gems are developed against the shared StructuredMerge fixtures. Those
fixtures define the cross-language behavior expected from the Go, TypeScript,
Rust, and Ruby implementations. Conformance checks live in gem specs and in the
shared spec/fixture tooling rather than in a static status document.

## Development

Common checks:

- `mise run check`
- `bundle exec rake`
- package-specific `bundle exec rspec` commands

Bundler path gems are the default isolation mechanism inside this monorepo. When
this repository needs to consume sibling workspace projects outside the monorepo
itself, prefer `nomono`-driven Bundler wiring rather than manual Ruby load-path
changes.
