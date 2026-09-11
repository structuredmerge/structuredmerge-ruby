# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/git/rust_host_provider'

RSpec.describe Ast::Merge::Git::RustHostProvider do
  subject(:provider) { described_class.new }

  before { skip 'compiled Rust host is unavailable' unless described_class.available? }
  before { Ast::Merge::Git.register_rust_host_provider!(replace: true) }

  let(:request_base) do
    {
      family: :json,
      dialect: :json,
      backend: :rust_tslp,
      profile_id: :source_preserving
    }
  end

  it 'advertises the explicit Git merge3 provider contract' do
    registration = Ast::Merge::ProviderContract.validate_provider!(provider)

    expect(registration).to include(
      provider_id: 'rust.git.json',
      family: :json,
      capabilities: hash_including(
        operations: %i[analyze diff2 merge2 merge3],
        backends: [:rust_tslp]
      )
    )
  end

  it 'delegates clean JSON Git merge3 through the compiled host' do
    result = provider.merge3(
      request_base.merge(
        base_source: "{\"shared\":true}\n",
        ours_source: "{\"shared\":true,\"ours\":1}\n",
        theirs_source: "{\"shared\":true,\"theirs\":2}\n"
      )
    )

    expect(result).to include(ok: true, provider: include(provider_id: 'rust.git.json'))
    expect(result.fetch(:output)).to include('"ours":1', '"theirs":2')
    expect(result.fetch(:verification)).to include(rust_host: true, base_participated: true)
  end

  it 'preserves localized conflict output for the Git adapter' do
    result = provider.merge3(
      request_base.merge(
        base_source: "{\"enabled\":true}\n",
        ours_source: "{\"enabled\":false}\n",
        theirs_source: "{\"enabled\":\"yes\"}\n"
      )
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).not_to be_empty
    expect(result.fetch(:conflicted_output)).to include('<<<<<<< ours', '>>>>>>> theirs')
  end

  it 'routes the explicit provider through the Ruby Git adapter envelope' do
    result = Ast::Merge::Git.merge3(
      request_base.merge(
        provider_id: 'rust.git.json',
        base_source: "{\"shared\":true}\n",
        ours_source: "{\"shared\":true,\"ours\":1}\n",
        theirs_source: "{\"shared\":true,\"theirs\":2}\n"
      )
    )

    expect(result).to include(ok: true, merged_source: include('"ours":1'))
    expect(result).not_to have_key(:git)
  end
end
