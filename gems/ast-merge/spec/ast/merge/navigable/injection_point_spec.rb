# frozen_string_literal: true

RSpec.describe Ast::Merge::Navigable::InjectionPoint do
  let(:mock_node) do
    node = Object.new
    allow(node).to receive_messages(
      type: :paragraph,
      to_s: 'Content',
      source_position: { start_line: 1, end_line: 1 }
    )
    node
  end

  let(:anchor) { Ast::Merge::Navigable::Statement.new(mock_node, index: 0) }

  describe '#initialize' do
    it 'creates with valid position' do
      point = described_class.new(anchor: anchor, position: :before)
      expect(point.anchor).to eq(anchor)
      expect(point.position).to eq(:before)
    end

    it 'raises for invalid position' do
      expect do
        described_class.new(anchor: anchor, position: :invalid)
      end.to raise_error(ArgumentError, /Invalid position/)
    end

    it 'raises for boundary with non-replace position' do
      boundary = Ast::Merge::Navigable::Statement.new(mock_node, index: 1)
      expect do
        described_class.new(anchor: anchor, position: :before, boundary: boundary)
      end.to raise_error(ArgumentError, /boundary is only valid/)
    end

    it 'allows boundary with replace position' do
      boundary = Ast::Merge::Navigable::Statement.new(mock_node, index: 1)
      point = described_class.new(anchor: anchor, position: :replace, boundary: boundary)
      expect(point.boundary).to eq(boundary)
    end
  end

  describe '#replacement?' do
    it 'returns true for :replace' do
      point = described_class.new(anchor: anchor, position: :replace)
      expect(point.replacement?).to be true
    end

    it 'returns false for other positions' do
      point = described_class.new(anchor: anchor, position: :before)
      expect(point.replacement?).to be false
    end
  end

  describe '#child_injection?' do
    it 'returns true for :first_child and :last_child' do
      expect(described_class.new(anchor: anchor, position: :first_child).child_injection?).to be true
      expect(described_class.new(anchor: anchor, position: :last_child).child_injection?).to be true
    end

    it 'returns false for other positions' do
      expect(described_class.new(anchor: anchor, position: :before).child_injection?).to be false
    end
  end

  describe '#sibling_injection?' do
    it 'returns true for :before and :after' do
      expect(described_class.new(anchor: anchor, position: :before).sibling_injection?).to be true
      expect(described_class.new(anchor: anchor, position: :after).sibling_injection?).to be true
    end

    it 'returns false for other positions' do
      expect(described_class.new(anchor: anchor, position: :first_child).sibling_injection?).to be false
    end
  end

  describe '#replaced_statements' do
    let(:nodes) do
      (0..4).map do |i|
        node = Object.new
        allow(node).to receive_messages(
          type: :paragraph,
          to_s: "Content #{i}",
          source_position: { start_line: i + 1, end_line: i + 1 }
        )
        node
      end
    end

    let(:statements) { Ast::Merge::Navigable::Statement.build_list(nodes) }

    it 'returns empty for non-replacement' do
      point = described_class.new(anchor: statements[0], position: :before)
      expect(point.replaced_statements).to eq([])
    end

    it 'returns single anchor for replacement without boundary' do
      point = described_class.new(anchor: statements[1], position: :replace)
      expect(point.replaced_statements).to eq([statements[1]])
    end

    it 'returns range for replacement with boundary' do
      point = described_class.new(
        anchor: statements[1],
        position: :replace,
        boundary: statements[3]
      )
      expect(point.replaced_statements).to eq([statements[1], statements[2], statements[3]])
    end
  end

  describe '#start_line' do
    let(:nodes) do
      (0..2).map do |i|
        node = Object.new
        allow(node).to receive_messages(
          type: :paragraph,
          to_s: "Content #{i}",
          source_position: { start_line: (i + 1) * 10, end_line: (i + 1) * 10 + 5 }
        )
        node
      end
    end

    let(:statements) { Ast::Merge::Navigable::Statement.build_list(nodes) }

    it 'returns anchor start line' do
      point = described_class.new(anchor: statements[1], position: :replace)
      expect(point.start_line).to eq(20)
    end
  end

  describe '#end_line' do
    let(:nodes) do
      (0..2).map do |i|
        node = Object.new
        allow(node).to receive_messages(
          type: :paragraph,
          to_s: "Content #{i}",
          source_position: { start_line: (i + 1) * 10, end_line: (i + 1) * 10 + 5 }
        )
        node
      end
    end

    let(:statements) { Ast::Merge::Navigable::Statement.build_list(nodes) }

    it 'returns anchor end line when no boundary' do
      point = described_class.new(anchor: statements[1], position: :replace)
      expect(point.end_line).to eq(25)
    end

    it 'returns boundary end line when boundary present' do
      point = described_class.new(
        anchor: statements[0],
        position: :replace,
        boundary: statements[2]
      )
      expect(point.end_line).to eq(35)
    end
  end

  describe '#inspect' do
    let(:nodes) do
      2.times.map do |i|
        node = Object.new
        allow(node).to receive_messages(
          type: :paragraph,
          to_s: "Content #{i}",
          source_position: { start_line: i + 1, end_line: i + 1 }
        )
        node
      end
    end

    let(:statements) { Ast::Merge::Navigable::Statement.build_list(nodes) }

    it 'returns readable representation without boundary' do
      point = described_class.new(anchor: statements[0], position: :before)
      expect(point.inspect).to eq('#<Navigable::InjectionPoint position=before anchor=0>')
    end

    it 'returns readable representation with boundary' do
      point = described_class.new(
        anchor: statements[0],
        position: :replace,
        boundary: statements[1]
      )
      expect(point.inspect).to eq('#<Navigable::InjectionPoint position=replace anchor=0 to 1>')
    end
  end
end
