# frozen_string_literal: true

require 'ast/merge/rspec/conformance_fixtures'

RSpec.describe Ast::Merge::RSpec::ConformanceFixtures do
  describe '.normalize_conformance_fixture_support' do
    it 'normalizes pending fixture metadata' do
      expect(
        described_class.normalize_conformance_fixture_support(
          pending: true,
          pending_reason: 'backend lacks delegated child operation records'
        )
      ).to eq(
        status: 'pending',
        reason: 'backend lacks delegated child operation records'
      )
    end

    it 'normalizes unsupported fixture metadata' do
      expect(
        described_class.normalize_conformance_fixture_support(
          unsupported: true,
          unsupported_reason: 'TSLP does not expose this node class yet',
          category: 'unsupported_parser_capability'
        )
      ).to eq(
        status: 'unsupported',
        reason: 'TSLP does not expose this node class yet',
        category: 'unsupported_parser_capability'
      )
    end

    it 'returns nil for supported fixtures' do
      expect(described_class.normalize_conformance_fixture_support(nil)).to be_nil
      expect(described_class.normalize_conformance_fixture_support(false)).to be_nil
      expect(described_class.normalize_conformance_fixture_support(support: false)).to be_nil
    end
  end

  describe '.support_for_conformance_fixture' do
    it 'selects role-level pending support before fixture metadata' do
      support = described_class.support_for_conformance_fixture(
        'delegated_child_operations',
        pending_roles: {
          delegated_child_operations: {
            reason: 'parser-backed child delegation is not implemented yet'
          }
        },
        fixture: { unsupported: true }
      )

      expect(support).to eq(
        status: 'pending',
        reason: 'parser-backed child delegation is not implemented yet'
      )
    end

    it 'selects role-level unsupported support' do
      support = described_class.support_for_conformance_fixture(
        'discovered_surfaces',
        unsupported_roles: ['discovered_surfaces']
      )

      expect(support).to eq(status: 'unsupported')
    end
  end
end
