# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ast::Merge::Freezable do
  describe 'module inclusion' do
    let(:freezable_class) do
      Class.new do
        include Ast::Merge::Freezable

        def initialize(content)
          @content = content
        end

        def slice
          @content
        end
      end
    end

    it 'makes instances satisfy is_a?(Freezable)' do
      instance = freezable_class.new('content')
      expect(instance).to be_a(described_class)
    end

    it 'provides freeze_node? method that returns true' do
      instance = freezable_class.new('content')
      expect(instance.freeze_node?).to be true
    end

    it 'provides freeze_signature method' do
      instance = freezable_class.new('  some content  ')
      expect(instance.freeze_signature).to eq([:FreezeNode, 'some content'])
    end

    it 'handles nil slice in freeze_signature' do
      instance = freezable_class.new(nil)
      expect(instance.freeze_signature).to eq([:FreezeNode, nil])
    end

    it 'requires implementing classes to define slice' do
      incomplete_class = Class.new do
        include Ast::Merge::Freezable
      end
      instance = incomplete_class.new
      expect { instance.slice }.to raise_error(NotImplementedError)
    end
  end

  describe 'FreezeNodeBase integration' do
    it 'FreezeNodeBase includes Freezable' do
      expect(Ast::Merge::FreezeNodeBase.ancestors).to include(described_class)
    end

    it 'FreezeNodeBase instances satisfy is_a?(Freezable)' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(
        start_line: 1,
        end_line: 3,
        content: 'frozen content'
      )
      expect(freeze_node).to be_a(described_class)
      expect(freeze_node.freeze_node?).to be true
    end
  end

  describe 'NodeTyping::FrozenWrapper integration' do
    let(:mock_node) do
      double('MockNode', slice: 'node content', location: nil)
    end

    it 'FrozenWrapper includes Freezable' do
      expect(Ast::Merge::NodeTyping::FrozenWrapper.ancestors).to include(described_class)
    end

    it 'FrozenWrapper instances satisfy is_a?(Freezable)' do
      wrapper = Ast::Merge::NodeTyping::FrozenWrapper.new(mock_node)
      expect(wrapper).to be_a(described_class)
      expect(wrapper.freeze_node?).to be true
    end

    it 'FrozenWrapper provides freeze_signature via Freezable' do
      wrapper = Ast::Merge::NodeTyping::FrozenWrapper.new(mock_node)
      expect(wrapper.freeze_signature).to eq([:FreezeNode, 'node content'])
    end

    it "FrozenWrapper's signature method uses freeze_signature" do
      wrapper = Ast::Merge::NodeTyping::FrozenWrapper.new(mock_node)
      expect(wrapper.signature).to eq([:FreezeNode, 'node content'])
    end

    it 'FrozenWrapper can unwrap to get the original node' do
      wrapper = Ast::Merge::NodeTyping::FrozenWrapper.new(mock_node)
      expect(wrapper.unwrap).to eq(mock_node)
    end

    it 'FrozenWrapper defaults merge_type to :frozen' do
      wrapper = Ast::Merge::NodeTyping::FrozenWrapper.new(mock_node)
      expect(wrapper.merge_type).to eq(:frozen)
    end

    it 'FrozenWrapper allows custom merge_type' do
      wrapper = Ast::Merge::NodeTyping::FrozenWrapper.new(mock_node, :custom_frozen)
      expect(wrapper.merge_type).to eq(:custom_frozen)
    end
  end

  describe 'NodeTyping.frozen helper' do
    let(:mock_node) do
      double('MockNode', slice: 'content', location: nil)
    end

    it 'creates a FrozenWrapper' do
      result = Ast::Merge::NodeTyping.frozen(mock_node)
      expect(result).to be_a(Ast::Merge::NodeTyping::FrozenWrapper)
    end

    it 'creates a node that is_a?(Freezable)' do
      result = Ast::Merge::NodeTyping.frozen(mock_node)
      expect(result).to be_a(described_class)
    end

    it 'defaults merge_type to :frozen' do
      result = Ast::Merge::NodeTyping.frozen(mock_node)
      expect(result.merge_type).to eq(:frozen)
    end

    it 'allows custom merge_type' do
      result = Ast::Merge::NodeTyping.frozen(mock_node, :special)
      expect(result.merge_type).to eq(:special)
    end
  end

  describe 'NodeTyping.frozen_node? helper' do
    it 'returns true for Freezable instances' do
      freezable = Ast::Merge::NodeTyping::FrozenWrapper.new(double(slice: 'x', location: nil))
      expect(Ast::Merge::NodeTyping.frozen_node?(freezable)).to be true
    end

    it 'returns true for FreezeNodeBase instances' do
      freeze_node = Ast::Merge::FreezeNodeBase.new(start_line: 1, end_line: 2, content: 'x')
      expect(Ast::Merge::NodeTyping.frozen_node?(freeze_node)).to be true
    end

    it 'returns false for regular objects' do
      expect(Ast::Merge::NodeTyping.frozen_node?('string')).to be false
      expect(Ast::Merge::NodeTyping.frozen_node?(123)).to be false
      expect(Ast::Merge::NodeTyping.frozen_node?(nil)).to be false
    end

    it 'returns false for regular Wrapper (non-frozen)' do
      wrapper = Ast::Merge::NodeTyping::Wrapper.new(double, :some_type)
      expect(Ast::Merge::NodeTyping.frozen_node?(wrapper)).to be false
    end
  end
end
