# frozen_string_literal: true

RSpec.describe "TreeHaver runtime dependencies" do
  it "declares the typed core binding as a compatible runtime dependency" do
    gemspec = Gem::Specification.load(File.expand_path("../../tree_haver.gemspec", __dir__))
    dependency = gemspec.dependencies.find { |item| item.name == "structuredmerge-core" }

    expect(dependency).not_to be_nil
    expect(dependency.type).to eq(:runtime)
    expect(dependency.requirement).to satisfy { |requirement| requirement.satisfied_by?(Gem::Version.new("0.2.0")) }
  end
end
