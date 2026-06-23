# frozen_string_literal: true

RSpec.describe Ast::Merge::UnresolvedPolicy do
  describe '.coerce' do
    it 'builds a policy from a Hash' do
      policy = described_class.coerce(
        enabled_kinds: [:matched_line],
        provisional_winner: :template
      )

      expect(policy).to be_a(described_class)
      expect(policy.to_h).to include(
        enabled_kinds: [:matched_line],
        provisional_winner: :template
      )
    end
  end

  describe '#unresolved_for?' do
    it 'defaults to all kinds' do
      expect(described_class.new.unresolved_for?(:matched_line)).to be(true)
    end

    it 'restricts unresolved eligibility to configured kinds' do
      policy = described_class.new(enabled_kinds: [:matched_line])

      expect(policy.unresolved_for?(:matched_line)).to be(true)
      expect(policy.unresolved_for?(:pair_replacement)).to be(false)
    end
  end

  describe '#provisional_winner_for' do
    it 'prefers per-kind overrides before the default and fallback' do
      policy = described_class.new(
        provisional_winner: :destination,
        provisional_winner_by_kind: { matched_line: :template }
      )

      expect(policy.provisional_winner_for(:matched_line, fallback: :destination)).to eq(:template)
      expect(policy.provisional_winner_for(:other_kind, fallback: :template)).to eq(:destination)
    end
  end
end
