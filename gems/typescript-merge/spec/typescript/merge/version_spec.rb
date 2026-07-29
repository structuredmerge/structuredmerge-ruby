# frozen_string_literal: true

require "anonymous_loader"
RSpec.describe TypeScript::Merge::Version do
  it_behaves_like "a Version module", described_class

it "executes the version file for coverage without redefining constants" do
  path = File.expand_path("../../../lib/typescript/merge/version.rb", __dir__)
  anonymous_namespace = AnonymousLoader.load(files: path)

  expect(anonymous_namespace::TypeScript::Merge::Version::VERSION).to eq(described_class::VERSION)
end
end
