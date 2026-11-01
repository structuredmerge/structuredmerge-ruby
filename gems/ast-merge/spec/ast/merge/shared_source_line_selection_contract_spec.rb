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
        SelectionOwner.new(id: entry.fetch('id'), start_line: entry.fetch('start_line'),
                           end_line: entry.fetch('end_line'), indent: 0)
      end
      comments = document.fetch('comments').map do |entry|
        entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
      end
      comment_augmenter = Ast::Merge::Comment::Augmenter.new(
        source: document.fetch('source'), comments: comments, owners: owners, style: 'hash_comment'
      )
      document.fetch('comment_regions').each do |region|
        actual_region = if region['owner_id']
                          attachment = comment_augmenter.attachment_for(owners.find do |owner|
                            owner.id == region.fetch('owner_id')
                          end)
                          attachment.public_send("#{region.fetch('kind')}_region")
                        else
                          comment_augmenter.public_send("#{region.fetch('kind')}_region")
                        end
        expect(actual_region&.start_line).to eq(region.fetch('start_line'))
        expect(actual_region&.end_line).to eq(region.fetch('end_line'))
      end
      layout = Ast::Merge::Layout::Augmenter.new(lines: document.fetch('source').lines, owners: owners)
      document.fetch('layout_gaps').each do |gap|
        actual_gap = layout.gaps.find do |candidate|
          candidate.start_line == gap.fetch('start_line') && candidate.end_line == gap.fetch('end_line')
        end
        expect(actual_gap&.kind.to_s).to eq(gap.fetch('kind'))
        controller = actual_gap&.controller_side == :after ? actual_gap.after_owner : actual_gap&.before_owner
        expect(controller&.id).to eq(gap.fetch('controller_owner_id'))
        actual_key = "gap:#{actual_gap&.kind}:#{actual_gap&.before_owner&.id || 'root'}:#{actual_gap&.after_owner&.id || 'root'}"
        expect(actual_key).to eq(gap.fetch('selection_key'))
      end
      lines = document.fetch('source').lines
      selected << [document.fetch('revision'), lines, owners, document.fetch('comment_regions'),
                   document.fetch('layout_gaps')]
    end

    baseline_revision = fixture.fetch('baseline_revision')
    baseline_document = selected.find { |entry| entry.fetch(0) == baseline_revision }
    owner_revisions = fixture.fetch('selections').each_with_object({}) do |selection, revisions|
      owner_id = selection.fetch('selection_key').delete_prefix('owner:')
      revisions[owner_id] = selection.fetch('revision') if selection.fetch('selection_key').start_with?('owner:')
    end
    line_regions = {}
    baseline_document.fetch(2).each do |owner|
      line_regions["owner:#{owner.id}"] = owner.start_line
    end
    baseline_document.fetch(3).each do |region|
      line_regions[region.fetch('selection_key')] = region.fetch('start_line')
    end
    baseline_document.fetch(4).each do |gap|
      line_regions[gap.fetch('selection_key')] = gap.fetch('start_line')
    end
    expect(fixture.fetch('selections').map { |selection| selection.fetch('selection_key') }).to eq(
      line_regions.sort_by { |_key, start_line| start_line }.map(&:first)
    )

    key_to_lines = {}
    key_to_records = {}
    fixture.fetch('selections').each do |selection|
      selection_key = selection.fetch('selection_key')
      owner_id = selection_key.delete_prefix('owner:')
      region = baseline_document.fetch(3).find { |entry| entry.fetch('selection_key') == selection_key }
      gap = baseline_document.fetch(4).find { |entry| entry.fetch('selection_key') == selection_key }
      expected_revision = if selection_key.start_with?('owner:')
                            owner_revisions.fetch(owner_id)
                          elsif region && region['owner_id']
                            owner_revisions.fetch(region.fetch('owner_id'))
                          elsif gap && gap['controller_owner_id']
                            owner_revisions.fetch(gap.fetch('controller_owner_id'), baseline_revision)
                          else
                            baseline_revision
                          end
      expect(selection.fetch('revision')).to eq(expected_revision), selection_key
      document = selected.find { |entry| entry.fetch(0) == selection.fetch('revision') }
      source_lines = document.fetch(1)
      owner = document.fetch(2).find { |entry| selection.fetch('selection_key') == "owner:#{entry.id}" }
      line_numbers = if owner
                       (owner.start_line..owner.end_line).to_a
                     elsif (region = document.fetch(3).find do |entry|
                       entry.fetch('selection_key') == selection.fetch('selection_key')
                     end)
                       (region.fetch('start_line')..region.fetch('end_line')).to_a
                     elsif (gap = document.fetch(4).find do |entry|
                       entry.fetch('selection_key') == selection.fetch('selection_key')
                     end)
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

  it 'selects every gap controlled by an added owner and its attached comments' do
    fixture_path = File.expand_path(
      '../../../../../../fixtures/polyglot/ast-merge/source_line_addition_selection.json', __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    owner_revisions = fixture.fetch('owner_revisions').to_h do |entry|
      [entry.fetch('owner_id'), entry.fetch('revision')]
    end
    baseline_revision = fixture.fetch('baseline_revision')
    documents = fixture.fetch('documents')
    baseline = documents.find { |document| document.fetch('revision') == baseline_revision }
    baseline_owner_ids = baseline.fetch('owners').map { |owner| owner.fetch('id') }
    additions = owner_revisions.keys.reject { |owner_id| baseline_owner_ids.include?(owner_id) }

    baseline_selections = baseline.fetch('owners').map do |owner|
      { 'selection_key' => "owner:#{owner.fetch('id')}", 'revision' => owner_revisions.fetch(owner.fetch('id')) }
    end
    appended = []
    documents.each do |document|
      revision = document.fetch('revision')
      document.fetch('layout_gaps').each do |gap|
        owner_id = gap['controller_owner_id']
        next unless additions.include?(owner_id) && owner_revisions[owner_id] == revision

        owners = document.fetch('owners').map do |owner|
          SelectionOwner.new(id: owner.fetch('id'), start_line: owner.fetch('start_line'),
                             end_line: owner.fetch('end_line'), indent: 0)
        end
        layout = Ast::Merge::Layout::Augmenter.new(lines: document.fetch('source').lines, owners: owners)
        actual_gap = layout.gaps.find do |candidate|
          candidate.start_line == gap.fetch('start_line') && candidate.end_line == gap.fetch('end_line')
        end
        expect(actual_gap&.controller&.id).to eq(owner_id)
        (gap.fetch('start_line')..gap.fetch('end_line')).each do |line_number|
          appended << { 'selection_key' => gap.fetch('selection_key'), 'revision' => revision,
                        'line_number' => line_number }
        end
      end
      document.fetch('comment_regions').each do |region|
        owner_id = region['owner_id']
        next unless additions.include?(owner_id) && owner_revisions[owner_id] == revision

        (region.fetch('start_line')..region.fetch('end_line')).each do |line_number|
          appended << { 'selection_key' => region.fetch('selection_key'), 'revision' => revision,
                        'line_number' => line_number }
        end
      end
      document.fetch('owners').each do |owner|
        owner_id = owner.fetch('id')
        next unless additions.include?(owner_id) && owner_revisions[owner_id] == revision

        (owner.fetch('start_line')..owner.fetch('end_line')).each do |line_number|
          appended << { 'selection_key' => "owner:#{owner_id}", 'revision' => revision, 'line_number' => line_number }
        end
      end
    end
    additions_by_line = appended.sort_by { |entry| [entry.fetch('revision'), entry.fetch('line_number')] }
    addition_selections = additions_by_line.map do |entry|
      { 'selection_key' => entry.fetch('selection_key'), 'revision' => entry.fetch('revision') }
    end.uniq
    selections = baseline_selections + addition_selections
    expect(selections).to eq(fixture.fetch('expected').fetch('selections'))

    content = selections.flat_map do |selection|
      document = documents.find { |entry| entry.fetch('revision') == selection.fetch('revision') }
      key = selection.fetch('selection_key')
      region = document.fetch('comment_regions').find { |entry| entry.fetch('selection_key') == key }
      gap = document.fetch('layout_gaps').find { |entry| entry.fetch('selection_key') == key }
      owner = document.fetch('owners').find { |entry| "owner:#{entry.fetch('id')}" == key }
      range = region || gap || owner
      (range.fetch('start_line')..range.fetch('end_line')).map do |line_number|
        document.fetch('source').lines.fetch(line_number - 1)
      end
    end.join
    expect(content).to eq(fixture.fetch('expected').fetch('content'))
  end
end
