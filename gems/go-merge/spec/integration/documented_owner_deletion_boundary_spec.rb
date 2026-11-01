# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'Go documented owner deletion boundary' do
  it 'fails closed in native and Rust providers per the shared fixture' do
    skip 'compiled Rust host unavailable' unless Go::Merge::RustHostProvider.available?

    path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/go_merge3_delete_documented_owner_with_independent_edit.json', __dir__
    )
    fixture = JSON.parse(File.read(path))
    input = fixture.fetch('input')
    request = { base_source: input.fetch('base'), ours_source: input.fetch('ours'),
                theirs_source: input.fetch('theirs') }

    {
      Go::Merge::Provider.new => fixture.fetch('ruby_native_expected'),
      Go::Merge::RustHostProvider.new => fixture.fetch('rust_host_expected')
    }.each do |provider, expected|
      result = provider.merge3(request)
      expect(result.fetch(:ok)).to be(false), result.inspect
      expect(result[:output]).to be_nil
      diagnostic = result.fetch(:diagnostics).first
      expect(diagnostic.fetch(:category).to_s).to eq(expected.fetch('diagnostic_category'))
      expect(diagnostic.fetch(:code)).to eq(expected['diagnostic_code']) if expected['diagnostic_code']
    end
  end
end
