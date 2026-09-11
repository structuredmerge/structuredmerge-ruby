# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/git/rust_host_provider'
require 'fileutils'
require 'pathname'

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

  it 'writes a clean result through the Git merge-files protocol' do
    root = Pathname(__dir__).join('../../tmp/rust-host-provider-protocol')
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p(root)
    base_path = root.join('base.json')
    ours_path = root.join('ours.json')
    theirs_path = root.join('theirs.json')
    base_path.write("{\"shared\":true}\n")
    ours_path.write("{\"shared\":true,\"ours\":1}\n")
    theirs_path.write("{\"shared\":true,\"theirs\":2}\n")

    result = Ast::Merge::Git.merge_files(
      base_path: base_path,
      ours_path: ours_path,
      theirs_path: theirs_path,
      provider_id: 'rust.git.json',
      family: :json,
      dialect: :json,
      backend: :rust_tslp,
      profile_id: :source_preserving
    )

    expect(result.fetch(:git)).to include(exit_code: 0, output_written: true)
    expect(ours_path.read).to include('"theirs":2')
  ensure
    FileUtils.rm_rf(root) if root
  end

  it 'writes localized conflicts and returns the Git conflict exit status' do
    root = Pathname(__dir__).join('../../tmp/rust-host-provider-conflict')
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p(root)
    base_path = root.join('base.json')
    ours_path = root.join('ours.json')
    theirs_path = root.join('theirs.json')
    base_path.write("{\"enabled\":true}\n")
    ours_path.write("{\"enabled\":false}\n")
    theirs_path.write("{\"enabled\":\"yes\"}\n")

    result = Ast::Merge::Git.merge_files(
      base_path: base_path,
      ours_path: ours_path,
      theirs_path: theirs_path,
      provider_id: 'rust.git.json',
      family: :json,
      dialect: :json,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      conflict_policy: :write
    )

    expect(result.fetch(:git)).to include(exit_code: 1, output_written: true)
    expect(ours_path.read).to include('<<<<<<< ours', '>>>>>>> theirs')
  ensure
    FileUtils.rm_rf(root) if root
  end
end
