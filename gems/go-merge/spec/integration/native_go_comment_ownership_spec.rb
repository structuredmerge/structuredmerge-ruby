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

  it 'rejects malformed Go syntax with matching parser-error categories' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/malformed-source.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    request = {
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      source: fixture.fetch('source')
    }

    native = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(native.fetch(:ok)).to be(false), native.inspect
    expect(rust.fetch(:ok)).to be(false), rust.inspect
    expect(native.fetch(:diagnostics).first.fetch(:category)).to eq(:parse_error)
    expect(rust.fetch(:diagnostics).first.fetch(:category)).to eq(:parse_error)
  end

  it 'projects a generic type alias as one stable type owner in both providers' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/generic-type-alias-owner.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    expected = fixture.fetch('expected')
    request = {
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      source: fixture.fetch('source')
    }

    native = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.dig(:analysis, :declarations)).to include(
      hash_including(signature: [:type, 'Set'], line_range: expected.fetch('type_line_range'))
    )
    expect(rust.dig(:analysis, :declarations)).to include(
      hash_including(path: '/type:Set', line_range: expected.fetch('type_line_range'))
    )
    expect(native.dig(:analysis, :declarations)).to include(
      hash_including(signature: [:function, 'Contains'], line_range: expected.fetch('function_line_range'))
    )
    expect(rust.dig(:analysis, :declarations)).to include(
      hash_including(path: '/function:Contains', line_range: expected.fetch('function_line_range'))
    )
  end

  it 'fails closed on partial parser recovery in both Ruby and Rust providers' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/parser-recovery-fail-closed.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    fixture.fetch('cases').each do |test_case|
      request = {
        family: :go,
        dialect: :go,
        backend: :rust_tslp,
        profile_id: :source_preserving,
        source: test_case.fetch('source')
      }
      native = Go::Merge::Provider.new.analyze(request)
      rust = Go::Merge::RustHostProvider.new.analyze(request)

      expect(native.fetch(:ok)).to be(false), "#{test_case.fetch('name')}: #{native.inspect}"
      expect(rust.fetch(:ok)).to be(false), "#{test_case.fetch('name')}: #{rust.inspect}"
      expect(native.fetch(:diagnostics).first.fetch(:category)).to eq(:parse_error)
      expect(rust.fetch(:diagnostics).first.fetch(:category)).to eq(:parse_error)
    end
  end

  it 'compares duplicate-owner failure categories across Ruby and Rust providers' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/duplicate-owner-identity.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    request = {
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      source: fixture.fetch('source')
    }

    native = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(native.fetch(:ok)).to be(false), native.inspect
    expect(rust.fetch(:ok)).to be(false), rust.inspect
    native_category = native.fetch(:diagnostics).first.fetch(:category)
    rust_category = rust.fetch(:diagnostics).first.fetch(:category)
    expect(rust_category).to eq(native_category), rust.inspect
  end

  it 'keeps a grouped import declaration as one comment-owned range in both adapters' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/grouped-import-owner.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    source = fixture.fetch('source')
    expected = fixture.fetch('expected')
    import_signature = expected.fetch('import_signature')
    import_signature[0] = import_signature[0].to_sym
    expected_range = expected.fetch('owner_line_range')
    request = { family: :go, dialect: :go, backend: :rust_tslp, profile_id: :source_preserving, source: source }

    native = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.dig(:analysis, :declarations)).to include(
      hash_including(signature: import_signature, line_range: expected_range)
    )
    expect(rust.dig(:analysis, :declarations)).to include(
      hash_including(path: expected.fetch('rust_import_path'), line_range: expected_range)
    )

    reordered_source = fixture.fetch('reordered_source')
    reordered_request = request.merge(source: reordered_source)
    reordered_native = Go::Merge::Provider.new.analyze(reordered_request)
    reordered_rust = Go::Merge::RustHostProvider.new.analyze(reordered_request)
    expect(reordered_native.dig(:analysis, :declarations)).to include(
      hash_including(signature: import_signature)
    )
    expect(reordered_rust.dig(:analysis, :declarations)).to include(
      hash_including(path: expected.fetch('rust_import_path'))
    )
  end
end
