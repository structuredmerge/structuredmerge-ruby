# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/layout_augmenter'

LayoutAugmenterOwner = Struct.new(:start_line, :end_line, :label, keyword_init: true)

# -- shared example self-test
RSpec.describe 'LayoutAugmenter shared examples' do
  let(:first_owner) { LayoutAugmenterOwner.new(start_line: 3, end_line: 3, label: :first) }
  let(:second_owner) { LayoutAugmenterOwner.new(start_line: 6, end_line: 6, label: :second) }
  let(:layout_augmenter) do
    Ast::Merge::Layout::Augmenter.new(
      lines: ['', '  ', 'first', '', '', 'second', ''],
      owners: [first_owner, second_owner]
    )
  end

  it_behaves_like 'Ast::Merge::Layout::Augmenter' do
    let(:augmenter_owner) { first_owner }
    let(:expected_preamble_range) { 1..2 }
    let(:expected_postlude_range) { 7..7 }
    let(:expected_interstitial_ranges) { [4..5] }
    let(:expected_owner_leading_gap_kind) { :preamble }
    let(:expected_owner_trailing_gap_kind) { :interstitial }
  end
end
