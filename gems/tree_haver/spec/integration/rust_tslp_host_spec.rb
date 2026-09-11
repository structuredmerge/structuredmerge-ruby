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

    expect(tree.provenance.dig('backend_ref', 'id')).to eq('kreuzberg-language-pack')
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
    expect(tree.errors).to include('tree-sitter-language-pack reported syntax errors for json.')
    expect(tree.has_error?).to be(true)
    expect(tree.root_node.text).to eq('{"answer":')
  end
end
