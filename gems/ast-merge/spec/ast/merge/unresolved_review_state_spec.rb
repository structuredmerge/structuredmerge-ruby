# frozen_string_literal: true

RSpec.describe Ast::Merge::UnresolvedReviewState do
  let(:resolution_case) do
    Ast::Merge::Runtime::ResolutionCase.new(
      case_id: 'case-1',
      reason: :conflict,
      candidates: { template: 'old', destination: 'new' },
      provisional_winner: :destination,
      metadata: { line: 1 }
    )
  end

  it 'serializes cases and selections' do
    state = described_class.new(
      cases: [resolution_case],
      selections: { 'case-1' => :template },
      metadata: { document: 'example' }
    )

    expect(state.to_h).to eq(
      schema_version: 1,
      cases: [resolution_case.to_h],
      selections: { 'case-1' => :template },
      metadata: { document: 'example' }
    )
  end

  it 'loads from a hash payload' do
    state = described_class.from_h(
      'schema_version' => 1,
      'cases' => [resolution_case.to_h],
      'selections' => { 'case-1' => 'template' }
    )

    expect(state.cases.map(&:to_h)).to eq([resolution_case.to_h])
    expect(state.selections).to eq({ 'case-1' => :template })
  end
end
