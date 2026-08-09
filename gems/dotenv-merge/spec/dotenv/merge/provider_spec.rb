# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider contract and adversarial three-way cases share one fixture surface
RSpec.describe Dotenv::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) { "# retained\nA=base\nB=base\n" }
  let(:ours) { "# retained\nA=ours\nB=base\nOURS=left\n" }
  let(:theirs) { "# retained\nA=base\nB=theirs\nTHEIRS=right\n" }

  it 'advertises the exact dotenv-line workflow selector' do
    expect(provider).to have_attributes(provider_id: 'ruby.dotenv', family: 'dotenv')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[dotenv],
      backends: [:'dotenv-line'],
      profiles: %i[source_preserving],
      role: :workflow
    )
  end

  it 'auto-registers when dotenv/merge is required' do
    resolved = Ast::Merge.resolve_provider(
      provider_id: 'ruby.dotenv',
      family: :dotenv,
      operation: :merge3,
      dialect: :dotenv,
      backend: :'dotenv-line',
      profile_id: :source_preserving
    )

    expect(resolved).to equal(Dotenv::Merge.merge_provider)
  end

  it 'analyzes assignments with key, value, export, comments, and backend identity' do
    result = provider.analyze(source: "# heading\nexport TOKEN='a#b' # literal\nEMPTY=\n")

    expect(result).to include(ok: true, operation: :analyze)
    expect(result.dig(:analysis, :backend)).to eq('dotenv-line')
    expect(result.dig(:analysis, :assignments)).to eq(
      [
        { key: 'TOKEN', value: "'a#b'", export: true },
        { key: 'EMPTY', value: '', export: false }
      ]
    )
    expect(result.dig(:analysis, :comment_support_style, :available)).to be(true)
  end

  it 'returns exact one-sided revision bytes after structural analysis' do
    winner = "# exact\r\nexport A = \"theirs\"\r\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: winner)

    expect(result).to include(ok: true, output: winner)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.dig(:verification, :source_role)).to eq(:theirs)
  end

  it 'combines independent edits and additions in ours order then theirs-only order' do
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(
      ok: true,
      output: "# retained\nA=ours\nB=theirs\nOURS=left\nTHEIRS=right\n"
    )
    expect(result.dig(:render_report, :strategy)).to eq(:exact_assignment_composite)
    expect(result.dig(:verification, :assignment_sources)).to eq(
      [
        { key: 'A', source_role: :ours, source_line: 2 },
        { key: 'B', source_role: :theirs, source_line: 3 },
        { key: 'OURS', source_role: :ours, source_line: 4 },
        { key: 'THEIRS', source_role: :theirs, source_line: 4 }
      ]
    )
  end

  it 'combines an independent deletion with an independent edit' do
    result = provider.merge3(
      base_source: "DELETE=1\nEDIT=base\nKEEP=1\n",
      ours_source: "EDIT=base\nKEEP=1\n",
      theirs_source: "DELETE=1\nEDIT=theirs\nKEEP=1\n"
    )

    expect(result).to include(ok: true, output: "EDIT=theirs\nKEEP=1\n")
  end

  it 'adds a line boundary only when exact fragments require one' do
    result = provider.merge3(
      base_source: "A=1\n",
      ours_source: "A=1\nOURS=1",
      theirs_source: "A=1\nTHEIRS=1\n"
    )

    expect(result).to include(ok: true, output: "A=1\nOURS=1\nTHEIRS=1\n")
    expect(result.dig(:render_report, :synthesized_fragments)).to include(
      hash_including(reason: :assignment_separator)
    )
  end

  it 'localizes divergent same-key source edits' do
    result = provider.merge3(
      base_source: "STABLE=1\nVALUE=base\nTAIL=1\n",
      ours_source: "STABLE=1\nVALUE=ours # left\nTAIL=1\n",
      theirs_source: "STABLE=1\nexport VALUE=theirs\nTAIL=1\n"
    )

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:conflicted_output)).to start_with("STABLE=1\n<<<<<<< ours\n")
    expect(result.fetch(:conflicted_output)).to end_with(">>>>>>> theirs\nTAIL=1\n")
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: '/assignments/VALUE')
    )
    expect(result.dig(:render_report, :strategy)).to eq(:assignment_localized_conflict)
  end

  it 'serializes non-addressable delete/edit conflicts as public conflict records' do
    result = provider.merge3(
      base_source: "VALUE=base\n",
      ours_source: '',
      theirs_source: "VALUE=theirs\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :delete_edit, path: '/assignments/VALUE')
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'fails conservatively on duplicate keys but permits an exact one-sided winner' do
    duplicate = "A=1\nA=2\n"
    exact = provider.merge3(base_source: duplicate, ours_source: duplicate, theirs_source: "A=3\n")
    ambiguous = provider.merge3(
      base_source: duplicate,
      ours_source: "A=1\nA=ours\n",
      theirs_source: "A=1\nA=theirs\n"
    )

    expect(exact).to include(ok: true, output: "A=3\n")
    expect(exact.fetch(:diagnostics)).to include(hash_including(category: :duplicate_key, source_role: :base))
    expect(ambiguous).to include(ok: false)
    expect(ambiguous.fetch(:diagnostics)).to include(
      hash_including(category: :duplicate_key, source_role: :ours)
    )
  end

  it 'rejects an ambiguous exact winner after structural validation' do
    invalid = "not an assignment\n"
    result = provider.merge3(base_source: "A=1\n", ours_source: invalid, theirs_source: invalid)

    expect(result).to include(ok: false)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :invalid_line, source_role: :ours)
    )
  end

  it 'fails conservatively on invalid lines and freeze ambiguity with source roles' do
    invalid = provider.merge3(
      base_source: "A=1\n",
      ours_source: "not an assignment\nA=ours\n",
      theirs_source: "A=theirs\n"
    )
    frozen = provider.merge3(
      base_source: "A=1\n",
      ours_source: "# dotenv-merge:freeze\nA=ours\n",
      theirs_source: "A=theirs\n"
    )

    expect(invalid).to include(ok: false)
    expect(invalid.fetch(:diagnostics)).to include(
      hash_including(category: :invalid_line, source_role: :ours)
    )
    expect(frozen).to include(ok: false)
    expect(frozen.fetch(:diagnostics)).to include(
      hash_including(category: :freeze_ambiguity, source_role: :ours)
    )
  end

  it 'conflicts instead of dropping independently changed unowned comments' do
    result = provider.merge3(
      base_source: "# base\nA=1\n",
      ours_source: "# ours\nA=1\n",
      theirs_source: "# base\nA=2\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :unmanaged_source_change)
    )
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'conflicts when unmanaged source moves across a stable assignment anchor' do
    result = provider.merge3(
      base_source: "# owned layout\nA=1\nB=1\n",
      ours_source: "A=1\n# owned layout\nB=ours\n",
      theirs_source: "# owned layout\nA=theirs\nB=1\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :unmanaged_source_change)
    )
  end

  it 'rejects structurally ambiguous merge2 inputs with source attribution' do
    result = provider.merge2(
      current_source: "A=1\n",
      incoming_source: "not an assignment\nA=2\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :invalid_line, source_role: :incoming)
    )
  end
end

RSpec.describe 'Dotenv::Merge provider conformance' do
  subject(:provider) { Dotenv::Merge.merge_provider }

  def parsed_assignments(source)
    Dotenv::Merge::FileAnalysis.new(source).all_assignments.map do |line|
      [line.key, line.value, line.export?]
    end
  end

  let(:stable) { "STABLE=1\n" }
  let(:ours_add) { "STABLE=1\nOURS=left\n" }
  let(:theirs_add) { "STABLE=1\nTHEIRS=right\n" }
  let(:provider_conformance) do
    {
      dialect: :dotenv,
      backend: :'dotenv-line',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: ours_add },
        merge2: { current_source: ours_add, incoming_source: theirs_add },
        merge3: { base_source: stable, ours_source: ours_add, theirs_source: theirs_add }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "invalid line\nOURS=left\n",
        theirs_source: theirs_add,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "OBSOLETE=1\nSTABLE=1\n",
          ours_source: "OBSOLETE=1\nSTABLE=1\n",
          theirs_source: stable
        },
        expected_value: parsed_assignments(stable)
      },
      parse_output: method(:parsed_assignments)
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
