# frozen_string_literal: true

require 'json'

RSpec.describe 'shared Ast::Merge comment layout contract' do
  let(:fixture) do
    path = File.expand_path('../../../../../../fixtures/polyglot/ast-merge/comment_line_ownership.json', __dir__)
    JSON.parse(File.read(path))
  end

  it 'matches comment regions, floating ownership, and neighboring layout gaps' do
    owner_class = Struct.new(:start_line, :end_line, :indent, :id, keyword_init: true)
    owners = fixture.fetch('owners').map do |entry|
      owner_class.new(start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'),
                      indent: entry.fetch('indent'), id: entry.fetch('id'))
    end
    by_id = owners.to_h { |owner| [owner.id, owner] }
    comments = fixture.fetch('comments').map do |entry|
      entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
    end
    augmenter = Ast::Merge::Comment::Augmenter.new(
      source: fixture.fetch('source'), comments: comments, owners: owners,
      style: fixture.fetch('style')
    )
    region_summary = lambda do |region|
      next unless region

      { 'kind' => region.kind.to_s, 'normalized_content' => region.normalized_content,
        'floating' => region.floating?, 'start_line' => region.start_line, 'end_line' => region.end_line }
    end
    gap_summary = lambda do |gap|
      next unless gap

      { 'kind' => gap.kind.to_s, 'start_line' => gap.start_line, 'end_line' => gap.end_line }
    end
    actual_attachments = owners.map do |owner|
      attachment = augmenter.attachment_for(owner)
      { 'owner_id' => owner.id, 'leading' => region_summary.call(attachment.leading_region),
        'inline' => region_summary.call(attachment.inline_region),
        'trailing' => region_summary.call(attachment.trailing_region),
        'leading_gap' => gap_summary.call(attachment.leading_gap),
        'trailing_gap' => gap_summary.call(attachment.trailing_gap) }
    end
    actual_document_regions = {
      'preamble' => augmenter.preamble_region&.normalized_content,
      'postlude' => augmenter.postlude_region&.normalized_content,
      'orphans' => augmenter.orphan_regions.map(&:normalized_content)
    }

    expect(actual_attachments).to eq(fixture.dig('expected', 'attachments'))
    expect(actual_document_regions).to eq(fixture.dig('expected', 'document_regions'))

    fixture.fetch('attachment_cases').each do |case_data|
      case_owners = case_data.fetch('owners').map do |entry|
        owner_class.new(start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'),
                        indent: entry.fetch('indent'), id: entry.fetch('id'))
      end
      case_comments = case_data.fetch('comments').map do |entry|
        entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
      end
      case_augmenter = Ast::Merge::Comment::Augmenter.new(
        source: case_data.fetch('source'), comments: case_comments, owners: case_owners,
        style: case_data.fetch('style')
      )
      case_data.dig('expected', 'trailing_by_owner').each do |owner_id, expected|
        owner = case_owners.find { |candidate| candidate.id == owner_id }
        expect(case_augmenter.attachment_for(owner).trailing_region&.normalized_content).to eq(expected)
      end
      expect(case_augmenter.postlude_region&.normalized_content).to eq(case_data.dig('expected', 'postlude'))
    end
    fixture.fetch('policy_cases').each do |case_data|
      case_owners = case_data.fetch('owners').map do |entry|
        owner_class.new(start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'),
                        indent: entry['indent'], id: entry.fetch('id'))
      end
      case_comments = case_data.fetch('comments').map do |entry|
        entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
      end
      case_data.fetch('policies').each do |policy_case|
        case_augmenter = Ast::Merge::Comment::Augmenter.new(
          source: case_data.fetch('source'), comments: case_comments, owners: case_owners,
          style: case_data.fetch('style'), attachment_policy: policy_case.fetch('id').to_sym
        )
        policy_case.dig('expected', 'leading_by_owner').each do |owner_id, expected|
          owner = case_owners.find { |candidate| candidate.id == owner_id }
          expect(case_augmenter.attachment_for(owner).leading_region&.normalized_content).to eq(expected)
        end
        policy_case.dig('expected', 'trailing_by_owner').each do |owner_id, expected|
          owner = case_owners.find { |candidate| candidate.id == owner_id }
          expect(case_augmenter.attachment_for(owner).trailing_region&.normalized_content).to eq(expected)
        end
        policy_case.dig('expected', 'inline_by_owner')&.each do |owner_id, expected|
          owner = case_owners.find { |candidate| candidate.id == owner_id }
          expect(case_augmenter.attachment_for(owner).inline_region&.normalized_content).to eq(expected)
        end
        expect(case_augmenter.postlude_region&.normalized_content).to eq(policy_case.dig('expected', 'postlude'))
        expect(case_augmenter.orphan_regions.map(&:normalized_content)).to eq(policy_case.dig('expected', 'orphans'))
      end
    end
    fixture.fetch('indent_cases').each do |case_data|
      owner = owner_class.new(start_line: 1, end_line: 1, indent: case_data['owner_indent'], id: 'alpha')
      comment = case_data.fetch('comment').transform_keys(&:to_sym).merge(raw: case_data.dig('comment', 'text'))
      case_augmenter = Ast::Merge::Comment::Augmenter.new(
        source: case_data.fetch('source'), comments: [comment], owners: [owner], style: fixture.fetch('style')
      )
      attachment = case_augmenter.attachment_for(owner)
      expect(attachment.trailing_region&.normalized_content).to eq(case_data['expected_trailing'])
      expect(case_augmenter.postlude_region&.normalized_content).to eq(case_data['expected_postlude'])
    end
    fixture.fetch('document_cases').each do |case_data|
      case_owners = case_data.fetch('owners').map do |entry|
        owner_class.new(start_line: entry.fetch('start_line'), end_line: entry.fetch('end_line'),
                        indent: entry.fetch('indent'), id: entry.fetch('id'))
      end
      case_comments = case_data.fetch('comments').map do |entry|
        entry.transform_keys(&:to_sym).merge(raw: entry.fetch('text'))
      end
      case_augmenter = Ast::Merge::Comment::Augmenter.new(
        source: case_data.fetch('source'), comments: case_comments, owners: case_owners,
        style: fixture.fetch('style')
      )
      expect(case_augmenter.preamble_region&.normalized_content).to eq(case_data.dig('expected', 'preamble'))
      expect(case_augmenter.orphan_regions.map(&:normalized_content)).to eq(case_data.dig('expected', 'orphans'))
      case_data.dig('expected', 'leading_by_owner').each do |owner_id, expected|
        owner = case_owners.find { |candidate| candidate.id == owner_id }
        expect(case_augmenter.attachment_for(owner).leading_region&.normalized_content).to eq(expected)
      end
    end
  end
end
