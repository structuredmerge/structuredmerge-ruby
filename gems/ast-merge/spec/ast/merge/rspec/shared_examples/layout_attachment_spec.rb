# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/layout_attachment'

LayoutSharedOwner = Struct.new(:start_line, :end_line, :label, keyword_init: true)

# -- shared example self-test
RSpec.describe 'LayoutAttachment shared examples' do
  let(:owner) { LayoutSharedOwner.new(start_line: 3, end_line: 3, label: :owner) }
  let(:layout_attachment) do
    Ast::Merge::Layout::Attachment.new(
      owner: owner,
      leading_gap: Ast::Merge::Layout::Gap.new(
        kind: :preamble,
        start_line: 1,
        end_line: 2,
        lines: ['', ''],
        after_owner: owner
      ),
      trailing_gap: Ast::Merge::Layout::Gap.new(
        kind: :postlude,
        start_line: 4,
        end_line: 5,
        lines: ['', ''],
        before_owner: owner
      )
    )
  end

  it_behaves_like 'Ast::Merge::Layout::Attachment' do
    let(:expected_attachment_owner) { owner }
    let(:expected_leading_gap_kind) { :preamble }
    let(:expected_trailing_gap_kind) { :postlude }
    let(:expected_gap_ranges) { [1..2, 4..5] }
    let(:expected_leading_controls_output) { true }
    let(:expected_trailing_controls_output) { true }
  end
end
