<a href="https://github.com/structuredmerge"><img alt="structuredmerge Logo by GitHub" src="https://github.com/structuredmerge.png?size=192" width="12%" align="right"/></a> <a href="https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem"><img alt="kettle-jem Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/structuredmerge/structuredmerge-ruby/kettle-jem/avatar-128px.svg" width="12%" align="right"/></a>

# 🔮 Kettle::Jem

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

Kettle::Jem is an AST-aware gem templating system that keeps hundreds of Ruby gems
in sync with a shared template while preserving each project's customizations.
Unlike line-based copy/merge tools, Kettle::Jem understands the *structure* of
every file it touches — Ruby via Prism, YAML via Psych, Markdown via Markly,
TOML via tree-sitter, and more — so template updates land precisely where they
belong, and project-specific additions are never clobbered.

Plugin authors can now use the dedicated [plugin authoring guide](KETTLE_JEM_PLUGINS.md)
to build `kettle-jem` extension gems against the supported plugin seam.

### Key Features

- **AST-aware merging** — 10 format-specific merge engines (prism, psych, markly, toml, json, jsonc, json5, bash, dotenv, rbs, text)
- **Token substitution** — `{KJ|TOKEN}` patterns resolved from config, ENV, or auto-derived from gemspec
- **Freeze blocks** — protect any section from template overwrites with `# kettle-jem:freeze` / `# kettle-jem:unfreeze`
- **Per-file strategies** — `merge`, `accept_template`, `keep_destination`, or `raw_copy`
- **Multi-phase pipeline** — 11 ordered phases (service_actor-based) from config sync through duplicate checking
- **SHA-pinned GitHub Actions** — template `uses:` always wins, propagating immutable SHAs
- **Convergence in one pass** — a single `kettle-jem install` applies all changes; a second run produces zero diff
- **Selftest divergence check** — CI verifies that project drift stays within a configurable threshold

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

Compatible with MRI Ruby 4.0.0+, and JRuby.
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
| [kettle-soup-cover](https://clickgems.clickhouse.com/dashboard/kettle-soup-cover) | [GitHub](https://github.com/kettle-dev/kettle-soup-cover) | SimpleCov coverage policy and reporting | [![Total downloads for kettle-soup-cover](https://img.shields.io/gem/dt/kettle-soup-cover.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/kettle-soup-cover) |
| [kettle-test](https://clickgems.clickhouse.com/dashboard/kettle-test) | [GitHub](https://github.com/kettle-dev/kettle-test) | standard test runner and coverage harness | [![Total downloads for kettle-test](https://img.shields.io/gem/dt/kettle-test.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/kettle-test) |
| [rubocop-lts](https://clickgems.clickhouse.com/dashboard/rubocop-lts) | [GitHub](https://github.com/rubocop-lts/rubocop-lts) | Ruby-version-aware linting | [![Total downloads for rubocop-lts](https://img.shields.io/gem/dt/rubocop-lts.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/rubocop-lts) |
| [turbo_tests2](https://clickgems.clickhouse.com/dashboard/turbo_tests2) | [GitHub](https://github.com/galtzo-floss/turbo_tests2) | parallel test execution | [![Total downloads for turbo_tests2](https://img.shields.io/gem/dt/turbo_tests2.svg?style=flat-square)](https://clickgems.clickhouse.com/dashboard/turbo_tests2) |

</details>

<details markdown="1">
<summary>StructuredMerge package family</summary>

This gem is part of the StructuredMerge Ruby package family. The implementation inventory, layering model, and backend notes live in the [root package-family guide][sm-family-guide]. Shared behavior is defined by the [StructuredMerge fixtures][sm-family-fixtures] and implemented by the [Go][sm-family-go], [Ruby][sm-family-ruby], [Rust][sm-family-rust], and [TypeScript][sm-family-typescript] repositories.

Merge analysis must enter parsing through `tree_haver`. Parser-specific gems register concrete TreeHaver backends; substrate gems register grammar mappings and keep shared format or language merge behavior in one place. Missing backends fail closed instead of falling back to direct parser-library calls.

</details>

[sm-family-guide]: https://github.com/structuredmerge/structuredmerge-ruby#package-family
[sm-family-fixtures]: https://github.com/structuredmerge/structuredmerge-fixtures
[sm-family-go]: https://github.com/structuredmerge/structuredmerge-go
[sm-family-ruby]: https://github.com/structuredmerge/structuredmerge-ruby
[sm-family-rust]: https://github.com/structuredmerge/structuredmerge-rust
[sm-family-typescript]: https://github.com/structuredmerge/structuredmerge-typescript

## ✨ Installation

Install the gem and add to the application's Gemfile by executing:

```console
bundle add kettle-jem
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install kettle-jem
```

## ⚙️ Configuration

Each gem that uses Kettle::Jem has a `.kettle-jem.yml` file at its root. This file controls
every aspect of how the template is applied.

### Minimal Configuration

```yaml
project_emoji: "🔮"
engines:
  - ruby
licenses:
  - MIT
tokens:
  forge:
    gh_user: "your-username"
  author:
    name: "Your Name"
    email: "you@example.com"
```

### Full Configuration Reference

```yaml
# REQUIRED — unique emoji used in badges and gemspec summary
project_emoji: "🔮"               # ENV override: KJ_PROJECT_EMOJI

# Ruby engines to include in CI matrix (remove to skip)
engines:
  - ruby
  - jruby
  - truffleruby

# The generated direct dependency-heads workflow derives its Bundler lockfile
# platform from `engines`. JRuby gets an isolated temporary lockfile with the
# `universal-java` platform; MRI and TruffleRuby use the checked-in lock
# context. This avoids making one shared lockfile satisfy incompatible engine
# platforms.

# SPDX license identifiers
licenses:
  - MIT

# Logo layout in README header: org | project | org_and_project
readme:
  top_logo_mode: org

# Bot accounts to exclude from contributor lists
machine_users:
  - dependabot

# Maximum allowed divergence (%) for selftest CI check
min_divergence_threshold: 5       # ENV override: KJ_MIN_DIVERGENCE_THRESHOLD

# Default merge behavior applied to all files
defaults:
  preference: "template"           # template | destination
  add_template_only_nodes: true    # add nodes that only exist in template
  freeze_token: "kettle-jem"       # marker for frozen sections

# Token values for {KJ|TOKEN} substitution
tokens:
  forge:
    gh_user: "github-username"    # ENV override: KJ_GH_USER
    gl_user: "gitlab-username"    # ENV override: KJ_GL_USER
    cb_user: "codeberg-username"  # ENV override: KJ_CB_USER
    sh_user: "sourcehut-user"     # ENV override: KJ_SH_USER
  author:
    name: "Full Name"             # ENV override: KJ_AUTHOR_NAME
    given_names: "Full"           # ENV override: KJ_AUTHOR_GIVEN_NAMES
    family_names: "Name"          # ENV override: KJ_AUTHOR_FAMILY_NAMES
    email: "you@example.com"      # ENV override: KJ_AUTHOR_EMAIL
    domain: "example.com"         # ENV override: KJ_AUTHOR_DOMAIN
    orcid: "0000-0000-0000-0000"  # ENV override: KJ_AUTHOR_ORCID
  funding:
    kofi: "username"              # ENV override: KJ_FUNDING_KOFI
    paypal: "username"            # ENV override: KJ_FUNDING_PAYPAL
    buymeacoffee: "username"      # ENV override: KJ_FUNDING_BUYMEACOFFEE
    liberapay: "username"         # ENV override: KJ_FUNDING_LIBERAPAY
  social:
    mastodon: "username"          # ENV override: KJ_SOCIAL_MASTODON
    bluesky: "user.bsky.social"   # ENV override: KJ_SOCIAL_BLUESKY
    linktree: "username"          # ENV override: KJ_SOCIAL_LINKTREE
    devto: "username"             # ENV override: KJ_SOCIAL_DEVTO

# Glob-based overrides (first match wins)
patterns:
  - path: "certs/**"
    strategy: raw_copy

# Per-file overrides
files:
  Rakefile:
    strategy: merge
    preference: destination        # preserve local tasks
  AGENTS.md:
    strategy: accept_template      # always use template version
```

### Framework Matrix vs. Appraisals

`workflows.preset: framework` and `workflows.framework_matrix` are meant for a
simple 2D matrix: **Ruby versions × one framework gem/version axis**. This is a
good fit when you want kettle-jem to generate framework-version modular gemfiles,
`Appraisals` entries, and CI matrix entries for a single framework dependency.

If you need a deeper or more complex matrix, prefer
**`kettle-jem-appraisals`**, which generates `Appraisals` entries and is the
better fit for Appraisals-style combinations.

### Strategies

| Strategy           | Behavior                                                              |
|--------------------|-----------------------------------------------------------------------|
| `merge`            | Resolve tokens, then AST-merge template + destination (default)       |
| `accept_template`  | Resolve tokens, overwrite destination with template result            |
| `keep_destination`  | Skip entirely — no merge, no creation                                |
| `raw_copy`         | Copy bytes as-is — no token resolution, no merge (for binary assets) |

`raw_copy` exists for bootstrap files that may be needed before the full
templating stack is available. Because it bypasses normal template processing,
do not use it for templates that contain `{KJ|...}` tokens or require
StructuredMerge normalization.

### Token Substitution

Tokens use `{KJ|TOKEN}` syntax and are resolved in priority order:

1. **ENV variables** (highest) — e.g., `KJ_AUTHOR_NAME`
2. **`.kettle-jem.yml` `tokens:` section** — explicit values
3. **Auto-derived from gemspec** (lowest) — author name, email, domain

Common tokens:

| Token                  | Source                            |
|------------------------|-----------------------------------|
| `{KJ\|GEM_NAME}`       | Gem name from gemspec             |
| `{KJ\|NAMESPACE}`      | Ruby module namespace             |
| `{KJ\|AUTHOR:NAME}`    | Author full name                  |
| `{KJ\|AUTHOR:EMAIL}`   | Author email                      |
| `{KJ\|GH:USER}`        | GitHub username                   |
| `{KJ\|PROJECT_EMOJI}`  | Project emoji from config         |
| `{KJ\|MIN_RUBY}`       | Minimum Ruby version              |
| `{KJ\|FREEZE_TOKEN}`   | Freeze marker name                |

### Freeze Blocks

Protect sections in any file from template overwrites:

```ruby
# kettle-jem:freeze
gem "my-local-fork", path: "../custom"
# kettle-jem:unfreeze
```

Content between freeze/unfreeze markers is always preserved from the destination,
regardless of what the template contains. Works in all supported formats (Ruby, YAML,
Markdown, TOML, JSON, Bash, etc.).

### Merge Engine Selection

Kettle::Jem selects the merge engine by file type:

| File Pattern                                             | Merge Engine  | Key Behaviors                              |
|----------------------------------------------------------|---------------|--------------------------------------------|
| `*.rb`, `Gemfile`, `*.gemspec`, `Rakefile`, `Appraisals` | Prism::Merge  | Three-phase matching, gemspec var renaming |
| `*.yml`, `*.yaml`                                        | Psych::Merge  | SHA-pinned `uses:`, per-key preferences    |
| `*.md`, `*.markdown`                                     | Markly::Merge | Heading/list matching, inner list merge    |
| `*.toml`                                                 | Toml::Merge   | Sort keys, table matching                  |
| `*.json`                                                 | Json::Merge   | Key-based matching                         |
| `*.jsonc`                                                | Json::Merge   | With comment preservation                  |
| `*.json5`                                                | Json::Merge   | JSON5 keys, strings, comments, and trailing commas |
| `*.sh`, `*.bash`, `.envrc`                               | Bash::Merge   | Block matching                             |
| `.env*`                                                  | Dotenv::Merge | KEY=value matching                         |
| `*.rbs`                                                  | RBS::Merge    | Type signature matching                    |
| `.gitignore`                                             | Text::Merge   | Intentional line-based merge               |

> **No silent fallback:** If a tree-sitter grammar is unavailable for a file
> type that requires AST merging, kettle-jem will **fail** (default) or
> **skip** the file — never silently degrade to text-based merging.
> See `PARSE_ERROR_MODE` below.

## 🔧 Basic Usage

### Initial Setup

```bash
gem install kettle-jem
cd my-gem
kettle-jem
```

The setup CLI runs a two-phase bootstrap:

1. **Bootstrap** — creates `.kettle-jem.yml`, installs modular gemfiles, ensures dev dependencies
2. **Bundled** — loads the full runtime and runs `kettle-jem install`

### Applying Template Updates

After initial setup, re-run the template process to pull in updates:

```bash
K_JEM_TEMPLATING=true bundle exec kettle-jem install
```

This applies all template phases, then runs the local finishing steps such as
`bin/setup`, curated binstub generation, hooks, and lockfile normalization.

| Phase | Description                          | Files Affected                        |
|-------|--------------------------------------|---------------------------------------|
| 0     | Config sync                          | `.kettle-jem.yml`                     |
| 1     | Dev container                        | `.devcontainer/`                      |
| 2     | GitHub workflows                     | `.github/workflows/`, `FUNDING.yml`   |
| 3     | Quality config                       | `.qlty/qlty.toml`                     |
| 4     | Modular gemfiles                     | `gemfiles/modular/`                   |
| 5     | Spec helper                          | `spec/spec_helper.rb`                 |
| 6     | Environment templates                | `.env.local.example`                  |
| 7     | Remaining files                      | gemspec, README, LICENSE, Rakefile, … |
| 8     | Git hooks                            | `.git-hooks/`                         |
| 9     | License files                        | `LICENSE*`                            |
| 10    | Duplicate check                      | _(validation only)_                   |

Each phase is implemented as a composable [service_actor](https://github.com/sunny/actor)
actor, enabling per-phase statistics (📄 templates, 🆕 created, 📋 pre-existing,
🟰 identical, ✏️ changed) and future slice-based workflows.

### Checking Divergence

CI can verify that a project hasn't drifted too far from the template:

```bash
bundle exec rake kettle:jem:selftest
```

This re-applies the template in a temporary checkout and measures the diff.
Output is condensed to two summary lines after the template run:

```
[selftest] 📄  Report - tmp/template_test/report/summary.md
[selftest] ✅  Score: 100.0% · Divergence: 0.0% · Threshold: fail when divergence reaches 5.0%
```

If divergence exceeds `min_divergence_threshold` (default 5%), the check fails.

### Workflow-Specific Options

For GitHub Actions workflows, the template always wins for `uses:` lines
(SHA-pinned action references) while destination wins for job configuration:

```yaml
# Template updates this SHA automatically:
uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0

# Your matrix customizations are preserved:
matrix:
  ruby: ["3.2", "3.3", "3.4"]
```

### Per-File Overrides

Override merge behavior for specific files in `.kettle-jem.yml`:

```yaml
files:
  Rakefile:
    strategy: merge
    preference: destination     # keep your custom tasks
  certs/my.pem:
    strategy: raw_copy          # binary file, no merging
  generated/report.md:
    strategy: keep_destination  # never touch this file
```

### Environment Variables & CLI Options

Kettle::Jem behavior is controlled via environment variables (which double as
Rake task arguments) and CLI flags passed to `kettle-jem setup`.

#### Merge & Error Handling

| Variable | CLI Flag | Default | Description |
|----------|----------|---------|-------------|
| `FAILURE_MODE` | `--failure-mode=VAL` | `error` | How general merge failures are handled. `error` raises and halts; `rescue` logs a warning and uses unmerged content. |
| `PARSE_ERROR_MODE` | — | `fail` | How AST parser unavailability is handled. `fail` raises immediately (recommended); `skip` warns and preserves the destination file unchanged. **There is no text-merge fallback** — AST merge or nothing. |

#### Task Control

| Variable | CLI Flag | Default | Description |
|----------|----------|---------|-------------|
| `allowed` | `--allowed=VAL` | `true` | Set to `false`/`0`/`no` to require manual review of env file changes before continuing. |
| — | `--interactive` | _(off)_ | Enable interactive prompts (opt-in). Overrides the default non-interactive behavior. |
| `KETTLE_JEM_VERBOSE` | `--verbose` | `false` | Show detailed output including per-file messages and setup progress. Overrides the default quiet behavior. |
| `only` | `--only=VAL` | _(all)_ | Comma-separated glob patterns — only template files matching at least one pattern are processed. |
| `include` | `--include=VAL` | _(all)_ | Comma-separated glob patterns — additional files to include beyond the default set. |
| `hook_templates` | `--hook_templates=VAL` | _(prompt)_ | Git hook install location: `l`/`local`, `g`/`global`, or `n`/`none`. Also via `KETTLE_DEV_HOOK_TEMPLATES`. |
| `KETTLE_JEM_CHECKSUMS` | `--checksums=VAL` | `template,ignore-dest` | Checksum skip mode. See "Checksum Skip Modes" below. |
| — | `--ignore-checksums` | _(off)_ | Alias for `--checksums=off`; disables checksum-based skipping. |

#### Checksum Skip Modes

Kettle::Jem writes managed template state to
`.structuredmerge/kettle-jem.lock`. The legacy whole-template checksum
inventory now lives under `template_state.checksums`.
That inventory is useful for coarse template drift state, but it is not used to
skip individual files. File skipping uses `files.*.input_fingerprint`, a
per-destination digest that includes the selected template source SHA, recipe
identity/version, resolved token digest, and kettle-jem implementation SHA.
Token values are hashed into the fingerprint and are not written to the lockfile.

`--checksums` accepts comma-separated modes:

| Mode | Behavior |
|------|----------|
| `template` | Skip a destination file only when its `input_fingerprint` matches the lock. This is the default template-input check. |
| `ignore-dest` | Do not compare the destination file checksum. This is the default destination behavior. |
| `dest` | Also require the destination file checksum to match the lock before skipping. `dest` implies `template` unless `ignore-template` is present. |
| `ignore-template` | Do not compare `input_fingerprint`; useful only with `dest` when local destination state should be the only skip gate. |
| `off` | Disable checksum-based skipping. This cannot be combined with other modes. |

Common combinations:

| Value | Result |
|-------|--------|
| `template,ignore-dest` | Default. Retemplate when relevant template input changes; ignore local destination edits. |
| `dest,template` | Retemplate when relevant template input changes or the destination differs from the prior templated result. |
| `dest,ignore-template` | Skip only when the destination checksum matches; ignore template input changes. |
| `off` | Run normal templating without checksum skip shortcuts. |

#### Config & Identity (KJ_ prefix)

These map directly to `.kettle-jem.yml` keys, seed freshly created configs,
fill missing keys during config sync, and act as runtime overrides.

| Variable | Description |
|----------|-------------|
| `KJ_PROJECT_EMOJI` | Project identifying emoji (e.g. `🪙`). Required in config. |
| `KJ_MIN_DIVERGENCE_THRESHOLD` | Selftest divergence threshold for `min_divergence_threshold`. |
| `KJ_AUTHOR_NAME` | Gem author full name |
| `KJ_AUTHOR_EMAIL` | Gem author email |
| `KJ_AUTHOR_DOMAIN` | Author website domain (derived from email if unset) |
| `KJ_AUTHOR_GIVEN_NAMES` | First/given names |
| `KJ_AUTHOR_FAMILY_NAMES` | Last/family names |
| `KJ_AUTHOR_ORCID` | ORCID identifier |
| `FORGE_ORG` | Preferred forge organization or owner used for scaffolded repository URLs when no forge remote is available |
| `KJ_GH_ORG` | GitHub-specific organization or owner fallback for scaffolded repository URLs |
| `KJ_GH_USER` | GitHub username used for maintainer profile and sponsor links |
| `KJ_GL_USER` | GitLab username |
| `KJ_CB_USER` | Codeberg username |
| `KJ_SH_USER` | SourceHut username |

#### Workspace & Funding

| Variable | Description |
|----------|-------------|
| `KETTLE_DEV_DEV` | Workspace root for local sibling gems. `true` = `~/src/my`; a path = that path; unset/`false` = released gems. |
| `KETTLE_DEV_DEBUG` | Set to `true` for verbose debug output. |
| `FUNDING_ORG` | OpenCollective organization handle for FUNDING.yml. Auto-derived from git remote if unset. |
| `OPENCOLLECTIVE_HANDLE` | Alternative to `FUNDING_ORG` for personal OpenCollective pages. |
| `KJ_FUNDING_KOFI` | Ko-fi handle for FUNDING.yml |
| `KJ_FUNDING_PAYPAL` | PayPal handle for FUNDING.yml |
| `KJ_FUNDING_BUYMEACOFFEE` | Buy Me a Coffee handle for funding links |
| `KJ_FUNDING_LIBERAPAY` | Liberapay handle for funding links |
| `KJ_SOCIAL_MASTODON` | Mastodon handle for social/profile links |
| `KJ_SOCIAL_BLUESKY` | Bluesky handle for social/profile links |
| `KJ_SOCIAL_LINKTREE` | Linktree handle for social/profile links |
| `KJ_SOCIAL_DEVTO` | DEV Community handle for social/profile links |

#### Templating Examples

```bash
# Standard template update (quiet, non-interactive — the default)
K_JEM_TEMPLATING=true bundle exec kettle-jem install

# Verbose output
K_JEM_TEMPLATING=true KETTLE_JEM_VERBOSE=true bundle exec kettle-jem install

# Interactive mode (prompts before each change)
K_JEM_TEMPLATING=true bundle exec kettle-jem install --interactive

# Force re-evaluation of every selected template file
K_JEM_TEMPLATING=true bundle exec kettle-jem install --ignore-checksums

# Retemplate when either template inputs or destination checksums changed
K_JEM_TEMPLATING=true bundle exec kettle-jem install --checksums=dest,template

# Only workflow files, skip unparseable. Scoped template runs skip install
# finishing steps and are intended for surgical file updates.
K_JEM_TEMPLATING=true PARSE_ERROR_MODE=skip bundle exec kettle-jem template --only=".github/**"

# Rescue on merge failure (don't halt)
K_JEM_TEMPLATING=true FAILURE_MODE=rescue bundle exec kettle-jem install
```

The `kettle:jem:*` rake tasks are internal targets used by the executable after
it prepares the templating environment; call `kettle-jem` directly for normal
templating work.

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
spec.add_dependency("kettle-jem", "~> 7.0")
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
[⛳️gem-namespace]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Kettle::Jem-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://clickgems.clickhouse.com/dashboard/kettle-jem
[⛳️name-img]: https://img.shields.io/badge/name-kettle--jem-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/structuredmerge/structuredmerge-ruby.svg
[⛳️tag]: https://github.com/structuredmerge/structuredmerge-ruby/releases
[🚂maint-blog]: http://www.railsbling.com/tags/kettle-jem
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
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-kettle-jem?utm_source=rubygems-kettle-jem&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/kettle-jem
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/kettle-jem
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=GitHub&logoColor=green
[📜src-gh]: https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/kettle-jem
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/wikis/home
[📜gh-wiki]: https://github.com/structuredmerge/structuredmerge-ruby/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-gitlab-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-github-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://clickgems.clickhouse.com/dashboard/kettle-jem
[👽dl-ranki]: https://img.shields.io/gem/dt/kettle-jem.svg
[👽version]: https://clickgems.clickhouse.com/dashboard/kettle-jem
[👽versioni]: https://img.shields.io/gem/v/kettle-jem.svg
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
[🧮kloc-img]: https://img.shields.io/badge/KLOC-11.378-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
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
[🚎yard-current]: http://rubydoc.info/gems/kettle-jem
[🚎yard-head]: https://kettle-jem.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
