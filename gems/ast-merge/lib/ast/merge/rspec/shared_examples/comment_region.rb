# frozen_string_literal: true

# Shared examples for validating merge-facing comment regions.
#
# Usage:
#   it_behaves_like "Ast::Merge::Comment::Region" do
#     let(:comment_region) { ... }
#     let(:expected_region_kind) { :leading }
#     let(:expected_region_content) { "header\ninline" }
#     let(:expected_region_lines) { 1..2 }
#     let(:freeze_token) { "my-merge" }
#     let(:freeze_marker_expected) { false }
#   end
#
RSpec.shared_examples('Ast::Merge::Comment::Region') do
  it 'preserves the region kind' do
    expect(comment_region.kind).to(eq(expected_region_kind))
  end

  it 'exposes normalized content' do
    expect(comment_region.normalized_content).to(eq(expected_region_content))
  end

  it 'tracks line range from its child nodes' do
    expect(comment_region.start_line).to(eq(expected_region_lines.begin))
    expect(comment_region.end_line).to(eq(expected_region_lines.end))
  end

  it 'detects freeze markers across region nodes' do
    expect(comment_region.freeze_marker?(freeze_token)).to(be(freeze_marker_expected))
  end
end
