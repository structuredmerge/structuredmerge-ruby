# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Go linkname comment ownership fixture' do
  it 'attaches the directive to the function in Ruby and Rust host analysis' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/go/slice-114-native/linkname-comment-ownership.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    expected = fixture.fetch('expected')
    native = Go::Merge::Provider.new.analyze(dialect: :go, source: fixture.fetch('source'))
    rust = Go::Merge::RustHostProvider.new.analyze(
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      source: fixture.fetch('source')
    )

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.dig(:analysis, :declarations)).to include(
      hash_including(signature: [:function, 'localName'], line_range: expected.fetch('function_line_range'))
    )
    expect(rust.dig(:analysis, :declarations)).to include(
      hash_including(path: expected.fetch('rust_function_path'), line_range: expected.fetch('function_line_range'))
    )
  end
end
