# frozen_string_literal: true

# Shared examples for validating source/native comment augmenters.
#
# Usage:
#   it_behaves_like "Ast::Merge::Comment::Augmenter" do
#     let(:comment_augmenter) { ... }
#     let(:augmenter_owner) { owner }
#     let(:expected_capability_predicate) { :source_augmented? }
#     let(:expected_leading_content) { "header" }
#     let(:expected_inline_content) { nil }
#     let(:expected_preamble_content) { nil }
#     let(:expected_postlude_content) { "footer" }
#     let(:expected_orphan_contents) { [] }
#   end
#
RSpec.shared_examples('Ast::Merge::Comment::Augmenter') do
  it 'reports the expected comment capability' do
    expect(comment_augmenter.capability).to(be_a(Ast::Merge::Comment::Capability))
    expect(comment_augmenter.capability.public_send(expected_capability_predicate)).to(be(true))
  end

  it 'builds an attachment for the requested owner' do
    attachment = comment_augmenter.attachment_for(augmenter_owner)

    expect(attachment).to(be_a(Ast::Merge::Comment::Attachment))
    expect(attachment.leading_region&.normalized_content).to(eq(expected_leading_content))
    expect(attachment.inline_region&.normalized_content).to(eq(expected_inline_content))
  end

  it 'preserves preamble, postlude, and orphan comment regions' do
    expect(comment_augmenter.preamble_region&.normalized_content).to(eq(expected_preamble_content))
    expect(comment_augmenter.postlude_region&.normalized_content).to(eq(expected_postlude_content))
    expect(comment_augmenter.orphan_regions.map(&:normalized_content)).to(eq(expected_orphan_contents))
  end
end
