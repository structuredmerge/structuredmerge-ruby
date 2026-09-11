# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Bash::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

  let(:request_base) do
    {
      family: :bash,
      dialect: :bash,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end
  let(:base_source) { "left() { echo one; }\nright() { echo one; }\n" }
  let(:ours_source) { "left() { echo two; }\nright() { echo one; }\n" }
  let(:theirs_source) { "left() { echo one; }\nright() { echo two; }\n" }

  it 'satisfies the provider contract through the generated host' do
    requests = {
      analyze: request_base.merge(source: base_source),
      diff2: request_base.merge(before_source: base_source, after_source: ours_source),
      merge2: request_base.merge(incoming_source: ours_source, current_source: base_source),
      merge3: request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    }

    requests.each do |operation, request|
      result = provider.public_send(operation, request)
      expect(Ast::Merge::ProviderContract.validate_result!(operation, result)).to eq(result)
      expect(result.fetch(:provider)).to include(provider_id: 'rust.bash', backend: :rust_tslp)
      expect(result.fetch(:verification)).to include(rust_host: true)
      expect(result.fetch(:ok)).to be(true), result.inspect
    end
  end

  it 'reports the ownership boundary for its portable subset' do
    expect(provider.capabilities.fetch(:ast_ownership)).to eq(:top_level_functions_assignments_and_literal_test_titles)
  end

  it 'dispatches an explicitly selected Rust Bash provider' do
    Bash::Merge.register_rust_host_provider!(replace: true)
    result = Ast::Merge.dispatch_provider(
      :merge2,
      request_base.merge(
        provider_id: 'rust.bash',
        incoming_source: ours_source,
        current_source: base_source
      )
    )

    expect(result.fetch(:provider)).to include(provider_id: 'rust.bash')
    expect(result.fetch(:verification)).to include(rust_host: true)
    expect(result.fetch(:ok)).to be(true), result.inspect
  end

  it 'preserves native output for independent function edits' do
    native = Bash::Merge::Provider.new.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    )
    rust = provider.merge3(
      request_base.merge(base_source: base_source, ours_source: ours_source, theirs_source: theirs_source)
    )

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native output for independent variable and function edits' do
    base = "VALUE=one\nleft() { echo one; }\n"
    ours = "VALUE=two\nleft() { echo one; }\n"
    theirs = "VALUE=one\nleft() { echo two; }\n"
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end

  it 'preserves native output for literal test-harness edits' do
    base = "test_expect_success 'works' 'echo one'\n"
    ours = "test_expect_success 'works' 'echo two'\n"
    theirs = "test_expect_success 'works' 'echo one'\n"
    request = request_base.merge(base_source: base, ours_source: ours, theirs_source: theirs)

    native = Bash::Merge::Provider.new.merge3(request)
    rust = provider.merge3(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
  end
end
