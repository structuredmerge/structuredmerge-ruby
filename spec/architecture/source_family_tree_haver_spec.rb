# frozen_string_literal: true

require_relative '../../gems/go-merge/lib/go/merge'
require_relative '../../gems/rust-merge/lib/rust/merge'
require_relative '../../gems/typescript-merge/lib/typescript/merge'

RSpec.describe 'source-family TreeHaver parsing' do
  before do
    allow(TreeHaver).to receive(:parser_for) do |language_name|
      raise TreeHaver::NotAvailable, "No parser registered for #{language_name}"
    end
  end

  it 'fails closed through TreeHaver when Go has no registered parser' do
    result = Go::Merge.parse_go("package main\n", 'go')

    expect(TreeHaver).to have_received(:parser_for).with(:go)
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to include(
      include(severity: 'error', category: 'parse_error', message: include('No parser registered for go'))
    )
  end

  it 'fails closed through TreeHaver when Rust has no registered parser' do
    result = Rust::Merge.parse_rust("fn main() {}\n", 'rust')

    expect(TreeHaver).to have_received(:parser_for).with(:rust)
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to include(
      include(severity: 'error', category: 'parse_error', message: include('No parser registered for rust'))
    )
  end

  it 'fails closed through TreeHaver when TypeScript has no registered parser' do
    result = TypeScript::Merge.parse_type_script("export const x = 1;\n", 'typescript')

    expect(TreeHaver).to have_received(:parser_for).with(:typescript)
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to include(
      include(severity: 'error', category: 'parse_error', message: include('No parser registered for typescript'))
    )
  end
end
