# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

RSpec.describe Ast::Merge::RSpec::ProviderConformance do
  it 'fails a provider that attests base participation but substitutes a two-way result' do
    provider = Object.new
    provider.define_singleton_method(:merge3) do |_request|
      Ast::Merge::ProviderResult.build(
        operation: :merge3,
        success: true,
        envelope: { verification: { base_participated: true } },
        output: '{"obsolete":true,"stable":true}'
      )
    end
    proof = described_class.new(
      provider: provider,
      request: {
        base_source: '{"obsolete":true,"stable":true}',
        ours_source: '{"obsolete":true,"stable":true}',
        theirs_source: '{"stable":true}'
      },
      parse_output: ->(source) { JSON.parse(source) },
      expected_value: { 'stable' => true }
    ).call

    expect(proof.passed).to be(false)
    expect(proof.actual_value).to include('obsolete' => true)
  end
end

# rubocop:disable Metrics/BlockLength -- matrix coverage and advertising assertions share one fixture
RSpec.describe Ast::Merge::RSpec::ProviderConformanceMatrix do
  def fixture
    root = Pathname(__dir__).join('..', '..', '..', '..', '..', '..', '..', 'fixtures').expand_path
    JSON.parse(
      root
        .join('diagnostics', 'slice-1018-uniform-merge-provider-contract', 'uniform-merge-provider-contract.json')
        .read,
      symbolize_names: true
    )
  end

  it 'covers all 22 providers while advertising only tested rows' do
    matrix = described_class.new(fixture).validate!

    expect(matrix.advertised_provider_ids).to eq(
      %w[ruby.binary ruby.dotenv ruby.json ruby.ruby ruby.ruby.prism ruby.text ruby.toml.citrus ruby.toml.parslet
         ruby.yaml ruby.yaml.psych ruby.zip]
    )
    expect(matrix.blocked_provider_ids.length).to eq(11)
    expect(
      matrix.tested?(
        provider_id: 'ruby.toml.citrus',
        dialect: :toml,
        backend: :citrus,
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.toml.parslet',
        dialect: :toml,
        backend: :parslet,
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.yaml',
        dialect: :yaml,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.json',
        dialect: :json5,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.ruby',
        dialect: :ruby,
        backend: :prism,
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.ruby.prism',
        dialect: :ruby,
        backend: :prism,
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.yaml.psych',
        dialect: :yaml,
        backend: :psych,
        profile_id: :source_preserving
      )
    ).to be(true)
  end
end
# rubocop:enable Metrics/BlockLength
