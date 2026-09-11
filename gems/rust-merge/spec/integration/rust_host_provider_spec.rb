# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rust::Merge::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }

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
end
