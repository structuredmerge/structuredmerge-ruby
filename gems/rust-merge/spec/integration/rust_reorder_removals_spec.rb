# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust reorder merge with independent removals' do
  it 'compares Ruby native and both explicit Rust host backends' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_compatible_reorder_with_two_removals.json',
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
    native_expected = fixture.fetch('ruby_native_expected')
    expect(native.fetch(:ok)).to eq(native_expected.fetch('outcome') == 'clean'), native.inspect
    if native_expected.fetch('outcome') == 'conflict'
      expect(native.dig(:conflicts, 0, :category).to_s).to eq(native_expected.fetch('conflict_category'))
      expect(native.dig(:diagnostics, 0, :category).to_s).to eq(native_expected.fetch('diagnostic_category'))
    else
      expect(native.fetch(:output)).to eq(native_expected.fetch('output'))
    end

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.reorder-with-removals')
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
