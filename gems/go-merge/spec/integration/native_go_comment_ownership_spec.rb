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

    grouped_signature = expected.fetch('grouped_ruby_signature')
    grouped_signature[0] = grouped_signature[0].to_sym
    grouped_request = request.merge(source: fixture.fetch('grouped_source'))
    grouped_native = Go::Merge::Provider.new.analyze(grouped_request)
    grouped_rust = Go::Merge::RustHostProvider.new.analyze(grouped_request)
    expect(grouped_native.fetch(:ok)).to be(true), grouped_native.inspect
    expect(grouped_rust.fetch(:ok)).to be(true), grouped_rust.inspect
    expect(grouped_native.dig(:analysis, :declarations)).to include(
      hash_including(signature: grouped_signature,
                     line_range: expected.fetch('grouped_line_range'))
    )
    expect(grouped_rust.dig(:analysis, :declarations)).to include(
      hash_including(path: expected.fetch('grouped_rust_path'),
                     line_range: expected.fetch('grouped_line_range'))
    )
  end

  it 'records native go/parser BOM acceptance separately from Tree-sitter provider boundaries' do
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/bom-source-ownership.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    fixture.fetch('cases').each do |test_case|
      expected = test_case.fetch('expected')
      native_request = { source: test_case.fetch('source'), dialect: :go }
      rust_request = {
        family: :go,
        dialect: :go,
        backend: :rust_tslp,
        profile_id: :source_preserving,
        source: test_case.fetch('source')
      }
      ruby = Go::Merge::Provider.new.analyze(native_request)
      rust = Go::Merge::RustHostProvider.new.analyze(rust_request)

      expect(ruby.fetch(:ok)).to be(false), "#{test_case.fetch('name')}: #{ruby.inspect}"
      expect(ruby.dig(:diagnostics, 0, :category).to_s).to eq(expected.fetch('ruby_treesitter_category'))
      expect(rust.fetch(:ok)).to be(false), "#{test_case.fetch('name')}: #{rust.inspect}"
      expect(rust.dig(:diagnostics, 0, :category).to_s).to eq(expected.fetch('rust_treesitter_category'))
    end
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

  it 'fails closed when only one merge3 input has partial parser recovery' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/go/slice-114-native/merge3-one-sided-parser-failure.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    fixture.fetch('cases').each do |test_case|
      request = {
        family: :go,
        dialect: :go,
        backend: :rust_tslp,
        profile_id: :source_preserving,
        base_source: test_case.fetch('base_source'),
        ours_source: test_case.fetch('ours_source'),
        theirs_source: test_case.fetch('theirs_source')
      }
      native = Go::Merge::Provider.new.merge3(request)
      rust = Go::Merge::RustHostProvider.new.merge3(request)
      role = test_case.fetch('failed_role').to_sym

      expect(native.fetch(:ok)).to be(false), "#{test_case.fetch('name')}: #{native.inspect}"
      expect(native.fetch(:diagnostics).first.fetch(:category)).to eq(:parse_error)
      expect(native.fetch(:diagnostics).first.fetch(:message)).to start_with("#{role} parse error")
      expect(native[:output]).to be_nil
      expect(native[:conflicted_output]).to be_nil

      expect(rust.fetch(:ok)).to be(false), "#{test_case.fetch('name')}: #{rust.inspect}"
      expect(rust.fetch(:diagnostics).first.fetch(:category)).to eq(:parse_error)
      source_refs = rust.dig(:diagnostics, 0, :typed_record, :canonical, :source_refs)
      expect(source_refs).to include(hash_including(role: role))
      expect(rust[:output]).to be_nil
      expect(rust[:conflicted_output]).to be_nil
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


RSpec.describe 'Go comment directive ownership fixture' do
  it 'keeps a go:embed directive attached to its variable in Ruby and Rust host analysis' do
    skip 'compiled typed core is unavailable' unless Go::Merge::RustHostProvider.available?
    fixture_path = File.expand_path('../../../../../fixtures/go/slice-114-native/comment-directive-ownership.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    expected_range = fixture.dig('expected', 'declaration_line_range')
    request = {
      family: :go,
      dialect: :go,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      source: fixture.fetch('source')
    }

    ruby = Go::Merge::Provider.new.analyze(request)
    rust = Go::Merge::RustHostProvider.new.analyze(request)

    expect(ruby.fetch(:ok)).to be(true), ruby.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(ruby.dig(:analysis, :declarations)).to include(hash_including(line_range: expected_range))
    expect(rust.dig(:analysis, :declarations)).to include(hash_including(line_range: expected_range))
  end
end
