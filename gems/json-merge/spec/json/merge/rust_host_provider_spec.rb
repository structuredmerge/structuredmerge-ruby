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
                      'owners' => [{
                        'path' => '/answer',
                        'owner_kind' => 'member',
                        'match_key' => 'answer',
                        'source_fragment' => '"answer": 42'
                      }]
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
    expect(analysis.dig(:analysis, :declarations, 0, :line_range)).to eq([1, 1])
    expect(merge2).to include(ok: true, operation: :merge2, output: '{"answer": 42}\n')
    expect(merge3).to include(ok: true, operation: :merge3, output: '{"answer": 42}\n')
  end

  it 'preserves native semantic results across the JSON-family dialects', not_rust_tslp_backend: true do
    skip 'compiled Rust host unavailable' unless described_class.available?

    sources = {
      json: {
        base: "{\"stable\": true}\n",
        ours: "{\"stable\": true, \"ours\": 1}\n",
        theirs: "{\"stable\": true, \"theirs\": 2}\n"
      },
      jsonc: {
        base: "// base\n{\n  \"stable\": true,\n}\n",
        ours: "// ours\n{\n  \"stable\": true,\n  \"ours\": 1,\n}\n",
        theirs: "// theirs\n{\n  \"stable\": true,\n  \"theirs\": 2,\n}\n"
      },
      json5: {
        base: "{\n  stable: true,\n}\n",
        ours: "{\n  stable: true,\n  ours: 1,\n}\n",
        theirs: "{\n  stable: true,\n  theirs: 2,\n}\n"
      }
    }

    sources.each do |dialect, source_set|
      analysis = provider.analyze(source: source_set.fetch(:ours), dialect: dialect)
      result = provider.merge3(
        base_source: source_set.fetch(:base),
        ours_source: source_set.fetch(:ours),
        theirs_source: source_set.fetch(:theirs),
        dialect: dialect
      )

      expect(analysis).to include(ok: true, operation: :analyze)
      expect(analysis.dig(:analysis, :declarations)).not_to be_empty
      expect(result).to include(ok: true, operation: :merge3)
      expect(
        Json::Merge.json_value_for_source(
          result.fetch(:output),
          dialect: dialect,
          backend: 'kreuzberg-language-pack'
        )
      ).to eq(
        'stable' => true,
        'ours' => 1,
        'theirs' => 2
      )
    end
  end

  it 'matches native merge status and semantic output for exact and conflicting revisions',
     not_rust_tslp_backend: true do
    skip 'compiled Rust host unavailable' unless described_class.available?

    cases = [
      {
        name: :exact_theirs,
        base: "{\"stable\": true}\n",
        ours: "{\"stable\": true}\n",
        theirs: "{\"stable\": true, \"theirs\": 2}\n"
      },
      {
        name: :independent_additions,
        base: "{\"stable\": true}\n",
        ours: "{\"stable\": true, \"ours\": 1}\n",
        theirs: "{\"stable\": true, \"theirs\": 2}\n"
      },
      {
        name: :conflicting_revisions,
        base: "{\"value\": 0}\n",
        ours: "{\"value\": 1}\n",
        theirs: "{\"value\": 2}\n"
      }
    ]

    native_provider = Json::Merge::Provider.new
    cases.each do |example|
      native = native_provider.merge3(
        base_source: example.fetch(:base),
        ours_source: example.fetch(:ours),
        theirs_source: example.fetch(:theirs),
        dialect: :json,
        backend: 'kreuzberg-language-pack'
      )
      rust = provider.merge3(
        base_source: example.fetch(:base),
        ours_source: example.fetch(:ours),
        theirs_source: example.fetch(:theirs),
        dialect: :json
      )

      expect(rust.fetch(:ok)).to eq(native.fetch(:ok))
      next unless native.fetch(:ok)

      rust_value = Json::Merge.json_value_for_source(
        rust.fetch(:output), dialect: :json, backend: 'kreuzberg-language-pack'
      )
      native_value = Json::Merge.json_value_for_source(
        native.fetch(:output), dialect: :json, backend: 'kreuzberg-language-pack'
      )
      expect(rust_value).to eq(native_value)
    end
  end
end
