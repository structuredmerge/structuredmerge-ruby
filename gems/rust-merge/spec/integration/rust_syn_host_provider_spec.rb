# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rust::Merge::RustHostProvider do
  it 'runs Rust typed analysis through the native syn parser' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    descriptor = StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby')
    expect(StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby').id).to eq(descriptor.id)

    provider = described_class.new
    result = provider.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: "/// Native documentation\nfn café() {}\n"
    )

    expect(result.fetch(:ok)).to be(true), result.inspect
    expect(result.fetch(:provider)).to include(backend: :rust_syn)
    declaration = result.dig(:analysis, :declarations).fetch(0)
    expect(declaration.fetch(:path)).to eq('/function:café')
    expect(declaration.fetch(:line_range)).to eq([1, 2])

    base = "fn left() -> i32 { 1 }\n\nfn right() -> i32 { 1 }\n"
    ours = base.sub('{ 1 }', '{ 2 }')
    theirs = base.sub('fn right() -> i32 { 1 }', 'fn right() -> i32 { 2 }')
    diff = provider.diff2(family: :rust, dialect: :rust, backend: :rust_syn,
                          profile_id: :source_preserving, before_source: base, after_source: ours)
    merge = provider.merge3(family: :rust, dialect: :rust, backend: :rust_syn,
                            profile_id: :source_preserving, base_source: base,
                            ours_source: ours, theirs_source: theirs)
    directional = provider.merge2(family: :rust, dialect: :rust, backend: :rust_syn,
                                  profile_id: :source_preserving, incoming_source: ours,
                                  current_source: base)

    expect(diff.fetch(:ok)).to be(true), diff.inspect
    expect(diff.fetch(:changes).map { |change| change.fetch(:path) }).to include('/function:left')
    expect(merge.fetch(:ok)).to be(true), merge.inspect
    expect(merge.fetch(:output)).to include('fn left() -> i32 { 2 }', 'fn right() -> i32 { 2 }')
    expect(directional.fetch(:ok)).to be(true), directional.inspect
  end

  it 'matches the shared commented owner-addition fixture through rust_syn' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.fixture')
    path = File.expand_path('../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions.json', __dir__)
    fixture = JSON.parse(File.read(path))
    input = fixture.fetch('input')
    result = described_class.new.merge3(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )

    expect(result.fetch(:ok)).to eq(fixture.dig('expected', 'ok')), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
  end

  it 'matches shared classic Rust comment-owner fixture through rust_syn' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    path = File.expand_path('../../../../../fixtures/polyglot/typed-core/rust_merge2_comment_owner.json', __dir__)
    fixture = JSON.parse(File.read(path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.classic')
    result = described_class.new.merge2(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      incoming_source: input.fetch('template'),
      current_source: input.fetch('destination')
    )

    expect(result.fetch(:ok)).to eq(fixture.dig('expected', 'ok')), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
  end

  it 'matches shared classic Rust block-doc fixture through rust_syn' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge2_block_doc_comment_owner.json',
      __dir__
    )
    fixture = JSON.parse(File.read(path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.classic.block-doc')
    result = described_class.new.merge2(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      incoming_source: input.fetch('template'),
      current_source: input.fetch('destination')
    )

    expect(result.fetch(:ok)).to eq(fixture.dig('expected', 'ok')), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
  end

  it 'matches the shared Rust parser and owner-profile failure boundary' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixtures_path = File.expand_path('../../../../../fixtures', __dir__)
    fixture_path = File.join(fixtures_path, 'polyglot/typed-core/rust_parser_owner_profile_failure_boundary.json')
    fixture = JSON.parse(File.read(fixture_path))
    native = Rust::Merge::Provider.new
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.failure-boundary')

    fixture.fetch('cases').each do |case_data|
      source = case_data.fetch('source')
      expected = case_data.fetch('expected')
      native_result = native.analyze(source: source)
      rust_result = described_class.new.analyze(
        family: :rust,
        dialect: :rust,
        backend: :rust_syn,
        profile_id: :source_preserving,
        source: source
      )

      expect([native_result, rust_result].map { |result| result.fetch(:ok) })
        .to all(eq(expected.fetch('ok')))
      native_categories = native_result.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category).to_s }
      rust_categories = rust_result.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category).to_s }
      expect(native_categories).to include(expected.fetch('ruby_native_category'))
      expect(rust_categories).to include(expected.fetch('rust_syn_host_category'))

      input = case_data.fetch('merge3')
      native_merge = native.merge3(
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      )
      rust_merge = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: :rust_syn,
        profile_id: :source_preserving,
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      )
      expect([native_merge, rust_merge].map { |result| result.fetch(:ok) }).to all(eq(false))
      native_merge_categories = native_merge.fetch(:diagnostics).map do |diagnostic|
        diagnostic.fetch(:category).to_s
      end
      rust_merge_categories = rust_merge.fetch(:diagnostics).map do |diagnostic|
        diagnostic.fetch(:category).to_s
      end
      expect(native_merge_categories).to include(expected.fetch('ruby_native_category'))
      expect(rust_merge_categories).to include(expected.fetch('rust_syn_host_category'))
    end
  end

  it 'fails closed on syntax errors and unsupported native Rust items' do
    unless StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      skip 'compiled native syn registration is unavailable'
    end

    provider = described_class.new
    request = {
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving
    }
    malformed = provider.analyze(request.merge(source: 'fn broken('))
    unsupported = provider.analyze(request.merge(source: "unsafe extern \"C\" { fn native_symbol(); }\n"))

    expect(malformed.fetch(:ok)).to be(false)
    malformed_messages = malformed.fetch(:diagnostics).map { |item| item.fetch(:message) }.join
    expect(malformed_messages).to include('native parser rejected input')
    expect(unsupported.fetch(:ok)).to be(false)
    unsupported_messages = unsupported.fetch(:diagnostics).map { |item| item.fetch(:message) }.join
    expect(unsupported_messages).to include('unsupported top-level Rust node')
  end
end
