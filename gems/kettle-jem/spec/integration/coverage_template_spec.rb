# frozen_string_literal: true

RSpec.describe Kettle::Jem, "coverage bootstrap template behavior" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "removes obsolete SimpleCov setup calls from .simplecov while preserving local config" do
    content = <<~RUBY
      # kettle-jem:freeze
      # local coverage note
      # kettle-jem:unfreeze
      require "kettle-soup-cover"
      require "kettle/soup/cover/config"

      SimpleCov.configure do
        track_files "lib/**/*.rb"
        custom_setting "kept"
      end

      SimpleCov.start do
        track_files "lib/**/*.rb"
        track_files "exe/*.rb"
      end

      custom_after_config
    RUBY

    output = described_class.send(:normalize_simplecov_template_source, content)

    expect(output).to include("# local coverage note")
    expect(output).to include("SimpleCov.configure do")
    expect(output).to include('cover "lib/**/*.rb"')
    expect(output).to include('custom_setting "kept"')
    expect(output).to include("custom_after_config")
    expect(output).not_to include('require "kettle-soup-cover"')
    expect(output).not_to include('require "kettle/soup/cover/config"')
    expect(output).not_to include("SimpleCov.start")
    expect(output).not_to include("track_files")
  end

  it "removes obsolete .simplecov keep_destination config during config sync" do
    content = <<~YAML
      defaults:
        preference: "template"
      files:
        AGENTS.md:
          strategy: accept_template
        .simplecov:
          strategy: keep_destination
        Rakefile:
          strategy: accept_template
    YAML

    output = described_class.send(:sync_kettle_config_env_overrides, content, {})

    expect(output).to include("AGENTS.md:")
    expect(output).to include("Rakefile:")
    expect(output).not_to include(".simplecov:")
  end

  it "normalizes stale spec helper SimpleCov bootstrap without dropping local wiring" do
    content = <<~RUBY
      # frozen_string_literal: true

      require_relative "support/local"

      begin
        require "kettle-soup-cover"
        if Kettle::Soup::Cover::DO_COV
          require "simplecov"
          SimpleCov.start
        end
        require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
      rescue LoadError => error
        raise error unless error.message.include?("kettle")
      end

      require "kettle/test/rspec"
      require "example"
    RUBY

    output = described_class.send(:normalize_spec_helper_simplecov_template_source, content)

    expect(output).to include('require_relative "support/local"')
    expect(output.scan('require "simplecov"').size).to eq(1)
    expect(output.index('require "simplecov"')).to be < output.index('require "kettle/soup/cover/config"')
    expect(output.index('require "kettle/soup/cover/config"')).to be < output.index("SimpleCov.start")
    expect(output).not_to include("`.simplecov` is run here")
  end

  it "upgrades modifier-form spec helper SimpleCov bootstrap to the kettle-soup-cover startup block" do
    content = <<~RUBY
      # frozen_string_literal: true

      # For code coverage, must be required before all application / gem / library code.
      begin
        require "kettle-soup-cover"
        require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
      rescue LoadError => error
        raise error unless error.message.include?("kettle")
      end

      require "active_record"
      require "example"
    RUBY

    output = described_class.send(:normalize_spec_helper_simplecov_template_source, content)

    expect(output).to include('require "kettle-soup-cover"')
    expect(output).to include("if Kettle::Soup::Cover::DO_COV")
    expect(output).to include('require "simplecov" # Loads project-local .simplecov.')
    expect(output).to include('require "kettle/soup/cover/config"')
    expect(output).to include("SimpleCov.start")
    expect(output.index('require "kettle/soup/cover/config"')).to be < output.index("SimpleCov.start")
    expect(output.index("SimpleCov.start")).to be < output.index('require "active_record"')
    expect(output).not_to include("`.simplecov` is run here")
  end

  it "updates old generated SimpleCov files in the same templating pass that removes keep_destination" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-simplecov-migration", tmp_root) do |root|
      write_tree(root, {
        "example.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "example"
            spec.summary = "Example gem"
            spec.required_ruby_version = ">= 3.2"
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML,
          project_emoji: 🧪
          templates:
            root: packaged
            apply: true
            entries:
              - .structuredmerge/kettle-jem.yml
              - .simplecov
              - spec/spec_helper.rb
          rubygems:
            entrypoint_require: "example"
            namespace: "Example"
          files:
            .simplecov:
              strategy: keep_destination
        YAML
        ".simplecov" => <<~RUBY,
          require "kettle-soup-cover"
          require "kettle/soup/cover/config"

          SimpleCov.start do
            track_files "lib/**/*.rb"
          end
        RUBY
        "spec/spec_helper.rb" => <<~RUBY
          # frozen_string_literal: true

          begin
            require "kettle-soup-cover"
            if Kettle::Soup::Cover::DO_COV
              require "simplecov"
              SimpleCov.start
            end
            require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
          rescue LoadError => error
            raise error unless error.message.include?("kettle")
          end

          require "example"
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      simplecov = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".simplecov" }
      spec_helper = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "spec/spec_helper.rb" }
      kettle_config = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".structuredmerge/kettle-jem.yml" }

      expect(simplecov.fetch(:final_content)).to include('cover "lib/**/*.rb"')
      expect(simplecov.fetch(:final_content)).not_to include("SimpleCov.start")
      expect(simplecov.fetch(:final_content)).not_to include('require "kettle-soup-cover"')
      expect(simplecov.fetch(:final_content)).not_to include('require "kettle/soup/cover/config"')
      expect(spec_helper.fetch(:final_content).scan('require "simplecov"').size).to eq(1)
      expect(spec_helper.fetch(:final_content)).to include('require "kettle/soup/cover/config"')
      expect(spec_helper.fetch(:final_content)).to include("SimpleCov.start")
      expect(kettle_config.fetch(:final_content)).not_to include(".simplecov:")
    end
  end

  it "migrates existing SimpleCov bootstrap files for monorepo package profiles that omit harness entries" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-smorg-rb-simplecov-migration", tmp_root) do |root|
      write_tree(root, {
        "smorg-rb.gemspec" => <<~RUBY,
          Gem::Specification.new do |spec|
            spec.name = "smorg-rb"
            spec.summary = "Example gem"
            spec.licenses = ["AGPL-3.0-only", "PolyForm-Small-Business-1.0.0"]
            spec.required_ruby_version = ">= 4.0"
          end
        RUBY
        ".structuredmerge/kettle-jem.yml" => <<~YAML,
          project_emoji: 💎
          templates:
            root: packaged
            apply: true
            profile: monorepo-subgem-package
            entries:
              - README.md
              - source: gem.gemspec
                target: smorg-rb.gemspec
              - Gemfile
          defaults:
            preference: "template"
            add_template_only_nodes: true
            freeze_token: "kettle-jem"
          rubygems:
            namespace: Smorg::RB
          files:
            README.md:
              strategy: merge
            smorg-rb.gemspec:
              strategy: keep_destination
        YAML
        ".simplecov" => <<~RUBY,
          require 'kettle/soup/cover/config'

          SimpleCov.start do
            track_files 'lib/**/*.rb'
            track_files 'lib/**/*.rake'
            track_files 'exe/*.rb'
          end
        RUBY
        "spec/spec_helper.rb" => <<~RUBY
          # frozen_string_literal: true

          begin
            require 'kettle-soup-cover'
            require 'simplecov' if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
          rescue LoadError => e
            raise e unless e.message.include?('kettle')
          end

          require 'smorg/rb'
        RUBY
      })

      apply = described_class.apply_project(root, env: {}, run_options: {accept: true})
      simplecov = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == ".simplecov" }
      spec_helper = apply.fetch(:recipe_reports).find { |candidate| candidate.fetch(:relative_path) == "spec/spec_helper.rb" }

      expect(simplecov).not_to be_nil
      expect(spec_helper).not_to be_nil
      expect(simplecov.fetch(:final_content)).to include('cover "lib/**/*.rb", "lib/**/*.rake", "exe/*.rb"')
      expect(simplecov.fetch(:final_content)).not_to include("SimpleCov.start")
      expect(simplecov.fetch(:final_content)).not_to include("track_files")
      expect(spec_helper.fetch(:final_content)).to include('require "simplecov"')
      expect(spec_helper.fetch(:final_content)).to include('require "kettle/soup/cover/config"')
      expect(spec_helper.fetch(:final_content)).to include("SimpleCov.start")
      expect(spec_helper.fetch(:final_content)).not_to include("require 'kettle-soup-cover'")
      expect(spec_helper.fetch(:final_content)).not_to include("`.simplecov` is run here")
    end
  end
end
