# frozen_string_literal: true

require 'json'

RSpec.describe Ast::Merge::CommentLayoutEmissionSupport do
  RemovedOwnerStatement = Struct.new(:name, :start_line, :end_line, keyword_init: true)
  RemovedOwnerRegion = Struct.new(:start_line, :end_line, :normalized_content, keyword_init: true) do
    def empty?
      false
    end

    def text
      normalized_content
    end
  end
  RemovedOwnerAttachment = Struct.new(:leading_region, :trailing_region, :trailing_gap, keyword_init: true)

  class RemovedOwnerAnalysis
    attr_reader :lines

    def initialize(lines:, attachment:)
      @lines = lines
      @attachment = attachment
    end

    def line_at(line_number)
      lines[line_number - 1]
    end

    def comment_attachment_for(_owner, **)
      @attachment
    end
  end

  class Harness
    include Ast::Merge::CommentLayoutEmissionSupport

    public :removed_owner_preserved_lines_for, :removed_owner_preserved_line_numbers_for
  end

  it 'matches the shared removed-owner emission contract' do
    path = File.expand_path('../../../../../../../fixtures/polyglot/ast-merge/structural_removed_owner_emission.json',
                            __dir__)
    fixture = JSON.parse(File.read(path))
    fixture.fetch('cases').each do |entry|
      owner_line = entry.fetch('removed_owner_line_number')
      owner = RemovedOwnerStatement.new(name: entry.fetch('removed_owner_id'), start_line: owner_line,
                                        end_line: owner_line)
      later_id = entry.dig('trailing_gap', 'after_owner_id')
      later_line = entry.fetch('retained_owner_line_number')
      later = later_id && RemovedOwnerStatement.new(name: later_id, start_line: later_line, end_line: later_line)
      region_data = entry.fetch('trailing_region')
      region = RemovedOwnerRegion.new(start_line: region_data.fetch('line_numbers').first,
                                      end_line: region_data.fetch('line_numbers').last,
                                      normalized_content: region_data.fetch('lines').join("\n"))
      gap_data = entry.fetch('trailing_gap')
      gap = Ast::Merge::Layout::Gap.new(
        kind: gap_data.fetch('kind').to_sym,
        start_line: gap_data.fetch('start_line'),
        end_line: gap_data.fetch('end_line'),
        lines: gap_data.fetch('lines'),
        before_owner: owner,
        after_owner: later,
        controller_side: gap_data.fetch('controller_side').to_sym
      )
      analysis = RemovedOwnerAnalysis.new(
        lines: entry.fetch('source'),
        attachment: RemovedOwnerAttachment.new(leading_region: RemovedOwnerRegion.new(start_line: 1, end_line: 1,
                                                                                      normalized_content: entry.fetch('leading_segment_lines').first),
                                               trailing_region: region,
                                               trailing_gap: gap)
      )
      actual_lines = Harness.new.removed_owner_preserved_lines_for(
        owner, analysis, inline_lines: entry.fetch('inline_lines')
      )
      actual_numbers = Harness.new.removed_owner_preserved_line_numbers_for(
        owner, analysis, inline_line_numbers: entry.fetch('inline_line_numbers')
      )
      expect({ 'lines' => actual_lines, 'line_numbers' => actual_numbers })
        .to eq(entry.fetch('expected')), entry.fetch('name')
    end
  end
end
