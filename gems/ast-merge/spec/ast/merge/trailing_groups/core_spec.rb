# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Merge::TrailingGroups::Core do
  let(:test_class) do
    Class.new do
      include Ast::Merge::TrailingGroups::Core

      # Expose private sorted_anchors for testing
      public :sorted_anchors
    end
  end

  let(:instance) { test_class.new }

  # Helper to create mock nodes with an identity
  def mock_node(name)
    double("Node:#{name}", name: name)
  end

  describe '#build_trailing_groups' do
    context 'with no template nodes' do
      it 'returns empty groups and empty matched set' do
        groups, matched = instance.build_trailing_groups(
          template_nodes: [],
          matched_predicate: ->(_node, _idx) { false }
        )
        expect(groups).to eq({})
        expect(matched).to be_empty
      end
    end

    context 'when all nodes are matched' do
      it 'returns empty groups and full matched set' do
        nodes = [mock_node(:a), mock_node(:b), mock_node(:c)]
        groups, matched = instance.build_trailing_groups(
          template_nodes: nodes,
          matched_predicate: ->(_node, _idx) { true }
        )
        expect(groups).to eq({})
        expect(matched).to eq(Set[0, 1, 2])
      end
    end

    context 'when all nodes are unmatched' do
      it 'puts all nodes in a :prefix group' do
        nodes = [mock_node(:x), mock_node(:y)]
        groups, matched = instance.build_trailing_groups(
          template_nodes: nodes,
          matched_predicate: ->(_node, _idx) { false }
        )
        expect(matched).to be_empty
        expect(groups.keys).to eq([:prefix])
        expect(groups[:prefix].map { |e| e[:index] }).to eq([0, 1])
      end
    end

    context 'with prefix template-only nodes before first match' do
      it 'groups prefix nodes under :prefix key' do
        nodes = [mock_node(:tpl1), mock_node(:tpl2), mock_node(:matched), mock_node(:tpl3)]
        groups, matched = instance.build_trailing_groups(
          template_nodes: nodes,
          matched_predicate: ->(_node, idx) { idx == 2 }
        )
        expect(matched).to eq(Set[2])
        expect(groups[:prefix].size).to eq(2)
        expect(groups[:prefix].map { |e| e[:index] }).to eq([0, 1])
        expect(groups[2].size).to eq(1)
        expect(groups[2].first[:index]).to eq(3)
      end
    end

    context 'with interleaved matched and template-only nodes' do
      it 'groups template-only nodes by preceding matched anchor' do
        # Template: [matched_0, tpl_1, tpl_2, matched_3, tpl_4, matched_5, tpl_6]
        nodes = 7.times.map { |i| mock_node(:"n#{i}") }
        groups, matched = instance.build_trailing_groups(
          template_nodes: nodes,
          matched_predicate: ->(_node, idx) { [0, 3, 5].include?(idx) }
        )
        expect(matched).to eq(Set[0, 3, 5])
        expect(groups.keys.sort_by { |k| k == :prefix ? -1 : k }).to eq([0, 3, 5])
        expect(groups[0].map { |e| e[:index] }).to eq([1, 2])
        expect(groups[3].map { |e| e[:index] }).to eq([4])
        expect(groups[5].map { |e| e[:index] }).to eq([6])
      end
    end

    context 'with trailing nodes after last match' do
      it 'groups tail nodes under the last matched anchor' do
        nodes = [mock_node(:m0), mock_node(:t1), mock_node(:t2)]
        groups, matched = instance.build_trailing_groups(
          template_nodes: nodes,
          matched_predicate: ->(_node, idx) { idx == 0 }
        )
        expect(matched).to eq(Set[0])
        expect(groups[0].map { |e| e[:index] }).to eq([1, 2])
      end
    end

    context 'with custom entry_builder' do
      it 'uses the custom builder for entry hashes' do
        nodes = [mock_node(:m), mock_node(:t)]
        groups, _matched = instance.build_trailing_groups(
          template_nodes: nodes,
          matched_predicate: ->(_node, idx) { idx == 0 },
          entry_builder: ->(node, idx) { { item: node, index: idx, custom: true } }
        )
        entry = groups[0].first
        expect(entry[:item]).to eq(nodes[1])
        expect(entry[:custom]).to be true
        expect(entry[:index]).to eq(1)
        expect(entry).not_to have_key(:node)
      end
    end
  end

  describe '#flush_ready_trailing_groups' do
    context 'with empty matched indices' do
      it 'does nothing' do
        emitted = []
        instance.flush_ready_trailing_groups(
          trailing_groups: { 0 => [{ node: :a, index: 1 }] },
          matched_indices: Set.new,
          consumed_indices: Set.new
        ) { |info| emitted << info }
        expect(emitted).to be_empty
      end
    end

    context 'when all anchors have been consumed (in-order)' do
      it 'flushes interior groups that are ready' do
        # Template: [m0, t1, m2, t3]
        groups = { 0 => [{ node: :t1, index: 1 }] }
        matched = Set[0, 2]
        consumed = Set[0, 2]
        emitted = []

        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }

        expect(emitted.map { |e| e[:node] }).to eq([:t1])
      end
    end

    context 'when not all preceding anchors consumed' do
      it 'does not flush the group' do
        # Template: [m0, m2, t3, m4]
        # Group anchored at 2 requires m0 and m2 consumed
        groups = { 2 => [{ node: :t3, index: 3 }] }
        matched = Set[0, 2, 4]
        consumed = Set[2] # m0 not consumed yet
        emitted = []

        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }

        expect(emitted).to be_empty
      end
    end

    context 'with tail groups (anchor >= last_matched)' do
      it 'defers tail groups — does not flush them' do
        groups = { 3 => [{ node: :tail, index: 4 }] }
        matched = Set[0, 3]
        consumed = Set[0, 3]
        emitted = []

        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }

        expect(emitted).to be_empty
      end
    end

    context 'with destination reordering' do
      it 'defers groups until prerequisites are met' do
        # Template: [m0, t1, m2, t3, m4]
        # Dest order: m4, m0, m2 — so m0 consumed after m4
        groups = {
          0 => [{ node: :t1, index: 1 }],
          2 => [{ node: :t3, index: 3 }]
        }
        matched = Set[0, 2, 4]
        consumed = Set[4] # only m4 consumed so far
        emitted = []

        # First flush: only m4 consumed — nothing ready
        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }
        expect(emitted).to be_empty

        # Consume m0
        consumed << 0
        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }
        expect(emitted.map { |e| e[:node] }).to eq([:t1])

        # Consume m2
        consumed << 2
        emitted.clear
        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }
        expect(emitted.map { |e| e[:node] }).to eq([:t3])
      end
    end

    context 'with already-consumed entries in a group' do
      it 'skips entries already consumed' do
        groups = { 0 => [{ node: :t1, index: 1 }, { node: :t2, index: 2 }] }
        matched = Set[0, 3]
        consumed = Set[0, 1, 3] # t1 already consumed
        emitted = []

        instance.flush_ready_trailing_groups(
          trailing_groups: groups,
          matched_indices: matched,
          consumed_indices: consumed
        ) { |info| emitted << info }

        expect(emitted.map { |e| e[:node] }).to eq([:t2])
      end
    end
  end

  describe '#emit_remaining_trailing_groups' do
    it 'emits all unconsumed non-prefix groups in anchor order' do
      groups = {
        :prefix => [{ node: :p, index: 0 }],
        1 => [{ node: :a, index: 2 }],
        5 => [{ node: :b, index: 6 }, { node: :c, index: 7 }]
      }
      consumed = Set[0] # prefix already consumed
      emitted = []

      instance.emit_remaining_trailing_groups(
        trailing_groups: groups,
        consumed_indices: consumed
      ) { |info| emitted << info }

      expect(emitted.map { |e| e[:node] }).to eq(%i[a b c])
    end

    it 'skips already-consumed entries' do
      groups = { 1 => [{ node: :a, index: 2 }, { node: :b, index: 3 }] }
      consumed = Set[2] # :a already consumed
      emitted = []

      instance.emit_remaining_trailing_groups(
        trailing_groups: groups,
        consumed_indices: consumed
      ) { |info| emitted << info }

      expect(emitted.map { |e| e[:node] }).to eq([:b])
    end

    it 'does not emit :prefix group' do
      groups = { prefix: [{ node: :p, index: 0 }] }
      consumed = Set.new
      emitted = []

      instance.emit_remaining_trailing_groups(
        trailing_groups: groups,
        consumed_indices: consumed
      ) { |info| emitted << info }

      expect(emitted).to be_empty
    end
  end

  describe '#sorted_anchors' do
    it 'sorts :prefix first, then integers ascending' do
      groups = { 5 => [], :prefix => [], 1 => [], 3 => [] }
      expect(instance.sorted_anchors(groups)).to eq([:prefix, 1, 3, 5])
    end
  end
end
