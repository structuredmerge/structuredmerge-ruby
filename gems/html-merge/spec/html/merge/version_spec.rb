# frozen_string_literal: true

require "anonymous_loader"
require "html/merge"
RSpec.describe Html::Merge::Version do
  it_behaves_like "a Version module", described_class

it "executes the version file for coverage without redefining constants" do
  path = File.expand_path("../../../lib/html/merge/version.rb", __dir__)
  anonymous_namespace = AnonymousLoader.load(files: path)

  expect(anonymous_namespace::Html::Merge::Version::VERSION).to eq(described_class::VERSION)
end
end
