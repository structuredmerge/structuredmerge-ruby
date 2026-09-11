# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe TreeHaver::Backends::RustTslp do
  it 'normalizes JSON5 node names to the established TSLP contract' do
    tree = TreeHaver.with_backend(:rust_tslp) do
      TreeHaver::GrammarFinder.new(:json5).register!(raise_on_missing: true)
      TreeHaver.parser_for(:json5).parse("{ answer: true }\n")
    end

    root = tree.root_node
    member = root.children.first.children.find { |child| child.native_type == 'member' }

    expect(root.type).to eq('document')
    expect(root.native_type).to eq('file')
    expect(member.type).to eq('pair')
    expect(member.native_type).to eq('member')
  end
end
