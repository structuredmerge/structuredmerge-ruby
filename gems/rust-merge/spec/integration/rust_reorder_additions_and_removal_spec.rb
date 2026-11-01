# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust compatible reorder merge with additions and removal' do
  it 'compares Ruby native and both Rust host backends against shared contracts' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_names = %w[
      rust_merge3_compatible_two_sided_reorders_additions_and_removal
      rust_merge3_two_sided_reorders_additions_removal_owned_gaps
    ]

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.two-sided-reorder-addition-removal')
    fixture_names.each do |fixture_name|
      fixture_path = File.expand_path(
        "../../../../../fixtures/polyglot/typed-core/#{fixture_name}.json",
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
      ruby_expected = fixture.fetch('ruby_native_expected')
      expect(native.fetch(:ok)).to eq(ruby_expected.fetch('outcome') == 'clean'),
                                   "#{fixture_name}: #{native.inspect}"
      expect(native.fetch(:output)).to eq(ruby_expected.fetch('output')), fixture_name if ruby_expected.key?('output')
      if ruby_expected.key?('diagnostic_category')
        expect(native.fetch(:diagnostics).first.fetch(:category).to_s)
          .to eq(ruby_expected.fetch('diagnostic_category')), fixture_name
      end
      if ruby_expected.key?('conflict_category')
        expect(native.fetch(:conflicts).first.fetch(:category).to_s)
          .to eq(ruby_expected.fetch('conflict_category')), fixture_name
      end

      %i[rust_tslp rust_syn].each do |backend|
        result = Rust::Merge::RustHostProvider.new.merge3(
          family: :rust,
          dialect: :rust,
          backend: backend,
          profile_id: :source_preserving,
          **request
        )
        expect(result.fetch(:ok)).to eq(fixture.dig('expected', 'outcome') == 'clean'),
                                     "#{fixture_name} #{backend}: #{result.inspect}"
        expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')),
                                         "#{fixture_name} #{backend}"
      end
    end
  end
end
