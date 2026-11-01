# frozen_string_literal: true

require 'json'

RSpec.describe 'shared ast-merge source line selection contract' do
  SelectionOwner = Struct.new(:id, :start_line, :end_line, :indent, keyword_init: true)

  it 'selects ordered source regions from the revisions named by the shared fixture' do
    fixture_path = File.expand_path('../../../../../../fixtures/polyglot/ast-merge/source_line_selection.json', __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    selected = []

    fixture.fetch('documents').each do |document|
      owners = document.fetch('owners').map do |entry|
        SelectionOwner.new(id: entry.fetch('id'), start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'), indent: 0)
      end
      comments = document.fetch('comments').map do |entry|
        entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
      end
      comment_augmenter = Ast::Merge::Comment::Augmenter.new(
        source: document.fetch('source'), comments: comments, owners: owners, style: 'hash_comment'
      )
      document.fetch('comment_regions').each do |region|
        actual_region = if region['owner_id']
                          attachment = comment_augmenter.attachment_for(owners.find { |owner| owner.id == region.fetch('owner_id') })
                          attachment.public_send("#{region.fetch('kind')}_region")
                        else
                          comment_augmenter.public_send("#{region.fetch('kind')}_region")
                        end
        expect(actual_region&.start_line).to eq(region.fetch('start_line'))
        expect(actual_region&.end_line).to eq(region.fetch('end_line'))
      end
      layout = Ast::Merge::Layout::Augmenter.new(lines: document.fetch('source').lines, owners: owners)
      document.fetch('layout_gaps').each do |gap|
        actual_gap = layout.gaps.find { |candidate| candidate.start_line == gap.fetch('start_line') && candidate.end_line == gap.fetch('end_line') }
        expect(actual_gap&.kind.to_s).to eq(gap.fetch('kind'))
      end
      lines = document.fetch('source').lines
      selected << [document.fetch('revision'), lines, owners, document.fetch('comment_regions'), document.fetch('layout_gaps')]
    end

    key_to_lines = {}
    key_to_records = {}
    fixture.fetch('selections').each do |selection|
      document = selected.find { |entry| entry.fetch(0) == selection.fetch('revision') }
      source_lines = document.fetch(1)
      owner = document.fetch(2).find { |entry| selection.fetch('selection_key') == "owner:#{entry.id}" }
      line_numbers = if owner
                       (owner.start_line..owner.end_line).to_a
                     elsif (region = document.fetch(3).find { |entry| entry.fetch('selection_key') == selection.fetch('selection_key') })
                       (region.fetch('start_line')..region.fetch('end_line')).to_a
                     elsif (gap = document.fetch(4).find { |entry| entry.fetch('selection_key') == selection.fetch('selection_key') })
                       (gap.fetch('start_line')..gap.fetch('end_line')).to_a
                     else
                       raise "missing fixture selection #{selection.fetch('selection_key')}"
                     end
      key = selection.fetch('selection_key')
      selected_region = document.fetch(3).find { |entry| entry.fetch('selection_key') == key }
      disposition_kind = if owner
                           'structural_owner'
                         elsif selected_region
                           selected_region['owner_id'] ? 'comment_owner' : 'root_region'
                         else
                           'layout_gap'
                         end
      key_to_lines[key] = line_numbers.map { |number| source_lines.fetch(number - 1) }
      key_to_records[key] = line_numbers.map do |number|
        {
          'revision' => selection.fetch('revision'),
          'original_line' => number,
          'selection_key' => key,
          'disposition_kind' => disposition_kind
        }
      end
    end
    actual_content = fixture.fetch('selections').flat_map do |selection|
      key_to_lines.fetch(selection.fetch('selection_key'))
    end.join

    actual_records = fixture.fetch('selections').flat_map do |selection|
      key_to_records.fetch(selection.fetch('selection_key'))
    end.each_with_index.map do |record, index|
      record.merge('output_line' => index + 1)
    end
    expect(actual_content).to eq(fixture.dig('expected', 'content'))
    expect(actual_records).to eq(fixture.dig('expected', 'line_records'))
  end
end
