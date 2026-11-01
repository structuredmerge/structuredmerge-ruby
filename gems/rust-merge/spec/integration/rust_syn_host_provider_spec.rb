# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rust::Merge::RustHostProvider do
  it 'runs Rust typed analysis through the native syn parser' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    descriptor = StructuredmergeCore.register_rust_syn_parser("rust.syn.ruby")
    expect(StructuredmergeCore.register_rust_syn_parser("rust.syn.ruby").id).to eq(descriptor.id)

    provider = described_class.new
    result = provider.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: "/// Native documentation\nfn café() {}\n"
    )

    expect(result.fetch(:ok)).to be(true), result.inspect
    expect(result.fetch(:provider)).to include(backend: :rust_syn)
    declaration = result.dig(:analysis, :declarations).fetch(0)
    expect(declaration.fetch(:path)).to eq('/function:café')
    expect(declaration.fetch(:line_range)).to eq([1, 2])

    base = "fn left() -> i32 { 1 }\n\nfn right() -> i32 { 1 }\n"
    ours = base.sub("{ 1 }", "{ 2 }")
    theirs = base.sub("fn right() -> i32 { 1 }", "fn right() -> i32 { 2 }")
    diff = provider.diff2(family: :rust, dialect: :rust, backend: :rust_syn,
                          profile_id: :source_preserving, before_source: base, after_source: ours)
    merge = provider.merge3(family: :rust, dialect: :rust, backend: :rust_syn,
                            profile_id: :source_preserving, base_source: base,
                            ours_source: ours, theirs_source: theirs)
    directional = provider.merge2(family: :rust, dialect: :rust, backend: :rust_syn,
                                  profile_id: :source_preserving, incoming_source: ours,
                                  current_source: base)

    expect(diff.fetch(:ok)).to be(true), diff.inspect
    expect(diff.fetch(:changes).map { |change| change.fetch(:path) }).to include('/function:left')
    expect(merge.fetch(:ok)).to be(true), merge.inspect
    expect(merge.fetch(:output)).to include("fn left() -> i32 { 2 }", "fn right() -> i32 { 2 }")
    expect(directional.fetch(:ok)).to be(true), directional.inspect
  end

  it 'fails closed on syntax errors and unsupported native Rust items' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    provider = described_class.new
    request = {
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving
    }
    malformed = provider.analyze(request.merge(source: "fn broken("))
    unsupported = provider.analyze(request.merge(source: "unsafe extern \"C\" { fn native_symbol(); }\n"))

    expect(malformed.fetch(:ok)).to be(false)
    malformed_messages = malformed.fetch(:diagnostics).map { |item| item.fetch(:message) }.join
    expect(malformed_messages).to include('native parser rejected input')
    expect(unsupported.fetch(:ok)).to be(false)
    unsupported_messages = unsupported.fetch(:diagnostics).map { |item| item.fetch(:message) }.join
    expect(unsupported_messages).to include('unsupported top-level Rust node')
  end
end
