# frozen_string_literal: true

RSpec.describe Ast::Merge::Navigable::InjectionPointFinder do
  let(:nodes) do
    TestableNode.create_list(
      { type: :class, text: "class Foo\nend", start_line: 1 },
      { type: :constant, text: 'BAR = 1', start_line: 3 },
      { type: :method, text: 'def baz; end', start_line: 4 }
    )
  end

  let(:statements) { Ast::Merge::Navigable::Statement.build_list(nodes) }
  let(:finder) { described_class.new(statements) }

  describe '#find' do
    it 'finds injection point by type' do
      point = finder.find(type: :class, position: :first_child)
      expect(point).to be_a(Ast::Merge::Navigable::InjectionPoint)
      expect(point.anchor.type).to eq('class')
      expect(point.position).to eq(:first_child)
    end

    it 'finds injection point by text' do
      point = finder.find(text: 'BAR', position: :replace)
      expect(point.anchor.type).to eq('constant')
    end

    it 'returns nil when no match' do
      point = finder.find(type: :module, position: :after)
      expect(point).to be_nil
    end

    it 'includes metadata about the match' do
      point = finder.find(type: :method, position: :before)
      expect(point.metadata[:match]).to include(type: :method)
    end

    context 'with boundary_type' do
      it 'finds boundary by type' do
        point = finder.find(type: :class, position: :replace, boundary_type: :method)
        expect(point.boundary).not_to be_nil
        expect(point.boundary.type).to eq('method')
      end
    end

    context 'with boundary_text' do
      it 'finds boundary by text pattern' do
        point = finder.find(type: :class, position: :replace, boundary_text: /baz/)
        expect(point.boundary).not_to be_nil
        expect(point.boundary.text).to include('baz')
      end
    end

    context 'with boundary_matcher proc' do
      it 'uses custom matcher for boundary' do
        matcher = ->(stmt) { stmt.type == 'method' }
        point = finder.find(type: :class, position: :replace, boundary_matcher: matcher)
        expect(point.boundary).not_to be_nil
        expect(point.boundary.type).to eq('method')
      end
    end

    context 'with boundary_same_or_shallower' do
      # For tree-depth testing we need nodes with parent relationships.
      # TreeHaver::Node doesn't track parents, so we use mocks for this specific test.
      # The tree_depth is calculated via tree_parent chain.
      let(:grandparent) do
        node = Object.new
        allow(node).to receive_messages(type: 'document', text: '', parent: nil)
        node
      end

      let(:parent) do
        node = Object.new
        allow(node).to receive_messages(type: 'section', text: '', parent: grandparent)
        node
      end

      let(:nested_nodes) do
        child = Object.new
        allow(child).to receive_messages(
          type: 'heading',
          text: '# Child',
          source_position: { start_line: 1, end_line: 1 },
          parent: parent
        )

        deeper = Object.new
        deeper_parent = Object.new
        allow(deeper_parent).to receive_messages(type: 'subsection', text: '', parent: parent)
        allow(deeper).to receive_messages(
          type: 'paragraph',
          text: 'Content',
          source_position: { start_line: 2, end_line: 2 },
          parent: deeper_parent
        )

        sibling = Object.new
        allow(sibling).to receive_messages(
          type: 'heading',
          text: '# Sibling',
          source_position: { start_line: 3, end_line: 3 },
          parent: parent
        )

        [child, deeper, sibling]
      end

      let(:statements) { Ast::Merge::Navigable::Statement.build_list(nested_nodes) }
      let(:finder) { described_class.new(statements) }

      it 'finds boundary at same or shallower depth' do
        point = finder.find(type: :heading, position: :replace, boundary_same_or_shallower: true)
        expect(point).not_to be_nil
        # The boundary should be the sibling heading (same depth), not the deeper paragraph
        expect(point.boundary&.type).to eq('heading')
        expect(point.boundary&.index).to eq(2)
      end

      it 'can filter boundary by type with depth check' do
        point = finder.find(
          type: :heading,
          position: :replace,
          boundary_type: :heading,
          boundary_same_or_shallower: true
        )
        expect(point.boundary).not_to be_nil
        expect(point.boundary.type).to eq('heading')
      end
    end
  end

  describe '#find_all' do
    let(:nodes_with_duplicates) do
      TestableNode.create_list(
        { type: :constant, text: 'CONST_0 = 0', start_line: 1 },
        { type: :constant, text: 'CONST_1 = 1', start_line: 2 },
        { type: :constant, text: 'CONST_2 = 2', start_line: 3 }
      )
    end

    let(:statements) { Ast::Merge::Navigable::Statement.build_list(nodes_with_duplicates) }
    let(:finder) { described_class.new(statements) }

    it 'finds all matching injection points' do
      points = finder.find_all(type: :constant, position: :replace)
      expect(points.size).to eq(3)
      expect(points).to all(be_a(Ast::Merge::Navigable::InjectionPoint))
    end
  end
end
