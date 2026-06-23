# frozen_string_literal: true

RSpec.describe Ast::Merge::TokenMatchRefiner do
  before { stub_const('NodeStub', Struct.new(:text, :type, keyword_init: true)) }

  let(:refiner) { described_class.new(threshold: 0.35) }

  describe '#call' do
    it 'matches nodes with similar text' do
      t_nodes = [NodeStub.new(text: 'Commit changes to the branch', type: :list_item)]
      d_nodes = [NodeStub.new(text: 'Commit your changes', type: :list_item)]

      matches = refiner.call(t_nodes, d_nodes)

      expect(matches.size).to eq(1)
      expect(matches[0].template_node).to eq(t_nodes[0])
      expect(matches[0].dest_node).to eq(d_nodes[0])
      expect(matches[0].score).to be > 0.35
    end

    it 'does not match nodes with unrelated text' do
      t_nodes = [NodeStub.new(text: 'Fork the repository', type: :list_item)]
      d_nodes = [NodeStub.new(text: 'Run the test suite', type: :list_item)]

      matches = refiner.call(t_nodes, d_nodes)

      expect(matches).to be_empty
    end

    it 'performs greedy best-first matching' do
      t_nodes = [
        NodeStub.new(text: 'Create a feature branch', type: :list_item),
        NodeStub.new(text: 'Push to the remote branch', type: :list_item)
      ]
      d_nodes = [
        NodeStub.new(text: 'Create your feature branch', type: :list_item),
        NodeStub.new(text: 'Push to the remote', type: :list_item)
      ]

      matches = refiner.call(t_nodes, d_nodes)

      expect(matches.size).to eq(2)
      # Each template node matches exactly one dest node
      matched_templates = matches.map(&:template_node)
      matched_dests = matches.map(&:dest_node)
      expect(matched_templates.uniq.size).to eq(2)
      expect(matched_dests.uniq.size).to eq(2)
    end

    it 'respects node_types filter' do
      refiner_filtered = described_class.new(threshold: 0.35, node_types: [:paragraph])
      t_nodes = [NodeStub.new(text: 'Commit changes', type: :list_item)]
      d_nodes = [NodeStub.new(text: 'Commit your changes', type: :list_item)]

      matches = refiner_filtered.call(t_nodes, d_nodes)
      expect(matches).to be_empty
    end

    it 'uses custom text_extractor' do
      custom_refiner = described_class.new(
        threshold: 0.35,
        text_extractor: ->(node) { node.text.upcase }
      )
      t_nodes = [NodeStub.new(text: 'commit changes', type: :item)]
      d_nodes = [NodeStub.new(text: 'commit your changes', type: :item)]

      matches = custom_refiner.call(t_nodes, d_nodes)
      expect(matches.size).to eq(1)
    end

    it 'handles empty node lists' do
      expect(refiner.call([], [])).to be_empty
      expect(refiner.call([NodeStub.new(text: 'hello', type: :item)], [])).to be_empty
      expect(refiner.call([], [NodeStub.new(text: 'hello', type: :item)])).to be_empty
    end

    it 'handles nodes with emoji text' do
      t_nodes = [NodeStub.new(text: '🪙 Token resolution step', type: :item)]
      d_nodes = [NodeStub.new(text: '🍲 Token resolution phase', type: :item)]

      matches = refiner.call(t_nodes, d_nodes)
      expect(matches.size).to eq(1)
      expect(matches[0].score).to be > 0.35
    end
  end

  describe 'threshold behavior' do
    it 'accepts matches at exactly the threshold' do
      # Build tokens with known Jaccard ≥ 0.5
      # {alpha, beta, gamma} vs {alpha, beta, delta} → 2/4 = 0.5
      t_nodes = [NodeStub.new(text: 'alpha beta gamma', type: :item)]
      d_nodes = [NodeStub.new(text: 'alpha beta delta', type: :item)]

      half_threshold = described_class.new(threshold: 0.5)
      matches = half_threshold.call(t_nodes, d_nodes)
      expect(matches.size).to eq(1)
    end

    it 'rejects matches below threshold' do
      t_nodes = [NodeStub.new(text: 'alpha beta gamma delta', type: :item)]
      d_nodes = [NodeStub.new(text: 'alpha epsilon zeta eta', type: :item)]

      high_threshold = described_class.new(threshold: 0.5)
      matches = high_threshold.call(t_nodes, d_nodes)
      # Jaccard = 1/6 ≈ 0.167 < 0.5
      expect(matches).to be_empty
    end
  end
end
