# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rust::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

  before { Rust::Merge.register_rust_host_provider!(replace: true) }

  let(:request_base) do
    {
      family: :rust,
      dialect: :rust,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end
  let(:base_source) { "fn left() -> i32 { 1 }\n\nfn right() -> i32 { 1 }\n" }
  let(:ours_source) { "fn left() -> i32 { 2 }\n\nfn right() -> i32 { 1 }\n" }
  let(:theirs_source) { "fn left() -> i32 { 1 }\n\nfn right() -> i32 { 2 }\n" }

  it 'satisfies the provider contract for every operation through the host' do
    requests = {
      analyze: request_base.merge(source: base_source),
      diff2: request_base.merge(before_source: base_source, after_source: ours_source),
      merge2: request_base.merge(incoming_source: ours_source, current_source: base_source),
      merge3: request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    }

    requests.each do |operation, request|
      result = provider.public_send(operation, request)
      expect(Ast::Merge::ProviderContract.validate_result!(operation, result)).to eq(result)
      expect(result.fetch(:provider)).to include(provider_id: 'rust.rust', backend: :rust_tslp)
      expect(result.fetch(:verification)).to include(rust_host: true)
      expect(result.fetch(:ok)).to be(true), result.inspect
    end
  end

  it 'dispatches an explicitly selected Rust provider through the registry' do
    result = Ast::Merge.dispatch_provider(
      :merge2,
      request_base.merge(
        provider_id: 'rust.rust',
        incoming_source: ours_source,
        current_source: base_source
      )
    )

    expect(result.fetch(:provider)).to include(provider_id: 'rust.rust')
    expect(result.fetch(:verification)).to include(rust_host: true)
    expect(result.fetch(:ok)).to be(true), result.inspect
  end

  it 'preserves native merge3 output for independent function edits' do
    request = request_base.merge(
      base_source: base_source,
      ours_source: ours_source,
      theirs_source: theirs_source
    )

    native = Rust::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native merge3 output for independent named item edits' do
    base = "const LIMIT: usize = 1;\n\nstruct Config {\n    value: usize,\n}\n"
    ours = base.sub('LIMIT: usize = 1', 'LIMIT: usize = 2')
    theirs = base.sub('value: usize', 'value: u64')
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Rust::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native merge2 output' do
    request = request_base.merge(incoming_source: ours_source, current_source: base_source)
    native = Rust::Merge::Provider.new.merge2(request)
    rust = provider.merge2(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'reports edits when declaration identity is unchanged' do
    result = provider.diff2(request_base.merge(before_source: base_source, after_source: ours_source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    change = result.fetch(:changes).find { |entry| entry[:path] == '[:function, "left"]' }
    expect(change).to include(
      before: { present: true, source_role: :before, line_range: [1, 1] },
      after: { present: true, source_role: :after, line_range: [1, 1] },
      change: :edited
    )
  end

  it 'preserves named declaration kinds in host analysis and diff paths' do
    source = "const LIMIT: usize = 1;\n\nstruct Config {\n    value: usize,\n}\n"
    analysis = provider.analyze(request_base.merge(source: source))
    paths = analysis.dig(:analysis, :declarations).map { |declaration| declaration.fetch(:path) }

    expect(paths).to contain_exactly('[:const, "LIMIT"]', '[:struct, "Config"]')

    changed = source.sub('LIMIT: usize = 1', 'LIMIT: usize = 2')
    diff = provider.diff2(request_base.merge(before_source: source, after_source: changed))

    expect(diff.fetch(:changes).map { |change| change.fetch(:path) }).to include('[:const, "LIMIT"]')
  end

  it 'reports added and deleted declarations with explicit presence records' do
    after_source = "fn left() -> i32 { 1 }\n\nfn added() -> i32 { 4 }\n"
    result = provider.diff2(request_base.merge(before_source: base_source, after_source: after_source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    deleted = result.fetch(:changes).find { |entry| entry[:path] == '[:function, "right"]' }
    added = result.fetch(:changes).find { |entry| entry[:path] == '[:function, "added"]' }
    expect(deleted).to include(
      before: { present: true, source_role: :before, line_range: [3, 3] },
      after: { present: false, source_role: :after, line_range: [nil, nil] },
      change: :deleted
    )
    expect(added).to include(
      before: { present: false, source_role: :before, line_range: [nil, nil] },
      after: { present: true, source_role: :after, line_range: [3, 3] },
      change: :added
    )
  end

  it 'fails closed on malformed source with a normalized parse diagnostic' do
    request = request_base.merge(source: "fn {")
    result = provider.analyze(request)

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.rust')
    expect(result.fetch(:diagnostics).first).to include(category: :parse_error, blocking: true)
  end

  it 'preserves a localized conflict envelope for incompatible edits' do
    conflicting_theirs = base_source.sub('fn left() -> i32 { 1 }', 'fn left() -> i32 { 3 }')
    result = provider.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: conflicting_theirs)
    )

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.rust')
    expect(result.fetch(:conflicts)).not_to be_empty
  end

  it 'matches native behavior for independently edited reordered declarations' do
    reordered_ours = base_source.sub(
      'fn left() -> i32 { 1 }\n\nfn right() -> i32 { 1 }',
      'fn right() -> i32 { 1 }\n\nfn left() -> i32 { 2 }'
    )
    reordered_theirs = base_source.sub(
      'fn left() -> i32 { 1 }\n\nfn right() -> i32 { 1 }',
      'fn right() -> i32 { 3 }\n\nfn left() -> i32 { 1 }'
    )
    request = request_base.merge(
      base_source: base_source,
      ours_source: reordered_ours,
      theirs_source: reordered_theirs
    )
    native = Rust::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end
end
