# frozen_string_literal: true

RSpec.describe Kettle::Jem, "shim profile templating" do
  include_context "with isolated kettle-jem environment"
  include_context "with kettle-jem fixture contracts"

  it "converts an implementation-shaped gem into a shim profile gem" do
    tmp_root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-jem-shim-slice", tmp_root) do |root|
      write_tree(
        root,
        {
          ".structuredmerge/kettle-jem.yml" => <<~YAML,
            project_emoji: "*"

            rubygems:
              name: legacy-shim
              entrypoint_require: legacy/shim
              namespace: Legacy::Shim
              min_ruby: "2.2"

            shim:
              replacement_gem: legacy-shim2
              replacement_require: legacy-shim2
              legacy_requires:
                - legacy/strategies/shim

            templates:
              root: packaged
              apply: true
              profile: shim

            tokens:
              author:
                name: Ada Lovelace
                email: ada@example.com
          YAML
          "legacy-shim.gemspec" => <<~RUBY,
            Gem::Specification.new do |spec|
              spec.name = "legacy-shim"
              spec.version = "0.1.0"
              spec.authors = ["Ada Lovelace"]
              spec.email = ["ada@example.com"]
              spec.summary = "Legacy implementation"
              spec.description = "Legacy implementation"
              spec.homepage = "https://github.com/example/legacy-shim"
              spec.licenses = ["MIT"]
              spec.required_ruby_version = ">= 2.2"
              spec.add_dependency "old-implementation"
            end
          RUBY
          "README.md" => "# Old implementation README\n",
          "Gemfile" => "source \"https://rubygems.org\"\n",
          "Rakefile" => "task :old\n",
          "lib/legacy/shim.rb" => "require \"old-implementation\"\n",
          "lib/legacy/shim/version.rb" => "module Legacy; module Shim; VERSION = \"0.1.0\"; end; end\n",
          "lib/legacy/strategies/shim.rb" => "class OldStrategy; end\n",
          "spec/lib/legacy/strategies/shim_spec.rb" => "RSpec.describe OldStrategy\n",
          "spec/support/helper.rb" => "# old helper\n",
          "gemfiles/legacy.gemfile" => "gem \"old-implementation\"\n",
          ".github/workflows/coverage.yml" => "name: Coverage\n"
        }
      )
      system("git", "-C", root, "init", "--quiet")
      system("git", "-C", root, "add", "legacy-shim.gemspec", "lib/legacy/shim/version.rb")

      plan = described_class.plan_project(root, env: {})
      expect(plan.dig(:facts, :shim, :replacement_gem)).to eq("legacy-shim2")
      recipe_names = plan[:recipe_pack][:recipes].map { |recipe| recipe[:name] }
      expect(recipe_names).to include("template_source_application_legacy_shim_gemspec")
      expect(recipe_names).to include("template_shim_profile_cleanup_gemfiles_legacy_gemfile")
      expect(recipe_names).to include("template_shim_profile_cleanup_spec_lib_legacy_strategies_shim_spec_rb")

      described_class.apply_project(root, env: {})

      generated = project_files(
        root,
        [
          "legacy-shim.gemspec",
          "lib/legacy/shim.rb",
          "lib/legacy/shim/version.rb",
          "lib/legacy/strategies/shim.rb",
          "spec/shim_spec.rb",
          "README.md",
          "Gemfile",
          "gemfiles/modular/templating.gemfile",
          "gemfiles/modular/templating_local.gemfile",
          "gemfiles/legacy.gemfile",
          "spec/lib/legacy/strategies/shim_spec.rb",
          ".github/workflows/coverage.yml"
        ]
      )
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.version = "0.1.0"))
      expect(generated[:"legacy-shim.gemspec"]).not_to include(%(load "lib/legacy/shim/version.rb"))
      expect(generated[:"legacy-shim.gemspec"]).to include("LICENSE.md")
      expect(generated[:"legacy-shim.gemspec"]).not_to include("LICENSE.txt")
      expect(generated[:"legacy-shim.gemspec"]).to include(%(spec.add_dependency "legacy-shim2"))
      expect_gemspec_dependency_declared(generated[:"legacy-shim.gemspec"], "kettle-dev", kind: :add_development_dependency)
      expect_gemspec_dependency_declared(generated[:"legacy-shim.gemspec"], "kettle-test", kind: :add_development_dependency)
      expect_gemspec_dependency_declared(generated[:"legacy-shim.gemspec"], "stone_checksums", kind: :add_development_dependency)
      expect(generated[:Gemfile]).to include(%(source "https://gem.coop"))
      expect_gem_dependency_declared(generated[:Gemfile], "nomono")
      expect(generated[:Gemfile]).to include(%(eval_gemfile "gemfiles/modular/templating.gemfile"))
      expect(generated[:Gemfile]).not_to include("git:")
      expect_gem_dependency_declared(generated[:"gemfiles/modular/templating.gemfile"], "kettle-jem")
      expect(generated[:"gemfiles/modular/templating_local.gemfile"]).to include(%(structuredmerge_local_gems = %w[))
      expect(generated[:"legacy-shim.gemspec"]).not_to include("old-implementation")
      expect(generated[:"lib/legacy/shim.rb"]).to include(%(require "legacy-shim2"))
      expect(generated[:"lib/legacy/strategies/shim.rb"]).to include(%(require "legacy/shim"))
      expect(generated[:"spec/shim_spec.rb"]).to include(%(require("legacy-shim2")))
      expect(generated[:"README.md"]).to include("compatibility shim for `legacy-shim2`")
      expect(generated[:"gemfiles/legacy.gemfile"]).to be_nil
      expect(generated[:"spec/lib/legacy/strategies/shim_spec.rb"]).to be_nil
      expect(generated[:".github/workflows/coverage.yml"]).to be_nil

      File.write(File.join(root, "legacy-shim.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          load "lib/legacy/shim/version.rb"
          spec.name = "legacy-shim"
          spec.version = Legacy::Shim::Version::VERSION
          spec.authors = ["Ada Lovelace"]
          spec.email = ["ada@example.com"]
          spec.summary = "Legacy implementation"
          spec.description = "Legacy implementation"
          spec.homepage = "https://github.com/example/legacy-shim"
          spec.licenses = ["MIT"]
          spec.required_ruby_version = ">= 2.2"
        end
      RUBY
      expect { described_class.plan_project(root, env: {}) }.not_to raise_error
    end
  end
end
