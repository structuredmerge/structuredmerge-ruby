# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe TreeHaver::Backends::Tslp do
  before do
    described_class.reset!
  end

  it 'reports availability only when tree_sitter_language_pack exposes a parser API' do
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new do
      def parse(_source)
        :tree
      end
    end
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:get_parser)

    expect(described_class.available?).to be(true)
  end

  it 'fails closed when the installed language pack does not expose parser methods' do
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:get_parser)

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
    parser = double('TreeSitterLanguagePack::Parser', parse: raw_tree)
    parser_class = Class.new do
      def parse(_source)
        :tree
      end
    end
    stub_const('TreeSitterLanguagePack', Module.new)
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('toml').and_return(parser)

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:toml)
    tree = tree_haver_parser.parse("title = 1\n")

    expect(TreeSitterLanguagePack).to have_received(:get_parser).with('toml')
    expect(parser).to have_received(:parse).with("title = 1\n")
    expect(tree.root_node.type).to eq('document')
  end

  it 'can parse through a real TSLP language when the installed binding exposes parser methods' do
    begin
      require 'tree_sitter_language_pack'
    rescue LoadError
      skip 'tree_sitter_language_pack is not installed'
    end

    described_class.reset!
    skip described_class.unavailable_reason || 'tree_sitter_language_pack parser API is unavailable' unless described_class.available?
    skip 'tree_sitter_language_pack does not publish json' unless TreeSitterLanguagePack.has_language('json')

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:json)
    tree = tree_haver_parser.parse('{"a":1}')

    expect(tree.root_node.type).to eq('document')
    expect(tree.root_node.children.map(&:type)).to include('object')
  end
end
