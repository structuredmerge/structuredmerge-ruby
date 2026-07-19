# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe Ast::Merge::Git do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  it 'conforms to the git merge3 contract fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-950-git-merge3-contract', 'git-merge3-contract.json'))
    expect(fixture.dig(:contract, :package)).to eq('ast-merge-git')
    expect(fixture.dig(:contract, :operation)).to eq('merge3')

    fixture.fetch(:cases).each do |test_case|
      result = described_class.merge3(test_case.fetch(:request))
      expected = test_case.fetch(:expected)

      expect(result.fetch(:ok)).to eq(expected.fetch(:ok)), test_case.fetch(:case_id)
      expect(result.fetch(:conflicts).length).to eq(expected.fetch(:conflict_count)), test_case.fetch(:case_id)
      expect(result.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category) }).to eq(
        expected.fetch(:diagnostic_categories)
      ), test_case.fetch(:case_id)
      expect(result.fetch(:change_classifications)).to eq(expected.fetch(:change_classifications)),
                                                       test_case.fetch(:case_id)
      expect(result.fetch(:reparse_after_render)).to eq(expected.fetch(:reparse_after_render)),
                                                     test_case.fetch(:case_id)
      expect(result.fetch(:render_report).fetch(:strategy)).to eq(expected.dig(:render_report, :strategy)),
                                                          test_case.fetch(:case_id)
      if expected[:merged_json]
        expect(JSON.parse(result.fetch(:merged_source), symbolize_names: true)).to eq(expected.fetch(:merged_json)),
                                                                        test_case.fetch(:case_id)
      end
      expected.fetch(:conflict_categories, []).each_with_index do |category, index|
        expect(result.dig(:conflicts, index, :category)).to eq(category), test_case.fetch(:case_id)
      end
      expected.fetch(:conflict_paths, []).each_with_index do |path, index|
        expect(result.dig(:conflicts, index, :path)).to eq(path), test_case.fetch(:case_id)
      end
      expected.fetch(:conflicted_source_contains, []).each do |needle|
        expect(result.fetch(:conflicted_source)).to include(needle), test_case.fetch(:case_id)
      end
      expected.fetch(:conflicted_source_not_contains, []).each do |needle|
        expect(result.fetch(:conflicted_source)).not_to include(needle), test_case.fetch(:case_id)
      end
    end
  end

  it 'conforms to the git comment delta semantics fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-953-git-comment-delta-semantics',
                                           'git-comment-delta-semantics.json'))
    expect(fixture.dig(:contract, :package)).to eq('ast-merge-git')
    expect(fixture.dig(:contract, :operation)).to eq('comment_delta_semantics')

    fixture.fetch(:cases).each do |test_case|
      result = described_class.merge_comment_delta(
        base_comment: test_case[:base_comment],
        ours_comment: test_case[:ours_comment],
        theirs_comment: test_case[:theirs_comment],
        owner_path: fixture.dig(:owner, :path)
      )
      expected = test_case.fetch(:expected)

      expect(result.fetch(:ok)).to eq(expected.fetch(:ok)), test_case.fetch(:case_id)
      expect(result.fetch(:conflicts).length).to eq(expected.fetch(:conflict_count)), test_case.fetch(:case_id)
      expect(result.fetch(:merged_comment)).to eq(expected[:merged_comment]) if expected.key?(:merged_comment)
      if expected.key?(:conflict_categories)
        expect(result.fetch(:conflicts).map do |conflict|
          conflict.fetch(:category)
        end).to eq(expected.fetch(:conflict_categories))
      end
      expect(fixture.dig(:owner, :path)).to eq(expected[:comment_owner_path]) if expected.key?(:comment_owner_path)
    end
  end
end
