# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Ast::Crispr::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled typed core is unavailable' unless described_class.available? }

  def fixture(slice, name)
    root = File.expand_path('../../../../../fixtures/diagnostics', __dir__)
    JSON.parse(File.read(File.join(root, "slice-#{slice}-#{name}", "#{name}.json")))
  end

  {
    'match' => [918, 'ast-crispr-match-profile-helpers'],
    'selection' => [919, 'ast-crispr-selection-profile-helpers'],
    'destination' => [920, 'ast-crispr-destination-profile-helpers'],
    'operation' => [921, 'ast-crispr-operation-profile-helpers']
  }.each do |kind, (slice, name)|
    it "preserves every #{kind} report in the shared fixture" do
      fixture(slice, name).fetch('cases').each do |test_case|
        expect(provider.report(test_case.fetch('profile').merge('kind' => kind)))
          .to eq(test_case.fetch('expected')), test_case.fetch('name')
      end
    end
  end

  it 'preserves the complete package boundary fixture' do
    expect(provider.report(kind: 'boundary')).to eq(fixture(916, 'ast-crispr-package-boundary').fetch('boundary'))
  end

  it 'preserves every valid limit description and rejects invalid fixture inputs' do
    data = fixture(917, 'ast-crispr-limit-helpers')
    data.fetch('cases').each do |test_case|
      expect(provider.report(kind: 'limit', spec: test_case['spec']))
        .to eq('description' => test_case.fetch('expected_description')), test_case.fetch('name')
    end
    data.fetch('invalid_cases').each do |test_case|
      expect { provider.report(kind: 'limit', spec: test_case['spec']) }.to raise_error(RuntimeError)
    end
  end

  it 'preserves complete operation batches in their original order' do
    fixture(923, 'ast-crispr-batch-operation-helpers').fetch('cases').each do |test_case|
      operations = test_case.fetch('helpers').map do |helper|
        # Existing public helpers supply the request; expected reports come only
        # from the independent shared fixture, not from these helper reports.
        profile = Ast::Crispr.public_send("#{helper}_operation")
        %i[operation_kind source_requirement destination_requirement replacement_source]
          .to_h { |field| [field, profile.public_send(field).to_s] }
          .merge(captures_source_text: profile.captures_source_text?, supports_if_missing: profile.supports_if_missing?)
      end
      expect(provider.report(kind: 'batch_operations', operations: operations)).to eq(test_case.fetch('expected'))
    end
  end
end
