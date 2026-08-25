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

The family is intentionally layered:

- [`tree_haver`][ruby-tree-haver] provides parser portability, backend discovery, byte ranges, and runtime capability reporting.
- [`ast-merge`][ruby-ast-merge] provides the cross-format merge substrate: shared base classes, layout/comment ownership, diagnostics, review state, and execution reports.
- Family gems such as [`markdown-merge`][ruby-markdown-merge], [`yaml-merge`][ruby-yaml-merge], and [`toml-merge`][ruby-toml-merge] own parser-neutral behavior for one format family.
- Provider gems such as [`markly-merge`][ruby-markly-merge], [`psych-merge`][ruby-psych-merge], and [`citrus-toml-merge`][ruby-citrus-toml-merge] register backend-specific parser/emitter behavior.
- Workflow gems such as [`ast-merge-git`][ruby-ast-merge-git], [`smorg-rb`][ruby-smorg-rb], and [`kettle-jem`][ruby-kettle-jem] package the family for Git, release, and templating workflows.

### Core and Workflow Gems

| Gem | Layer | What it provides |
| --- | --- | --- |
| [`tree_haver`][ruby-tree-haver] | Parser substrate | Parser backend registry, byte ranges, node wrappers, source locations, binary tree contracts, and backend selection helpers. |
| [`ast-merge`][ruby-ast-merge] | Merge substrate | AST merge contracts, diagnostics, structural edit plans, review/replay vocabulary, nested merge orchestration, backend provider registration, and shared spec helpers. |
| [`ast-template`][ruby-ast-template] | Template substrate | Template/session transport objects used by recipe tooling and language-specific templating layers. |
| [`ast-merge-git`][ruby-ast-merge-git] | Git integration | Merge-driver, diff-driver, conflict inspection, language registry, and command plumbing for `smorg-rb`. |
| [`smorg-rb`][ruby-smorg-rb] | Command package | Ruby implementation command packaging and executable entry points. |
| [`kettle-jem`][ruby-kettle-jem] | Recipe tooling | Template recipes, monorepo root materialization, gem maintenance helpers, and StructuredMerge Ruby release support. |

### Transformation Gems

| Gem | Layer | What it provides |
| --- | --- | --- |
| [`ast-crispr`][ruby-ast-crispr] | Generic AST edits | Structured document surgery recipes for generated blocks and template-owned regions. |
| [`ast-crispr-ruby-prism`][ruby-ast-crispr-ruby-prism] | Ruby AST edits | [Prism][prism]-backed Ruby source edits, including require insertion and template-managed Ruby regions. |
| [`ast-crispr-markdown-markly`][ruby-ast-crispr-markdown-markly] | Markdown AST edits | [Markly][markly]-backed Markdown block replacement and README recipe support. |

### Format Gems

| Gem | Family | What it provides |
| --- | --- | --- |
| [`plain-merge`][ruby-plain-merge] | Text | Line-backed TreeHaver parser registration, plain-text fallback contracts, and conflict-preserving merge behavior. |
| [`json-merge`][ruby-json-merge] | JSON and JSONC | Object/array-aware JSON merge behavior using the shared StructuredMerge merge substrate and [tree-sitter JSON][ts-json] grammar coverage where the selected backend supplies it. |
| [`yaml-merge`][ruby-yaml-merge] | YAML | YAML-family merge contracts, shared provider tags, and provider-neutral behavior. |
| [`toml-merge`][ruby-toml-merge] | TOML | TOML-family merge contracts and provider-neutral behavior. |
| [`dotenv-merge`][ruby-dotenv-merge] | dotenv | Dotenv line parser registration and key/value configuration merge behavior built on the plain text substrate. |
| [`markdown-merge`][ruby-markdown-merge] | Markdown | Markdown-family merge contracts, heading/table/list matching, link-reference handling, fenced-code flow, and provider-neutral behavior. |
| [`ruby-merge`][ruby-ruby-merge] | Ruby source | Ruby source merge contracts and parser-backed source-language behavior. |
| [`rbs-merge`][ruby-rbs-merge] | RBS | Ruby signature merge behavior, declaration matching, and template-owned signature updates using [RBS][rbs] and tree-sitter RBS grammar coverage where available. |
| [`bash-merge`][ruby-bash-merge] | Bash source | Shell source merge contracts and parser-backed shell-language behavior using [tree-sitter Bash][ts-bash] where available. |
| [`go-merge`][ruby-go-merge] | Go source | Go source merge contracts for the cross-language StructuredMerge family. |
| [`rust-merge`][ruby-rust-merge] | Rust source | Rust source merge contracts for the cross-language StructuredMerge family. |
| [`typescript-merge`][ruby-typescript-merge] | TypeScript source | TypeScript source merge contracts for the cross-language StructuredMerge family. |
| [`binary-merge`][ruby-binary-merge] | Binary | Kaitai/binary-family substrate for byte-range ownership, preservation reports, unsafe diagnostics, and renderer planning. |
| [`zip-merge`][ruby-zip-merge] | Archives | ZIP parser registration and archive-aware merge contracts built on the binary-family substrate. |

### Provider Gems

Provider gems register themselves with the backend tag system used by
`ast-merge` and `tree_haver`. That registry lets a spec suite run against a
single selected backend, lets a format gem ask for a capability instead of a
hard dependency, and keeps parser-specific behavior out of provider-neutral
merge gems.

| Gem | Provides | Runtime notes |
| --- | --- | --- |
| [`psych-merge`][ruby-psych-merge] | YAML provider | Uses Ruby's [Psych][psych] parser and emitter. |
| [`citrus-toml-merge`][ruby-citrus-toml-merge] | TOML provider | Registers a TreeHaver TOML backend backed by a [Citrus][citrus] grammar, commonly paired with [`toml-rb`][toml-rb] style TOML data handling. |
| [`parslet-toml-merge`][ruby-parslet-toml-merge] | TOML provider | Registers a TreeHaver TOML backend backed by [Parslet][parslet], commonly paired with [`toml`][toml] style TOML data handling. |
| [`commonmarker-merge`][ruby-commonmarker-merge] | Markdown provider | Uses [CommonMarker][commonmarker] for CommonMark-oriented Markdown parsing. |
| [`kramdown-merge`][ruby-kramdown-merge] | Markdown provider | Uses [Kramdown][kramdown] for Ruby-native Markdown parsing. |
| [`markly-merge`][ruby-markly-merge] | Markdown provider | Uses [Markly][markly] for cmark-gfm-backed Markdown parsing and README templating support. |
| [`prism-merge`][ruby-prism-merge] | Ruby provider | Uses [Prism][prism] for Ruby source parsing and Ruby-specific merge refiners. |

### Ruby Backend Notes

Ruby has the broadest backend surface in the StructuredMerge implementation set.
`tree_haver` owns the parser backend registry and byte-range contracts;
`ast-merge` owns provider registration and merge orchestration. The backend
tags are capability names, not package preferences.

| Backend or provider path | Used by | Notes |
| --- | --- | --- |
| `:TSLP` | source-family gems | Uses [tree-sitter-language-pack][tree-sitter-language-pack] parser aggregation where available. This is the preferred tree-sitter provider path for broad language coverage. |
| `:MRI` | source-family gems | Uses [`ruby_tree_sitter`][ruby-tree-sitter]; retained as the MRI-native tree-sitter backend name. |
| `:rust` | source-family gems | Uses [`tree_stump`][tree-stump] where that native Rust-backed parser path is selected. |
| `:ffi` | source-family gems | Uses [FFI][ffi] bindings to [libtree-sitter][tree-sitter]; suitable where the runtime and native library support the needed ABI. |
| `:java` | source-family gems | Uses JVM tree-sitter bindings through [java-tree-sitter][java-tree-sitter] / [jtreesitter][jtreesitter] for JRuby-oriented parser runs. |
| [Prism][prism] | `ruby-merge`, `prism-merge`, `ast-crispr-ruby-prism` | Ruby-native parser path for Ruby source and structured Ruby source edits. |
| [Psych][psych] | `yaml-merge`, `psych-merge` | Ruby standard YAML parser/emitter path. |
| [RBS][rbs] | `rbs-merge` | Ruby signature parser path. |
| [CommonMarker][commonmarker], [Markly][markly], [Kramdown][kramdown] | `markdown-merge` providers | Markdown parser families with different CommonMark/GFM/Ruby-native tradeoffs. |
| [Citrus][citrus], [Parslet][parslet] | `toml-merge` providers | Pure-Ruby TOML parser families exposed as provider-specific TreeHaver backend paths. |
| [Kaitai Struct][kaitai] | `binary-merge`, `zip-merge` | Schema-oriented binary parsing support and shared binary-family merge behavior. |

#### Backend Platform Compatibility

`tree_haver` supports multiple Ruby parser backends, but not every backend works
on every Ruby runtime:

| TreeHaver backend | MRI | JRuby | TruffleRuby | Notes |
| --- | :---: | :---: | :---: | --- |
| `:TSLP` ([tree-sitter-language-pack][tree-sitter-language-pack]) | ✅ | ❓ | ❓ | Aggregated tree-sitter provider used by StructuredMerge language-family gems where available. |
| `:MRI` ([`ruby_tree_sitter`][ruby-tree-sitter]) | ✅ | ❌ | ❌ | C extension, MRI only. |
| `:rust` ([`tree_stump`][tree-stump]) | ✅ | ❌ | ❌ | Rust extension through Ruby native-extension tooling, MRI only. |
| `:ffi` ([FFI][ffi] + [libtree-sitter][tree-sitter]) | ✅ | ✅ | ❌ | TruffleRuby FFI does not support the tree-sitter struct-by-value ABI. |
| `:java` ([java-tree-sitter][java-tree-sitter] / [jtreesitter][jtreesitter]) | ❌ | ✅ | ❌ | JRuby-oriented path that requires matching grammar JARs. |
| [Prism][prism] | ✅ | ✅ | ✅ | Ruby parser, standard library in Ruby 3.4+. |
| [Psych][psych] | ✅ | ✅ | ✅ | YAML parser/emitter, standard library. |
| [Citrus][citrus] | ✅ | ✅ | ✅ | Pure Ruby PEG parser. |
| [Parslet][parslet] | ✅ | ✅ | ✅ | Pure Ruby PEG parser. |
| [CommonMarker][commonmarker] | ✅ | ❌ | ❓ | Native Markdown parser used through `commonmarker-merge`. |
| [Markly][markly] | ✅ | ❌ | ❓ | Native cmark-gfm parser used through `markly-merge`. |
| [Kramdown][kramdown] | ✅ | ✅ | ✅ | Pure Ruby Markdown parser. |

Legend: ✅ = works, ❌ = does not work, ❓ = not part of the supported runtime claim.

[ruby-tree-haver]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver
[ruby-ast-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge
[ruby-ast-template]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template
[ruby-ast-merge-git]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge-git
[ruby-smorg-rb]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/smorg-rb
[ruby-kettle-jem]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem
[ruby-ast-crispr]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr
[ruby-ast-crispr-ruby-prism]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr-ruby-prism
[ruby-ast-crispr-markdown-markly]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr-markdown-markly
[ruby-plain-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge
[ruby-json-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge
[ruby-yaml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/yaml-merge
[ruby-toml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/toml-merge
[ruby-dotenv-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/dotenv-merge
[ruby-markdown-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markdown-merge
[ruby-ruby-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ruby-merge
[ruby-rbs-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge
[ruby-bash-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/bash-merge
[ruby-go-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/go-merge
[ruby-rust-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rust-merge
[ruby-typescript-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/typescript-merge
[ruby-binary-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/binary-merge
[ruby-zip-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/zip-merge
[ruby-psych-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge
[ruby-citrus-toml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge
[ruby-parslet-toml-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge
[ruby-commonmarker-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge
[ruby-kramdown-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge
[ruby-markly-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge
[ruby-prism-merge]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge
[tree-sitter-language-pack]: https://github.com/kreuzberg-dev/tree-sitter-language-pack
[tree-sitter]: https://tree-sitter.github.io/tree-sitter/
[ruby-tree-sitter]: https://github.com/Faveod/ruby-tree-sitter
[tree-stump]: https://github.com/joker1007/tree_stump
[ffi]: https://github.com/ffi/ffi
[java-tree-sitter]: https://github.com/tree-sitter/java-tree-sitter
[jtreesitter]: https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter
[prism]: https://github.com/ruby/prism
[psych]: https://github.com/ruby/psych
[rbs]: https://github.com/ruby/rbs
[commonmarker]: https://github.com/gjtorikian/commonmarker
[markly]: https://github.com/ioquatix/markly
[kramdown]: https://github.com/gettalong/kramdown
[citrus]: https://github.com/mjackson/citrus
[parslet]: https://github.com/kschiess/parslet
[toml-rb]: https://github.com/emancu/toml-rb
[toml]: https://github.com/jm/toml
[kaitai]: https://kaitai.io/
[ts-json]: https://github.com/tree-sitter/tree-sitter-json
[ts-bash]: https://github.com/tree-sitter/tree-sitter-bash

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

Core and transformation gems:

- [`tree_haver`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/tree_haver) - parser substrate, byte ranges, backend adapters, and binary tree contracts.
- [`ast-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge) - AST merge contracts, diagnostics, planning, review, replay, and nested-merge vocabulary.
- [`ast-template`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-template) - template/session transport contracts.
- [`ast-crispr`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr) - generic AST edit recipes for generated blocks and template-owned regions.
- [`ast-crispr-ruby-prism`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr-ruby-prism) - Prism-backed Ruby source edits.
- [`ast-crispr-markdown-markly`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-crispr-markdown-markly) - Markly-backed Markdown source edits.

Format libraries:

- [`plain-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/plain-merge)
- [`bash-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/bash-merge)
- [`dotenv-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/dotenv-merge)
- [`json-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/json-merge)
- [`rbs-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/rbs-merge)
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

- [`ast-merge-git`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge-git)
- [`psych-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/psych-merge)
- [`citrus-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/citrus-toml-merge)
- [`parslet-toml-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/parslet-toml-merge)
- [`commonmarker-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/commonmarker-merge)
- [`kramdown-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kramdown-merge)
- [`markly-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/markly-merge)
- [`prism-merge`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/prism-merge)
- [`kettle-jem`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem)
- [`smorg-rb`](https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/smorg-rb)

## Portability

The Ruby gems are developed against the [shared StructuredMerge fixtures][structuredmerge-fixtures].
Those fixtures define the cross-language behavior expected from the Go,
TypeScript, Rust, and Ruby implementations. Conformance checks live in gem specs
and in the shared spec/fixture tooling rather than in a static status document.

## Development

Use the consistent family task names from the monorepo root. The root
`mise.toml` files are manually maintained workspace configuration, so the
invocation adapts to each family's local Bundler and path wiring while the task
names stay the same:

```sh
mise run install
mise run readiness
mise run lint
mise run test
mise run check
```

`lint` is read-only. Use `mise run lint-fix` when applying RuboCop Gradual
autocorrections is intentional. `mise run deps` updates against released
dependencies without committing; `mise run deps-local` uses sibling checkouts
without committing; and `mise run deps-release` uses released dependencies and
permits lockfile commits. `mise run state` shows release state, while
`mise run release-plan` previews a publish and `mise run release -- --only pend`
executes one with additional release options forwarded after `--`.

The same task names are available from the other Ruby family roots in this
workspace, including `appraisal-rb`, `galtzo-floss`, `kettle-dev`, `omniauth`,
`resque`, `rubocop-lts`, `ruby-oauth`, `ruby-openid`, `rubythems`, and
`ur-brain`. The StructuredMerge Go, Rust, and TypeScript roots retain their
language-specific native tasks.

For a single gem, run commands from that gem directory:

```sh
bundle exec kettle-test
bin/rake rubocop_gradual:autocorrect
```

Prefer `kettle-test` over direct `rspec` so local verification exercises the
same parallel runner, worker isolation, filtering, and formatter behavior used
by CI. Use direct `rspec` only for narrow debugging when `kettle-test` cannot
express the probe, then rerun `kettle-test` before treating the suite as
verified.

Bundler path gems are the default isolation mechanism inside this monorepo. When
this repository needs to consume sibling workspace projects outside the monorepo
itself, prefer `nomono`-driven Bundler wiring rather than manual Ruby load-path
changes.
