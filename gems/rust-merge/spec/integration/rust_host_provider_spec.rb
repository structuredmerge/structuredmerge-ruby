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

  it 'reports edits when declaration identity is unchanged' do
    result = provider.diff2(request_base.merge(before_source: base_source, after_source: ours_source))

    expect(result.fetch(:ok)).to be(true), result.inspect
    expect(result.fetch(:changes)).to include(path: '[:function, "left"]', change: :edited)
  end

  it 'fails closed on malformed source with a normalized parse diagnostic' do
    request = request_base.merge(source: "fn {")
    result = provider.analyze(request)

    expect(result.fetch(:ok)).to be(false)
    expect(result.fetch(:provider)).to include(provider_id: 'rust.rust')
    expect(result.fetch(:diagnostics).first).to include(category: :parse_error, blocking: true)
  end
end
