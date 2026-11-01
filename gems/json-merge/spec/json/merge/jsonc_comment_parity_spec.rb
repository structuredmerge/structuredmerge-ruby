# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSONC comment preservation across native and Rust providers' do
  it "keeps an existing member's trailing comment when another member is appended" do
    skip 'compiled Rust host unavailable' unless Json::Merge::RustHostProvider.available?

    fixture_dir = File.expand_path('../../fixtures/reproducible/01_nested_object_comment_block_template_preference', __dir__)
    incoming = File.read(File.join(fixture_dir, 'template.jsonc'))
    current = File.read(File.join(fixture_dir, 'destination.jsonc'))

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
    expect(rust.fetch(:output)).to eq(native.fetch(:output))
    expect(rust.fetch(:output)).to include('// Keep docs', '// More keep docs', '// keep inline')
  end
end
