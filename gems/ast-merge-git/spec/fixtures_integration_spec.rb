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
      if expected.key?(:change_classifications)
        expect(result.fetch(:change_classifications)).to eq(expected.fetch(:change_classifications))
      end
      expect(result.fetch(:reparse_after_render)).to eq(expected.fetch(:reparse_after_render))
      expect(result.fetch(:render_report)).to eq(expected.fetch(:render_report)) if expected.key?(:render_report)
      if expected.key?(:formatting_preservation)
        expect(result.fetch(:formatting_preservation)).to eq(expected.fetch(:formatting_preservation))
      end
      if expected.key?(:secondary_formatting_metrics)
        expect(result.fetch(:secondary_formatting_metrics)).to eq(expected.fetch(:secondary_formatting_metrics))
      end
      if expected.key?(:default_driver_evaluation)
        expect(result.fetch(:default_driver_evaluation)).to eq(expected.fetch(:default_driver_evaluation))
      end
      if expected.key?(:owned_regions)
        expect(result.fetch(:owned_regions).length).to eq(expected.fetch(:owned_regions).length),
                                                       test_case.fetch(:case_id)
        expected.fetch(:owned_regions).each_with_index do |expected_region, index|
          expect(result.fetch(:owned_regions)[index]).to include(expected_region), test_case.fetch(:case_id)
        end
      end
      if result.fetch(:ok)
        expect(JSON.parse(result.fetch(:merged_source))).to eq(JSON.parse(JSON.generate(expected.fetch(:merged_json))))
      else
        expect(result.fetch(:conflicts).map do |conflict|
          conflict.fetch(:category)
        end).to eq(expected.fetch(:conflict_categories))
        expect(result.fetch(:conflicts).map { |conflict| conflict.fetch(:path) }).to eq(expected.fetch(:conflict_paths))
        expected.fetch(:conflicted_source_contains, []).each do |needle|
          expect(result.fetch(:conflicted_source)).to include(needle), test_case.fetch(:case_id)
        end
        expected.fetch(:conflicted_source_not_contains, []).each do |needle|
          expect(result.fetch(:conflicted_source)).not_to include(needle), test_case.fetch(:case_id)
        end
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
