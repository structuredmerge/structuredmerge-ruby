# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust owner membership change with an independent edit' do
  it 'compares Ruby native and both Rust host backends against the shared contract' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture = JSON.parse(File.read(File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_owner_membership_change_with_independent_edit.json',
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
    if ruby_expected.key?('output')
      expect(native.fetch(:output)).to eq(ruby_expected.fetch('output'))
    end
    if ruby_expected.key?('diagnostic_category')
      expect(native.fetch(:diagnostics).first.fetch(:category).to_s)
        .to eq(ruby_expected.fetch('diagnostic_category'))
    end
    if ruby_expected.key?('conflict_category')
      expect(native.fetch(:conflicts).first.fetch(:category).to_s)
        .to eq(ruby_expected.fetch('conflict_category'))
    end

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.membership-edit')
    %i[rust_tslp rust_syn].each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      host_expected = fixture.fetch('rust_host_expected').fetch(backend.to_s)
      expect(result.fetch(:ok)).to eq(host_expected.fetch('outcome') == 'clean'),
                                     "#{backend}: #{result.inspect}"
      if host_expected.key?('output')
        expect(result.fetch(:output)).to eq(host_expected.fetch('output')), backend.to_s
      end
      if host_expected.key?('diagnostic_category')
        expect(result.fetch(:diagnostics).first.fetch(:category).to_s)
          .to eq(host_expected.fetch('diagnostic_category')), backend.to_s
      end
      if host_expected.key?('diagnostic_code')
        expect(result.fetch(:diagnostics).first.fetch(:code))
          .to eq(host_expected.fetch('diagnostic_code')), backend.to_s
      end
      if host_expected.key?('conflict_category')
        expect(result.fetch(:conflicts).first.dig(:typed_record, :canonical, :category).to_s)
          .to eq(host_expected.fetch('conflict_category')), backend.to_s
      end
    end
  end
end
