# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'Go documented owner deletion' do
  let(:fixture) do
    fixture_id = 'go_merge3_delete_documented_owner_with_independent_edit'
    JSON.parse(File.read(File.expand_path("../../../../../fixtures/polyglot/typed-core/#{fixture_id}.json", __dir__)))
  end
  let(:request) do
    input = fixture.fetch('input')
    { base_source: input.fetch('base'), ours_source: input.fetch('ours'), theirs_source: input.fetch('theirs') }
  end

  before { skip 'compiled Rust host unavailable' unless Go::Merge::RustHostProvider.available? }

  it 'fails closed in the native Ruby provider' do
    expected = fixture.fetch('ruby_native_expected')
    result = Go::Merge::Provider.new.merge3(request)

    expect(result.fetch(:ok)).to be(false), result.inspect
    expect(result[:output]).to be_nil
    expect(result.fetch(:diagnostics).first.fetch(:category).to_s).to eq(expected.fetch('diagnostic_category'))
  end

  it 'merges cleanly in the Rust host by deleting the Doc comment with its owner' do
    result = Go::Merge::RustHostProvider.new.merge3(request)

    expect(result.fetch(:ok)).to be(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('rust_host_expected', 'output'))
  end
end
