# frozen_string_literal: true

require "rubygems"

RSpec.describe "StructuredMerge Ruby gemspec package manifests" do
  forbidden_package_files = %w[
    CITATION.cff
    CODE_OF_CONDUCT.md
    CONTRIBUTING.md
    FUNDING.md
    MIT.md
    RUBOCOP.md
    SECURITY.md
  ].freeze

  Dir.glob("gems/*/*.gemspec").sort.each do |gemspec_path|
    it "#{gemspec_path} ships only runtime package files and minimal metadata" do
      spec = Gem::Specification.load(gemspec_path)
      expect(spec).not_to be_nil

      files = spec.files
      expect(files).not_to include(*forbidden_package_files)
      expect(files.grep(%r{\Acerts/})).to be_empty
      expect(spec.extra_rdoc_files).to be_empty
    end
  end
end
