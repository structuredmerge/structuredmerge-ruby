# frozen_string_literal: true

# Shared examples for validating merge-facing layout attachments.
#
# Usage:
#   it_behaves_like "Ast::Merge::Layout::Attachment" do
#     let(:layout_attachment) { ... }
#     let(:expected_attachment_owner) { owner }
#     let(:expected_leading_gap_kind) { :preamble }
#     let(:expected_trailing_gap_kind) { :postlude }
#     let(:expected_gap_ranges) { [1..2, 4..5] }
#     let(:expected_leading_controls_output) { true }
#     let(:expected_trailing_controls_output) { true }
#   end
#
RSpec.shared_examples('Ast::Merge::Layout::Attachment') do
  let(:layout_attachment_control_options) { {} }

  it 'preserves the structural owner' do
    expect(layout_attachment.owner).to(eq(expected_attachment_owner))
  end

  it 'exposes the expected adjacent gap kinds and line ranges' do
    expect(layout_attachment.leading_gap&.kind).to(eq(expected_leading_gap_kind))
    expect(layout_attachment.trailing_gap&.kind).to(eq(expected_trailing_gap_kind))
    expect(layout_attachment.gaps.map { |gap| gap.start_line..gap.end_line }).to(eq(expected_gap_ranges))
  end

  it 'reports whether attached gaps control output for the owner' do
    expect(layout_attachment.leading_controls_output?(**layout_attachment_control_options)).to(be(expected_leading_controls_output))
    expect(layout_attachment.trailing_controls_output?(**layout_attachment_control_options)).to(be(expected_trailing_controls_output))
  end
end
