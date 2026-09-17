# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Json::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before(:context) do
    if File.basename(ENV.fetch('BUNDLE_GEMFILE', '')) == 'typed_core.gemfile' && !Json::Merge::RustHostProvider.available?
      raise 'The typed-core artifact test bundle must load structuredmerge-core'
    end
  end

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

  it 'maps real typed analysis and merges without the prototype adapter' do
    skip 'compiled typed core unavailable' unless described_class.available?

    expect(described_class.ancestors).not_to include(Ast::Merge::RustHostProvider)
    analysis = provider.analyze(source: '{"answer": 42}', dialect: :json)
    merge2 = provider.merge2(
      incoming_source: '{"answer": 42}',
      current_source: '{"answer": 1}',
      dialect: :json
    )
    merge3 = provider.merge3(
      base_source: '{"answer": 1}',
      ours_source: '{"answer": 42}',
      theirs_source: '{"answer": 42}',
      dialect: :json
    )

    expect(analysis).to include(ok: true, operation: :analyze)
    expect(analysis.dig(:analysis, :declarations)).to include(hash_including(path: '/answer', line_range: [1, 1]))
    expect(analysis.fetch(:typed_result)).to include(schema: Ast::Merge::ProviderContract::RESULT_SCHEMA, ok: true)
    expect(merge2).to include(ok: true, operation: :merge2, output: '{"answer": 1}')
    expect(merge3).to include(ok: true, operation: :merge3, output: '{"answer": 42}')
    expect(merge2.dig(:verification, :directional_roles_preserved)).to be(true)
    expect(merge3.dig(:verification, :output_reparsed)).to be(true)
  end

  it 'uses Rust classifications and native spans for repeated nested fragments' do
    skip 'compiled typed core unavailable' unless described_class.available?

    before = "{\"é\":0,\n \"a\":{\"x\":1},\n \"b\":{\"x\":1}\n}"
    after = "{\"é\":0,\n \"a\":{\"x\":1},\n \"b\":{\"x\":2}\n}"
    result = provider.diff2(before_source: before, after_source: after, dialect: :json)
    expect(result).to include(ok: true)
    change = result.fetch(:changes).find { |entry| entry[:path] == '/b/x' }
    expect(change).to include(change: :edited, before: hash_including(line_range: [3, 3]), after: hash_including(line_range: [3, 3]))
    expect(result.fetch(:changes).map { |entry| entry[:path] }).not_to include('/a/x')
    expect(Ast::Merge::ProviderContract.validate_result!(:diff2, result)).to include(ok: true)
    expect(Gem.loaded_specs.keys).not_to include('structuredmerge_host_prototype')
  end

  it 'rejects unsupported constraints instead of silently dropping them' do
    result = provider.analyze(source: '{}', dialect: :json, arbitrary_policy: true)
    expect(result).to include(ok: false)
    expect(result.fetch(:diagnostics).first).to include(category: :unsupported_capability)
  end

  it 'round trips deterministic portable results and retains document-only changes' do
    skip 'compiled typed core unavailable' unless described_class.available?

    request = { before_source: '{}', after_source: "{}\r\n", dialect: :json }
    first = provider.diff2(request)
    second = provider.diff2(request)
    expect(JSON.generate(first)).to eq(JSON.generate(second))
    expect(JSON.parse(JSON.generate(first)).fetch('ok')).to be(true)
    expect(first.fetch(:changes)).to contain_exactly(hash_including(subject_ref: 'json.document', change: :edited))
  end

  it 'preserves conflict evidence, invalid-input diagnostics and binary UTF-8 bytes' do
    skip 'compiled typed core unavailable' unless described_class.available?

    conflict = provider.merge3(base_source: '{"x":1}', ours_source: '{"x":2}', theirs_source: '{"x":3}', dialect: :json)
    expect(conflict).to include(ok: false, output: nil)
    expect(conflict.fetch(:conflicts).length).to eq(1)
    expect(conflict.dig(:typed_result, :conflicts, 0, :canonical, :alternatives).length).to eq(3)
    expect(JSON.generate(conflict)).not_to include('#<StructuredmergeCore::')
    invalid = provider.analyze(source: '{', dialect: :json)
    expect(invalid).to include(ok: false)
    expect(invalid.fetch(:diagnostics)).not_to be_empty
    bytes = '{"é":1}'.b
    expect(provider.analyze(source: bytes, dialect: :json)).to include(ok: true)
    expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)
    expect(provider.analyze(source: "\xFF".b, dialect: :json)).to include(ok: false)
  end

  it 'preserves native semantic results across the JSON-family dialects' do
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

  it 'matches native merge status and semantic output for exact and conflicting revisions' do
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
