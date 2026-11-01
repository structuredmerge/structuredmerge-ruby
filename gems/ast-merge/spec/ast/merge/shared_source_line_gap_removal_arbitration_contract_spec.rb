# frozen_string_literal: true

require 'json'

SharedSourceLineGapArbitrationOwner = Struct.new(:id, :start_line, :end_line, :indent, keyword_init: true)

# rubocop:disable Metrics/BlockLength -- ownership facts and rendered bytes form one contract.
RSpec.describe 'shared source-line gap removal arbitration contract' do
  it 'keeps one gap at a collapsed boundary using surviving controller precedence' do
    fixture_path = File.expand_path(
      '../../../../../../fixtures/polyglot/ast-merge/source_line_gap_removal_arbitration.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    deleted = fixture.fetch('deleted_owner_ids')
    document = fixture.fetch('documents').find { |entry| entry.fetch('revision') == fixture.fetch('baseline_revision') }
    owners = document.fetch('owners').map do |entry|
      SharedSourceLineGapArbitrationOwner.new(
        id: entry.fetch('id'), start_line: entry.fetch('start_line'),
        end_line: entry.fetch('end_line'), indent: 0
      )
    end
    comment_boundaries = document.fetch('comment_regions').map do |region|
      {
        owner: owners.find { |owner| owner.id == region.fetch('owner_id') },
        kind: region.fetch('kind'), start_line: region.fetch('start_line'), end_line: region.fetch('end_line')
      }
    end
    layout = Ast::Merge::Layout::Augmenter.new(
      lines: document.fetch('source').lines, owners: owners, comment_boundaries: comment_boundaries
    )
    removed_owners = owners.select { |owner| deleted.include?(owner.id) }
    expected_controllers = fixture.dig('expected', 'gap_controllers_after_deletion').to_h do |entry|
      [entry.fetch('selection_key'), entry]
    end
    candidates = document.fetch('layout_gaps').filter_map do |entry|
      actual = layout.gaps.find do |gap|
        gap.start_line == entry.fetch('start_line') && gap.end_line == entry.fetch('end_line')
      end
      expect(actual).not_to be_nil
      expect(actual.kind.to_s).to eq(entry.fetch('kind'))
      expect(actual.controller&.id).to eq(entry.fetch('controller_owner_id'))
      expected = expected_controllers.fetch(entry.fetch('selection_key'))
      effective_controller = actual.effective_controller(removed_owners: removed_owners)&.id
      expect(effective_controller).to eq(expected.fetch('controller_owner_id'))
      before = entry['before_owner_id'] unless deleted.include?(entry['before_owner_id'])
      after = entry['after_owner_id'] unless deleted.include?(entry['after_owner_id'])
      next if before.nil? && after.nil?

      [expected.fetch('priority'), entry.fetch('start_line'), entry, effective_controller]
    end
    boundary = fixture.dig('expected', 'collapsed_boundary')
    winner = candidates.min_by { |priority, line, _gap, _controller| [priority, line] }
    expect(winner).not_to be_nil
    expect(winner[2].fetch('selection_key')).to eq(fixture.dig('expected', 'retained_gap_key'))
    expect(boundary.fetch('before_owner_id')).to eq('before')
    expect(boundary.fetch('after_owner_id')).to eq('after')

    selections = fixture.dig('expected', 'selections')
    rendered = selections.flat_map do |selection|
      source = fixture.fetch('documents').find do |entry|
        entry.fetch('revision') == selection.fetch('revision')
      end.fetch('source')
      key = selection.fetch('selection_key')
      range = if key.start_with?('owner:')
                owner = document.fetch('owners').find { |entry| "owner:#{entry.fetch('id')}" == key }
                owner.fetch('start_line')..owner.fetch('end_line')
              else
                gap = document.fetch('layout_gaps').find { |entry| entry.fetch('selection_key') == key }
                gap.fetch('start_line')..gap.fetch('end_line')
              end
      range.map { |line| source.lines.fetch(line - 1) }
    end.join
    expect(rendered).to eq(fixture.dig('expected', 'content'))
  end
end
# rubocop:enable Metrics/BlockLength
