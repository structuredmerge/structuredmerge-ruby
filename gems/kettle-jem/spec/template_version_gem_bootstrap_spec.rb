# frozen_string_literal: true

require "pathname"
require "rbs"

RSpec.describe Kettle::Jem do
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
      expect(version_spec).to include('require "nomono/version_gem"')
      expect(version_spec).to include("RSpec.describe Nomono::Version do")
    end
  end
end
