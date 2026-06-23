# frozen_string_literal: true

RSpec.describe Ast::Merge::Comment::Attachment do
  let(:owner) { Ast::Merge::Comment::Line.new(text: '# owner proxy', line_number: 20) }
  let(:leading_region) do
    Ast::Merge::Comment::Region.new(
      kind: :leading,
      nodes: [Ast::Merge::Comment::Line.new(text: '# Leading', line_number: 1)]
    )
  end
  let(:inline_region) do
    Ast::Merge::Comment::Region.new(
      kind: :inline,
      nodes: [Ast::Merge::Comment::Line.new(text: '# Inline', line_number: 20)]
    )
  end
  let(:orphan_region) do
    Ast::Merge::Comment::Region.new(
      kind: :orphan,
      nodes: [Ast::Merge::Comment::Line.new(text: '# Orphan', line_number: 50)]
    )
  end
  let(:leading_gap) do
    Ast::Merge::Layout::Gap.new(
      kind: :preamble,
      start_line: 19,
      end_line: 19,
      lines: [''],
      after_owner: owner
    )
  end
  let(:trailing_gap) do
    Ast::Merge::Layout::Gap.new(
      kind: :postlude,
      start_line: 21,
      end_line: 21,
      lines: [''],
      before_owner: owner
    )
  end

  describe '#regions' do
    it 'returns all non-nil regions in a stable order' do
      attachment = described_class.new(
        owner: owner,
        leading_region: leading_region,
        inline_region: inline_region,
        orphan_regions: [orphan_region]
      )

      expect(attachment.regions).to eq([leading_region, inline_region, orphan_region])
    end

    it 'is empty when no regions are provided' do
      attachment = described_class.new(owner: owner)

      expect(attachment).to be_empty
      expect(attachment.regions).to eq([])
    end
  end

  describe '#freeze_marker?' do
    it 'returns true when any region contains a freeze marker' do
      marker_region = Ast::Merge::Comment::Region.new(
        kind: :trailing,
        nodes: [Ast::Merge::Comment::Line.new(text: '# psych-merge:freeze', line_number: 30)]
      )

      attachment = described_class.new(
        owner: owner,
        leading_region: leading_region,
        trailing_region: marker_region
      )

      expect(attachment.freeze_marker?('psych-merge')).to be(true)
      expect(attachment.freeze_marker?('prism-merge')).to be(false)
    end
  end

  describe '#layout_gaps' do
    it 'exposes adjacent layout gaps without changing comment emptiness semantics' do
      attachment = described_class.new(
        owner: owner,
        leading_gap: leading_gap,
        trailing_gap: trailing_gap
      )

      expect(attachment.layout_gaps).to eq([leading_gap, trailing_gap])
      expect(attachment).to be_empty
    end
  end

  describe '#leading_region_layout_owned? / #layout_owned_regions' do
    it 'treats a floating leading region plus its controlling leading gap as layout-owned' do
      floating_leading = Ast::Merge::Comment::Region.new(
        kind: :leading,
        nodes: [Ast::Merge::Comment::Line.new(text: '# Floating', line_number: 18)],
        metadata: { floating: true }
      )
      attachment = described_class.new(
        owner: owner,
        leading_region: floating_leading,
        leading_gap: leading_gap
      )

      expect(attachment.leading_region_layout_owned?).to be(true)
      expect(attachment.layout_owned_regions).to eq([floating_leading])
    end

    it 'stops treating the leading region as layout-owned when the gap controller falls back elsewhere' do
      floating_leading = Ast::Merge::Comment::Region.new(
        kind: :leading,
        nodes: [Ast::Merge::Comment::Line.new(text: '# Floating', line_number: 18)],
        metadata: { floating: true }
      )
      alternate_owner = Ast::Merge::Comment::Line.new(text: '# alternate', line_number: 17)
      interstitial_gap = Ast::Merge::Layout::Gap.new(
        kind: :interstitial,
        start_line: 19,
        end_line: 19,
        lines: [''],
        before_owner: alternate_owner,
        after_owner: owner
      )
      attachment = described_class.new(
        owner: owner,
        leading_region: floating_leading,
        leading_gap: interstitial_gap
      )

      expect(attachment.leading_region_layout_owned?(removed_owners: [owner])).to be(false)
      expect(attachment.layout_owned_regions(removed_owners: [owner])).to eq([])
    end
  end

  describe '#leading_freeze? / #leading_unfreeze?' do
    it 'detects freeze directives in the leading region only' do
      attachment = described_class.new(
        owner: owner,
        leading_region: Ast::Merge::Comment::Region.new(
          kind: :leading,
          nodes: [Ast::Merge::Comment::Line.new(text: '# psych-merge:freeze', line_number: 1)]
        ),
        inline_region: inline_region
      )

      expect(attachment.leading_freeze?('psych-merge')).to be(true)
      expect(attachment.leading_unfreeze?('psych-merge')).to be(false)
    end

    it 'distinguishes unfreeze directives from freeze directives' do
      attachment = described_class.new(
        owner: owner,
        leading_region: Ast::Merge::Comment::Region.new(
          kind: :leading,
          nodes: [Ast::Merge::Comment::Line.new(text: '# psych-merge:unfreeze', line_number: 1)]
        )
      )

      expect(attachment.leading_freeze?('psych-merge')).to be(false)
      expect(attachment.leading_unfreeze?('psych-merge')).to be(true)
    end
  end

  describe '#inspect' do
    it 'includes owner and region count for debugging' do
      attachment = described_class.new(owner: owner, leading_region: leading_region)

      expect(attachment.inspect).to include('owner')
      expect(attachment.inspect).to include('regions=1')
    end
  end
end
