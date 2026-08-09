# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength -- all portable provider operations share one fixture surface
RSpec.describe Json::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~JSON
      {
        "shared": true
      }
    JSON
  end
  let(:ours) do
    <<~JSON
      {
        "shared": true,
        "ours": 1
      }
    JSON
  end
  let(:theirs) do
    <<~JSON
      {
        "shared": true,
        "theirs": 2
      }
    JSON
  end

  it 'exposes the complete portable provider capabilities' do
    expect(provider.provider_id).to eq('ruby.json')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[json jsonc json5],
      role: :workflow
    )
  end

  it 'analyzes a selected JSON-family dialect' do
    result = provider.analyze(source: "// retained\n{\"value\": true,}\n", dialect: :jsonc)

    expect(result).to include(ok: true, operation: :analyze)
    expect(result.dig(:analysis, :dialect)).to eq('jsonc')
  end

  it 'reports semantic two-way changes' do
    result = provider.diff2(
      before_source: '{"value": 1}',
      after_source: '{"value": 2}',
      dialect: :json
    )

    expect(result).to include(ok: true, operation: :diff2)
    expect(result.fetch(:changes)).to contain_exactly(
      { path: '/value', ours: :unchanged, theirs: :edited }
    )
  end

  it 'preserves the existing source-aware merge2 path' do
    result = provider.merge2(
      incoming_source: "{\"incoming\": true}\n",
      current_source: "// retained\n{\"current\": true,}\n",
      dialect: :jsonc
    )

    expect(result).to include(ok: true, operation: :merge2)
    expect(result.fetch(:output)).to include('// retained', '"incoming": true', '"current": true')
    expect(result.dig(:verification, :output_reparsed)).to be(true)
  end

  it 'reports invalid merge2 emitter output as a structured failure' do
    allow(Json::Merge).to receive(:merge_json).and_return(ok: true, output: '{broken')

    result = provider.merge2(
      incoming_source: '{"incoming": true}',
      current_source: '{"current": true}',
      dialect: :json
    )

    expect(result).to include(ok: false, operation: :merge2)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :render_failure, message: /emitter produced invalid output/)
    )
  end

  it 'returns an exact revision when only theirs changed' do
    result = provider.merge3(
      base_source: base,
      ours_source: base,
      theirs_source: theirs,
      dialect: :json
    )

    expect(result).to include(ok: true, operation: :merge3, output: theirs)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.dig(:verification, :base_participated)).to be(true)
  end

  it 'synthesizes and verifies independent JSON object additions' do
    result = provider.merge3(
      base_source: base,
      ours_source: ours,
      theirs_source: theirs,
      dialect: :json
    )

    expect(result).to include(ok: true, operation: :merge3)
    expect(Json::Merge.json_value_for_source(result.fetch(:output))).to eq(
      'shared' => true,
      'ours' => 1,
      'theirs' => 2
    )
    expect(result.dig(:render_report, :strategy)).to eq(:family_composite)
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'preserves JSONC comments while synthesizing independent additions' do
    result = provider.merge3(
      base_source: "// base\n{\"shared\": true,}\n",
      ours_source: "// ours retained\n{\"shared\": true, \"ours\": 1,}\n",
      theirs_source: "// theirs retained\n{\"shared\": true, \"theirs\": 2,}\n",
      dialect: :jsonc
    )

    expect(result).to include(ok: true, operation: :merge3)
    expect(result.fetch(:output)).to include('// ours retained')
    expect(result.fetch(:output)).to include('"ours": 1', '"theirs": 2')
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'returns explicit full-file conflicts with source provenance' do
    result = provider.merge3(
      base_source: "{\"value\": 0}\n",
      ours_source: "{\"value\": 1}\n",
      theirs_source: "{\"value\": 2}\n",
      dialect: :json
    )

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicted_output)).to include(
      '<<<<<<< ours',
      '||||||| base',
      '=======',
      '>>>>>>> theirs'
    )
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: '/value')
    )
  end

  it 'identifies the source role for parse failures' do
    result = provider.merge3(
      base_source: base,
      ours_source: '{broken',
      theirs_source: theirs,
      dialect: :json
    )

    expect(result).to include(ok: false, operation: :merge3, source_role: :ours)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, message: /ours parse error/)
    )
  end
end
# rubocop:enable Metrics/BlockLength
