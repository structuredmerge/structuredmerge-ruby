# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust documented enum owner merge' do
  it 'compares Ruby native and both Rust host backends against the shared contract' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture = JSON.parse(File.read(File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_enum_doc_attributes_with_independent_function_edit.json',
      __dir__
    )))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    ruby_expected = fixture.fetch('ruby_native_expected')
    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to eq(ruby_expected.fetch('outcome') == 'clean'), native.inspect
    expect(native.fetch(:output)).to eq(ruby_expected.fetch('output'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.enum-doc-attributes')
    %i[rust_tslp rust_syn].each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to eq(fixture.dig('expected', 'outcome') == 'clean'),
                                     "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
    end
  end
end
