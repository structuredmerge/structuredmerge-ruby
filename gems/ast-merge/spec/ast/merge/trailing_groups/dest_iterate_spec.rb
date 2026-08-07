# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Merge::TrailingGroups::DestIterate do
  let(:test_class) do
    Class.new do
      include Ast::Merge::TrailingGroups::DestIterate
    end
  end

  let(:instance) { test_class.new }

  # Helper to create mock nodes
  def mock_node(name, sig: nil)
    double("Node:#{name}", name: name, sig: sig)
  end

  describe '#build_dest_iterate_trailing_groups' do
    context 'when add_template_only_nodes is false' do
      it 'returns empty groups and empty matched set' do
        groups, matched = instance.build_dest_iterate_trailing_groups(
          template_nodes: [mock_node(:a)],
          dest_sigs: Set[:sig_a],
          signature_for: ->(_node) { :sig_a },
          add_template_only_nodes: false
        )
        expect(groups).to eq({})
        expect(matched).to be_empty
      end
    end

    context 'with signature-based matching' do
      it 'detects matched nodes by signature presence in dest_sigs' do
        nodes = [mock_node(:matched, sig: :s1), mock_node(:tpl_only, sig: :s2)]
        groups, matched = instance.build_dest_iterate_trailing_groups(
          template_nodes: nodes,
          dest_sigs: Set[:s1],
          signature_for: lambda(&:sig)
        )
        expect(matched).to eq(Set[0])
        expect(groups[0]).to be_an(Array)
        expect(groups[0].first[:index]).to eq(1)
      end
    end

    context 'with refined match detection' do
      it 'treats nodes in refined_template_ids as matched' do
        nodes = [mock_node(:refined), mock_node(:tpl_only)]
        groups, matched = instance.build_dest_iterate_trailing_groups(
          template_nodes: nodes,
          dest_sigs: Set.new, # no signature matches
          signature_for: ->(_node) { nil },
          refined_template_ids: Set[nodes[0].object_id]
        )
        expect(matched).to eq(Set[0])
        expect(groups[0].first[:index]).to eq(1)
      end
    end

    context 'with trailing_group_node_matched? override' do
      it 'uses the hook for additional match criteria' do
        klass = Class.new do
          include Ast::Merge::TrailingGroups::DestIterate

          def trailing_group_node_matched?(node, _signature)
            node.name == :freeze
          end
        end

        inst = klass.new
        nodes = [mock_node(:freeze), mock_node(:tpl_only)]
        groups, matched = inst.build_dest_iterate_trailing_groups(
          template_nodes: nodes,
          dest_sigs: Set.new,
          signature_for: ->(_node) { nil }
        )
        expect(matched).to eq(Set[0])
        expect(groups[0].first[:index]).to eq(1)
      end
    end

    context 'with custom entry_builder' do
      it 'passes the builder through to Core' do
        nodes = [mock_node(:m), mock_node(:t)]
        _, _matched = instance.build_dest_iterate_trailing_groups(
          template_nodes: nodes,
          dest_sigs: Set[nodes[0].sig],
          signature_for: lambda(&:name),
          entry_builder: ->(node, idx) { { item: node, index: idx } }
        )
        # m is at index 0 (matched because name :m is not in dest_sigs Set[nil])
        # Actually, let's use explicit sig matching:
        nodes2 = [mock_node(:m, sig: :s1), mock_node(:t, sig: :s2)]
        groups2, _matched2 = instance.build_dest_iterate_trailing_groups(
          template_nodes: nodes2,
          dest_sigs: Set[:s1],
          signature_for: lambda(&:sig),
          entry_builder: ->(node, idx) { { item: node, index: idx } }
        )
        expect(groups2[0].first[:item]).to eq(nodes2[1])
        expect(groups2[0].first).not_to have_key(:node)
      end
    end

    context 'with complex interleaving' do
      it 'produces correct groups for prefix, interior, and tail positions' do
        # Template: [tpl0, matched1, tpl2, tpl3, matched4, tpl5]
        nodes = 6.times.map { |i| mock_node(:"n#{i}", sig: :"s#{i}") }
        groups, matched = instance.build_dest_iterate_trailing_groups(
          template_nodes: nodes,
          dest_sigs: Set[:s1, :s4],
          signature_for: lambda(&:sig)
        )

        expect(matched).to eq(Set[1, 4])
        expect(groups[:prefix].map { |e| e[:index] }).to eq([0])
        expect(groups[1].map { |e| e[:index] }).to eq([2, 3])
        expect(groups[4].map { |e| e[:index] }).to eq([5])
      end
    end
  end

  describe '#emit_prefix_trailing_group' do
    it 'emits all prefix entries and marks them consumed' do
      groups = { prefix: [{ node: :a, index: 0 }, { node: :b, index: 1 }] }
      consumed = Set.new
      emitted = []

      instance.emit_prefix_trailing_group(groups, consumed) { |info| emitted << info }

      expect(emitted.map { |e| e[:node] }).to eq(%i[a b])
      expect(consumed).to eq(Set[0, 1])
    end

    it 'skips already-consumed entries' do
      groups = { prefix: [{ node: :a, index: 0 }, { node: :b, index: 1 }] }
      consumed = Set[0]
      emitted = []

      instance.emit_prefix_trailing_group(groups, consumed) { |info| emitted << info }

      expect(emitted.map { |e| e[:node] }).to eq([:b])
    end

    it 'does nothing when no :prefix group exists' do
      groups = { 0 => [{ node: :a, index: 1 }] }
      consumed = Set.new
      emitted = []

      instance.emit_prefix_trailing_group(groups, consumed) { |info| emitted << info }

      expect(emitted).to be_empty
    end
  end

  describe '#trailing_group_node_matched?' do
    it 'returns false by default' do
      expect(instance.trailing_group_node_matched?(mock_node(:x), :sig)).to be false
    end
  end
end
