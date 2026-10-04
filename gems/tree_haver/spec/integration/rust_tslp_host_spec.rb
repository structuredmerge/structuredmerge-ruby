# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Rust TSLP host integration' do
  let(:source) { "{\n  \"answer\": 42\n}\n" }

  it 'parses through the canonical Rust host when its platform gem is installed' do
    skip TreeHaver::Backends::RustTslp.unavailable_reason unless TreeHaver::Backends::RustTslp.available?

    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse(source)
    end
    root = tree.root_node
    object = root.children.find { |child| child.type == 'object' }
    pair = object.children.find { |child| child.type == 'pair' }

    expect(tree.provenance.dig('backend_ref', 'id')).to eq('tree_haver.rust_tslp.json')
    expect(root.type).to eq('document')
    expect(root.text).to eq(source)
    expect(pair.text).to eq('"answer": 42')
    expect(pair.start_point).to eq(row: 1, column: 2)
    expect(pair.end_point).to eq(row: 1, column: 14)
    expect(pair.child_by_field_name(:key).text).to eq('"answer"')
    expect(pair.child_by_field_name(:value).text).to eq('42')
  end

  it 'returns a partial tree with diagnostics for malformed source' do
    skip TreeHaver::Backends::RustTslp.unavailable_reason unless TreeHaver::Backends::RustTslp.available?

    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json).parse('{"answer":')
    end

    expect(tree.errors).not_to be_empty
    expect(tree.errors).to include('native parser reported syntax errors')
    expect(tree.has_error?).to be(true)
    expect(tree.root_node.text).to eq('{"answer":')
  end

  it 'preserves native extra flags and immutable Unicode/CRLF source bytes' do
    skip TreeHaver::Backends::RustTslp.unavailable_reason unless TreeHaver::Backends::RustTslp.available?

    input = +"// café\r\n{\"é\":true}"
    parser = TreeHaver::Backends::RustTslp::Parser.new
    parser.language = TreeHaver::Backends::RustTslp::Language.new(:json)
    tree = parser.parse(input)
    input.replace('changed')
    comment = tree.root_node.children.find { |node| node.native_type == 'comment' }
    # This grammar includes CR in the comment span; keep its actual bytes.
    expect(comment.text).to eq("// café\r")
    expect(comment.extra?).to be(true)
    expect(comment.missing?).to be(false)
    expect(tree.root_node.extra?).to be(false)
    expect(tree.root_node.text).to eq("// café\r\n{\"é\":true}")
    expect(defined?(StructuredmergeHostPrototype)).to be_nil
  end
end
