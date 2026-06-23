# frozen_string_literal: true

RSpec.describe Ast::Merge::BlockDirective do
  # A minimal stub that includes the protocol but does NOT implement any abstract methods
  let(:unimplemented_class) do
    Class.new do
      include Ast::Merge::BlockDirective
    end
  end

  # A fully-implemented stub for testing the concrete helpers
  let(:implemented_class) do
    Class.new do
      include Ast::Merge::BlockDirective

      def initialize(kind, start_line, end_line, children = [])
        @kind = kind
        @start_line = start_line
        @end_line = end_line
        @children = children
      end

      attr_reader :kind
      attr_reader :start_line
      attr_reader :end_line
      attr_reader :children

      def merge_policy = :destination
    end
  end

  describe '#block_directive?' do
    it 'returns true' do
      instance = implemented_class.new(:freeze, 1, 5)
      expect(instance.block_directive?).to be(true)
    end
  end

  describe '#freeze_directive?' do
    it 'returns true when kind is :freeze' do
      instance = implemented_class.new(:freeze, 1, 5)
      expect(instance.freeze_directive?).to be(true)
    end

    it 'returns false when kind is :nocov' do
      instance = implemented_class.new(:nocov, 1, 5)
      expect(instance.freeze_directive?).to be(false)
    end

    it 'returns false when kind is some other symbol' do
      instance = implemented_class.new(:custom, 1, 5)
      expect(instance.freeze_directive?).to be(false)
    end
  end

  describe '#nocov_directive?' do
    it 'returns true when kind is :nocov' do
      instance = implemented_class.new(:nocov, 1, 5)
      expect(instance.nocov_directive?).to be(true)
    end

    it 'returns false when kind is :freeze' do
      instance = implemented_class.new(:freeze, 1, 5)
      expect(instance.nocov_directive?).to be(false)
    end
  end

  describe '#line_range' do
    it 'returns a Range from start_line to end_line (inclusive)' do
      instance = implemented_class.new(:freeze, 3, 10)
      expect(instance.line_range).to eq(3..10)
    end

    it 'returns a single-line Range when start equals end' do
      instance = implemented_class.new(:freeze, 7, 7)
      expect(instance.line_range).to eq(7..7)
    end
  end

  describe '#covers_line?' do
    subject(:instance) { implemented_class.new(:freeze, 5, 15) }

    it 'returns true for the start line' do
      expect(instance.covers_line?(5)).to be(true)
    end

    it 'returns true for an interior line' do
      expect(instance.covers_line?(10)).to be(true)
    end

    it 'returns true for the end line' do
      expect(instance.covers_line?(15)).to be(true)
    end

    it 'returns false for a line before the range' do
      expect(instance.covers_line?(4)).to be(false)
    end

    it 'returns false for a line after the range' do
      expect(instance.covers_line?(16)).to be(false)
    end
  end

  describe 'abstract method stubs raise NotImplementedError' do
    subject(:instance) { unimplemented_class.new }

    it 'raises NotImplementedError for #kind' do
      expect { instance.kind }.to raise_error(NotImplementedError, /must implement #kind/)
    end

    it 'raises NotImplementedError for #children' do
      expect { instance.children }.to raise_error(NotImplementedError, /must implement #children/)
    end

    it 'raises NotImplementedError for #start_line' do
      expect { instance.start_line }.to raise_error(NotImplementedError, /must implement #start_line/)
    end

    it 'raises NotImplementedError for #end_line' do
      expect { instance.end_line }.to raise_error(NotImplementedError, /must implement #end_line/)
    end

    it 'raises NotImplementedError for #merge_policy' do
      expect { instance.merge_policy }.to raise_error(NotImplementedError, /must implement #merge_policy/)
    end
  end

  describe 'FreezeNodeBase satisfies the BlockDirective protocol' do
    let(:nodes) { %i[node_a node_b] }
    let(:freeze_node) do
      Ast::Merge::FreezeNodeBase.new(
        start_line: 2,
        end_line: 8,
        nodes: nodes,
        content: 'some content'
      )
    end

    it 'includes BlockDirective' do
      expect(Ast::Merge::FreezeNodeBase.ancestors).to include(described_class)
    end

    it 'returns :freeze for #kind' do
      expect(freeze_node.kind).to eq(:freeze)
    end

    it 'returns :destination for #merge_policy' do
      expect(freeze_node.merge_policy).to eq(:destination)
    end

    it 'returns the nodes array for #children' do
      expect(freeze_node.children).to eq(nodes)
    end

    it 'returns true for #block_directive?' do
      expect(freeze_node.block_directive?).to be(true)
    end

    it 'returns true for #freeze_directive?' do
      expect(freeze_node.freeze_directive?).to be(true)
    end

    it 'returns false for #nocov_directive?' do
      expect(freeze_node.nocov_directive?).to be(false)
    end

    it 'returns the correct #line_range' do
      expect(freeze_node.line_range).to eq(2..8)
    end

    it 'covers a line inside the range' do
      expect(freeze_node.covers_line?(5)).to be(true)
    end

    it 'does not cover a line outside the range' do
      expect(freeze_node.covers_line?(9)).to be(false)
    end
  end
end
