# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Go native comment ownership fixture' do
  before { skip 'compiled typed core is unavailable' unless Go::Merge::RustHostProvider.available? }

  it 'keeps a same-line comment with its declaration in Ruby and Rust host analysis' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/trailing-comment-ownership.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    source = fixture.fetch('source')
    expected_ranges = fixture.dig('expected', 'declaration_line_ranges')
    request = { family: :go, dialect: :go, backend: :rust_tslp, profile_id: :source_preserving, source: source }

    native = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expected_ranges.each do |line_range|
      expect(native.dig(:analysis, :declarations)).to include(hash_including(line_range: line_range))
      expect(rust.dig(:analysis, :declarations)).to include(hash_including(line_range: line_range))
    end
  end

  it 'keeps a grouped import declaration as one comment-owned range in both adapters' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/grouped-import-owner.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    source = fixture.fetch('source')
    expected_range = fixture.dig('expected', 'owner_line_range')
    request = { family: :go, dialect: :go, backend: :rust_tslp, profile_id: :source_preserving, source: source }

    native = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.dig(:analysis, :declarations)).to include(hash_including(line_range: expected_range))
    expect(rust.dig(:analysis, :declarations)).to include(hash_including(line_range: expected_range))
  end
end
