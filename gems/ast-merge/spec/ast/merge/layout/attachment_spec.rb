# frozen_string_literal: true

RSpec.describe Ast::Merge::Layout::Attachment do
  before { stub_const('AttachmentOwner', Struct.new(:start_line, :end_line, :label, keyword_init: true)) }

  let(:before_owner) { AttachmentOwner.new(start_line: 2, end_line: 2, label: :before) }
  let(:after_owner) { AttachmentOwner.new(start_line: 4, end_line: 4, label: :after) }
  let(:shared_gap) do
    Ast::Merge::Layout::Gap.new(
      kind: :interstitial,
      start_line: 3,
      end_line: 3,
      lines: [''],
      before_owner: before_owner,
      after_owner: after_owner
    )
  end

  describe 'shared awareness without duplicate control' do
    it 'lets adjacent owners reference the same gap while only one controls output' do
      trailing_attachment = described_class.new(owner: before_owner, trailing_gap: shared_gap)
      leading_attachment = described_class.new(owner: after_owner, leading_gap: shared_gap)

      expect(trailing_attachment.gaps).to eq([shared_gap])
      expect(leading_attachment.gaps).to eq([shared_gap])
      expect(trailing_attachment.trailing_controls_output?).to be(false)
      expect(leading_attachment.leading_controls_output?).to be(true)
    end

    it 'lets the surviving owner take control if the primary owner is removed' do
      trailing_attachment = described_class.new(owner: before_owner, trailing_gap: shared_gap)
      leading_attachment = described_class.new(owner: after_owner, leading_gap: shared_gap)

      expect(trailing_attachment.trailing_controls_output?(removed_owners: [after_owner])).to be(true)
      expect(leading_attachment.leading_controls_output?(removed_owners: [after_owner])).to be(false)
    end
  end

  describe '#empty?' do
    it 'is true when no gaps are attached' do
      expect(described_class.new(owner: before_owner)).to be_empty
    end
  end
end
