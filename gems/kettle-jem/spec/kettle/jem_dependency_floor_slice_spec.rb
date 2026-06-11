# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Kettle::Jem do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:non_structuredmerge_floors) do
    {
      "appraisal2" => {
        declaration_names: ["appraisal2"],
        requirement_args: %("~> 3.1", ">= 3.1.2"),
        lock_version: "3.1.2",
        requirement_surfaces: [
          "kettle-jem.gemspec",
          "lib/kettle/jem.rb",
          "lib/kettle/jem/templates/gem.gemspec.example"
        ]
      },
      "kettle-dev" => {
        declaration_names: ["kettle-dev", "{KJ|KETTLE_DEV_GEM}"],
        requirement_args: %("~> 2.2", ">= 2.2.3"),
        lock_version: "2.2.3",
        requirement_surfaces: [
          "kettle-jem.gemspec",
          "lib/kettle/jem.rb",
          "lib/kettle/jem/templates/gem.gemspec.example"
        ]
      },
      "kettle-drift" => {
        declaration_names: ["kettle-drift"],
        requirement_args: %("~> 1.0", ">= 1.0.3"),
        lock_version: "1.0.3",
        requirement_surfaces: [
          "gemfiles/modular/templating.gemfile",
          "lib/kettle/jem.rb",
          "lib/kettle/jem/templates/gemfiles/modular/templating.gemfile.example"
        ]
      },
      "kettle-test" => {
        declaration_names: ["kettle-test"],
        requirement_args: %("~> 2.0", ">= 2.0.5"),
        lock_version: "2.0.5",
        requirement_surfaces: [
          "lib/kettle/jem.rb",
          "lib/kettle/jem/templates/gem.gemspec.example"
        ]
      },
      "kettle-soup-cover" => {
        declaration_names: ["kettle-soup-cover"],
        requirement_args: %("~> 2.0", ">= 2.0.2"),
        lock_version: "2.0.2",
        requirement_surfaces: [
          "gemfiles/modular/coverage.gemfile",
          "lib/kettle/jem/templates/gemfiles/modular/coverage.gemfile.example"
        ]
      },
      "rubocop-gradual" => {
        declaration_names: ["rubocop-gradual"],
        requirement_args: %("~> 0.4", ">= 0.4.0"),
        lock_version: "0.4.0",
        requirement_surfaces: [
          "gemfiles/modular/style.gemfile",
          "lib/kettle/jem/templates/gemfiles/modular/style.gemfile.example"
        ]
      },
      "nomono" => {
        declaration_names: ["nomono"],
        requirement_args: %("~> 1.0", ">= 1.0.3"),
        lock_version: "1.0.3",
        requirement_surfaces: [
          "Gemfile",
          "lib/kettle/jem/templates/Gemfile.example"
        ]
      },
      "token-resolver" => {
        declaration_names: ["token-resolver"],
        requirement_args: %("~> 2.0", ">= 2.0.2"),
        lock_version: "2.0.2",
        requirement_surfaces: [
          "kettle-jem.gemspec"
        ]
      },
      "turbo_tests2" => {
        declaration_names: ["turbo_tests2"],
        requirement_args: %("~> 3.1", ">= 3.1.2"),
        lock_version: "3.1.2",
        requirement_surfaces: [
          "lib/kettle/jem.rb",
          "lib/kettle/jem/templates/gem.gemspec.example"
        ]
      },
      "yard-fence" => {
        declaration_names: ["yard-fence"],
        requirement_args: %("~> 0.9", ">= 0.9.3"),
        lock_version: "0.9.3",
        requirement_surfaces: [
          "lib/kettle/jem/templates/gemfiles/modular/documentation.gemfile.example"
        ]
      }
    }
  end

  def file_content(relative_path)
    root.join(relative_path).read
  end

  it "keeps non-StructuredMerge floors aligned across fast-checkable surfaces" do
    non_structuredmerge_floors.each do |gem_name, config|
      config.fetch(:requirement_surfaces).each do |relative_path|
        content = file_content(relative_path)
        floor_declarations = config.fetch(:declaration_names).map do |declaration_name|
          %(#{declaration_name}", #{config.fetch(:requirement_args)})
        end

        expect(floor_declarations.any? { |declaration| content.include?(declaration) }).to be(true)
      end

      lockfile = file_content(config.fetch(:lockfile_path, "Gemfile.lock"))
      expect(lockfile).to include(%(#{gem_name} (#{config.fetch(:lock_version)})))
    end
  end
end
