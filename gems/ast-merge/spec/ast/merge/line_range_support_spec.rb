# frozen_string_literal: true

RSpec.describe Ast::Merge::LineRangeSupport do
  Location = Struct.new(:start_line, :end_line, keyword_init: true)
  Point = Struct.new(:row, keyword_init: true)

  class LineRangeHarness
    include Ast::Merge::LineRangeSupport

    public :object_start_line, :object_end_line, :source_line_at
  end

  subject(:harness) { LineRangeHarness.new }

  it 'reads explicit line ranges' do
    object = Struct.new(:start_line, :end_line).new(3, 5)

    expect(harness.object_start_line(object)).to eq(3)
    expect(harness.object_end_line(object)).to eq(5)
  end

  it 'reads location line ranges' do
    object = Struct.new(:location).new(Location.new(start_line: 7, end_line: 9))

    expect(harness.object_start_line(object)).to eq(7)
    expect(harness.object_end_line(object)).to eq(9)
  end

  it 'reads source_position line ranges' do
    object = Struct.new(:source_position).new({ start_line: 11, end_line: 13 })

    expect(harness.object_start_line(object)).to eq(11)
    expect(harness.object_end_line(object)).to eq(13)
  end

  it 'reads tree-sitter point line ranges' do
    object = Struct.new(:start_point, :end_point).new(Point.new(row: 16), Point.new(row: 18))

    expect(harness.object_start_line(object)).to eq(17)
    expect(harness.object_end_line(object)).to eq(19)
  end

  it 'reads normalized hash point line ranges' do
    object = Struct.new(:start_point, :end_point).new({ row: 20 }, { row: 22 })

    expect(harness.object_start_line(object)).to eq(21)
    expect(harness.object_end_line(object)).to eq(23)
  end

  it 'normalizes raw line objects' do
    analysis = Struct.new(:lines) do
      def line_at(line_number)
        lines[line_number - 1]
      end
    end.new([Struct.new(:raw).new('raw line')])

    expect(harness.source_line_at(analysis, 1)).to eq('raw line')
  end
end
