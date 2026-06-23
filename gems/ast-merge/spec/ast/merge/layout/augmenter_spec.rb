# frozen_string_literal: true

RSpec.describe Ast::Merge::Layout::Augmenter do
  before do
    stub_const('AugmenterOwner', Struct.new(:start_line, :end_line, :label, keyword_init: true))
    stub_const('AugmenterLocation', Struct.new(:start_line, :end_line, keyword_init: true))
    stub_const('AugmenterLocatedOwner', Struct.new(:location, :label, keyword_init: true))
  end

  describe '.call' do
    it 'builds a passive augmenter result' do
      augmenter = described_class.call(lines: [], owners: [])

      expect(augmenter).to be_a(described_class)
      expect(augmenter.gaps).to eq([])
      expect(augmenter.attachments_by_owner).to eq({})
    end
  end

  describe 'gap inference' do
    let(:first_owner) { AugmenterOwner.new(start_line: 3, end_line: 3, label: :first) }
    let(:second_owner) { AugmenterOwner.new(start_line: 6, end_line: 6, label: :second) }
    let(:owners) { [first_owner, second_owner] }
    let(:lines) do
      [
        '',
        '  ',
        'first',
        '',
        '',
        'second',
        ''
      ]
    end

    it 'builds shared preamble, interstitial, and postlude gaps' do
      augmenter = described_class.new(lines: lines, owners: owners)

      expect(augmenter.preamble_gap).not_to be_nil
      expect(augmenter.preamble_gap).to be_preamble
      expect(augmenter.preamble_gap.controller).to equal(first_owner)

      expect(augmenter.interstitial_gaps.size).to eq(1)
      interstitial_gap = augmenter.interstitial_gaps.first
      expect(interstitial_gap).to be_interstitial
      expect(interstitial_gap.before_owner).to equal(first_owner)
      expect(interstitial_gap.after_owner).to equal(second_owner)
      expect(interstitial_gap.controller).to equal(second_owner)

      expect(augmenter.postlude_gap).not_to be_nil
      expect(augmenter.postlude_gap).to be_postlude
      expect(augmenter.postlude_gap.controller).to equal(second_owner)
    end

    it 'attaches the same interstitial gap to both adjacent owners' do
      augmenter = described_class.new(lines: lines, owners: owners)
      first_attachment = augmenter.attachment_for(first_owner)
      second_attachment = augmenter.attachment_for(second_owner)
      interstitial_gap = augmenter.interstitial_gaps.first

      expect(first_attachment.leading_gap).to equal(augmenter.preamble_gap)
      expect(first_attachment.trailing_gap).to equal(interstitial_gap)
      expect(second_attachment.leading_gap).to equal(interstitial_gap)
      expect(second_attachment.trailing_gap).to equal(augmenter.postlude_gap)
    end

    it 'ignores blank runs that are not directly adjacent to any owner boundary' do
      augmenter = described_class.new(
        lines: ['intro', '', 'bridge', 'owner'],
        owners: [AugmenterOwner.new(start_line: 4, end_line: 4, label: :owner)]
      )

      expect(augmenter.gaps).to eq([])
      expect(augmenter.attachment_for(augmenter.owners.first)).to be_empty
    end

    it 'supports comment-free but layout-aware owners' do
      owner = AugmenterOwner.new(start_line: 2, end_line: 2, label: :json_member)
      augmenter = described_class.new(lines: ['', '"name": true'], owners: [owner])

      expect(augmenter.preamble_gap).to be_preamble
      expect(augmenter.attachment_for(owner).leading_gap).to equal(augmenter.preamble_gap)
      expect(augmenter.attachment_for(owner).leading_gap.lines).to eq([''])
    end
  end

  describe 'validation' do
    it 'supports owners via configured line extractors' do
      located_owner = AugmenterLocatedOwner.new(
        location: AugmenterLocation.new(start_line: 2, end_line: 2),
        label: :located
      )

      augmenter = described_class.new(
        lines: ['', 'owner', ''],
        owners: [located_owner],
        start_line_for: ->(owner) { owner.location.start_line },
        end_line_for: ->(owner) { owner.location.end_line }
      )

      expect(augmenter.preamble_gap).to be_preamble
      expect(augmenter.postlude_gap).to be_postlude
      expect(augmenter.attachment_for(located_owner).leading_gap).to equal(augmenter.preamble_gap)
      expect(augmenter.attachment_for(located_owner).trailing_gap).to equal(augmenter.postlude_gap)
    end

    it 'raises when an owner does not expose start_line and end_line' do
      expect do
        described_class.new(lines: [], owners: [Object.new])
      end.to raise_error(ArgumentError, /owner must respond to #start_line and #end_line/)
    end
  end
end
