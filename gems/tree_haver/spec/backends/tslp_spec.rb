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
    allow(described_class).to receive(:parser_api_available?).and_return(false)

    expect(described_class.available?).to be(false)
    expect(described_class.unavailable_reason).to eq('tree_sitter_language_pack parser API is not exposed')
  end

  it 'parses through the language-pack parser API when available' do
    raw_node = instance_double(
      'TreeSitterLanguagePack::Node',
      kind: 'document',
      start_byte: 0,
      end_byte: 9,
      start_position: instance_double('TreeSitterLanguagePack::Point', row: 0, column: 0),
      end_position: instance_double('TreeSitterLanguagePack::Point', row: 0, column: 9),
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
    expect(tree.root_node.start_point).to eq({ row: 0, column: 0 })
    expect(tree.root_node.end_point).to eq({ row: 0, column: 9 })
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

  it 'exposes real TSLP point locations through TreeHaver nodes when available' do
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
    object = tree_haver_parser.parse("{\n  \"a\": 1\n}\n").root_node.children.find { |child| child.type == 'object' }
    pair = object.children.find { |child| child.type == 'pair' }

    expect(pair.start_point).to eq({ row: 1, column: 2 })
    expect(pair.end_point).to eq({ row: 1, column: 8 })
    expect(pair.start_line).to eq(2)
    expect(pair.end_line).to eq(2)
  end

  it 'parses the source-family languages expected to use TSLP when available' do
    begin
      require 'tree_sitter_language_pack'
    rescue LoadError
      skip 'tree_sitter_language_pack is not installed'
    end

    described_class.reset!
    skip described_class.unavailable_reason || 'tree_sitter_language_pack parser API is unavailable' unless described_class.available?

    fixtures = {
      json: ['{"a":1}', 'document'],
      toml: ["title = \"demo\"\n[tool]\nname = \"x\"\n", 'document'],
      bash: ["echo hi\n", 'program'],
      go: ["package main\nfunc main() {}\n", 'source_file'],
      rust: ["fn main() {}\n", 'source_file'],
      typescript: ["export const x = 1;\n", 'program'],
      ruby: ["class X\nend\n", 'program'],
      yaml: ["name: demo\n", 'stream'],
      markdown: ["# Heading\n\nBody\n", 'document']
    }

    fixtures.each do |language, (source, expected_root)|
      skip "tree_sitter_language_pack does not publish #{language}" unless TreeSitterLanguagePack.has_language(language.to_s)

      TreeHaver::GrammarFinder.new(language).register!(raise_on_missing: true)
      tree = TreeHaver.with_backend('tslp') { TreeHaver.parser_for(language).parse(source) }

      expect(tree.root_node.type).to eq(expected_root)
      expect(tree.root_node).not_to have_error
    end
  end
end
