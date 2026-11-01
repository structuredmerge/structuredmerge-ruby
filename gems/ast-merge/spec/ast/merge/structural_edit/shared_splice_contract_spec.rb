# frozen_string_literal: true

require 'json'

RSpec.describe Ast::Merge::StructuralEdit::SplicePlan do
  it 'matches the shared source-preserving splice contract' do
    path = File.expand_path('../../../../../../../fixtures/polyglot/ast-merge/structural_splice.json', __dir__)
    fixture = JSON.parse(File.read(path))

    fixture.fetch('cases').each do |case_data|
      options = {}
      if case_data.key?('preserve_removed_trailing_blank_lines')
        options[:preserve_removed_trailing_blank_lines] = case_data.fetch('preserve_removed_trailing_blank_lines')
      end
      plan = described_class.new(
        source: case_data.fetch('source'),
        replacement: case_data.fetch('replacement'),
        replace_start_line: case_data.fetch('replace_start_line'),
        replace_end_line: case_data.fetch('replace_end_line'),
        **options
      )
      expected = case_data.fetch('expected')
      expect(plan.before_content).to eq(expected.fetch('before'))
      expect(plan.removed_content).to eq(expected.fetch('removed'))
      expect(plan.after_content).to eq(expected.fetch('after'))
      expect(plan.merged_content).to eq(expected.fetch('merged'))
      expect(plan.changed?).to eq(expected.fetch('changed'))
    end
  end
end
