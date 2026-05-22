# Template Run Review Work Log

Context: generated diffs from the monorepo `workspace-scripts/template_ruby_gems.rb` run. Review each item before changing implementation or committing generated output.

## Review Items

### 1. `json-merge` README JSONC docs placement

- Status: decided; fix applied in working tree
- Type: content placement error, not a template bug
- Current diff: `gems/json-merge/README.md` lost the old `## 📚 JSONC behavior` section because it was added as a top-level section outside the allowed user-editable README areas.
- Rule: README top-level sections are template-managed. User/project-specific content may only be added as subsections under `## 🌻 Synopsis`, `## ⚙️ Configuration`, and `## 🔧 Basic Usage`.
- Decision: restore JSONC content only as `###` subsections under the allowed sections.
- Implementation notes: added `### JSONC Support` under Synopsis, `### JSONC Options` under Configuration, and JSONC usage/freeze/template-only examples under Basic Usage.

### 2. `kettle-jem` README profile behavior

- Status: decided; script fix applied in working tree
- Type: missing special-case behavior in monorepo wrapper
- Current diff: `gems/kettle-jem/README.md` is treated like a normal monorepo subgem and loses large kettle-jem-specific sections.
- Question: should `kettle-jem` use the same monorepo-subgem profile, a special profile, or per-gem preservation rules?
- Decision: `kettle-jem` must run with the full template because it should exemplify the result of applying the full kettle-jem template to a gem.
- Implementation notes: `workspace-scripts/template_ruby_gems.rb` now routes `kettle-jem` through the full template by omitting `template_profile`, while other gems continue to use `monorepo-subgem`. The banner and per-gem output now show this distinction.

### 3. Four-logo README header support

- Status: decided; implementation in working tree
- Type: missing feature
- Current diff: `gems/kettle-jem/README.md` drops the kettle-jem logo/link from the header, reducing four logos to three.
- Question: what config shape should support additional logos? Candidate: ordered logo entries with image URL, alt/title, attribution text, and target URL.
- Decision: replace the single `top_logo_mode` matrix with a comma-separated `readme.top_logos` list. Supported named options are `related-org`, `ruby`, `org`, and `project`; all are optional.
- Compatibility: legacy `top_logo_mode` values map forward: `org` => `related-org,ruby,org`, `project` => `related-org,ruby,project`, and `org_and_project` => `related-org,ruby,org,project`.
- Implementation notes: README logo generation now builds the full row from normalized logo options instead of hard-coded static logos plus extras. `kettle-jem` sets `top_logos: related-org,ruby,org,project` to restore its fourth project logo.

### 4. Consistent monorepo vs standalone repository links

- Status: pending evaluation
- Type: likely bug or incomplete monorepo-link model
- Current diff: kettle-jem docs mix standalone `structuredmerge/kettle-jem` URLs with monorepo subdirectory URLs under `structuredmerge-ruby/tree/main/gems/kettle-jem`.
- Question: which generated files should use monorepo root URLs, subdirectory URLs, or standalone mirror URLs?
- Decision:
- Implementation notes:

### 5. Template commit behavior

- Status: pending evaluation
- Type: missing feature / regression from reference kettle-jem
- Current behavior: the wrapper passes `skip_commit: true` for bootstrap and apply, and the banner does not mention commit behavior.
- Reference behavior: reference kettle-jem auto-committed by default unless `KETTLE_JEM_SKIP_COMMIT` or `--skip-commit` was set.
- Question: should this monorepo wrapper default to one repo-level commit after all gems, with `--no-commit` and a clean-worktree preflight?
- Decision:
- Implementation notes:

### 6. README badge and link projection audit

- Status: pending evaluation
- Type: likely intended template drift, needs audit
- Current diff: many READMEs gain expanded CI/runtime badges and some unused refs are removed.
- Question: are all generated badges valid for the monorepo, and are removed refs genuinely unused?
- Decision:
- Implementation notes:

### 7. Homepage URI override result

- Status: pending evaluation
- Type: likely correct
- Current diff: gemspecs use `spec.metadata["homepage_uri"] = "https://structuredmerge.org"`.
- Question: are `.kettle-jem.yml`, ENV, and root `mise.toml` now the correct source chain, and does this apply consistently to all gems?
- Decision:
- Implementation notes:

### 8. Minimum Ruby version gemspec version-loader rewrite

- Status: pending evaluation
- Type: likely correct
- Current diff: affected gemspecs lose the legacy `RUBY_VERSION >= "3.1"` branch and inline the anonymous-module version load.
- Question: is the ast-crispr-ruby-prism rewrite complete, and do any gems still require lower-Ruby fallback behavior?
- Decision:
- Implementation notes:

### 9. `kettle-jem` generated `.kettle-jem.yml` additions

- Status: pending evaluation
- Type: likely correct
- Current diff: `yard_host: kettle-jem.galtzo.com` and `homepage_uri: https://structuredmerge.org` are added.
- Question: is this split between generated YARD links and gemspec homepage URI intended?
- Decision:
- Implementation notes:

### 10. Generated documentation formatting drift

- Status: pending evaluation
- Type: mixed risk
- Current diff: `CITATION.cff`, `CONTRIBUTING.md`, `FUNDING.md`, and README reference definitions change formatting and URL targets.
- Question: is formatting normalization acceptable, and are URL target changes correct separately from formatting?
- Decision:
- Implementation notes:
