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

  it 'registers as the JSON-family workflow provider after dialect conformance loads' do
    Json::Merge.register_provider!(replace: true)
    resolved = Ast::Merge.resolve_provider(
      family: :json,
      operation: :merge3,
      dialect: :json5,
      backend: provider.capabilities.fetch(:backends).first,
      profile_id: :source_preserving
    )

    expect(resolved).to equal(Json::Merge.merge_provider)
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

  it 'falls back to exact owner replacement when two-way synthesis would restore a three-way deletion' do
    result = provider.merge3(
      base_source: "{\n  \"remove\": true,\n  \"value\": 0\n}\n",
      ours_source: "{\n  \"value\": 0\n}\n",
      theirs_source: "{\n  \"remove\": true,\n  \"value\": 1\n}\n",
      dialect: :json
    )

    expect(result).to include(ok: true, operation: :merge3)
    expect(result.fetch(:output)).to eq("{\n  \"value\": 1\n}\n")
    expect(result.dig(:render_report, :strategy)).to eq(:exact_owner_composite)
    expect(result.fetch(:fallbacks)).to contain_exactly(
      hash_including(from: :family_composite, to: :exact_owner_composite)
    )
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'preserves JSON5 key, quote, comment, and trailing-comma syntax' do
    result = provider.merge3(
      base_source: "{\n  stable: 'base',\n}\n",
      ours_source: "{\n  // ours retained\n  stable: 'base',\n  ours: 'left',\n}\n",
      theirs_source: "{\n  stable: 'base',\n  theirs: 'right',\n}\n",
      dialect: :json5
    )

    expect(result).to include(ok: true, operation: :merge3)
    expect(result.fetch(:output)).to include(
      '// ours retained',
      "stable: 'base'",
      "ours: 'left'",
      "theirs: 'right'"
    )
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
    expect(result.fetch(:changes)).to contain_exactly(
      path: '/value',
      ours: :edited,
      theirs: :edited
    )
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    expect(result.fetch(:fallbacks)).to contain_exactly(
      hash_including(to: :full_file_conflict, reason: :owner_not_whole_line_addressable)
    )
  end

  it 'synthesizes explicit line boundaries for conflict sources without final newlines' do
    result = provider.merge3(
      base_source: '{"value":0}',
      ours_source: '{"value":1}',
      theirs_source: '{"value":2}',
      dialect: :json
    )

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicted_output)).to include(
      "<<<<<<< ours\n{\"value\":1}\n||||||| base\n{\"value\":0}\n"
    )
    expect(result.dig(:render_report, :synthesized_fragments)).to include(
      hash_including(reason: :conflict_line_boundary, conflict_side: :ours)
    )
  end

  it 'localizes conflicts to whole-line object-pair owners' do
    result = provider.merge3(
      base_source: "{\n  \"stable\": true,\n  \"value\": 0\n}\n",
      ours_source: "{\n  \"stable\": true,\n  \"value\": 1\n}\n",
      theirs_source: "{\n  \"stable\": true,\n  \"value\": 2\n}\n",
      dialect: :json
    )

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicted_output)).to start_with("{\n  \"stable\": true,\n<<<<<<< ours\n")
    expect(result.fetch(:conflicted_output)).to end_with(">>>>>>> theirs\n}\n")
    expect(result.dig(:render_report, :strategy)).to eq(:owner_localized_conflict)
    expect(result.dig(:render_report, :conflicts, 0, :metadata)).to include(path: '/value')
  end

  it 'localizes delete/edit conflicts with an explicit empty side' do
    result = provider.merge3(
      base_source: "{\n  \"value\": 0,\n  \"stable\": true\n}\n",
      ours_source: "{\n  \"stable\": true,\n  \"ours\": 1\n}\n",
      theirs_source: "{\n  \"value\": 2,\n  \"stable\": true\n}\n",
      dialect: :json
    )

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicted_output)).to include(
      "<<<<<<< ours\n||||||| base\n  \"value\": 0,\n=======\n  \"value\": 2,\n>>>>>>> theirs\n"
    )
    expect(result.fetch(:conflicted_output)).to include('"ours": 1')
    expect(result.dig(:render_report, :strategy)).to eq(:synthesized_owner_localized_conflict)
    expect(result.fetch(:fallbacks)).to contain_exactly(
      hash_including(to: :synthesized_conflict_context, reason: :missing_side_owner)
    )
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :delete_edit, path: '/value')
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

# rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength, Style/HashLikeCase -- dialect fixtures stay explicit
RSpec.describe 'Json::Merge provider conformance' do
  subject(:provider) { Json::Merge.merge_provider }

  def conformance_sources(dialect)
    case dialect
    when :json
      {
        base: "{\"obsolete\": true, \"stable\": true}\n",
        theirs: "{\"stable\": true}\n",
        stable: "{\"stable\": true}\n",
        ours_add: "{\"stable\": true, \"ours\": 1}\n",
        theirs_add: "{\"stable\": true, \"theirs\": 2}\n"
      }
    when :jsonc
      {
        base: "// base\n{\n  \"obsolete\": true,\n  \"stable\": true,\n}\n",
        theirs: "// theirs\n{\n  \"stable\": true,\n}\n",
        stable: "// stable\n{\n  \"stable\": true,\n}\n",
        ours_add: "// ours\n{\n  \"stable\": true,\n  \"ours\": 1,\n}\n",
        theirs_add: "// theirs\n{\n  \"stable\": true,\n  \"theirs\": 2,\n}\n"
      }
    when :json5
      {
        base: "{\n  obsolete: true,\n  stable: 'base',\n}\n",
        theirs: "{\n  stable: 'base',\n}\n",
        stable: "{\n  stable: 'base',\n}\n",
        ours_add: "{\n  stable: 'base',\n  ours: 'left',\n}\n",
        theirs_add: "{\n  stable: 'base',\n  theirs: 'right',\n}\n"
      }
    end
  end

  def conformance_for(dialect)
    sources = conformance_sources(dialect)
    {
      dialect: dialect,
      backend: provider.capabilities.fetch(:backends).first,
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: sources.fetch(:stable) },
        diff2: { before_source: sources.fetch(:stable), after_source: sources.fetch(:ours_add) },
        merge2: { current_source: sources.fetch(:ours_add), incoming_source: sources.fetch(:theirs_add) },
        merge3: {
          base_source: sources.fetch(:stable),
          ours_source: sources.fetch(:ours_add),
          theirs_source: sources.fetch(:theirs_add)
        }
      },
      invalid_merge3: {
        base_source: sources.fetch(:base),
        ours_source: '{broken',
        theirs_source: sources.fetch(:theirs),
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: sources.fetch(:base),
          ours_source: sources.fetch(:base),
          theirs_source: sources.fetch(:theirs)
        },
        expected_value: Json::Merge.json_value_for_source(sources.fetch(:theirs), dialect: dialect)
      },
      synthesized_merge3: {
        request: {
          base_source: sources.fetch(:stable),
          ours_source: sources.fetch(:ours_add),
          theirs_source: sources.fetch(:theirs_add)
        }
      },
      parse_output: lambda { |source|
        Json::Merge.json_value_for_source(source, dialect: dialect)
      }
    }
  end

  %i[json jsonc json5].each do |dialect|
    context "with #{dialect}" do
      let(:provider_conformance) { conformance_for(dialect) }

      it_behaves_like 'Ast::Merge::ProviderConformance'
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength, Style/HashLikeCase
