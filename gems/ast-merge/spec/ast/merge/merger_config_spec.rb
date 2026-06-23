# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples'

RSpec.describe Ast::Merge::MergerConfig do
  it_behaves_like 'Ast::Merge::MergerConfig' do
    let(:merger_config_class) { described_class }
    let(:build_merger_config) { ->(**opts) { described_class.new(**opts) } }
  end

  describe '.destination_wins' do
    it 'creates a config with :destination preference' do
      config = described_class.destination_wins
      expect(config.preference).to eq(:destination)
    end

    it 'sets add_template_only_nodes to false' do
      config = described_class.destination_wins
      expect(config.add_template_only_nodes).to be false
    end

    it 'accepts freeze_token option' do
      config = described_class.destination_wins(freeze_token: 'my-merge')
      expect(config.freeze_token).to eq('my-merge')
    end

    it 'accepts signature_generator option' do
      generator = ->(node) { [:custom, node] }
      config = described_class.destination_wins(signature_generator: generator)
      expect(config.signature_generator).to eq(generator)
    end

    it 'accepts node_typing option' do
      typing = { CallNode: ->(node) { node } }
      config = described_class.destination_wins(node_typing: typing)
      expect(config.node_typing).to eq(typing)
    end

    it 'accepts resolution_mode option' do
      config = described_class.destination_wins(resolution_mode: :unresolved)
      expect(config.resolution_mode).to eq(:unresolved)
    end
  end

  describe '.template_wins' do
    it 'creates a config with :template preference' do
      config = described_class.template_wins
      expect(config.preference).to eq(:template)
    end

    it 'sets add_template_only_nodes to true' do
      config = described_class.template_wins
      expect(config.add_template_only_nodes).to be true
    end

    it 'accepts freeze_token option' do
      config = described_class.template_wins(freeze_token: 'my-merge')
      expect(config.freeze_token).to eq('my-merge')
    end

    it 'accepts signature_generator option' do
      generator = ->(node) { [:custom, node] }
      config = described_class.template_wins(signature_generator: generator)
      expect(config.signature_generator).to eq(generator)
    end

    it 'accepts node_typing option' do
      typing = { CallNode: ->(node) { node } }
      config = described_class.template_wins(node_typing: typing)
      expect(config.node_typing).to eq(typing)
    end

    it 'accepts resolution_mode option' do
      config = described_class.template_wins(resolution_mode: :unresolved)
      expect(config.resolution_mode).to eq(:unresolved)
    end
  end

  describe 'Hash-based preference' do
    it 'accepts a Hash for preference' do
      config = described_class.new(
        preference: { default: :destination, lint_gem: :template }
      )
      expect(config.preference).to eq({ default: :destination, lint_gem: :template })
    end

    describe '#prefer_destination?' do
      it 'returns true when default is :destination' do
        config = described_class.new(
          preference: { default: :destination, other: :template }
        )
        expect(config.prefer_destination?).to be true
      end

      it 'returns false when default is :template' do
        config = described_class.new(
          preference: { default: :template }
        )
        expect(config.prefer_destination?).to be false
      end

      it 'returns true when :default key is missing (implicit :destination)' do
        config = described_class.new(
          preference: { lint_gem: :template }
        )
        expect(config.prefer_destination?).to be true
      end
    end

    describe '#prefer_template?' do
      it 'returns true when default is :template' do
        config = described_class.new(
          preference: { default: :template }
        )
        expect(config.prefer_template?).to be true
      end

      it 'returns false when default is :destination' do
        config = described_class.new(
          preference: { default: :destination }
        )
        expect(config.prefer_template?).to be false
      end
    end

    describe '#preference_for' do
      let(:config) do
        described_class.new(
          preference: {
            default: :destination,
            lint_gem: :template,
            test_gem: :destination
          }
        )
      end

      it 'returns the preference for a known type' do
        expect(config.preference_for(:lint_gem)).to eq(:template)
        expect(config.preference_for(:test_gem)).to eq(:destination)
      end

      it 'returns the default for unknown types' do
        expect(config.preference_for(:unknown_type)).to eq(:destination)
      end

      it 'returns :destination when no :default key and unknown type' do
        config = described_class.new(
          preference: { lint_gem: :template }
        )
        expect(config.preference_for(:unknown_type)).to eq(:destination)
      end

      context 'with Symbol preference' do
        it 'returns the symbol preference for any type' do
          config = described_class.new(preference: :template)
          expect(config.preference_for(:any_type)).to eq(:template)
          expect(config.preference_for(:other_type)).to eq(:template)
        end
      end
    end

    describe '#per_type_preference?' do
      it 'returns true for Hash preference' do
        config = described_class.new(
          preference: { default: :destination }
        )
        expect(config.per_type_preference?).to be true
      end

      it 'returns false for Symbol preference' do
        config = described_class.new(preference: :destination)
        expect(config.per_type_preference?).to be false
      end
    end

    it 'raises ArgumentError for invalid Hash values' do
      expect do
        described_class.new(
          preference: { default: :invalid }
        )
      end.to raise_error(ArgumentError, /must be :destination or :template/)
    end

    it 'raises ArgumentError for non-Symbol Hash keys' do
      expect do
        described_class.new(
          preference: { 'string_key' => :destination }
        )
      end.to raise_error(ArgumentError, /keys must be Symbols/)
    end
  end

  describe '#node_typing' do
    it 'stores node_typing configuration' do
      typing = { CallNode: ->(node) { node } }
      config = described_class.new(node_typing: typing)
      expect(config.node_typing).to eq(typing)
    end

    it 'validates node_typing on initialization' do
      expect do
        described_class.new(node_typing: 'not a hash')
      end.to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'includes node_typing in to_h' do
      typing = { CallNode: ->(node) { node } }
      config = described_class.new(node_typing: typing)
      expect(config.to_h[:node_typing]).to eq(typing)
    end

    it 'preserves node_typing in #with' do
      typing = { CallNode: ->(node) { node } }
      config = described_class.new(node_typing: typing)
      new_config = config.with(preference: :template)
      expect(new_config.node_typing).to eq(typing)
    end
  end

  describe '#resolution_mode' do
    it 'reports eager and unresolved predicates' do
      config = described_class.new(resolution_mode: :unresolved)

      expect(config.unresolved_resolution?).to be(true)
      expect(config.eager_resolution?).to be(false)
    end
  end
end
