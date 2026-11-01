# frozen_string_literal: true

require 'json'

RSpec.describe 'shared Ast::Merge layout ownership contract' do
  let(:fixture) do
    path = File.expand_path('../../../../../../../fixtures/polyglot/ast-merge/layout_line_ownership.json', __dir__)
    JSON.parse(File.read(path))
  end

  it 'matches shared gap ownership, attachments, and removal fallback' do
    owner_class = Struct.new(:start_line, :end_line, :id, keyword_init: true)
    owners = fixture.fetch('owners').map do |entry|
      owner_class.new(start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'), id: entry.fetch('id'))
    end
    by_id = owners.to_h { |owner| [owner.id, owner] }
    augmenter = Ast::Merge::Layout::Augmenter.new(lines: fixture.fetch('lines'), owners: owners)

    actual_gaps = augmenter.gaps.map do |gap|
      removed = fixture.fetch('removed_owner_ids_for_fallback').map { |id| by_id.fetch(id) }
      {
        'id' => "layout-gap:#{gap.start_line}-#{gap.end_line}",
        'kind' => gap.kind.to_s,
        'start_line' => gap.start_line,
        'end_line' => gap.end_line,
        'lines' => gap.lines,
        'before_owner_id' => gap.before_owner&.id,
        'after_owner_id' => gap.after_owner&.id,
        'controller_side' => gap.controller_side.to_s,
        'controller_after_removal_owner_id' => gap.effective_controller(removed_owners: removed)&.id
      }
    end
    actual_attachments = owners.map do |owner|
      attachment = augmenter.attachment_for(owner)
      {
        'owner_id' => owner.id,
        'leading_gap_id' => attachment.leading_gap && "layout-gap:#{attachment.leading_gap.start_line}-#{attachment.leading_gap.end_line}",
        'trailing_gap_id' => attachment.trailing_gap && "layout-gap:#{attachment.trailing_gap.start_line}-#{attachment.trailing_gap.end_line}"
      }
    end

    expect(actual_gaps).to eq(fixture.fetch('gaps'))
    expect(actual_attachments).to eq(fixture.fetch('attachments'))

    fixture.fetch('controller_checks').each do |check|
      owner = by_id.fetch(check.fetch('owner_id'))
      attachment = augmenter.attachment_for(owner)
      removed = check.fetch('removed_owner_ids').map { |id| by_id.fetch(id) }
      controls_output = attachment.public_send(
        "#{check.fetch('edge')}_controls_output?", removed_owners: removed
      )
      expect(controls_output).to eq(check.fetch('expected'))
    end

    fixture.fetch('physical_line_case').fetch('documents').each do |document|
      source_lines = document.fetch('source').lines
      owner_lines = document.fetch('owners').map do |owner|
        source_lines[(owner.fetch('start_line') - 1)...owner.fetch('end_line')].join
      end
      expect(owner_lines).to all(end_with("\n"))
    end

    membership_case = fixture.fetch('membership_removal_case')
    stable_ids = membership_case.fetch('stable_owner_ids')
    actual_segments = membership_case.fetch('documents').map do |document|
      source_lines = document.fetch('source').lines
      cursor = 0
      segment = []
      segments = []
      document.fetch('owners').each do |owner|
        start_index = owner.fetch('start_line') - 1
        end_index = owner.fetch('end_line')
        segment.concat(source_lines[cursor...start_index] || [])
        if stable_ids.include?(owner.fetch('id'))
          segments << segment.join
          segment = []
        end
        cursor = end_index
      end
      segment.concat(source_lines[cursor..] || [])
      segments << segment.join
      segments
    end
    expect(actual_segments).to all(eq(membership_case.fetch('expected_stable_layout_segments')))
  end
end
