# frozen_string_literal: true

RSpec.describe Ast::Merge::Ruleset::FeatureProfile do
  describe '#to_h' do
    it 'normalizes feature metadata and derived booleans' do
      profile = described_class.new(
        owner_selector: :shared_default,
        match_key: :signature,
        read_strategy: :native_read_portable_write,
        attachment_strategy: :normalize_tracked_layout_merge,
        comment_style: :hash_comment,
        render_family: :toml_pairs_and_tables,
        comment_capability: Ast::Merge::Comment::Capability.native_full(source: :fixture, style: :hash_comment),
        support_style: Ast::Merge::Comment::SupportStyle.native_read_portable_write(source: :fixture,
                                                                                    style: :hash_comment),
        capabilities: { layout_aware: true },
        logical_owners: { link_definition: :preserve_if_referenced },
        repair_policies: [{ kind: :comment_ownership_overlap, handling: :warn }],
        surfaces: [{ name: :fenced_code_block, selector: :language_tag }],
        delegation_policies: [{ surface_name: :fenced_code_block, strategy: :by_language }],
        metadata: { source: :fixture }
      )

      expect(profile.to_h).to include(
        owner_selector: :shared_default,
        match_key: :signature,
        read_strategy: :native_read_portable_write,
        attachment_strategy: :normalize_tracked_layout_merge,
        comment_style: :hash_comment,
        render_family: :toml_pairs_and_tables,
        capabilities: { layout_aware: true },
        owner_selector_family: :generic,
        owner_selector_kind: :logical_owner,
        match_key_family: :structural_signature,
        attachment_strategy_family: :layout_merge,
        logical_owners: { link_definition: :preserve_if_referenced },
        repair_policies: [{ kind: :comment_ownership_overlap, handling: :warn, metadata: {} }],
        surfaces: [{ name: :fenced_code_block, selector: :language_tag, metadata: {} }],
        delegation_policies: [{ surface_name: :fenced_code_block, strategy: :by_language, metadata: {} }],
        metadata: { source: :fixture },
        layout_aware: true,
        logical_owner: true,
        comment_aware: true,
        structural_only: false,
        repair_aware: true,
        surface_aware: true,
        delegated_surface_aware: true,
        tracked_attachment: true,
        normalized_attachment: true,
        augmenter_preferred_attachment: false
      )
    end

    it 'detects structural-only profiles' do
      profile = described_class.new(
        owner_selector: :shared_default,
        match_key: :signature
      )

      expect(profile.layout_aware?).to be(false)
      expect(profile.logical_owner?).to be(false)
      expect(profile.comment_aware?).to be(false)
      expect(profile.repair_aware?).to be(false)
      expect(profile.surface_aware?).to be(false)
      expect(profile.delegated_surface_aware?).to be(false)
      expect(profile.owner_selector_family).to eq(:generic)
      expect(profile.owner_selector_kind).to eq(:shared_default)
      expect(profile.match_key_family).to eq(:structural_signature)
      expect(profile.attachment_strategy_family).to be_nil
      expect(profile.tracked_attachment?).to be(false)
      expect(profile.normalized_attachment?).to be(false)
      expect(profile.augmenter_preferred_attachment?).to be(false)
      expect(profile.structural_only?).to be(true)
    end

    it 'surfaces vocabulary metadata for the profile axes' do
      profile = described_class.new(
        owner_selector: :assignment_lines_plus_freeze_blocks,
        match_key: :env_key,
        attachment_strategy: :augmenter_preferred_tracker_layout
      )

      expect(profile.owner_selector_metadata).to include(family: :line_oriented)
      expect(profile.owner_selector_kind).to eq(:explicit)
      expect(profile.match_key_metadata).to include(family: :named_key)
      expect(profile.attachment_strategy_metadata).to include(
        family: :layout_merge,
        tracked_comments: true,
        augmenter_preferred: true,
        normalized: false
      )
      expect(profile.augmenter_preferred_attachment?).to be(true)
    end
  end
end
