# frozen_string_literal: true

RSpec.describe Ast::Merge::Layout::Gap do
  before { stub_const('GapOwner', Struct.new(:start_line, :end_line, :label, keyword_init: true)) }

  let(:before_owner) { GapOwner.new(start_line: 2, end_line: 2, label: :before) }
  let(:after_owner) { GapOwner.new(start_line: 5, end_line: 5, label: :after) }

  describe 'interstitial ownership' do
    subject(:gap) do
      described_class.new(
        kind: :interstitial,
        start_line: 3,
        end_line: 4,
        lines: ['', ''],
        before_owner: before_owner,
        after_owner: after_owner
      )
    end

    it 'defaults control to the following owner' do
      expect(gap.controller_side).to eq(:after)
      expect(gap.controller).to equal(after_owner)
      expect(gap.trailing_for?(before_owner)).to be(true)
      expect(gap.leading_for?(after_owner)).to be(true)
    end

    it 'falls back to the preceding owner when the controller is removed' do
      expect(gap.effective_controller(removed_owners: [after_owner])).to equal(before_owner)
      expect(gap.controls_output_for?(before_owner, removed_owners: [after_owner])).to be(true)
      expect(gap.controls_output_for?(after_owner, removed_owners: [after_owner])).to be(false)
    end

    it 'reports adjacency sides and attachment roles for each owner' do
      expect(gap.adjacent_side_for(before_owner)).to eq(:before)
      expect(gap.adjacent_side_for(after_owner)).to eq(:after)
      expect(gap.role_for(before_owner)).to eq(:trailing)
      expect(gap.role_for(after_owner)).to eq(:leading)
      expect(gap.role_for(Object.new)).to be_nil
    end
  end

  describe 'edge ownership' do
    it 'assigns preamble gaps to the following owner' do
      gap = described_class.new(
        kind: :preamble,
        start_line: 1,
        end_line: 2,
        lines: ['', '  '],
        after_owner: after_owner
      )

      expect(gap.controller_side).to eq(:after)
      expect(gap.controller).to equal(after_owner)
      expect(gap.blank_line_count).to eq(2)
    end

    it 'assigns postlude gaps to the preceding owner' do
      gap = described_class.new(
        kind: :postlude,
        start_line: 6,
        end_line: 7,
        lines: ['', ''],
        before_owner: before_owner
      )

      expect(gap.controller_side).to eq(:before)
      expect(gap.controller).to equal(before_owner)
    end
  end

  describe 'validation' do
    it 'rejects controller sides that do not point at an adjacent owner' do
      expect do
        described_class.new(
          kind: :preamble,
          start_line: 1,
          end_line: 1,
          lines: [''],
          after_owner: after_owner,
          controller_side: :before
        )
      end.to raise_error(ArgumentError, /controller_side/)
    end
  end
end
