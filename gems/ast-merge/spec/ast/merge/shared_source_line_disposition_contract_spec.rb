# frozen_string_literal: true

require 'json'

RSpec.describe 'shared ast-merge source-line disposition contract' do
  LineDispositionOwner = Struct.new(:id, :start_line, :end_line, :indent, keyword_init: true)

  it 'composes Ruby comment and layout augmenters into the shared per-line rubric' do
    fixture_path = File.expand_path('../../../../../../fixtures/polyglot/ast-merge/source_line_disposition.json', __dir__)
    fixture = JSON.parse(File.read(fixture_path))

    fixture.fetch('cases').each do |contract|
      owners = contract.fetch('owners').map do |entry|
        LineDispositionOwner.new(id: entry.fetch('id'), start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'), indent: entry.fetch('indent'))
      end
      comments = contract.fetch('comments').map do |entry|
        entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
      end
      comment_augmenter = Ast::Merge::Comment::Augmenter.new(
        source: contract.fetch('source'), comments: comments, owners: owners, style: contract.fetch('style')
      )
      actual_comment_regions = []
      owners.each do |owner|
        attachment = comment_augmenter.attachment_for(owner)
        %i[leading inline trailing].each do |kind|
          region = attachment.public_send("#{kind}_region")
          next unless region

          actual_comment_regions << comment_region_record(owner.id, kind.to_s, region)
        end
      end
      { 'preamble' => comment_augmenter.preamble_region, 'postlude' => comment_augmenter.postlude_region }.each do |kind, region|
        actual_comment_regions << comment_region_record(nil, kind, region) if region
      end
      comment_augmenter.orphan_regions.each do |region|
        actual_comment_regions << comment_region_record(nil, 'orphan', region)
      end
      region_keys = contract.fetch('comment_regions').to_h { |region| [region.fetch('id'), region.fetch('selection_key')] }
      actual_comment_regions.each { |region| region['selection_key'] = region_keys.fetch(region.fetch('id')) }
      actual_comment_regions.sort_by! { |region| [region.fetch('start_line'), region.fetch('end_line'), region.fetch('id')] }
      expect(actual_comment_regions).to eq(contract.fetch('comment_regions')), contract.fetch('name')

      layout_augmenter = Ast::Merge::Layout::Augmenter.new(lines: contract.fetch('source').lines, owners: owners)
      actual_gaps = layout_augmenter.gaps.map do |gap|
        controller = gap.controller_side == :after ? gap.after_owner : gap.before_owner
        {
          'id' => "layout-gap:#{gap.start_line}-#{gap.end_line}",
          'selection_key' => "gap:#{gap.kind}:#{gap.before_owner&.id || 'root'}:#{gap.after_owner&.id || 'root'}",
          'kind' => gap.kind.to_s,
          'start_line' => gap.start_line,
          'end_line' => gap.end_line,
          'before_owner_id' => gap.before_owner&.id,
          'after_owner_id' => gap.after_owner&.id,
          'controller_side' => gap.controller_side.to_s,
          'controller_owner_id' => controller&.id
        }
      end
      expect(actual_gaps).to eq(contract.fetch('layout_gaps')), contract.fetch('name')

      actual = source_line_dispositions(contract.fetch('source'), owners, actual_comment_regions, actual_gaps)
      expect(actual).to eq(contract.fetch('expected')), contract.fetch('name')
    end
  end

  def comment_region_record(owner_id, kind, region)
    start_line = region.start_line
    end_line = region.end_line
    {
      'id' => "comment-region:#{kind}:#{start_line}-#{end_line}",
      'owner_id' => owner_id,
      'kind' => kind,
      'start_line' => start_line,
      'end_line' => end_line
    }
  end

  def source_line_dispositions(source, owners, comment_regions, gaps)
    lines = source.lines
    dispositions = Array.new(lines.length)
    owners.each do |owner|
      (owner.start_line..owner.end_line).each do |line_number|
        raise "overlapping structural owners at line #{line_number}" if dispositions[line_number - 1]

        current = disposition(line_number, lines[line_number - 1], 'structural_owner', owner_id: owner.id)
        current['selection_key'] = "owner:#{owner.id}"
        dispositions[line_number - 1] = current
      end
    end
    comment_regions.each do |region|
      (region.fetch('start_line')..region.fetch('end_line')).each do |line_number|
        current = dispositions[line_number - 1]
        if current
          raise "comment and structural owner disagree at line #{line_number}" unless current['kind'] == 'structural_owner' && current['owner_id'] == region['owner_id']

          current['comment_region_ids'] << region.fetch('id')
          current['comment_kind'] = region.fetch('kind')
        else
          kind = region['owner_id'] ? 'comment_owner' : 'root_region'
          current = disposition(line_number, lines[line_number - 1], kind, owner_id: region['owner_id'])
          current['comment_region_ids'] << region.fetch('id')
          current['selection_key'] = region.fetch('selection_key')
          if kind == 'root_region'
            current['root_region_kind'] = region.fetch('kind')
          else
            current['comment_kind'] = region.fetch('kind')
          end
          dispositions[line_number - 1] = current
        end
      end
    end
    gaps.each do |gap|
      (gap.fetch('start_line')..gap.fetch('end_line')).each do |line_number|
        raise "layout gap overlaps an owned line #{line_number}" if dispositions[line_number - 1]

        current = disposition(line_number, lines[line_number - 1], 'layout_gap')
        current['gap_id'] = gap.fetch('id')
        current['selection_key'] = gap.fetch('selection_key')
        current['controller_owner_id'] = gap['controller_owner_id']
        dispositions[line_number - 1] = current
      end
    end
    dispositions.each_with_index.map do |entry, index|
      entry || disposition(index + 1, lines[index], 'unmanaged')
    end
  end

  def disposition(line_number, line, kind, owner_id: nil)
    {
      'line_number' => line_number,
      'line' => line,
      'kind' => kind,
      'selection_key' => "unmanaged:#{line_number}",
      'owner_id' => owner_id,
      'comment_region_ids' => [],
      'comment_kind' => nil,
      'gap_id' => nil,
      'controller_owner_id' => nil,
      'root_region_kind' => nil
    }
  end
end
