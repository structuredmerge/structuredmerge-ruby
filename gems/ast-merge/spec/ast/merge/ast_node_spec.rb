# frozen_string_literal: true

RSpec.describe Ast::Merge::AstNode do
  let(:location) do
    described_class::Location.new(
      start_line: 1,
      end_line: 3,
      start_column: 0,
      end_column: 10
    )
  end

  let(:source) { "line one\nline two\nline three" }
  let(:slice) { 'line two' }

  let(:node) { described_class.new(slice: slice, location: location, source: source) }

  describe 'Point struct' do
    let(:point) { described_class::Point.new(row: 5, column: 10) }

    describe '#[]' do
      it 'accesses row by symbol' do
        expect(point[:row]).to eq(5)
      end

      it 'accesses column by symbol' do
        expect(point[:column]).to eq(10)
      end

      it 'accesses row by string' do
        expect(point['row']).to eq(5)
      end

      it 'accesses column by string' do
        expect(point['column']).to eq(10)
      end

      it 'returns nil for unknown key' do
        expect(point[:unknown]).to be_nil
      end
    end

    describe '#to_h' do
      it 'returns hash representation' do
        expect(point.to_h).to eq({ row: 5, column: 10 })
      end
    end

    describe '#to_s' do
      it 'returns string representation' do
        expect(point.to_s).to eq('(5, 10)')
      end
    end

    describe '#inspect' do
      it 'returns detailed inspect string' do
        expect(point.inspect).to eq('#<Ast::Merge::AstNode::Point row=5 column=10>')
      end
    end
  end

  describe 'Location struct' do
    let(:loc) do
      described_class::Location.new(
        start_line: 5,
        end_line: 10,
        start_column: 0,
        end_column: 20
      )
    end

    describe '#cover?' do
      it 'returns true for lines within range' do
        expect(loc.cover?(5)).to be true
        expect(loc.cover?(7)).to be true
        expect(loc.cover?(10)).to be true
      end

      it 'returns false for lines outside range' do
        expect(loc.cover?(4)).to be false
        expect(loc.cover?(11)).to be false
      end
    end
  end

  describe '#initialize' do
    it 'sets slice' do
      expect(node.slice).to eq(slice)
    end

    it 'sets location' do
      expect(node.location).to eq(location)
    end

    it 'sets source' do
      expect(node.source).to eq(source)
    end

    it 'source is optional' do
      node_without_source = described_class.new(slice: slice, location: location)
      expect(node_without_source.source).to be_nil
    end
  end

  describe '#inner_node' do
    it 'returns self' do
      expect(node.inner_node).to eq(node)
    end
  end

  describe '#type' do
    it 'derives type from class name' do
      expect(node.type).to eq('ast_node')
    end
  end

  describe '#kind' do
    it 'is aliased to type' do
      expect(node.kind).to eq(node.type)
    end
  end

  describe '#text' do
    it 'returns slice as string' do
      expect(node.text).to eq(slice)
    end

    it 'handles nil slice' do
      node_nil = described_class.new(slice: nil, location: location)
      expect(node_nil.text).to eq('')
    end
  end

  describe '#start_byte' do
    it 'calculates byte offset from source' do
      # "line one\n" = 9 bytes, then we're at start of line 2
      # But our location starts at line 1, so it should be 0
      loc = described_class::Location.new(start_line: 1, end_line: 1, start_column: 0, end_column: 8)
      n = described_class.new(slice: 'line one', location: loc, source: source)
      expect(n.start_byte).to eq(0)
    end

    it 'returns 0 when source is nil' do
      node_no_source = described_class.new(slice: slice, location: location)
      expect(node_no_source.start_byte).to eq(0)
    end

    it 'returns 0 when location is nil' do
      node_no_loc = described_class.new(slice: slice, location: nil)
      expect(node_no_loc.start_byte).to eq(0)
    end

    it 'handles multi-line offset calculation' do
      loc = described_class::Location.new(start_line: 2, end_line: 2, start_column: 5, end_column: 8)
      n = described_class.new(slice: 'two', location: loc, source: source)
      # Line 1 has 9 bytes ("line one\n"), then column 5
      expect(n.start_byte).to eq(14)
    end
  end

  describe '#end_byte' do
    it 'returns start_byte plus slice bytesize' do
      expect(node.end_byte).to eq(node.start_byte + slice.bytesize)
    end
  end

  describe '#start_point' do
    it 'returns Point with 0-based row' do
      expect(node.start_point.row).to eq(0) # line 1 becomes row 0
      expect(node.start_point.column).to eq(0)
    end

    it 'handles nil location gracefully' do
      node_no_loc = described_class.new(slice: slice, location: nil)
      expect(node_no_loc.start_point.row).to eq(0)
      expect(node_no_loc.start_point.column).to eq(0)
    end
  end

  describe '#end_point' do
    it 'returns Point with 0-based row' do
      expect(node.end_point.row).to eq(2) # line 3 becomes row 2
      expect(node.end_point.column).to eq(10)
    end

    it 'handles nil location gracefully' do
      node_no_loc = described_class.new(slice: slice, location: nil)
      expect(node_no_loc.end_point.row).to eq(0)
      expect(node_no_loc.end_point.column).to eq(0)
    end
  end

  describe '#children' do
    it 'returns empty array by default' do
      expect(node.children).to eq([])
    end
  end

  describe '#child_count' do
    it 'returns children size' do
      expect(node.child_count).to eq(0)
    end
  end

  describe '#child' do
    it 'returns nil for any index on empty children' do
      expect(node.child(0)).to be_nil
    end
  end

  describe '#named?' do
    it 'returns true' do
      expect(node.named?).to be true
    end
  end

  describe '#structural?' do
    it 'returns true' do
      expect(node.structural?).to be true
    end
  end

  describe '#has_error?' do
    it 'returns false' do
      expect(node.has_error?).to be false
    end
  end

  describe '#missing?' do
    it 'returns false' do
      expect(node.missing?).to be false
    end
  end

  describe '#each' do
    it 'returns enumerator when no block given' do
      expect(node.each).to be_an(Enumerator)
    end

    it 'iterates over children when block given' do
      collected = []
      node.each { |c| collected << c }
      expect(collected).to eq([])
    end
  end

  describe '#signature' do
    it 'returns array with type and normalized content' do
      expect(node.signature).to eq([:ast_node, 'line two'])
    end
  end

  describe '#normalized_content' do
    it 'returns stripped slice' do
      node_whitespace = described_class.new(slice: '  content  ', location: location)
      expect(node_whitespace.normalized_content).to eq('content')
    end
  end

  describe '#<=>' do
    let(:other_location) do
      described_class::Location.new(start_line: 5, end_line: 6, start_column: 0, end_column: 10)
    end
    let(:other_node) { described_class.new(slice: 'other', location: other_location, source: source) }

    it 'compares by start_byte' do
      expect(node <=> other_node).to eq(-1)
    end

    it 'returns nil for non-comparable objects' do
      expect(node <=> 'string').to be_nil
    end

    context 'with same start_byte' do
      let(:same_start_location) do
        described_class::Location.new(start_line: 1, end_line: 1, start_column: 0, end_column: 5)
      end
      let(:same_start_node) { described_class.new(slice: 'line', location: same_start_location, source: source) }

      it 'compares by end_byte when start_byte is equal' do
        expect(node <=> same_start_node).to eq(1) # node has longer slice
      end
    end
  end

  describe '#inspect' do
    it 'returns human-readable representation' do
      expect(node.inspect).to match(/#<Ast::Merge::AstNode type=ast_node lines=1\.\.3>/)
    end

    it 'handles nil location' do
      node_no_loc = described_class.new(slice: slice, location: nil)
      expect(node_no_loc.inspect).to match(/lines=\.\./)
    end
  end

  describe '#to_s' do
    it 'returns slice as string' do
      expect(node.to_s).to eq(slice)
    end
  end

  describe '#unwrap' do
    it 'returns self' do
      expect(node.unwrap).to eq(node)
    end
  end

  describe 'SyntheticNode alias' do
    it 'is aliased to AstNode' do
      expect(Ast::Merge::SyntheticNode).to eq(described_class)
    end
  end
end
