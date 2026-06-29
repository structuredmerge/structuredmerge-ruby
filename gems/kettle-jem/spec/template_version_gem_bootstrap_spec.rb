# frozen_string_literal: true

require_relative "spec_helper"
require "pathname"
require "rbs"

RSpec.describe Kettle::Jem do
  def write_file(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
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
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")
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
          changed_files: include("lib/plain/merge.rb", "lib/plain/merge/version.rb", "sig/plain/merge.rbs", "sig/plain/merge/version.rbs")
        )
      )
      entrypoint = File.read(File.join(root, "lib/plain/merge.rb"))
      expect(entrypoint).to include(<<~RUBY)
        require "version_gem"
        require_relative "merge/version"
      RUBY
      expect(entrypoint.index('require_relative "merge/version"')).to be < entrypoint.index("Plain::Merge::Version.class_eval do")
      expect(File.read(File.join(root, "lib/plain/merge/version.rb"))).to include('VERSION = "7.0.0"')
      signature = File.read(File.join(root, "sig/plain/merge/version.rbs"))
      expect(signature).to include("module Plain")
      expect(signature).to include("module Merge")
      expect(signature).to include("module Version")
      expect(signature.scan("VERSION: String").length).to eq(2)
      root_signature = File.read(File.join(root, "sig/plain/merge.rbs"))
      expect(root_signature).not_to include("VERSION: String")
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
          spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.13")
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
          changed_files: include("sig/dummy/gem.rbs", "sig/dummy/gem/version.rbs")
        )
      )
      root_signature = File.read(File.join(root, "sig/dummy/gem.rbs"))
      expect(root_signature).not_to include("VERSION:")
      expect(root_signature).to include("class Error < ::StandardError")
      loader = RBS::EnvironmentLoader.new
      loader.add(path: Pathname(File.join(root, "sig")))
      expect { RBS::Environment.from_loader(loader).resolve_type_names }.not_to raise_error
    end
  end
end
