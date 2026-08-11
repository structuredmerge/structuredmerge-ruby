# frozen_string_literal: true

RSpec.describe Kettle::Jem, "structural merge template behavior" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "uses dotenv structural merge for environment template files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-dotenv-template-merge", tmp_root) do |root|
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
              - source: .env.local
                target: .env.local.example
        YAML
        "template/.env.local.example" => <<~ENV,
          # Shared development defaults
          KETTLE_DEV_DEV=false
          DEBUG=false # keep debugging disabled by default
        ENV
        ".env.local.example" => <<~ENV
          # Local documentation must survive
          KETTLE_DEV_DEV=true
        ENV
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == ".env.local.example" }

      expect(report.fetch(:final_content)).to eq(<<~ENV)
        # Local documentation must survive
        KETTLE_DEV_DEV=true
        DEBUG=false # keep debugging disabled by default
      ENV
    end
  end

  it "uses JSONC structural merge for devcontainer JSON files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-json-template-merge", tmp_root) do |root|
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
              - source: devcontainer.json
                target: .devcontainer/devcontainer.json
        YAML
        "template/devcontainer.json.example" => <<~JSON,
          // Shared devcontainer defaults
          {
            "name": "template",
            "features": {
              "ghcr.io/devcontainers/features/git:1": {}
            }
          }
        JSON
        ".devcontainer/devcontainer.json" => <<~JSON
          // Local devcontainer settings
          {
            "name": "destination",
            "customizations": {
              "jetbrains": {
                "backend": "RubyMine"
              }
            },
            // Keep this comment after the trailing comma.
            "remoteUser": "vscode"
          }
        JSON
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == ".devcontainer/devcontainer.json" }

      expect(report.fetch(:final_content)).to include('"name": "destination"')
      expect(report.fetch(:final_content)).to include('"ghcr.io/devcontainers/features/git:1": {}')
      expect(report.fetch(:final_content)).to include("// Local devcontainer settings")
    end
  end

  it "uses JSONC structural merge for JSONC template files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-jsonc-template-merge", tmp_root) do |root|
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
              - source: settings.jsonc
                target: .vscode/settings.jsonc
        YAML
        "template/settings.jsonc.example" => <<~JSONC,
          {
            // Shared editor defaults
            "editor.tabSize": 2,
            "files.trimTrailingWhitespace": true
          }
        JSONC
        ".vscode/settings.jsonc" => <<~JSONC
          {
            // Local documentation must survive
            "editor.tabSize": 4
          }
        JSONC
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == ".vscode/settings.jsonc" }

      expect(report.fetch(:final_content)).to eq(<<~JSONC)
        {
          // Local documentation must survive
          "editor.tabSize": 4,
          "files.trimTrailingWhitespace": true
        }
      JSONC
    end
  end

  it "uses JSON5 structural merge for JSON5 template files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-json5-template-merge", tmp_root) do |root|
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
              - source: settings.json5
                target: config/settings.json5
        YAML
        "template/settings.json5.example" => <<~JSON5,
          {
            shared: true,
            'template-only': 'added',
          }
        JSON5
        "config/settings.json5" => <<~JSON5
          {
            // Local configuration must survive
            shared: false,
          }
        JSON5
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == "config/settings.json5" }

      expect(report.fetch(:final_content)).to include('"shared": false', '"template-only": \'added\'')
    end
  end

  it "uses RBS structural merge for RBS template files" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-rbs-template-merge", tmp_root) do |root|
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
              - source: sig/example/version.rbs
                target: sig/example/version.rbs
        YAML
        "template/sig/example/version.rbs.example" => <<~RBS,
          module Example
            module Version
              VERSION: String
            end

            VERSION: String
          end
        RBS
        "sig/example/version.rbs" => <<~RBS
          module Example
            module Version
              VERSION: "1.2.3"
            end
          end
        RBS
      })

      plan = described_class.plan_project(root, env: {})
      report = plan.fetch(:recipe_reports).find { |entry| entry.fetch(:relative_path) == "sig/example/version.rbs" }

      expect(report.fetch(:final_content)).to include('VERSION: "1.2.3"')
      expect(report.fetch(:final_content)).to include("VERSION: String")
    end
  end

  it "loudly rejects explicit Bash structural routing when the node parser is unavailable" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-bash-template-gate", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            scripts:
              setup:
                strategy: merge
                file_type: bash
          templates:
            root: template
            apply: true
            entries:
              - source: setup
                target: scripts/setup
        YAML
        "template/setup.example" => <<~BASH,
          #!/usr/bin/env bash
          bundle install
        BASH
        "scripts/setup" => <<~BASH
          #!/usr/bin/env bash
          bundle check || bundle install
        BASH
      })
      availability = Bash::Merge::Availability.new(
        grammar_path: nil,
        node_parser: false,
        diagnostics: [{kind: "bash_node_parser_unavailable", message: "missing node adapter"}]
      )
      allow(Bash::Merge).to receive(:availability).and_return(availability)

      expect do
        described_class.plan_project(root, env: {})
      end.to raise_error(ArgumentError, /failed to merge bash template scripts\/setup: bash structural merge is unavailable/)
    end
  end

  it "refreshes mise trust after templating mise.toml when mise is available" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-install-mise-trust", tmp_root) do |root|
      fake_bin = File.join(root, "fake-bin")
      FileUtils.mkdir_p(fake_bin)
      fake_mise = File.join(fake_bin, "mise")
      File.write(fake_mise, "#!/usr/bin/env sh\nexit 0\n")
      FileUtils.chmod(0o755, fake_mise)
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
              - mise.toml
        YAML
        "template/mise.toml.example" => <<~TOML
          [tools]
          ruby = "3.4.1"
        TOML
      })

      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end
      env = {"PATH" => "#{fake_bin}#{File::PATH_SEPARATOR}#{ENV.fetch("PATH", "")}"}

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: env,
        run_options: {only: "mise.toml", bootstrap_mode: true, skip_commit: true},
        command_runner: command_runner
      )

      expect(install.fetch(:install_steps)).to include(hash_including(
        name: "mise_trust",
        path: "mise.toml",
        command: ["mise", "trust", "-C", root],
        status: "succeeded",
        reason: "executed",
        exitstatus: 0
      ))
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        statuses: hash_including("mise_trust" => "succeeded")
      ))
      expect(commands).to include(["mise", "trust", "-C", root])
    end
  end

  it "preserves coverage thresholds from an existing coverage workflow in generated mise.toml" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-mise-coverage-thresholds", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".github/workflows/coverage.yml" => <<~YAML,
          env:
            K_SOUP_COV_MIN_BRANCH: 64
            K_SOUP_COV_MIN_LINE: 90
        YAML
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - mise.toml
        YAML
        "template/mise.toml.example" => <<~TOML
          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "92"

          [tools]
          ruby = "4.0.6"
        TOML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {only: "mise.toml", skip_commit: true})
      mise = File.read(File.join(root, "mise.toml"))

      expect(apply.fetch(:changed_files)).to include("mise.toml")
      expect(mise).to include('K_SOUP_COV_MIN_BRANCH = "64"')
      expect(mise).to include('K_SOUP_COV_MIN_LINE = "90"')
    end
  end

  it "preserves coverage thresholds from mise.toml in generated coverage workflow" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-coverage-thresholds", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        "mise.toml" => <<~TOML,
          [env]
          K_SOUP_COV_MIN_BRANCH = "76"
          K_SOUP_COV_MIN_LINE = "100"
        TOML
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: .github/workflows/coverage.yml
                target: .github/workflows/coverage.yml
        YAML
        "template/.github/workflows/coverage.yml" => <<~YAML
          name: Test Coverage

          env:
            K_SOUP_COV_MIN_BRANCH: 100
            K_SOUP_COV_MIN_LINE: 100
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {only: ".github/workflows/coverage.yml", skip_commit: true})
      workflow = File.read(File.join(root, ".github", "workflows", "coverage.yml"))

      expect(apply.fetch(:changed_files)).to include(".github/workflows/coverage.yml")
      expect(workflow).to include("K_SOUP_COV_MIN_BRANCH: 76")
      expect(workflow).to include("K_SOUP_COV_MIN_LINE: 100")
    end
  end

  it "generates QLTY coverage uploads with OIDC in the packaged coverage workflow" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-workflow-coverage-qlty-oidc", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          templates:
            apply: true
            entries:
              - source: .github/workflows/coverage.yml
                target: .github/workflows/coverage.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {}, run_options: {only: ".github/workflows/coverage.yml", skip_commit: true})
      workflow = File.read(File.join(root, ".github", "workflows", "coverage.yml"))

      expect(apply.fetch(:changed_files)).to include(".github/workflows/coverage.yml")
      expect_pinned_action(workflow, "qltysh/qlty-action/coverage")
      expect(workflow).to include("oidc: true")
      expect(workflow).not_to include("QLTY_COVERAGE_TOKEN")
      expect(workflow).not_to include("KJ|GITHUB_ACTIONS:COVERAGE_UPLOAD_STEPS")
    end
  end

  it "bootstraps version_gem touchpoints before bundled setup" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-bootstrap", tmp_root) do |root|
      write_tree(root, {
        "example-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: example-gem.gemspec
                target: example-gem.gemspec
        YAML
        "template/example-gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example-gem"
            spec.version = "1.2.3"
            spec.summary = "Example gem"
            spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
          end
        RUBY
      })
      commands = []
      command_runner = lambda do |command, **|
        commands << command
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      install = Kettle::Jem::Tasks::InstallTask.run(
        project_root: root,
        env: {},
        run_options: {only: "example-gem.gemspec", skip_commit: true},
        command_runner: command_runner
      )
      version_path = File.join(root, "lib", "example/gem/version.rb")
      entrypoint_path = File.join(root, "lib", "example/gem.rb")

      expect(install.fetch(:install_steps)).to include(
        name: "version_gem_bootstrap",
        status: "applied",
        changed_files: [
          "lib/example/gem/version.rb",
          "lib/example/gem.rb",
          "spec/example/gem/version_spec.rb",
          "sig/example/gem.rbs"
        ],
        version_path: "lib/example/gem/version.rb",
        entrypoint_path: "lib/example/gem.rb",
        signature_path: "sig/example/gem.rbs"
      )
      expect(install.fetch(:install_phase_reports)).to include(hash_including(
        phase: "post_template",
        statuses: hash_including("version_gem_bootstrap" => "applied")
      ))
      expect(File.read(version_path)).to include("module Example")
      expect(File.read(version_path)).to include("module Gem")
      expect(File.read(version_path)).to include('VERSION = "1.2.3"')
      expect(File.read(entrypoint_path)).to include('require "version_gem"')
      expect(File.read(entrypoint_path)).to include('require_relative "gem/version"')
      expect(File.read(entrypoint_path)).to include("Example::Gem::Version.class_eval do")
      signature = File.read(File.join(root, "sig", "example", "gem.rbs"))
      expect(signature).to include("module Example")
      expect(signature).to include("module Gem")
      expect(signature).to include("module Version")
      expect(signature).to include("VERSION: String")
      expect(commands).to include(
        %w[bundle binstubs appraisal2 rake rbs rspec-core yard kettle-dev kettle-test kettle-soup-cover kettle-gha-pins stone_checksums],
        kettle_jem_handoff_command("--skip-commit", "--only", "example-gem.gemspec")
      )
    end
  end

  it "uses configured version_gem namespace before stale entrypoint inference" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-version-gem-configured-namespace", tmp_root) do |root|
      write_tree(root, {
        "lib/oauth2/mcp.rb" => <<~RUBY,
          # frozen_string_literal: true

          module OAuth2
            module MCP
            end
          end

          Oauth2::Mcp::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/oauth2/mcp/version.rb" => <<~RUBY
          # frozen_string_literal: true

          module OAuth2
            module MCP
              VERSION = "0.1.0"
            end
          end
        RUBY
      })
      facts = {
        package: {name: "oauth2-mcp"},
        rubygems: {entrypoint_require: "oauth2/mcp", namespace: "OAuth2::MCP"},
        project_runtime: {version: "0.1.0"}
      }

      step = described_class.send(:version_gem_bootstrap_step, root, facts)
      version_file = File.read(File.join(root, "lib", "oauth2", "mcp", "version.rb"))
      signature = File.read(File.join(root, "sig", "oauth2", "mcp.rbs"))

      expect(step.fetch(:status)).to eq("applied")
      expect(version_file).to include("module OAuth2")
      expect(version_file).to include("module MCP")
      expect(version_file).not_to include("module Oauth2")
      expect(signature).to include("module OAuth2")
      expect(signature).to include("module MCP")
      expect(signature).not_to include("module Oauth2")
    end
  end

  it "discovers public entrypoint version namespace before stale gemspec metadata" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-version-gem-public-entrypoint-namespace", tmp_root) do |root|
      write_tree(root, {
        "oauth2.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "oauth2"
            spec.version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/oauth2/version.rb", mod) }::Oauth2::Version::VERSION
            spec.summary = "OAuth2"
            spec.required_ruby_version = ">= 2.2.0"
          end
        RUBY
        "lib/oauth2.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "oauth2/version"

          module OAuth2
          end

          OAuth2::Version.class_eval do
            extend VersionGem::Basic
          end

          Oauth2::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/oauth2/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module OAuth2
            module Version
              VERSION = "2.0.20"
            end
            VERSION = Version::VERSION
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "🔐"
          rubygems:
            min_ruby: "2.2.0"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})

      expect(facts.dig(:rubygems, :namespace)).to eq("OAuth2")
      expect(facts.dig(:rubygems, :namespace)).not_to eq("Oauth2")
    end
  end

  it "discovers nested public entrypoint namespace before stale generated version namespace" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-nested-entrypoint-namespace", tmp_root) do |root|
      write_tree(root, {
        "warden_oauth.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "warden_oauth"
            spec.version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/warden_oauth/version.rb", mod) }::WardenOauth::Version::VERSION
            spec.summary = "Warden OAuth"
            spec.required_ruby_version = ">= 1.8"
          end
        RUBY
        "lib/warden_oauth.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "warden_oauth/version"

          module Warden
            module OAuth
              autoload :Strategy, "warden_oauth/strategy"
            end
          end
        RUBY
        "lib/warden_oauth/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module WardenOauth
            module Version
              VERSION = "0.1.1"
            end
            VERSION = Version::VERSION
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "🛡️"
          rubygems:
            min_ruby: "1.8"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})
      tokens = described_class.send(:template_tokens, facts, {})

      expect(facts.dig(:rubygems, :namespace)).to eq("Warden::OAuth")
      expect(facts.dig(:rubygems, :namespace)).not_to eq("WardenOauth")
      expect(tokens.fetch("KJ|NAMESPACE_SHIELD")).to eq("Warden::OAuth")
      expect(tokens.fetch("KJ|KETTLE_CHANGELOG_GEMFILE_DEPENDENCY")).to include(
        'ENV.fetch("KETTLE_DEV_DEV", "false")',
        'ENV.fetch("KETTLE_DEV_SKIP_CHANGELOG", "false")',
        'Gem::Version.new("4.0.0")',
        'gem "kettle-changelog", "~> 1.0", ">= 1.0.0"'
      )

      facts[:package][:name] = "kettle-changelog"
      self_tokens = described_class.send(:template_tokens, facts, {})
      expect(self_tokens.fetch("KJ|KETTLE_CHANGELOG_GEMFILE_DEPENDENCY")).to eq("")
    end
  end

  it "does not infer nested implementation namespaces from the public entrypoint" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-entrypoint-implementation-namespace", tmp_root) do |root|
      write_tree(root, {
        "kettle-dev.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "kettle-dev"
            spec.version = Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/kettle/dev/version.rb", mod) }::Kettle::Dev::Version::VERSION
            spec.summary = "Kettle Dev"
            spec.required_ruby_version = ">= 2.4.0"
          end
        RUBY
        "lib/kettle/dev.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "dev/version"

          module Kettle
            module Dev
              autoload :ReleaseCLI, "kettle/dev/release_cli"

              module Tasks
                autoload :CITask, "kettle/dev/tasks/ci_task"
              end
            end
          end
        RUBY
        "lib/kettle/dev/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Kettle
            module Dev
              module Version
                VERSION = "2.3.fixture.rc1"
              end
              VERSION = Version::VERSION
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          rubygems:
            min_ruby: "2.4.0"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})

      expect(facts.dig(:rubygems, :namespace)).to eq("Kettle::Dev")
      expect(facts.dig(:rubygems, :namespace)).not_to eq("Kettle::Dev::Tasks")
    end
  end

  it "uses the existing version namespace when the entrypoint contains a nested error class" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-version-namespace-with-error", tmp_root) do |root|
      write_tree(root, {
        "stone_checksums.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "stone_checksums"
            spec.version = "1.0.8"
            spec.summary = "Stone checksums"
            spec.required_ruby_version = ">= 2.2.0"
          end
        RUBY
        "lib/stone_checksums.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "stone_checksums/version"

          module StoneChecksums
            class Error < StandardError; end
          end
        RUBY
        "lib/stone_checksums/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module StoneChecksums
            module Version
              VERSION = "1.0.8"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          rubygems:
            min_ruby: "2.2.0"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})

      expect(facts.dig(:rubygems, :namespace)).to eq("StoneChecksums")
    end
  end

  it "repairs a version namespace that conflicts with an entrypoint class declaration" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-version-namespace-kind-conflict", tmp_root) do |root|
      write_tree(root, {
        "stone_checksums.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "stone_checksums"
            spec.version = "1.0.8"
            spec.summary = "Stone checksums"
            spec.required_ruby_version = ">= 2.2.0"
          end
        RUBY
        "lib/stone_checksums.rb" => <<~RUBY,
          # frozen_string_literal: true

          module StoneChecksums
            class Error < StandardError; end
          end
        RUBY
        "lib/stone_checksums/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module StoneChecksums
            module Error
              module Version
                VERSION = "1.0.8"
              end
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML
          project_emoji: "💎"
          rubygems:
            min_ruby: "2.2.0"
        YAML
      })

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})

      expect(facts.dig(:rubygems, :namespace)).to eq("StoneChecksums")
    end
  end

  it "normalizes generated README badge image URLs consistently with pre-release checks" do
    expect(described_class.send(:shield_token, "Example::Gem")).to eq("Example::Gem")
    expect(described_class.send(:license_compat_img, :a)).to include(
      "Apache_Compatible:_Category_A-%E2%9C%93-259D6C.svg"
    )
  end

  it "places version_gem entrypoint requires from top-level Ruby structure" do
    content = <<~RUBY
      # frozen_string_literal: true

      def setup
        require "version_gem"
      end
    RUBY

    updated = described_class.send(
      :version_gem_bootstrap_entrypoint_content,
      content,
      namespace: "Example::Gem",
      entrypoint_require: "example/gem"
    )

    expect(updated).to start_with(<<~RUBY)
      # frozen_string_literal: true

      require "version_gem"
      require_relative "gem/version"

      def setup
        require "version_gem"
      end
    RUBY
    expect(updated).to include("Example::Gem::Version.class_eval do")
  end

  it "anchors version_gem relative entrypoint requires after an existing top-level version_gem require" do
    content = <<~RUBY
      # frozen_string_literal: true

      require "version_gem"

      module Example
        module Gem
        end
      end
    RUBY

    updated = described_class.send(
      :version_gem_bootstrap_entrypoint_content,
      content,
      namespace: "Example::Gem",
      entrypoint_require: "example/gem"
    )

    expect(updated).to include(<<~RUBY)
      require "version_gem"
      require_relative "gem/version"

      module Example
    RUBY
  end

  it "keeps the version require before executable code that precedes later requires" do
    content = <<~RUBY
      require "version_gem"
      require_relative "turbo_tests/version"

      TurboTests::Version.class_eval do
        extend VersionGem::Basic
      end

      require "securerandom"
    RUBY

    updated = described_class.send(
      :version_gem_bootstrap_entrypoint_content,
      content,
      namespace: "TurboTests",
      entrypoint_require: "turbo_tests"
    )

    expect(updated).to include(<<~RUBY)
      require "version_gem"
      require_relative "turbo_tests/version"

      TurboTests::Version.class_eval do
    RUBY
    expect(updated.index('require_relative "turbo_tests/version"')).to be < updated.index("TurboTests::Version.class_eval do")
  end

  it "loads runtime dependencies before a generated nested version namespace" do
    content = <<~RUBY
      require "month/serializer/version"

      # Eternal Gems
      require "month"

      class Month
        module Serializer
        end
      end
    RUBY

    updated = described_class.send(
      :version_gem_bootstrap_entrypoint_content,
      content,
      namespace: "Month::Serializer",
      entrypoint_require: "month/serializer"
    )

    expect(updated).to include(<<~RUBY)
      # Eternal Gems
      require "month"
      require "version_gem"
      require_relative "serializer/version"

      class Month
    RUBY
    expect(updated).not_to include('require "month/serializer/version"')
  end

  it "preserves a class outer namespace when generating a nested version file" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-class-version-namespace", tmp_root) do |root|
      write_tree(root, {
        "lib/month/serializer.rb" => <<~RUBY
          # frozen_string_literal: true

          require "month"

          class Month
            module Serializer
            end
          end
        RUBY
      })
      facts = {
        package: {name: "month-serializer"},
        rubygems: {
          entrypoint_require: "month/serializer",
          namespace: "Month::Serializer",
          min_ruby: "1.9.3"
        },
        project_runtime: {version: "1.0.0"}
      }

      result = described_class.send(:version_gem_bootstrap_step_for_paths, root, facts)
      version_file = File.read(File.join(root, "lib/month/serializer/version.rb"))

      expect(result[:status]).to eq("applied")
      expect(version_file).to include("class Month\n  module Serializer")
      expect(version_file).not_to include("module Month\n")
    end
  end

  it "preserves a class namespace superclass when bootstrapping version_gem" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-namespace-superclass", tmp_root) do |root|
      write_tree(root, {
        "simple_column-scopes.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "simple_column-scopes"
            spec.version = "0.1.1"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
        "lib/simple_column/scopes.rb" => <<~RUBY,
          module SimpleColumn
          end
        RUBY
        "lib/simple_column/scopes/version.rb" => <<~RUBY
          module SimpleColumn
            class Scopes < Module
              module Version
                VERSION = "0.1.1"
              end
            end
          end
        RUBY
      })
      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})
      expect(facts.dig(:rubygems, :version_namespace_superclasses)).to include(1 => "Module")
      report = {
        facts: facts,
        recipe_reports: [{relative_path: "lib/simple_column/scopes/version.rb"}],
        template_selection: {only: []}
      }

      described_class.send(:template_version_gem_bootstrap_step, root, report)

      version_file = File.read(File.join(root, "lib/simple_column/scopes/version.rb"))
      expect(version_file).to include("class Scopes < Module")
    end
  end

  it "derives a version namespace from the package name when none is configured" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-missing-version-namespace", tmp_root) do |root|
      write_tree(root, {"lib/example.rb" => "# No namespace here\n"})
      facts = {
        package: {name: "example"},
        rubygems: {entrypoint_require: "example"},
        project_runtime: {version: "1.0.0"}
      }

      result = described_class.send(:version_gem_bootstrap_step_for_paths, root, facts)

      expect(result).to include(name: "version_gem_bootstrap", status: "applied")
      expect(File.read(File.join(root, "lib/example/version.rb"))).to include("module Example")
    end
  end

  it "preserves an existing Version module include during version bootstrap" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-module-include", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = "1.0.0"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
        "lib/example.rb" => <<~RUBY,
          require_relative "example/version"

          module Example
          end
        RUBY
        "lib/example/version.rb" => <<~RUBY
          module Example
            module Version
              VERSION = "1.0.0"
            end

            VERSION = Version::VERSION
            include Version
          end
        RUBY
      })
      facts = {
        package: {name: "example"},
        rubygems: {entrypoint_require: "example", namespace: "Example"},
        project_runtime: {version: "1.0.0"}
      }

      result = described_class.send(:version_gem_bootstrap_step_for_paths, root, facts)
      version_file = File.read(File.join(root, "lib/example/version.rb"))

      expect(result[:status]).to eq("applied")
      expect(version_file).to include("include Version")
    end
  end

  it "preserves a Version module include when the version recipe runs first" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-module-include-recipe", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = "1.0.0"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: lib/gem/version.rb
                target: lib/example/version.rb
        YAML
        "lib/example.rb" => <<~RUBY,
          require_relative "example/version"

          module Example
          end
        RUBY
        "lib/example/version.rb" => <<~RUBY,
          module Example
            module Version
              VERSION = "1.0.0"
            end

            VERSION = Version::VERSION
            include Version
          end
        RUBY
        "template/lib/gem/version.rb.example" => <<~RUBY
          module Example
            module Version
              VERSION = "1.0.0"
            end

            VERSION = Version::VERSION
          end
        RUBY
      })

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(File.read(File.join(root, "lib/example/version.rb"))).to include("include Version")
    end
  end

  it "requires a package entrypoint when it loads the nested version file" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-package-version-spec-entrypoint", tmp_root) do |root|
      write_tree(root, {
        "lib/example-gem.rb" => <<~RUBY,
          require_relative "example/version"
        RUBY
        "lib/example/version.rb" => <<~RUBY,
          module Example
            module Version
              VERSION = "1.0.0"
            end
          end
        RUBY
        "spec/example/version_spec.rb" => <<~RUBY
          require "anonymous_loader"
          require "example/version"
          RSpec.describe Example::Version do
          end
        RUBY
      })

      described_class.send(
        :normalize_version_gem_version_spec,
        root,
        "spec/example/version_spec.rb",
        "example/version",
        "Example",
        ensure_version_gem_require: false,
        package_name: "example-gem",
        ensure_package_entrypoint_require: true
      )

      version_spec = File.read(File.join(root, "spec/example/version_spec.rb"))
      expect(version_spec).to include('require "example-gem"')
      expect(version_spec).not_to include('require "example/version"')
    end
  end

  it "repairs a recipe-generated module wrapper when the entrypoint outer namespace is a class" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-class-version-repair", tmp_root) do |root|
      write_tree(root, {
        "lib/month/serializer.rb" => <<~RUBY,
          require "month"

          class Month
            module Serializer
            end
          end
        RUBY
        "lib/month/serializer/version.rb" => <<~RUBY
          module Month
            module Serializer
            end
          end
        RUBY
      })
      facts = {
        package: {name: "month-serializer"},
        rubygems: {
          entrypoint_require: "month/serializer",
          namespace: "Month::Serializer",
          min_ruby: "1.9.3"
        },
        project_runtime: {version: "1.0.0"}
      }
      report = {
        facts: facts,
        recipe_reports: [{relative_path: "lib/month/serializer/version.rb"}],
        template_selection: {only: []}
      }

      result = Array(described_class.send(:template_version_gem_bootstrap_step, root, report)).find do |step|
        step[:name] == "version_bootstrap"
      end
      version_file = File.read(File.join(root, "lib/month/serializer/version.rb"))

      expect(result[:status]).to eq("applied")
      expect(version_file).to include("class Month\n  module Serializer")
      expect(version_file).not_to include("module Month\n")
    end
  end

  it "preserves a class namespace when the class is loaded by the entrypoint" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-loaded-class-version-repair", tmp_root) do |root|
      write_tree(root, {
        "activesupport-broadcast_logger.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "activesupport-broadcast_logger"
            spec.version = "2.0.4"
            spec.required_ruby_version = ">= 2.7.0"
            spec.add_dependency "version_gem", "~> 1.1"
          end
        RUBY
        "lib/activesupport/broadcast_logger.rb" => <<~RUBY,
          module ActiveSupport
            class BroadcastLogger
            end
          end

          require_relative "broadcast_logger/version"
        RUBY
        "lib/activesupport/broadcast_logger/version.rb" => <<~RUBY
          module ActiveSupport
            module BroadcastLogger
              module Version
                VERSION = "2.0.4"
              end
            end
          end
        RUBY
      })
      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})
      expect(facts.dig(:rubygems, :version_namespace_kinds)).to include(1 => :class)
      report = {
        facts: facts,
        recipe_reports: [{relative_path: "lib/activesupport/broadcast_logger/version.rb"}],
        template_selection: {only: []}
      }

      described_class.send(:template_version_gem_bootstrap_step, root, report)

      version_file = File.read(File.join(root, "lib/activesupport/broadcast_logger/version.rb"))
      expect(version_file).to include("class BroadcastLogger")
      expect(version_file).to include("    module Version")
      expect(version_file).not_to include("module ActiveSupport\n  module BroadcastLogger")
    end
  end

  it "reports setup execution context without load-path inspection" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-setup-context-slice", tmp_root) do |root|
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
            apply: true
            entries:
              - bin/setup
        YAML
      })
      command_runner = lambda do |_command, chdir:, env:, quiet:|
        expect(chdir).to eq(root)
        expect(env).to include(
          "BUNDLE_LOCKFILE" => nil,
          "RUBYLIB" => nil,
          "RUBYOPT" => nil
        )
        expect(quiet).to be(true)
        {success: true, exitstatus: 0, stdout: "", stderr: ""}
      end

      bundled = described_class.setup_project(
        root,
        env: {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")},
        run_options: {only: "bin/setup", quiet: true},
        command_runner: command_runner
      )
      expect(bundled.fetch(:setup_execution_context)).to eq(
        bundled: true,
        source: "BUNDLE_GEMFILE",
        bundle_gemfile: File.join(root, "Gemfile")
      )
      expect(bundled.fetch(:install_steps)).to include(
        name: "bundled_handoff",
        status: "already_bundled",
        bundle_gemfile: File.join(root, "Gemfile")
      )

      bootstrap = described_class.setup_project(
        root,
        env: {"BUNDLE_GEMFILE" => File.join(root, "Gemfile")},
        run_options: {only: "bin/setup", bootstrap_mode: true}
      )
      expect(bootstrap.fetch(:setup_execution_context)).to eq(
        bundled: false,
        source: "bootstrap_mode",
        bundle_gemfile: nil
      )
    end
  end

  it "preserves configured README sections during merge template application" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          readme:
            preserve_sections:
              - synopsis
              - basic usage
              - custom section
              - authors
            preserve_patterns:
              - "note:*"
            section_aliases:
              usage: basic usage
          templates:
            root: template
            apply: true
            entries:
              - README.md
        YAML
        "README.md" => <<~MARKDOWN,
          # 1️⃣ Example

          ## Synopsis

          Destination synopsis.

          ### Details

          Destination nested detail.

          ```console
          # DANGER: keep this code comment inside the Synopsis branch.
          K_JEM_TEMPLATING=true bundle exec kettle-jem template
          ```

          ## Usage

          Destination usage.

          ## Custom Section

          Destination custom.

          ## Note: Local

          Destination note.

          ## Authors

          Destination authors.

          ## Installation

          Old install.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          # 💎 Example

          ## 🌻 Synopsis

          Template synopsis.

          ## 🔧 Basic Usage

          Template usage.

          ## Custom Section

          Template custom.

          ## Note: Local

          Template note.

          ## Installation

          Template install.
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      readme_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end
      final_content = readme_report.fetch(:final_content)
      expect(final_content).to include("# 💎 Example")
      expect(final_content).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis\./)
      expect(final_content).to include("### Details\n\nDestination nested detail.")
      expect(final_content).to include("# DANGER: keep this code comment inside the Synopsis branch.")
      expect(final_content).to include("K_JEM_TEMPLATING=true bundle exec kettle-jem template")
      expect(final_content).to include("## 🔧 Basic Usage\n\nDestination usage.")
      expect(final_content).to include("## Custom Section\n\nDestination custom.")
      expect(final_content).to include("## Note: Local\n\nDestination note.")
      expect(final_content).to include("## Authors\n\nDestination authors.")
      expect(final_content).to include("## Installation\n\nTemplate install.")
      expect(final_content).to match(/## Note: Local\n\nDestination note\.\n\n## Authors\n\nDestination authors\.\n\n## Installation/m)
      expect(final_content).not_to include("Template synopsis.")
      expect(final_content).not_to include("Template usage.")
      expect(final_content).not_to include("Template custom.")
      expect(final_content).not_to include("Template note.")
      expect(File.read(File.join(root, "README.md"))).to eq(final_content)
    end
  end

  it "does not duplicate destination-only README sections already inside a preserved parent section" do
    template = <<~MARKDOWN
      # Example

      ## 🌻 Synopsis

      Template synopsis.

      ## 💡 Info

      Template info.
    MARKDOWN
    destination = <<~MARKDOWN
      # Example

      ## Synopsis

      Destination synopsis.

      ### This README

      This README has two jobs.

      ## 💡 Info

      Destination info.
    MARKDOWN
    preserve_config = {sections: ["synopsis", "this readme"]}

    once = described_class.send(
      :merge_readme_template,
      template_content: template,
      destination_content: destination,
      preserve_config: preserve_config
    )
    twice = described_class.send(
      :merge_readme_template,
      template_content: template,
      destination_content: once,
      preserve_config: preserve_config
    )

    expect(once.scan(/^### This README$/).length).to eq(1)
    expect(twice.scan(/^### This README$/).length).to eq(1)
    expect(twice).to include(
      "## 🌻 Synopsis\n\nDestination synopsis.\n\n### This README\n\nThis README has two jobs."
    )
  end

  it "preserves a front Important section that encloses the README badge cloud" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-readme-front-important-slice", tmp_root) do |root|
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
        "README.md" => <<~MARKDOWN,
          # 💎 Example

          ## Important

          Keep this local warning.

          [![Version][version-img]][version] [![CI][ci-img]][ci]

          ## Synopsis

          Destination synopsis.
        MARKDOWN
        "template/README.md.example" => <<~MARKDOWN
          # 💎 Example

          [![Version][version-img]][version] [![CI][ci-img]][ci]

          ## 🌻 Synopsis

          Template synopsis.

          ## ✨ Installation

          Template install.
        MARKDOWN
      })

      apply = described_class.apply_project(root, env: {})
      readme = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_README_md"
      end.fetch(:final_content)

      expect(readme).to include("## Important\n\nKeep this local warning.")
      expect(readme).to match(/\A# 💎 Example\n\n## Important/m)
      expect(readme).to match(/## Important.*\[!\[Version\]\[version-img\]\]\[version\].*## 🌻 Synopsis/m)
      expect(readme).to match(/## 🌻 Synopsis(?: <a [^\n]+)?\n\nDestination synopsis\./)
      expect(readme).to include("## ✨ Installation\n\nTemplate install.")
      expect(File.read(File.join(root, "README.md"))).to eq(readme)
    end
  end

  it "only preserves recognized README front sections before the first canonical section" do
    template = <<~MARKDOWN
      # Example

      Template prelude.

      ## Synopsis

      Template synopsis.
    MARKDOWN
    important_destination = <<~MARKDOWN
      # Example

      ## Important

      Keep this warning even without badges.

      ## Synopsis

      Destination synopsis.
    MARKDOWN
    unknown_destination = <<~MARKDOWN
      # Example

      ## Old Notes

      Drop this stale front section.

      ## Synopsis

      Destination synopsis.
    MARKDOWN
    no_synopsis_destination = <<~MARKDOWN
      # Example

      ## Important

      No canonical anchor exists.
    MARKDOWN

    important = described_class.send(:preserve_readme_front_sections, template, important_destination)

    expect(important).to include("## Important\n\nKeep this warning even without badges.")
    expect(described_class.send(:preserve_readme_front_sections, template, unknown_destination)).to eq(template)
    expect(described_class.send(:preserve_readme_front_sections, template, no_synopsis_destination)).to eq(template)
    expect(described_class.send(:preserve_readme_front_sections, "# Example\n", important_destination)).to eq("# Example\n")
  end

  it "merges YAML and TOML template applications with destination values" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-config-merge-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            config:
              explicit.yml:
                strategy: merge
                file_type: yaml
          templates:
            root: template
            apply: true
            entries:
              - .github/dependabot.yml
              - config/settings.yml
              - config/tool.toml
              - config/explicit.yml
        YAML
        ".github/dependabot.yml" => <<~YAML,
          updates:
            - package-ecosystem: bundler
              directory: /
          version: 1
        YAML
        "config/settings.yml" => <<~YAML,
          engines:
            - ruby
          nested:
            value: destination
          version: 1
        YAML
        "config/tool.toml" => <<~TOML,
          title = "destination"

          [settings]
          retries = 1
        TOML
        "config/explicit.yml" => <<~YAML,
          destination_only: keep
          nested:
            value: destination
        YAML
        "template/.github/dependabot.yml.example" => <<~YAML,
          schedule:
            interval: weekly
          updates:
            - package-ecosystem: github-actions
              directory: /
          version: 2
        YAML
        "template/config/settings.yml.example" => <<~YAML,
          engines:
            - ruby
            - jruby
          nested:
            template_only: true
            value: template
          version: 2
        YAML
        "template/config/tool.toml.example" => <<~TOML,
          title = "template"

          [settings]
          retries = 3
          timeout = 30
        TOML
        "template/config/explicit.yml.example" => <<~YAML
          nested:
            value: template
            template_only: true
          template_only: added
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      dependabot_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_github_dependabot_yml"
      end
      yaml_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      toml_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_tool_toml"
      end
      explicit_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_config_explicit_yml"
      end

      expect(YAML.safe_load(dependabot_report.fetch(:final_content))).to eq(
        "schedule" => {"interval" => "weekly"},
        "updates" => [
          {
            "directory" => "/",
            "package-ecosystem" => "bundler"
          }
        ],
        "version" => 1
      )
      expect(YAML.safe_load(yaml_report.fetch(:final_content))).to eq(
        "engines" => ["ruby"],
        "nested" => {
          "template_only" => true,
          "value" => "destination"
        },
        "version" => 1
      )
      expect(toml_report.fetch(:final_content)).to eq(<<~TOML)
        title = "destination"

        [settings]
        retries = 1
        timeout = 30
      TOML
      expect(YAML.safe_load(explicit_report.fetch(:final_content))).to eq(
        "destination_only" => "keep",
        "nested" => {
          "template_only" => true,
          "value" => "destination"
        },
        "template_only" => "added"
      )
      expect(explicit_report.dig(:metadata, :template_source_preference)).to include(file_type: "yaml")
    end
  end

  it "merges Git driver TOML manifests with destination driver values" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-git-driver-toml-merge", tmp_root) do |root|
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
              - .structuredmerge/git-drivers.toml
        YAML
        ".structuredmerge/git-drivers.toml" => <<~TOML,
          version = 1
          driver_namespace = "smorg"

          [profiles.semantic-diff]
          description = "Destination driver"

          [[profiles.semantic-diff.attributes]]
          pattern = "*.rb"
          diff = "smorg-rb"

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-rb.command"
          value = "smorg-rb diff-driver"
        TOML
        "template/.structuredmerge/git-drivers.toml.example" => <<~TOML
          version = 1
          driver_namespace = "smorg"

          [profiles.semantic-diff]
          description = "Template driver"

          [[profiles.semantic-diff.attributes]]
          pattern = "*.rb"
          diff = "smorg-rb"

          [[profiles.semantic-diff.git_config]]
          scope = "global"
          key = "diff.smorg-rb.command"
          value = "smorg-rb diff-driver"

          [profiles.textconv-normalized]
          description = "Template-only profile"

          [[profiles.textconv-normalized.attributes]]
          pattern = "*.json"
          diff = "smorg-json-textconv"
        TOML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == ".structuredmerge/git-drivers.toml"
      end
      content = report.fetch(:final_content)

      expect(content).to include('diff = "smorg-rb"')
      expect(content).to include('key = "diff.smorg-rb.command"')
      expect(content).to include('value = "smorg-rb diff-driver"')
      expect(content).to include("[profiles.textconv-normalized]")
      expect(content).not_to include("smorg-ruby")
    end
  end

  it "restores documentation comments from YAML templates when destination config stripped them" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-yaml-template-comment-restore", tmp_root) do |root|
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
              - .kettle-jem.yml
        YAML
        "template/.kettle-jem.yml.example" => <<~YAML
          # kettle-jem configuration file
          templates:
            # Template root directory.
            root: template
            # Apply templates during setup.
            apply: true
            # Template entries to apply.
            entries:
              - .kettle-jem.yml
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_kettle_jem_yml"
      end
      final_content = report.fetch(:final_content)

      expect(final_content).to include("# kettle-jem configuration file")
      expect(final_content).to include("# Template root directory.")
      expect(final_content).to include("# Apply templates during setup.")
      expect(final_content).to include("# Template entries to apply.")
      expect(File.read(File.join(root, ".kettle-jem.yml"))).to eq(final_content)
    end
  end

  it "allows YAML template recipes to keep git-style destination comment policy" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-yaml-template-comment-policy", tmp_root) do |root|
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
              - config/settings.yml
          files:
            config:
              settings.yml:
                strategy: merge
                file_type: yaml
                comment_merge_policy: preserve_destination
        YAML
        "config/settings.yml" => <<~YAML,
          project:
            name: example
        YAML
        "template/config/settings.yml.example" => <<~YAML
          # project settings
          project:
            # Project display name.
            name: example
        YAML
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:recipe_name) == "template_source_application_config_settings_yml"
      end
      final_content = report.fetch(:final_content)

      expect(final_content).not_to include("# project settings")
      expect(final_content).not_to include("# Project display name.")
      expect(final_content).to include("project:")
      expect(final_content).to include("  name: example")
    end
  end

  it "merges Ruby-family template applications with destination declarations and DSL calls" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ruby-merge-slice", tmp_root) do |root|
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
              - Gemfile
              - Rakefile
              - lib/example.rb
        YAML
        "Gemfile" => <<~RUBY,
          source "https://gem.coop"
          gem "rspec"
          gem "example", path: "../example"
          eval_gemfile "gemfiles/modular/style.gemfile"
        RUBY
        "Rakefile" => <<~RUBY,
          desc "Default"
          task :default do
            puts "destination"
          end
        RUBY
        "lib/example.rb" => <<~RUBY,
          require "set"

          class Existing
            def keep
              :destination
            end
          end
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          source "https://gem.coop"
          gemspec
          eval_gemfile "gemfiles/modular/style.gemfile" if ENV.fetch("K_JEM_STYLE", "false").casecmp("true").zero?
          gem "appraisal"
          gem "example", path: "."
          gem "rake"
        RUBY
        "template/Rakefile.example" => <<~RUBY,
          desc "Default"
          task :default do
            puts "template"
          end

          desc "CI"
          task :ci do
            sh "bundle exec rspec"
          end
        RUBY
        "template/lib/example.rb.example" => <<~RUBY
          require "json"

          class Existing
            def keep
              :template
            end
          end

          class Added
            def call
              :template_only
            end
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      ruby_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_lib_example_rb"
      end
      gemfile_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Gemfile"
      end
      rakefile_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_Rakefile"
      end
      final_content = ruby_report.fetch(:final_content)

      expect(final_content).to include('require "set"')
      expect(final_content).to include('require "json"')
      expect(final_content).not_to include('require_relative "example/version"')
      expect(final_content).to include("def keep\n    :destination\n  end")
      expect(final_content).to include("class Added")
      expect(final_content).to include(":template_only")
      expect(File.read(File.join(root, "lib/example.rb"))).to eq(final_content)

      gemfile_content = gemfile_report.fetch(:final_content)
      expect(gemfile_content).to include('source "https://gem.coop"')
      expect(gemfile_content).to include("gemspec")
      expect(gemfile_content).to include('eval_gemfile "gemfiles/modular/style.gemfile" if ENV.fetch("K_JEM_STYLE", "false").casecmp("true").zero?')
      expect(gemfile_content).to include('gem "rspec"')
      expect(gemfile_content).to include('gem "rake"')
      expect(gemfile_content).not_to include('gem "appraisal"')
      expect(gemfile_content).not_to include('gem "example"')
      expect(gemfile_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "gemfile",
        operations: include(
          include(operation: "delete_dependency_declarations", deleted_gems: contain_exactly("appraisal", "example"))
        )
      )

      rakefile_content = rakefile_report.fetch(:final_content)
      expect(rakefile_content.scan(/task\s+:default/).size).to eq(1)
      expect(rakefile_content).to include('puts "destination"')
      expect(rakefile_content).to include("task :ci")
    end
  end

  it "normalizes generated Rakefile section spacing after merge" do
    rakefile = described_class.send(:normalize_generated_rakefile, <<~RAKE)
      task :custom do
        puts "custom"
      end


      ### TEMPLATING TASKS
      task "kettle:jem:selftest"
    RAKE

    expect(rakefile).to include("\n\n### TEMPLATING TASKS\n")
    expect(rakefile).not_to include("\n\n\n### TEMPLATING TASKS")
  end

  it "passes Ruby method move policy through per-file template strategy config" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-ruby-method-move-policy-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          files:
            lib:
              example.rb:
                strategy: merge
                file_type: ruby
                method_move_policy: destination_order
          templates:
            root: template
            apply: true
            entries:
              - lib/example.rb
        YAML
        "lib/example.rb" => <<~RUBY,
          class Greeter
            def beta
              :beta
            end

            def alpha
              :alpha
            end
          end
        RUBY
        "template/lib/example.rb.example" => <<~RUBY
          class Greeter
            def alpha
              :template_alpha
            end

            def beta
              :template_beta
            end

            def gamma
              :gamma
            end
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      report = apply.fetch(:recipe_reports).find do |entry|
        entry.fetch(:recipe_name) == "template_source_application_lib_example_rb"
      end
      final_content = report.fetch(:final_content)

      expect(final_content.index("def beta")).to be < final_content.index("def alpha")
      expect(final_content.scan("def alpha").size).to eq(1)
      expect(final_content.scan("def beta").size).to eq(1)
      expect(final_content.scan("def gamma").size).to eq(1)
      expect(report.dig(:metadata, :template_source_preference)).to include(
        file_type: "ruby",
        method_move_policy: "destination_order"
      )
    end
  end
end
