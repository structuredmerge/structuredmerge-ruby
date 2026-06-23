# frozen_string_literal: true

# Shared examples for validating merge-facing comment attachments.
#
# Usage:
#   it_behaves_like "Ast::Merge::Comment::Attachment" do
#     let(:comment_attachment) { ... }
#     let(:expected_attachment_owner) { owner }
#     let(:expected_leading_content) { "header" }
#     let(:expected_inline_content) { nil }
#     let(:expected_trailing_content) { nil }
#     let(:expected_orphan_contents) { [] }
#     let(:freeze_token) { "my-merge" }
#     let(:freeze_marker_expected) { false }
#   end
#
RSpec.shared_examples('Ast::Merge::Comment::Attachment') do
  it 'preserves the structural owner' do
    expect(comment_attachment.owner).to(eq(expected_attachment_owner))
  end

  it 'exposes normalized leading, inline, and trailing regions' do
    expect(comment_attachment.leading_region&.normalized_content).to(eq(expected_leading_content))
    expect(comment_attachment.inline_region&.normalized_content).to(eq(expected_inline_content))
    expect(comment_attachment.trailing_region&.normalized_content).to(eq(expected_trailing_content))
  end

  it 'preserves orphan region ordering' do
    expect(comment_attachment.orphan_regions.map(&:normalized_content)).to(eq(expected_orphan_contents))
  end

  it 'detects freeze markers across all attached regions' do
    expect(comment_attachment.freeze_marker?(freeze_token)).to(be(freeze_marker_expected))
  end
end
