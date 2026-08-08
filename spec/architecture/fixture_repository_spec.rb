# frozen_string_literal: true

RSpec.describe StructuredMerge::FixtureRepository do
  it 'uses the library release version for the fixture release' do
    expect(described_class.version).to eq(TreeHaver::VERSION)
  end

  it 'uses the locked fixture revision in the sibling checkout' do
    expect(described_class.checkout_revision).to eq(described_class.revision)
  end

  it 'uses a fixture tag that resolves to the locked revision' do
    expect(described_class.tag).to eq("v#{described_class.version}")
    expect(described_class.tag_revision).to eq(described_class.revision)
  end
end
