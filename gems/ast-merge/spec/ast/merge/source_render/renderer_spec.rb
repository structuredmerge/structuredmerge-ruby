# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength -- renderer contract cases share compact fixture helpers
RSpec.describe Ast::Merge::SourceRender::Renderer do
  subject(:renderer) { described_class.new }

  let(:sources) do
    {
      base: "alpha\nshared\nomega\n",
      ours: "alpha ours\nshared\nomega\n",
      theirs: "alpha\nshared\nomega theirs\n"
    }
  end

  def source_fragment(revision, start_line, end_line, **metadata)
    Ast::Merge::SourceRender::SourceFragment.new(
      revision: revision,
      start_line: start_line,
      end_line: end_line,
      metadata: metadata
    )
  end

  it 'copies exact lines from multiple revisions and records provenance' do
    plan = Ast::Merge::SourceRender::Plan.new(
      sources: sources,
      fragments: [
        source_fragment(:ours, 1, 2, owner_id: 'document.head'),
        source_fragment(:theirs, 3, 3, owner_id: 'document.tail')
      ]
    )

    result = renderer.render(plan)

    expect(result.content).to eq("alpha ours\nshared\nomega theirs\n")
    expect(result.line_records).to contain_exactly(
      hash_including(output_line: 1, revision: :ours, original_line: 1, owner_id: 'document.head'),
      hash_including(output_line: 2, revision: :ours, original_line: 2, owner_id: 'document.head'),
      hash_including(output_line: 3, revision: :theirs, original_line: 3, owner_id: 'document.tail')
    )
    expect(result.synthesized_fragments).to be_empty
  end

  it 'reports family-synthesized separators without attributing them to a revision' do
    separator = Ast::Merge::SourceRender::SynthesizedFragment.new(
      content: "\n",
      reason: :separator,
      producer: :'family-profile'
    )
    plan = Ast::Merge::SourceRender::Plan.new(
      sources: sources,
      fragments: [source_fragment(:ours, 1, 1), separator, source_fragment(:theirs, 3, 3)]
    )

    result = renderer.render(plan)

    expect(result.content).to eq("alpha ours\n\nomega theirs\n")
    expect(result.synthesized_fragments).to include(
      hash_including(reason: :separator, producer: :'family-profile')
    )
    expect(result.line_records[1]).to include(
      fragment_kind: :synthesized,
      synthesized_reason: :separator,
      output_line: 2
    )
    expect(result.line_records[1]).not_to have_key(:revision)
  end

  it 'localizes a three-way conflict and retains side provenance' do
    conflict = Ast::Merge::SourceRender::ConflictFragment.new(
      conflict_id: 'owner-shared',
      base: [source_fragment(:base, 2, 2)],
      ours: [
        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "shared ours\n",
          reason: :family_emission,
          producer: :'example-provider'
        )
      ],
      theirs: [
        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "shared theirs\n",
          reason: :family_emission,
          producer: :'example-provider'
        )
      ]
    )
    plan = Ast::Merge::SourceRender::Plan.new(
      sources: sources,
      fragments: [source_fragment(:ours, 1, 1), conflict, source_fragment(:theirs, 3, 3)]
    )

    result = renderer.render(plan)

    expect(result.content).to eq(<<~MERGED)
      alpha ours
      <<<<<<< ours
      shared ours
      ||||||| base
      shared
      =======
      shared theirs
      >>>>>>> theirs
      omega theirs
    MERGED
    expect(result.conflicts).to contain_exactly(
      hash_including(conflict_id: 'owner-shared', output_start_line: 2, output_end_line: 8)
    )
    expect(result.line_records).to include(
      hash_including(conflict_id: 'owner-shared', conflict_side: :base, revision: :base, original_line: 2)
    )
    expect(result.synthesized_fragments.count { |entry| entry[:reason] == :conflict_marker }).to eq(4)
  end

  it 'preserves source final-newline state exactly' do
    plan = Ast::Merge::SourceRender::Plan.new(
      sources: { ours: "first\nlast" },
      fragments: [source_fragment(:ours, 1, 2)]
    )

    expect(renderer.render(plan).content).to eq("first\nlast")
  end

  it 'provides stable content and exact-fragment digests for verification' do
    plan = Ast::Merge::SourceRender::Plan.new(
      sources: sources,
      fragments: [source_fragment(:ours, 1, 1), source_fragment(:theirs, 3, 3)]
    )

    result = renderer.render(plan)

    expect(result.verification_input).to include(
      content_sha256: Digest::SHA256.hexdigest("alpha ours\nomega theirs\n"),
      synthesized_fragment_count: 0,
      conflict_count: 0
    )
    expect(result.verification_input.fetch(:source_fragments)).to contain_exactly(
      hash_including(revision: :ours, sha256: Digest::SHA256.hexdigest("alpha ours\n")),
      hash_including(revision: :theirs, sha256: Digest::SHA256.hexdigest("omega theirs\n"))
    )
  end

  it 'tracks multiple localized conflicts independently' do
    conflict = lambda do |conflict_id|
      Ast::Merge::SourceRender::ConflictFragment.new(
        conflict_id: conflict_id,
        base: [source_fragment(:base, 2, 2)],
        ours: [source_fragment(:ours, 2, 2)],
        theirs: [source_fragment(:theirs, 2, 2)]
      )
    end
    plan = Ast::Merge::SourceRender::Plan.new(
      sources: sources,
      fragments: [conflict.call('first'), conflict.call('second')]
    )

    result = renderer.render(plan)

    expect(result.conflicts.map { |entry| entry[:conflict_id] }).to eq(%w[first second])
    expect(result.conflicts.map { |entry| entry[:output_start_line] }).to eq([1, 8])
    expect(result.verification_input.fetch(:conflict_count)).to eq(2)
  end

  it 'rejects a source range outside its revision' do
    fragment = source_fragment(:ours, 3, 4)

    expect do
      Ast::Merge::SourceRender::Plan.new(sources: sources, fragments: [fragment])
    end.to raise_error(Ast::Merge::SourceRender::InvalidPlanError, /exceeds source line count/)
  end

  it 'rejects non-final fragments that do not end at a line boundary' do
    expect do
      Ast::Merge::SourceRender::Plan.new(
        sources: { ours: 'unterminated', theirs: "next\n" },
        fragments: [source_fragment(:ours, 1, 1), source_fragment(:theirs, 1, 1)]
      )
    end.to raise_error(Ast::Merge::SourceRender::InvalidPlanError, /line boundary/)
  end

  it 'rejects nested conflicts before rendering' do
    nested = Ast::Merge::SourceRender::ConflictFragment.new(
      conflict_id: 'nested',
      base: [],
      ours: [],
      theirs: []
    )

    expect do
      Ast::Merge::SourceRender::ConflictFragment.new(
        conflict_id: 'outer',
        base: [nested],
        ours: [],
        theirs: []
      )
    end.to raise_error(Ast::Merge::SourceRender::InvalidPlanError, /only source or synthesized/)
  end
end
# rubocop:enable Metrics/BlockLength
