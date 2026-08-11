# frozen_string_literal: true

RSpec.describe Kettle::Jem, "README and changelog templating" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "applies README style conditionals and reports missing integrations" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["PolyForm-Noncommercial-1.0.0"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - README.md
          readme:
            integrations:
              coveralls: false
        YAML
        "templates/README.md.example" => <<~MARKDOWN,
          # 💎 Example

          [![CodeCov Test Coverage][🏀codecovi]][🏀codecov] [![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls] [![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov] [![QLTY Maintainability][🏀qlty-mnti]][🏀qlty-mnt] [![CodeQL][🖐codeQL-img]][🖐codeQL]

          ## 🌻 Synopsis

          Template synopsis.

          ## 🦷 FLOSS Funding

          Funding template text.

          ## 🔐 Security

          Security template text.

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.
        MARKDOWN
        "README.md" => <<~MARKDOWN
          # 💎 Example

          ## 🌻 Synopsis

          Project synopsis.

          ## ⚙️ Configuration

          Project configuration.

          ## 🔧 Basic Usage

          Project usage.
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "template_source_application_README_md" }
      expect(report.fetch(:final_content)).to include("Project synopsis.")
      expect(report.fetch(:final_content)).to include("Project configuration.")
      expect(report.fetch(:final_content)).to include("Project usage.")
      expect(report.fetch(:final_content)).not_to include("## 🦷 FLOSS Funding")
      expect(report.fetch(:final_content)).not_to include("## 🔐 Security")
      expect(report.fetch(:final_content)).not_to include("CodeCov Test Coverage")
      expect(report.fetch(:final_content)).not_to include("Coveralls Test Coverage")
      expect(report.fetch(:final_content)).not_to include("QLTY Test Coverage")
      expect(report.fetch(:final_content)).not_to include("CodeQL")
      expect(report.dig(:metadata, :readme_style, :floss_funding_enabled)).to be(false)
      expect(report.dig(:metadata, :readme_style, :security_enabled)).to be(false)
      expect(report.dig(:metadata, :readme_style, :disabled_integrations)).to contain_exactly("coveralls", "skywalking-eyes")
      expect(report.dig(:metadata, :readme_style, :missing_integrations)).to contain_exactly("codecov", "qlty", "codeql")
    end
  end

  it "creates a package README through the packaged README style API" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-style-api-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:changed)).to be(true)
      expect(plan.fetch(:final_content)).to include("# 💎 Example")
      expect(plan.fetch(:final_content)).to include("## 🌻 Synopsis")
      expect(plan.fetch(:final_content)).not_to include("root package-family guide")
      expect(plan.fetch(:final_content)).not_to include("Tokens to Remember")

      apply = described_class.apply_readme_style(root, env: {})
      expect(apply.fetch(:changed)).to be(true)
      expect(File.read(File.join(root, "README.md"))).to eq(apply.fetch(:final_content))
      expect(described_class.plan_readme_style(root, env: {}).fetch(:changed)).to be(false)
    end
  end

  it "merges CHANGELOG templates without replacing release history" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-changelog-template-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - CHANGELOG.md
        YAML
        "templates/CHANGELOG.md.example" => <<~MARKDOWN,
          # Changelog

          Template intro.

          ## [Unreleased]

          ### Added

          ### Changed

          ### Deprecated

          ### Removed

          ### Fixed

          ### Security

          [Unreleased]: https://example.com/template/compare/HEAD
        MARKDOWN
        "CHANGELOG.md" => <<~MARKDOWN
          # Changelog

          Project intro.

          ## [Unreleased]

          ### Added
          - Keep project pending feature.
            - Keep nested detail.

          ### Fixed
          - Keep project pending fix.

          ## [2.0.0] - 2026-01-02

          - Existing release must survive.

          [Unreleased]: https://github.com/acme/example/compare/v2.0.0...HEAD
          [2.0.0]: https://github.com/acme/example/compare/v1.0.0...v2.0.0
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "template_source_application_CHANGELOG_md" }
      changelog = report.fetch(:final_content)

      expect(changelog).to include("Template intro.")
      expect(changelog).not_to include("Project intro.")
      expect(changelog).to include("Template intro.\n\n## [Unreleased]")
      expect(changelog).to include("### Deprecated")
      expect(changelog).to include("### Removed")
      expect(changelog).to include("### Security")
      expect(changelog).to include("[Unreleased]\n\n### Added\n\n- Keep project pending feature.")
      expect(changelog).to include("### Fixed\n\n- Keep project pending fix.")
      expect(changelog).to include("- Keep project pending feature.")
      expect(changelog).to include("  - Keep nested detail.")
      expect(changelog).to include("- Keep project pending fix.")
      expect(changelog).to include("## [2.0.0] - 2026-01-02")
      expect(changelog).to include("[2.0.0]: https://github.com/acme/example/compare/v1.0.0...v2.0.0")
      expect(changelog).not_to include("[Unreleased]: https://example.com/template/compare/HEAD")
    end
  end

  it "canonicalizes legacy release headings before replaying transfer entries" do
    template = <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      ### Added

      ### Changed

      ### Deprecated

      ### Removed

      ### Fixed

      ### Security
    MARKDOWN
    destination = <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      ### Fixed

      - Pending project fix.

      ## 3.1.0 - 2024-09-24

      - Historical release entry.
    MARKDOWN

    transfer_entries = [
      {
        key: "kettle-jem-template-20260801-001",
        section: "### Changed",
        lines: ["- kettle-jem-template-20260801-001 - Template change."]
      }
    ]
    result = described_class.send(
      :merge_changelog_template_source,
      template,
      destination,
      facts: {changelog: {transfer_entries: transfer_entries}}
    )

    expect(result).to include("## [3.1.0] - 2024-09-24")
    expect(result).to include("- Historical release entry.")
    expect(result).to include("- Pending project fix.")
    expect(result).to include("- kettle-jem-template-20260801-001 - Template change.")
    expect(result).not_to include("## 3.1.0 - 2024-09-24")
  end

  it "applies transferable changelog entries once while preserving project entries" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-changelog-transfer-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: false
            entries:
              - README.md
          kettle-jem:
            version: "7.0.0"
            changelog_replay:
              last_entry_key: "kettle-jem-template-20260715-999"
              last_entry_date: "2026-07-15"
            checksums: {}
        YAML
        "CHANGELOG.md" => <<~MARKDOWN
          # Changelog

          ## [Unreleased]

          ### Added

          - Project-authored item.

          ### Changed

          - kettle-jem-template-20260716-002 - Gemspecs now ship fewer repository-only
            files, reducing package noise for downstream packagers.

          ### Fixed

          - Existing fix.
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "changelog_unreleased" }
      changelog = report.fetch(:final_content)

      expect(changelog.scan("kettle-jem-template-20260716-002").size).to eq(1)
      expect(changelog).to include("- Project-authored item.")
      expect(changelog).to include("- Existing fix.")
    end
  end

  it "replays transfer entries when stored replay state claims entries absent from the changelog" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-changelog-replay-state-drift-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: false
            entries:
              - README.md
          kettle-jem:
            version: "7.1.0"
            changelog_replay:
              last_entry_key: "kettle-jem-template-20260725-001"
              last_entry_date: "2026-07-25"
            checksums: {}
        YAML
        "CHANGELOG.md" => <<~MARKDOWN
          # Changelog

          ## [Unreleased]

          ### Added

          ### Changed

          - Project-authored item.

          ### Deprecated

          ### Removed

          ### Fixed

          ### Security
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "changelog_unreleased" }
      changelog = report.fetch(:final_content)

      expect(changelog).to include("- Project-authored item.")
      expect(changelog).to include("kettle-jem-template-20260716-002")
      expect(changelog).to include("kettle-jem-template-20260725-002")
      expect(changelog).not_to include("kettle-jem-template-20260716-001")
      expect(changelog).not_to include("kettle-jem-template-initial")
    end
  end

  it "uses migrated lockfile replay state for transfer changelog selection" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-changelog-lock-replay-state-slice", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: false
            entries:
              - README.md
        YAML
        Kettle::Jem::KETTLE_LOCK_PATH => <<~YAML,
          ---
          version: 1
          template_state:
            version: 7.1.0
            changelog_replay:
              last_entry_key: kettle-jem-template-20260720-001
              last_entry_date: '2026-07-20'
            checksums:
              README.md.example: old
          files: {}
        YAML
        "CHANGELOG.md" => <<~MARKDOWN
          # Changelog

          ## [Unreleased]

          ### Added

          - kettle-jem-template-20260720-001 - Already applied.
        MARKDOWN
      })
      entries = [
        {key: "kettle-jem-template-20260720-001", section: "Added", lines: ["Already applied."]},
        {key: "kettle-jem-template-20260721-001", section: "Fixed", lines: ["Later fix."]}
      ]

      facts = described_class.send(:changelog_transfer_facts, root, entries)

      expect(facts.fetch(:first_template)).to be(false)
      expect(facts.fetch(:transfer_entries).map { |entry| entry.fetch(:key) }).to eq(["kettle-jem-template-20260721-001"])
    end
  end

  it "adds only the initial templating changelog entry when no replay state exists" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-changelog-initial-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: false
            entries:
              - README.md
        YAML
        "CHANGELOG.md" => <<~MARKDOWN
          # Changelog

          ## [Unreleased]

          ### Added

          - Project-authored item.
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      report = plan[:recipe_reports].find { |candidate| candidate.fetch(:recipe_name) == "changelog_unreleased" }
      changelog = report.fetch(:final_content)

      expect(changelog).to include("- kettle-jem-template-initial - Initial templating by kettle-jem.")
      expect(changelog).not_to include("kettle-jem-template-20260716-001")
      expect(changelog).to include("- Project-authored item.")
    end
  end

  it "applies multiple missed transferable changelog entries without duplicating existing keys" do
    changelog = <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      ### Changed

      - kettle-jem-template-20260716-001 - Already applied.
    MARKDOWN
    entries = [
      {
        key: "kettle-jem-template-20260716-001",
        section: "### Changed",
        lines: ["- kettle-jem-template-20260716-001 - Already applied."]
      },
      {
        key: "kettle-jem-template-20260716-002",
        section: "### Fixed",
        lines: [
          "- kettle-jem-template-20260716-002 - First missed transfer.",
          "  Continued detail."
        ]
      },
      {
        key: "kettle-jem-template-20260716-003",
        section: "### Security",
        lines: ["- kettle-jem-template-20260716-003 - Second missed transfer."]
      }
    ]

    result = described_class.send(:apply_changelog_transfer_entries, changelog, entries)

    expect(result.scan("kettle-jem-template-20260716-001").size).to eq(1)
    expect(result).to include("### Fixed\n\n- kettle-jem-template-20260716-002")
    expect(result).to include("### Security\n\n- kettle-jem-template-20260716-003")
    expect(result).to include("- kettle-jem-template-20260716-002 - First missed transfer.\n  Continued detail.")
    expect(result).to include("- kettle-jem-template-20260716-003 - Second missed transfer.")
  end

  it "preserves existing transfer changelog entries inside released sections by stable ID" do
    changelog = <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      ### Added

      ### Changed

      ### Deprecated

      ### Removed

      ### Fixed

      ### Security

      ## [1.0.7] - 2026-07-25

      - TAG: [v1.0.7][1.0.7t]
      - COVERAGE: 100.00% -- 129/129 lines in 8 files
      - BRANCH COVERAGE: 100.00% -- 42/42 branches in 8 files
      - 54.17% documented

      ### Changed

      - Project-authored changed entry.

      - kettle-jem-template-20260716-001 - Shim gemspec manifests now include
        `LICENSE.md` instead of nonexistent `LICENSE.txt`.
      - kettle-jem-template-20260720-001 - Generated READMEs can now render
        template-managed corporate sponsor logos from project or family config.
      - kettle-jem-template-20260725-001 - Generated JRuby and TruffleRuby workflow
        files now run when pull request head branches start with `feature/release`,
        so release CI monitoring does not report intentionally skipped engine
        workflows as failures.

      ### Fixed

      - Project-authored fixed entry.

      ## [1.0.6] - 2026-07-11

      - TAG: [v1.0.6][1.0.6t]

      ### Changed

      - Prior release entry.
    MARKDOWN
    entries = [
      {
        key: "kettle-jem-template-20260716-001",
        section: "### Fixed",
        lines: [
          "- kettle-jem-template-20260716-001 - Shim gems now package `LICENSE.md` instead",
          "  of a missing `LICENSE.txt` file."
        ]
      },
      {
        key: "kettle-jem-template-20260720-001",
        section: "### Added",
        lines: [
          "- kettle-jem-template-20260720-001 - READMEs can now display configured",
          "  corporate sponsor logos."
        ]
      },
      {
        key: "kettle-jem-template-20260725-001",
        section: "### Fixed",
        lines: [
          "- kettle-jem-template-20260725-001 - Release pull request branches beginning",
          "  with `feature/release` now run JRuby and TruffleRuby workflows."
        ]
      }
    ]

    result = described_class.send(:apply_changelog_transfer_entries, changelog, entries)

    expect(result.scan("kettle-jem-template-20260716-001").size).to eq(1)
    expect(result.scan("kettle-jem-template-20260720-001").size).to eq(1)
    expect(result.scan("kettle-jem-template-20260725-001").size).to eq(1)
    expect(result).to include("## [1.0.7] - 2026-07-25")
    expect(result).to include("- TAG: [v1.0.7][1.0.7t]")
    expect(result).to include("- Project-authored changed entry.")
    expect(result).to include("- Project-authored fixed entry.")
    expect(result).to include("Shim gemspec manifests now include")
    expect(result).to include("Generated READMEs can now render")
    expect(result).to include("so release CI monitoring does not report")
    expect(result).not_to include("READMEs can now display configured")
    expect(result).not_to include("Shim gems now package `LICENSE.md`")
    expect(result).to include("## [1.0.6] - 2026-07-11")
    expect(result).to include("- Prior release entry.")
  end

  it "corrects interleaved transfer changelog entries across multiple released sections" do
    changelog = File.read(project_root.join("spec/fixtures/kettle_family_interleaved_changelog.md"))
    entries = described_class.transfer_changelog_entries

    result = described_class.send(:apply_changelog_transfer_entries, changelog, entries)

    existing_keys = described_class.send(:changelog_transfer_keys, changelog)
    entries.each do |entry|
      expect(result.scan(entry.fetch(:key)).size).to eq(1)
      expect(result).to include(entry.fetch(:lines).join("\n")) unless existing_keys.include?(entry.fetch(:key))
    end
    expect(result).to include("## [1.1.9] - 2026-07-25")
    expect(result).to include("- TAG: [v1.1.9][1.1.9t]")
    expect(result).to include("## [1.1.6] - 2026-07-25")
    expect(result).to include("## [1.0.2] - 2026-07-21")
    expect(result).to include("## [1.0.0] - 2026-07-17")
    expect(result).to include("- `kettle-family state` now marks mismatched GitHub release tags")
    expect(result).to include("- Bare `kettle-family bump` now defaults to `--only bump`")
    expect(result).to include("- Release summaries now count only members that reached a release terminal")
    expect(result).to include("- `kettle-family template` now passes family-level `readme.corporate_sponsors`")
    expect(result).to include("- Promoted the gems that provide built-in `kettle-family` workflow commands")
  end

  it "parses sectioned transferable changelog entries through Markdown owners" do
    path = File.join(described_class::PACKAGED_TEMPLATE_ROOT, described_class::TRANSFER_CHANGELOG_TEMPLATE_PATH)
    content = File.read(path)
    context = Ast::Crispr::Markdown::Markly.document_context(content: content, source_label: path)
    sections = context.structural_owners(owner_scope: :heading_sections).select do |owner|
      owner.level == 2 && described_class.send(:changelog_transfer_section_map).key?(owner.heading_text.to_s.strip)
    end
    entries = described_class.transfer_changelog_entries

    expect(sections.map { |section| section.heading_text.to_s.strip }.uniq.size).to be > 1
    expect(entries).not_to be_empty
    expect(entries.map { |entry| entry.fetch(:section) }.uniq.size).to be > 1
    expect(entries.map { |entry| entry.fetch(:key) }).to eq(entries.map { |entry| entry.fetch(:key) }.sort)
    entries.each do |entry|
      expect(entry.fetch(:key)).to match(/\Akettle-jem-template-\d{8}-\d{3}\z/)
      expect(described_class::CHANGELOG_STANDARD_HEADINGS).to include(entry.fetch(:section))
      expect(entry.fetch(:lines).join("\n")).to include(entry.fetch(:key))
    end
  end

  it "parses transfer applicability filters without transferring their source notation" do
    parsed = described_class.send(
      :parse_changelog_transfer_line,
      "kettle-jem-template-20260720-004 [if engine.alternates=false & ruby.min<2.2] - MRI-only fix."
    )

    expect(parsed.fetch(:filter)).to eq(
      predicates: [
        {field: "engine.alternates", operator: "=", value: "false"},
        {field: "ruby.min", operator: "<", value: "2.2"}
      ]
    )
    expect(parsed.fetch(:rendered_payload)).to eq("kettle-jem-template-20260720-004 - MRI-only fix.")
  end

  it "evaluates transfer filters against the fixed destination context schema" do
    filter = described_class.send(:parse_changelog_transfer_filter, "engine.alternates=false & ruby.min<2.2")

    expect(described_class.send(
      :transfer_changelog_filter_applies?,
      filter,
      {"engine.alternates" => false, "ruby.min" => "2.1"}
    )).to be(true)
    expect(described_class.send(
      :transfer_changelog_filter_applies?,
      filter,
      {"engine.alternates" => true, "ruby.min" => "2.1"}
    )).to be(false)
    expect {
      described_class.send(
        :transfer_changelog_filter_applies?,
        {predicates: [{field: "unknown.field", operator: "=", value: "true"}]},
        {}
      )
    }.to raise_error(Kettle::Jem::Error, /Unknown transfer changelog filter field/)
  end

  it "builds transfer context without recursively rediscovering project facts" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-transfer-context", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          engines:
            - ruby
        YAML
      })
      expect(described_class).not_to receive(:discover_facts)

      context = described_class.send(:transfer_changelog_context, root, env: {})

      expect(context).to include("ruby.min" => "3.2", "engine.alternates" => false)
    end
  end

  it "removes retroactively excluded transfer entries from every release section" do
    changelog = <<~MARKDOWN
      # Changelog

      ## [Unreleased]

      ### Fixed

      - kettle-jem-template-20260720-004 - Remove this transfer entry.
        Continuation.

      ## [1.0.0] - 2026-08-01

      ### Fixed

      - kettle-jem-template-20260720-004 - Remove this released transfer entry.
        Continuation.

      - Project-authored released history remains.
    MARKDOWN

    result = described_class.send(
      :apply_changelog_transfer_entries,
      changelog,
      [],
      excluded_keys: ["kettle-jem-template-20260720-004"]
    )

    expect(result).not_to include("Remove this transfer entry.")
    expect(result).not_to include("Continuation.")
    expect(result).to include("Project-authored released history remains.")
  end

  it "reports transfer changelog lag from a stored replay cursor" do
    entries = described_class.transfer_changelog_entries
    cursor = entries.fetch(-2).fetch(:key)
    latest = entries.last.fetch(:key)
    expected_missing = entries.last(1)
    lag = described_class.transfer_changelog_lag(cursor, verbose: true)

    expect(lag.fetch(:last_entry_key)).to eq(cursor)
    expect(lag.fetch(:latest_entry_key)).to eq(latest)
    expect(lag.fetch(:missing_count)).to eq(expected_missing.size)
    expect(lag.fetch(:missing_entries)).to eq(expected_missing)
  end

  it "reports every transfer changelog entry as missing when no replay cursor exists" do
    entries = described_class.transfer_changelog_entries
    lag = described_class.transfer_changelog_lag

    expect(lag.fetch(:last_entry_key, nil)).to be_nil
    expect(lag.fetch(:latest_entry_key)).to eq(entries.last.fetch(:key))
    expect(lag.fetch(:missing_count)).to eq(entries.size)
  end

  it "keeps the real CHANGELOG template in canonical Unreleased form" do
    template = File.read(project_root.join("lib/kettle/jem/templates/CHANGELOG.md.example"))

    expect(template).to include(<<~MARKDOWN)
      ## [Unreleased]

      ### Added

      ### Changed

      ### Deprecated

      ### Removed

      ### Fixed

      ### Security
    MARKDOWN
  end

  it "fills configured README section partials while preserving unconfigured manual sections" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-partials-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
          readme:
            section_partials:
              synopsis: readme/partials/synopsis.md
              configuration: readme/partials/configuration.md
              basic_usage: readme/partials/basic_usage.md
        YAML
        "templates/readme/partials/synopsis.md.example" => "Generated synopsis for {KJ|GEM_NAME}.\\n",
        "templates/readme/partials/configuration.md.example" => "Generated configuration.\\n",
        "templates/readme/partials/basic_usage.md.example" => "Generated usage.\\n",
        "README.md" => <<~MARKDOWN
          # 💎 Example

          ## 🌻 Synopsis

          Old synopsis.

          ## ⚙️ Configuration

          Old configuration.

          ## 🔧 Basic Usage

          Old usage.
        MARKDOWN
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:final_content)).to include("Generated synopsis for example.")
      expect(plan.fetch(:final_content)).to include("Generated configuration.")
      expect(plan.fetch(:final_content)).to include("Generated usage.")
      expect(plan.fetch(:final_content)).not_to include("Old synopsis.")
      expect(plan.fetch(:final_content)).not_to include("Old configuration.")
      expect(plan.fetch(:final_content)).not_to include("Old usage.")
      expect(plan.dig(:readme_style, :section_partials, "synopsis", :selected_source)).to eq(
        "templates/readme/partials/synopsis.md.example"
      )
    end
  end

  it "loads packaged README section partials" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-readme-partials-slice", tmp_root) do |root|
      write_tree(root, {
        "kettle-jem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-jem"
            spec.summary = "Kettle Jem"
            spec.homepage = "https://github.com/structuredmerge/kettle-jem"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
          readme:
            section_partials:
              synopsis: readme/partials/synopsis.md
              configuration: readme/partials/configuration.md
              basic_usage: readme/partials/basic_usage.md
        YAML
      })

      plan = described_class.plan_readme_style(root, env: {})
      expect(plan.fetch(:final_content)).to include("Kettle template tool")
      expect(plan.fetch(:final_content)).to include("Configuration shape")
      expect(plan.fetch(:final_content)).to include("K_JEM_TEMPLATING=true kettle-jem install")
      expect(plan.dig(:readme_style, :section_partials, "configuration", :source_root)).to eq("packaged")
    end
  end

  it "removes Open Collective funding when disabled" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: false
          templates:
            root: packaged
            entries:
              - README.md
              - source: FUNDING.md.example
                target: FUNDING.md
        YAML
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: example
        YAML
        ".github/workflows/opencollective.yml" => <<~YAML
          name: Open Collective
          on:
            workflow_dispatch:
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: actions/checkout@v3
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_disabled_source)).to eq("config.funding.open_collective")
      expect(plan.dig(:facts, :funding, :open_collective_files)).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe.fetch(:name) }
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_opencollective_yml")
      expect(recipe_names).to include("opencollective_disabled_file_cleanup_github_workflows_opencollective_yml")
      expect(recipe_names).not_to include("github_actions_workflow_snippets_github_workflows_opencollective_yml")
      expect(plan.dig(:facts, :templates, :source_preferences)).to contain_exactly(
        a_hash_including(
          target_path: "README.md",
          configured_source: "README.md",
          selected_source: "README.md.example",
          source_relative_path: "README.md.example",
          source_root: "packaged",
          selection_reason: "default_example_variant",
          apply: false
        ),
        a_hash_including(
          target_path: "FUNDING.md",
          configured_source: "FUNDING.md.example",
          selected_source: "FUNDING.md.no-osc.example",
          source_relative_path: "FUNDING.md.no-osc.example",
          source_root: "packaged",
          selection_reason: "opencollective_disabled_no_osc_variant",
          apply: false
        )
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.fetch(:changed)).to be(false)
      expect(template_report.dig(:metadata, :template_source_preference, :selected_source)).to eq(
        "README.md.example"
      )
      expect(template_report.dig(:request_envelope, :request, :runtime_context, :template_source_preference, :selection_reason)).to eq(
        "default_example_variant"
      )
      funding_report = plan[:recipe_reports].find { |report| report.fetch(:recipe_name) == "github_funding_yml" }
      expect(funding_report.fetch(:final_content)).not_to include("open_collective")
      expect(funding_report.fetch(:final_content)).to include("tidelift: rubygems/example")
      open_collective_reports = plan[:recipe_reports].select do |report|
        report.fetch(:recipe_name).start_with?("opencollective_disabled_file_cleanup_")
      end
      expect(open_collective_reports.map { |report| report.fetch(:relative_path) }).to eq(
        [".opencollective.yml", ".github/workflows/opencollective.yml"]
      )
      expect(open_collective_reports).to all(satisfy { |report| report.fetch(:metadata).fetch(:delete_file) == true })

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to include(".opencollective.yml", ".github/workflows/opencollective.yml")
      expect(File).not_to exist(File.join(root, ".opencollective.yml"))
      expect(File).not_to exist(File.join(root, ".github/workflows/opencollective.yml"))
    end
  end

  it "applies the packaged README Open Collective recipe from the canonical template" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-readme-no-opencollective", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/acme/example"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          funding:
            open_collective: false
          templates:
            root: packaged
            apply: true
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      readme = readme_report.fetch(:final_content)

      expect(readme_report.dig(:metadata, :template_source_preference, :selected_source)).to eq("README.md.example")
      expect(readme).not_to include("KJ:OPEN_COLLECTIVE")
      expect(readme).not_to include("KJ:NO_OPEN_COLLECTIVE")
      expect(readme).not_to include("opencollective")
      expect(readme).not_to include("Open Collective")
      expect(readme).not_to include("kettle-readme-backers")
      expect(readme).not_to include("Open Source Helpers")
      expect(readme).not_to include("codetriage")
      expect(readme).to include("Apache SkyWalking Eyes License Compatibility Check")
      expect(readme).to include("[![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor]")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "updates the README KLOC badge from the current changelog release coverage" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-kloc-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          gem_version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/example/version.rb", mod) }::Example::Version::VERSION

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.version = gem_version
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "lib/example/version.rb" => <<~RUBY,
          module Example
            module Version
              VERSION = "1.2.3"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            profile: full
            apply: true
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        "CHANGELOG.md" => <<~MARKDOWN,
          # Changelog

          ## [1.2.3] - 2026-05-23

          ### Fixed

          - COVERAGE: 91.09% -- 3644/4000 lines in 80 files
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|GEM_NAME}

          spec.add_dependency("{KJ|GEM_NAME}", "~> {KJ|GEM_MAJOR}.0")

          [🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).to include("KLOC-4.000-FFDD67.svg")
      expect(readme).to include('spec.add_dependency("example", "~> 1.0")')
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "preserves the destination README KLOC badge when current changelog coverage is unavailable" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-kloc-fallback-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          gem_version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/example/version.rb", mod) }::Example::Version::VERSION

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.version = gem_version
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "lib/example/version.rb" => <<~RUBY,
          module Example
            module Version
              VERSION = "1.2.3"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            profile: full
            apply: true
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        "CHANGELOG.md" => <<~MARKDOWN,
          # Changelog

          ## [Unreleased]

          ### Fixed

          - Example change.
        MARKDOWN
        "README.md" => <<~MARKDOWN,
          # Example

          [🧮kloc-img]: https://img.shields.io/badge/KLOC-0.063-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|GEM_NAME}

          [🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).to include("KLOC-0.063-FFDD67.svg")
      expect(readme).not_to include("KLOC-5.053-FFDD67.svg")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "keeps shim-only template files out of full profile inventory" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-inventory-profile-slice", tmp_root) do |root|
      template_root = File.join(root, "template")
      write_tree(template_root, {
        "README.md.example" => "readme",
        "shim/.structuredmerge/kettle-jem.yml.example" => "{KJ|SHIMMED_GEM_NAME}"
      })

      full_entries = described_class.send(
        :template_inventory_entries,
        root,
        template_root,
        templates: {"profile" => "full"}
      )
      shim_entries = described_class.send(
        :template_inventory_entries,
        root,
        template_root,
        templates: {"profile" => "shim"}
      )

      expect(full_entries).to include("README.md")
      expect(full_entries).not_to include("shim/.structuredmerge/kettle-jem.yml")
      expect(shim_entries).to include("shim/.structuredmerge/kettle-jem.yml")
    end
  end

  it "applies packaged monorepo subgem README badge policy" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-subgem-readme-badge-policy", tmp_root) do |root|
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "☯️"
          readme:
            package_family: structuredmerge
          templates:
            root: packaged
            apply: true
            profile: monorepo-subgem
            entries:
              - README.md
              - FUNDING.md
          files:
            README.md:
              strategy: accept_template
        YAML
        ".github/workflows/current.yml" => "name: Current\n"
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)
      funding = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_FUNDING_md"
      end.fetch(:final_content)

      expect(readme).not_to include("Open Source Helpers")
      expect(readme).not_to include("codetriage")
      expect(readme).not_to include("OpenCollective Backers")
      expect(readme).not_to include("OpenCollective Sponsors")
      expect(readme).not_to include("opencollective")
      expect(funding).not_to include("OpenCollective Backers")
      expect(funding).not_to include("OpenCollective Sponsors")
      expect(funding).not_to include("opencollective")
      expect(readme).not_to include("Apache SkyWalking Eyes License Compatibility Check")
      expect(readme).to include("https://github.com/structuredmerge/structuredmerge-ruby#package-family")
      expect(readme).to include("root package-family guide")
      expect(readme).to include("https://github.com/structuredmerge/structuredmerge-ruby/actions/workflows/current.yml")
      expect(readme).not_to include("https://github.com/structuredmerge/ast-merge/actions/workflows/current.yml")
      expect(readme).not_to include("actions/workflows/heads.yml")
      expect(readme).to include("https://img.shields.io/badge/wiki-gitlab-943CD2.svg")
      expect(readme).to include("https://img.shields.io/badge/wiki-github-943CD2.svg")
      expect(readme).not_to include("https://img.shields.io/badge/wiki-examples-943CD2.svg")
    end
  end

  it "honors falsey Open Collective environment variables when config is absent" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-env-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".github/FUNDING.yml" => <<~YAML,
          github: [example]
          open_collective: example
        YAML
        ".opencollective.yml" => <<~YAML
          collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: {"OPENCOLLECTIVE_HANDLE" => "NO"})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be(true)
      expect(plan.dig(:facts, :funding, :open_collective_disabled_source)).to eq("env.OPENCOLLECTIVE_HANDLE")
      expect(plan.dig(:facts, :funding, :open_collective_org)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).not_to include("https://opencollective.com/example")
      expect(plan[:changed_files]).to include(".opencollective.yml")
    end
  end

  it "lets explicit Open Collective config override falsey environment variables" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-config-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          funding:
            open_collective: true
        YAML
        ".github/FUNDING.yml" => <<~YAML
          github: [example]
          open_collective: example
        YAML
      })

      plan = described_class.plan_project(root, env: {"FUNDING_ORG" => "0"})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be_nil
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/example")
    end
  end

  it "uses explicit Open Collective config as the template token source" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-config-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          funding:
            open_collective: config-org
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("config-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("config.funding.open_collective")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/config-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "config-org")
    end
  end

  it "uses GitHub funding Open Collective config as the template token source" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-github-funding-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".github/FUNDING.yml" => <<~YAML,
          open_collective: "github-funding-org"
        YAML
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("github-funding-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq(".github/FUNDING.yml")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/github-funding-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include(
        "KJ|OPENCOLLECTIVE_ORG" => "github-funding-org"
      )
    end
  end

  it "defaults Open Collective template content to galtzo-floss when no org can be resolved" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-default-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            entries:
              - .opencollective.yml
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_disabled)).to be_nil
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("galtzo-floss")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("fallback.default")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/galtzo-floss")
      expect(plan.dig(:facts, :templates, :tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "galtzo-floss")
      expect(plan.fetch(:warnings)).to be_empty
    end
  end

  it "warns when the default Open Collective org differs from the GitHub org" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-default-org-warning-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/example-org/example"
            spec.metadata["source_code_uri"] = "https://github.com/example-org/example"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("galtzo-floss")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("fallback.default")
      expect(plan.fetch(:warnings)).to contain_exactly(
        'OpenCollective funding org defaulted to "galtzo-floss", but the GitHub org is "example-org". Configure funding.open_collective or FUNDING_ORG if this is not intended.'
      )
    end
  end

  it "discovers Open Collective org from environment before .opencollective.yml" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-env-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            entries:
              - README.md
        YAML
        ".opencollective.yml" => <<~YAML,
          collective: yaml-org
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {"FUNDING_ORG" => "env-org"})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("env-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq("env.FUNDING_ORG")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/env-org")
      expect(plan.dig(:facts, :templates, :tokens)).to include(
        "KJ|GEM_NAME" => "example",
        "KJ|GEM_NAME_PATH" => "example",
        "KJ|NAMESPACE" => "Example",
        "KJ|OPENCOLLECTIVE_ORG" => "env-org"
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_preference_README_md"
      end
      expect(template_report.dig(:metadata, :template_tokens)).to include("KJ|OPENCOLLECTIVE_ORG" => "env-org")
      expect(template_report.dig(:request_envelope, :request, :runtime_context, :template_tokens)).to include(
        "KJ|OPENCOLLECTIVE_ORG" => "env-org"
      )
    end
  end

  it "discovers Open Collective org from .opencollective.yml when env is absent" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-opencollective-yaml-org-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".opencollective.yml" => <<~YAML
          org: yaml-org
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :funding, :open_collective_org)).to eq("yaml-org")
      expect(plan.dig(:facts, :funding, :open_collective_org_source)).to eq(".opencollective.yml")
      expect(plan.dig(:facts, :funding, :urls)).to include("https://opencollective.com/yaml-org")
    end
  end

  it "applies selected template content with projected tokens when configured" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-application-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => "# old\n",
        ".opencollective.yml" => <<~YAML,
          collective: yaml-org
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|GEM_NAME}

          Namespace: {KJ|NAMESPACE}
          Path: {KJ|GEM_NAME_PATH}
          Ruby: {KJ|MIN_RUBY}
          Author: {KJ|AUTHOR:NAME}
          Given: {KJ|AUTHOR:GIVEN_NAMES}
          Family: {KJ|AUTHOR:FAMILY_NAMES}
          Email: {KJ|AUTHOR:EMAIL}
          Domain: {KJ|AUTHOR:DOMAIN}
          Funding: {KJ|OPENCOLLECTIVE_ORG}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.fetch(:changed)).to be(true)
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include("{KJ|GEM_NAME}")
      expect(template_report.fetch(:final_content)).to eq(<<~MARKDOWN)
        # 💎 Example

        Namespace: Example
        Path: example
        Ruby: 3.2
        Author: Jane Q Public
        Given: Jane Q
        Family: Public
        Email: jane@example.test
        Domain: example.test
        Funding: yaml-org
      MARKDOWN
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|AUTHOR:DOMAIN" => "example.test",
        "KJ|AUTHOR:EMAIL" => "jane@example.test",
        "KJ|AUTHOR:FAMILY_NAMES" => "Public",
        "KJ|AUTHOR:GIVEN_NAMES" => "Jane Q",
        "KJ|AUTHOR:NAME" => "Jane Q Public",
        "KJ|GEM_NAME" => "example",
        "KJ|GEM_NAME_PATH" => "example",
        "KJ|MIN_RUBY" => "3.2",
        "KJ|NAMESPACE" => "Example",
        "KJ|OPENCOLLECTIVE_ORG" => "yaml-org"
      )

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
    end
  end

  it "applies packaged template files when no project template root exists" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-packaged-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          funding:
            open_collective: collective-acme
          tokens:
            forge:
              gh_user: acme
              gl_user: acme
              cb_user: acme
              sh_user: acme
            funding:
              kofi: acme
              paypal: acme
              buymeacoffee: acme
              liberapay: acme
            social:
              mastodon: "@acme@example.social"
              bluesky: acme.example
              linktree: acme
              devto: acme
          templates:
            apply: true
            entries:
              - README.md
              - FUNDING.md
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(template_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: "README.md.example",
        source_relative_path: "README.md.example",
        source_root: "packaged"
      )
      expect(template_report.dig(:metadata, :template_source_preference, :source_root_path)).to end_with(
        "lib/kettle/jem/templates"
      )
      expect(template_report.dig(:request_envelope, :request, :template_content)).to include("# {KJ|PROJECT_EMOJI} {KJ|README:TITLE}")
      expect(template_report.fetch(:final_content)).to include("# 💎 Example")
      expect(template_report.fetch(:final_content)).to include("Compatible with MRI Ruby 3.2+")
      expect(template_report.fetch(:final_content)).to include("https://github.com/acme/example")
      expect(template_report.fetch(:final_content)).to include("Sponsor collective-acme/example on Open Source Collective")
      expect(template_report.fetch(:final_content)).to include("https://opencollective.com/collective-acme")
      expect(template_report.fetch(:final_content)).not_to include("https://opencollective.com/acme")

      described_class.apply_project(root, env: {})
      expect(File.read(File.join(root, "README.md"))).to eq(template_report.fetch(:final_content))
      expect(File.read(File.join(root, "FUNDING.md"))).to include(
        "Sponsor collective-acme/example on Open Source Collective"
      )
    end
  end

  it "trims README compatibility badges from minimum Ruby and engine config" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-compatibility-badge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # Example

          | Works with MRI Ruby 3 | [![Ruby 3.0 Compat][💎ruby-3.0i]][🚎4-lg-wf] [![Ruby 3.2 Compat][💎ruby-3.2i]][🚎6-s-wf] [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf] |
          | Works with JRuby | [![JRuby 10.0 Compat][💎jruby-10.0i]][🚎11-j-wf] |

          [💎ruby-3.0i]: https://example/ruby-30
          [💎ruby-3.2i]: https://example/ruby-32
          [💎ruby-c-i]: https://example/ruby-current
          [💎jruby-10.0i]: https://example/jruby-100
          [🚎4-lg-wf]: https://example/legacy
          [🚎6-s-wf]: https://example/supported
          [🚎11-c-wf]: https://example/current
          [🚎11-j-wf]: https://example/jruby
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = report.fetch(:final_content)
      mri_line = final_content.lines.find { |line| line.start_with?("| Works with MRI Ruby 3") }

      expect(mri_line).not_to include("ruby-3.0i")
      expect(mri_line).to include("ruby-3.2i")
      expect(mri_line).to include("ruby-c-i")
      expect(final_content).not_to include("Works with JRuby")
      expect(final_content).not_to match(/^\[💎ruby-3\.0i\]:/)
      expect(final_content).not_to match(/^\[💎jruby-10\.0i\]:/)
      expect(final_content).not_to match(/^\[🚎4-lg-wf\]:/)
      expect(final_content).not_to match(/^\[🚎11-j-wf\]:/)
      expect(final_content).to match(/^\[💎ruby-3\.2i\]:/)
      expect(final_content).to match(/^\[🚎6-s-wf\]:/)
      expect(final_content).to match(/^\[🚎11-c-wf\]:/)
    end
  end

  it "retains the MRI runtime floor when normalizing multi-engine compatibility text" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-compatibility-floor-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
            - jruby
            - truffleruby
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # Example

          Compatible with MRI Ruby {KJ|MIN_RUBY}+, and concordant releases of JRuby, and TruffleRuby.
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(report.fetch(:final_content)).to include(
        "Compatible with MRI Ruby 4.0.0+, JRuby, and TruffleRuby."
      )
    end
  end

  it "keeps Ruby 2.3 in the untested README support badge set" do
    template = File.read(project_root.join("lib/kettle/jem/templates/README.md.example"))
    ruby_2_line = template.lines.find { |line| line.start_with?("| Works with MRI Ruby 2") }

    expect(ruby_2_line).to include("![Ruby 2.2 Compat][💎ruby-2.2i] ![Ruby 2.3 Compat][💎ruby-2.3i] <br/>")
    expect(ruby_2_line).not_to include("[![Ruby 2.3 Compat][💎ruby-2.3i]][🚎ruby-2.3-wf]")
    expect(template).to include("[💎ruby-2.3i]: https://img.shields.io/badge/Ruby-2.3_(%F0%9F%9A%ABCI)-AABBCC")
    expect(template).not_to include("[🚎ruby-2.3-wf]:")
    expect(template).not_to include("[🚎ruby-2.3-wfi]:")
  end

  it "keeps current runtime badges distinct from prior-current engine badges" do
    template = File.read(project_root.join("lib/kettle/jem/templates/README.md.example"))
    ruby_4_line = template.lines.find { |line| line.start_with?("| Works with MRI Ruby 4") }
    jruby_line = template.lines.find { |line| line.start_with?("| Works with JRuby") }
    truffleruby_line = template.lines.find { |line| line.start_with?("| Works with Truffle Ruby") }

    expect(ruby_4_line).to include("[![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf]")
    expect(ruby_4_line).not_to include("Ruby 4.0 Compat")
    expect(jruby_line).to include("[![JRuby 10.0 Compat][💎jruby-10.0i]][🚎jruby-10.0-wf]")
    expect(jruby_line).to include("[![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf]")
    expect(truffleruby_line).to include("[![Truffle Ruby 33.0 Compat][💎truby-33.0i]][🚎truby-33.0-wf]")
    expect(truffleruby_line).to include("[![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf]")
    expect(truffleruby_line).to include("[![Truffle Ruby HEAD Compat][💎truby-headi]][🚎3-hd-wf]")
  end

  it "adds missing compatible versioned engine README badges when workflows exist" do
    readme = <<~MARKDOWN
      # Example

      | Works with JRuby | [![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf] [![JRuby HEAD Compat][💎jruby-headi]][🚎3-hd-wf]|
      | Works with Truffle Ruby | [![Truffle Ruby 24.2 Compat][💎truby-24.2i]][🚎truby-24.2-wf] [![Truffle Ruby 25.0 Compat][💎truby-25.0i]][🚎truby-25.0-wf] [![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf] [![Truffle Ruby HEAD Compat][💎truby-headi]][🚎3-hd-wf]|

      [🚎10-j-wf]: https://github.com/acme/example/actions/workflows/jruby.yml
      [🚎3-hd-wf]: https://github.com/acme/example/actions/workflows/heads.yml
      [🚎9-t-wf]: https://github.com/acme/example/actions/workflows/truffle.yml
      [🚎truby-24.2-wf]: https://github.com/acme/example/actions/workflows/truffleruby-24.2.yml
      [🚎truby-25.0-wf]: https://github.com/acme/example/actions/workflows/truffleruby-25.0.yml
      [💎jruby-c-i]: https://img.shields.io/badge/JRuby-current-FBE742
      [💎jruby-headi]: https://img.shields.io/badge/JRuby-HEAD-FBE742
      [💎truby-24.2i]: https://img.shields.io/badge/Truffle_Ruby-24.2-34BCB1
      [💎truby-25.0i]: https://img.shields.io/badge/Truffle_Ruby-25.0-34BCB1
      [💎truby-c-i]: https://img.shields.io/badge/Truffle_Ruby-current-34BCB1
      [💎truby-headi]: https://img.shields.io/badge/Truffle_Ruby-HEAD-34BCB1
    MARKDOWN

    processed = described_class::ReadmePostProcessor.process(
      content: readme,
      min_ruby: Gem::Version.new("3.2"),
      engines: %w[ruby jruby truffleruby],
      workflow_paths: %w[
        .github/workflows/jruby.yml
        .github/workflows/jruby-10.0.yml
        .github/workflows/truffle.yml
        .github/workflows/truffleruby-24.2.yml
        .github/workflows/truffleruby-25.0.yml
        .github/workflows/truffleruby-33.0.yml
        .github/workflows/heads.yml
      ]
    )

    expect(processed).to include("[![JRuby 10.0 Compat][💎jruby-10.0i]][🚎jruby-10.0-wf]")
    expect(processed).to include("| Works with Truffle Ruby |")
    expect(processed).to include("[🚎jruby-10.0-wf]: https://github.com/acme/example/actions/workflows/jruby-10.0.yml")
    expect(processed).not_to include("[🚎truby-33.0-wf]: https://github.com/acme/example/actions/workflows/truffleruby-33.0.yml")
    expect(processed).to include("[💎jruby-10.0i]: https://img.shields.io/badge/JRuby-10.0-FBE742")
    expect(processed).not_to include("[💎truby-33.0i]: https://img.shields.io/badge/Truffle_Ruby-33.0-34BCB1")
  end

  it "removes disabled engine workflow badges from top-level README references" do
    readme = <<~MARKDOWN
      # Example

      [![CI Truffle Ruby][🚎9-t-wfi]][🚎9-t-wf]

      | Works with Truffle Ruby | [![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf] |

      [🚎9-t-wf]: https://github.com/acme/example/actions/workflows/truffle.yml
      [🚎9-t-wfi]: https://github.com/acme/example/actions/workflows/truffle.yml/badge.svg
      [💎truby-c-i]: https://img.shields.io/badge/Truffle_Ruby-current-34BCB1
    MARKDOWN

    processed = described_class::ReadmePostProcessor.process(
      content: readme,
      min_ruby: "4.0",
      engines: ["ruby"]
    )

    expect(processed).not_to include("CI Truffle Ruby")
    expect(processed).not_to include("🚎9-t-wf")
    expect(processed).not_to include("🚎9-t-wfi")
    expect(processed).not_to include("💎truby-c-i")
  end

  it "keeps same-minor Ruby compatibility badges for patch-level runtime floors" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-patch-floor-badge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.2.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # Example

          | Works with MRI Ruby 1 | ![Ruby 1.8 Compat][💎ruby-1.8i] ![Ruby 1.9 Compat][💎ruby-1.9i] |
          | Works with MRI Ruby 2 | ![Ruby 2.1 Compat][💎ruby-2.1i] ![Ruby 2.2 Compat][💎ruby-2.2i] ![Ruby 2.3 Compat][💎ruby-2.3i] |

          [💎ruby-1.8i]: https://example/ruby-18
          [💎ruby-1.9i]: https://example/ruby-19
          [💎ruby-2.1i]: https://example/ruby-21
          [💎ruby-2.2i]: https://example/ruby-22
          [💎ruby-2.3i]: https://example/ruby-23
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = report.fetch(:final_content)
      ruby_2_line = final_content.lines.find { |line| line.start_with?("| Works with MRI Ruby 2") }

      expect(final_content).not_to include("Works with MRI Ruby 1")
      expect(ruby_2_line).not_to include("ruby-2.1i")
      expect(ruby_2_line).to include("ruby-2.2i")
      expect(ruby_2_line).to include("ruby-2.3i")
      expect(final_content).not_to match(/^\[💎ruby-2\.1i\]:/)
      expect(final_content).to match(/^\[💎ruby-2\.2i\]:/)
      expect(final_content).to match(/^\[💎ruby-2\.3i\]:/)
    end
  end

  it "keeps the Ruby 1.8 compatibility badge for a Ruby 1.8.7 runtime floor" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-ruby-18-badge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 1.8.7"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          engines:
            - ruby
          files:
            README.md:
              strategy: accept_template
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # Example

          | Works with MRI Ruby 1 | ![Ruby 1.8 Compat][💎ruby-1.8i] ![Ruby 1.9 Compat][💎ruby-1.9i] |

          [💎ruby-1.8i]: https://example/ruby-18
          [💎ruby-1.9i]: https://example/ruby-19
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = report.fetch(:final_content)
      mri_line = final_content.lines.find { |line| line.start_with?("| Works with MRI Ruby 1") }

      expect(mri_line).to include("ruby-1.8i")
      expect(mri_line).to include("ruby-1.9i")
      expect(final_content).to match(/^\[💎ruby-1\.8i\]:/)
      expect(final_content).to match(/^\[💎ruby-1\.9i\]:/)
    end
  end
end
