# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- The exact canonical summary is intentionally asserted as one contract.
RSpec.describe Ast::Merge::PortableBenchmarkContract do
  subject(:consume) { described_class.parse(JSON.generate(contract)) }

  let(:fixture_path) do
    Pathname(__dir__).join(
      '..',
      '..',
      '..',
      '..',
      'fixtures',
      'diagnostics',
      'slice-1022-portable-benchmark-contract',
      'contract.json'
    ).expand_path
  end
  let(:fixture_source) { fixture_path.binread }
  let(:contract) { JSON.parse(fixture_source) }

  let(:expected_summary) do
    {
      'schema' => 'structuredmerge.benchmark/v1',
      'counts' => {
        'adapters' => 2,
        'cases' => 6,
        'results' => 7,
        'selected_cases' => 5,
        'score_eligible_results' => 5,
        'quality_denominator_excluded_results' => 2,
        'eligible_false_auto_merges' => 1
      },
      'case_ids_by_operation' => {
        'diff' => ['case.diff.json.object-update.v1'],
        'merge2' => ['case.merge2.json.current-owned-fields.v1'],
        'merge3' => [
          'case.merge3.json.independent-fields.v1',
          'case.merge3.json.region-conflict.v1'
        ],
        'history_replay' => ['case.history.ruby.release-events-dotenv-provider.v1'],
        'metamorphic' => ['case.metamorphic.json.reorder-format.v1']
      },
      'case_ids_by_partition' => {
        'sentinel' => ['case.diff.json.object-update.v1'],
        'gold' => [
          'case.merge2.json.current-owned-fields.v1',
          'case.merge3.json.independent-fields.v1',
          'case.merge3.json.region-conflict.v1'
        ],
        'metamorphic' => ['case.metamorphic.json.reorder-format.v1'],
        'history' => ['case.history.ruby.release-events-dotenv-provider.v1'],
        'holdout' => []
      },
      'score_eligible_result_ids' => [
        'result.base.clean.false-conflict',
        'result.base.conflict.true',
        'result.candidate.clean.correct',
        'result.candidate.conflict.false-auto-merge',
        'result.candidate.diff.error'
      ],
      'quality_denominator_excluded_result_ids' => [
        'result.candidate.history.excluded-ambiguous',
        'result.candidate.metamorphic.unsupported'
      ],
      'false_auto_merges' => [
        { 'id' => 'result.candidate.conflict.false-auto-merge', 'severity' => 'critical' }
      ],
      'safety_gate' => {
        'status' => 'fail',
        'eligible_false_auto_merge_count' => 1,
        'non_compensable' => true
      },
      'selection_reason_categories' => %w[
        budget_exceed
        changed_paths
        direct_cases
        inferred_capabilities
        neighbor_samples
        sentinels
      ],
      'contract_digest' => 'cc65ce8cb9312e1487fbde257bb80ae53169da6c5e23299957af653af9a616a8'
    }
  end

  it 'parses and deterministically summarizes the exact shared contract bytes' do
    consumer = described_class.load_file(fixture_path)

    expect(consumer.canonical_summary).to eq(expected_summary)
    expect(consumer.contract_digest).to eq(expected_summary.fetch('contract_digest'))
  end

  it 'rejects a bad inline digest' do
    contract.dig('cases', 0, 'inputs', 'before')['sha256'] = '0' * 64

    expect { consume }.to raise_error(described_class::ValidationError, /SHA-256 does not match exact bytes/)
  end

  it 'rejects a duplicate case ID' do
    contract['cases'][1]['id'] = contract['cases'][0]['id']

    expect { consume }.to raise_error(described_class::ValidationError, /duplicate case ID/)
  end

  it 'rejects a dangling result case reference' do
    contract['case_results'][0]['case_id'] = 'case.missing'

    expect { consume }.to raise_error(described_class::ValidationError, /case_id is dangling/)
  end

  it 'rejects an eligible excluded result' do
    excluded = contract['case_results'].find { |result| result['outcome'] == 'excluded_ambiguous' }
    excluded['score_eligible'] = true

    expect { consume }.to raise_error(described_class::ValidationError, /score eligibility conflicts/)
  end

  it 'rejects a compensable false auto-merge' do
    false_auto_merge = contract['case_results'].find { |result| result['outcome'] == 'false_auto_merge' }
    false_auto_merge.dig('dimensions', 'safety')['compensable'] = true

    expect { consume }.to raise_error(described_class::ValidationError, /cannot be compensable/)
  end

  it 'rejects an LLM oracle participating in a micro hard gate' do
    contract['run_manifest']['profile'] = 'micro'
    contract['cases'][0]['oracle']['class'] = 'llm'

    expect do
      consume
    end.to raise_error(described_class::ValidationError, /LLM oracle cannot participate in micro hard gates/)
  end
end
# rubocop:enable Metrics/BlockLength
