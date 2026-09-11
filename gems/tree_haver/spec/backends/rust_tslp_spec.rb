# frozen_string_literal: true

require_relative '../spec_helper'
require 'json'

# rubocop:disable Metrics/BlockLength
RSpec.describe TreeHaver::Backends::RustTslp do
  let(:source) { "{\n  \"answer\": 42\n}\n" }
  let(:result) do
    {
      'ok' => true,
      'backend_capability' => { 'backend_ref' => { 'id' => 'kreuzberg-language-pack' } },
      'root_id' => 'tslp:json:0',
      'nodes' => [
        {
          'id' => 'tslp:json:0',
          'kind' => 'document',
          'role' => 'root',
          'child_ids' => ['tslp:json:1'],
          'span' => {
            'range' => { 'start_byte' => 0, 'end_byte' => source.bytesize },
            'start_point' => { 'row' => 0, 'column' => 0 },
            'end_point' => { 'row' => 2, 'column' => 1 }
          },
          'named' => true,
          'has_source_text' => true,
          'source_fragment' => source,
          'backend_roles' => []
        },
        {
          'id' => 'tslp:json:1',
          'kind' => 'object',
          'role' => 'named',
          'parent_id' => 'tslp:json:0',
          'child_ids' => [],
          'span' => {
            'range' => { 'start_byte' => 0, 'end_byte' => source.bytesize },
            'start_point' => { 'row' => 0, 'column' => 0 },
            'end_point' => { 'row' => 2, 'column' => 1 }
          },
          'named' => true,
          'has_source_text' => true,
          'source_fragment' => source,
          'backend_roles' => []
        }
      ],
      'diagnostics' => []
    }
  end

  before do
    stub_const('StructuredmergeHostPrototype', Module.new)
    allow(StructuredmergeHostPrototype).to receive(:parse_normalized_with_tslp)
      .with('json', source, 'json')
      .and_return(JSON.generate(result))
    described_class.reset!
  end

  after { described_class.reset! }

  it 'adapts the Rust normalized tree with source, topology, points, and provenance' do
    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse(source)
    end
    root = tree.root_node

    expect(tree.provenance.dig('backend_ref', 'id')).to eq('kreuzberg-language-pack')
    expect(root.type).to eq('document')
    expect(root.text).to eq(source)
    expect(root.start_point).to eq(row: 0, column: 0)
    expect(root.children.map(&:type)).to eq(['object'])
    expect(root.first_child.parent).to eq(root)
    expect(root.first_child.prev_sibling).to be_nil
  end

  it 'routes tree-sitter contract requests through the selected Rust provider' do
    parser = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json, backend_type: :tree_sitter)
    end

    expect(parser).to be_a(described_class::Parser)
    expect(parser.parse(source).root_node.type).to eq('document')
  end

  it 'uses a full parse for parse_string and does not retain incremental edit state' do
    next_source = "{\n  \"answer\": 43\n}\n"
    allow(StructuredmergeHostPrototype).to receive(:parse_normalized_with_tslp)
      .with('json', next_source, 'json')
      .and_return(JSON.generate(result.merge(
        'nodes' => result.fetch('nodes').map do |node|
          node.merge('source_fragment' => node.fetch('source_fragment').sub('42', '43'))
        end
      )))

    parser = described_class::Parser.new
    parser.language = described_class::Language.new(:json)
    tree = parser.parse(source)
    reparsed = parser.parse_string(tree, next_source)

    expect(reparsed.root_node.text).to eq(next_source)
    expect(tree.edit(
      start_byte: 0,
      old_end_byte: 1,
      new_end_byte: 1,
      start_point: { row: 0, column: 0 },
      old_end_point: { row: 0, column: 1 },
      new_end_point: { row: 0, column: 1 }
    )).to be_nil
    expect(tree.root_node.text).to eq(source)
  end

  it 'rejects invalid binary source rather than changing source bytes' do
    parser = described_class::Parser.new
    parser.language = described_class::Language.new(:json)

    expect { parser.parse("{\"bad\":\"\xFF\"}".b) }
      .to raise_error(TreeHaver::NotAvailable, /requires valid UTF-8/)
  end

  it 'advertises unsupported operations instead of emulating native behavior' do
    expect(described_class.capabilities).to include(
      backend: :rust_tslp,
      query: false,
      incremental: false,
      comment_support: :nodes_only,
      provenance: :rust_tree_haver
    )
  end

  it 'preserves parser diagnostics and error-node flags from a partial tree' do
    malformed = result.merge(
      'ok' => false,
      'diagnostics' => ['tree-sitter-language-pack reported syntax errors for json.'],
      'nodes' => result.fetch('nodes').map do |node|
        node.merge('role' => node.fetch('kind') == 'object' ? 'error' : node.fetch('role'))
      end
    )
    allow(StructuredmergeHostPrototype).to receive(:parse_normalized_with_tslp)
      .with('json', source, 'json')
      .and_return(JSON.generate(malformed))

    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse(source)
    end

    expect(tree.errors).to eq(['tree-sitter-language-pack reported syntax errors for json.'])
    expect(tree.has_error?).to be(true)
    expect(tree.root_node.children.first.error?).to be(true)
  end

  it 'exposes comments as normalized nodes without emulating comment attachment APIs' do
    comment_source = "// note\n{}\n"
    comment = {
      'id' => 'tslp:json:comment',
      'kind' => 'line_comment',
      'role' => 'comment',
      'parent_id' => 'tslp:json:0',
      'child_ids' => [],
      'span' => {
        'range' => { 'start_byte' => 0, 'end_byte' => 7 },
        'start_point' => { 'row' => 0, 'column' => 0 },
        'end_point' => { 'row' => 0, 'column' => 7 }
      },
      'named' => false,
      'has_source_text' => true,
      'source_fragment' => '// note',
      'backend_roles' => []
    }
    commented = result.merge(
      'nodes' => [
        result.fetch('nodes').first.merge('child_ids' => ['tslp:json:comment']),
        comment
      ],
      'root_id' => 'tslp:json:0'
    )
    allow(StructuredmergeHostPrototype).to receive(:parse_normalized_with_tslp)
      .with('json', comment_source, 'json')
      .and_return(JSON.generate(commented))

    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse(comment_source)
    end

    expect(tree.root_node.children.first.native_type).to eq('line_comment')
    expect(tree.comments).to eq([])
  end
end
# rubocop:enable Metrics/BlockLength
