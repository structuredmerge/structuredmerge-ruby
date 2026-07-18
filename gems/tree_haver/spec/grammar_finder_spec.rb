# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe TreeHaver::GrammarFinder do
  describe '#available?' do
    it 'uses the TSLP parser backend without requiring a cached shared library' do
      stub_const('TreeSitterLanguagePack', Module.new)
      allow(TreeSitterLanguagePack).to receive(:has_language).with('cold_cache_toml').and_return(true)
      allow(TreeHaver::Backends::Tslp).to receive(:available?).and_return(true)

      finder = described_class.new(:cold_cache_toml)

      expect(finder).to be_available
    end
  end

  describe '#register!' do
    it 'registers a TSLP backend module when the language pack parser is available' do
      stub_const('TreeSitterLanguagePack', Module.new)
      allow(TreeSitterLanguagePack).to receive(:has_language).with('cold_cache_json').and_return(true)
      allow(TreeHaver::Backends::Tslp).to receive(:available?).and_return(true)

      finder = described_class.new(:cold_cache_json)

      expect(finder.register!).to be(true)
      expect(TreeHaver.registered_languages(:cold_cache_json)).to include(
        tslp: include(
          backend_module: TreeHaver::Backends::Tslp,
          gem_name: 'tree_sitter_language_pack'
        )
      )
    end
  end
end
