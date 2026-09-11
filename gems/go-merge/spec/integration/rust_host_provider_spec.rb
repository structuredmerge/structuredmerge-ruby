# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Go::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

  before { Go::Merge.register_rust_host_provider!(replace: true) }

  let(:request_base) do
    {
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end
  let(:base_source) { "package main\n\nfunc left() int { return 1 }\n\nfunc right() int { return 1 }\n" }
  let(:ours_source) { "package main\n\nfunc left() int { return 2 }\n\nfunc right() int { return 1 }\n" }
  let(:theirs_source) { "package main\n\nfunc left() int { return 1 }\n\nfunc right() int { return 2 }\n" }

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
      expect(result.fetch(:provider)).to include(provider_id: 'rust.go', backend: :rust_tslp)
      expect(result.fetch(:verification)).to include(rust_host: true)
      expect(result.fetch(:ok)).to be(true), result.inspect
    end
  end

  it 'dispatches an explicitly selected Rust provider through the registry' do
    result = Ast::Merge.dispatch_provider(
      :merge2,
      request_base.merge(
        provider_id: 'rust.go',
        incoming_source: ours_source,
        current_source: base_source
      )
    )

    expect(result.fetch(:provider)).to include(provider_id: 'rust.go')
    expect(result.fetch(:verification)).to include(rust_host: true)
    expect(result.fetch(:ok)).to be(true), result.inspect
  end

  it 'preserves native merge3 output for independent function edits' do
    request = request_base.merge(
      base_source: base_source,
      ours_source: ours_source,
      theirs_source: theirs_source
    )

    native = Go::Merge::Provider.new.merge3(request)
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
end
