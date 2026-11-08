# frozen_string_literal: true

RSpec.describe Kettle::Jem do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "verifies the packaged template against a filtered native manifest" do
    Dir.mktmpdir do |root|
      write_tree(root, {
        "example.gemspec" => <<~GEMSPEC,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.version = "1.0.0"
            spec.summary = "Example"
            spec.authors = ["Example"]
            spec.email = ["example@example.com"]
            spec.licenses = ["MIT"]
            spec.files = [
              "lib/example.rb"
            ]
            spec.extensions = ["ext/example/extconf.rb"]
            spec.add_runtime_dependency "json", ">= 2.0"
          end
        GEMSPEC
        ".kettle-jem.yml" => <<~YAML,
          gemspec:
            package_files:
              include:
                - data/**/*.json
                - ext/**/*
          tokens:
            author:
              orcid: "0000-0000-0000-0000"
              given_names: "Jane"
              family_names: "Example"
          templates:
            root: packaged
            apply: true
        YAML
        "README.md" => "readme", "LICENSE.md" => "license", "lib/example.rb" => "", "ext/example/extconf.rb" => "", "ext/example/native.c" => "source", "custom/source.c" => "", "data/config.json" => "{}", "exe/tool" => "tool",
        **%w[so bundle dylib dll o a].to_h { |ext| ["ext/example/native.#{ext}", "bad"] },
        "ext/example/native.log" => "keep"
      })
      described_class.apply_project(root, env: {})
      first_files = Dir.chdir(root) { Gem::Specification.load("example.gemspec").files }
      described_class.apply_project(root, env: {})
      second = File.read(File.join(root, "example.gemspec"))
      expect(second.scan("data/**/*.json").length).to eq(1)
      expect(Dir.chdir(root) { Gem::Specification.load("example.gemspec").files }).to eq(first_files)
      spec = Dir.chdir(root) { Gem::Specification.load("example.gemspec") }
      expect(spec.extensions).to include("ext/example/extconf.rb")
      expect(spec.runtime_dependencies.map(&:name)).to include("json")
      expect(spec.files).to include("README.md", "lib/example.rb", "ext/example/extconf.rb", "ext/example/native.c", "ext/example/native.log", "data/config.json", "exe/tool")
      expect(spec.files.grep(%r{\.(?:so|bundle|dylib|dll|o|a)\z})).to be_empty
      Dir.chdir(root) do
        require "rubygems/package"
        gem_path = Gem::Package.build(spec, true)
        packaged = Gem::Package.new(gem_path).contents
        expect(packaged).to include("ext/example/extconf.rb", "ext/example/native.c", "ext/example/native.log", "data/config.json", "exe/tool")
        expect(packaged.grep(%r{\.(?:so|bundle|dylib|dll|o|a)\z})).to be_empty
      end
    end
  end
end
