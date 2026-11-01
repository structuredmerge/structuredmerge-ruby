# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSONC comment preservation across native and Rust providers' do
  it "keeps an existing member's trailing comment when another member is appended" do
    skip 'compiled Rust host unavailable' unless Json::Merge::RustHostProvider.available?

    fixture_path = File.expand_path('../../../../../../fixtures/polyglot/typed-core/jsonc_inline_comment_member_append.json', __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    incoming = fixture.dig('input', 'incoming')
    current = fixture.dig('input', 'current')
    expected = fixture.dig('expected', 'output')

    native = Json::Merge::Provider.new.merge2(
      incoming_source: incoming,
      current_source: current,
      dialect: :jsonc,
      backend: 'kreuzberg-language-pack'
    )
    rust = Json::Merge::RustHostProvider.new.merge2(
      incoming_source: incoming,
      current_source: current,
      dialect: :jsonc
    )

    expect(native).to include(ok: true)
    expect(rust).to include(ok: native.fetch(:ok))
    expect(native.fetch(:output)).to eq(expected)
    expect(rust.fetch(:output)).to eq(expected)
    expect(rust.fetch(:output)).to include('// keep inline')
  end
end
