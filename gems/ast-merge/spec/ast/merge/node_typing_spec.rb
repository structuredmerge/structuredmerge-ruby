# frozen_string_literal: true

RSpec.describe Ast::Merge::NodeTyping do
  describe '.with_merge_type' do
    let(:mock_node) { double('MockNode') }

    it 'creates a Wrapper with the given merge_type' do
      result = described_class.with_merge_type(mock_node, :my_type)

      expect(result).to be_a(Ast::Merge::NodeTyping::Wrapper)
      expect(result.merge_type).to eq(:my_type)
      expect(result.node).to eq(mock_node)
    end
  end

  describe '.frozen' do
    let(:mock_node) { double('MockNode', slice: 'content') }

    it 'creates a FrozenWrapper with default merge_type' do
      result = described_class.frozen(mock_node)

      expect(result).to be_a(Ast::Merge::NodeTyping::FrozenWrapper)
      expect(result.merge_type).to eq(:frozen)
      expect(result.node).to eq(mock_node)
    end

    it 'creates a FrozenWrapper with custom merge_type' do
      result = described_class.frozen(mock_node, :custom_frozen)

      expect(result.merge_type).to eq(:custom_frozen)
    end
  end

  describe '.frozen_node?' do
    it 'returns true for FrozenWrapper' do
      mock_node = double('MockNode', slice: 'content')
      wrapper = described_class.frozen(mock_node)

      expect(described_class.frozen_node?(wrapper)).to be true
    end

    it 'returns true for objects including Freezable' do
      freezable_obj = Class.new do
        include Ast::Merge::Freezable

        def slice
          'content'
        end
      end.new

      expect(described_class.frozen_node?(freezable_obj)).to be true
    end

    it 'returns false for regular Wrapper' do
      mock_node = double('MockNode')
      wrapper = described_class.with_merge_type(mock_node, :type)

      expect(described_class.frozen_node?(wrapper)).to be false
    end

    it 'returns false for regular objects' do
      expect(described_class.frozen_node?('string')).to be false
      expect(described_class.frozen_node?(nil)).to be false
    end
  end

  describe '.typed_node?' do
    it 'returns true for Wrapper' do
      mock_node = double('MockNode')
      wrapper = described_class.with_merge_type(mock_node, :type)

      expect(described_class.typed_node?(wrapper)).to be true
    end

    it 'returns true for FrozenWrapper' do
      mock_node = double('MockNode', slice: 'content')
      wrapper = described_class.frozen(mock_node)

      expect(described_class.typed_node?(wrapper)).to be true
    end

    it 'returns false for regular objects' do
      expect(described_class.typed_node?('string')).to be false
      expect(described_class.typed_node?(nil)).to be false
      expect(described_class.typed_node?(Object.new)).to be false
    end
  end

  describe '.merge_type_for' do
    it 'returns merge_type for Wrapper' do
      mock_node = double('MockNode')
      wrapper = described_class.with_merge_type(mock_node, :special_type)

      expect(described_class.merge_type_for(wrapper)).to eq(:special_type)
    end

    it 'returns merge_type for FrozenWrapper' do
      mock_node = double('MockNode', slice: 'content')
      wrapper = described_class.frozen(mock_node, :frozen_type)

      expect(described_class.merge_type_for(wrapper)).to eq(:frozen_type)
    end

    it 'returns nil for non-wrapped nodes' do
      expect(described_class.merge_type_for('string')).to be_nil
      expect(described_class.merge_type_for(nil)).to be_nil
    end
  end

  describe '.unwrap' do
    it 'unwraps Wrapper' do
      mock_node = double('MockNode')
      wrapper = described_class.with_merge_type(mock_node, :type)

      expect(described_class.unwrap(wrapper)).to eq(mock_node)
    end

    it 'unwraps FrozenWrapper' do
      mock_node = double('MockNode', slice: 'content')
      wrapper = described_class.frozen(mock_node)

      expect(described_class.unwrap(wrapper)).to eq(mock_node)
    end

    it 'returns non-wrapped nodes unchanged' do
      node = 'regular_node'

      expect(described_class.unwrap(node)).to eq(node)
    end
  end

  describe '.process' do
    let(:mock_node) do
      node_class = Class.new do
        class << self
          def name
            'CallNode'
          end
        end
      end
      double('MockNode', class: node_class, name: :gem)
    end

    it 'returns node unchanged when typing_config is nil' do
      result = described_class.process(mock_node, nil)

      expect(result).to eq(mock_node)
    end

    it 'returns node unchanged when typing_config is empty' do
      result = described_class.process(mock_node, {})

      expect(result).to eq(mock_node)
    end

    it 'returns node unchanged when no matching callable is found' do
      config = {
        DefNode: ->(node) { described_class.with_merge_type(node, :method) }
      }

      result = described_class.process(mock_node, config)

      expect(result).to eq(mock_node)
    end

    it 'processes node through matching callable by symbol key' do
      config = {
        CallNode: ->(node) { described_class.with_merge_type(node, :call_type) }
      }

      result = described_class.process(mock_node, config)

      expect(described_class.typed_node?(result)).to be true
      expect(result.merge_type).to eq(:call_type)
    end

    it 'processes node through matching callable by string key' do
      config = {
        'CallNode' => ->(node) { described_class.with_merge_type(node, :string_key_type) }
      }

      result = described_class.process(mock_node, config)

      expect(result.merge_type).to eq(:string_key_type)
    end

    it 'allows callable to return node unchanged' do
      config = {
        CallNode: ->(node) { node }
      }

      result = described_class.process(mock_node, config)

      expect(result).to eq(mock_node)
      expect(described_class.typed_node?(result)).to be false
    end

    it 'allows callable to return nil' do
      config = {
        CallNode: ->(_node) { nil }
      }

      result = described_class.process(mock_node, config)

      expect(result).to be_nil
    end

    context 'with fully-qualified class name' do
      let(:namespaced_node) do
        node_class = Class.new do
          class << self
            def name
              'Prism::CallNode'
            end
          end
        end
        double('NamespacedNode', class: node_class, name: :test)
      end

      it 'finds callable by fully-qualified symbol key' do
        config = {
          "Prism::CallNode": ->(node) { described_class.with_merge_type(node, :fq_type) }
        }

        result = described_class.process(namespaced_node, config)

        expect(result.merge_type).to eq(:fq_type)
      end

      it 'finds callable by fully-qualified string key' do
        config = {
          'Prism::CallNode' => ->(node) { described_class.with_merge_type(node, :fq_string_type) }
        }

        result = described_class.process(namespaced_node, config)

        expect(result.merge_type).to eq(:fq_string_type)
      end

      it 'finds callable by underscored naming convention' do
        config = {
          prism_call_node: ->(node) { described_class.with_merge_type(node, :underscored_type) }
        }

        result = described_class.process(namespaced_node, config)

        expect(result.merge_type).to eq(:underscored_type)
      end
    end

    context 'with already-typed node' do
      it 'processes Wrapper through matching callable' do
        wrapped = described_class.with_merge_type(mock_node, :original_type)
        config = {
          CallNode: ->(node) { described_class.with_merge_type(node, :rewrapped_type) }
        }

        result = described_class.process(wrapped, config)

        expect(result.merge_type).to eq(:rewrapped_type)
      end
    end
  end

  describe '.validate!' do
    it 'accepts nil' do
      expect { described_class.validate!(nil) }.not_to raise_error
    end

    it 'accepts empty hash' do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    it 'accepts valid configuration with symbol keys' do
      config = {
        CallNode: ->(_node) { nil },
        DefNode: ->(_node) { nil }
      }

      expect { described_class.validate!(config) }.not_to raise_error
    end

    it 'accepts valid configuration with string keys' do
      config = {
        'CallNode' => ->(_node) { nil }
      }

      expect { described_class.validate!(config) }.not_to raise_error
    end

    it 'raises ArgumentError for non-Hash' do
      expect { described_class.validate!('not a hash') }
        .to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'raises ArgumentError for non-Symbol/String keys' do
      config = { 123 => ->(_node) { nil } }

      expect { described_class.validate!(config) }
        .to raise_error(ArgumentError, /keys must be Symbol or String/)
    end

    it 'raises ArgumentError for non-callable values' do
      config = { CallNode: 'not callable' }

      expect { described_class.validate!(config) }
        .to raise_error(ArgumentError, /must be callable/)
    end
  end

  describe '.process edge cases for branch coverage' do
    context 'with node that has nil class.name (anonymous class)' do
      let(:anonymous_node) do
        anon_class = Class.new # Anonymous class has nil name
        anon_class.new
      end

      it 'falls back to class.to_s for type key' do
        config = {
          SomeOtherNode: ->(node) { described_class.with_merge_type(node, :other_type) }
        }

        result = described_class.process(anonymous_node, config)

        expect(result).to eq(anonymous_node)
      end

      it 'can match anonymous class by its to_s representation' do
        anon_class = Class.new
        anon_node = anon_class.new
        type_string = anon_class.to_s

        config = {
          type_string => ->(node) { described_class.with_merge_type(node, :anon_type) }
        }

        result = described_class.process(anon_node, config)

        expect(described_class.typed_node?(result)).to be true
        expect(result.merge_type).to eq(:anon_type)
      end
    end

    context 'when full_name is nil for lookup paths' do
      let(:anonymous_node) do
        anon_class = Class.new
        anon_class.new
      end

      it 'skips fully-qualified and underscored lookups when full_name is nil' do
        config = {
          'SomeNode' => ->(node) { described_class.with_merge_type(node, :some_type) }
        }

        result = described_class.process(anonymous_node, config)

        expect(result).to eq(anonymous_node)
      end
    end

    context 'when config has no matching keys for any lookup strategy' do
      let(:namespaced_node) do
        node_class = Class.new do
          class << self
            def name
              'MyModule::MyNode'
            end
          end
        end
        double('NamespacedNode', class: node_class, name: :test)
      end

      it 'returns nil from find_typing_callable when no strategy matches' do
        config = {
          :OtherNode => ->(node) { described_class.with_merge_type(node, :other) },
          'Different::Path' => ->(node) { described_class.with_merge_type(node, :different) },
          :some_other_node => ->(node) { described_class.with_merge_type(node, :some_other) }
        }

        result = described_class.process(namespaced_node, config)

        expect(result).to eq(namespaced_node)
        expect(described_class.typed_node?(result)).to be false
      end
    end

    context 'with string key lookup' do
      let(:string_key_node) do
        node_class = Class.new do
          class << self
            def name
              'StringKeyNode'
            end
          end
        end
        double('StringKeyNode', class: node_class)
      end

      it 'matches config with string type_key' do
        config = {
          'StringKeyNode' => ->(node) { described_class.with_merge_type(node, :string_match) }
        }

        result = described_class.process(string_key_node, config)

        expect(described_class.typed_node?(result)).to be true
        expect(result.merge_type).to eq(:string_match)
      end
    end

    context 'with Wrapper passed to process' do
      let(:inner_node) do
        node_class = Class.new do
          class << self
            def name
              'InnerNode'
            end
          end
        end
        double('InnerNode', class: node_class)
      end

      it 'unwraps Wrapper to find matching callable' do
        wrapped = described_class.with_merge_type(inner_node, :original_type)
        config = {
          InnerNode: ->(node) { described_class.with_merge_type(node, :new_type) }
        }

        result = described_class.process(wrapped, config)

        expect(described_class.typed_node?(result)).to be true
        expect(result.merge_type).to eq(:new_type)
      end
    end
  end
end
