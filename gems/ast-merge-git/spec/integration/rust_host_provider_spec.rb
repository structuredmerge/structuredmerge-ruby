# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/git/rust_host_provider'
require 'fileutils'
require 'pathname'

RSpec.describe Ast::Merge::Git::RustHostProvider do
  subject(:provider) { described_class.new }

  before(:context) do
    raise 'typed artifact core is unavailable' if ENV['BUNDLE_GEMFILE']&.end_with?('typed_core.gemfile') && !described_class.available?
  end
  before { skip 'typed Rust core is unavailable' unless described_class.available? }
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
        operations: [:merge3],
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
    expect(result.fetch(:verification)).to include(rust_core: true, base_participated: true, output_reparsed: true)
    expect(Gem.loaded_specs).not_to have_key('structuredmerge_host_prototype')
  end

  it 'keeps non-merge3 Git operations explicitly unsupported' do
    result = provider.analyze(request_base)

    expect(result).to include(ok: false)
    expect(result.fetch(:diagnostics)).to include(
      include(category: :unsupported_capability, blocking: true)
    )
  end

  it 'preserves the explicit JSON5 dialect through the Git provider' do
    result = provider.merge3(
      request_base.merge(
        dialect: :json5,
        base_source: "{shared: true}\n",
        ours_source: "{shared: true, ours: 1}\n",
        theirs_source: "{shared: true, theirs: 2}\n"
      )
    )

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('ours: 1', 'theirs: 2')
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
    expect(result.fetch(:verification)[:output_reparsed]).to be_nil
    expect(result.fetch(:render_report)).to include('artifact_kind' => 'unresolved-conflict-review')
    expect(result.fetch(:typed_result)[:conflicts].first[:canonical][:alternatives].length).to eq(3)
    expect(JSON.parse(JSON.generate(result))).to be_a(Hash)
  end

  it 'honors marker and label options and rejects unknown constraints' do
    sources = { base_source: '{"x":0}', ours_source: '{"x":1}', theirs_source: '{"x":2}' }
    result = provider.merge3(request_base.merge(sources, conflict_marker_size: '9', labels: { ours: 'local-é' }))
    expect(result.fetch(:conflicted_output)).to include('<<<<<<<<< local-é')
    [ { labels: { ours: "bad\nlabel" } }, { labels: { unknown: 'bad' } },
      { conflict_marker_size: -1 }, { conflict_marker_size: 1025 }, { unexpected: true } ].each do |options|
      rejected = provider.merge3(request_base.merge(sources, **options))
      expect(rejected[:ok]).to be(false)
      expect(rejected[:output]).to be_nil
      expect(rejected[:conflicted_output]).to be_nil
    end
  end

  it 'keeps ours untouched for leave-ours, unrenderable conflicts, and invalid input' do
    require 'tmpdir'
    scratch = Pathname(__dir__).join('../../tmp')
    FileUtils.mkdir_p(scratch)
    Dir.mktmpdir('typed-git-protocol-', scratch) do |directory|
      paths = %w[base ours theirs].map { |role| Pathname(directory).join("#{role}.json") }
      [
        ['{"x":0}', '{"x":1}', '{"x":2}', :leave_ours, 1],
        ['{"x":0}', '{}', '{"x":2}', :write, 2],
        ['{"x":0}', '{}', '{"x":2}', :leave_ours, 1],
        ['{}', '{', '{}', :write, 2]
      ].each do |base, ours, theirs, policy, exit_code|
        paths.zip([base, ours, theirs]).each { |path, text| path.binwrite(text) }
        result = Ast::Merge::Git.merge_files(**request_base, provider_id: 'rust.git.json',
          base_path: paths[0], ours_path: paths[1], theirs_path: paths[2], conflict_policy: policy)
        expect(result.fetch(:git)).to include(exit_code: exit_code, output_written: false)
        expect(paths[1].binread).to eq(ours)
      end
    end
  end

  it 'registers the explicit Git provider and writes through the command protocol' do
    require 'tmpdir'
    require 'stringio'
    scratch = Pathname(__dir__).join('../../tmp')
    FileUtils.mkdir_p(scratch)
    Dir.mktmpdir('typed-git-command-', scratch) do |directory|
      paths = %w[base ours theirs].map { |role| Pathname(directory).join("#{role}.json") }
      paths.zip(['{"x":0}', '{"x":1}', '{"x":2}']).each { |path, text| path.binwrite(text) }
      expect(Ast::Merge::Git).to receive(:register_rust_host_provider!).with(replace: true).and_call_original
      status = Ast::Merge::Git.run(paths.map(&:to_s) + ['file.json', '9', 'ancestor', 'local', 'remote'],
        env: { 'AST_MERGE_PROVIDER' => 'rust.git.json', 'AST_MERGE_DIALECT' => 'json' }, stderr: StringIO.new)
      expect(status).to eq(1)
      expect(paths[1].binread).to include('<<<<<<<<< local', '||||||||| ancestor', '>>>>>>>>> remote')
    end
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
