# frozen_string_literal: true

RSpec.describe Ast::Merge::Navigable::Statement do
  # Create test nodes using TestableNode which conforms to TreeHaver API
  let(:mock_node) { TestableNode.create(type: :paragraph, text: 'Test content', start_line: 1) }
  let(:class_node) { TestableNode.create(type: :class, text: "class Foo\nend", start_line: 1) }

  describe '.build_list' do
    let(:nodes) { [mock_node, class_node, mock_node] }
    let(:statements) { described_class.build_list(nodes) }

    it 'creates Statement for each node' do
      expect(statements.size).to eq(3)
      expect(statements).to all(be_a(described_class))
    end

    it 'assigns correct indices' do
      expect(statements.map(&:index)).to eq([0, 1, 2])
    end

    it 'links prev_statement and next_statement' do
      expect(statements[0].prev_statement).to be_nil
      expect(statements[0].next_statement).to eq(statements[1])

      expect(statements[1].prev_statement).to eq(statements[0])
      expect(statements[1].next_statement).to eq(statements[2])

      expect(statements[2].prev_statement).to eq(statements[1])
      expect(statements[2].next_statement).to be_nil
    end
  end

  describe 'flat list navigation' do
    let(:nodes) { [mock_node, class_node, mock_node] }
    let(:statements) { described_class.build_list(nodes) }

    it '#next returns next_statement' do
      expect(statements[0].next).to eq(statements[1])
    end

    it '#previous returns prev_statement' do
      expect(statements[1].previous).to eq(statements[0])
    end

    it '#first? returns true for first statement' do
      expect(statements[0].first?).to be true
      expect(statements[1].first?).to be false
    end

    it '#last? returns true for last statement' do
      expect(statements[2].last?).to be true
      expect(statements[1].last?).to be false
    end
  end

  describe '#each_following' do
    let(:nodes) { [mock_node, class_node, mock_node] }
    let(:statements) { described_class.build_list(nodes) }

    it 'yields each following statement' do
      collected = []
      statements[0].each_following do |s|
        collected << s
        true
      end
      expect(collected).to eq([statements[1], statements[2]])
    end

    it 'returns enumerator when no block given' do
      expect(statements[0].each_following).to be_a(Enumerator)
    end
  end

  describe '#take_until' do
    let(:nodes) do
      TestableNode.create_list(
        { type: :paragraph, text: 'First', start_line: 1 },
        { type: :paragraph, text: 'Second', start_line: 2 },
        { type: :heading, text: 'Heading', start_line: 3 },
        { type: :paragraph, text: 'Third', start_line: 4 }
      )
    end
    let(:statements) { described_class.build_list(nodes) }

    it 'collects statements until condition is true' do
      result = statements[0].take_until { |s| s.type == 'heading' }
      expect(result.size).to eq(1)
      expect(result[0].type).to eq('paragraph')
    end

    it 'returns empty array when no statements before condition' do
      result = statements[0].take_until { |s| s.type == 'paragraph' }
      expect(result).to eq([])
    end

    it 'returns all following when condition never true' do
      result = statements[0].take_until { |s| s.type == 'nonexistent' }
      expect(result.size).to eq(3)
    end
  end

  describe 'tree navigation' do
    context 'with parser-backed node that has tree methods' do
      let(:parent_mock) { Object.new }
      let(:next_mock) { Object.new }
      let(:tree_node) do
        node = Object.new
        allow(node).to receive_messages(
          type: :child,
          text: 'child content',
          parent: parent_mock,
          next: next_mock
        )
        node
      end
      let(:statement) { described_class.new(tree_node, index: 0) }

      it '#tree_parent returns parent' do
        expect(statement.tree_parent).to eq(parent_mock)
      end

      it '#tree_next returns next sibling' do
        expect(statement.tree_next).to eq(next_mock)
      end

      it '#has_tree_navigation? returns true' do
        expect(statement.has_tree_navigation?).to be true
      end

      it '#synthetic? returns false' do
        expect(statement.synthetic?).to be false
      end
    end

    context 'with synthetic node (no tree methods)' do
      let(:synthetic_node) do
        node = Object.new
        allow(node).to receive_messages(type: :synthetic, text: 'synthetic')
        node
      end
      let(:statement) { described_class.new(synthetic_node, index: 0) }

      it '#tree_parent returns nil' do
        expect(statement.tree_parent).to be_nil
      end

      it '#has_tree_navigation? returns false' do
        expect(statement.has_tree_navigation?).to be false
      end

      it '#synthetic? returns true' do
        expect(statement.synthetic?).to be true
      end
    end

    context 'with nested tree structure' do
      let(:grandparent) do
        node = Object.new
        allow(node).to receive_messages(type: 'root', parent: nil)
        node
      end

      let(:parent) do
        node = Object.new
        allow(node).to receive_messages(type: 'section', parent: grandparent)
        node
      end

      let(:child) do
        node = Object.new
        allow(node).to receive_messages(type: 'paragraph', text: 'content', parent: parent)
        node
      end

      let(:sibling) do
        node = Object.new
        allow(node).to receive_messages(type: 'paragraph', text: 'sibling', parent: parent)
        node
      end

      let(:root_stmt) { described_class.new(grandparent, index: 0) }
      let(:child_stmt) { described_class.new(child, index: 1) }
      let(:sibling_stmt) { described_class.new(sibling, index: 2) }

      describe '#tree_depth' do
        it 'returns 0 for root level nodes' do
          expect(root_stmt.tree_depth).to eq(0)
        end

        it "returns 1 for grandparent's children" do
          parent_stmt = described_class.new(parent, index: 0)
          expect(parent_stmt.tree_depth).to eq(1)
        end

        it "returns 2 for parent's children" do
          expect(child_stmt.tree_depth).to eq(2)
        end
      end

      describe '#same_or_shallower_than?' do
        it 'returns true for same depth' do
          expect(sibling_stmt.same_or_shallower_than?(child_stmt)).to be true
        end

        it 'returns true for shallower depth' do
          expect(root_stmt.same_or_shallower_than?(child_stmt)).to be true
        end

        it 'returns false for deeper depth' do
          expect(child_stmt.same_or_shallower_than?(root_stmt)).to be false
        end

        it 'accepts integer depth value' do
          expect(child_stmt.same_or_shallower_than?(2)).to be true
          expect(child_stmt.same_or_shallower_than?(3)).to be true
          expect(child_stmt.same_or_shallower_than?(1)).to be false
        end
      end
    end
  end

  describe '#tree_previous' do
    context 'when node responds to previous' do
      let(:prev_node) { Object.new }
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :node, text: 'text', previous: prev_node)
        n
      end
      let(:statement) { described_class.new(node, index: 1) }

      it 'returns previous sibling' do
        expect(statement.tree_previous).to eq(prev_node)
      end
    end

    context 'when node does not respond to previous' do
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :node, text: 'text')
        n
      end
      let(:statement) { described_class.new(node, index: 0) }

      it 'returns nil' do
        expect(statement.tree_previous).to be_nil
      end
    end
  end

  describe '#tree_children' do
    context 'when node responds to each' do
      let(:children) { [Object.new, Object.new] }
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :parent, text: 'parent')
        allow(n).to receive(:each).and_yield(children[0]).and_yield(children[1])
        allow(n).to receive(:to_a).and_return(children)
        n
      end
      let(:statement) { described_class.new(node, index: 0) }

      it 'returns children array' do
        expect(statement.tree_children).to eq(children)
      end
    end

    context 'when node responds to children' do
      let(:children) { [Object.new, Object.new] }
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :parent, text: 'parent', children: children)
        n
      end
      let(:statement) { described_class.new(node, index: 0) }

      it 'returns children' do
        expect(statement.tree_children).to eq(children)
      end
    end

    context 'when node has neither each nor children' do
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :leaf, text: 'leaf')
        n
      end
      let(:statement) { described_class.new(node, index: 0) }

      it 'returns empty array' do
        expect(statement.tree_children).to eq([])
      end
    end
  end

  describe '#tree_first_child' do
    context 'when node responds to first_child' do
      let(:first_child) { Object.new }
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :parent, text: 'parent', first_child: first_child)
        n
      end
      let(:statement) { described_class.new(node, index: 0) }

      it 'returns first child' do
        expect(statement.tree_first_child).to eq(first_child)
      end
    end
  end

  describe '#tree_last_child' do
    context 'when node responds to last_child' do
      let(:last_child) { Object.new }
      let(:node) do
        n = Object.new
        allow(n).to receive_messages(type: :parent, text: 'parent', last_child: last_child)
        n
      end
      let(:statement) { described_class.new(node, index: 0) }

      it 'returns last child' do
        expect(statement.tree_last_child).to eq(last_child)
      end
    end
  end

  describe '#type' do
    it 'delegates to node.type' do
      statement = described_class.new(mock_node, index: 0)
      expect(statement.type).to eq('paragraph')
    end
  end

  describe "#type when node doesn't respond to type" do
    let(:typeless_node) do
      Class.new do
        def text
          'content'
        end
      end.new
    end
    let(:statement) { described_class.new(typeless_node, index: 0) }

    it 'derives type from class name' do
      expect(statement.type).to be_a(String)
    end
  end

  describe '#text' do
    context 'when node conforms to TreeHaver API' do
      it 'delegates to node.text' do
        statement = described_class.new(mock_node, index: 0)
        expect(statement.text).to eq('Test content')
      end
    end

    context 'with empty text' do
      let(:empty_node) { TestableNode.create(type: :empty, text: '', start_line: 1) }

      it 'returns empty string' do
        statement = described_class.new(empty_node, index: 0)
        expect(statement.text).to eq('')
      end
    end

    context 'with multiline text' do
      let(:multiline_node) { TestableNode.create(type: :block, text: "line1\nline2\nline3", start_line: 1) }

      it 'returns the full text' do
        statement = described_class.new(multiline_node, index: 0)
        expect(statement.text).to eq("line1\nline2\nline3")
      end
    end
  end

  describe "#source_position when node doesn't respond to source_position" do
    let(:no_pos_node) do
      node = Object.new
      allow(node).to receive_messages(type: :test, text: 'test')
      node
    end
    let(:statement) { described_class.new(no_pos_node, index: 0) }

    it 'returns nil' do
      expect(statement.source_position).to be_nil
    end

    it '#start_line returns nil' do
      expect(statement.start_line).to be_nil
    end

    it '#end_line returns nil' do
      expect(statement.end_line).to be_nil
    end
  end

  describe "#signature when node doesn't respond to signature" do
    let(:no_sig_node) do
      node = Object.new
      allow(node).to receive_messages(type: :test, text: 'test')
      node
    end
    let(:statement) { described_class.new(no_sig_node, index: 0) }

    it 'returns nil' do
      expect(statement.signature).to be_nil
    end
  end

  describe 'node attribute helpers' do
    describe '#type?' do
      let(:statement) { described_class.new(mock_node, index: 0) }

      it 'returns true for matching type' do
        expect(statement.type?(:paragraph)).to be true
        expect(statement.type?('paragraph')).to be true
      end

      it 'returns false for non-matching type' do
        expect(statement.type?(:heading)).to be false
      end
    end

    describe '#text_matches?' do
      let(:statement) { described_class.new(mock_node, index: 0) }

      it 'matches regex' do
        expect(statement.text_matches?(/Test/)).to be true
        expect(statement.text_matches?(/Missing/)).to be false
      end

      it 'matches substring' do
        expect(statement.text_matches?('content')).to be true
        expect(statement.text_matches?('missing')).to be false
      end
    end

    describe '#node_attribute' do
      let(:node_with_attrs) do
        node = Object.new
        allow(node).to receive_messages(
          type: :test,
          text: 'test',
          custom_attr: 'value'
        )
        node
      end
      let(:statement) { described_class.new(node_with_attrs, index: 0) }

      it 'returns attribute value' do
        expect(statement.node_attribute(:custom_attr)).to eq('value')
      end

      it 'returns nil for missing attribute' do
        expect(statement.node_attribute(:missing_attr)).to be_nil
      end

      it 'tries aliases' do
        expect(statement.node_attribute(:missing, :custom_attr)).to eq('value')
      end
    end
  end

  describe '#unwrapped_node' do
    context 'with wrapper node' do
      let(:inner) { Object.new }
      let(:wrapper) do
        w = Object.new
        allow(w).to receive_messages(type: :wrapper, text: '', inner_node: inner)
        w
      end
      let(:statement) { described_class.new(wrapper, index: 0) }

      it 'returns inner node' do
        expect(statement.unwrapped_node).to eq(inner)
      end
    end

    context 'with deeply nested wrappers' do
      let(:innermost) { Object.new }
      let(:middle) do
        m = Object.new
        allow(m).to receive(:inner_node).and_return(innermost)
        m
      end
      let(:outer) do
        o = Object.new
        allow(o).to receive_messages(type: :outer, text: '', inner_node: middle)
        o
      end
      let(:statement) { described_class.new(outer, index: 0) }

      it 'returns innermost node' do
        expect(statement.unwrapped_node).to eq(innermost)
      end
    end

    context 'with self-referencing inner_node' do
      let(:self_ref) do
        s = Object.new
        allow(s).to receive_messages(type: :self_ref, text: '')
        allow(s).to receive(:inner_node).and_return(s)
        s
      end
      let(:statement) { described_class.new(self_ref, index: 0) }

      it 'returns the node itself' do
        expect(statement.unwrapped_node).to eq(self_ref)
      end
    end
  end

  describe '#inspect' do
    let(:statement) { described_class.new(mock_node, index: 5) }

    it 'returns human-readable representation' do
      expect(statement.inspect).to match(/Navigable::Statement\[5\]/)
      expect(statement.inspect).to include('type=paragraph')
    end
  end

  describe '#to_s' do
    let(:long_text_node) { TestableNode.create(type: :long, text: 'a' * 100, start_line: 1) }
    let(:statement) { described_class.new(long_text_node, index: 0) }

    it 'returns truncated text' do
      expect(statement.to_s.length).to be <= 50
    end
  end

  describe '#method_missing' do
    let(:node_with_custom_method) do
      node = Object.new
      allow(node).to receive_messages(type: :custom, text: 'test', custom_method: 'custom_value')
      node
    end
    let(:statement) { described_class.new(node_with_custom_method, index: 0) }

    it 'delegates to node' do
      expect(statement.custom_method).to eq('custom_value')
    end

    it 'raises NoMethodError for unknown methods' do
      expect { statement.unknown_method }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    let(:node_with_custom_method) do
      node = Object.new
      allow(node).to receive_messages(type: :custom, text: 'test', custom_method: 'value')
      node
    end
    let(:statement) { described_class.new(node_with_custom_method, index: 0) }

    it 'returns true for methods node responds to' do
      expect(statement.respond_to?(:custom_method)).to be true
    end

    it "returns false for methods node doesn't respond to" do
      expect(statement.respond_to?(:unknown_method)).to be false
    end
  end

  describe '.find_matching' do
    let(:nodes) do
      TestableNode.create_list(
        { type: :class, text: 'class Foo', start_line: 1 },
        { type: :method, text: 'def bar', start_line: 2 },
        { type: :method, text: 'def baz', start_line: 3 }
      )
    end
    let(:statements) { described_class.build_list(nodes) }

    it 'finds by type' do
      matches = described_class.find_matching(statements, type: :method)
      expect(matches.size).to eq(2)
    end

    it 'finds by text' do
      matches = described_class.find_matching(statements, text: 'bar')
      expect(matches.size).to eq(1)
    end

    it 'finds by regex' do
      matches = described_class.find_matching(statements, text: /ba[rz]/)
      expect(matches.size).to eq(2)
    end

    it 'finds by block' do
      matches = described_class.find_matching(statements) { |s| s.type == 'class' }
      expect(matches.size).to eq(1)
    end
  end

  describe '.find_first' do
    let(:nodes) do
      TestableNode.create_list(
        { type: :method, text: 'def first', start_line: 1 },
        { type: :method, text: 'def second', start_line: 2 }
      )
    end
    let(:statements) { described_class.build_list(nodes) }

    it 'returns first match' do
      match = described_class.find_first(statements, type: :method)
      expect(match.text).to include('first')
    end

    it 'returns nil when no match' do
      match = described_class.find_first(statements, type: :class)
      expect(match).to be_nil
    end
  end
end
