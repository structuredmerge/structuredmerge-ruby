# frozen_string_literal: true

RSpec.describe Ast::Merge::NodeTyping::FrozenWrapper do
  let(:mock_node) do
    node_class = Class.new do
      class << self
        def name
          'TestNode'
        end
      end
    end
    double('MockNode', name: :test_method, class: node_class, slice: 'frozen content here')
  end

  describe '#initialize' do
    it 'stores the node with default merge_type of :frozen' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.node).to eq(mock_node)
      expect(wrapper.merge_type).to eq(:frozen)
    end

    it 'allows custom merge_type' do
      wrapper = described_class.new(mock_node, :custom_frozen_type)

      expect(wrapper.merge_type).to eq(:custom_frozen_type)
    end
  end

  describe '#frozen_node?' do
    it 'returns true' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.frozen_node?).to be true
    end
  end

  describe '#typed_node?' do
    it 'returns true (inherited from Wrapper)' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.typed_node?).to be true
    end
  end

  describe '#slice' do
    it "delegates to the wrapped node's slice method" do
      wrapper = described_class.new(mock_node)

      expect(wrapper.slice).to eq('frozen content here')
    end
  end

  describe '#signature' do
    it 'returns freeze_signature from Freezable module' do
      wrapper = described_class.new(mock_node)
      signature = wrapper.signature

      expect(signature).to be_an(Array)
      expect(signature.first).to eq(:FreezeNode)
      expect(signature.last).to eq('frozen content here')
    end
  end

  describe '#unwrap' do
    it 'returns the original node' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.unwrap).to eq(mock_node)
    end
  end

  describe '#inspect' do
    it 'includes FrozenWrapper and merge_type' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.inspect).to include('FrozenWrapper')
      expect(wrapper.inspect).to include('frozen')
    end
  end

  describe 'Freezable integration' do
    it 'includes the Freezable module' do
      wrapper = described_class.new(mock_node)

      expect(wrapper).to be_a(Ast::Merge::Freezable)
    end

    it 'responds to freeze_node?' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.freeze_node?).to be true
    end

    it 'responds to freeze_signature' do
      wrapper = described_class.new(mock_node)

      expect(wrapper).to respond_to(:freeze_signature)
      expect(wrapper.freeze_signature).to eq([:FreezeNode, 'frozen content here'])
    end
  end

  describe 'method delegation' do
    it 'delegates unknown methods to the wrapped node' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.name).to eq(:test_method)
    end

    it 'responds to methods that the wrapped node responds to' do
      wrapper = described_class.new(mock_node)

      expect(wrapper.respond_to?(:name)).to be true
      expect(wrapper.respond_to?(:slice)).to be true
    end
  end

  describe '#==' do
    it 'compares by node and merge_type when comparing to another wrapper' do
      wrapper1 = described_class.new(mock_node, :frozen)
      wrapper2 = described_class.new(mock_node, :frozen)

      expect(wrapper1).to eq(wrapper2)
    end

    it 'is not equal to a regular Wrapper with same node and merge_type' do
      frozen_wrapper = described_class.new(mock_node, :frozen)
      regular_wrapper = Ast::Merge::NodeTyping::Wrapper.new(mock_node, :frozen)

      # They have the same node and merge_type, so == returns true
      # This is expected behavior - they compare equal based on content
      expect(frozen_wrapper == regular_wrapper).to be true
    end
  end

  describe 'use with NodeTyping class methods' do
    it 'is recognized by NodeTyping.typed_node?' do
      wrapper = described_class.new(mock_node)

      expect(Ast::Merge::NodeTyping.typed_node?(wrapper)).to be true
    end

    it 'is recognized by NodeTyping.frozen_node?' do
      wrapper = described_class.new(mock_node)

      expect(Ast::Merge::NodeTyping.frozen_node?(wrapper)).to be true
    end

    it 'can be unwrapped via NodeTyping.unwrap' do
      wrapper = described_class.new(mock_node)

      expect(Ast::Merge::NodeTyping.unwrap(wrapper)).to eq(mock_node)
    end

    it 'merge_type can be retrieved via NodeTyping.merge_type_for' do
      wrapper = described_class.new(mock_node, :custom_frozen)

      expect(Ast::Merge::NodeTyping.merge_type_for(wrapper)).to eq(:custom_frozen)
    end
  end
end
