# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe TreeHaver::Backends::Tslp do
  before do
    described_class.reset!
  end

  it 'reports availability only when tree_sitter_language_pack exposes a parser API' do
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new do
      def set_language(_name); end

      def parse(_source)
        :tree
      end
    end
    TreeSitterLanguagePack.const_set(:Parser, parser_class)

    expect(described_class.available?).to be(true)
  end

  it 'fails closed when the installed language pack does not expose parser methods' do
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new
    TreeSitterLanguagePack.const_set(:Parser, parser_class)

    expect(described_class.available?).to be(false)
    expect(described_class.unavailable_reason).to eq('tree_sitter_language_pack parser API is not exposed')
  end

  it 'parses through the language-pack parser API when available' do
    raw_node = instance_double(
      'TreeSitterLanguagePack::Node',
      kind: 'document',
      start_byte: 0,
      end_byte: 9,
      child_count: 0,
      is_named: true,
      has_error: false,
      is_error: false,
      is_missing: false,
      is_extra: false
    )
    raw_tree = instance_double('TreeSitterLanguagePack::Tree', root_node: raw_node)
    parser = double(
      'TreeSitterLanguagePack::Parser',
      set_language: nil,
      parse: raw_tree
    )
    parser_class = double('TreeSitterLanguagePack::Parser', new: parser)
    stub_const('TreeSitterLanguagePack', Module.new)
    TreeSitterLanguagePack.const_set(:Parser, parser_class)

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:toml)
    tree = tree_haver_parser.parse("title = 1\n")

    expect(parser).to have_received(:set_language).with('toml')
    expect(parser).to have_received(:parse).with("title = 1\n")
    expect(tree.root_node.type).to eq('document')
  end
end
