# frozen_string_literal: true

RSpec.describe Kettle::Jem, "template selection and bootstrap behavior" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "fails on a direct dependency also declared by a modular Gemfile" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-direct-modular-dependency-conflict", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          dependency_conflicts:
            reviewed: true
            resolve: []
        YAML
      })

      reports = [
        {
          relative_path: "shields-badge.gemspec",
          final_content: <<~RUBY
            Gem::Specification.new do |spec|
              spec.add_development_dependency("yard-relative_markdown_links", "~> 0.5.0")
            end
          RUBY
        },
        {
          relative_path: "gemfiles/modular/documentation.gemfile",
          final_content: %(gem "yard-relative_markdown_links", "~> 0.6", require: false\n)
        }
      ]

      expect {
        described_class.validate_modular_dependency_conflicts!(root, reports)
      }.to raise_error(
        Kettle::Jem::Error,
        include("yard-relative_markdown_links", "shields-badge.gemspec", "gemfiles/modular/documentation.gemfile", "dependency_conflicts.resolve")
      )
    end
  end

  it "keeps an explicit direct-versus-modular dependency decision stable across runs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-direct-modular-dependency-decision", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          dependency_conflicts:
            resolve:
              - gem: yard-relative_markdown_links
                direct: shields-badge.gemspec
                modular: gemfiles/modular/documentation.gemfile
                action: remove_modular_gem
                reason: "The gemspec intentionally owns this dependency."
        YAML
      })
      reports = [
        {relative_path: "shields-badge.gemspec", final_content: %(spec.add_development_dependency("yard-relative_markdown_links", "~> 0.5.0")\n)},
        {relative_path: "gemfiles/modular/documentation.gemfile", final_content: %(gem "yard-relative_markdown_links", "~> 0.6"\n)}
      ]

      2.times do
        expect {
          described_class.validate_modular_dependency_conflicts!(root, reports)
        }.not_to raise_error
      end
    end
  end

  it "allows a broad direct requirement to coexist with a compatible modular narrowing" do
    expect(described_class.compatible_dependency_requirements?([">= 1.0"], ["~> 2.0"])).to be(true)
    expect(described_class.compatible_dependency_requirements?(["~> 0.5.0"], ["~> 0.6.0"])).to be(false)
  end

  it "does not accept keep_both for incompatible direct and modular requirements" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-incompatible-keep-both", tmp_root) do |root|
      write_tree(root, {
        ".structuredmerge/kettle-jem.yml" => <<~YAML
          dependency_conflicts:
            resolve:
              - gem: yard-relative_markdown_links
                direct: example.gemspec
                modular: gemfiles/modular/documentation.gemfile
                action: keep_both
                reason: "The modular declaration was intended to narrow the direct range."
        YAML
      })
      reports = [
        {
          relative_path: "example.gemspec",
          final_content: %(spec.add_development_dependency("yard-relative_markdown_links", "~> 0.5.0")\n)
        },
        {
          relative_path: "gemfiles/modular/documentation.gemfile",
          final_content: %(gem "yard-relative_markdown_links", "~> 0.6"\n)
        }
      ]

      expect {
        described_class.validate_modular_dependency_conflicts!(root, reports)
      }.to raise_error(Kettle::Jem::Error, include("keep_both", "requirements overlap"))
    end
  end

  it "writes discovered conflicts into a first-run config for review" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-direct-modular-dependency-bootstrap", tmp_root) do |root|
      reports = [
        {
          relative_path: ".structuredmerge/kettle-jem.yml",
          final_content: "dependency_conflicts:\n  resolve: []\n"
        },
        {
          relative_path: "example.gemspec",
          final_content: %(spec.add_development_dependency("yard-relative_markdown_links", "~> 0.5.0")\n)
        },
        {
          relative_path: "gemfiles/modular/documentation.gemfile",
          final_content: %(gem "yard-relative_markdown_links", "~> 0.6", require: false\n)
        }
      ]

      described_class.validate_modular_dependency_conflicts!(root, reports)
      config = reports.first.fetch(:final_content)
      expect(config).to include("action: review")
      expect(config).to include("yard-relative_markdown_links")
    end
  end

  it "filters template recipes with old only/include semantics" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-only-filter-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
            spec.metadata["source_code_uri"] = "https://github.com/acme/example"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "template/README.md.example" => "# Example\n"
      })

      plan = described_class.plan_project(root, env: {}, run_options: {only: "README.md"})
      paths = plan.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }
      expect(paths.uniq).to eq(["README.md"])

      apply = described_class.apply_project(root, env: {}, run_options: {only: "README.md"})
      expect(apply.fetch(:changed_files)).to eq(["README.md"])
      expect(File).to exist(File.join(root, "README.md"))
      expect(File).not_to exist(File.join(root, ".github", "FUNDING.yml"))

      expanded = described_class.plan_project(root, env: {}, run_options: {only: "README.md", include: ".github/**"})
      expect(expanded.fetch(:recipe_reports).map { |report| report.fetch(:relative_path) }).to include(
        "README.md",
        ".github/FUNDING.yml"
      )
    end
  end

  it "bootstraps kettle config from packaged reference template when missing" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-slice", tmp_root) do |root|
      packaged_config_template = File.read(File.join(described_class::PACKAGED_TEMPLATE_ROOT, ".structuredmerge/kettle-jem.yml.example"))
      expect(packaged_config_template).to include('family_tag: "{KJ|RUBYFORUM:FAMILY_TAG}"')
      expect(packaged_config_template).to include('project_tag: "{KJ|RUBYFORUM:PROJECT_TAG}"')

      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {"KJ_MIN_DIVERGENCE_THRESHOLD" => "7"})
      bootstrap_report = plan[:recipe_reports].find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      expect(bootstrap_report.fetch(:changed)).to be(true)
      expect(bootstrap_report.fetch(:relative_path)).to eq(".structuredmerge/kettle-jem.yml")
      expect(bootstrap_report.dig(:metadata, :bootstrap_file)).to be(true)
      expect(bootstrap_report.dig(:metadata, :template_source_preference)).to include(
        selected_source: ".structuredmerge/kettle-jem.yml.example",
        source_relative_path: ".structuredmerge/kettle-jem.yml.example",
        source_root: "packaged"
      )
      expect(bootstrap_report.fetch(:final_content)).to include("# kettle-jem configuration file")
      expect(bootstrap_report.fetch(:final_content)).to include("min_divergence_threshold: 7")
      expect(bootstrap_report.fetch(:final_content)).to include("#   tokens    - values for {KJ|...} placeholders used across template files")
      expect(YAML.safe_load(bootstrap_report.fetch(:final_content)).dig("rubyforum", "family_tag")).to eq("")
      expect(YAML.safe_load(bootstrap_report.fetch(:final_content)).dig("rubyforum", "project_tag")).to eq("")

      described_class.apply_project(root, env: {"KJ_MIN_DIVERGENCE_THRESHOLD" => "7"})
      applied_config = File.read(File.join(root, ".structuredmerge/kettle-jem.yml"))
      expect(applied_config).to start_with(bootstrap_report.fetch(:final_content).rstrip)
      expect(YAML.safe_load(applied_config)).not_to have_key("kettle-jem")
      expect(YAML.safe_load_file(File.join(root, described_class::KETTLE_LOCK_PATH)).fetch("template_state")).to include(
        "version" => described_class::VERSION,
        "checksums" => a_kind_of(Hash)
      )
    end
  end

  it "renders an unset divergence threshold without trailing whitespace" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-empty-divergence-threshold", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)

      expect(content).to include('min_divergence_threshold: ""')
      expect(content).not_to match(/[ \t]+\n/)
      expect(YAML.safe_load(content).fetch("min_divergence_threshold")).to eq("")
    end
  end

  it "removes explicit RuboCop TargetRubyVersion when templating rubocop-lts config" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubocop-target-ruby-version-cleanup", tmp_root) do |root|
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
              - .rubocop.yml
        YAML
        ".rubocop.yml" => <<~YAML,
          inherit_gem:
            rubocop-lts: config/rubygem_rspec.yml
          AllCops:
            Exclude:
              - tmp/**/*
            TargetRubyVersion: 3.2
          Style/StringLiterals:
            EnforcedStyle: double_quotes
        YAML
        "template/.rubocop.yml.example" => <<~YAML
          inherit_gem:
            rubocop-lts: config/rubygem_rspec.yml
          AllCops:
            Exclude:
              - vendor/**/*
              - "**/vendor/**/*"
          RBS:
            Enabled: true
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".rubocop.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(report.fetch(:changed)).to be(true)
      expect(config.fetch("AllCops")).not_to have_key("TargetRubyVersion")
      expect(config.dig("AllCops", "Exclude")).to eq(["tmp/**/*"])
      expect(config.dig("Style/StringLiterals", "EnforcedStyle")).to eq("double_quotes")
      expect(config.dig("RBS", "Enabled")).to be(true)
      expect(report.fetch(:final_content)).not_to include("TargetRubyVersion")
      expect(File.read(File.join(root, ".rubocop.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "activates the RSpec RuboCop plugin when templating the RSpec RuboCop overlay" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rubocop-rspec-plugin", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: packaged
            apply: true
            entries:
              - .rubocop.yml
        YAML
        ".rubocop.yml" => <<~YAML
          inherit_gem:
            rubocop-lts: config/rubygem_rspec.yml
          plugins:
            - rubocop-on-rbs
            - rubocop-packaging
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".rubocop.yml" }
      config = YAML.safe_load(report.fetch(:final_content))

      expect(config.fetch("plugins")).to include("rubocop-rspec", "rubocop-on-rbs", "rubocop-packaging")
      expect(File.read(File.join(root, ".rubocop.yml"))).to eq(report.fetch(:final_content))
    end
  end

  it "seeds bootstrap config licenses from the gemspec" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-licenses", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end

      expect(bootstrap_report.fetch(:final_content)).to include(<<~YAML)
        licenses:
          - AGPL-3.0-only
          - PolyForm-Small-Business-1.0.0
      YAML
      expect(bootstrap_report.fetch(:final_content)).not_to include(<<~YAML)
        licenses:
          - MIT
      YAML
      expect(bootstrap_report.fetch(:final_content)).to include(<<~YAML)
        license_eye:
          dependency_licenses:
            - name: simplecov-rcov
              version: 0.3.7
              license: MIT
      YAML
    end
  end

  it "seeds bootstrap config minimum Ruby from the gemspec" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-min-ruby", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2.0"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)

      expect(content).to include(<<~YAML)
        ruby:
          # Lowest MRI Ruby version for generated CI workflows, Appraisals, and
          # test/development dependency assumptions. This is intentionally separate
          # from the gemspec required_ruby_version, which describes the published
          # runtime contract. Effective CI minimum is max(gemspec minimum, this value).
          test_minimum: "3.2.0"
      YAML
      expect(content).to include(<<~YAML)
        rubygems:
          # Published runtime Ruby floor used for generated gemspec metadata and README
          # compatibility text. Omit this to derive the value from the gemspec.
          # ENV override: KJ_MIN_RUBY
          min_ruby: "3.2.0"
      YAML
      expect(content).to include("version_gem_entrypoint: auto")
      expect(content).not_to include('min_ruby: "2.4"')
    end
  end

  it "seeds bootstrap config runtime URI values from gemspec metadata" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-runtime-uris", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.email = ["maintainer@example.test"]
            spec.metadata["homepage_uri"] = "https://docs.example.test"
          end
        RUBY
      })

      reader_metadata = described_class::GemSpecReader.load(root)
      expect(reader_metadata[:homepage_uri]).to eq("https://docs.example.test")

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)

      expect(content).to include('yard_host: "example.example.test"')
      expect(content).to include('homepage_uri: "https://docs.example.test"')
      expect(content).not_to include("{KJ|YARD_HOST}")
      expect(content).not_to include("{KJ|HOMEPAGE_URI}")
    end
  end

  it "syncs OpenCollective ENV into bootstrap config funding tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-open-collective", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {"OPENCOLLECTIVE_HANDLE" => "example-org"})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)
      config = YAML.safe_load(content)

      expect(config.dig("tokens", "funding", "open_collective")).to eq("example-org")
      expect(content).to include('open_collective: "example-org"')
      expect(content).not_to include('open_collective: "galtzo-floss"')
    end
  end

  it "syncs FUNDING_ORG ENV into bootstrap config OpenCollective tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-funding-org", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {"FUNDING_ORG" => "funding-org"})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      config = YAML.safe_load(bootstrap_report.fetch(:final_content))

      expect(config.dig("tokens", "funding", "open_collective")).to eq("funding-org")
    end
  end

  it "bootstraps full-template Gemfile ownership to avoid merging legacy Gemfile dependency sets" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-gemfile-owner", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      config = YAML.safe_load(bootstrap_report.fetch(:final_content))

      expect(config.dig("files", "Gemfile", "strategy")).to eq("accept_template")
    end
  end

  it "seeds bootstrap config CI minimum Ruby no lower than 2.4" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-ci-min-ruby", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
      })

      plan = described_class.plan_project(root, env: {})
      bootstrap_report = plan.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "kettle_config_bootstrap"
      end
      content = bootstrap_report.fetch(:final_content)

      expect(content).to include('test_minimum: "2.4"')
      expect(content).to include('min_ruby: "2.3"')
    end
  end

  it "migrates MIT LICENSE.txt copyright text into LICENSE.md and deletes the legacy file" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-license-legacy-cleanup", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.licenses = ["MIT"]
          end
        RUBY
        "LICENSE.txt" => <<~TEXT,
          Copyright (c) 2026 Example Maintainer

          Permission is hereby granted, free of charge, to any person obtaining a copy
          of this software and associated documentation files (the "Software"), to deal
          in the Software without restriction.
        TEXT
        ".kettle-jem.yml" => <<~YAML
          licenses:
            - MIT
          templates:
            root: packaged
            apply: true
            entries:
              - LICENSE.md
        YAML
      })

      apply = described_class.apply_project(root, env: {})

      expect(apply.fetch(:changed_files)).to include("LICENSE.md", "LICENSE.txt")
      expect(File).to exist(File.join(root, "LICENSE.md"))
      expect(File).not_to exist(File.join(root, "LICENSE.txt"))
      expect(File.read(File.join(root, "LICENSE.md"))).to include("Copyright (c) 2026 Example Maintainer")
    end
  end

  it "preserves custom LICENSE.txt and links to it without inventing an SPDX label" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-custom-license", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        "LICENSE.txt" => "All rights reserved.\n",
        ".kettle-jem.yml" => <<~YAML
          templates:
            root: packaged
            apply: true
            entries:
              - LICENSE.md
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      license = File.read(File.join(root, "LICENSE.md"))

      expect(apply.fetch(:changed_files)).to include("LICENSE.md")
      expect(File).to exist(File.join(root, "LICENSE.txt"))
      expect(license).to include("[LICENSE.txt](LICENSE.txt)")
      expect(license).not_to include("MIT")
    end
  end

  it "bootstraps a monorepo subgem template profile with package-owned entries and Gemfile support files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-subgem", tmp_root) do |root|
      write_tree(root, {
        "tree_haver.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "tree_haver"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        "README.md" => "# 💎 Tree::Haver\n\nExisting README.\n"
      })

      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )
      config = File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".structuredmerge/kettle-jem.yml")
      expect(config).to include("project_emoji: 💎\n")
      expect(config_yaml.dig("templates", "root")).to eq("packaged")
      expect(config_yaml.dig("templates", "apply")).to be(true)
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-subgem-package")
      expect(config_yaml.dig("templates", "entries")).to include(
        "README.md",
        {"source" => "gem.gemspec", "target" => "tree_haver.gemspec"},
        "Rakefile",
        "LICENSE.md",
        "mise.toml",
        "Gemfile",
        "gemfiles/modular/coverage.gemfile",
        "gemfiles/modular/debug.gemfile",
        "gemfiles/modular/documentation.gemfile",
        "gemfiles/modular/optional.gemfile",
        "gemfiles/modular/style.gemfile",
        "gemfiles/modular/templating.gemfile",
        "gemfiles/modular/templating_local.gemfile",
        "gemfiles/modular/x_std_libs.gemfile"
      )
      expect(config).to include(
        "    - source: lib/gem/version.rb\n      " \
          "target: lib/tree_haver/version.rb\n    " \
          "- source: lib/gem/version_gem.rb\n      " \
          "target: lib/tree_haver/version_gem.rb\n    " \
          "- source: sig/gem.rbs\n      " \
          "target: sig/tree_haver.rbs\n"
      )
      expect(config).to include("    - certs/pboling.pem\n")
      expect(config).to include("    - tmp/.gitignore\n")
      expect(config).not_to include("    - .github/workflows/current.yml\n")
      expect(config).to include(<<~YAML)
        files:
          README.md:
            strategy: merge
          Rakefile:
            strategy: accept_template
          tree_haver.gemspec:
            strategy: merge
      YAML

      configure_dependency_conflicts(root, [
        {"gem" => "version_gem", "direct" => "tree_haver.gemspec", "modular" => "gemfiles/modular/runtime_heads.gemfile", "action" => "keep_both", "reason" => "The runtime gemspec and HEAD appraisal intentionally share this dependency."}
      ])

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})
      expect(apply.fetch(:changed_files)).to include("LICENSE.md")
      expect(apply.fetch(:changed_files)).to include("README.md")
      expect(apply.fetch(:changed_files)).to include("Gemfile")
      expect(apply.fetch(:changed_files)).to include("tree_haver.gemspec")
      expect(File).not_to exist(File.join(root, ".github"))
      expect(File.read(File.join(root, "Gemfile"))).to include('gem "nomono"')
      expect(File.read(File.join(root, "Gemfile"))).to include('gem "kettle-family"')
      expect(File).to exist(File.join(root, "Rakefile"))
    end
  end

  it "bootstraps a monorepo subgem release profile with per-gem harness entries" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-subgem-release", tmp_root) do |root|
      write_tree(root, {
        "tree_haver.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "tree_haver"
            spec.summary = "Example gem"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem-release", skip_commit: true}
      )
      config = File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".structuredmerge/kettle-jem.yml")
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-subgem-release")
      expect(config_yaml.dig("templates", "entries")).to include(
        "Gemfile",
        "Rakefile",
        ".rspec",
        ".simplecov",
        ".yard-lint.yml",
        ".yardopts",
        ".yardignore",
        "bin/setup",
        "spec/README.md",
        "spec/spec_helper.rb",
        "gemfiles/modular/documentation.gemfile"
      )
      expect(config_yaml.dig("files", "tree_haver.gemspec", "strategy")).to eq("merge")

      configure_dependency_conflicts(root, [
        {"gem" => "version_gem", "direct" => "tree_haver.gemspec", "modular" => "gemfiles/modular/runtime_heads.gemfile", "action" => "keep_both", "reason" => "The runtime gemspec and HEAD appraisal intentionally share this dependency."}
      ])

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})
      expect(apply.fetch(:changed_files)).to include("Gemfile", ".yard-lint.yml", ".yardopts", ".yardignore", "bin/setup", "spec/README.md")
      expect(File).to exist(File.join(root, "Rakefile"))
      expect(File).to exist(File.join(root, "Gemfile"))
      expect(File.read(File.join(root, ".rspec"))).to include("--exclude-pattern spec/tmp/**/*_spec.rb")
      expect(File.read(File.join(root, "spec", "README.md"))).to include("stub_env")
      expect(File.read(File.join(root, "spec", "README.md"))).to include("include_context \"with rake\"")
      expect(File).to exist(File.join(root, ".yard-lint.yml"))
      yard_lint_config = YAML.safe_load_file(File.join(root, ".yard-lint.yml"))
      expect(yard_lint_config.dig("AllValidators", "FailOnSeverity")).to eq("error")
      expect(yard_lint_config.dig("Tags/Order", "EnforcedOrder")).to include("param", "return")
      expect(yard_lint_config).not_to have_key("FailOnSeverity")
      expect(yard_lint_config.fetch("Tags/Order")).not_to have_key("Order")
      expect(File).to exist(File.join(root, ".yardopts"))
      expect(File.read(File.join(root, "gemfiles", "modular", "documentation.gemfile"))).to include('gem "yard-lint"')
      updated_config = YAML.safe_load_file(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      expect(updated_config.dig("templates", "profile")).to eq("monorepo-subgem-release")
      expect(updated_config.dig("templates", "entries")).to include("Rakefile", ".yard-lint.yml", ".yardopts")
    end
  end

  it "renders version_gem Ruby and RBS files from packaged templates" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-template-files", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
                target: lib/example/gem/version.rb
              - source: sig/gem.rbs
                target: sig/example/gem.rbs
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/example/gem/version.rb", "sig/example/gem.rbs")
      version_rb = File.read(File.join(root, "lib", "example", "gem", "version.rb"))
      expect(version_rb).to include("module Example")
      expect(version_rb).to include("module Gem")
      expect(version_rb).to include("# Version namespace for this gem.")
      expect(version_rb).to include("# Current gem version.")
      expect(version_rb).to include("# Current gem version exposed at the traditional constant location.")
      expect(version_rb).to include('VERSION = "1.2.3"')
      expect(version_rb).not_to end_with("\n\n")
      version_rbs = File.read(File.join(root, "sig", "example", "gem.rbs"))
      expect(version_rbs).to include("module Example")
      expect(version_rbs).to include("module Gem")
      expect(version_rbs).to include("VERSION: String")
      expect(version_rbs).not_to end_with("\n\n")
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "version_gem_bootstrap" }
      expect(post_step.fetch(:changed_files)).to eq(["lib/example/gem.rb", "spec/example/gem/version_spec.rb"])
    end
  end

  it "renders a configured dedicated version_gem entrypoint from packaged templates" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-dedicated-template", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 2.2"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          rubygems:
            version_gem_entrypoint: dedicated
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
              - source: lib/gem/version_gem.rb
              - source: sig/gem.rbs
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include(
        "lib/example/gem/version.rb",
        "lib/example/gem/version_gem.rb",
        "lib/example/gem.rb"
      )
      version_gem_rb = File.read(File.join(root, "lib", "example", "gem", "version_gem.rb"))
      expect(version_gem_rb).to include('require "version_gem"')
      expect(version_gem_rb).to include('require_relative "version"')
      expect(version_gem_rb).to include("Example::Gem::Version.class_eval do")
      entrypoint = File.read(File.join(root, "lib", "example", "gem.rb"))
      expect(entrypoint).to include('require_relative "gem/version"')
      expect(entrypoint).not_to include('require "version_gem"')
      expect(entrypoint).not_to include("VersionGem::Basic")
    end
  end

  it "skips dedicated version_gem templates for Ruby floors below 2.2" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-old-ruby-template", tmp_root) do |root|
      write_tree(root, {
        "legacy-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "legacy-gem"
            spec.version = "1.2.3"
            spec.summary = "Legacy gem"
            spec.required_ruby_version = ">= 1.8.7"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          rubygems:
            min_ruby: "1.8.7"
            version_gem_entrypoint: dedicated
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
              - source: lib/gem/version_gem.rb
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/legacy/gem/version.rb")
      expect(apply.fetch(:changed_files)).not_to include("lib/legacy/gem/version_gem.rb")
      expect(File).not_to exist(File.join(root, "lib", "legacy", "gem", "version_gem.rb"))
      version_rb = File.read(File.join(root, "lib", "legacy", "gem", "version.rb"))
      expect(version_rb).to include("module Version")
      expect(version_rb).to include("VERSION = Version::VERSION # Traditional Constant Location")
      expect(version_rb).not_to include("VersionGem")
    end
  end

  it "replaces legacy version files with the packaged version_gem template" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-accept-template", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        "lib/example/gem/version.rb" => <<~RUBY,
          module Example
            module Gem
              VERSION = "1.2.3"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
                target: lib/example/gem/version.rb
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/example/gem/version.rb")
      version_rb = File.read(File.join(root, "lib", "example", "gem", "version.rb"))
      expect(version_rb).to include("# frozen_string_literal: true")
      expect(version_rb).to include("module Version")
      expect(version_rb).to include("# Version namespace for this gem.")
      expect(version_rb).to include("# Current gem version.")
      expect(version_rb).to include("# Current gem version exposed at the traditional constant location.")
      expect(version_rb).to include('VERSION = "1.2.3"')
      expect(version_rb).to include("VERSION = Version::VERSION # Traditional Constant Location")
      expect(version_rb).not_to include("module Gem\n    VERSION")
      expect(version_rb).not_to end_with("\n\n")
    end
  end

  it "uses configured RubyGems entrypoint and namespace for version_gem files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-configured-entrypoint", tmp_root) do |root|
      write_tree(root, {
        "turbo_tests2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "turbo_tests2"
            spec.version = "3.0.0"
            spec.summary = "Turbo tests"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "🚀"
          rubygems:
            entrypoint_require: "turbo_tests"
            namespace: "TurboTests"
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
              - source: sig/gem.rbs
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      expect(apply.fetch(:changed_files)).to include("lib/turbo_tests/version.rb", "sig/turbo_tests.rbs")
      expect(apply.fetch(:changed_files)).not_to include("lib/turbo_tests2/version.rb")
      version_rb = File.read(File.join(root, "lib", "turbo_tests", "version.rb"))
      expect(version_rb).to include("module TurboTests")
      version_rbs = File.read(File.join(root, "sig", "turbo_tests.rbs"))
      expect(version_rbs).to include("module TurboTests")
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "version_gem_bootstrap" }
      expect(post_step.fetch(:changed_files)).to include("lib/turbo_tests.rb")
      expect(post_step.fetch(:changed_files)).not_to include("lib/turbo_tests2.rb")
    end
  end

  it "preserves a legacy nested version namespace when bootstrapping version_gem" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-legacy-version-namespace", tmp_root) do |root|
      write_tree(root, {
        "activesupport-broadcast_logger.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "activesupport-broadcast_logger"
            spec.version = "2.0.4"
            spec.summary = "Broadcast logger"
            spec.required_ruby_version = ">= 2.7.0"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        "lib/activesupport-broadcast_logger.rb" => <<~RUBY,
          require_relative "activesupport/broadcast_logger/version"

          module Activesupport
          end

          Activesupport::BroadcastLogger::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/activesupport/broadcast_logger/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Activesupport
            module BroadcastLogger
              module Version
                VERSION = "2.0.4"
              end
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          rubygems:
            version_gem_entrypoint: auto
          templates:
            root: packaged
            apply: true
            entries:
              - source: lib/gem/version.rb
                target: lib/activesupport/broadcast_logger/version.rb
        YAML
      })

      described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})

      version_rb = File.read(File.join(root, "lib", "activesupport", "broadcast_logger", "version.rb"))
      expect(version_rb).to include("module Activesupport")
      expect(version_rb).to include("module BroadcastLogger")
      expect(version_rb).not_to include("module ActiveSupport")
      expect(version_rb).to include('VERSION = "2.0.4"')
    end
  end

  it "migrates all legacy nested RBS files into the package-level signature" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rbs-consolidation", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        "sig/example/gem/version.rbs" => <<~RBS,
          module Example
            module Gem
              module Version
                VERSION: String
              end

              VERSION: String
            end
          end
        RBS
        "sig/example/gem/client.rbs" => <<~RBS,
          module Example
            module Gem
              class Client
              end
            end
          end
        RBS
        "sig/example/gem/nested/tool.rbs" => <<~RBS
          module Example
            module Gem
              module Nested
                class Tool
                end
              end
            end
          end
        RBS
      })

      step = described_class.send(
        :version_gem_bootstrap_step,
        root,
        {
          package: {name: "example-gem"},
          rubygems: {entrypoint_require: "example/gem", namespace: "Example::Gem"},
          project_runtime: {version: "1.2.3"}
        }
      )

      expect(step.fetch(:changed_files)).to include(
        "sig/example/gem.rbs",
        "sig/example/gem/client.rbs",
        "sig/example/gem/nested/tool.rbs",
        "sig/example/gem/version.rbs"
      )
      expect(step.fetch(:signature_path)).to eq("sig/example/gem.rbs")
      expect(File).to exist(File.join(root, "sig", "example", "gem.rbs"))
      expect(File).not_to exist(File.join(root, "sig", "example", "gem", "version.rbs"))
      expect(File).not_to exist(File.join(root, "sig", "example", "gem", "client.rbs"))
      expect(File).not_to exist(File.join(root, "sig", "example", "gem", "nested", "tool.rbs"))
      signature = File.read(File.join(root, "sig", "example", "gem.rbs"))
      expect(signature).to include("module Example")
      expect(signature).to include("module Gem")
      expect(signature).to include("module Version")
      expect(signature).to include("class Client")
      expect(signature).to include("module Nested")
      expect(signature).to include("class Tool")
      expect(signature.scan("VERSION: String").size).to eq(2)
    end
  end

  it "migrates all legacy nested RBS files when the package-level signature is templated" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-templated-rbs-consolidation", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            entrypoint_require: "example/gem"
            namespace: "Example::Gem"
          templates:
            root: template
            apply: true
            entries:
              - source: sig/example/gem.rbs
        YAML
        "template/sig/example/gem.rbs.example" => <<~RBS,
          module Example
            module Gem
              VERSION: String
            end
          end
        RBS
        "sig/example/gem/version.rbs" => <<~RBS,
          module Example
            module Gem
              module Version
                BUILD: String
              end
            end
          end
        RBS
        "sig/example/gem/client.rbs" => <<~RBS
          module Example
            module Gem
              class Client
              end
            end
          end
        RBS
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "version_gem_bootstrap" }

      expect(post_step.fetch(:changed_files)).to include("sig/example/gem.rbs", "sig/example/gem/client.rbs", "sig/example/gem/version.rbs")
      expect(File).not_to exist(File.join(root, "sig", "example", "gem", "version.rbs"))
      expect(File).not_to exist(File.join(root, "sig", "example", "gem", "client.rbs"))
      signature = File.read(File.join(root, "sig", "example", "gem.rbs"))
      expect(signature).to include("VERSION: String")
      expect(signature).to include("module Version")
      expect(signature).to include("BUILD: String")
      expect(signature).to include("class Client")
    end
  end

  it "migrates legacy nested RBS files without requiring a version_gem dependency" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rbs-consolidation-without-version-gem", tmp_root) do |root|
      write_tree(root, {
        "kettle-family.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-family"
            spec.version = "1.2.3"
            spec.summary = "Kettle family"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "2.1"
            namespace: "Kettle::Family"
          templates:
            root: template
            apply: true
            entries:
              - source: sig/kettle/family.rbs
        YAML
        "template/sig/kettle/family.rbs.example" => <<~RBS,
          module Kettle
            module Family
              VERSION: String
            end
          end
        RBS
        "sig/kettle/family/version.rbs" => <<~RBS
          module Kettle
            module Family
              module Version
                VERSION: String
              end
            end
          end
        RBS
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true, accept: true})
      post_step = apply.fetch(:post_apply_steps).find { |step| step.fetch(:name) == "legacy_rbs_consolidation" }

      expect(post_step.fetch(:changed_files)).to include("sig/kettle/family.rbs", "sig/kettle/family/version.rbs")
      expect(File).not_to exist(File.join(root, "sig", "kettle", "family", "version.rbs"))
      signature = File.read(File.join(root, "sig", "kettle", "family.rbs"))
      expect(signature).to include("module Version")
      expect(signature.scan("VERSION: String").size).to eq(2)
    end
  end

  it "bootstraps a monorepo root template profile with shared documentation entries" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-root", tmp_root) do |root|
      setup = described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-root", skip_commit: true}
      )
      config = File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))
      config_yaml = YAML.safe_load(config)

      expect(setup.fetch(:changed_files)).to include(".structuredmerge/kettle-jem.yml")
      expect(config_yaml.dig("templates", "root")).to eq("packaged")
      expect(config_yaml.dig("templates", "apply")).to be(true)
      expect(config_yaml.dig("templates", "profile")).to eq("monorepo-root")
      expect(config_yaml.dig("templates", "entries")).to include(
        "CHANGELOG.md",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "FUNDING.md",
        "Gemfile",
        "IRP.md",
        "LICENSE.md",
        "AGPL-3.0-only.md",
        "PolyForm-Small-Business-1.0.0.md",
        "RUBOCOP.md",
        "Rakefile",
        "SECURITY.md",
        ".github/FUNDING.yml",
        ".structuredmerge/git-drivers.toml"
      )
      expect(config_yaml.dig("files", "CHANGELOG.md", "strategy")).to eq("keep_destination")
      expect(config_yaml.dig("files", "Gemfile", "strategy")).to eq("accept_template")
      expect(described_class.send(:monorepo_root_file_strategy, "Gemfile")).to eq("accept_template")
      expect(config.lines.count { |line| line == "  .github:\n" }).to eq(1)
    end
  end

  it "removes stale monorepo subgem gemspec overrides when syncing template profiles" do
    content = <<~YAML
      project_emoji: "💎"
      templates:
        root: packaged
        apply: true
        profile: monorepo-subgem-package
        entries:
          - README.md
      files:
        README.md:
          strategy: merge
        plain-merge.gemspec:
          strategy: keep_destination
        gemfiles:
          strategy: keep_destination
    YAML

    updated = described_class.send(
      :sync_kettle_config_monorepo_subgem_profile,
      content,
      "bash-merge.gemspec",
      "monorepo-subgem-package"
    )
    config_yaml = YAML.safe_load(updated)

    expect(config_yaml.dig("files", "bash-merge.gemspec", "strategy")).to eq("merge")
    expect(config_yaml.dig("files", "Rakefile", "strategy")).to eq("accept_template")
    expect(config_yaml.fetch("files")).not_to have_key("plain-merge.gemspec")
    expect(config_yaml.dig("files", "gemfiles", "strategy")).to eq("keep_destination")
  end

  it "templates a monorepo root without a gemspec and syncs root Gemfile tooling dependencies" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-root-apply", tmp_root) do |root|
      write_tree(root, {
        "AGPL-3.0-only.md" => "AGPL\n",
        "PolyForm-Small-Business-1.0.0.md" => "PolyForm\n",
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🍲"
          licenses:
            - MIT
          templates:
            root: packaged
            apply: true
            profile: monorepo-root
            entries:
              - Gemfile
              - Rakefile
              - LICENSE.md
              - AGPL-3.0-only.md
              - PolyForm-Small-Business-1.0.0.md
          files:
            Gemfile:
              strategy: keep_destination
            Rakefile:
              strategy: accept_template
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          # gem "kettle-dev"
          warn "kettle-test" if false
          gemspec path: "gems/kettle-jem"
          gem "rake"
        RUBY
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, template_profile: "monorepo-root", skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))
      rakefile = File.read(File.join(root, "Rakefile"))

      expect(report.fetch(:changed_files)).to include("Gemfile", "LICENSE.md")
      expect(report.fetch(:facts).dig(:license, :spdx)).to eq(["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"])
      expect(gemfile).to include('gemspec path: "gems/kettle-jem"')
      expect(gemfile).not_to include('gem "kettle-jem", "~> 7.0"')
      expect_gem_dependency_declared(gemfile, "kettle-dev")
      expect_gem_dependency_declared(gemfile, "kettle-family")
      expect_gem_dependency_declared(gemfile, "kettle-test")
      expect(gemfile.lines.count { |line| line.start_with?('gem "kettle-dev"') }).to eq(1)
      expect(gemfile.lines.count { |line| line.start_with?('gem "kettle-family"') }).to eq(1)
      expect(gemfile.lines.count { |line| line.start_with?('gem "kettle-test"') }).to eq(1)
      expect_gem_dependency_declared(gemfile, "turbo_tests2")
      expect(rakefile).to include('require "kettle/dev"')
      expect(rakefile).to include("Kettle::Dev.install_tasks")
      expect(rakefile).to include("namespace :family do")
      expect(rakefile).to include('run_kettle_family("check")')
    end
  end

  it "adds released root Gemfile tooling even when local nomono overrides are present" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-root-gemfile-released-tooling", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🍲"
          licenses:
            - MIT
          templates:
            root: packaged
            apply: true
            profile: monorepo-root
            entries:
              - Gemfile
          files:
            Gemfile:
              strategy: keep_destination
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          unless ENV.fetch("KETTLE_DEV_DEV", "false").casecmp("false").zero?
            require "nomono/bundler"

            eval_nomono_gems(
              gems: %w[kettle-dev kettle-test],
              prefix: "KETTLE_DEV",
              path_env: "KETTLE_DEV_DEV",
              vendored_gems_env: "VENDORED_GEMS",
              vendor_gem_dir_env: "VENDOR_GEM_DIR",
              debug_env: "KETTLE_DEV_DEBUG",
            )
          end
        RUBY
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, template_profile: "monorepo-root", skip_commit: true}
      )
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(report.fetch(:changed_files)).to include("Gemfile")
      expect_gem_dependency_declared(gemfile, "kettle-dev")
      expect_gem_dependency_declared(gemfile, "kettle-family")
      expect_gem_dependency_declared(gemfile, "kettle-test")
      expect_gem_dependency_declared(gemfile, "turbo_tests2")
    end
  end

  it "guards preserved main Gemfile local workspace overrides during templating" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-templating-local-guard", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "Demo"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          gemspec

          unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
            require "nomono/bundler"

            eval_nomono_gems(
              gems: %w[auth-sanitizer oauth-tty snaky_hash version_gem],
              prefix: "RUBY_OAUTH",
              path_env: "RUBY_OAUTH_DEV",
              root: %w[code src ruby-oauth],
              debug_env: "RUBY_OAUTH_DEBUG"
            )
          end
        RUBY
      })

      report = described_class.apply_project(root, env: {}, run_options: {accept: true, force: true, skip_commit: true})
      gemfile = File.read(File.join(root, "Gemfile"))

      expect(report.fetch(:changed_files)).to include("Gemfile")
      expect(gemfile).to include('eval_gemfile "gemfiles/modular/templating.gemfile" if ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?')
      expect(gemfile).to include(<<~RUBY.rstrip)
        unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
          unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
            require "nomono/bundler"

            eval_nomono_gems(
      RUBY
      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true, skip_commit: true})
      reapplied_gemfile = File.read(File.join(root, "Gemfile"))
      guard_line = %(unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?\n)
      expect(reapplied_gemfile.lines.count(guard_line)).to eq(1)
    end
  end

  it "collapses duplicate templating guards around main Gemfile local workspace overrides" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemfile-templating-local-guard-collapse", tmp_root) do |root|
      write_tree(root, {
        "demo.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "Demo"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "💎"
          templates:
            root: packaged
            apply: true
            entries:
              - Gemfile
        YAML
        "Gemfile" => <<~RUBY
          source "https://gem.coop"

          gemspec

          unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
            unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
              unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
                require "nomono/bundler"

                eval_nomono_gems(
                  gems: %w[version_gem],
                  prefix: "RUBY_OAUTH",
                  path_env: "RUBY_OAUTH_DEV"
                )
              end
            end
          end
        RUBY
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, force: true, skip_commit: true})
      gemfile = File.read(File.join(root, "Gemfile"))
      guard_line = %(unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?\n)
      expect(gemfile.lines.count(guard_line)).to eq(1)
      expect(gemfile).to include(<<~RUBY.rstrip)
        unless ENV.fetch("K_JEM_TEMPLATING", "false").casecmp("true").zero?
          unless %w[false 0 no off].include?(ENV.fetch("RUBY_OAUTH_DEV", "false").downcase)
            require "nomono/bundler"
      RUBY
    end
  end

  it "preserves monorepo root Rakefile tasks during scaffold cleanup" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-root-rakefile", tmp_root) do |root|
      write_tree(root, {
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🍲"
          templates:
            root: packaged
            apply: true
            profile: monorepo-root
            entries: []
        YAML
        "Rakefile" => <<~RUBY
          require "rake/testtask"
          require "rspec/core/rake_task"

          RSpec::Core::RakeTask.new(:spec)

          task default: :spec
        RUBY
      })

      report = described_class.apply_project(
        root,
        env: {},
        run_options: {accept: true, force: true, template_profile: "monorepo-root", skip_commit: true}
      )
      rakefile_report = report.fetch(:recipe_reports).find { |recipe| recipe.fetch(:recipe_name) == "rakefile_scaffold_cleanup" }

      expect(rakefile_report.dig(:request_envelope, :request, :runtime_context, :delete_selectors)).to be_empty
      expect(File.read(File.join(root, "Rakefile"))).to include("RSpec::Core::RakeTask.new(:spec)")
      expect(File.read(File.join(root, "Rakefile"))).to include("task default: :spec")
    end
  end

  it "rewrites monorepo subgem README policy document references to source-hosted URLs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-subgem-readme-links", tmp_root) do |root|
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
            spec.licenses = ["AGPL-3.0-only"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "☯️"
          templates:
            root: template
            apply: true
            profile: monorepo-subgem
            entries:
              - README.md
          files:
            README.md:
              strategy: accept_template
        YAML
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}

          ## 🤝 Contributing

          See [CONTRIBUTING.md][🤝contributing].

          ## 🔐 Security

          See [SECURITY.md][🔐security].

          ## 📌 Versioning

          See [CHANGELOG.md][📌changelog].

          [🤝contributing]: CONTRIBUTING.md
          [🪇conduct]: CODE_OF_CONDUCT.md
          [📌changelog]: CHANGELOG.md
          [🧹rubocop]: RUBOCOP.md
          [🚨irp]: IRP.md
          [🔐security]: SECURITY.md
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "README.md" }
      readme = report.fetch(:final_content)
      source_root = "https://github.com/structuredmerge/structuredmerge-ruby/blob/main"

      expect(readme).to include("[🤝contributing]: #{source_root}/CONTRIBUTING.md")
      expect(readme).to include("[🪇conduct]: #{source_root}/CODE_OF_CONDUCT.md")
      expect(readme).to include("[📌changelog]: #{source_root}/CHANGELOG.md")
      expect(readme).to include("[🧹rubocop]: #{source_root}/RUBOCOP.md")
      expect(readme).to include("[🚨irp]: #{source_root}/IRP.md")
      expect(readme).to include("[🔐security]: #{source_root}/SECURITY.md")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "exposes canonical repository URL tokens for monorepo subgem templates" do
    repository = {
      url: "https://github.com/structuredmerge/structuredmerge-ruby",
      name: "structuredmerge-ruby",
      slug: "structuredmerge/structuredmerge-ruby",
      package_path: "gems/ast-merge",
      package_source_url: "https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge",
      gitlab_package_source_url: "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/ast-merge",
      codeberg_package_source_url: "https://codeberg.org/structuredmerge/structuredmerge-ruby/src/branch/main/gems/ast-merge",
      checksums_url: "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/checksums"
    }
    tokens = described_class.send(:readme_url_template_tokens, repository, "ast-merge", "structuredmerge")

    expect(tokens.fetch("KJ|README:GH_REPOSITORY_URL")).to eq("https://github.com/structuredmerge/structuredmerge-ruby")
    expect(tokens.fetch("KJ|README:GH_PACKAGE_SOURCE_URL")).to eq(
      "https://github.com/structuredmerge/structuredmerge-ruby/tree/main/gems/ast-merge"
    )
    expect(tokens.fetch("KJ|README:GH_CONTRIBUTING_URL")).to eq(
      "https://github.com/structuredmerge/structuredmerge-ruby/blob/main/CONTRIBUTING.md"
    )
    expect(tokens.fetch("KJ|README:GL_PACKAGE_SOURCE_URL")).to eq(
      "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tree/main/gems/ast-merge"
    )
    expect(tokens.fetch("KJ|CHANGELOG:GL_COMPARE_URL")).to eq(
      "https://gitlab.com/structuredmerge/structuredmerge-ruby/-/compare"
    )
    expect(tokens.fetch("KJ|CHANGELOG:GL_TAGS_URL")).to eq("https://gitlab.com/structuredmerge/structuredmerge-ruby/-/tags")
  end

  it "projects monorepo subgem README output to thin form while preserving destination-owned sections" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-monorepo-subgem-thin-readme", tmp_root) do |root|
      write_tree(root, {
        "ast-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "ast-merge"
            spec.summary = "Example gem"
            spec.homepage = "https://github.com/structuredmerge/structuredmerge-ruby"
            spec.licenses = ["AGPL-3.0-only"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "☯️"
          templates:
            root: template
            apply: true
            profile: monorepo-subgem
            entries:
              - README.md
          files:
            README.md:
              strategy: merge
        YAML
        "README.md" => <<~MARKDOWN,
          # Existing

          ## 🌻 Synopsis

          Destination synopsis.

          ## ⚙️ Configuration

          Destination configuration.

          ## 🔧 Basic Usage

          Destination usage.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          # {KJ|PROJECT_EMOJI} {KJ|NAMESPACE}

          ## 🌻 Synopsis

          Template synopsis.

          ## 💡 Info you can shake a stick at

          Info.

          ### Compatibility

          Compatible.

          ### Enterprise Support

          Heavy support content.

          ## ✨ Installation

          Install.

          ## ⚙️ Configuration

          Template configuration.

          ## 🔧 Basic Usage

          Template usage.

          ## 🦷 FLOSS Funding

          Funding.

          ## 🔐 Security

          See [SECURITY.md][🔐security].

          ## 🤝 Contributing

          Contributions.

          ### Code Coverage

          Coverage.

          ## 🌈 Contributors

          Contributors.

          ## 📌 Versioning

          Versioning.

          ## 📄 License

          License.

          ## 🤑 A request for help

          Request.

          [🔐security]: SECURITY.md
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {}, run_options: {skip_commit: true})
      readme = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "README.md" }.fetch(:final_content)

      expect(readme).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis\./)
      expect(readme).to include("## ⚙️ Configuration\n\nDestination configuration.")
      expect(readme).to include("## 🔧 Basic Usage\n\nDestination usage.")
      expect(readme).to include("### Compatibility")
      expect(readme).to include("## ✨ Installation")
      expect(readme).to include("## 🔐 Security")
      expect(readme).not_to include("### Enterprise Support")
      expect(readme).not_to include("## 🦷 FLOSS Funding")
      expect(readme).not_to include("### Code Coverage")
      expect(readme).not_to include("## 🌈 Contributors")
      expect(readme).not_to include("## 🤑 A request for help")
    end
  end

  it "seeds a default project emoji for monorepo subgems without a README" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-monorepo-subgem-emoji", tmp_root) do |root|
      write_tree(root, {
        "ast-crispr.gemspec" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "ast-crispr"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
          end
        RUBY
      })

      described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )

      expect(File.read(File.join(root, described_class::KETTLE_CONFIG_PATH))).to include("project_emoji: 💎\n")
    end
  end

  it "seeds project emoji from KJ_PROJECT_EMOJI before README or defaults" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-env-emoji", tmp_root) do |root|
      write_tree(root, {
        "json-merge.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "json-merge"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
          end
        RUBY
        "README.md" => "# 💎 Json::Merge\n\nExisting README.\n"
      })

      described_class.setup_project(
        root,
        env: {"KJ_PROJECT_EMOJI" => "☯️"},
        run_options: {bootstrap_mode: true, template_profile: "monorepo-subgem", skip_commit: true}
      )

      expect(File.read(File.join(root, described_class::KETTLE_CONFIG_PATH))).to include("project_emoji: ☯️\n")
    end
  end

  it "seeds project emoji from gemspec summary when README has no leading H1" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-bootstrap-gemspec-emoji", tmp_root) do |root|
      write_tree(root, {
        "yaml-converter.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "yaml-converter"
            spec.summary = "🥨 Convert annotated YAML blueprints into readable documentation."
            spec.licenses = ["MIT"]
          end
        RUBY
        "README.md" => <<~MARKDOWN
          | 📍 NOTE |
          |---------|
          | Existing preface. |

          # Yaml::Converter
        MARKDOWN
      })

      described_class.setup_project(
        root,
        env: {},
        run_options: {bootstrap_mode: true, skip_commit: true}
      )

      expect(File.read(File.join(root, ".structuredmerge", "kettle-jem.yml"))).to include("project_emoji: 🥨\n")
    end
  end

  def configure_dependency_conflicts(root, resolve)
    path = File.join(root, ".structuredmerge", "kettle-jem.yml")
    lines = File.read(path).lines
    start = lines.index { |line| line.match?(/\Adependency_conflicts:\s*$/) }
    finish = (start + 1...lines.length).find { |index| lines[index].match?(/\A\S/) }
    replacement = [
      "dependency_conflicts:\n",
      "  # Test fixture declares its direct-versus-modular ownership decisions.\n",
      "  reviewed: true\n",
      "  resolve:\n"
    ]
    resolve.each do |entry|
      replacement.concat([
        "    - gem: #{entry.fetch("gem")}\n",
        "      direct: #{entry.fetch("direct")}\n",
        "      modular: #{entry.fetch("modular")}\n",
        "      action: #{entry.fetch("action")}\n",
        "      reason: #{entry.fetch("reason").dump}\n"
      ])
    end
    File.write(path, [*lines[0...start], *replacement, *lines[finish || lines.length..]].join)
  end
end
