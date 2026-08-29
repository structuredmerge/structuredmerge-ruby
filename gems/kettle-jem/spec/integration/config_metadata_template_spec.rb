# frozen_string_literal: true

RSpec.describe Kettle::Jem, "configuration and metadata templating" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "projects project runtime template tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-project-runtime-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "2.4.6"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          min_divergence_threshold: "{KJ|MIN_DIVERGENCE_THRESHOLD}"
          defaults:
            freeze_token: custom-freeze
          rubyforum:
            family_tag: structuredmerge
            project_tag: ast-merge
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Gem shield: {KJ|GEM_SHIELD}
          Major: {KJ|GEM_MAJOR}
          GitHub org: {KJ|GH_ORG}
          Namespace shield: {KJ|NAMESPACE_SHIELD}
          Namespace badge: https://img.shields.io/badge/namespace-{KJ|NAMESPACE_SHIELD}-3C2D2D.svg
          Min dev Ruby: {KJ|MIN_DEV_RUBY}
          Freeze: {KJ|FREEZE_TOKEN}
          Version: {KJ|KETTLE_JEM_VERSION}
          Date: {KJ|TEMPLATE_RUN_DATE}
          Year: {KJ|TEMPLATE_RUN_YEAR}
          YARD: {KJ|YARD_HOST}
          Homepage URI: {KJ|HOMEPAGE_URI}
          Emoji: {KJ|PROJECT_EMOJI}
          Divergence: {KJ|MIN_DIVERGENCE_THRESHOLD}
          RubyForum tag: {KJ|RUBYFORUM:TAG}
          RubyForum URL: {KJ|RUBYFORUM:URL}
          RubyForum badge: {KJ|RUBYFORUM:BADGE_IMG}
          RubyForum badge FTB: {KJ|RUBYFORUM:BADGE_IMG_FTB}
        MARKDOWN
      })

      plan = described_class.plan_project(
        root,
        env: {
          "KJ_MIN_DIVERGENCE_THRESHOLD" => "12",
          "KJ_YARD_HOST" => "docs.example.test",
          "KJ_HOMEPAGE_URI" => "https://homepage.example.test"
        }
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Gem shield: example--gem")
      expect(final_content).to include("Major: 2")
      expect(final_content).to include("GitHub org: acme")
      expect(final_content).to include("Namespace shield: Example::Gem")
      expect(final_content).to include("Namespace badge: https://img.shields.io/badge/namespace-Example::Gem-3C2D2D.svg")
      expect(final_content).to include("Min dev Ruby: 3.2")
      expect(final_content).to include("Freeze: custom-freeze")
      expect(final_content).to include("Version: #{Kettle::Jem::VERSION}")
      expect(final_content).to include("Date: #{Time.now.strftime("%Y-%m-%d")}")
      expect(final_content).to include("Year: #{Time.now.year}")
      expect(final_content).to include("YARD: docs.example.test")
      expect(final_content).to include("Homepage URI: https://homepage.example.test")
      expect(final_content).to include("Emoji: 🫖")
      expect(final_content).to include("Divergence: 12")
      expect(final_content).to include("RubyForum tag: ast-merge")
      expect(final_content).to include("RubyForum URL: https://www.rubyforum.org/tag/ast-merge")
      expect(final_content).to include("RubyForum badge: https://img.shields.io/discourse/topics?server=https%3A%2F%2Fwww.rubyforum.org&style=flat&logo=discourse&label=Ruby%20Users%20Forum")
      expect(final_content).to include("RubyForum badge FTB: https://img.shields.io/discourse/topics?server=https%3A%2F%2Fwww.rubyforum.org&style=for-the-badge&logo=discourse&label=Ruby%20Users%20Forum")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|FREEZE_TOKEN" => "custom-freeze",
        "KJ|GEM_MAJOR" => "2",
        "KJ|GEM_SHIELD" => "example--gem",
        "KJ|GH_ORG" => "acme",
        "KJ|MIN_DEV_RUBY" => "3.2",
        "KJ|MIN_DIVERGENCE_THRESHOLD" => "12",
        "KJ|NAMESPACE_SHIELD" => "Example::Gem",
        "KJ|PROJECT_EMOJI" => "🫖",
        "KJ|HOMEPAGE_URI" => "https://homepage.example.test",
        "KJ|RUBYFORUM:TAG" => "ast-merge",
        "KJ|RUBYFORUM:URL" => "https://www.rubyforum.org/tag/ast-merge",
        "KJ|YARD_HOST" => "docs.example.test"
      )
    end
  end

  it "resolves known optional RubyForum tag tokens when unset" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubyforum-empty-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Family tag: {KJ|RUBYFORUM:FAMILY_TAG}
          Project tag: {KJ|RUBYFORUM:PROJECT_TAG}
          Effective URL: {KJ|RUBYFORUM:URL}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(template_report.fetch(:final_content)).to include("Family tag:\n")
      expect(template_report.fetch(:final_content)).to include("Project tag:\n")
      expect(template_report.fetch(:final_content)).not_to include("{KJ|RUBYFORUM:")
      expect(template_report.fetch(:final_content)).to include("Effective URL: https://www.rubyforum.org/tag/example-gem\n")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|RUBYFORUM:FAMILY_TAG" => "",
        "KJ|RUBYFORUM:PROJECT_TAG" => ""
      )
    end
  end

  it "honors configured project runtime URI tokens when ENV is absent" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-project-runtime-uri-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          yard_host: docs.config.test
          homepage_uri: https://homepage.config.test
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "YARD: {KJ|YARD_HOST}\nHomepage URI: {KJ|HOMEPAGE_URI}\n"
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(template_report.fetch(:final_content)).to eq("YARD: docs.config.test\nHomepage URI: https://homepage.config.test\n")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|HOMEPAGE_URI" => "https://homepage.config.test",
        "KJ|YARD_HOST" => "docs.config.test"
      )
    end
  end

  it "normalizes invalid underscores in configured project hostnames" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-project-runtime-hostname-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          yard_host: example_gem.example.test
          homepage_uri: https://example_gem.example.test/docs
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "YARD: {KJ|YARD_HOST}\nHomepage URI: {KJ|HOMEPAGE_URI}\n"
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(report.fetch(:final_content)).to eq("YARD: example-gem.example.test\nHomepage URI: https://example-gem.example.test/docs\n")
      normalized_config = described_class.send(:sync_kettle_config_env_overrides, File.read(File.join(root, ".kettle-jem.yml")), {})
      expect(normalized_config).to include('yard_host: "example-gem.example.test"')
      expect(normalized_config).to include('homepage_uri: "https://example-gem.example.test/docs"')
    end
  end

  it "syncs ENV-backed values back into kettle config during templating" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-env-config-sync", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          project_emoji: "🫖"
          min_divergence_threshold: 5 # ENV override: KJ_MIN_DIVERGENCE_THRESHOLD
          yard_host: docs.config.test # ENV override: KJ_YARD_HOST
          homepage_uri: https://homepage.config.test # ENV override: KJ_HOMEPAGE_URI
          rubygems:
            min_ruby: "3.1" # ENV override: KJ_MIN_RUBY
          rubyforum:
            family_tag: old-family # ENV override: KJ_RUBYFORUM_FAMILY_TAG
            project_tag: old-project # ENV override: KJ_RUBYFORUM_PROJECT_TAG
          kettle-jem:
            version: "1.0.0"
          tokens:
            forge:
              gh_user: config-user # GitHub username only. ENV: KJ_GH_USER
            author:
              orcid: "0000-0000-0000-0000"
          templates:
            root: packaged
            apply: true
        YAML
      })

      apply = described_class.apply_project(
        root,
        env: {
          "KJ_MIN_DIVERGENCE_THRESHOLD" => "12",
          "KJ_YARD_HOST" => "docs.env.test",
          "KJ_HOMEPAGE_URI" => "https://homepage.env.test",
          "KJ_MIN_RUBY" => "1.8.7",
          "KJ_GH_USER" => "env-user",
          "KJ_RUBYFORUM_FAMILY_TAG" => "structuredmerge",
          "KJ_RUBYFORUM_PROJECT_TAG" => "ast-merge"
        },
        run_options: {skip_commit: true}
      )
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == described_class::KETTLE_CONFIG_PATH }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.fetch("min_divergence_threshold")).to eq(12)
      expect(config.fetch("yard_host")).to eq("docs.env.test")
      expect(config.fetch("homepage_uri")).to eq("https://homepage.env.test")
      expect(config.dig("rubygems", "min_ruby")).to eq("1.8.7")
      expect(config.dig("rubyforum", "family_tag")).to eq("structuredmerge")
      expect(config.dig("rubyforum", "project_tag")).to eq("ast-merge")
      expect(config).not_to have_key("kettle-jem")
      expect(config.dig("tokens", "forge", "gh_user")).to eq("env-user")
      lock = YAML.safe_load_file(File.join(root, Kettle::Jem::KETTLE_LOCK_PATH))
      expect(lock.dig("template_state", "version")).to eq(Kettle::Jem::Version::VERSION)
      expect(report.fetch(:final_content)).to include("min_divergence_threshold: 12 # ENV override: KJ_MIN_DIVERGENCE_THRESHOLD")
      expect(report.fetch(:final_content)).to include('yard_host: "docs.env.test" # ENV override: KJ_YARD_HOST')
      expect(report.fetch(:final_content)).to include('homepage_uri: "https://homepage.env.test" # ENV override: KJ_HOMEPAGE_URI')
      expect(report.fetch(:final_content)).to include('min_ruby: "1.8.7" # ENV override: KJ_MIN_RUBY')
      expect(report.fetch(:final_content)).to include('family_tag: "structuredmerge" # ENV override: KJ_RUBYFORUM_FAMILY_TAG')
      expect(report.fetch(:final_content)).to include('project_tag: "ast-merge" # ENV override: KJ_RUBYFORUM_PROJECT_TAG')
      expect(report.fetch(:final_content)).not_to include("kettle-jem:")
      expect(report.fetch(:final_content)).to include('gh_user: "env-user" # GitHub username only. ENV: KJ_GH_USER')
      expect(File.read(File.join(root, described_class::KETTLE_CONFIG_PATH))).to eq(report.fetch(:final_content))
    end
  end

  it "canonicalizes an unset divergence threshold without trailing whitespace" do
    content = "project_emoji: \"🫖\"\nmin_divergence_threshold: \n"

    synced = described_class.send(:sync_kettle_config_env_overrides, content, {})

    expect(synced).to include('min_divergence_threshold: ""')
    expect(synced).not_to match(/[ \t]+\n/)
    expect(YAML.safe_load(synced).fetch("min_divergence_threshold")).to eq("")
  end

  it "sets gemspec mailing_list_uri from the effective RubyForum tag" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubyforum-gemspec-metadata", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.metadata["source_code_uri"] = "\#{spec.homepage}/tree/v\#{spec.version}"
            spec.metadata["mailing_list_uri"] = "https://groups.google.com/g/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubyforum:
            family_tag: structuredmerge
            project_tag: ast-merge
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/example"
            spec.metadata["source_code_uri"] = "\#{spec.homepage}/tree/v\#{spec.version}"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "example.gemspec" }
      final_content = report.fetch(:final_content)

      expect(Prism.parse(final_content)).to be_success
      expect(final_content).to include('spec.metadata["mailing_list_uri"] = "https://www.rubyforum.org/tag/ast-merge"')
      expect(final_content).not_to include("groups.google.com")
    end
  end

  it "prunes legacy kettle config keys after their replacement exists" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-legacy-config-key-cleanup", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "🫖"
          # README top logo mode.
          # Controls whether the generated README header includes the GitHub org logo,
          # the project logo, or both after the shared Galtzo and ruby-lang logos.
          # Supported values: org, project, org_and_project
          # Default (when key is absent): org_and_project
          readme:
            top_logos: related-org,ruby,org
            top_logo_mode: org_and_project
          templates:
            root: packaged
            apply: true
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.dig("readme", "top_logos")).to eq("org")
      expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
      expect(config.fetch("readme")).not_to have_key("top_logo_mode")
      expect(report.fetch(:final_content)).not_to include("top_logo_mode:")
      expect(report.fetch(:final_content)).to include("# README top logos.")
      expect(report.fetch(:final_content)).to include("# top_logos render above the title; h2_synopsis_logos render inline with the Synopsis H2.")
      expect(report.fetch(:final_content)).to include("# Supported values: related-org, ruby, org, project")
      citation_report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "CITATION.cff" }
      expect(citation_report.fetch(:final_content)).to include("orcid: 'https://orcid.org/'")
      expect(citation_report.fetch(:final_content)).not_to include("{KJ|AUTHOR:ORCID}")
      expect(File.read(File.join(root, ".structuredmerge/kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "migrates legacy-only README top logo mode config" do
    content = <<~YAML
      readme:
        top_logo_mode: org
    YAML

    migrated = described_class.send(:sync_kettle_config_env_overrides, content, {})
    config = YAML.safe_load(migrated)

    expect(config.dig("readme", "top_logos")).to eq("org")
    expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
    expect(config.fetch("readme")).not_to have_key("top_logo_mode")
  end

  it "migrates comma-separated legacy README top logo mode config" do
    content = <<~YAML
      readme:
        top_logo_mode: org, project
    YAML

    migrated = described_class.send(:sync_kettle_config_env_overrides, content, {})
    config = YAML.safe_load(migrated)

    expect(config.dig("readme", "top_logos")).to eq("org,project")
    expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
    expect(config.fetch("readme")).not_to have_key("top_logo_mode")
  end

  it "removes duplicated legacy config documentation without removing YAML settings" do
    content = <<~YAML
      # Framework matrix workflows.
      # Generated matrix documentation.

      workflows:
        exec_cmd: kettle-test

      # Framework matrix workflows.
      # Generated matrix documentation.

      # README top logos.
      readme:
        top_logos: org
        # Sections to preserve from the destination README during template merging.
        # Generated README preservation documentation.

        badges:
          fossa: false
        # Sections to preserve from the destination README during template merging.
        # Generated README preservation documentation.

      # SPDX license identifiers for this project.
      licenses:
        - MIT
    YAML

    output = described_class.send(:sync_kettle_config_env_overrides, content, {})

    expect(output.scan("# Framework matrix workflows.").size).to eq(1)
    expect(output.scan("# Sections to preserve from the destination README during template merging.").size).to eq(1)
    expect(YAML.safe_load(output).dig("workflows", "exec_cmd")).to eq("kettle-test")
    expect(YAML.safe_load(output).dig("readme", "badges", "fossa")).to be(false)
  end

  it "refreshes legacy author names documentation without changing config values" do
    content = <<~YAML
      # Safe automatic derivations currently implemented:
      #   AUTHOR:NAME         <- first author from the gemspec
      #   AUTHOR:NAMES        <- all authors from the gemspec, or copyright holders if no gemspec authors exist
      #   AUTHOR:EMAIL        <- first email from the gemspec

      author_aliases:
        "old@example.test": Canonical Author
    YAML

    output = described_class.send(:sync_kettle_config_documentation_comments, content)

    expect(output).to include("#   AUTHOR:NAMES        <- existing gemspec authors plus Git-derived copyright holders\n")
    expect(output).to include("#                           (after author_aliases consolidation)\n")
    expect(YAML.safe_load(output).fetch("author_aliases")).to eq("old@example.test" => "Canonical Author")
  end

  it "refreshes legacy author token documentation" do
    content = <<~YAML
      tokens:
        author:
          name: "Peter H. Boling" # Auto-seeded from gemspec authors.first; generated gemspec authors preserve the full existing authors array via AUTHOR:NAMES.
    YAML

    output = described_class.send(:sync_kettle_config_documentation_comments, content)

    expect(output).to include("AUTHOR:NAMES preserves existing gemspec authors and appends Git-derived copyright holders.")
    expect(output).not_to include("generated gemspec authors preserve the full existing authors array via AUTHOR:NAMES.")
  end

  it "preserves explicit kettle config values while refreshing the config template" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-destination-values", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          defaults:
            preference: destination
            add_template_only_nodes: true
          project_emoji: "🫖"
          repository:
            topology: standalone
          readme:
            top_logos: org,project
            h2_synopsis_logos: related-org,ruby
          templates:
            root: packaged
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.fetch("project_emoji")).to eq("🫖")
      expect(config.dig("repository", "topology")).to eq("standalone")
      expect(config.dig("readme", "top_logos")).to eq("org,project")
      expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
      expect(File.read(File.join(root, ".structuredmerge/kettle-jem.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "normalizes combined top logo config when Synopsis H2 logos already exist" do
    content = <<~YAML
      readme:
        top_logos: related-org,ruby,org
        h2_synopsis_logos: related-org,ruby
    YAML

    migrated = described_class.send(:sync_kettle_config_env_overrides, content, {})
    config = YAML.safe_load(migrated)

    expect(config.dig("readme", "top_logos")).to eq("org")
    expect(config.dig("readme", "h2_synopsis_logos")).to eq("related-org,ruby")
  end

  it "derives source and forge tokens from git origin when gemspec metadata is absent" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-origin-token-slice", tmp_root) do |root|
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
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Source: {KJ|GH_ORG}
          GitHub user: {KJ|GH:USER}
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:acme/example.git")).to be(true)

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      expect(plan.dig(:facts, :package, :source_url)).to eq("https://github.com/acme/example")
      expect(template_report.fetch(:final_content)).to include("Source: acme")
      expect(template_report.fetch(:final_content)).to include("GitHub user: acme")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|GH_ORG" => "acme",
        "KJ|GH:USER" => "acme"
      )
    end
  end

  it "prefers git origin over stale generated gemspec homepage metadata" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-stale-homepage-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/pboling/example"
            spec.metadata["source_code_uri"] = "\#{spec.homepage}/tree/v\#{spec.version}"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
              - README.md
        YAML
        "template/example.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.homepage = "{KJ|README:GH_REPOSITORY_URL}"
          end
        RUBY
        "template/README.md.example" => <<~MARKDOWN
          Source: {KJ|GH_ORG}
          GitHub user: {KJ|GH:USER}
          Repository: {KJ|README:GH_REPOSITORY_URL}
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:rubocop-lts/example.git")).to be(true)

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(plan.dig(:facts, :package, :source_url)).to eq("https://github.com/rubocop-lts/example")
      expect(plan.dig(:facts, :package, :homepage_url)).to eq("https://github.com/rubocop-lts/example")
      expect(template_report.fetch(:final_content)).to include("Source: rubocop-lts")
      expect(template_report.fetch(:final_content)).to include("GitHub user: rubocop-lts")
      expect(template_report.fetch(:final_content)).to include("Repository: https://github.com/rubocop-lts/example")

      apply = described_class.apply_project(root, env: {})
      expect(apply[:changed_files]).to include("example.gemspec")
      expect(File.read(File.join(root, "example.gemspec"))).to include('spec.homepage = "https://github.com/rubocop-lts/example"')
    end
  end

  it "normalizes destination gemspec Dir globs into the template files assignment" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-files-preserve", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.files = Dir[
              "lib/**/*.rb",
              "rubocop-lts/**/*.yml",
              "README.md"
            ]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            enumerate_package_files = lambda do |root|
              Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
                File.file?(path) && ![".", ".."].include?(File.basename(path))
              end
            end

            spec.name = "example"
            spec.summary = "Template summary"
            spec.files = [
              *enumerate_package_files.call("lib"),
              *enumerate_package_files.call("exe"),
              *enumerate_package_files.call("certs"),
              *enumerate_package_files.call("sig")
            ]
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      final_content = template_report.fetch(:final_content)

      expect(Prism.parse(final_content)).to be_success
      expect(final_content).to include("spec.files = [")
      expect(final_content).not_to include("spec.files = Dir[")
      expect(final_content).not_to include("] + [")
      expect(final_content).to include('*enumerate_package_glob.call(File.join(gemspec_root, "rubocop-lts/**/*.yml"))')
      expect(final_content).to include('*enumerate_package_files.call("exe")')
      expect(final_content.index('*enumerate_package_glob.call(File.join(gemspec_root, "rubocop-lts/**/*.yml"))')).to be < final_content.index('*enumerate_package_files.call("lib")')
      expect(final_content.scan(/^\s*"lib\/\*\*\/\*\.rb",/)).to be_empty
    end
  end

  it "replaces old broad generated gemspec manifests with the minimal package manifest" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-files-minimal-package", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.authors = ["Jane Q Public"]
            spec.email = ["jane@example.test"]
            spec.licenses = ["MIT"]

            enumerate_package_files = lambda do |root|
              Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
                File.file?(path) && ![".", ".."].include?(File.basename(path))
              end
            end

            # Specify which files are part of the released package.
            spec.files = [
              "LICENSE.md",
              "MIT.md",
              "CITATION.cff",
              "CODE_OF_CONDUCT.md",
              "CONTRIBUTING.md",
              "FUNDING.md",
              "README.md",
              "RUBOCOP.md",
              "SECURITY.md",
              "config/runtime.yml",
              *enumerate_package_files.call("lib"),
              *enumerate_package_files.call("exe"),
              *enumerate_package_files.call("certs"),
              *enumerate_package_files.call("sig")
            ]

            spec.extra_rdoc_files = Dir[
              "CHANGELOG.md",
              "CITATION.cff",
              "CODE_OF_CONDUCT.md",
              "CONTRIBUTING.md",
              "FUNDING.md",
              "LICENSE.md",
              "README.md",
              "RUBOCOP.md",
              "SECURITY.md"
            ]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          tokens:
            author:
              orcid: "0000-0000-0000-0000"
          templates:
            root: packaged
            apply: true
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      gemspec = File.read(File.join(root, "example.gemspec"))
      files_assignment = described_class.gemspec_assignment_records(gemspec, receiver: "spec").find do |record|
        record.fetch(:field) == "files"
      end.fetch(:source)

      expect(apply[:changed_files]).to include("example.gemspec")
      expect(Prism.parse(gemspec)).to be_success
      expect(gemspec).to include("CHANGELOG.md")
      expect(gemspec).to include("LICENSE.md")
      expect(gemspec).to include("README.md")
      expect(gemspec).to include("sig/example.rbs")
      expect(gemspec).to include("files = []")
      expect(gemspec).not_to include("filter_map")
      expect(files_assignment).to include("*package_metadata_files")
      expect(files_assignment).to include('"config/runtime.yml"')
      expect(files_assignment).to include('*enumerate_package_files.call("lib")')
      expect(files_assignment).to include('*enumerate_package_files.call("exe")')
      expect(files_assignment).not_to include('"LICENSE.md"')
      expect(files_assignment).not_to include('"README.md"')
      expect(files_assignment).not_to include("MIT.md")
      expect(files_assignment).not_to include("CITATION.cff")
      expect(files_assignment).not_to include("CODE_OF_CONDUCT.md")
      expect(files_assignment).not_to include("CONTRIBUTING.md")
      expect(files_assignment).not_to include("FUNDING.md")
      expect(files_assignment).not_to include("RUBOCOP.md")
      expect(files_assignment).not_to include("SECURITY.md")
      expect(files_assignment).not_to include('*enumerate_package_files.call("certs")')
      expect(files_assignment).not_to include('*enumerate_package_files.call("sig")')
      expect(gemspec).not_to include("spec.extra_rdoc_files")
    end
  end

  it "emits modern generated gemspec package helpers for modern Ruby floors" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-files-modern-ruby", tmp_root) do |root|
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
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, "gem.gemspec.example"))
      })

      described_class.apply_project(root, env: {})
      gemspec = File.read(File.join(root, "example.gemspec"))

      expect(gemspec).to include('path.delete_prefix("#{gemspec_root}/")')
      expect(gemspec).to include("filter_map")
      expect(gemspec).not_to include("files = []")
      expect { RubyVM::InstructionSequence.compile(gemspec) }.not_to raise_error
    end
  end

  it "merges recursive config package files without preserving stale frozen files overrides" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-files-recursive-config", tmp_root) do |root|
      write_tree(root, {
        "standard-rubocop-lts.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "standard-rubocop-lts"
            spec.files = Dir[
              "config/**/*.yml",
              "lib/**/*.rb",
              "README.md"
            ]

            # kettle-jem:freeze
            spec.files = Dir[
              "config/*.yml",
              "lib/**/*.rb",
              "README.md"
            ]
            # kettle-jem:unfreeze
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - standard-rubocop-lts.gemspec
        YAML
        "template/standard-rubocop-lts.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            enumerate_package_files = lambda do |root|
              Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
                File.file?(path) && ![".", ".."].include?(File.basename(path))
              end
            end

            spec.name = "standard-rubocop-lts"
            spec.files = [
              *enumerate_package_files.call("lib"),
              *enumerate_package_files.call("exe"),
              *enumerate_package_files.call("certs"),
              *enumerate_package_files.call("sig")
            ]
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_standard_rubocop_lts_gemspec"
      end
      final_content = template_report.fetch(:final_content)

      expect(Prism.parse(final_content)).to be_success
      expect(final_content.scan(/^\s*spec\.files\s*=/).size).to eq(1)
      expect(final_content).to include('"config/**/*.yml"')
      expect(final_content).to include('*enumerate_package_files.call("lib")')
      expect(final_content).not_to include("# kettle-jem:freeze")
      expect(final_content).not_to include('"config/*.yml"')
    end
  end

  it "unions literal Dir gemspec files assignments from destination and template" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-files-dir-union", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.files = Dir[
              "sig/**/*.rbs",
              "rubocop-lts/**/*.yml",
            ]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.files = Dir[
              "lib/**/*.rb",
              "sig/**/*.rbs",
              "README.md",
            ]
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      final_content = template_report.fetch(:final_content)

      expect(Prism.parse(final_content)).to be_success
      expect(final_content).to include("spec.files = Dir[")
      expect(final_content.index('"rubocop-lts/**/*.yml"')).to be < final_content.index('"lib/**/*.rb"')
      expect(final_content.scan('"sig/**/*.rbs"').size).to eq(1)
      expect(final_content).to include('"README.md"')
    end
  end

  it "fails hard on unsupported custom nonliteral destination gemspec files assignments" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-files-custom", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            enumerate_package_files = lambda do |root|
              Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
                File.file?(path) && ![".", ".."].include?(File.basename(path))
              end
            end
            spec.files = [
              *Dir["lib/**/*.rb"],
              *enumerate_package_files.call("template"),
              *Dir["sig/**/*.rbs"],
            ]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.files = Dir[
              "lib/**/*.rb",
              "sig/**/*.rbs",
            ]
          end
        RUBY
      })

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(Kettle::Jem::Error, /Unsupported gemspec spec\.files assignment/)
    end
  end

  it "preserves destination splat files assignments without appending duplicate template splats" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        # Specify which files are part of the released package.
        spec.files = [
          # Root license files
          "LICENSE.md",
          "MIT.md",
          # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
          *enumerate_package_files.call("lib"),
          # Executables and executable support scripts
          *enumerate_package_files.call("exe"),
          # Public certs for gem signing
          *enumerate_package_files.call("certs"),
          # Signatures
          *enumerate_package_files.call("sig")
        ]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        enumerate_package_files = lambda do |root|
          Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
            File.file?(path) && ![".", ".."].include?(File.basename(path))
          end
        end

        # Specify which files are part of the released package.
        spec.files = [
          # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
          *enumerate_package_files.call('lib'),
          # Executables and executable support scripts
          *enumerate_package_files.call('exe'),
          # Public certs for gem signing
          *enumerate_package_files.call('certs'),
          # Signatures
          *enumerate_package_files.call('sig')
        ]
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "example"}})

    expect(Prism.parse(merged)).to be_success
    expect(merged.scan(/^\s*spec\.files\s*=/).size).to eq(1)
    expect(merged).to include('"LICENSE.md"')
    expect(merged).to include('"MIT.md"')
    lib_splat_index = merged =~ /\*enumerate_package_files\.call\(["']lib["']\)/
    expect(lib_splat_index).not_to be_nil
    expect(merged.index('"MIT.md"')).to be < lib_splat_index
    expect(merged).to match(/^\s*\*enumerate_package_files\.call\(["']sig["']\)\n/)
    expect(merged.scan(/\*enumerate_package_files\.call\(["']lib["']\)/).size).to eq(1)
  end

  it "normalizes the generated Dir plus Array gemspec files assignment shape" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        package_metadata_files = %w[
          CHANGELOG.md
          LICENSE.md
          README.md
        ]
        # Specify which files are part of the released package.
        spec.files = [
          # Root package metadata
          *package_metadata_files,
          # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
          *enumerate_package_files.call("lib"),
          # Executables and executable support scripts
          *enumerate_package_files.call("exe")
        ]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        enumerate_package_files = lambda do |root|
          Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
            File.file?(path) && ![".", ".."].include?(File.basename(path))
          end
        end

        # Specify which files are part of the released package.
        spec.files = Dir[
          # Splats (alphabetical)
          "config/*.yml",
          "lib/**/*.rb"
        ] + [
          "LICENSE.md",
          "MIT.md",
          # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
          *enumerate_package_files.call("lib"),
          # Executables and executable support scripts
          *enumerate_package_files.call("exe"),
          # Public certs for gem signing
          *enumerate_package_files.call("certs"),
          # Signatures
          *enumerate_package_files.call("sig"),
          "CHANGELOG.md",
          "CODE_OF_CONDUCT.md",
          "CONTRIBUTING.md",
          "README.md",
          "rubocop-lts.yml",
          "SECURITY.md"
        ]
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "example"}})
    remerged = described_class.merge_gemspec_template_source(template, merged, facts: {package: {name: "example"}})

    expect(Prism.parse(merged)).to be_success
    expect(merged).to include("spec.files = [")
    expect(merged).not_to include("spec.files = Dir[")
    expect(merged).not_to include("] + [")
    expect(merged).not_to include('"lib/**/*.rb"')
    expect(merged).to include('*enumerate_package_glob.call(File.join(gemspec_root, "config/*.yml"))')
    expect(merged).to include('"rubocop-lts.yml"')
    expect(merged).not_to include('*enumerate_package_files.call("certs")')
    expect(merged).not_to include('*enumerate_package_files.call("sig")')
    expect(merged.scan('*enumerate_package_files.call("lib")').size).to eq(1)
    expect(merged.scan('*enumerate_package_glob.call(File.join(gemspec_root, "config/*.yml"))').size).to eq(1)
    expect(merged.scan("spec.files =").size).to eq(1)
    expect(remerged).to eq(merged)
  end

  it "projects README top logo template tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-logo-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Galtzo FLOSS Logo")
      expect(final_content).to include("ruby-lang Logo")
      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="acme Logo by GitHub" src="https://github.com/acme.png?size=192" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme/example-gem"><img alt="example-gem Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/example-gem/avatar-128px.svg" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://discord.gg/3qme4XHNKN"><img alt="Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).not_to include("[🖼️acme-example-gem]:")
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|README:TOP_LOGO_REFS" => "",
        "KJ|README:TOP_LOGO_ROW" => a_string_including("example-gem Logo by Aboling0"),
        "KJ|README:H2_SYNOPSIS_LOGO_ROW" => a_string_including("ruby-lang Logo")
      )
    end
  end

  it "allows README logo options to override rendered widths" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-logo-width-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: org|96px
            h2_synopsis_logos: ruby|12%
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)

      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="acme Logo by GitHub" src="https://github.com/acme.png?size=192" width="96px" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="12%" align="right"/></a>))
    end
  end

  it "renders configured corporate sponsor logos near the top of README" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-sponsor-token-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            corporate_sponsors:
              - name: Example & Sons
                url: https://example.com/sponsor?from=kettle&level=gold
                img_src: https://example.com/logo.svg?badge=1&size=small
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Top funding row.
          {KJ|README:CORPORATE_SPONSORS}

          ## 🦷 FLOSS Funding
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expected_sponsor_row = [
        %(<p><sub>Corporate sponsor: <a href="https://example.com/sponsor?from=kettle&amp;level=gold">),
        %(<img alt="Example &amp; Sons" src="https://example.com/logo.svg?badge=1&amp;size=small" height="24"/>),
        %(</a> <a href="#-floss-funding">Become a sponsor</a></sub></p>)
      ].join

      expect(final_content).to include(expected_sponsor_row)
      expect(template_report.dig(:metadata, :template_tokens)).to include(
        "KJ|README:CORPORATE_SPONSORS" => a_string_including("Corporate sponsor:")
      )
    end
  end

  it "renders corporate sponsors inherited from kettle-family environment" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-family-sponsor-token-slice", tmp_root) do |root|
      sponsors_json = JSON.generate([
        {
          "name" => "Family Sponsor",
          "url" => "https://family.example",
          "img_src" => "https://family.example/logo.svg"
        }
      ])
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "{KJ|README:CORPORATE_SPONSORS}\n"
      })

      plan = described_class.plan_project(
        root,
        env: {"KETTLE_JEM_CORPORATE_SPONSORS_JSON" => sponsors_json}
      )
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end

      expect(template_report.fetch(:final_content)).to include(
        %(<img alt="Family Sponsor" src="https://family.example/logo.svg" height="24"/>)
      )
      expect(plan.dig(:facts, :readme_sponsors, :entries)).to eq([
        {
          name: "Family Sponsor",
          url: "https://family.example",
          img_src: "https://family.example/logo.svg"
        }
      ])
    end
  end

  it "keeps generated Synopsis H2 logo HTML when normalizing existing README headings and prunes stale logo refs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-synopsis-logo-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🫖"
          readme:
            top_logos: org
            h2_synopsis_logos: related-org,ruby
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          [🖼️galtzo-floss]: https://discord.gg/3qme4XHNKN
          [🖼️ruby-lang]: https://ruby-toolbox.com

          # Old Title

          ## 🌻 Synopsis

          Existing synopsis.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          {KJ|README:TOP_LOGO_ROW}

          {KJ|README:TOP_LOGO_REFS}

          # {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}

          ## 🌻 Synopsis {KJ|README:H2_SYNOPSIS_LOGO_ROW}
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "README.md" }
      final_content = report.fetch(:final_content)

      expect(final_content).to include("# 🫖 Example::Gem\n")
      expect(final_content).to include("## 🌻 Synopsis <a href=\"https://discord.gg/3qme4XHNKN\"")
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo,))
      expect(final_content).not_to include("[🖼️galtzo-floss]:")
      expect(final_content).not_to include("[🖼️ruby-lang]:")
      expect(final_content).not_to include("\n\n\n")
    end
  end

  it "separates full template profile from monorepo sub-project URL topology" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-monorepo-url-topology-slice", tmp_root) do |root|
      gem_root = File.join(root, "gems", "kettle-jem")
      write_tree(gem_root, {
        "kettle-jem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-jem"
            spec.summary = "Kettle gem templater"
            spec.metadata["source_code_uri"] = "https://github.com/structuredmerge/kettle-jem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: project
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:structuredmerge/structuredmerge-ruby.git")).to be(true)

      plan = described_class.plan_project(
        gem_root,
        env: {
          "KETTLE_JEM_TEMPLATE_PROFILE" => "full",
          "KJ_REPOSITORY_TOPOLOGY" => "monorepo-subproject"
        }
      )
      expect(plan.dig(:facts, :template_profile)).to eq("full")
      expect(plan.dig(:facts, :repository, :mode)).to eq("monorepo_subproject")
      expect(plan.dig(:facts, :readme_logo, :top_logo_row)).to include("structuredmerge/structuredmerge-ruby/kettle-jem/avatar-128px.svg")
      expect(plan.dig(:facts, :readme_logo, :top_logo_refs).to_s).to eq("")
    end
  end

  it "does not invent a gems path for a monorepo topology when the project is the git root" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-root-monorepo-topology-slice", tmp_root) do |root|
      write_tree(root, {
        "nomono.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "nomono"
            spec.summary = "Bundler path helper"
            spec.metadata["source_code_uri"] = "https://github.com/kettle-dev/nomono"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          repository:
            topology: monorepo-subproject
          templates:
            root: template
            apply: true
            profile: full
            entries:
              - README.md
        YAML
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)
      expect(system("git", "-C", root, "remote", "add", "origin", "git@github.com:kettle-dev/nomono.git")).to be(true)

      repository = described_class.send(
        :repository_facts,
        root,
        "https://github.com/kettle-dev/nomono",
        package_name: "nomono",
        repository_topology: "monorepo-subproject"
      )
      tokens = described_class.send(:readme_url_template_tokens, repository, "nomono", "kettle-rb")

      expect(repository[:mode]).to eq("monorepo_subproject")
      expect(repository).not_to have_key(:package_path)
      expect(tokens.fetch("KJ|README:GL_PACKAGE_SOURCE_URL")).to eq("https://gitlab.com/kettle-dev/nomono")
      expect(tokens.fetch("KJ|README:CB_PACKAGE_SOURCE_URL")).to eq("https://codeberg.org/kettle-dev/nomono")
      expect(tokens.fetch("KJ|README:GH_PACKAGE_SOURCE_URL")).to eq("https://github.com/kettle-dev/nomono")
      expect(tokens.values_at(
        "KJ|README:GL_PACKAGE_SOURCE_URL",
        "KJ|README:CB_PACKAGE_SOURCE_URL",
        "KJ|README:GH_PACKAGE_SOURCE_URL"
      ).join("\n")).not_to include("/gems/nomono")
    end
  end

  it "projects README logo row entries from named logo options" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-named-logo-options-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: related-org,ruby,org,project,unknown
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include(%(<a href="https://discord.gg/3qme4XHNKN"><img alt="Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" width="8%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="acme Logo by GitHub" src="https://github.com/acme.png?size=192" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme/example-gem"><img alt="example-gem Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/example-gem/avatar-128px.svg" width="12%" align="right"/></a>))
      expect(final_content).not_to include("[🖼️galtzo-floss]:")
      expect(final_content).not_to include("[🖼️acme-example-gem]:")
      expect(final_content).not_to include("unknown")
    end
  end

  it "deduplicates README logos by asset while preserving the related-org link" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-duplicate-logo-assets-slice", tmp_root) do |root|
      write_tree(root, {
        "turbo_tests2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "turbo_tests2"
            spec.summary = "Turbo tests"
            spec.metadata["source_code_uri"] = "https://github.com/galtzo-floss/turbo_tests2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logos: related-org,ruby,org,project
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).not_to include("[🖼️galtzo-floss]:")
      expect(final_content).not_to include("[🖼️galtzo-floss]: https://github.com/galtzo-floss")
      expect(final_content.scan("galtzo-floss/avatar-128px.svg").length).to eq(1)
      expect(final_content).to include(%(<a href="https://github.com/galtzo-floss"><img alt="galtzo-floss Logo by GitHub" src="https://github.com/galtzo-floss.png?size=192" width="12%" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/galtzo-floss/turbo_tests2"><img alt="turbo_tests2 Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/galtzo-floss/turbo_tests2/avatar-128px.svg" width="12%" align="right"/></a>))
    end
  end

  it "maps legacy README top logo modes to named logo options" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-legacy-logo-mode-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            top_logo_mode: org
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Synopsis:
          {KJ|README:H2_SYNOPSIS_LOGO_ROW}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include("Galtzo FLOSS Logo")
      expect(final_content).to include("ruby-lang Logo")
      expect(final_content).to include("acme Logo")
      expect(final_content).not_to include("example-gem Logo")
    end
  end

  it "projects configured README logo row entries by normalized logo type" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-typed-logo-slice", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.summary = "Example gem"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            logo_row:
              enabled: true
              logos:
                - type: language
                  slug: ruby-lang
                  alt: Ruby language logo
                - type: org
                  slug: acme
                  alt: Acme org logo
                - type: affiliated_project
                  slug: tree-sitter/tree-sitter
                  alt: Tree-sitter project logo
                - type: project
                  slug: acme/ignored
                  alt: Ignored fourth logo
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          Row:
          {KJ|README:TOP_LOGO_ROW}
          Refs:
          {KJ|README:TOP_LOGO_REFS}
        MARKDOWN
      })

      plan = described_class.plan_project(root, env: {})
      template_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = template_report.fetch(:final_content)
      expect(final_content).to include(%(<a href="https://ruby-toolbox.com"><img alt="Ruby language Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5" src="https://logos.galtzo.com/assets/images/ruby-lang/avatar-128px.svg" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme"><img alt="Acme org Logo by GitHub" src="https://github.com/acme.png?size=192" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://logos.galtzo.com/assets/images/tree-sitter/tree-sitter/"><img alt="Tree-sitter project Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/tree-sitter/tree-sitter/avatar-128px.svg" align="right"/></a>))
      expect(final_content).to include(%(<a href="https://github.com/acme/example-gem"><img alt="Ignored fourth Logo by Aboling0, CC BY-SA 4.0" src="https://logos.galtzo.com/assets/images/acme/ignored/avatar-128px.svg" align="right"/></a>))
    end
  end

  it "fails fast when template application leaves unresolved tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-unresolved-slice", tmp_root) do |root|
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
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|UNKNOWN}
        MARKDOWN
      })

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /unresolved kettle-jem template tokens: \{KJ\|UNKNOWN\}/)
    end
  end

  it "fails fast when resolved kettle config YAML values retain template tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-token-leak-slice", tmp_root) do |root|
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
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
        YAML
        "template/.structuredmerge/kettle-jem.yml.example" => <<~YAML
          project_emoji: "🧪"
          rubyforum:
            family_tag: "{KJ|UNKNOWN}"
        YAML
      })

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /\.structuredmerge\/kettle-jem\.yml: unresolved kettle-jem template tokens: \{KJ\|UNKNOWN\}/)
    end
  end

  it "resolves known template tokens retained in destination kettle config YAML values" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-known-token-migration-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          project_emoji: "🧪"
          yard_host: "{KJ|YARD_HOST}"
          homepage_uri: "{KJ|HOMEPAGE_URI}"
          templates:
            root: packaged
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
        YAML
      })

      report = described_class.plan_project(root, env: {}).fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml"
      end
      content = report.fetch(:final_content)

      expect(content).to include('yard_host: "example.example.com"')
      expect(content).to include('homepage_uri: "https://example.example.com"')
      expect(content).not_to include("{KJ|YARD_HOST}")
      expect(content).not_to include("{KJ|HOMEPAGE_URI}")
    end
  end

  it "reports template checksum drift" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-drift-slice", tmp_root) do |root|
      write_tree(root, {
        "templates/README.md.example" => "# Example\n",
        "templates/.github/FUNDING.yml.example" => "github: [example]\n",
        ".kettle-jem.yml" => <<~YAML
          project: example

          kettle-jem:
            version: "0.1.0"
            checksums:
              "README.md.example": "old"
              "removed.md.example": "gone"
        YAML
      })

      current = described_class::TemplateChecksums.compute(template_root: File.join(root, "templates"))
      stored = described_class::TemplateChecksums.load_stored(config_path: File.join(root, ".kettle-jem.yml"))
      drift = described_class::TemplateChecksums.diff(current: current, stored: stored)

      expect(current.keys).to eq([".github/FUNDING.yml.example", "README.md.example"])
      expect(drift).to eq(
        added: [".github/FUNDING.yml.example"],
        changed: ["README.md.example"],
        removed: ["removed.md.example"]
      )
      expect(described_class::TemplateChecksums.diff_count(drift)).to eq(3)
      expect(described_class::TemplateChecksums.summary(drift)).to eq(
        "3 template file(s) since last run: 1 added, 1 changed, 1 removed"
      )
      expect(described_class::TemplateChecksums.detail_lines(drift)).to eq([
        "  + .github/FUNDING.yml.example",
        "  ~ README.md.example",
        "  - removed.md.example"
      ])

      described_class::TemplateChecksums.write_to_config(
        config_path: File.join(root, ".kettle-jem.yml"),
        checksums: current,
        version: "1.2.3",
        applied_at: "2026-07-24",
        changelog_replay: {
          "last_entry_key" => "kettle-jem-template-20260720-005",
          "last_entry_date" => "2026-07-20"
        }
      )
      rewritten = YAML.safe_load_file(File.join(root, ".kettle-jem.yml"))
      expect(rewritten.fetch("kettle-jem").fetch("version")).to eq("1.2.3")
      expect(rewritten.fetch("kettle-jem").fetch("applied_at")).to eq("2026-07-24")
      expect(rewritten.fetch("kettle-jem").fetch("changelog_replay")).to eq(
        "last_entry_key" => "kettle-jem-template-20260720-005",
        "last_entry_date" => "2026-07-20"
      )
      expect(rewritten.fetch("kettle-jem").fetch("checksums")).to eq(current)
    end
  end

  it "migrates legacy config checksum state into a kettle-jem lockfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-lock-migration", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "template/config.yml.example" => "name: template\n",
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: template
            apply: true
            entries:
              - source: config.yml.example
                target: config.yml
          files:
            config.yml:
              strategy: accept_template

          kettle-jem:
            version: "0.1.0"
            applied_at: "2026-07-01"
            checksums:
              "config.yml.example": "old"
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      lock = YAML.safe_load_file(File.join(root, Kettle::Jem::KETTLE_LOCK_PATH))
      config = YAML.safe_load_file(File.join(root, ".kettle-jem.yml"))

      expect(apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "kettle_jem_state_sync" }).to include(
        changed_files: include(Kettle::Jem::KETTLE_LOCK_PATH, ".kettle-jem.yml")
      )
      expect(config).not_to have_key("kettle-jem")
      expect(lock.fetch("template_state").fetch("checksums")).to include("config.yml.example")
      expect(lock.fetch("files").fetch("config.yml")).to include("input_fingerprint", "dest_sha256")
    end
  end

  it "moves a legacy root kettle-jem lockfile into the structuredmerge directory" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-root-lock-migration", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "template/config.yml.example" => "name: template\n",
        ".kettle-jem.lock" => <<~YAML,
          ---
          version: 1
          template_state:
            version: 7.1.0
            changelog_replay:
              last_entry_key: kettle-jem-template-20260720-001
            checksums:
              config.yml.example: old
          files: {}
        YAML
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: template
            apply: true
            entries:
              - source: config.yml.example
                target: config.yml
          files:
            config.yml:
              strategy: accept_template
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      lock = YAML.safe_load_file(File.join(root, Kettle::Jem::KETTLE_LOCK_PATH))

      expect(File).not_to exist(File.join(root, Kettle::Jem::LEGACY_KETTLE_LOCK_PATH))
      expect(lock.fetch("template_state")).to include("changelog_replay", "checksums")
      expect(apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "kettle_jem_state_sync" }).to include(
        changed_files: include(Kettle::Jem::KETTLE_LOCK_PATH, Kettle::Jem::LEGACY_KETTLE_LOCK_PATH)
      )
    end
  end

  it "prunes stale write records when a template-owned destination was removed" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-stale-lock-record", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "template/config.yml.example" => "name: template\n",
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: template
            apply: true
            entries:
              - source: config.yml.example
                target: config.yml
          files:
            config.yml:
              strategy: accept_template
        YAML
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      lock_path = File.join(root, Kettle::Jem::KETTLE_LOCK_PATH)
      lock = YAML.safe_load_file(lock_path)
      lock.fetch("files")["obsolete.yml"] = {
        "action" => "write",
        "dest_sha256" => "stale",
        "input_fingerprint" => "stale"
      }
      File.write(lock_path, YAML.dump(lock))

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})

      expect(YAML.safe_load_file(lock_path).fetch("files")).not_to have_key("obsolete.yml")
    end
  end

  it "skips unchanged template inputs by default but honors destination checksum mode" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-skip", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "template/config.yml.example" => "name: template\n",
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: template
            apply: true
            entries:
              - source: config.yml.example
                target: config.yml
          files:
            config.yml:
              strategy: accept_template
        YAML
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      matching_apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      matching_outcomes = matching_apply.fetch(:file_outcomes)
      expect(matching_outcomes).to include(checksum_hits: 1, checksum_protected: 0)
      matching_report = matching_apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "config.yml" }
      fingerprint_payload = described_class.template_input_fingerprint_payload(root, matching_report)
      expect(fingerprint_payload).to include(template_source_application_fingerprint_version: 1)
      expect(fingerprint_payload).not_to include(:kettle_jem_version, :kettle_jem_implementation_sha256)

      File.write(File.join(root, "config.yml"), "name: local\n")

      default_apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      default_report = default_apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "config.yml" }

      expect(default_report.fetch(:checksum_skipped)).to be(true)
      outcomes = default_apply.fetch(:file_outcomes)
      expect(outcomes).to include(checksum_hits: 0, checksum_protected: 1, changed: 0)
      expect(outcomes.fetch(:planned)).to eq(
        outcomes.fetch(:checksum_hits) + outcomes.fetch(:checksum_protected) + outcomes.fetch(:unchanged) + outcomes.fetch(:changed)
      )
      expect(File.read(File.join(root, "config.yml"))).to eq("name: local\n")

      dest_apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true, checksums: "dest,template"})
      dest_report = dest_apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "config.yml" }

      expect(dest_report).not_to include(:checksum_skipped)
      expect(File.read(File.join(root, "config.yml"))).to eq("name: template\n")
    end
  end

  it "recreates a missing managed file even when default checksum mode ignores destination changes" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-missing-destination", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.add_dependency "mutex_m", "~> 0.2"
          end
        RUBY
        "template/gemfiles/modular/mutex_m/r4/v0.3.gemfile.example" => "gem \"mutex_m\", \"~> 0.2\"\n",
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: template
            apply: true
            entries:
              - source: gemfiles/modular/mutex_m/r4/v0.3.gemfile
                target: gemfiles/modular/mutex_m/r4/v0.3.gemfile
          files:
            gemfiles:
              modular:
                mutex_m:
                  r4:
                    v0.3.gemfile:
                      strategy: accept_template
        YAML
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      path = File.join(root, "gemfiles/modular/mutex_m/r4/v0.3.gemfile")
      File.delete(path)

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      report = apply.fetch(:recipe_reports).find do |entry|
        entry.fetch(:relative_path) == "gemfiles/modular/mutex_m/r4/v0.3.gemfile"
      end

      expect(report).not_to include(:checksum_skipped)
      expect(apply.fetch(:changed_files)).to include("gemfiles/modular/mutex_m/r4/v0.3.gemfile")
      expect(File.read(path)).to eq("gem \"mutex_m\", \"~> 0.2\"\n")
    end
  end

  it "accounts for final destination outcomes after recipe overlays" do
    outcomes = described_class.template_file_outcomes([
      {relative_path: "Gemfile", changed: true},
      {relative_path: "Gemfile", changed: false, metadata: {checksum_match: {input_match: true, destination_match: true}}},
      {relative_path: "README.md", changed: false},
      {relative_path: "Rakefile", changed: false, checksum_skipped: true, metadata: {checksum_match: {input_match: true, destination_match: false}}},
      {changed: true}
    ])

    expect(outcomes).to eq(
      planned: 3,
      checksum_hits: 1,
      checksum_protected: 1,
      unchanged: 1,
      changed: 0,
      unscoped_recipes: 1
    )
  end

  it "always evaluates the managed kettle config despite a checksum match" do
    report = {
      relative_path: described_class::KETTLE_CONFIG_PATH,
      metadata: {template_source_preference: {selected_source: ".structuredmerge/kettle-jem.yml.example"}},
      request_envelope: {request: {recipe_name: "supplied_template_source_application"}}
    }

    expect(described_class.send(:checksum_cache_safe_report?, report)).to be(false)
  end

  it "does not write template token values to the checksum lockfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-checksum-token-redaction", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "template/config.yml.example" => "freeze: {KJ|FREEZE_TOKEN}\n",
        ".kettle-jem.yml" => <<~YAML
          defaults:
            freeze_token: "ghp_sensitive-example-value"
          templates:
            root: template
            apply: true
            entries:
              - source: config.yml.example
                target: config.yml
          files:
            config.yml:
              strategy: accept_template
        YAML
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_drift_check: true})
      lock_content = File.read(File.join(root, Kettle::Jem::KETTLE_LOCK_PATH))

      expect(lock_content).to include("input_fingerprint")
      expect(lock_content).not_to include("ghp_sensitive-example-value")
      expect(lock_content).not_to include("freeze: ghp_sensitive-example-value")
    end
  end

  it "reports duplicate drift during template apply runs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-duplicate-drift-apply", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "# Example\n"
      })
      calls = []
      runner = lambda do |project_root:, template_dir:|
        calls << {project_root: project_root, template_dir: template_dir}
        {
          warning_count: 1,
          json_path: File.join(project_root, "tmp", "kettle-jem", "dup-check.json"),
          lock_path: File.join(project_root, ".kettle-drift.lock"),
          exit_code: 1
        }
      end

      apply = described_class.apply_project(root, env: {}, run_options: {duplicate_drift_runner: runner})

      expect(calls).to eq([{project_root: root, template_dir: File.join(root, "template")}])
      expect(apply.fetch(:duplicate_drift)).to include(
        available: true,
        warning_count: 1,
        json_path: File.join(root, "tmp", "kettle-jem", "dup-check.json"),
        lock_path: File.join(root, ".kettle-drift.lock"),
        exit_code: 1
      )
    end
  end

  it "skips duplicate drift checks when requested" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-skip-duplicate-drift", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })
      runner = lambda do |project_root:, template_dir:|
        raise "drift runner should not run for #{project_root} #{template_dir}"
      end

      apply = described_class.apply_project(root, env: {}, run_options: {skip_drift_check: true, duplicate_drift_runner: runner})

      expect(apply.fetch(:duplicate_drift)).to eq(
        available: false,
        skipped: true,
        reason: "skip_drift_check"
      )
    end
  end

  it "exposes template root and manifest metadata for adjacent tools" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-template-manifest", tmp_root) do |root|
      write_tree(root, {
        "template/README.md.example" => "# Example\n",
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      expect(described_class.packaged_template_root).to eq(described_class::PACKAGED_TEMPLATE_ROOT)
      expect(described_class.template_root_path(root)).to eq(File.join(root, "template"))

      manifest = described_class.template_manifest(project_root: root)
      expect(manifest).to include(
        kind: "kettle_jem_template_manifest",
        version: 1,
        template_root: File.join(root, "template")
      )
      expect(manifest.fetch(:checksums).keys).to eq(["README.md.example"])
    end
  end

  it "renders self-test and templating diagnostics reports" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-self-test-report-slice", tmp_root) do |root|
      before = File.join(root, "before")
      after = File.join(root, "after")
      write_tree(before, {
        "same.txt" => "same\n",
        "changed.txt" => "before\n",
        "removed.txt" => "removed\n"
      })
      write_tree(after, {
        "same.txt" => "same\n",
        "changed.txt" => "after\n",
        "added.txt" => "added\n"
      })

      comparison = described_class::SelfTest::Manifest.compare(
        described_class::SelfTest::Manifest.generate(before),
        described_class::SelfTest::Manifest.generate(after)
      ).merge(skipped: ["lib/internal.rb"])
      expect(comparison).to include(
        matched: ["same.txt"],
        changed: ["changed.txt"],
        added: ["added.txt"],
        removed: ["removed.txt"],
        skipped: ["lib/internal.rb"]
      )

      snapshot = {
        workspace_root: root,
        kettle_jem: {
          name: "kettle-jem",
          version: "1.2.3",
          path: File.join(root, "installed", "kettle-jem"),
          local_path: false,
          loaded: true
        },
        merge_gems: [
          {
            name: "ast-merge",
            version: "2.0.0",
            path: File.join(root, "ast-merge"),
            local_path: true,
            loaded: true
          },
          {
            name: "json-merge",
            version: nil,
            path: nil,
            local_path: false,
            loaded: false
          }
        ]
      }

      self_test_report = described_class::SelfTest::Reporter.summary(
        comparison,
        output_dir: File.join(root, "output"),
        templating_environment: snapshot,
        diff_count: 1,
        now: Time.utc(2026, 5, 14, 12, 0, 0)
      )
      expect(self_test_report).to include("**Score**: 25.0% (1/4 files unchanged)")
      expect(self_test_report).to include("**Divergence**: 75.0% (3/4 files changed, added, or missing)")
      expect(self_test_report).to include("## Changed Files (1)")
      expect(self_test_report).to include("## New Files (1)")
      expect(self_test_report).to include("## Not Templated - Unexpected (1)")
      expect(self_test_report).to include("<summary>Not Templated (1 files) - source-only files not produced by the template task</summary>")
      expect(self_test_report).to include("| ast-merge | 2.0.0 | local path |")
      expect(self_test_report).to include("| json-merge | _not loaded_ | not loaded |")

      run_report = described_class::TemplatingReport.render_markdown(
        project_root: root,
        snapshot: snapshot,
        run_started_at: Time.utc(2026, 5, 14, 12, 0, 0),
        finished_at: Time.utc(2026, 5, 14, 12, 1, 0),
        status: "failed",
        warnings: ["missing service", "missing service"],
        error: RuntimeError.new("boom"),
        template_diff: {added: ["new.md"], changed: ["README.md"], removed: ["old.md"]},
        template_commit_sha: "abc123"
      )
      expect(run_report).to include("# kettle-jem Templating Run Report")
      expect(run_report).to include("**Status**: `failed`")
      expect(run_report).to include("**Template commit**: `abc123`")
      expect(run_report.scan("- missing service").length).to eq(1)
      expect(run_report).to include("## Template File Changes")
      expect(run_report).to include("3 template file(s) since last run: 1 added, 1 changed, 1 removed")
      expect(run_report).to include("RuntimeError: boom")
    end
  end

  it "derives run stats from recipe reports" do
    stats = described_class.recipe_run_stats(
      [
        {changed: true, metadata: {destination_existed: false}},
        {changed: true, metadata: {destination_existed: true}},
        {changed: false, metadata: {destination_existed: true}},
        {changed: true, metadata: {delete_file: true, destination_existed: true}}
      ],
      diagnostics: [
        {kind: "plugin_file_change", path: "PLUGIN.md", action: "replace"}
      ]
    )

    expect(stats).to eq(
      recipes: 4,
      created: 1,
      pre_existing: 2,
      identical: 1,
      changed: 1,
      deleted: 1,
      plugin_file_changes: 1,
      summary: "recipes 4 created 1 pre_existing 2 identical 1 changed 1 deleted 1 plugin_file_changes 1"
    )
  end

  it "reports the Kettle/Jem non-interactive decision policy and recipe defaults" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-decision-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: templates
            apply: true
            entries:
              - README.md
        YAML
        "templates/README.md.example" => "# Example\n\nTemplate README.\n",
        "README.md" => "# Example\n\nDestination README.\n"
      })

      plan = described_class.plan_project(root, env: {"force" => "true"})
      expect(plan.fetch(:decision_policy)).to include(
        mode: "accept",
        non_interactive: true,
        accept: true,
        interactive: false,
        failure_mode: "error"
      )
      readme_decision = plan.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(readme_decision).to include(
        category: "apply_template_source",
        file: "README.md",
        default_action: "replace",
        selected_action: "replace",
        source: "default",
        severity: "advisory",
        blocking: false
      )
      expect(readme_decision.fetch(:diagnostics)).to include(
        "Non-interactive runs apply the configured template source default and report the decision."
      )

      apply = described_class.apply_project(root, env: {"force" => "false"})
      expect(apply.fetch(:decision_policy)).to include(
        mode: "interactive",
        non_interactive: false,
        accept: false,
        interactive: true
      )
      expect(apply.fetch(:decision_evaluations).map { |decision| decision.fetch(:selected_action) }).to include("replace")
      interactive_readme_decision = apply.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(interactive_readme_decision).to include(
        source: "interactive_default",
        prompt_required: true
      )
      expect(interactive_readme_decision.fetch(:prompt)).to include(
        id: "recipe:template_source_application_README_md",
        category: "apply_template_source",
        file: "README.md",
        default_action: "replace",
        choices: include("create", "replace", "keep", "skip")
      )
      expect(apply.fetch(:prompt_requests)).to include(interactive_readme_decision.fetch(:prompt))
      expect(interactive_readme_decision.fetch(:diagnostics)).to include(
        "Interactive prompt transport is active; selected the configured default pending an external response."
      )

      File.write(File.join(root, "README.md"), "# Example\n\nDestination README.\n")
      answered_apply = described_class.apply_project(
        root,
        env: {},
        run_options: {
          interactive: true,
          prompt_answers: {
            "recipe:readme_metadata" => "keep",
            "recipe:template_source_application_README_md" => "keep"
          }
        }
      )
      answered_decision = answered_apply.fetch(:decision_evaluations).find do |decision|
        decision.fetch(:id) == "recipe:template_source_application_README_md"
      end
      expect(answered_apply.fetch(:decision_policy)).to include(
        mode: "interactive",
        prompt_answers: {
          "recipe:readme_metadata" => "keep",
          "recipe:template_source_application_README_md" => "keep"
        }
      )
      expect(answered_decision).to include(
        selected_action: "keep",
        source: "interactive_answer",
        prompt_required: true
      )
      expect(answered_decision.fetch(:diagnostics)).to include(
        "Interactive prompt answer supplied through the shared decision policy input contract."
      )
      expect(answered_apply.fetch(:changed_files)).not_to include("README.md")
      expect(File.read(File.join(root, "README.md"))).to eq("# Example\n\nDestination README.\n")
    end
  end

  it "hard-fails decision evaluation only when no fatal default is available" do
    policy = described_class::DecisionPolicy.from_env({"force" => "true"})
    expect do
      policy.resolve(
        id: "parser:README.md",
        category: "parse",
        file: "README.md",
        default_action: nil,
        severity: :fatal
      )
    end.to raise_error(Kettle::Jem::Error, /No safe default decision/)
  end

  it "reports git preflight state and lets skip-commit bypass clean-worktree enforcement" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-preflight", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
      })
      expect(system("git", "-C", root, "init", "-q")).to be(true)

      expect do
        described_class.plan_project(root, env: {"KETTLE_JEM_REQUIRE_CLEAN" => "true"})
      end.to raise_error(Kettle::Jem::Error, /worktree is not clean/)

      plan = described_class.plan_project(root, env: {
        "KETTLE_JEM_REQUIRE_CLEAN" => "true",
        "KETTLE_JEM_SKIP_COMMIT" => "true"
      })
      expect(plan.fetch(:template_selection)).to include(skip_commit: true)
      expect(plan.fetch(:git_preflight)).to include(
        git_repository: true,
        clean_worktree: false,
        skip_commit: true
      )
      expect(plan.fetch(:git_preflight).fetch(:dirty_entries)).not_to be_empty
    end
  end

  it "holds the shared git operation lock during git preflight" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-preflight-lock", tmp_root) do |root|
      lock_path = File.join(root, ".git", "kettle-family-template-commit.lock")
      FileUtils.mkdir_p(File.dirname(lock_path))
      lock_was_held = false
      allow(described_class).to receive(:git_success?) do
        File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
          lock_was_held = !lock.flock(File::LOCK_EX | File::LOCK_NB)
        end
        true
      end
      allow(described_class).to receive(:git_output).and_return("")

      report = described_class.git_preflight_report(
        root,
        env: {"KETTLE_JEM_GIT_LOCK" => lock_path},
        template_selection: {skip_commit: true}
      )

      expect(report).to include(git_repository: true, clean_worktree: true)
      expect(lock_was_held).to be(true)
    end
  end

  it "loads configured plugins and runs apply-time phase hooks" do
    plugin_module = Module.new do
      class << self
        def register_kettle_jem_plugin(registrar)
          registrar.before_phase(:github_workflows) do |context:, phase:, **|
            path = File.join(context.project_root, ".github/FUNDING.yml")
            context.out.report_detail("before #{phase}: funding exists=#{File.exist?(path)}")
          end

          registrar.after_phase(:github_workflows) do |context:, phase:, **|
            path = File.join(context.project_root, ".github/FUNDING.yml")
            context.out.report_detail("after #{phase}: funding exists=#{File.exist?(path)}")
          end

          registrar.after_phase(:remaining_files) do |context:, phase:, phase_stats:, plugin_name:, **|
            path = File.join(context.project_root, "PLUGIN.md")
            File.write(path, "plugin=#{plugin_name}; phase=#{phase}; recipes=#{phase_stats.fetch(:recipe_count)}\n")
            context.helpers.record_template_result(path, :replace)
            context.out.report_detail("plugin hook ran")
          end
        end
      end
    end
    stub_const("Example::Plugin", plugin_module)
    allow(described_class::PluginLoader).to receive(:require).with("example/plugin").and_return(true)

    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-plugin-lifecycle", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          plugins:
            - example-plugin
        YAML
      })

      plan = described_class.plan_project(root, env: {})
      expect(File.exist?(File.join(root, "PLUGIN.md"))).to be(false)
      plan_lifecycle = plan.fetch(:diagnostics).find { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }
      expect(plan_lifecycle).to include(
        loaded_plugins: ["example-plugin"],
        callbacks_run: false
      )
      expect(plan_lifecycle.fetch(:active_runner_phases)).to be_empty
      expect(plan.fetch(:phase_reports).map { |phase_report| phase_report.fetch(:phase) }).to include(
        "github_workflows",
        "remaining_files"
      )
      github_phase = plan.fetch(:phase_reports).find { |phase_report| phase_report.fetch(:phase) == "github_workflows" }
      expect(github_phase.fetch(:changed_files)).to include(".github/FUNDING.yml")
      expect(plan.fetch(:run_stats).fetch(:plugin_file_changes)).to eq(0)

      apply = described_class.apply_project(root, env: {})
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "before github_workflows: funding exists=false"
      )
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "after github_workflows: funding exists=true"
      )
      expect(File.read(File.join(root, "PLUGIN.md"))).to include("plugin=example-plugin; phase=remaining_files; recipes=")
      expect(apply.fetch(:changed_files)).to include("PLUGIN.md")
      expect(apply.fetch(:run_stats).fetch(:plugin_file_changes)).to eq(1)
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_file_change",
        path: "PLUGIN.md",
        action: "replace"
      )
      expect(apply.fetch(:diagnostics)).to include(
        kind: "plugin_detail",
        message: "plugin hook ran"
      )
      apply_lifecycle = apply.fetch(:diagnostics).reverse.find { |diagnostic| diagnostic[:kind] == "plugin_lifecycle" }
      expect(apply_lifecycle).to include(
        loaded_plugins: ["example-plugin"],
        callbacks_run: true
      )
      expect(apply_lifecycle.fetch(:active_runner_phases)).to eq(described_class::PHASE_ORDER.map(&:to_s))
      expect(apply_lifecycle.fetch(:registered_hooks)).to contain_exactly(
        {
          plugin_name: "example-plugin",
          phase: "github_workflows",
          timing: "before"
        },
        {
          plugin_name: "example-plugin",
          phase: "github_workflows",
          timing: "after"
        },
        {
          plugin_name: "example-plugin",
          phase: "remaining_files",
          timing: "after"
        }
      )
    end
  end

  it "skips lockfile normalization when direct sibling runtime dependencies use local path env" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-direct-sibling-lock-env", tmp_root) do |workspace|
      root = File.join(workspace, "adapter")
      sibling = File.join(workspace, "shared-core")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "shared-core.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "shared-core"
            spec.version = "0.1.0"
            spec.summary = "Shared core"
          end
        RUBY
      })
      write_tree(root, {
        "Gemfile" => "source \"https://gem.coop\"\n",
        "Gemfile.lock" => <<~LOCK,
          GEM
            remote: https://gem.coop/
            specs:

          PLATFORMS
            ruby

          DEPENDENCIES

          BUNDLED WITH
             4.0.10
        LOCK
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/rubythems/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/rubythems/adapter"
            spec.add_dependency "shared-core", "= 0.1.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - bin/setup
        YAML
      })

      commands = []
      command_runner = lambda do |command, chdir:, env:, quiet:|
        commands << {command: command, chdir: chdir, env: env, quiet: quiet}
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {
          "K_JEM_TEMPLATING" => "true",
          "KETTLE_DEV_DEV" => "false",
          "STRUCTUREDMERGE_DEV" => "false",
          "RUBYTHEMS_DEV" => workspace
        },
        run_options: {only: "bin/setup", skip_commit: true},
        command_runner: command_runner
      )

      lock_command = commands.find { |entry| entry.fetch(:command) == %w[bundle update] }
      expect(lock_command).to be_nil
      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "bundle_lock_normalization",
        status: "skipped",
        reason: "local_path_development_env"
      ))
      setup_command = commands.find { |entry| entry.fetch(:command) == ["bin/setup"] }
      expect(setup_command.fetch(:env)).to include(
        "K_JEM_TEMPLATING" => "true",
        "RUBYTHEMS_DEV" => workspace
      )
    end
  end

  it "generates templating-aware main Gemfile nomono wiring for direct sibling runtime dependencies" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-direct-sibling-wiring", tmp_root) do |workspace|
      root = File.join(workspace, "adapter")
      sibling = File.join(workspace, "shared-core")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "shared-core.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "shared-core"
            spec.version = "0.1.0"
            spec.summary = "Shared core"
          end
        RUBY
      })
      write_tree(root, {
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/rubythems/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/rubythems/adapter"
            spec.add_dependency "shared-core", "= 0.1.0"
            spec.add_dependency "version_gem", ">= 1"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))
      direct_block = gemfile
        .split("# Direct sibling dependencies", 2).last.to_s
        .split("# Templating", 2).first.to_s

      expect(report.fetch(:changed_files)).to include("Gemfile")
      expect(direct_block).to include("direct_sibling_gems = %w[")
      expect(direct_block).to include("shared-core")
      expect(direct_block).not_to include("version_gem")
      expect(direct_block).to include(
        'direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?'
      )
      expect(gemfile).to include('gem "nomono"')
      expect(gemfile).not_to include("nomono_requirements")
      expect(direct_block).to include('require "nomono/bundler"')
      expect(direct_block).not_to include("nomono_activation_requirements")
      expect(direct_block).not_to include("nomono_lockfile")
      expect(direct_block).not_to include("Bundler::LockfileParser")
      expect(direct_block).not_to include('Kernel.send(:gem, "nomono"')
      expect(direct_block).not_to include('Gem::Specification.find_all_by_name("nomono")')
      expect(direct_block).not_to include(
        'unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?'
      )
      expect(direct_block).to include('direct_sibling_dev_was_set = ENV.key?("RUBYTHEMS_DEV")')
      expect(direct_block).to include('direct_sibling_dev_original = ENV.fetch("RUBYTHEMS_DEV", nil)')
      expect(direct_block).to include('ENV["RUBYTHEMS_DEV"] = File.expand_path("..", __dir__)')
      expect(direct_block).to include('ENV["RUBYTHEMS_DEV"] = direct_sibling_dev_original')
      expect(direct_block).to include('ENV.delete("RUBYTHEMS_DEV")')
      expect(direct_block).to include('prefix: "RUBYTHEMS"')
      expect(direct_block).to include('path_env: "RUBYTHEMS_DEV"')
      expect(direct_block).to include('root: ["src", "my", "rubythems"]')
      expect(gemfile).not_to include("Use released TSLP with the Ruby ABI platform-gem fix")
      expect(gemfile).not_to include(
        'gem "tree_sitter_language_pack", "~> 1.13", ">= 1.13.3"'
      )
      expect(gemfile).not_to include('branch: "fix/ruby-parser-api-methods"')
      expect(File.read(File.join(root, "Gemfile"))).to eq(gemfile)
    end
  end

  it "removes stale main Gemfile tree-sitter language pack declarations owned by templating Gemfiles" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-stale-tslp", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          gemspec

          # Use released TSLP with the Ruby ABI platform-gem fix.
          gem "tree_sitter_language_pack", "~> 1.13", ">= 1.13.3"

          # Templating
          eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
              - gemfiles/modular/templating.gemfile
        YAML
        "template/Gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          gemspec

          # Templating
          eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
        RUBY
        "template/gemfiles/modular/templating.gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          if ENV.fetch("STRUCTUREDMERGE_DEV", "false").casecmp("false").zero?
            gem "tree_sitter_language_pack", "~> 1.13", ">= 1.13.7"
          end
        RUBY
      })

      report = described_class.apply_project(root, env: {})
      gemfile = report.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "Gemfile" }.fetch(:final_content)

      expect(gemfile).not_to include("Use released TSLP with the Ruby ABI platform-gem fix")
      expect(gemfile).not_to include("tree_sitter_language_pack")
      expect(File.read(File.join(root, "Gemfile"))).to eq(gemfile)
      expect(File.read(File.join(root, "gemfiles/modular/templating.gemfile"))).to include(
        'gem "tree_sitter_language_pack", "~> 1.13", ">= 1.13.7"'
      )
    end
  end

  it "uses the monorepo member root for direct sibling runtime dependency wiring" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-direct-sibling-monorepo-root", tmp_root) do |workspace|
      repo_root = File.join(workspace, "structuredmerge", "ruby")
      root = File.join(repo_root, "gems", "ast-merge")
      sibling = File.join(repo_root, "gems", "tree_haver")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "tree_haver.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "tree_haver"
            spec.version = "7.1.0"
            spec.summary = "Tree tools"
          end
        RUBY
      })
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.version = "7.1.0"
            spec.summary = "AST merge"
            spec.metadata["source_code_uri"] = "https://github.com/structuredmerge/ast-merge"
            spec.add_dependency "tree_haver", "= 7.1.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          repository:
            topology: monorepo-subproject
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })
      expect(system("git", "-C", repo_root, "init", "-q")).to be(true)
      expect(system("git", "-C", repo_root, "remote", "add", "origin", "git@github.com:structuredmerge/structuredmerge-ruby.git")).to be(true)

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))
      direct_block = gemfile
        .split("# Direct sibling dependencies", 2).last.to_s
        .split("# Templating", 2).first.to_s

      expect(direct_block).to include("tree_haver")
      expect(direct_block).to include('path_env: "STRUCTUREDMERGE_DEV"')
      expect(direct_block).to include('root: ["src", "my", "structuredmerge", "ruby", "gems"]')
    end
  end

  it "collapses repeated direct sibling runtime dependency wiring in the main Gemfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-direct-sibling-dedupe", tmp_root) do |workspace|
      root = File.join(workspace, "adapter")
      sibling = File.join(workspace, "shared-core")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "shared-core.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "shared-core"
            spec.version = "0.1.0"
            spec.summary = "Shared core"
          end
        RUBY
      })
      write_tree(root, {
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/rubythems/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/rubythems/adapter"
            spec.add_dependency "shared-core", "= 0.1.0"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"

          gemspec

          gem "nomono", require: false

          # Direct sibling dependencies (env-switched via RUBYTHEMS_DEV)
          direct_sibling_gems = %w[
            stale-core
          ]
          direct_sibling_dev = ENV.fetch("RUBYTHEMS_DEV", "")
          direct_sibling_local =
            !direct_sibling_dev.empty? && !%w[false 0 no off].include?(direct_sibling_dev.downcase)
          direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

          if direct_sibling_gems.any? &&
              (direct_sibling_local ||
                ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?)
            require "nomono/bundler"
            eval_nomono_gems(
              gems: direct_sibling_gems,
              prefix: "RUBYTHEMS",
              path_env: "RUBYTHEMS_DEV",
              root: ["src", "my", "rubythems"]
            )
          end

          # Direct sibling dependencies (env-switched via RUBYTHEMS_DEV)
          direct_sibling_gems = %w[
            shared-core
          ]
          direct_sibling_dev = ENV.fetch("RUBYTHEMS_DEV", "")
          direct_sibling_local =
            !direct_sibling_dev.empty? && !%w[false 0 no off].include?(direct_sibling_dev.downcase)
          direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

          if direct_sibling_gems.any? &&
              (direct_sibling_local ||
                ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?)
            require "nomono/bundler"
            eval_nomono_gems(
              gems: direct_sibling_gems,
              prefix: "RUBYTHEMS",
              path_env: "RUBYTHEMS_DEV",
              root: ["src", "my", "rubythems"]
            )
          end

          # Templating (env-switched: STRUCTUREDMERGE_DEV=/path/to/structuredmerge/ruby/gems for local paths)
          eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(gemfile.scan("# Direct sibling dependencies").length).to eq(1)
      expect(gemfile).to include("shared-core")
      expect(gemfile).not_to include("stale-core")
    end
  end

  it "collapses repeated direct sibling execution blocks in the main Gemfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-direct-sibling-if-dedupe", tmp_root) do |workspace|
      root = File.join(workspace, "adapter")
      sibling = File.join(workspace, "shared-core")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "shared-core.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "shared-core"
            spec.version = "0.1.0"
            spec.summary = "Shared core"
          end
        RUBY
      })
      write_tree(root, {
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/rubythems/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/rubythems/adapter"
            spec.add_dependency "shared-core", "= 0.1.0"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"

          gemspec

          gem "nomono", require: false

          # Direct sibling dependencies (env-switched via RUBYTHEMS_DEV)
          direct_sibling_gems = %w[
            shared-core
          ]
          direct_sibling_dev = ENV.fetch("RUBYTHEMS_DEV", "")
          direct_sibling_local =
            !direct_sibling_dev.empty? && !%w[false 0 no off].include?(direct_sibling_dev.downcase)
          direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

          if direct_sibling_gems.any? &&
              (direct_sibling_local ||
                ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?)
            require "nomono/bundler"
            eval_nomono_gems(
              gems: direct_sibling_gems,
              prefix: "RUBYTHEMS",
              path_env: "RUBYTHEMS_DEV",
              root: ["src", "my", "rubythems"]
            )
          end

          if direct_sibling_gems.any? &&
              (direct_sibling_local ||
                ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?)
            require "nomono/bundler"
            eval_nomono_gems(
              gems: direct_sibling_gems,
              prefix: "RUBYTHEMS",
              path_env: "RUBYTHEMS_DEV",
              root: ["src", "my", "rubythems"]
            )
          end

          # Templating (env-switched: STRUCTUREDMERGE_DEV=/path/to/structuredmerge/ruby/gems for local paths)
          eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))
      direct_block = gemfile
        .split("# Direct sibling dependencies", 2).last.to_s
        .split("# Templating", 2).first.to_s

      expect(gemfile.scan("# Direct sibling dependencies").length).to eq(1)
      expect(direct_block.scan("eval_nomono_gems(").length).to eq(1)
      expect(direct_block).to include("shared-core")
    end
  end

  it "does not path-wire direct sibling dependencies when the sibling directory has a different gemspec name" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-direct-sibling-name-mismatch", tmp_root) do |workspace|
      root = File.join(workspace, "omniauth-openid")
      stale_sibling = File.join(workspace, "rack-openid")
      FileUtils.mkdir_p([root, stale_sibling])
      write_tree(stale_sibling, {
        "rack-openid2.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "rack-openid2"
            spec.version = "2.0.3"
            spec.summary = "Rack OpenID 2"
          end
        RUBY
      })
      write_tree(root, {
        "omniauth-openid.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "omniauth-openid"
            spec.version = "2.0.2"
            spec.summary = "OpenID strategy"
            spec.homepage = "https://github.com/ruby-openid/omniauth-openid"
            spec.metadata["source_code_uri"] = "https://github.com/ruby-openid/omniauth-openid"
            spec.add_dependency "rack-openid", "~> 1.4"
            spec.add_dependency "version_gem", ">= 1"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"

          gemspec

          gem "nomono", require: false

          # Direct sibling dependencies (env-switched via RUBY_OPENID_DEV)
          direct_sibling_gems = %w[
            rack-openid
          ]
          direct_sibling_dev = ENV.fetch("RUBY_OPENID_DEV", "")
          direct_sibling_local =
            !direct_sibling_dev.empty? && !%w[false 0 no off].include?(direct_sibling_dev.downcase)
          direct_sibling_templating = ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?

          if direct_sibling_gems.any? &&
              (direct_sibling_local ||
                ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?)
            require "nomono/bundler"
            eval_nomono_gems(
              gems: direct_sibling_gems,
              prefix: "RUBY_OPENID",
              path_env: "RUBY_OPENID_DEV",
              root: ["src", "my", "ruby-openid"]
            )
          end

          # Templating (env-switched: STRUCTUREDMERGE_DEV=/path/to/structuredmerge/ruby/gems for local paths)
          eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(gemfile).not_to include("# Direct sibling dependencies")
      expect(gemfile).not_to include("direct_sibling_gems")
      expect(gemfile).not_to include("rack-openid")
    end
  end

  it "replaces legacy nomono requirements assignments with a plain dependency declaration" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-nomono-order", tmp_root) do |root|
      write_tree(root, {
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
            spec.homepage = "https://github.com/ur-brain/adapter"
            spec.metadata["source_code_uri"] = "https://github.com/ur-brain/adapter"
            spec.add_dependency "version_gem", ">= 1"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"

          # Local workspace dependency wiring for *_local.gemfile overrides
          nomono_requirements = ["~> 1.0", ">= 1.0.8"]
          gem "nomono", *nomono_requirements, require: false # ruby >= 2.2
          gem "progress_bar"

          require "nomono/bundler"

          eval_nomono_gems(
            gems: %w[ur_brain],
            prefix: "UR_BRAIN",
            path_env: "UR_BRAIN_DEV",
            root: ["src", "my", "ur-brain"]
          )

          gemspec
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(gemfile).to include('gem "nomono"')
      expect(gemfile).not_to include("nomono_requirements")
      expect(gemfile).not_to include('gem "nomono", *nomono_requirements')
    end
  end

  it "normalizes static nomono declarations to the template requirement" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-static-nomono", tmp_root) do |root|
      write_tree(root, {
        "adapter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "adapter"
            spec.version = "0.1.0"
            spec.summary = "Adapter"
          end
        RUBY
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"

          # Local workspace dependency wiring for *_local.gemfile overrides
          gem "nomono", "~> 1.1", ">= 1.1.4", require: false # ruby >= 3.2.0

          gemspec
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(gemfile).to include('gem "nomono", "~> 1.1", ">= 1.1.5", require: false')
      expect(gemfile).not_to include(">= 1.1.4")
    end
  end

  it "does not add generic direct sibling wiring for gems already handled by local modular Gemfiles" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-local-modular-sibling", tmp_root) do |workspace|
      root = File.join(workspace, "ur_brain-claude-code")
      sibling = File.join(workspace, "ur_brain-adapters-ruby")
      FileUtils.mkdir_p([root, sibling])
      write_tree(sibling, {
        "ur_brain-adapters-ruby.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "ur_brain-adapters-ruby"
            spec.version = "0.1.0"
            spec.summary = "UR Brain adapters"
          end
        RUBY
      })
      write_tree(root, {
        "ur_brain-claude-code.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ur_brain-claude-code"
            spec.version = "0.1.0"
            spec.summary = "Claude Code adapter"
            spec.homepage = "https://github.com/ur-brain/ur_brain-claude-code"
            spec.metadata["source_code_uri"] = "https://github.com/ur-brain/ur_brain-claude-code"
            spec.add_dependency "ur_brain-adapters-ruby", "~> 0.1"
          end
        RUBY
        "gemfiles/modular/ur_brain_local.gemfile" => <<~RUBY,
          workspace_root = File.expand_path("../..", __dir__)
          gem "ur_brain-adapters-ruby",
            path: File.join(workspace_root, "ur_brain-adapters-ruby")
        RUBY
        "gemfiles/modular/ur_brain.gemfile" => <<~RUBY,
          if ENV.fetch("UR_BRAIN_DEV", "false").casecmp("false").zero?
            gem "ur_brain-adapters-ruby", "~> 0.1"
          else
            eval_gemfile "ur_brain_local.gemfile"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          dependency_conflicts:
            reviewed: true
            resolve:
              - gem: ur_brain-adapters-ruby
                direct: ur_brain-claude-code.gemspec
                modular: gemfiles/modular/ur_brain.gemfile
                action: keep_both
                reason: "The released modular dependency and gemspec range intentionally coexist."
              - gem: ur_brain-adapters-ruby
                direct: ur_brain-claude-code.gemspec
                modular: gemfiles/modular/ur_brain_local.gemfile
                action: keep_both
                reason: "The local modular override intentionally shadows the released dependency."
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(gemfile).not_to include("# Direct sibling dependencies")
      expect(gemfile).not_to include("direct_sibling_gems")
      expect(gemfile).to include(%(eval_gemfile "gemfiles/modular/ur_brain.gemfile"))
    end
  end

  it "preserves local modular runtime wiring declared through nomono local gem lists" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-main-gemfile-nomono-local-modular-sibling", tmp_root) do |workspace|
      root = File.join(workspace, "ur_brain-mcp")
      FileUtils.mkdir_p(root)
      write_tree(root, {
        "ur_brain-mcp.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ur_brain-mcp"
            spec.version = "0.1.0"
            spec.summary = "MCP adapter"
            spec.homepage = "https://github.com/ur-brain/ur_brain-adapters-ruby"
            spec.metadata["source_code_uri"] = "https://github.com/ur-brain/ur_brain-adapters-ruby"
            spec.add_dependency "ur_brain", "~> 0.1"
          end
        RUBY
        "gemfiles/modular/ur_brain_local.gemfile" => <<~RUBY,
          require "nomono/bundler" unless defined?(Nomono)

          local_gems = %w[ur_brain]

          eval_nomono_gems(
            gems: local_gems,
            prefix: "UR_BRAIN",
            path_env: "UR_BRAIN_DEV",
            vendored_gems_env: "VENDORED_GEMS",
            vendor_gem_dir_env: "VENDOR_GEM_DIR",
            debug_env: "KETTLE_DEV_DEBUG",
            root: %w[src my ur-brain]
          )
        RUBY
        "gemfiles/modular/ur_brain.gemfile" => <<~RUBY,
          if ENV.fetch("UR_BRAIN_DEV", "false").casecmp("false").zero?
            gem "ur_brain", "~> 0.1"
          else
            eval_gemfile "ur_brain_local.gemfile"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          dependency_conflicts:
            reviewed: true
            resolve:
              - gem: ur_brain
                direct: ur_brain-mcp.gemspec
                modular: gemfiles/modular/ur_brain.gemfile
                action: keep_both
                reason: "The modular local/released switch intentionally coexists with the gemspec range."
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
      })

      described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(gemfile).not_to include("# Direct sibling dependencies")
      expect(gemfile).not_to include("direct_sibling_gems")
      expect(gemfile).to include(%(eval_gemfile "gemfiles/modular/ur_brain.gemfile"))
    end
  end
end
