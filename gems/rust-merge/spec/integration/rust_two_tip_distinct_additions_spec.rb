# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust two-tip additions at distinct source gaps' do
  before { skip 'compiled typed core is unavailable' unless Rust::Merge::RustHostProvider.available? }

  it 'preserves both tips additions at their original source gaps' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions_distinct_source_gaps.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected = fixture.fetch('expected')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    native = Rust::Merge::Provider.new.merge3(request)
    rust = Rust::Merge::RustHostProvider.new.merge3(request.merge(
      family: :rust,
      dialect: :rust,
      backend: :rust_tslp,
      profile_id: :source_preserving
    ))

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(expected.fetch('output'))
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(expected.fetch('output'))
  end
end
