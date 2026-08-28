# frozen_string_literal: true

RSpec.describe Kettle::Jem, "gemspec templating" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "ports old Gemfile comment preservation, token resolution, and commented dependency policy" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:gemfile_comment_and_token_policy)
    important_block = <<~COMMENT
      #### IMPORTANT #######################################################
      # #{contract_case.fetch(:important_phrase)}; Gemfile is NOT loaded in CI #
      ####################################################### IMPORTANT ####
    COMMENT

    Dir.mktmpdir("kettle-jem-old-gemfile-comment-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{contract_case.fetch(:resolved_gem_name)}"
            spec.summary = "Example gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - Gemfile
              - gemfiles/modular/debug.gemfile
        YAML
        "Gemfile" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          #{important_block}
          # Include dependencies from #{contract_case.fetch(:resolved_gem_name)}.gemspec
          gemspec
        RUBY
        "gemfiles/modular/debug.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          # Ex-Standard Library gems
          gem "#{contract_case.fetch(:commented_dependency)}", "~> 1.15", ">= 1.15.2" # removed from stdlib in 3.5

          platform :mri do
            gem "#{contract_case.fetch(:active_dependency)}", ">= 1.1"
          end
        RUBY
        "template/Gemfile.example" => <<~RUBY,
          # frozen_string_literal: true

          source "https://gem.coop"

          #{important_block}
          # Include dependencies from #{contract_case.fetch(:token)}.gemspec
          gemspec
        RUBY
        "template/gemfiles/modular/debug.gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          # Ex-Standard Library gems
          # #{contract_case.fetch(:commented_dependency)} is included in main Gemfile (and unlocked_deps Appraisal), so it can't be included here.
          # gem "#{contract_case.fetch(:commented_dependency)}", "~> 1.15", ">= 1.15.2" # removed from stdlib in 3.5

          platform :mri do
            gem "#{contract_case.fetch(:active_dependency)}", ">= 1.1"
          end
        RUBY
      })

      first_apply = described_class.apply_project(root, env: {})
      second_apply = described_class.apply_project(root, env: {})
      gemfile_report = first_apply.fetch(:recipe_reports).find { |report| report.fetch(:relative_path) == "Gemfile" }
      debug_report = first_apply.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == "gemfiles/modular/debug.gemfile"
      end
      gemfile_content = gemfile_report.fetch(:final_content)
      debug_content = debug_report.fetch(:final_content)

      expect(gemfile_content).to include(contract_case.fetch(:important_phrase))
      expect(gemfile_content).to include("dependencies from #{contract_case.fetch(:resolved_gem_name)}.gemspec")
      expect(gemfile_content).not_to include(contract_case.fetch(:token))
      expect(debug_content).to include("#{contract_case.fetch(:commented_dependency)} is included in main Gemfile")
      expect(debug_content).to include(%(# gem "#{contract_case.fetch(:commented_dependency)}", "~> 1.15", ">= 1.15.2"))
      expect(debug_content).not_to match(/^gem "#{Regexp.escape(contract_case.fetch(:commented_dependency))}"/)
      expect(debug_content.scan(/^\s*# gem "#{Regexp.escape(contract_case.fetch(:commented_dependency))}"/).count).to eq(1)
      expect(debug_content.scan(/^\s*gem "#{Regexp.escape(contract_case.fetch(:active_dependency))}"/).count).to eq(1)
      expect(File.read(File.join(root, "Gemfile"))).to eq(gemfile_content)
      expect(File.read(File.join(root, "gemfiles/modular/debug.gemfile"))).to eq(debug_content)
      expect(second_apply.fetch(:changed_files)).not_to include("Gemfile", "gemfiles/modular/debug.gemfile")
    end
  end

  it "normalizes preserved gemspec lines to the template block receiver" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-receiver-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 3.2"
            gem.add_runtime_dependency "json", ">= 2.7"
            gem.add_development_dependency "rubocop", "~> 1.70"
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
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 3.1"
            spec.add_runtime_dependency "json", ">= 2.0"
            spec.add_development_dependency "rspec", "~> 3.13"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include('spec.summary = "Real summary"')
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 3.2"')
      expect(gemspec_content).to include('spec.add_runtime_dependency "json", ">= 2.7"')
      expect(gemspec_content).to include('spec.add_development_dependency "rubocop", "~> 1.70"')
      expect(gemspec_content).not_to include("gem.summary")
      expect(gemspec_content).not_to include("gem.add_runtime_dependency")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy)).to include(
        file_type: "gemspec",
        operations: include(
          include(operation: "preserve_project_fields", preserved_fields: include("required_ruby_version", "summary")),
          include(operation: "preserve_dependency_declarations", preserved_dependencies: include("json", "rubocop")),
          include(operation: "normalize_gemspec_receiver", from: "gem", to: "spec")
        )
      )
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "lets configured rubygems minimum Ruby override preserved gemspec Ruby floor" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-min-ruby-config-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.required_ruby_version = ">= 1.9.3"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "2.4"
          templates:
            root: template
            apply: true
            entries:
              - example.gemspec
        YAML
        "template/example.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.required_ruby_version = ">= 3.1"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include('spec.required_ruby_version = ">= 2.4"')
      expect(gemspec_content).not_to include('gem.required_ruby_version = ">= 1.9.3"')
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "inlines gemspec version loading when minimum Ruby is at least 3.1" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-modern-version-loader-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          # coding: utf-8
          # frozen_string_literal: true

          gem_version =
            if Gem.ruby_version >= Gem::Version.new("3.1")
              Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/my/gem/version.rb", mod) }::My::Gem::Version::VERSION
            else
              lib = File.expand_path("lib", __dir__)
              $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
              require "my/gem/version"
              My::Gem::Version::VERSION
            end

          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = gem_version
            gem.summary = "Modern loader"
            gem.required_ruby_version = ">= 3.2"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version =
            if Gem.ruby_version >= Gem::Version.new("3.1")
              Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/{KJ|GEM_NAME_PATH}/version.rb", mod) }::{KJ|NAMESPACE}::Version::VERSION
            else
              require_relative "lib/{KJ|GEM_NAME_PATH}/version"
              {KJ|NAMESPACE}::Version::VERSION
            end

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = gem_version
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).not_to include("gem_version =")
      expect(gemspec_content).not_to include('if RUBY_VERSION >= "3.1"')
      expect(gemspec_content).not_to include("Gemspec/RubyVersionGlobalsUsage")
      expect(gemspec_content).not_to include("$LOAD_PATH.unshift(lib)")
      expect(gemspec_content).not_to include('require "my/gem/version"')
      expect(gemspec_content).to include("spec.version = Module.new.tap { |mod| Kernel.load(\"\#{__dir__}/lib/my/gem/version.rb\", mod) }::My::Gem::Version::VERSION")
      version_loader_operation = gemspec_report.dig(
        :report_envelope,
        :report,
        :step_reports,
        0,
        :metadata,
        :ruby_template_policy,
        :operations
      ).find { |operation| operation[:operation] == "rewrite_version_loader" }
      expect(version_loader_operation).to include(mode: "modern", legacy_preamble_removed: true)
      expect(Gem::Version.new(version_loader_operation.fetch(:min_ruby))).to be >= Gem::Version.new("3.1")
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "rewrites preserved dependency requirements that interpolate the project version constant" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-version-dependency-slice", tmp_root) do |root|
      write_tree(root, {
        "gemserver-gem_coop.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "lib/gemserver/gem_coop/version"

          Gem::Specification.new do |spec|
            spec.name = "gemserver-gem_coop"
            spec.version = Gemserver::GemCoop::VERSION
            spec.summary = "Gem coop preset"
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency "gemserver-purl", "= \#{Gemserver::GemCoop::VERSION}"
          end
        RUBY
        "lib/gemserver/gem_coop/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Gemserver
            module GemCoop
              module Version
                VERSION = "0.1.0"
              end
              VERSION = Version::VERSION
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "3.2"
            entrypoint_require: "gemserver/gem_coop"
            namespace: "Gemserver::GemCoop"
          templates:
            root: template
            apply: true
            entries:
              - gemserver-gem_coop.gemspec
        YAML
        "template/gemserver-gem_coop.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_gemserver_gem_coop_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).not_to include('require_relative "lib/gemserver/gem_coop/version"')
      expect(gemspec_content).to include("spec.version = Module.new.tap { |mod| Kernel.load(\"\#{__dir__}/lib/gemserver/gem_coop/version.rb\", mod) }::Gemserver::GemCoop::Version::VERSION")
      expect(gemspec_content).to include(%(spec.add_dependency "gemserver-purl", "= \#{spec.version}"))
      expect(gemspec_content).not_to include("Gemserver::GemCoop::VERSION}")
      expect { load File.join(root, "gemserver-gem_coop.gemspec") }.not_to raise_error
      expect(File.read(File.join(root, "gemserver-gem_coop.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps gemspec legacy version loading with require_relative when minimum Ruby is below 3.1 and at least 2.2" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-legacy-version-loader-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = "0.1.0"
            gem.summary = "Legacy loader"
            gem.required_ruby_version = ">= 3.0"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include("gem_version =")
      expect(gemspec_content).to include('if Gem.ruby_version >= Gem::Version.new("3.1")')
      expect(gemspec_content).not_to include("Gemspec/RubyVersionGlobalsUsage")
      expect(gemspec_content).to include('require_relative "lib/my/gem/version"')
      expect(gemspec_content).not_to include("$LOAD_PATH.unshift(lib)")
      expect(gemspec_content).not_to include('require "my/gem/version"')
      expect(gemspec_content).to include("My::Gem::Version::VERSION")
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "rewrite_version_loader", min_ruby: "3.0", mode: "legacy", legacy_preamble_present: true)
      )
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "uses anonymous legacy version loading only for low-floor namesake superclasses" do
    content = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "my-gem"
        spec.version = "0.1.0"
        spec.required_ruby_version = ">= 2.4"
      end
    RUBY
    facts = {
      package: {name: "my-gem"},
      project_runtime: {version: "0.1.0"},
      rubygems: {
        entrypoint_require: "my/gem",
        namespace: "My::Gem",
        min_ruby: "2.4",
        entrypoint_namespace_superclasses: {1 => "Module"}
      }
    }

    gemspec = described_class.send(:rewrite_gemspec_version_loader, content, facts: facts)

    expect(gemspec).to include('if Gem.ruby_version >= Gem::Version.new("3.1")')
    expect(gemspec).to include('require "anonymous_loader"')
    expect(gemspec).to include("anonymous_namespace = AnonymousLoader.load(files: path)")
    expect(gemspec).not_to include('elsif Gem.ruby_version >= Gem::Version.new("2.2")')
    expect(gemspec).to include("anonymous_namespace::My::Gem::Version::VERSION")
    expect(gemspec).to include("spec.version = gem_version")
  end

  it "uses a literal gemspec version below the anonymous-loader Ruby floor" do
    content = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "my-gem"
        spec.version = "0.1.0"
        spec.required_ruby_version = ">= 2.1"
      end
    RUBY
    facts = {
      package: {name: "my-gem"},
      project_runtime: {version: "0.1.0"},
      rubygems: {
        entrypoint_require: "my/gem",
        namespace: "My::Gem",
        min_ruby: "2.1",
        entrypoint_namespace_superclasses: {1 => "Module"}
      }
    }

    gemspec = described_class.send(:rewrite_gemspec_version_loader, content, facts: facts)

    expect(gemspec).to include('elsif Gem.ruby_version >= Gem::Version.new("2.2")')
    expect(gemspec).to include("else\n    \"0.1.0\"")
  end

  it "does not add a runtime Ruby check for high-floor namesake superclasses" do
    content = <<~RUBY
      gem_version =
        if Gem.ruby_version >= Gem::Version.new("3.1")
          Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/my/gem/version.rb", mod) }::My::Gem::Version::VERSION
        else
          require_relative "lib/my/gem/version"
          My::Gem::Version::VERSION
        end

      Gem::Specification.new do |spec|
        spec.name = "my-gem"
        spec.version = gem_version
        spec.required_ruby_version = ">= 3.2"
      end
    RUBY
    facts = {
      package: {name: "my-gem"},
      project_runtime: {version: "0.1.0"},
      rubygems: {
        entrypoint_require: "my/gem",
        namespace: "My::Gem",
        min_ruby: "3.2",
        entrypoint_namespace_superclasses: {1 => "Module"}
      }
    }

    gemspec = described_class.send(:rewrite_gemspec_version_loader, content, facts: facts)

    expect(gemspec).to include("spec.version = Module.new.tap")
    expect(gemspec).not_to include("gem_version =")
    expect(gemspec).not_to include('if Gem.ruby_version >= Gem::Version.new("3.1")')
  end

  it "keeps load-path gemspec legacy version loading only when minimum Ruby is below 2.2" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-pre-require-relative-version-loader-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = "0.1.0"
            gem.summary = "Pre require_relative loader"
            gem.required_ruby_version = ">= 2.1"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include("gem_version =")
      expect(gemspec_content).to include("$LOAD_PATH.unshift(lib)")
      expect(gemspec_content).to include('lib = File.expand_path("lib", File.dirname(__FILE__))')
      expect(gemspec_content).to include('require "my/gem/version"')
      expect(gemspec_content).not_to include('require_relative "lib/my/gem/version"')
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(gemspec_report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "rewrite_version_loader", min_ruby: "2.1", mode: "legacy", legacy_preamble_present: true)
      )
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps explicit zero runtime gemspec floor dependency-free for Ruby 1.x compatibility" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-gemspec-zero-runtime-floor-slice", tmp_root) do |root|
      write_tree(root, {
        "my-gem.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "my-gem"
            gem.version = "0.1.0"
            gem.summary = "Zero floor loader"
            gem.homepage = "https://github.com/acme/my-gem"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "0"
            entrypoint_require: "my/gem"
            namespace: "My::Gem"
          templates:
            root: template
            apply: true
            entries:
              - my-gem.gemspec
        YAML
        "template/my-gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_my_gem_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include("gem_version =")
      expect(gemspec_content).to include('if Gem.ruby_version >= Gem::Version.new("3.1")')
      expect(gemspec_content).to include('lib = File.expand_path("lib", File.dirname(__FILE__))')
      expect(gemspec_content).to include('require "my/gem/version"')
      expect(gemspec_content).not_to include("required_ruby_version")
      expect(gemspec_content).not_to include("version_gem")
      expect(gemspec_content).not_to include("require_relative")
      expect(gemspec_content).to include("spec.version = gem_version")
      expect(File.read(File.join(root, "my-gem.gemspec"))).to eq(gemspec_content)
    end
  end

  it "removes version_gem dependency and entrypoint references when explicitly disabled" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-remove-version-gem-runtime", tmp_root) do |root|
      write_tree(root, {
        "legacy.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "legacy"
            gem.version = "0.1.0"
            gem.summary = "Legacy gem"
            gem.homepage = "https://github.com/acme/legacy"
            gem.required_ruby_version = ">= 3.2"
            gem.add_dependency("version_gem", "~> 1.1", ">= 1.1.10")
          end
        RUBY
        "lib/legacy.rb" => <<~RUBY,
          # frozen_string_literal: true

          require "version_gem"
          require_relative "legacy/version"

          module Legacy
          end

          Legacy::Version.class_eval do
            extend VersionGem::Basic
          end
        RUBY
        "lib/legacy/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Legacy
            module Version
              VERSION = "0.1.0"
            end
            VERSION = Version::VERSION # Traditional Constant Location
          end
        RUBY
        "spec/legacy/version_spec.rb" => <<~RUBY,
          # frozen_string_literal: true

          RSpec.describe Legacy::Version do
            it_behaves_like "a Version module", described_class
          end
        RUBY
        "gemfiles/modular/runtime_heads.gemfile" => <<~RUBY,
          # frozen_string_literal: true

          # Test against HEAD of runtime dependencies so we can proactively file bugs

          # Ruby >= 2.2
          gem "version_gem", github: "ruby-oauth/version_gem", branch: "main"

          eval_gemfile("x_std_libs/vHEAD.gemfile")
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "3.2"
            version_gem_entrypoint: disabled
            entrypoint_require: "legacy"
            namespace: "Legacy"
          templates:
            root: template
            apply: true
            entries:
              - legacy.gemspec
              - gemfiles/modular/runtime_heads.gemfile
        YAML
        "template/legacy.gemspec.example" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 3.2"
            # Ref: https://gitlab.com/ruby-oauth/version_gem/-/issues/3
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
          end
        RUBY
        "template/gemfiles/modular/runtime_heads.gemfile.example" => <<~RUBY
          # frozen_string_literal: true

          # Test against HEAD of runtime dependencies so we can proactively file bugs

          # Ruby >= 2.2
          gem "version_gem", github: "ruby-oauth/version_gem", branch: "main"

          eval_gemfile("x_std_libs/vHEAD.gemfile")
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_legacy_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)
      entrypoint_content = File.read(File.join(root, "lib", "legacy.rb"))
      version_content = File.read(File.join(root, "lib", "legacy", "version.rb"))
      runtime_heads_content = File.read(File.join(root, "gemfiles", "modular", "runtime_heads.gemfile"))
      version_spec_path = File.join(root, "spec", "legacy", "version_spec.rb")

      expect(gemspec_content).not_to include("version_gem")
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 3.2"')
      expect(apply.fetch(:post_apply_steps)).to include(hash_including(
        name: "version_gem_cleanup",
        status: "applied",
        changed_files: contain_exactly("lib/legacy.rb", "spec/legacy/version_spec.rb")
      ))
      expect(entrypoint_content).not_to include("version_gem")
      expect(entrypoint_content).not_to include("VersionGem")
      expect(entrypoint_content).to include('require_relative "legacy/version"')
      expect(entrypoint_content).not_to end_with("\n\n")
      expect(version_content).to include("module Version")
      expect(version_content).to include('VERSION = "0.1.0"')
      expect(version_content).to include("VERSION = Version::VERSION # Traditional Constant Location")
      expect(File).not_to exist(version_spec_path)
      expect(runtime_heads_content).not_to include("version_gem")
      expect(runtime_heads_content).to include('eval_gemfile("x_std_libs/vHEAD.gemfile")')
      expect(File.read(File.join(root, "legacy.gemspec"))).to eq(gemspec_content)
    end
  end

  it "defaults supported Ruby projects to the packaged version_gem dependency" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-default-version-gem", tmp_root) do |root|
      write_tree(root, {
        "modern.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "modern"
            spec.version = "0.1.0"
            spec.summary = "Modern gem"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
        "lib/modern.rb" => <<~RUBY,
          # frozen_string_literal: true

          require_relative "modern/version"

          module Modern
          end
        RUBY
        "lib/modern/version.rb" => <<~RUBY,
          # frozen_string_literal: true

          module Modern
            module Version
              VERSION = "0.1.0"
            end
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "2.3"
            entrypoint_require: "modern"
            namespace: "Modern"
          templates:
            root: template
            apply: true
            entries:
              - modern.gemspec
        YAML
        "template/modern.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})

      expect(File.read(File.join(root, "modern.gemspec"))).to include('spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")')
      expect(File.read(File.join(root, "lib", "modern.rb"))).to include('require "version_gem"', "VersionGem::Basic")
      expect(apply.fetch(:post_apply_steps)).to include(hash_including(name: "version_gem_bootstrap", status: "applied"))
    end
  end

  it "does not add the RequiredRubyVersion RuboCop disable for Ruby 2+ runtime floors" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-required-ruby-version-rubocop-disable", tmp_root) do |root|
      write_tree(root, {
        "modern.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "modern"
            spec.version = "0.1.0"
            spec.summary = "Modern gem"
            spec.homepage = "https://github.com/acme/modern"
            spec.required_ruby_version = ">= 1.8.7"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          rubygems:
            min_ruby: "2.0"
          templates:
            root: template
            apply: true
            entries:
              - modern.gemspec
        YAML
        "template/modern.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.required_ruby_version = ">= 2.3.0"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find { |report| report.fetch(:recipe_name) == "template_source_application_modern_gemspec" }
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include('spec.required_ruby_version = ">= 2.0"')
      expect(gemspec_content).not_to include("Gemspec/RequiredRubyVersion")
    end
  end

  it "preserves missing runtime gemspec dependencies above the development dependency separator" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-runtime-dependency-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 4.0"
            gem.add_dependency("json", "~> 2.10")
            gem.add_development_dependency("rubocop", "~> 1.70")
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
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 4.0"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")

            # NOTE: It is preferable to list development dependencies in the gemspec due to increased
            #       visibility and discoverability.

            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)
      runtime_index = gemspec_content.index(%(spec.add_dependency("json", "~> 2.10")))
      separator_index = gemspec_content.index("# NOTE: It is preferable")
      development_index = gemspec_content.index(%(spec.add_development_dependency("rubocop", "~> 1.70")))

      expect(gemspec_content).to include(%(spec.add_dependency("json", "~> 2.10")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("rubocop", "~> 1.70")))
      expect(runtime_index).to be < separator_index
      expect(development_index).to be > separator_index
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps the greater version requirement for template-managed gemspec dependencies" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-template-managed-dependencies", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 3.2"
            gem.add_dependency("json", "~> 2.10")
            gem.add_development_dependency("kettle-dev", "~> 2.0")
            gem.add_development_dependency("rake", "~> 13.1")
            gem.add_development_dependency("custom-dev", ">= 1")
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
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")

            # NOTE: It is preferable to list development dependencies in the gemspec due to increased
            #       visibility and discoverability.

            spec.add_development_dependency("kettle-dev", "~> 2.5", ">= 2.5.10")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content).to include(%(spec.add_dependency("json", "~> 2.10")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("custom-dev", ">= 1")))
      expect_gemspec_dependency_declared(gemspec_content, "kettle-dev", kind: :add_development_dependency)
      expect(gemspec_content).to include(%(spec.add_development_dependency("rake", "~> 13.1")))
      expect(gemspec_content).not_to include(%(spec.add_development_dependency("kettle-dev", "~> 2.0")\n))
      expect(gemspec_content).not_to include(%(spec.add_development_dependency("rake", "~> 13.0")))
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "does not duplicate runtime gemspec dependencies as development dependencies" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-runtime-dev-dedup-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 2.4"
            gem.add_dependency("kettle-test", "~> 2.0", ">= 2.0.11")
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
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 2.4"
            spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")

            # NOTE: It is preferable to list development dependencies in the gemspec due to increased
            #       visibility and discoverability.

            spec.add_development_dependency("kettle-test", "~> 2.0", ">= 2.0.11")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)

      expect(gemspec_content.scan('add_dependency("kettle-test"').size).to eq(1)
      expect(gemspec_content).not_to include(%(add_development_dependency("kettle-test")))
      expect(gemspec_content).to include(%(spec.add_development_dependency("rake", "~> 13.0")))
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "keeps old runtime dependency customizations above the development dependency note block" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "1.0.0"
        spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.9")              # ruby >= 2.2.0

        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.

        # Dev, Test, & Release Tasks
        spec.add_development_dependency("kettle-dev", "~> 2.5", ">= 2.5.10")     # ruby >= 2.4.0

        # Security
        spec.add_development_dependency("bundler-audit", "~> 0.9.3")             # ruby >= 2.0.0
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |gem|
        gem.name = "demo"
        gem.version = "1.0.0"
        gem.add_dependency("version_gem", "~> 1.1", ">= 1.1.9")              # ruby >= 2.2.0
        # Dev tooling (runtime dep -- kettle-jem extends kettle-dev's functionality)
        gem.add_dependency("kettle-dev", "~> 2.2", ">= 2.2.10")          # ruby >= 2.4.0

        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.

        # Security
        gem.add_development_dependency("bundler-audit", "~> 0.9.3")             # ruby >= 2.0.0
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})

    expect { RubyVM::InstructionSequence.compile(merged) }.not_to raise_error
    expect_gemspec_dependency_declared(merged, "kettle-dev", kind: :add_dependency)
    expect(merged).not_to include('spec.add_development_dependency("kettle-dev"')
    expect(merged).to include("#       visibility and discoverability.\n\n  # Security")
    expect(merged).not_to include("#       visibility and discoverability.\n\n\n  # Security")

    runtime_index = merged.index('spec.add_dependency("kettle-dev"')
    note_index = merged.index("# NOTE: It is preferable to list development dependencies in the gemspec due to increased")
    bundler_audit_index = merged.index('spec.add_development_dependency("bundler-audit", "~> 0.9.3")')

    expect(runtime_index).to be < note_index
    expect(note_index).to be < bundler_audit_index
  end

  it "removes direct rdoc development dependencies because Yard owns documentation dependencies" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.add_development_dependency("yard", "~> 0.9")
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |gem|
        gem.name = "demo"
        gem.add_development_dependency("yard", "~> 0.9")
        gem.add_development_dependency("rdoc", ">= 3")
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})

    expect(merged).to include('spec.add_development_dependency("yard", "~> 0.9")')
    expect(merged).not_to include('add_development_dependency("rdoc"')
  end

  it "does not accumulate duplicate blank section separators across repeated gemspec merges" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "1.0.0"
        spec.required_ruby_version = ">= 3.2.0"
        spec.metadata["rubygems_mfa_required"] = "true"

        # Specify which files are part of the released package.
        spec.files = Dir[
          "lib/**/*.rb",
        ]
        spec.require_paths = ["lib"]

        # Utilities
        spec.add_dependency("version_gem", "~> 1.1")

        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.

        # Dev, Test, & Release Tasks
        spec.add_development_dependency("kettle-dev", "~> 2.5", ">= 2.5.10")

        # Security
        spec.add_development_dependency("bundler-audit", "~> 0.9.3")

        # Tasks
        spec.add_development_dependency("rake", "~> 13.0")
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "1.0.0"
        spec.required_ruby_version = ">= 3.2.0"
        spec.metadata["allowed_push_host"] = "https://rubygems.org"
        spec.metadata["rubygems_mfa_required"] = "true"

        # Specify which files should be added to the gem when it is released.
        gemspec = File.basename(__FILE__)
        spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
          ls.readlines("\\x0", chomp: true)
        end
        spec.require_paths = ["lib"]

        # Utilities
        spec.add_dependency("version_gem", "~> 1.1")

        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.

        # Dev, Test, & Release Tasks
        spec.add_development_dependency("kettle-dev", "~> 2.0")

        # Security
        spec.add_development_dependency("bundler-audit", "~> 0.9.3")

        # Tasks
        spec.add_development_dependency("rake", "~> 13.0")
      end
    RUBY
    facts = {package: {name: "demo"}}

    once = described_class.merge_gemspec_template_source(template, destination, facts: facts)
    twice = described_class.merge_gemspec_template_source(template, once, facts: facts)

    expect { RubyVM::InstructionSequence.compile(once) }.not_to raise_error
    expect(once).to include("spec.metadata[\"rubygems_mfa_required\"] = \"true\"\n  spec.metadata[\"allowed_push_host\"] = \"https://rubygems.org\"\n\n  # Specify which files")
    expect(once).not_to include("spec.metadata[\"allowed_push_host\"] = \"https://rubygems.org\"\n\n\n  # Specify which files")
    expect(once).to include("spec.require_paths = [\"lib\"]\n\n  # Utilities")
    expect(once).not_to include("spec.require_paths = [\"lib\"]\n\n\n  # Utilities")
    expect_gemspec_dependency_declared(once, "kettle-dev", kind: :add_development_dependency)
    expect(once).to match(/spec\.add_development_dependency\("kettle-dev".*\n\n  # Security/)
    expect(once).not_to match(/spec\.add_development_dependency\("kettle-dev".*\n\n\n  # Security/)
    expect(once).to include("spec.add_development_dependency(\"bundler-audit\", \"~> 0.9.3\")\n\n  # Tasks")
    expect(once).not_to include("spec.add_development_dependency(\"bundler-audit\", \"~> 0.9.3\")\n\n\n  # Tasks")
    expect(twice).to eq(once)
  end

  it "preserves destination-only gemspec metadata while allowing template metadata to win" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.homepage = "https://example.test/demo"
        spec.metadata["rubygems_mfa_required"] = "true"
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.homepage = "https://example.test/demo"
        spec.metadata["rubygems_mfa_required"] = "false"
        spec.metadata["default_lint_roller_plugin"] = "RuboCop::Lts::Ruby::Plugin"
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})
    remerged = described_class.merge_gemspec_template_source(template, merged, facts: {package: {name: "demo"}})

    expect(merged).to include('spec.metadata["rubygems_mfa_required"] = "true"')
    expect(merged).to include('spec.metadata["default_lint_roller_plugin"] = "RuboCop::Lts::Ruby::Plugin"')
    expect(remerged).to eq(merged)
  end

  it "drops untouched Bundler gemspec metadata defaults without dropping real metadata" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.homepage = "https://example.test/demo"
        spec.metadata["rubygems_mfa_required"] = "true"
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.homepage = "https://example.test/demo"
        spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"
        spec.metadata["rubygems_mfa_required"] = "false"
        spec.metadata["default_lint_roller_plugin"] = "RuboCop::Lts::Ruby::Plugin"
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})
    remerged = described_class.merge_gemspec_template_source(template, merged, facts: {package: {name: "demo"}})

    expect(merged).not_to include("TODO: Set to your gem server")
    expect(merged).to include('spec.metadata["rubygems_mfa_required"] = "true"')
    expect(merged).to include('spec.metadata["default_lint_roller_plugin"] = "RuboCop::Lts::Ruby::Plugin"')
    expect(remerged).to eq(merged)
  end

  it "replaces executable destination gemspec files assignments with template package collections" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "1.0.0"

        # Specify which files are part of the released package.
        spec.files = Dir[
          "lib/**/*.rb",
          "sig/**/*.rbs",
        ]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "1.0.0"

        # Specify which files should be added to the gem when it is released.
        # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
        gemspec = File.basename(__FILE__)
        spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
          ls.readlines("\\x0", chomp: true).reject do |f|
            (f == gemspec) ||
              f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
          end
        end
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})

    expect { RubyVM::InstructionSequence.compile(merged) }.not_to raise_error
    expect(merged).to include("# Specify which files are part of the released package.")
    expect(merged).to include("spec.files = Dir[")
    expect(merged).to include('"lib/**/*.rb"')
    expect(merged).to include('"sig/**/*.rbs"')
    expect(merged).not_to include("IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL)")
  end

  it "replaces legacy backtick git-ls-files pipelines with the canonical package manifest" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.files = Dir["lib/**/*.rb"]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.files = `git ls-files -z`.split("\\x0").reject do |file|
          file.match?(%r{^(test|spec|features)/})
        end
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})

    expect(merged).to include('spec.files = Dir["lib/**/*.rb"]')
    expect(merged).not_to include("git ls-files")
  end

  it "replaces a legacy git-ls-files pipeline scoped by Dir.chdir" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.files = Dir["lib/**/*.rb"]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.files = Dir.chdir(File.expand_path(__dir__)) do
          `git ls-files -z`.split("\\x0").reject { |file| file.match?(%r{^(test|spec|features)/}) }
        end
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})

    expect(merged).to include('spec.files = Dir["lib/**/*.rb"]')
    expect(merged).not_to include("Dir.chdir")
    expect(merged).not_to include("git ls-files")
  end

  it "replaces legacy newline-split git-ls-files assignments with the canonical package manifest" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.files = Dir["lib/**/*.rb"]
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.files = `git ls-files`.split($\\)
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "demo"}})

    expect(merged).to include('spec.files = Dir["lib/**/*.rb"]')
    expect(merged).not_to include("git ls-files")
  end

  it "replaces every byebug-named Gemfile dependency with debug" do
    source = <<~RUBY
      group :test do
        gem "byebug", require: false
        gem "pry-byebug", require: false
      end
    RUBY

    migrated = described_class.send(:migrate_legacy_byebug_pair, source)

    expect(migrated).to include('gem "debug", require: false')
    expect(migrated).not_to include("byebug")
  end

  it "replaces legacy byebug requires in spec helpers with debug" do
    source = <<~RUBY
      require "byebug"
      require "pry-byebug"
      require "rspec"
    RUBY

    migrated = described_class.send(:migrate_legacy_byebug_requires, source)

    expect(migrated).to include('require "debug" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7") && ENV["CI"].nil? && ENV.fetch("DEBUG", "false").casecmp("true").zero?')
    expect(migrated).to include('require "rspec"')
    expect(migrated).not_to include("byebug")
    expect(migrated.scan('require "debug"').length).to eq(1)
  end

  it "guards existing direct debug requires for legacy Ruby appraisals" do
    source = <<~RUBY
      require "debug"
      require "debug" if load_debugger
    RUBY

    migrated = described_class.send(:migrate_legacy_byebug_requires, source)

    expect(migrated).to include('require "debug" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.7") && ENV["CI"].nil? && ENV.fetch("DEBUG", "false").casecmp("true").zero?')
    expect(migrated).to include('require "debug" if load_debugger')
  end

  it "replaces byebug-family dependencies in each appraisal independently" do
    source = <<~RUBY
      appraise "ruby_2_4" do
        gem "byebug", "9.0.6"
        gem "pry-byebug", "3.4.3"
      end

      appraise "ruby_3_2" do
        gem "byebug"
        gem "pry-byebug"
      end
    RUBY

    migrated = described_class.send(:migrate_legacy_byebug_appraisal_dependencies, source)

    expect(migrated).not_to include("byebug")
    expect(migrated.scan('gem "debug", require: false').length).to eq(2)
  end

  it "removes preserved duplicate gemspec dependency declarations" do
    source = <<~RUBY
      Gem::Specification.new do |spec|
        spec.add_development_dependency "kettle-test", "~> 2.0", ">= 2.0.18"
        spec.add_development_dependency "kettle-test"
      end
    RUBY

    migrated = described_class.send(:remove_duplicate_gemspec_dependency_lines, source, receiver: "spec")

    expect(migrated.scan("kettle-test").length).to eq(1)
    expect(migrated).to include('">= 2.0.18"')
  end

  it "preserves an existing main Gemfile source while applying the template" do
    recipe = {target_path: "Gemfile", template_preference: {strategy: "merge"}}
    template = "source \"https://gem.coop\"\ngemspec\n"
    destination = "source \"https://rubygems.org\"\ngemspec\n"

    merged = described_class.send(
      :finalize_gemfile_template_source,
      recipe,
      template,
      destination,
      facts: {},
      template_content: template
    )

    expect(merged).to start_with("source \"https://rubygems.org\"\n")
    expect(merged).not_to include("source \"https://gem.coop\"")
  end

  it "uses the template main Gemfile source when the configured strategy accepts the template" do
    recipe = {target_path: "Gemfile", template_preference: {strategy: "accept_template"}}
    template = "source \"https://gem.coop\"\ngemspec\n"
    destination = "source \"https://rubygems.org\"\ngemspec\n"

    merged = described_class.send(
      :finalize_gemfile_template_source,
      recipe,
      template,
      destination,
      facts: {},
      template_content: template
    )

    expect(merged).to start_with("source \"https://gem.coop\"\n")
    expect(merged).not_to include("source \"https://rubygems.org\"")
  end

  it "preserves the body of an accepted local modular Gemfile while removing rdoc" do
    recipe = {
      target_path: "gemfiles/modular/style_local.gemfile",
      template_preference: {strategy: "accept_template"}
    }
    template = <<~RUBY
      require "nomono/bundler"

      gem "rdoc"
      local_gems = %w[example]
      platform :mri do
        eval_nomono_gems(gems: local_gems)
      end
    RUBY

    finalized = described_class.send(
      :finalize_gemfile_template_source,
      recipe,
      template,
      "",
      facts: {package: {name: "other"}},
      template_content: template
    )

    expect(finalized).to include("local_gems = %w[example]")
    expect(finalized).to include("eval_nomono_gems(gems: local_gems)")
    expect(finalized).not_to include('gem "rdoc"')
  end

  it "repairs the rspec-pending_for generated package manifest merge shape" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "rspec-pending_for"
        spec.version = "1.0.0"

        gemspec_root = __dir__
        relative_package_path = lambda do |path|
          prefix = "\#{gemspec_root}/"
          path[0, prefix.length] == prefix ? path[prefix.length..-1] : path
        end
        enumerate_package_glob = lambda do |glob|
          files = []
          Dir.glob(glob, File::FNM_DOTMATCH).each do |path|
            next unless File.file?(path) && ![".", ".."].include?(File.basename(path))

            files << relative_package_path.call(path)
          end
          files
        end
        enumerate_package_files = lambda do |root|
          enumerate_package_glob.call(File.join(gemspec_root, root, "**", "*"))
        end
        package_metadata_files = %w[
          CHANGELOG.md
          LICENSE.md
          README.md
          sig/rspec/pending_for.rbs
        ].select { |path| File.exist?(File.join(gemspec_root, path)) }

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
        spec.name = "rspec-pending_for"
        spec.version = "1.0.0"

        gemspec_root = __dir__
        relative_package_path = lambda do |path|
          prefix = "\#{gemspec_root}/"
          (path[0, prefix.length] == prefix) ? path[prefix.length..-1] : path
        end
        enumerate_package_glob = lambda do |glob|
          enumerate_package_glob.call(File.join(gemspec_root, root, "**", "*"))
        end
        package_metadata_files = [
          "CHANGELOG.md",
          "LICENSE.md",
          "README.md",
          "sig/rspec/pending_for.rbs"
        ].select { |path| File.exist?(File.join(gemspec_root, path)) }

        # Specify which files are part of the released package.
        spec.files = Dir[
          # Executables and tasks
          "exe/*",
          "lib/**/*.rb",
          "lib/**/*.rake",
          # Signatures
          "sig/**/*.rbs"
      ] + [
        # Root package metadata
        *package_metadata_files,

        # Code / tasks / data (NOTE: exe/ is specified via spec.bindir and spec.executables below)
        *enumerate_package_files.call("lib"),
        # Executables and executable support scripts
        *enumerate_package_files.call("exe")
      ]
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "rspec-pending_for"}})

    expect { RubyVM::InstructionSequence.compile(merged) }.not_to raise_error
    expect(merged).to include("spec.files = [")
    expect(merged).not_to include("spec.files = Dir[")
    expect(merged).not_to include("] + [")
    expect(merged).not_to include("enumerate_package_glob = lambda do |glob|\n    enumerate_package_glob.call")
    expect(merged.scan("spec.files =").size).to eq(1)
    expect(merged.scan('*enumerate_package_files.call("lib")').size).to eq(1)
    expect(merged.scan('*enumerate_package_files.call("exe")').size).to eq(1)
  end

  it "normalizes destination gemspec receiver names while preserving destination-only fields" do
    template = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "example"
        spec.version = "1.0.0"
        spec.summary = "Template summary"
        spec.add_dependency("foo", "~> 1.0")
      end
    RUBY
    destination = <<~RUBY
      Gem::Specification.new do |gem|
        gem.name = "example"
        gem.version = "2.0.0"
        gem.summary = "Destination summary"
        gem.authors = ["Someone"]
      end
    RUBY

    merged = described_class.merge_gemspec_template_source(template, destination, facts: {package: {name: "example"}})

    expect { RubyVM::InstructionSequence.compile(merged) }.not_to raise_error
    expect(merged).not_to match(/\bgem\./)
    expect(merged).to include('spec.summary = "Destination summary"')
    expect(merged).to include('spec.authors = ["Someone"]')
    expect(merged).to include('spec.add_dependency("foo", "~> 1.0")')
  end

  it "preserves zero-byte template outputs" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-zero-byte-template-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - REEK
        YAML
        "template/REEK" => "",
        "REEK" => ""
      })

      apply = described_class.apply_project(root, env: {})
      reek_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:relative_path) == "REEK"
      end

      expect(reek_report.fetch(:final_content)).to eq("")
      expect(File.binread(File.join(root, "REEK"))).to eq("")
    end
  end

  it "sorts runtime gemspec dependencies with RuboCop-compatible gem name ordering" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-rubocop-order-slice", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.summary = "Real summary"
            gem.required_ruby_version = ">= 4.0"
            gem.add_dependency("rspec", "~> 3.0")
            gem.add_dependency("rspec-block_is_expected", "~> 1.0")
            gem.add_dependency("rspec-pending_for", "~> 0.1")
            gem.add_dependency("rspec-stubbed_env", "~> 1.0", ">= 1.0.5")
            gem.add_dependency("rspec_junit_formatter", "~> 0.6")
            gem.add_dependency("silent_stream", "~> 1.0")
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
            spec.summary = "TODO: Write a short summary"
            spec.required_ruby_version = ">= 4.0"
            spec.add_dependency("rspec", "~> 3.0")
            spec.add_dependency("rspec-block_is_expected", "~> 1.0")
            spec.add_dependency("rspec-pending_for", "~> 0.1")
            spec.add_dependency("rspec-stubbed_env", "~> 1.0")
            spec.add_dependency("rspec_junit_formatter", "~> 0.6")
            spec.add_dependency("silent_stream", "~> 1.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {})
      gemspec_report = apply.fetch(:recipe_reports).find do |report|
        report.fetch(:recipe_name) == "template_source_application_example_gemspec"
      end
      gemspec_content = gemspec_report.fetch(:final_content)
      junit_index = gemspec_content.index(%(spec.add_dependency("rspec_junit_formatter", "~> 0.6")))
      pending_index = gemspec_content.index(%(spec.add_dependency("rspec-pending_for", "~> 0.1")))
      stubbed_index = gemspec_content.index(%(spec.add_dependency("rspec-stubbed_env", "~> 1.0", ">= 1.0.6")))

      expect(junit_index).to be < pending_index
      expect(pending_index).to be < stubbed_index
      expect(gemspec_content).not_to include(%(rspec-stubbed_env", "~> 1.0", ">= 1.0.5"))
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "ports old gemspec emoji field replacement without duplicating the Gem::Specification block" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:gemspec_emoji_block_integrity)
    package_name = contract_case.fetch(:package_name)

    Dir.mktmpdir("kettle-jem-old-gemspec-emoji-policy", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          # coding: utf-8
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.version = "2.0.0"
            spec.authors = ["Kettle Maintainer"]
            spec.email = ["maintainer@example.com"]
            spec.summary = "#{contract_case.fetch(:summary)}"
            spec.description = "#{contract_case.fetch(:description)}"
            spec.homepage = "https://github.com/structuredmerge/#{package_name}"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 4.0"
            spec.require_paths = ["lib"]
            spec.bindir = "exe"
            spec.executables = ["#{contract_case.fetch(:executable)}"]
            spec.add_development_dependency("gitmoji-regex", "~> 2.0", ">= 2.0.4")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "1.0.0"
            spec.authors = ["Template Author"]
            spec.email = ["template@example.com"]
            spec.summary = "🍲 "
            spec.description = "🍲 "
            spec.homepage = "https://github.com/structuredmerge/{KJ|GEM_NAME}"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 2.3.0"
            spec.require_paths = ["lib"]
            spec.bindir = "exe"
            spec.executables = []
            spec.add_development_dependency("{KJ|GEM_NAME}", "~> 1.0")
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "#{package_name}.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content.scan(/Gem::Specification\.new\s+do/).count).to eq(1)
      expect(gemspec_content.scan(/^\s*spec\.name\s*=/).count).to eq(1)
      expect(gemspec_content).not_to match(/^spec\./)
      expect(gemspec_content).to include(contract_case.fetch(:summary))
      expect(gemspec_content).to include(contract_case.fetch(:description))
      expect(gemspec_content).to include(%(spec.executables = ["#{contract_case.fetch(:executable)}"]))
      expect_gemspec_dependency_declared(gemspec_content, "gitmoji-regex", kind: :add_development_dependency)
      expect(gemspec_content).not_to include("# Hence.")
      expect(gemspec_content).not_to include("add_development_dependency(\"#{package_name}\"")
      expect(File.read(File.join(root, "#{package_name}.gemspec"))).to eq(gemspec_content)
    end
  end

  it "preserves multiline heredoc gemspec assignments as whole fields" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)

    Dir.mktmpdir("kettle-jem-gemspec-heredoc-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          Gem::Specification.new do |gem|
            gem.name = "example"
            gem.version = "1.0.0"
            gem.summary = "Existing summary"
            gem.description = <<-DESC
          First line
          Second line
            DESC
            gem.homepage = "https://github.com/acme/example"
            gem.licenses = ["MIT"]
            gem.required_ruby_version = ">= 2.3"
            gem.add_development_dependency("test-unit", ">= 3")
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🧪"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: example.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "0.0.0"
            spec.summary = "Template summary"
            spec.description = "Template description"
            spec.homepage = "https://github.com/acme/{KJ|GEM_NAME}"
            spec.licenses = ["MIT"]
            spec.required_ruby_version = ">= 2.3"
            spec.add_development_dependency("rake", "~> 13.0")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "example.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include("spec.description = <<-DESC")
      expect(gemspec_content).not_to include("spec.description = 🧪")
      expect(gemspec_content).to include("First line")
      expect(gemspec_content).to include("Second line")
      expect(gemspec_content).to include("  DESC")
      expect(gemspec_content).to include('spec.homepage = "https://github.com/acme/example"')
      expect_gemspec_dependency_declared(gemspec_content, "test-unit", kind: :add_development_dependency)
      expect(gemspec_content).not_to match(/^spec\./)
    end
  end

  it "ports old gemspec freeze block location preservation" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:freeze_block_location)
    package_name = contract_case.fetch(:package_name)

    Dir.mktmpdir("kettle-jem-old-gemspec-freeze-block-policy", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.version = gem_version
            spec.summary = "Freeze gem"
            spec.bindir = "exe"

            #{contract_case.fetch(:open_marker)}
            # Custom dependencies
            # spec.add_dependency("#{contract_case.fetch(:custom_dependency)}")
            #{contract_case.fetch(:close_marker)}

            spec.require_paths = ["lib"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "2.0.0"
            spec.summary = "Template summary"
            spec.bindir = "exe"
            spec.executables = []
            spec.require_paths = ["lib"]
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "#{package_name}.gemspec" }
      gemspec_content = report.fetch(:final_content)
      lines = gemspec_content.lines
      gemspec_line = lines.find_index { |line| line.include?("Gem::Specification.new") }
      freeze_line = lines.find_index { |line| line.include?(contract_case.fetch(:open_marker)) }
      close_line = lines.find_index { |line| line.include?(contract_case.fetch(:close_marker)) }
      block_end_line = lines.each_index.to_a.reverse.find { |index| lines[index].strip == "end" }

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(freeze_line).to be > gemspec_line
      expect(close_line).to be > freeze_line
      expect(close_line).to be < block_end_line
      expect(gemspec_content).to include(%(# spec.add_dependency("#{contract_case.fetch(:custom_dependency)}")))
      expect(gemspec_content).not_to include("To retain during kettle-jem templating")
      expect(File.read(File.join(root, "#{package_name}.gemspec"))).to eq(gemspec_content)
    end
  end

  it "preserves gemspec freeze blocks with configured custom freeze tokens" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-custom-gemspec-freeze-block-policy", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = "1.0.0"
            spec.summary = "Freeze gem"

            # custom-freeze:freeze
            # Custom dependencies
            # spec.add_dependency("custom_dep")
            # custom-freeze:unfreeze

            spec.require_paths = ["lib"]
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          defaults:
            freeze_token: custom-freeze
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: example.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.version = "2.0.0"
            spec.summary = "Template summary"
            spec.require_paths = ["lib"]
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "example.gemspec" }
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include("# custom-freeze:freeze")
      expect(gemspec_content).to include('# spec.add_dependency("custom_dep")')
      expect(gemspec_content).to include("# custom-freeze:unfreeze")
      expect(gemspec_content).not_to include("# kettle-jem:freeze")
      expect(File.read(File.join(root, "example.gemspec"))).to eq(gemspec_content)
    end
  end

  it "ports old gemspec self-dependency removal while preserving project fields" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    contract_case = old_spec_contract.fetch(:cases).fetch(:gemspec_self_dependency)
    package_name = contract_case.fetch(:package_name)

    Dir.mktmpdir("kettle-jem-old-gemspec-policy", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.summary = "Destination summary"
            spec.description = "🧪 Destination description"
            spec.homepage = "https://github.com/acme/#{package_name}"
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🧬"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "Template summary"
            spec.description = "Template description"
            spec.homepage = "https://template.example"
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency("{KJ|GEM_NAME}", "~> 1.0")
            spec.add_dependency '{KJ|GEM_NAME}'
            spec.add_development_dependency("{KJ|GEM_NAME}")
            spec.add_development_dependency '{KJ|GEM_NAME}', ">= 0"
            spec.add_dependency("#{contract_case.fetch(:preserved_dependency)}", ">= 2.8", "< 3")
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "#{package_name}.gemspec"
      end
      gemspec_content = report.fetch(:final_content)

      expect(gemspec_content).to include(%(spec.name = "#{package_name}"))
      expect(gemspec_content).to include('spec.summary = "🧬 Destination summary"')
      expect(gemspec_content).to include('spec.description = "🧬 Destination description"')
      expect(gemspec_content).to include(%(spec.homepage = "https://github.com/acme/#{package_name}"))
      expect(gemspec_content).to include('spec.required_ruby_version = ">= 4.0"')
      expect(gemspec_content).to include(%(spec.add_dependency("#{contract_case.fetch(:preserved_dependency)}", ">= 2.8", "< 3")))
      expect(gemspec_content).not_to match(
        /add_(?:development_)?dependency\s*\(?\s*["']#{Regexp.escape(contract_case.fetch(:removed_dependency))}["']/
      )
      expect(report.dig(:report_envelope, :report, :step_reports, 0, :metadata, :ruby_template_policy, :operations)).to include(
        include(operation: "delete_self_dependency_declarations", deleted_dependency_count: 4)
      )
    end
  end

  it "keeps multiline gemspec descriptions valid when adding the project emoji" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    package_name = "oauth2-mcp"

    Dir.mktmpdir("kettle-jem-gemspec-emoji", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.summary = "OAuth 2.1 resource-server helpers for MCP servers."
            spec.description = "oauth2-mcp provides Ruby helpers for securing HTTP Model Context Protocol servers " \\
                               "with OAuth protected-resource metadata, bearer challenges, and scoped authorization."
            spec.homepage = "https://github.com/ruby-oauth/oauth2-mcp"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "🔮"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "{KJ|PROJECT_EMOJI} "
            spec.description = "{KJ|PROJECT_EMOJI} "
            spec.homepage = "https://template.example"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "#{package_name}.gemspec"
      end
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include('spec.summary = "🔮 OAuth 2.1 resource-server helpers for MCP servers."')
      expect(gemspec_content).to include('spec.description = "🔮 oauth2-mcp provides Ruby helpers')
      expect(gemspec_content).not_to include("spec.description = 🔮")
    end
  end

  it "keeps squiggly heredoc gemspec descriptions valid when adding the project emoji" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    package_name = "sanitize_email"

    Dir.mktmpdir("kettle-jem-gemspec-emoji-squiggly-heredoc", tmp_root) do |root|
      write_tree(root, {
        "#{package_name}.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "#{package_name}"
            spec.summary = "Email Condom for your Ruby Server"
            spec.description = <<~DESCRIPTION.strip
                Email Condom for your Ruby Server.
              In Rails, Sinatra, et al.
            DESCRIPTION
            spec.homepage = "https://github.com/pboling/sanitize_email"
            spec.required_ruby_version = ">= 2.3"
            spec.add_dependency(<<~GEM.strip, <<~REQ.strip)
              rake
            GEM
              ~> 13.0
            REQ
          end
        RUBY
        ".kettle-jem.yml" => <<~YAML,
          project_emoji: "📧"
          templates:
            root: template
            apply: true
            entries:
              - source: gem.gemspec
                target: #{package_name}.gemspec
        YAML
        "template/gem.gemspec.example" => <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "{KJ|GEM_NAME}"
            spec.summary = "{KJ|PROJECT_EMOJI} "
            spec.description = "{KJ|PROJECT_EMOJI} "
            spec.homepage = "https://template.example"
            spec.required_ruby_version = ">= 2.3"
          end
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      report = apply.fetch(:recipe_reports).find do |candidate|
        candidate.fetch(:relative_path) == "#{package_name}.gemspec"
      end
      gemspec_content = report.fetch(:final_content)

      expect { RubyVM::InstructionSequence.compile(gemspec_content) }.not_to raise_error
      expect(gemspec_content).to include("spec.description = <<~DESCRIPTION.strip")
      expect(gemspec_content).to include("Email Condom for your Ruby Server.")
      expect(gemspec_content).to include("DESCRIPTION")
      expect(gemspec_content).to include("spec.add_dependency(<<~GEM.strip, <<~REQ.strip)")
      expect(gemspec_content).to include("rake")
      expect(gemspec_content).to include("REQ")
      expect(gemspec_content).not_to include("spec.description = 📧")
    end
  end
end
