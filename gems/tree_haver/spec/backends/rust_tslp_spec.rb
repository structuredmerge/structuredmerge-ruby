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
    stub_const('StructuredmergeCore', Module.new)
    %w[SourceDescriptor LineEndings SourceInput ParseRequest ParserSelection ParseOptions ParseLimits].each do |name|
      klass = Class.new do
        def self.new(**fields)
          Struct.new(*fields.keys, keyword_init: true).new(**fields)
        end
      end
      stub_const("StructuredmergeCore::#{name}", klass)
    end
    allow(StructuredmergeCore).to receive(:register_language_pack_parser)
      .with('tree_haver.rust_tslp.json', 'json').and_return(record(id: 'tree_haver.rust_tslp.json'))
    allow(StructuredmergeCore).to receive(:parse_sources).and_return([typed_result(result)])
    described_class.reset!
  end

  after { described_class.reset! }

  def record(**fields)
    Struct.new(*fields.keys, keyword_init: true).new(**fields)
  end

  # Test doubles for generated DTOs keep unit tests independent of an optional gem.
  # Installed-artifact integration tests below exercise the real generated types.
  def typed_result(value)
    nodes = value.fetch('nodes').map do |node|
      span = node.fetch('span')
      record(id: node.fetch('id'), native_type: node.fetch('kind'), named: node.fetch('named'),
        missing: node.fetch('backend_roles', []).include?('missing'),
        has_error: node['role'] == 'error' || !value.fetch('ok', true),
        parent_id: node['parent_id'],
        children: node.fetch('child_ids', []).map { |id| record(node_id: id, field_name: nil) },
        extensions: [record(schema: 'tree-haver.tree-sitter.node/v1', namespace: 'tree-sitter', payload: '{"extra":true}')],
        span: record(range: record(**span.fetch('range').transform_keys(&:to_sym)),
          start_point: record(**span.fetch('start_point').transform_keys(&:to_sym)),
          end_point: record(**span.fetch('end_point').transform_keys(&:to_sym))))
    end
    record(parsed: record(nodes: nodes, root_id: value.fetch('root_id'),
      diagnostics: value.fetch('diagnostics').map { |message| record(message: message) }),
      backend: record(id: 'tree_haver.rust_tslp.json', runtime: 'rust', parser: 'tree-sitter-language-pack', parser_version: 'runtime'))
  end

  it 'adapts the Rust normalized tree with source, topology, points, and provenance' do
    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse(source)
    end
    root = tree.root_node

    expect(tree.provenance.dig('backend_ref', 'id')).to eq('tree_haver.rust_tslp.json')
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

  it 'fails closed when the selected Rust provider is unavailable' do
    allow(described_class).to receive(:available?).and_return(false)
    parser = described_class::Parser.new
    parser.language = described_class::Language.new(:json)

    expect { parser.parse(source) }
      .to raise_error(TreeHaver::NotAvailable, /Rust TreeHaver normalized parser is unavailable/)
  end

  it 'preserves parser diagnostics and error-node flags from a partial tree' do
    malformed = result.merge(
      'ok' => false,
      'diagnostics' => ['tree-sitter-language-pack reported syntax errors for json.'],
      'nodes' => result.fetch('nodes').map do |node|
        node.merge('role' => node.fetch('kind') == 'object' ? 'error' : node.fetch('role'))
      end
    )
    allow(StructuredmergeCore).to receive(:parse_sources).and_return([typed_result(malformed)])

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
    allow(StructuredmergeCore).to receive(:parse_sources).and_return([typed_result(commented)])

    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse(comment_source)
    end

    expect(tree.root_node.children.first.native_type).to eq('line_comment')
    expect(tree.root_node.children.first.extra?).to be(true)
    expect(tree.comments).to eq([])
  end

  it 'registers once and pins typed requests to the explicit provider' do
    parser = described_class::Parser.new
    parser.language = described_class::Language.new(:json)
    2.times { parser.parse(source) }
    expect(StructuredmergeCore).to have_received(:register_language_pack_parser).once
    expect(StructuredmergeCore).to have_received(:parse_sources).twice do |requests, limits|
      request = requests.fetch(0)
      expect(request.selection.backend_id).to eq('tree_haver.rust_tslp.json')
      expect(request.source.bytes.pack('C*')).to eq(source)
      expect(request.source.descriptor.sha256).to eq(Digest::SHA256.hexdigest(source))
      expect(request.options.native_extensions).to be(true)
      expect(limits.max_batch_items).to eq(1)
    end
  end

  it 'does not adopt foreign duplicate registrations' do
    allow(StructuredmergeCore).to receive(:register_language_pack_parser).and_raise(RuntimeError, 'registration: DuplicateId')
    parser = described_class::Parser.new
    parser.language = described_class::Language.new(:json)
    expect { parser.parse(source) }.to raise_error(RuntimeError, /DuplicateId/)
    expect(StructuredmergeCore).not_to have_received(:parse_sources)
  end
end
# rubocop:enable Metrics/BlockLength
