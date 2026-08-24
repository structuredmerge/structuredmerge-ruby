# frozen_string_literal: true

require_relative 'spec_helper'

# The examples exercise the complete ordering matrix in one context.
# rubocop:disable Metrics/BlockLength
RSpec.describe Ruby::Merge::RescueSemantics do
  subject(:semantics) { described_class.new(source_defined_exception_definitions: definitions) }

  let(:definitions) { [] }

  it 'keeps non-rescue begin clauses after rescue clauses' do
    clause_types = [
      :ensure_clause,
      [:rescue_clause, ['ArgumentError'], 0],
      :else_clause
    ]

    expect(semantics.canonicalize_begin_clause_kind_order(clause_types)).to eq(
      [
        [:rescue_clause, ['ArgumentError'], 0],
        :else_clause,
        :ensure_clause
      ]
    )
  end

  it 'moves broad StandardError rescue clauses after narrower clauses' do
    clause_types = [
      [:rescue_clause, [:standard_error], 0],
      [:rescue_clause, ['ArgumentError'], 1],
      :ensure_clause
    ]

    expect(semantics.canonicalize_rescue_clause_order(clause_types)).to eq(
      [
        [:rescue_clause, ['ArgumentError'], 1],
        [:rescue_clause, [:standard_error], 0],
        :ensure_clause
      ]
    )
  end

  it 'normalizes bare and explicit StandardError rescue signatures' do
    expect(semantics.rescue_clause_signature([])).to eq([:standard_error])
    expect(semantics.rescue_clause_signature(['::StandardError'])).to eq([:standard_error])
  end

  it 'sorts explicit rescue exception signatures' do
    expect(semantics.rescue_clause_signature(['Timeout::Error', 'ArgumentError'])).to eq(
      ['ArgumentError', 'Timeout::Error']
    )
  end

  context 'with source-defined exception classes' do
    let(:definitions) do
      [
        { name: 'MyGem::Error', namespace: 'MyGem', superclass: 'StandardError' },
        { name: 'MyGem::SpecificError', namespace: 'MyGem', superclass: 'Error' }
      ]
    end

    it 'orders locally defined broader exception classes after narrower subclasses' do
      clause_types = [
        [:rescue_clause, ['MyGem::Error'], 0],
        [:rescue_clause, ['MyGem::SpecificError'], 1]
      ]

      expect(semantics.canonicalize_rescue_clause_order(clause_types)).to eq(
        [
          [:rescue_clause, ['MyGem::SpecificError'], 1],
          [:rescue_clause, ['MyGem::Error'], 0]
        ]
      )
    end
  end
end
# rubocop:enable Metrics/BlockLength
