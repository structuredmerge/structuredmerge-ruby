# frozen_string_literal: true

RSpec.describe Ast::Merge::Recipe::Preset do
  let(:minimal_config) do
    {
      'name' => 'test_preset',
      'description' => 'A test preset'
    }
  end

  let(:full_config) do
    {
      'name' => 'full_preset',
      'description' => 'A full preset with all options',
      'parser' => 'markly',
      'freeze_token' => 'my-freeze',
      'merge' => {
        'preference' => 'destination',
        'add_missing' => false,
        'signature_generator' => '->(n) { n }'
      }
    }
  end

  describe '.load' do
    let(:preset_dir) { Dir.mktmpdir }
    let(:preset_path) { File.join(preset_dir, 'test.yml') }

    after { FileUtils.rm_rf(preset_dir) }

    it 'loads a preset from YAML file' do
      File.write(preset_path, YAML.dump(minimal_config))
      preset = described_class.load(preset_path)

      expect(preset.name).to eq('test_preset')
      expect(preset.description).to eq('A test preset')
    end

    it 'raises ArgumentError for missing file' do
      expect do
        described_class.load('/nonexistent/path.yml')
      end.to raise_error(ArgumentError, /not found/)
    end
  end

  describe '#initialize' do
    subject(:preset) { described_class.new(config) }

    context 'with minimal config' do
      let(:config) { minimal_config }

      it 'sets defaults' do
        expect(preset.name).to eq('test_preset')
        expect(preset.parser).to eq(:prism)
        expect(preset.parser_explicit?).to be(false)
        expect(preset.preference).to eq(:template)
        expect(preset.freeze_token).to be_nil
      end
    end

    context 'with full config' do
      let(:config) { full_config }

      it 'uses provided values' do
        expect(preset.name).to eq('full_preset')
        expect(preset.parser).to eq(:markly)
        expect(preset.parser_explicit?).to be(true)
        expect(preset.preference).to eq(:destination)
        expect(preset.freeze_token).to eq('my-freeze')
      end
    end
  end

  describe '#preference' do
    it 'defaults to :template' do
      preset = described_class.new(minimal_config)
      expect(preset.preference).to eq(:template)
    end

    it 'returns symbol from string config' do
      config = minimal_config.merge('merge' => { 'preference' => 'destination' })
      preset = described_class.new(config)
      expect(preset.preference).to eq(:destination)
    end

    it 'returns hash for per-type preferences' do
      config = minimal_config.merge('merge' => {
                                      'preference' => { 'heading' => 'template', 'paragraph' => 'destination' }
                                    })
      preset = described_class.new(config)
      expect(preset.preference).to eq({ heading: :template, paragraph: :destination })
    end
  end

  describe '#add_missing' do
    it 'defaults to true' do
      preset = described_class.new(minimal_config)
      expect(preset.add_missing).to be(true)
    end

    it 'returns false when configured' do
      config = minimal_config.merge('merge' => { 'add_missing' => false })
      preset = described_class.new(config)
      expect(preset.add_missing).to be(false)
    end
  end

  describe '#to_h' do
    subject(:preset) { described_class.new(full_config) }

    it 'returns SmartMerger-compatible hash' do
      hash = preset.to_h

      expect(hash).to include(:preference)
      expect(hash).to include(:add_template_only_nodes)
      expect(hash[:preference]).to eq(:destination)
      expect(hash[:add_template_only_nodes]).to be(false)
      expect(hash[:freeze_token]).to eq('my-freeze')
    end

    it 'excludes nil values' do
      preset = described_class.new(minimal_config)
      hash = preset.to_h

      expect(hash).not_to have_key(:freeze_token)
      expect(hash).not_to have_key(:signature_generator)
    end
  end

  describe '#signature_generator' do
    it 'returns nil when not configured' do
      preset = described_class.new(minimal_config)
      expect(preset.signature_generator).to be_nil
    end

    it 'returns callable when configured with inline lambda' do
      config = minimal_config.merge('merge' => {
                                      'signature_generator' => '->(n) { [:test, n] }'
                                    })
      preset = described_class.new(config)

      expect(preset.signature_generator).to respond_to(:call)
      expect(preset.signature_generator.call('foo')).to eq([:test, 'foo'])
    end
  end

  describe '#node_typing' do
    it 'returns nil when not configured' do
      preset = described_class.new(minimal_config)
      expect(preset.node_typing).to be_nil
    end

    it 'returns hash with callables when configured' do
      config = minimal_config.merge('merge' => {
                                      'node_typing' => {
                                        'CallNode' => '->(n) { n }'
                                      }
                                    })
      preset = described_class.new(config)

      expect(preset.node_typing).to be_a(Hash)
      expect(preset.node_typing['CallNode']).to respond_to(:call)
    end

    it 'returns existing callables unchanged' do
      existing_callable = ->(n) { [:already, n] }
      config = minimal_config.merge('merge' => {
                                      'node_typing' => { 'SomeType' => existing_callable }
                                    })
      preset = described_class.new(config)

      expect(preset.node_typing['SomeType']).to eq(existing_callable)
    end
  end

  describe '#add_missing with callable' do
    it 'returns callable when configured as callable' do
      filter = ->(node, _entry) { node.type == :paragraph }
      config = minimal_config.merge('merge' => { 'add_missing' => filter })
      preset = described_class.new(config)

      expect(preset.add_missing).to eq(filter)
    end

    it 'add_missing? is an alias' do
      preset = described_class.new(minimal_config)
      expect(preset.add_missing?).to eq(preset.add_missing)
    end
  end

  describe '#script_loader' do
    it 'returns a ScriptLoader instance' do
      preset = described_class.new(minimal_config, preset_path: '/some/path.yml')
      expect(preset.script_loader).to be_a(Ast::Merge::Recipe::ScriptLoader)
    end

    it 'caches the script_loader' do
      preset = described_class.new(minimal_config)
      loader1 = preset.script_loader
      loader2 = preset.script_loader
      expect(loader1).to equal(loader2)
    end
  end

  describe 'parse_preference edge cases' do
    it 'returns nil for nil preference' do
      config = minimal_config.merge('merge' => { 'preference' => nil })
      preset = described_class.new(config)
      expect(preset.preference).to eq(:template)
    end
  end
end
