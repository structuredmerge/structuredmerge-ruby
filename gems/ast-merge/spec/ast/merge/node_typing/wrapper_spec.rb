# frozen_string_literal: true

RSpec.describe Ast::Merge::NodeTyping::Wrapper do
  let(:mock_node) do
    node_class = Class.new do
      class << self
        def name
          'TestNode'
        end
      end
    end
    double('MockNode', name: :test_method, class: node_class)
  end

  describe '#initialize' do
    it 'stores the node and merge_type' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper.node).to eq(mock_node)
      expect(wrapper.merge_type).to eq(:custom_type)
    end
  end

  describe '#method_missing' do
    it 'delegates to the wrapped node' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper.name).to eq(:test_method)
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for methods the wrapped node responds to' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper.respond_to?(:name)).to be true
      expect(wrapper.respond_to?(:nonexistent_method)).to be false
    end
  end

  describe '#typed_node?' do
    it 'returns true' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper.typed_node?).to be true
    end
  end

  describe '#unwrap' do
    it 'returns the original node' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper.unwrap).to eq(mock_node)
    end
  end

  describe '#==' do
    it 'compares by node and merge_type when comparing to another wrapper' do
      wrapper1 = described_class.new(mock_node, :custom_type)
      wrapper2 = described_class.new(mock_node, :custom_type)
      wrapper3 = described_class.new(mock_node, :different_type)

      expect(wrapper1).to eq(wrapper2)
      expect(wrapper1).not_to eq(wrapper3)
    end

    it 'compares to the wrapped node when comparing to a non-wrapper' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper == mock_node).to be true
    end
  end

  describe '#inspect' do
    it 'includes merge_type and node info' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect(wrapper.inspect).to include('Wrapper')
      expect(wrapper.inspect).to include('custom_type')
    end
  end

  describe '#hash' do
    it 'returns consistent hash for same node and merge_type' do
      wrapper1 = described_class.new(mock_node, :custom_type)
      wrapper2 = described_class.new(mock_node, :custom_type)

      expect(wrapper1.hash).to eq(wrapper2.hash)
    end

    it 'returns different hash for different merge_types' do
      wrapper1 = described_class.new(mock_node, :type_a)
      wrapper2 = described_class.new(mock_node, :type_b)

      expect(wrapper1.hash).not_to eq(wrapper2.hash)
    end
  end

  describe '#eql?' do
    it 'returns true for equal wrappers' do
      wrapper1 = described_class.new(mock_node, :custom_type)
      wrapper2 = described_class.new(mock_node, :custom_type)

      expect(wrapper1.eql?(wrapper2)).to be true
    end

    it 'returns false for different merge_types' do
      wrapper1 = described_class.new(mock_node, :type_a)
      wrapper2 = described_class.new(mock_node, :type_b)

      expect(wrapper1.eql?(wrapper2)).to be false
    end
  end

  describe '#method_missing error handling' do
    it 'raises NoMethodError when wrapped node does not respond to method' do
      wrapper = described_class.new(mock_node, :custom_type)

      expect { wrapper.nonexistent_method_xyz }.to raise_error(NoMethodError)
    end
  end
end
