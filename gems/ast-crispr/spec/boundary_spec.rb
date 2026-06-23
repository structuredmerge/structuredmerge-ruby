# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ast::Crispr do
  it 'conforms to the ast-crispr package boundary fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-916-ast-crispr-package-boundary',
      'ast-crispr-package-boundary.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    expect(described_class.boundary_report).to eq(fixture.fetch(:boundary))
    expect(described_class.ast_merge_contract_anchor).to eq('Ast::Merge.structured_edit')
  end
end

RSpec.describe Ast::Crispr::MatchProfile do
  it 'conforms to the ast-crispr match profile helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-918-ast-crispr-match-profile-helpers',
      'ast-crispr-match-profile-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      profile = described_class.new(**test_case.fetch(:profile))
      expect(profile.report).to eq(test_case.fetch(:expected))
    end
  end
end

RSpec.describe Ast::Crispr::Limit do
  it 'conforms to the ast-crispr limit helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-917-ast-crispr-limit-helpers',
      'ast-crispr-limit-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      limit = described_class.new(test_case[:spec])
      expect(limit.describe).to eq(test_case[:expected_description])
      test_case.fetch(:expectations).each do |expectation|
        expect(limit.allows?(expectation[:count])).to eq(expectation[:allowed])
      end
    end

    fixture.fetch(:invalid_cases).each do |test_case|
      expect { described_class.new(test_case[:spec]) }
        .to raise_error(Ast::Crispr::Error) { |error| expect(error.code).to eq(test_case[:expected_error]) }
    end
  end
end

RSpec.describe Ast::Crispr::SelectionProfile do
  it 'conforms to the ast-crispr selection profile helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-919-ast-crispr-selection-profile-helpers',
      'ast-crispr-selection-profile-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      profile = described_class.new(**test_case.fetch(:profile))
      expect(profile.report).to eq(test_case.fetch(:expected))
    end
  end
end

RSpec.describe Ast::Crispr::DestinationProfile do
  it 'conforms to the ast-crispr destination profile helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-920-ast-crispr-destination-profile-helpers',
      'ast-crispr-destination-profile-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      profile = described_class.new(**test_case.fetch(:profile))
      expect(profile.report).to eq(test_case.fetch(:expected))
    end
  end
end

RSpec.describe Ast::Crispr::OperationProfile do
  it 'conforms to the ast-crispr operation profile helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-921-ast-crispr-operation-profile-helpers',
      'ast-crispr-operation-profile-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      profile = described_class.new(**test_case.fetch(:profile))
      expect(profile.report).to eq(test_case.fetch(:expected))
    end
  end
end

RSpec.describe 'Ast::Crispr operation helpers' do
  it 'conforms to the ast-crispr operation helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-922-ast-crispr-operation-helpers',
      'ast-crispr-operation-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    helpers = {
      replace: Ast::Crispr.method(:replace_operation),
      delete: Ast::Crispr.method(:delete_operation),
      insert: Ast::Crispr.method(:insert_operation),
      move: Ast::Crispr.method(:move_operation)
    }

    fixture.fetch(:cases).each do |test_case|
      profile = helpers.fetch(test_case.fetch(:helper).to_sym).call
      expect(profile.report).to eq(test_case.fetch(:expected_operation_profile))
    end
  end
end

RSpec.describe 'Ast::Crispr batch operation helpers' do
  it 'conforms to the ast-crispr batch operation helper fixture' do
    fixture_path = Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-923-ast-crispr-batch-operation-helpers',
      'ast-crispr-batch-operation-helpers.json'
    )
    fixture = JSON.parse(fixture_path.read, symbolize_names: true)

    helpers = {
      replace: Ast::Crispr.method(:replace_operation),
      delete: Ast::Crispr.method(:delete_operation),
      insert: Ast::Crispr.method(:insert_operation),
      move: Ast::Crispr.method(:move_operation)
    }

    fixture.fetch(:cases).each do |test_case|
      profiles = test_case.fetch(:helpers).map { |helper| helpers.fetch(helper.to_sym).call }
      expect(Ast::Crispr.batch_operation_report(profiles)).to eq(test_case.fetch(:expected))
    end
  end
end
