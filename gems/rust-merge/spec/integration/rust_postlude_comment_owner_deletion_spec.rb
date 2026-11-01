# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust trailing file comment after owner deletion' do
  it 'compares native and Rust host ownership of a trailing comment' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture = JSON.parse(File.read(File.expand_path(
                                     '../../../../../fixtures/polyglot/typed-core/rust_merge3_delete_owner_with_trailing_postlude_comment_and_independent_edit.json',
                                     __dir__
                                   )))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    native_expected = fixture.fetch('ruby_native_expected')
    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to eq(native_expected.fetch('outcome') == 'clean'), native.inspect
    if native_expected.fetch('outcome') == 'clean'
      expect(native.fetch(:output)).to eq(native_expected.fetch('output'))
    else
      expect(native.fetch(:diagnostics).first.fetch(:category).to_s)
        .to eq(native_expected.fetch('diagnostic_category'))
      expect(native.fetch(:conflicts).first.fetch(:category).to_s)
        .to eq(native_expected.fetch('conflict_category'))
    end

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.postlude-comment')
    %i[rust_tslp rust_syn].each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expected = fixture.fetch('rust_host_expected').fetch(backend.to_s)
      expect(result.fetch(:ok)).to eq(expected.fetch('outcome') == 'clean'), result.inspect
      if expected.fetch('outcome') == 'clean'
        expect(result.fetch(:output)).to eq(expected.fetch('output'))
        expect(result.fetch(:conflicts)).to be_empty
      else
        expect(result.fetch(:output, nil)).to be_nil
        expect(result.fetch(:diagnostics).first.fetch(:category).to_s)
          .to eq(expected.fetch('diagnostic_category'))
        expect(result.fetch(:diagnostics).first.fetch(:code))
          .to eq(expected.fetch('diagnostic_code'))
        expect(result.fetch(:conflicts).first.dig(:typed_record, :canonical, :category).to_s)
          .to eq(expected.fetch('conflict_category'))
      end
    end
  end
end
