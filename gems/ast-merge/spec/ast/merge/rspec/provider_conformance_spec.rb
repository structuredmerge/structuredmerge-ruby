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

  it 'covers and advertises all 21 tested providers' do
    matrix = described_class.new(fixture).validate!

    expect(matrix.advertised_provider_ids).to eq(
      %w[ruby.bash ruby.binary ruby.dotenv ruby.go ruby.html ruby.json ruby.markdown ruby.markdown.commonmarker
         ruby.markdown.kramdown ruby.markdown.markly ruby.rbs ruby.ruby ruby.ruby.prism ruby.rust ruby.text ruby.toml
         ruby.toml.citrus ruby.toml.parslet ruby.typescript ruby.yaml.psych ruby.zip]
    )
    expect(matrix.blocked_provider_ids).to eq(%w[ruby.yaml])
    expect(
      matrix.tested?(
        provider_id: 'ruby.bash',
        dialect: :bash,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
    {
      'ruby.markdown' => [:'kreuzberg-language-pack', %i[markdown]],
      'ruby.markdown.commonmarker' => [:commonmarker, %i[markdown commonmark]],
      'ruby.markdown.kramdown' => [:kramdown, %i[markdown kramdown]],
      'ruby.markdown.markly' => [:markly, %i[markdown commonmark]]
    }.each do |provider_id, (backend, dialects)|
      dialects.each do |dialect|
        expect(
          matrix.tested?(
            provider_id: provider_id,
            dialect: dialect,
            backend: backend,
            profile_id: :source_preserving
          )
        ).to be(true)
      end
    end
    expect(
      matrix.tested?(
        provider_id: 'ruby.html',
        dialect: :html,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.rust',
        dialect: :rust,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.go',
        dialect: :go,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
    %i[typescript tsx].each do |dialect|
      expect(
        matrix.tested?(
          provider_id: 'ruby.typescript',
          dialect: dialect,
          backend: :'kreuzberg-language-pack',
          profile_id: :source_preserving
        )
      ).to be(true)
    end
    expect(
      matrix.tested?(
        provider_id: 'ruby.rbs',
        dialect: :rbs,
        backend: :rbs,
        profile_id: :source_preserving
      )
    ).to be(true)
    expect(
      matrix.tested?(
        provider_id: 'ruby.toml',
        dialect: :toml,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving
      )
    ).to be(true)
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
        backend: :tslp,
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
