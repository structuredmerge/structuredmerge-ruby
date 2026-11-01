# frozen_string_literal: true

require 'json'

RSpec.describe Ast::Merge::StructuralEdit::RemovePlan do
  it 'matches the shared removal splice and rehome contract' do
    path = File.expand_path('../../../../../../../fixtures/polyglot/ast-merge/structural_remove_rehome.json', __dir__)
    fixture = JSON.parse(File.read(path))
    owner_class = Struct.new(:id)
    fixture.fetch('cases').each do |case_data|
      owners = ([case_data.dig('boundaries', 'leading', 'owner_id'),
                 case_data.dig('boundaries', 'trailing', 'owner_id')] +
                case_data.fetch('removed_attachments').map { |entry| entry['owner_id'] }).compact.uniq
                 .to_h { |id| [id, owner_class.new(id)] }
      boundary_for = lambda do |key, edge|
        entry = case_data.dig('boundaries', key)
        entry && Ast::Merge::StructuralEdit::Boundary.new(edge: edge, owner: owners.fetch(entry.fetch('owner_id')))
      end
      region_for = lambda do |id, kind|
        Ast::Merge::Comment::Region.new(kind: kind, nodes: [id])
      end
      removed = case_data.fetch('removed_attachments').map do |entry|
        Ast::Merge::Comment::Attachment.new(
          owner: owners.fetch(entry.fetch('owner_id')),
          leading_region: entry['leading_region_id'] && region_for.call(entry['leading_region_id'], :leading),
          inline_region: entry['inline_region_id'] && region_for.call(entry['inline_region_id'], :inline),
          orphan_regions: entry.fetch('orphan_region_ids', []).map { |id| region_for.call(id, :orphan) },
          trailing_region: entry['trailing_region_id'] && region_for.call(entry['trailing_region_id'], :trailing),
          leading_gap: entry['leading_gap_id'],
          trailing_gap: entry['trailing_gap_id']
        )
      end
      plan = described_class.new(
        source: case_data.fetch('source'),
        remove_start_line: case_data.fetch('remove_start_line'),
        remove_end_line: case_data.fetch('remove_end_line'),
        leading_boundary: boundary_for.call('leading', :leading),
        trailing_boundary: boundary_for.call('trailing', :trailing),
        removed_attachments: removed
      )
      actual = {
        'merged' => plan.merged_content,
        'removed_owner_ids' => plan.removed_owners.map(&:id),
        'retained_owner_ids' => plan.retained_owners.map(&:id),
        'promoted_comment_region_ids' => plan.promoted_comment_regions.map(&:normalized_content),
        'promoted_layout_gap_ids' => plan.promoted_layout_gaps,
        'plans' => plan.rehome_plans.map do |entry|
          {
            'source_owner_id' => entry.source_owner.id,
            'target_owner_id' => entry.target_owner.id,
            'edge' => entry.edge.to_s,
            'kind' => entry.metadata.fetch(:kind).to_s,
            'comment_region_ids' => entry.comment_regions.map(&:normalized_content),
            'layout_gap_ids' => entry.layout_gaps,
            'comment_attachment' => {
              'owner_id' => entry.comment_attachment.owner.id,
              'leading_region_id' => entry.comment_attachment.leading_region&.normalized_content,
              'inline_region_id' => entry.comment_attachment.inline_region&.normalized_content,
              'trailing_region_id' => entry.comment_attachment.trailing_region&.normalized_content,
              'orphan_region_ids' => entry.comment_attachment.orphan_regions.map(&:normalized_content),
              'metadata' => entry.comment_attachment.metadata.transform_keys(&:to_s).transform_values(&:to_s)
            },
            'layout_attachment' => {
              'owner_id' => entry.layout_attachment.owner.id,
              'leading_gap_id' => entry.layout_attachment.leading_gap,
              'trailing_gap_id' => entry.layout_attachment.trailing_gap,
              'metadata' => entry.layout_attachment.metadata.transform_keys(&:to_s).transform_values(&:to_s)
            }
          }
        end
      }
      expect(actual).to eq(case_data.fetch('expected')), case_data.fetch('name')
    end
  end
end

