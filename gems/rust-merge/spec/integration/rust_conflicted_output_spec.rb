# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust conflict review output' do
  it 'compares review buffers for the shared conflict fixture' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)
    fixture = JSON.parse(File.read(File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_conflict.json',
      __dir__
    )))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    native = Rust::Merge::Provider.new.merge3(request)
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.conflict-preview')
    hosts = %i[rust_tslp rust_syn].to_h do |backend|
      [backend, Rust::Merge::RustHostProvider.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )]
    end
    expected = fixture.fetch('expected_conflicted_output')
    expect(native[:conflicted_output]).to eq(expected.fetch('ruby_native'))
    expect(hosts[:rust_tslp][:conflicted_output]).to eq(expected.fetch('rust_tslp'))
    expect(hosts[:rust_syn][:conflicted_output]).to eq(expected.fetch('rust_syn'))
  end
end
