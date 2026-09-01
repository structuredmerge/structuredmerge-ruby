# frozen_string_literal: true

require "pathname"
require "rbs"

RSpec.describe Kettle::Jem do
  include_context "with isolated kettle-jem environment"

  it "preserves class-shaped nested version namespaces" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-namespace-kind", tmp_root) do |root|
      write_file(root, "lib/simple_column/scopes/version.rb", <<~RUBY)
        module SimpleColumn
          class Scopes < Module
            module Version
              VERSION = "0.1.1"
            end
          end
        end
      RUBY

      kinds = described_class.send(
        :existing_version_namespace_kinds,
        root,
        "lib/simple_column/scopes/version.rb",
        "SimpleColumn::Scopes"
      )

      expect(
        described_class.send(:existing_version_namespace, root, "lib/simple_column/scopes/version.rb")
      ).to eq("SimpleColumn::Scopes")

      expect(kinds).to eq(0 => :module, 1 => :class)
      rendered = described_class.send(
        :version_gem_version_file_content,
        existing_version: "0.1.1",
        namespace: "SimpleColumn::Scopes",
        version: "0.1.1",
        namespace_kinds: kinds
      )
      expect(rendered).to include("class Scopes")
      expect(rendered).not_to include("class Scopes < Module")
      expect(rendered).not_to include("module Scopes")
    end
  end

  it "renders class-shaped version files and signatures from discovered facts" do
    facts = {
      rubygems: {
        namespace: "ActiveSupport::Logger",
        version_namespace_kinds: {0 => :module, 1 => :class}
      },
      project_runtime: {version: "3.0.1"}
    }

    tokens = described_class.send(:version_gem_template_tokens, facts)

    expect(tokens.fetch("KJ|VERSION_GEM:VERSION_RB")).to include("class Logger")
    expect(tokens.fetch("KJ|VERSION_GEM:VERSION_RB")).not_to include("module Logger")
    expect(tokens.fetch("KJ|VERSION_GEM:VERSION_RBS")).to include("class Logger")
    expect(tokens.fetch("KJ|VERSION_GEM:VERSION_RBS")).not_to include("module Logger")
  end

  it "preserves a nested class namespace when a package wrapper is the public entrypoint" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-package-wrapper-class-namespace", tmp_root) do |root|
      write_file(root, "activesupport-broadcast_logger.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "activesupport-broadcast_logger"
          spec.version = "3.0.1"
          spec.summary = "Broadcast logger"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, "lib/activesupport-broadcast_logger.rb", <<~RUBY)
        require_relative "activesupport/broadcast_logger"
        require_relative "activesupport/broadcast_logger/version"

        ActiveSupport::BroadcastLogger::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "lib/activesupport/broadcast_logger.rb", <<~RUBY)
        module ActiveSupport
          class BroadcastLogger
          end
        end
      RUBY
      write_file(root, "lib/activesupport/broadcast_logger/version.rb", <<~RUBY)
        module ActiveSupport
          class BroadcastLogger
            module Version
              VERSION = "3.0.1"
            end
          end
        end
      RUBY

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      version = File.read(File.join(root, "lib/activesupport/broadcast_logger/version.rb"))
      signature = File.read(File.join(root, "sig/activesupport/broadcast_logger.rbs"))
      expect(version).to include("class BroadcastLogger")
      expect(version).not_to include("module BroadcastLogger")
      expect(signature).to include("class BroadcastLogger")
      expect(signature).not_to include("module BroadcastLogger")
    end
  end

  it "includes the version namespace policy in managed version fingerprints" do
    report = {
      relative_path: "lib/demo/widget/version.rb",
      recipe_name: "template_source_application_lib_demo_widget_version_rb",
      request_envelope: {
        request: {
          recipe_name: "supplied_template_source_application",
          recipe_version: "1"
        }
      },
      metadata: {
        template_source_preference: {
          source_root_path: "/templates",
          source_relative_path: "lib/gem/version.rb"
        }
      }
    }

    payload = described_class.template_input_fingerprint_payload(Dir.pwd, report)

    expect(payload).to include(
      version_namespace_template_policy_fingerprint_version: described_class::VERSION_NAMESPACE_TEMPLATE_POLICY_FINGERPRINT_VERSION
    )
  end

  def write_file(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it "removes an empty trailing gemspec development dependency section without leaving its separator" do
    content = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "demo-gem"

        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.

        # Testing
        spec.add_development_dependency("kettle-test", "~> 2.0", ">= 2.0.11")

        # HTTP recording for deterministic specs
        # In Ruby 3.5 (HEAD) the CGI library has been pared down, so we also need to depend on gem "cgi" for ruby@head
        # This is done in the "head" appraisal.
        # See: https://github.com/vcr/vcr/issues/1057
      end
    RUBY

    cleaned = described_class.remove_empty_gemspec_development_dependency_section_headings(content, receiver: "spec")

    expect(cleaned).to eq(<<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "demo-gem"

        # NOTE: It is preferable to list development dependencies in the gemspec due to increased
        #       visibility and discoverability.

        # Testing
        spec.add_development_dependency("kettle-test", "~> 2.0", ">= 2.0.11")
      end
    RUBY
  end

  it "repairs the version_gem entrypoint shape during template apply" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-bootstrap", tmp_root) do |root|
      write_file(root, "plain-merge.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "plain-merge"
          spec.version = "7.0.0"
          spec.summary = "Plain merge"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, "lib/plain/merge.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"

        module Plain
          module Merge
          end
        end

        Plain::Merge::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "sig/plain/merge.rbs", <<~RBS)
        module Plain
          module Merge
            VERSION: String
          end
        end
      RBS

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("lib/plain/merge.rb", "lib/plain/merge/version.rb", "sig/plain/merge.rbs")
        )
      )
      entrypoint = File.read(File.join(root, "lib/plain/merge.rb"))
      expect(entrypoint).to include(<<~RUBY)
        require "version_gem"
        require_relative "merge/version"
      RUBY
      expect(entrypoint.index('require_relative "merge/version"')).to be < entrypoint.index("Plain::Merge::Version.class_eval do")
      expect(File.read(File.join(root, "lib/plain/merge/version.rb"))).to include('VERSION = "7.0.0"')
      expect(File).not_to exist(File.join(root, "sig/plain/merge/version.rbs"))
      signature = File.read(File.join(root, "sig/plain/merge.rbs"))
      expect(signature).to include("module Plain")
      expect(signature).to include("module Merge")
      expect(signature).to include("module Version")
      expect(signature.scan("VERSION: String").length).to eq(2)
    end
  end

  it "preserves a legacy flat entrypoint instead of synthesizing a slash-delimited path" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-flat-entrypoint", tmp_root) do |root|
      write_file(root, "resque-lonely_job.gemspec", <<~RUBY)
        gem_version =
          if Gem.ruby_version >= Gem::Version.new("3.1")
            Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/resque-lonely_job/version.rb", mod) }::Resque::Plugins::LonelyJob::VERSION
          else
            require_relative "lib/resque-lonely_job/version"
            Resque::Plugins::LonelyJob::VERSION
          end

        Gem::Specification.new do |spec|
          spec.name = "resque-lonely_job"
          spec.version = gem_version
          spec.summary = "Resque worker serialization"
          spec.required_ruby_version = ">= 2.4"
          spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
        end
      RUBY
      write_file(root, "lib/resque-lonely_job.rb", <<~RUBY)
        require "resque-lonely_job/version"

        module Resque
          module Plugins
            module LonelyJob
            end
          end
        end
      RUBY
      write_file(root, "lib/resque-lonely_job/version.rb", <<~RUBY)
        module Resque
          module Plugins
            module LonelyJob
              VERSION = "1.1.4"
            end
          end
        end
      RUBY
      write_file(root, ".kettle-jem.yml", <<~YAML)
        project_emoji: "💎"
        templates:
          root: packaged
          apply: true
          entries:
            - source: lib/gem/version.rb
            - source: sig/gem.rbs
      YAML

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(apply.fetch(:changed_files)).to include("lib/resque-lonely_job/version.rb", "sig/resque-lonely_job.rbs")
      expect(File).to exist(File.join(root, "lib/resque-lonely_job.rb"))
      expect(File).not_to exist(File.join(root, "lib/resque/lonely_job.rb"))
      expect(File).not_to exist(File.join(root, "lib/resque/lonely_job/version.rb"))
      expect(File).not_to exist(File.join(root, "sig/resque/lonely_job.rbs"))

      entrypoint = File.read(File.join(root, "lib/resque-lonely_job.rb"))
      expect(entrypoint).to include('require_relative "resque-lonely_job/version"')
      expect(entrypoint).not_to include('require "resque-lonely_job/version"')
      expect(entrypoint).to include('require "version_gem"')
    end
  end

  it "bootstraps an existing package shim without modifying its nested implementation" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-package-shim-entrypoint", tmp_root) do |root|
      write_file(root, "demo-widget.gemspec", <<~RUBY)
        gem_version =
          Module.new.tap { |mod| Kernel.load("\#{__dir__}/lib/demo/widget/version.rb", mod) }::Demo::Widget::VERSION

        Gem::Specification.new do |spec|
          spec.name = "demo-widget"
          spec.version = gem_version
          spec.summary = "Demo widget"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
        end
      RUBY
      write_file(root, "lib/demo-widget.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "demo/widget/version"
        require_relative "demo/widget"
      RUBY
      write_file(root, "lib/demo/widget.rb", <<~RUBY)
        # frozen_string_literal: true

        module Demo
          module Widget
          end
        end
      RUBY
      write_file(root, "lib/demo/widget/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module Demo
          module Widget
            VERSION = "1.0.0"
          end
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(name: "version_gem_bootstrap", status: "applied")
      )
      package_entrypoint = File.read(File.join(root, "lib/demo-widget.rb"))
      expect(package_entrypoint).to include('require "version_gem"')
      expect(package_entrypoint).to include('require_relative "demo/widget/version"')
      expect(package_entrypoint).to include("Demo::Widget::Version.class_eval")

      implementation = File.read(File.join(root, "lib/demo/widget.rb"))
      expect(implementation).not_to include("version_gem", "Version.class_eval")
      expect(File).to exist(File.join(root, "lib/demo/widget/version.rb"))
      expect(File).not_to exist(File.join(root, "lib/demo-widget/version.rb"))
    end
  end

  it "preserves the full version path for a dedicated package-shim entrypoint" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-dedicated-package-shim-entrypoint", tmp_root) do |root|
      write_file(root, "demo-widget.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "demo-widget"
          spec.version = "1.0.0"
          spec.summary = "Demo widget"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
        end
      RUBY
      write_file(root, "lib/demo-widget.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "demo/widget"
      RUBY
      write_file(root, "lib/demo/widget.rb", <<~RUBY)
        # frozen_string_literal: true

        module Demo
          module Widget
          end
        end
      RUBY
      write_file(root, "lib/demo/widget/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module Demo
          module Widget
            VERSION = "1.0.0"
          end
        end
      RUBY
      write_file(root, "lib/demo/widget/version_gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "version"

        Demo::Widget::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      package_entrypoint = File.read(File.join(root, "lib/demo-widget.rb"))
      expect(package_entrypoint).to include('require_relative "demo/widget/version"')
      expect(package_entrypoint).not_to include('require_relative "widget/version"')
    end
  end

  it "does not duplicate a version require owned by a package shim implementation" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-package-shim-owned-version", tmp_root) do |root|
      write_file(root, "demo-widget.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "demo-widget"
          spec.version = "1.0.0"
          spec.summary = "Demo widget"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency "version_gem", "~> 1.1", ">= 1.1.14"
        end
      RUBY
      write_file(root, "lib/demo-widget.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "demo/widget"
      RUBY
      write_file(root, "lib/demo/widget.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "widget/version"

        module Demo
          module Widget
          end
        end
      RUBY
      write_file(root, "lib/demo/widget/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module Demo
          module Widget
            VERSION = "1.0.0"
          end
        end
      RUBY
      write_file(root, "lib/demo/widget/version_gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "version"

        Demo::Widget::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY

      described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      package_entrypoint = File.read(File.join(root, "lib/demo-widget.rb"))
      expect(package_entrypoint).not_to include("version")
      expect(File.read(File.join(root, "lib/demo/widget.rb"))).to include('require_relative "widget/version"')
    end
  end

  it "repairs a package-derived executable version header for a configured legacy entrypoint" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-executable-entrypoint", tmp_root) do |root|
      write_file(root, "appraisal2.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "appraisal2"
          spec.version = "3.2.1"
          spec.summary = "Appraisal compatibility matrix"
          spec.required_ruby_version = ">= 1.8.7"
          spec.executables = ["appraisal"]
        end
      RUBY
      write_file(root, "lib/appraisal.rb", <<~RUBY)
        module Appraisal
        end
      RUBY
      write_file(root, "lib/appraisal/version.rb", <<~RUBY)
        module Appraisal
          module Version
            VERSION = "3.2.1"
          end
        end
      RUBY
      write_file(root, "exe/appraisal", <<~RUBY)
        #!/usr/bin/env ruby

        script_basename = File.basename(__FILE__)
        require_relative "../lib/appraisal2/version"
        if ARGV.any? { |arg| arg == "-v" || arg == "--version" }
          puts Appraisal2::Version::VERSION
          exit(0)
        end

        require "appraisal2"
        puts "== \#{script_basename} v\#{Appraisal2::Version::VERSION} =="
      RUBY
      write_file(root, ".kettle-jem.yml", <<~YAML)
        project_emoji: "🔍"
        rubygems:
          entrypoint_require: appraisal
          min_ruby: "1.8.7"
      YAML

      facts = described_class.send(:discover_facts, root, env: {}, run_options: {skip_commit: true})
      tokens = described_class.send(:template_tokens, facts, {})
      expect(tokens.fetch("KJ|README:TITLE")).to eq("appraisal2 / Appraisal")
      heading_facts = facts.merge(project_runtime: facts.fetch(:project_runtime, {}).merge(project_emoji: "🔍"))
      expect(described_class.send(:normalize_readme_project_heading, "# 🔍 Appraisal\n", heading_facts)).to eq(
        "# 🔍 appraisal2 / Appraisal\n"
      )

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "executable_version_entrypoint_sync",
          status: "applied",
          changed_files: ["exe/appraisal"]
        )
      )
      executable = File.read(File.join(root, "exe/appraisal"))
      expect(executable).to include('require "appraisal2"')
      expect(executable).not_to include("script_basename")
      expect(executable).not_to include("require_relative")
      expect(executable).not_to include("appraisal2/version")
      expect(executable).not_to include("Appraisal2::Version")
    end
  end

  it "removes bundle gem scaffold literal VERSION declarations from the root signature" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-scaffold-rbs", tmp_root) do |root|
      write_file(root, "dummy-gem.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "dummy-gem"
          spec.version = "0.1.0"
          spec.summary = "Dummy gem"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, "lib/dummy/gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "gem/version"

        module Dummy
          module Gem
            class Error < StandardError; end
          end
        end
      RUBY
      write_file(root, "sig/dummy/gem.rbs", <<~RBS)
        module Dummy
          module Gem
            VERSION: "0.1.0"

            class Error < ::StandardError
            end
          end
        end
      RBS

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("sig/dummy/gem.rbs")
        )
      )
      root_signature = File.read(File.join(root, "sig/dummy/gem.rbs"))
      expect(root_signature).to include("module Version")
      expect(root_signature).to include("VERSION: String")
      expect(root_signature).to include("class Error < ::StandardError")
      loader = RBS::EnvironmentLoader.new
      loader.add(path: Pathname(File.join(root, "sig")))
      expect { RBS::Environment.from_loader(loader).resolve_type_names }.not_to raise_error
    end
  end

  it "removes stale root VERSION declarations when the managed version signature already exists" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-existing-rbs", tmp_root) do |root|
      write_file(root, "kettle-rb.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "kettle-rb"
          spec.version = "0.1.1"
          spec.summary = "Kettle Ruby compatibility data"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, "lib/kettle/rb.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "rb/version"

        module Kettle
          module Rb
          end
        end

        Kettle::Rb::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "lib/kettle/rb/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module Kettle
          module Rb
            module Version
              VERSION = "0.1.1"
            end
            VERSION = Version::VERSION # Traditional Constant Location
          end
        end
      RUBY
      write_file(root, "sig/kettle/rb.rbs", <<~RBS)
        module Kettle
          module Rb
            VERSION: String
          end
        end
      RBS
      write_file(root, "sig/kettle/rb/version.rbs", <<~RBS)
        module Kettle
          module Rb
            module Version
              VERSION: String
            end
            VERSION: String
          end
        end
      RBS

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("sig/kettle/rb.rbs", "sig/kettle/rb/version.rbs")
        )
      )
      expect(File).not_to exist(File.join(root, "sig/kettle/rb/version.rbs"))
      root_signature = File.read(File.join(root, "sig/kettle/rb.rbs"))
      expect(root_signature).to include("module Version")
      expect(root_signature.scan("VERSION: String").length).to eq(2)
      loader = RBS::EnvironmentLoader.new
      loader.add(path: Pathname(File.join(root, "sig")))
      expect { RBS::Environment.from_loader(loader).resolve_type_names }.not_to raise_error
    end
  end

  it "normalizes existing version specs to load version files anonymously for coverage" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-version-spec", tmp_root) do |root|
      write_file(root, "kettle-family.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "kettle-family"
          spec.version = "1.1.7"
          spec.summary = "Kettle family"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, "lib/kettle/family.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "family/version"

        module Kettle
          module Family
          end
        end

        Kettle::Family::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "lib/kettle-family.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "kettle/family"
      RUBY
      write_file(root, "spec/kettle/family/version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe Kettle::Family::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("lib/kettle/family/version.rb", "spec/kettle/family/version_spec.rb")
        )
      )
      version_spec = File.read(File.join(root, "spec/kettle/family/version_spec.rb"))
      expect(version_spec).to include('require "anonymous_loader"')
      expect(version_spec).to include('require "kettle-family"')
      expect(version_spec).to include('File.expand_path("../../../lib/kettle/family/version.rb", __dir__)')
      expect(version_spec).to include('File.expand_path("../../../lib/kettle/family/version_gem.rb", __dir__)')
      expect(version_spec).to include("anonymous_namespace = AnonymousLoader.load(files: paths)")
      expect(version_spec).to include(
        "expect(anonymous_namespace::Kettle::Family::Version::VERSION).to eq(described_class::VERSION)"
      )
      expect(version_spec).not_to include("load path")
    end
  end

  it "uses the discovered entrypoint require for hyphenated package names" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-hyphenated-version-spec", tmp_root) do |root|
      write_file(root, "lib/gitmoji/regex.rb", <<~RUBY)
        require_relative "regex/version"
      RUBY
      write_file(root, "lib/gitmoji/regex/version.rb", <<~RUBY)
        module Gitmoji
          module Regex
            module Version
              VERSION = "1.0.0"
            end
          end
        end
      RUBY
      write_file(root, "spec/gitmoji/regex/version_spec.rb", <<~RUBY)
          require "anonymous_loader"
          require "gitmoji-regex"
          RSpec.describe Gitmoji::Regex::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY

      report = {
        facts: {
          package: {name: "gitmoji-regex"},
          rubygems: {entrypoint_require: "gitmoji/regex", namespace: "Gitmoji::Regex"},
          project_runtime: {version: "1.0.0"},
          version_gem: {non_default_entrypoint: false}
        }
      }

      result = described_class.version_gem_bootstrap_step_for_paths(root, report.fetch(:facts))

      expect(result.fetch(:status)).to eq("applied")
      expect(File.read(File.join(root, "spec/gitmoji/regex/version_spec.rb"))).to include(
        'require "gitmoji/regex"'
      )
      expect(File.read(File.join(root, "spec/gitmoji/regex/version_spec.rb"))).not_to include(
        'require "gitmoji-regex"'
      )
    end
  end

  it "upgrades legacy anonymous-loader version specs to include version_gem entrypoints" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-version-spec-loader", tmp_root) do |root|
      write_file(root, "stone_checksums.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "stone_checksums"
          spec.version = "1.0.8"
          spec.summary = "Stone checksums"
          spec.required_ruby_version = ">= 3.1"
        end
      RUBY
      write_file(root, "lib/stone_checksums.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "stone_checksums/version"
      RUBY
      write_file(root, "lib/stone_checksums/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module StoneChecksums
          module Version
            VERSION = "1.0.8"
          end
        end
      RUBY
      write_file(root, "lib/stone_checksums/version_gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "version"

        StoneChecksums::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "spec/stone_checksums/version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        require "anonymous_loader"
        require "stone_checksums/version_gem"

        RSpec.describe StoneChecksums::Version do
          it_behaves_like "a Version module", described_class

          it "executes the version file for coverage without redefining constants" do
            path = File.expand_path("../../lib/stone_checksums/version.rb", __dir__)
            anonymous_namespace = AnonymousLoader.load(files: path)

            expect(anonymous_namespace::StoneChecksums::Version::VERSION).to eq(described_class::VERSION)
          end
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("spec/stone_checksums/version_spec.rb")
        )
      )
      version_spec = File.read(File.join(root, "spec/stone_checksums/version_spec.rb"))
      expect(version_spec).to include('File.expand_path("../../lib/stone_checksums/version.rb", __dir__)')
      expect(version_spec).to include('File.expand_path("../../lib/stone_checksums/version_gem.rb", __dir__)')
      expect(version_spec).to include("anonymous_namespace = AnonymousLoader.load(files: paths)")
      expect(version_spec).not_to include("AnonymousLoader.load(files: path)")
    end
  end

  it "creates a missing canonical version spec without migrating shim namespace specs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-missing-canonical-spec", tmp_root) do |root|
      write_file(root, "stone_checksums.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "stone_checksums"
          spec.version = "1.0.8"
          spec.summary = "Stone checksums"
          spec.required_ruby_version = ">= 3.1"
        end
      RUBY
      write_file(root, "lib/stone_checksums.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "stone_checksums/version"
      RUBY
      write_file(root, "lib/stone_checksums/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module StoneChecksums
          module Version
            VERSION = "1.0.8"
          end
        end
      RUBY
      write_file(root, "lib/stone_checksums/version_gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "version"

        StoneChecksums::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "spec/gem_checksums/version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe GemChecksums::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("spec/stone_checksums/version_spec.rb")
        )
      )
      version_spec = File.read(File.join(root, "spec/stone_checksums/version_spec.rb"))
      expect(version_spec).to include('require "anonymous_loader"')
      expect(version_spec).to include('require "stone_checksums/version_gem"')
      expect(version_spec).to include("RSpec.describe StoneChecksums::Version do")
      expect(version_spec).to include('File.expand_path("../../lib/stone_checksums/version.rb", __dir__)')
      expect(version_spec).to include('File.expand_path("../../lib/stone_checksums/version_gem.rb", __dir__)')
      expect(version_spec).to include("anonymous_namespace = AnonymousLoader.load(files: paths)")
      expect(version_spec).to include(
        "expect(anonymous_namespace::StoneChecksums::Version::VERSION).to eq(described_class::VERSION)"
      )
      expect(File.read(File.join(root, "spec/gem_checksums/version_spec.rb"))).to include("RSpec.describe GemChecksums::Version do")
    end
  end

  it "defaults an unconfigured supported-Ruby gem to the VersionGem bootstrap" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-spec-disabled", tmp_root) do |root|
      write_file(root, "plain-gem.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "plain-gem"
          spec.version = "1.0.0"
          spec.summary = "Plain gem"
          spec.required_ruby_version = ">= 3.2"
        end
      RUBY
      write_file(root, "lib/plain/gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "gem/version"

        module Plain
          module Gem
          end
        end
      RUBY
      write_file(root, "spec/plain/gem/version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe Plain::Gem::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY
      write_file(root, "spec/plain/gem/custom_version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe Plain::Gem::Version do
          it "keeps custom checks" do
            expect(described_class.name).to end_with("Version")
          end
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("lib/plain/gem.rb", "lib/plain/gem/version.rb", "spec/plain/gem/version_spec.rb")
        )
      )
      expect(File).to exist(File.join(root, "spec/plain/gem/version_spec.rb"))
      expect(File).to exist(File.join(root, "spec/plain/gem/custom_version_spec.rb"))
      entrypoint = File.read(File.join(root, "lib/plain/gem.rb"))
      expect(entrypoint).to include('require_relative "gem/version"')
      expect(entrypoint).to include('require "version_gem"')
      expect(entrypoint).to include("VersionGem::Basic")
    end
  end

  it "creates a managed plain version spec for old Ruby gems without version_gem" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-old-ruby-version-spec", tmp_root) do |root|
      write_file(root, "legacy-gem.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "legacy-gem"
          spec.version = "1.0.0"
          spec.summary = "Legacy gem"
          spec.required_ruby_version = ">= 1.8.7"
        end
      RUBY
      write_file(root, "lib/legacy/gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "gem/version"

        module Legacy
          module Gem
          end
        end
      RUBY
      write_file(root, "lib/legacy/gem/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module Legacy
          module Gem
            module Version
              VERSION = "1.0.0"
            end
            VERSION = Version::VERSION # Traditional Constant Location
          end
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_bootstrap",
          status: "applied",
          changed_files: ["lib/legacy/gem/version.rb", "spec/legacy/gem/version_spec.rb"]
        )
      )
      version_rb = File.read(File.join(root, "lib/legacy/gem/version.rb"))
      expect(version_rb).to include("# Version namespace for this gem.")
      expect(version_rb).to include("# Current gem version.")
      expect(version_rb).to include("# Current gem version exposed at the traditional constant location.")
      version_spec = File.read(File.join(root, "spec/legacy/gem/version_spec.rb"))
      expect(version_spec).to include('require "anonymous_loader"')
      expect(version_spec).to include('path = File.expand_path("../../../lib/legacy/gem/version.rb", __dir__)')
      expect(version_spec).to include("anonymous_namespace = AnonymousLoader.load(files: path)")
      expect(version_spec).to include("RSpec.describe Legacy::Gem::Version do")
      expect(version_spec).to include(
        "expect(anonymous_namespace::Legacy::Gem::Version::VERSION).to eq(described_class::VERSION)"
      )
      expect(version_spec).not_to include('it_behaves_like "a Version module"')
      expect(version_spec).not_to include("version_gem")
      expect(version_spec).not_to include("VersionGem")
    end
  end

  it "removes stale managed VersionGem shared examples from old Ruby version specs" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-old-ruby-version-spec-stale-shared", tmp_root) do |root|
      write_file(root, "legacy-gem.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "legacy-gem"
          spec.version = "1.0.0"
          spec.summary = "Legacy gem"
          spec.required_ruby_version = ">= 1.8.7"
        end
      RUBY
      write_file(root, "lib/legacy/gem.rb", <<~RUBY)
        # frozen_string_literal: true

        require_relative "gem/version"

        module Legacy
          module Gem
          end
        end
      RUBY
      write_file(root, "lib/legacy/gem/version.rb", <<~RUBY)
        # frozen_string_literal: true

        module Legacy
          module Gem
            module Version
              VERSION = "1.0.0"
            end
            VERSION = Version::VERSION # Traditional Constant Location
          end
        end
      RUBY
      write_file(root, "spec/legacy/gem/version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe Legacy::Gem::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_bootstrap",
          status: "applied",
          changed_files: include("spec/legacy/gem/version_spec.rb")
        )
      )
      version_spec = File.read(File.join(root, "spec/legacy/gem/version_spec.rb"))
      expect(version_spec).not_to include('it_behaves_like "a Version module"')
      expect(version_spec).not_to include("VersionGem")
      expect(version_spec).to include("anonymous_namespace = AnonymousLoader.load(files: path)")
      expect(version_spec).to include(
        "expect(anonymous_namespace::Legacy::Gem::Version::VERSION).to eq(described_class::VERSION)"
      )
    end
  end

  it "preserves non-default version_gem loading when a dedicated version_gem entrypoint exists" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-non-default", tmp_root) do |root|
      write_file(root, "nomono.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "nomono"
          spec.version = "1.0.8"
          spec.summary = "Nomono"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, ".kettle-jem.yml", <<~YAML)
        templates:
          root: template
          apply: true
          entries:
            - nomono.gemspec
      YAML
      write_file(root, "template/nomono.gemspec.example", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "{KJ|GEM_NAME}"
          spec.version = "0.0.0"
          spec.summary = "Template summary"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.14")
        end
      RUBY
      write_file(root, "lib/nomono.rb", <<~RUBY)
        # frozen_string_literal: true

        require "version_gem"
        require_relative "nomono/version"
        require_relative "nomono/core"

        Nomono::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      dedicated_entrypoint = <<~RUBY
        # frozen_string_literal: true

        require "version_gem"
        require_relative "version"

        Nomono::Version.class_eval do
          extend VersionGem::Basic
        end
      RUBY
      write_file(root, "lib/nomono/version_gem.rb", dedicated_entrypoint)
      write_file(root, "spec/nomono/version_spec.rb", <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe Nomono::Version do
          it_behaves_like "a Version module", described_class
        end
      RUBY

      result = described_class.apply_project(root, env: {}, run_options: {accept: true, skip_commit: true})

      expect(result.fetch(:post_apply_steps)).to include(
        include(
          name: "version_gem_bootstrap",
          status: "applied",
          changed_files: include("lib/nomono.rb", "lib/nomono/version.rb", "sig/nomono.rbs", "spec/nomono/version_spec.rb")
        )
      )
      entrypoint = File.read(File.join(root, "lib/nomono.rb"))
      expect(entrypoint).to include('require_relative "nomono/version"')
      expect(entrypoint).to include('require_relative "nomono/core"')
      expect(entrypoint).not_to include('require "version_gem"')
      expect(entrypoint).not_to include("VersionGem::Basic")
      gemspec = File.read(File.join(root, "nomono.gemspec"))
      expect(gemspec).not_to include("version_gem")
      expect(File.read(File.join(root, "lib/nomono/version_gem.rb"))).to eq(dedicated_entrypoint)
      version_spec = File.read(File.join(root, "spec/nomono/version_spec.rb"))
      expect(version_spec).to include('require "anonymous_loader"')
      expect(version_spec).to include('require "nomono/version_gem"')
      expect(version_spec).to include("RSpec.describe Nomono::Version do")
      expect(version_spec).to include('File.expand_path("../../lib/nomono/version.rb", __dir__)')
      expect(version_spec).to include('File.expand_path("../../lib/nomono/version_gem.rb", __dir__)')
      expect(version_spec).to include("anonymous_namespace = AnonymousLoader.load(files: paths)")
      expect(version_spec).to include(
        "expect(anonymous_namespace::Nomono::Version::VERSION).to eq(described_class::VERSION)"
      )
    end
  end

  it "uses the public slash entrypoint for explicit inline version_gem mode despite a legacy package wrapper" do
    tmp_root = File.join(__dir__, "tmp")
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-version-gem-inline-wrapper", tmp_root) do |root|
      write_file(root, "yard-timekeeper.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "yard-timekeeper"
          spec.version = "0.2.5"
          spec.summary = "YARD timekeeper"
          spec.required_ruby_version = ">= 3.2"
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.15")
        end
      RUBY
      write_file(root, "lib/yard-timekeeper.rb", <<~RUBY)
        require_relative "yard/timekeeper"
      RUBY
      write_file(root, "lib/yard/timekeeper.rb", <<~RUBY)
        require "open3"
      RUBY

      facts = {
        package: {name: "yard-timekeeper"},
        rubygems: {
          entrypoint_require: "yard/timekeeper",
          namespace: "Yard::Timekeeper",
          min_ruby: "3.2"
        },
        project_runtime: {version: "0.2.5"},
        version_gem: {enabled: true, mode: "inline"}
      }

      report = {
        facts: facts,
        recipe_reports: [],
        template_selection: {only: []}
      }
      result = described_class.send(:template_version_gem_bootstrap_step, root, report)

      expect(result[:entrypoint_path]).to eq("lib/yard/timekeeper.rb")
      entrypoint = File.read(File.join(root, "lib/yard/timekeeper.rb"))
      expect(entrypoint).to include('require "version_gem"')
      expect(entrypoint).to include('require_relative "timekeeper/version"')
      expect(File.read(File.join(root, "lib/yard-timekeeper.rb"))).to include('require_relative "yard/timekeeper"')
    end
  end
end
