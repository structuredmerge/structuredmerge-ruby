# frozen_string_literal: true

# Shared examples for validating shared layout augmenters.
#
# Usage:
#   it_behaves_like "Ast::Merge::Layout::Augmenter" do
#     let(:layout_augmenter) { ... }
#     let(:augmenter_owner) { owner }
#     let(:expected_preamble_range) { 1..2 }
#     let(:expected_postlude_range) { 7..7 }
#     let(:expected_interstitial_ranges) { [4..5] }
#     let(:expected_owner_leading_gap_kind) { :preamble }
#     let(:expected_owner_trailing_gap_kind) { :interstitial }
#   end
#
RSpec.shared_examples('Ast::Merge::Layout::Augmenter') do
  it 'exposes the expected shared gap ranges' do
    expect(layout_augmenter.preamble_gap&.start_line..layout_augmenter.preamble_gap&.end_line).to(eq(expected_preamble_range))
    expect(layout_augmenter.postlude_gap&.start_line..layout_augmenter.postlude_gap&.end_line).to(eq(expected_postlude_range))
    expect(layout_augmenter.interstitial_gaps.map do |gap|
      gap.start_line..gap.end_line
    end).to(eq(expected_interstitial_ranges))
  end

  it 'builds a layout attachment for the requested owner' do
    attachment = layout_augmenter.attachment_for(augmenter_owner)

    expect(attachment).to(be_a(Ast::Merge::Layout::Attachment))
    expect(attachment.owner).to(eq(augmenter_owner))
    expect(attachment.leading_gap&.kind).to(eq(expected_owner_leading_gap_kind))
    expect(attachment.trailing_gap&.kind).to(eq(expected_owner_trailing_gap_kind))
  end
end
