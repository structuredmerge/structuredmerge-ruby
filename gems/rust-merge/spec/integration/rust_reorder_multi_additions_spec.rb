# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust reorder merge with multiple interior additions' do
  it 'compares native output and both explicit Rust host backends' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_compatible_reorders_with_two_interior_additions.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(fixture.dig('ruby_native_expected', 'output'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.two-interior-additions')
    %i[rust_tslp rust_syn].each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
    end
  end
end
