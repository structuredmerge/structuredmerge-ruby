# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Json::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  it 'advertises all JSON-family dialects through the Rust host contract' do
    expect(provider.provider_id).to eq('rust.json')
    expect(provider.family).to eq('json')
    expect(provider.capabilities).to include(
      dialects: %i[json jsonc json5],
      backends: [:rust_tslp]
    )
  end

  it 'validates the opt-in provider contract without loading native JSON defaults' do
    registration = Ast::Merge::ProviderContract.validate_provider!(provider)

    expect(registration).to include(
      provider_id: 'rust.json',
      family: :json,
      capabilities: hash_including(
        operations: %i[analyze diff2 merge2 merge3],
        dialects: %i[json jsonc json5],
        backends: [:rust_tslp],
        role: :workflow
      )
    )
  end

  it 'resolves through the shared registry when the Rust backend is selected' do
    registry = Ast::Merge::ProviderRegistry.new
    registry.register(provider)

    expect(
      registry.resolve(
        family: :json,
        dialect: :json5,
        backend: :rust_tslp,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(provider)
  end

  it 'maps the Rust host analysis and source-preserving merge envelopes' do
    stub_const('StructuredmergeHostPrototype', Module.new)
    allow(StructuredmergeHostPrototype).to receive(:parse_json_analysis)
      .and_return(JSON.generate(
                    'ok' => true,
                    'analysis' => {
                      'dialect' => 'json',
                      'owners' => [{ 'path' => '/answer', 'owner_kind' => 'member', 'match_key' => 'answer' }]
                    },
                    'diagnostics' => []
                  ))
    allow(StructuredmergeHostPrototype).to receive(:merge_json_two_way)
      .and_return(JSON.generate('ok' => true, 'output' => '{"answer": 42}\n', 'diagnostics' => []))
    allow(StructuredmergeHostPrototype).to receive(:merge_json_three_way)
      .and_return(JSON.generate('outcome' => 'clean', 'output' => '{"answer": 42}\n', 'diagnostics' => []))

    analysis = provider.analyze(source: '{"answer": 42}\n', dialect: :json)
    merge2 = provider.merge2(
      incoming_source: '{"answer": 42}\n',
      current_source: '{"answer": 1}\n',
      dialect: :json
    )
    merge3 = provider.merge3(
      base_source: '{"answer": 1}\n',
      ours_source: '{"answer": 42}\n',
      theirs_source: '{"answer": 42}\n',
      dialect: :json
    )

    expect(analysis).to include(ok: true, operation: :analyze)
    expect(analysis.dig(:analysis, :declarations, 0, :path)).to eq('[:member, "answer"]')
    expect(merge2).to include(ok: true, operation: :merge2, output: '{"answer": 42}\n')
    expect(merge3).to include(ok: true, operation: :merge3, output: '{"answer": 42}\n')
  end
end
