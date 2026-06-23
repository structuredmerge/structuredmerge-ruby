# frozen_string_literal: true

require 'ast/merge/rspec/shared_examples/recipe_preset_contract'

# -- shared example self-test
RSpec.describe 'Recipe::PresetContract shared examples' do
  it_behaves_like 'Ast::Merge::Recipe::PresetContract' do
    let(:preset_config) do
      {
        'name' => 'preset_contract_self_test',
        'description' => 'Exercises shared preset loading and script resolution',
        'parser' => 'psych',
        'freeze_token' => 'keep-me',
        'merge' => {
          'preference' => 'destination',
          'signature_generator' => 'signature_generator.rb',
          'node_typing' => {
            'Heading' => 'typing/heading.rb'
          },
          'add_missing' => 'add_missing.rb',
          'normalize_whitespace' => true
        }
      }
    end

    let(:preset_script_files) do
      {
        'signature_generator.rb' => "->(node) { [:sig, node] }\n",
        'typing/heading.rb' => "->(node) { [:heading, node] }\n",
        'add_missing.rb' => "->(node, _entry) { node == :keep }\n"
      }
    end

    let(:expected_to_h_including) do
      {
        preference: :destination,
        freeze_token: 'keep-me',
        normalize_whitespace: true
      }
    end

    let(:verify_loaded_preset) { method(:run_verify_loaded_preset) }

    def run_verify_loaded_preset(preset)
      expect(preset.signature_generator.call('node')).to eq([:sig, 'node'])
      expect(preset.node_typing['Heading'].call('node')).to eq([:heading, 'node'])
      expect(preset.add_missing.call(:keep, nil)).to be(true)
      expect(preset.add_missing.call(:drop, nil)).to be(false)
      expect(preset.to_h[:add_template_only_nodes]).to respond_to(:call)
    end
  end
end
