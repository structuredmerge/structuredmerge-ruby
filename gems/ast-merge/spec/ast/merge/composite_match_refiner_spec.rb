# frozen_string_literal: true

RSpec.describe Ast::Merge::CompositeMatchRefiner do
  before { stub_const('NodeStub', Struct.new(:text, :type, keyword_init: true)) }

  # A refiner that only matches nodes of a specific type
  let(:paragraph_refiner) do
    Ast::Merge::TokenMatchRefiner.new(threshold: 0.35, node_types: [:paragraph])
  end

  let(:comment_refiner) do
    Ast::Merge::TokenMatchRefiner.new(threshold: 0.35, node_types: [:comment])
  end

  let(:catch_all_refiner) do
    Ast::Merge::TokenMatchRefiner.new(threshold: 0.35)
  end

  describe '#initialize' do
    it 'accepts refiners as arguments' do
      composite = described_class.new(paragraph_refiner, comment_refiner)
      expect(composite.refiners).to eq([paragraph_refiner, comment_refiner])
    end

    it 'accepts an array of refiners' do
      composite = described_class.new([paragraph_refiner, comment_refiner])
      expect(composite.refiners).to eq([paragraph_refiner, comment_refiner])
    end

    it 'works with no arguments' do
      composite = described_class.new
      expect(composite.refiners).to be_empty
    end

    it 'strips nil arguments' do
      composite = described_class.new(paragraph_refiner, nil, comment_refiner)
      expect(composite.size).to eq(2)
    end
  end

  describe '#<<' do
    it 'appends a refiner' do
      composite = described_class.new
      composite << paragraph_refiner
      expect(composite.size).to eq(1)
    end

    it 'returns self for chaining' do
      composite = described_class.new
      result = composite << paragraph_refiner
      expect(result).to be(composite)
    end
  end

  describe '#call' do
    it 'returns empty array with no refiners' do
      composite = described_class.new
      t = [NodeStub.new(text: 'hello world again', type: :paragraph)]
      d = [NodeStub.new(text: 'hello world there', type: :paragraph)]
      expect(composite.call(t, d)).to eq([])
    end

    it 'delegates to a single refiner' do
      composite = described_class.new(catch_all_refiner)
      t = [NodeStub.new(text: 'Commit changes to branch', type: :paragraph)]
      d = [NodeStub.new(text: 'Commit your changes', type: :paragraph)]

      matches = composite.call(t, d)
      expect(matches.size).to eq(1)
      expect(matches[0].template_node).to eq(t[0])
      expect(matches[0].dest_node).to eq(d[0])
    end

    it 'chains refiners that target different types' do
      composite = described_class.new(paragraph_refiner, comment_refiner)

      t_nodes = [
        NodeStub.new(text: 'Create a feature branch', type: :paragraph),
        NodeStub.new(text: '# Install the dependencies first', type: :comment)
      ]
      d_nodes = [
        NodeStub.new(text: 'Create your feature branch', type: :paragraph),
        NodeStub.new(text: '# Install all dependencies', type: :comment)
      ]

      matches = composite.call(t_nodes, d_nodes)
      expect(matches.size).to eq(2)

      types = matches.map { |m| m.template_node.type }
      expect(types).to contain_exactly(:paragraph, :comment)
    end

    it 'second refiner only sees unmatched nodes from first' do
      # Both refiners accept all types, but first one consumes the match
      composite = described_class.new(catch_all_refiner, catch_all_refiner)

      t = [NodeStub.new(text: 'alpha beta gamma', type: :item)]
      d = [NodeStub.new(text: 'alpha beta delta', type: :item)]

      matches = composite.call(t, d)
      # First refiner matches them; second has nothing left
      expect(matches.size).to eq(1)
    end

    it 'accumulates matches from multiple refiners' do
      composite = described_class.new(paragraph_refiner, comment_refiner)

      t_nodes = [
        NodeStub.new(text: 'Fork the repository upstream', type: :paragraph),
        NodeStub.new(text: 'Push to the branch origin', type: :paragraph),
        NodeStub.new(text: '# Configuration settings block', type: :comment)
      ]
      d_nodes = [
        NodeStub.new(text: 'Fork the repository', type: :paragraph),
        NodeStub.new(text: 'Push to the remote branch', type: :paragraph),
        NodeStub.new(text: '# Configuration options block', type: :comment)
      ]

      matches = composite.call(t_nodes, d_nodes)
      expect(matches.size).to eq(3)
    end

    it 'handles empty node lists' do
      composite = described_class.new(catch_all_refiner)
      expect(composite.call([], [])).to be_empty
    end

    it 'handles no matches from any refiner' do
      composite = described_class.new(paragraph_refiner, comment_refiner)

      t = [NodeStub.new(text: 'completely unrelated text here', type: :unknown)]
      d = [NodeStub.new(text: 'nothing in common whatsoever', type: :unknown)]

      matches = composite.call(t, d)
      expect(matches).to be_empty
    end

    it 'passes context through to each refiner' do
      context_spy = nil
      spy_refiner = lambda { |_t, _d, ctx|
        context_spy = ctx
        []
      }

      composite = described_class.new(spy_refiner)
      t = [NodeStub.new(text: 'something here', type: :item)]
      d = [NodeStub.new(text: 'unrelated text', type: :item)]
      composite.call(t, d, { foo: :bar })
      expect(context_spy).to eq({ foo: :bar })
    end

    it 'stops early when template nodes exhausted' do
      call_count = 0
      counting_refiner = lambda { |_t, _d, _ctx|
        call_count += 1
        []
      }

      composite = described_class.new(catch_all_refiner, counting_refiner)
      t = [NodeStub.new(text: 'alpha beta gamma', type: :item)]
      d = [NodeStub.new(text: 'alpha beta delta', type: :item)]

      composite.call(t, d)
      # First refiner matches the only pair; second is skipped (empty remaining)
      expect(call_count).to eq(0)
    end
  end

  describe '#empty?' do
    it 'returns true with no refiners' do
      expect(described_class.new.empty?).to be true
    end

    it 'returns false with refiners' do
      expect(described_class.new(catch_all_refiner).empty?).to be false
    end
  end

  describe '#size' do
    it 'returns number of refiners' do
      composite = described_class.new(paragraph_refiner, comment_refiner)
      expect(composite.size).to eq(2)
    end
  end
end
