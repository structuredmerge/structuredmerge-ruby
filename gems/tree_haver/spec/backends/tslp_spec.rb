# frozen_string_literal: true

require_relative '../spec_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe TreeHaver::Backends::Tslp do
  before do
    described_class.reset!
  end

  after do
    # Several examples replace TreeSitterLanguagePack to exercise fail-closed
    # behavior. Reset the backend memoization at the end of each example so a
    # failed smoke probe cannot poison unrelated parser-backed specs.
    described_class.reset!
  end

  it 'reports availability only when tree_sitter_language_pack exposes a parser API' do
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new do
      def parse(_source)
        :tree
      end
    end
    parser = instance_double(
      'TreeSitterLanguagePack::Parser',
      parse: instance_double(
        'TreeSitterLanguagePack::Tree',
        root_node: instance_double('TreeSitterLanguagePack::Node', has_error: false)
      )
    )
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:has_language).with('json').and_return(true)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('json').and_return(parser)

    expect(described_class.available?).to be(true)
  end

  it 'fails closed when the exposed parser method cannot parse a smoke fixture' do
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new do
      def parse(_source)
        raise TypeError, 'no implicit conversion of TreeSitterLanguagePack::Parser into TreeSitterLanguagePack::Parser'
      end
    end
    parser = parser_class.new
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:has_language).with('json').and_return(true)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('json').and_return(parser)

    expect(described_class.available?).to be(false)
    expect(described_class.unavailable_reason)
      .to include('no implicit conversion of TreeSitterLanguagePack::Parser into TreeSitterLanguagePack::Parser')
  end

  it 'validates the requested language by parsing that language smoke source' do
    raw_tree = instance_double(
      'TreeSitterLanguagePack::Tree',
      root_node: instance_double('TreeSitterLanguagePack::Node', has_error: false)
    )
    parser = instance_double('TreeSitterLanguagePack::Parser', parse: raw_tree)
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new
    parser_class.define_method(:parse) { |_source| :tree }
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:has_language).with('toml').and_return(true)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('toml').and_return(parser)
    allow(described_class).to receive(:available?).and_return(true)

    expect(described_class.parser_available_for?(:toml)).to be(true)
    expect(parser).to have_received(:parse).with("title = \"tree_haver\"\n")
  end

  it 'rejects the requested language when its smoke source cannot parse cleanly' do
    raw_tree = instance_double(
      'TreeSitterLanguagePack::Tree',
      root_node: instance_double('TreeSitterLanguagePack::Node', has_error: true)
    )
    parser = instance_double('TreeSitterLanguagePack::Parser', parse: raw_tree)
    stub_const('TreeSitterLanguagePack', Module.new)
    parser_class = Class.new
    parser_class.define_method(:parse) { |_source| :tree }
    TreeSitterLanguagePack.const_set(:Parser, parser_class)
    allow(TreeSitterLanguagePack).to receive(:has_language).with('json').and_return(true)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('json').and_return(parser)
    allow(described_class).to receive(:available?).and_return(true)

    expect(described_class.parser_available_for?(:json)).to be(false)
    expect(parser).to have_received(:parse).with('{}')
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
    allow(described_class).to receive(:available?).and_return(true)

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:toml)
    tree = tree_haver_parser.parse("title = 1\n")

    expect(TreeSitterLanguagePack).to have_received(:get_parser).with('toml')
    expect(parser).to have_received(:parse).with("title = 1\n")
    expect(tree.root_node.type).to eq('document')
    expect(tree.root_node.start_point).to eq({ row: 0, column: 0 })
    expect(tree.root_node.end_point).to eq({ row: 0, column: 9 })
  end

  it 'retags valid UTF-8 filesystem bytes without transcoding before TSLP parsing' do
    source = "{\"label\":\"caf\u00e9\"}".b
    raw_tree = double('TreeSitterLanguagePack::Tree')
    parser = double('TreeSitterLanguagePack::Parser', parse: raw_tree)
    allow(described_class).to receive(:available?).and_return(true)
    stub_const('TreeSitterLanguagePack', Module.new)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('json').and_return(parser)

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:json)
    tree_haver_parser.parse(source)

    expect(parser).to have_received(:parse) do |parsed_source|
      expect(parsed_source.encoding).to eq(Encoding::UTF_8)
      expect(parsed_source.b).to eq(source)
    end
    expect(source.encoding).to eq(Encoding::BINARY)
  end

  it 'does not relabel invalid binary source as UTF-8' do
    source = "{\"label\":\"\xFF\"}".b
    raw_tree = double('TreeSitterLanguagePack::Tree')
    parser = double('TreeSitterLanguagePack::Parser', parse: raw_tree)
    allow(described_class).to receive(:available?).and_return(true)
    stub_const('TreeSitterLanguagePack', Module.new)
    allow(TreeSitterLanguagePack).to receive(:get_parser).with('json').and_return(parser)

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:json)
    tree_haver_parser.parse(source)

    expect(parser).to have_received(:parse).with(source)
  end

  it 'can parse through a real TSLP language when the installed binding exposes parser methods' do
    begin
      require 'tree_sitter_language_pack'
    rescue LoadError
      skip 'tree_sitter_language_pack is not installed'
    end

    described_class.reset!
    unless described_class.available?
      skip described_class.unavailable_reason || 'tree_sitter_language_pack parser API is unavailable'
    end
    skip 'tree_sitter_language_pack does not publish json' unless TreeSitterLanguagePack.has_language('json')

    tree_haver_parser = described_class::Parser.new
    tree_haver_parser.language = described_class::Language.new(:json)
    tree = tree_haver_parser.parse('{"a":1}')

    expect(tree.root_node.type).to eq('document')
    expect(tree.root_node.children.map(&:type)).to include('object')
  end

  it 'normalizes JSON5 root and member names for portable JSON consumers' do
    begin
      require 'tree_sitter_language_pack'
    rescue LoadError
      skip 'tree_sitter_language_pack is not installed'
    end

    described_class.reset!
    unless described_class.available?
      skip described_class.unavailable_reason || 'tree_sitter_language_pack parser API is unavailable'
    end
    skip 'tree_sitter_language_pack does not publish json5' unless TreeSitterLanguagePack.has_language('json5')

    TreeHaver::GrammarFinder.new(:json5).register!(raise_on_missing: true)
    tree = TreeHaver.with_backend('tslp') do
      TreeHaver.parser_for(:json5).parse("// comment\n{\n  \"name\": \"value\",\n}\n")
    end

    object = tree.root_node.children.find { |child| child.type == 'object' }
    pair = object.children.find { |child| child.type == 'pair' }

    expect(tree.root_node.type).to eq('document')
    expect(tree.root_node.native_type).to eq('file')
    expect(pair.native_type).to eq('member')
    expect(pair.child_by_field_name('value').type).to eq('string')
  end

  it 'exposes real TSLP point locations through TreeHaver nodes when available' do
    begin
      require 'tree_sitter_language_pack'
    rescue LoadError
      skip 'tree_sitter_language_pack is not installed'
    end

    described_class.reset!
    unless described_class.available?
      skip described_class.unavailable_reason || 'tree_sitter_language_pack parser API is unavailable'
    end
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
    unless described_class.available?
      skip described_class.unavailable_reason || 'tree_sitter_language_pack parser API is unavailable'
    end

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
      unless TreeSitterLanguagePack.has_language(language.to_s)
        skip "tree_sitter_language_pack does not publish #{language}"
      end

      TreeHaver::GrammarFinder.new(language).register!(raise_on_missing: true)
      tree = TreeHaver.with_backend('tslp') { TreeHaver.parser_for(language).parse(source) }

      expect(tree.root_node.type).to eq(expected_root)
      expect(tree.root_node).not_to have_error
    end
  end
end
# rubocop:enable Metrics/BlockLength
