# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'

RSpec.shared_examples('Ast::Merge::Recipe::PresetContract') do
  let(:preset_filename) { 'test_recipe.yml' }
  let(:preset_script_files) { {} }
  let(:preset_workspace) { Dir.mktmpdir('ast-merge-preset-contract') }
  let(:preset_path) { File.join(preset_workspace, preset_filename) }
  let(:expected_parser) { (preset_config['parser'] || preset_config[:parser] || 'prism').to_sym }
  let(:expected_parser_explicit) { preset_config.key?('parser') || preset_config.key?(:parser) }
  let(:expected_preference) do
    raw_preference = (preset_config['merge'] || preset_config[:merge] || {})['preference']
    normalize_preference(raw_preference)
  end
  let(:expected_to_h_including) { {} }
  let(:verify_loaded_preset) { ->(_preset) {} }

  after do
    FileUtils.rm_rf(preset_workspace)
  end

  before do
    File.write(preset_path, YAML.dump(preset_config))

    preset_script_files.each do |relative_path, content|
      absolute_path = File.join(preset_workspace, File.basename(preset_filename, '.*'), relative_path)
      FileUtils.mkdir_p(File.dirname(absolute_path))
      File.write(absolute_path, content)
    end
  end

  it 'loads the preset from disk and preserves recipe metadata' do
    preset = Ast::Merge::Recipe::Preset.load(preset_path)

    expect(preset.parser).to(eq(expected_parser))
    expect(preset.parser_explicit?).to(eq(expected_parser_explicit))
    expect(preset.preference).to(eq(expected_preference))
  end

  it 'converts the preset into SmartMerger-compatible options' do
    preset = Ast::Merge::Recipe::Preset.load(preset_path)
    preset_options = preset.to_h

    expect(preset_options[:preference]).to(eq(expected_preference))
    expect(preset_options).to(include(:add_template_only_nodes))
    expect(preset_options).to(include(expected_to_h_including)) unless expected_to_h_including.empty?
  end

  it 'resolves companion scripts through the shared ScriptLoader' do
    preset = Ast::Merge::Recipe::Preset.load(preset_path)

    if preset_script_files.empty?
      expect(preset.script_loader.scripts_available?).to(be(false))
    else
      expect(preset.script_loader.scripts_available?).to(be(true))
      expect(preset.script_loader.available_scripts).to(match_array(preset_script_files.keys))
    end

    verify_loaded_preset.call(preset)
  end

  def normalize_preference(raw_preference)
    return :template if raw_preference.nil?
    return raw_preference.to_sym if raw_preference.is_a?(String) || raw_preference.is_a?(Symbol)

    raw_preference.transform_keys(&:to_sym).transform_values(&:to_sym)
  end
end
