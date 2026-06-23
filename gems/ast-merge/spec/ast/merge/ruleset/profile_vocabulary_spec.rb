# frozen_string_literal: true

RSpec.describe Ast::Merge::Ruleset::ProfileVocabulary do
  describe '.owner_selector_metadata' do
    it 'returns shared metadata for known owner selectors' do
      expect(described_class.owner_selector_metadata(:line_bound_statements)).to eq(
        family: :line_oriented,
        description: 'Line-oriented structural statements'
      )
    end

    it 'tracks heading-owned section selectors' do
      expect(described_class.owner_selector_metadata(:heading_sections)).to eq(
        family: :section_branch,
        description: 'Heading-owned section branches'
      )
    end

    it 'returns nil for unknown owner selectors' do
      expect(described_class.owner_selector_metadata(:mystery_owner)).to be_nil
    end
  end

  describe '.match_key_metadata' do
    it 'returns shared metadata for known match keys' do
      expect(described_class.match_key_metadata(:env_key)).to eq(
        family: :named_key,
        description: 'Environment-variable key matching'
      )
    end
  end

  describe '.attachment_strategy_metadata' do
    it 'returns shared metadata for known attachment strategies' do
      expect(described_class.attachment_strategy_metadata(:normalize_tracked_layout_merge)).to eq(
        family: :layout_merge,
        tracked_comments: true,
        normalized: true,
        augmenter_preferred: false,
        description: 'Normalize tracked attachments while folding them into shared layout ownership'
      )
    end
  end

  describe 'known-vocabulary predicates' do
    it 'tracks known owner selectors, match keys, and attachment strategies' do
      expect(described_class.known_owner_selector?(:rbs_declarations)).to be(true)
      expect(described_class.known_owner_selector?(:mystery_owner)).to be(false)
      expect(described_class.known_match_key?(:signature)).to be(true)
      expect(described_class.known_match_key?(:mystery_match)).to be(false)
      expect(described_class.known_attachment_strategy?(:tracker_layout_merge)).to be(true)
      expect(described_class.known_attachment_strategy?(:mystery_attach)).to be(false)
    end
  end
end
