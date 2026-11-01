# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rust two-tip additions at distinct source gaps' do
  before { skip 'compiled typed core is unavailable' unless Rust::Merge::RustHostProvider.available? }

  it "preserves both tips' additions at their original source gaps" do
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

  it "combines both tips' additions and comments in the same source gap" do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions_same_internal_gap.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected_output = fixture.dig('expected', 'output')
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
    expect(native.fetch(:output)).to eq(expected_output)
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(rust.fetch(:output)).to eq(expected_output)

    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.same-gap')
      rust_syn = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                            family: :rust,
                                                            dialect: :rust,
                                                            backend: :rust_syn,
                                                            profile_id: :source_preserving
                                                          ))
      expect(rust_syn.fetch(:ok)).to be(true), rust_syn.inspect
      expect(rust_syn.fetch(:output)).to eq(expected_output)
    end
  end

  it 'preserves additions in the preamble and postlude gaps' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions_file_edges.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected_output = fixture.dig('expected', 'output')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(expected_output)

    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.file-edge-additions')
      backends << :rust_syn
    end
    backends.each do |backend|
      rust = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                        family: :rust,
                                                        dialect: :rust,
                                                        backend: backend,
                                                        profile_id: :source_preserving
                                                      ))
      expect(rust.fetch(:ok)).to be(true), "#{backend}: #{rust.inspect}"
      expect(rust.fetch(:output)).to eq(expected_output)
    end
  end

  it "composes both tips' additions in the same preamble gap" do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions_same_preamble_gap.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected_output = fixture.dig('expected', 'output')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(expected_output)

    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.same-preamble-additions')
      backends << :rust_syn
    end
    backends.each do |backend|
      rust = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                        family: :rust,
                                                        dialect: :rust,
                                                        backend: backend,
                                                        profile_id: :source_preserving
                                                      ))
      expect(rust.fetch(:ok)).to be(true), "#{backend}: #{rust.inspect}"
      expect(rust.fetch(:output)).to eq(expected_output)
    end
  end

  it 'keeps crate-level Rust docs with a new preamble owner' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_addition_with_crate_docs.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected_output = fixture.dig('expected', 'output')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(expected_output)

    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.crate-doc-preamble')
      backends << :rust_syn
    end
    backends.each do |backend|
      rust = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                        family: :rust,
                                                        dialect: :rust,
                                                        backend: backend,
                                                        profile_id: :source_preserving
                                                      ))
      expect(rust.fetch(:ok)).to be(true), "#{backend}: #{rust.inspect}"
      expect(rust.fetch(:output)).to eq(expected_output)
    end
  end

  it 'composes divergent and edited Rust crate docs through Rust providers' do
    fixture_names = [
      'rust_syn_crate_doc_additions.json',
      'rust_syn_crate_doc_edit_with_independent_addition.json'
    ]
    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.crate-doc-additions')
      backends << :rust_syn
    end

    fixture_names.each do |fixture_name|
      fixture_path = File.expand_path("../../../../../fixtures/polyglot/typed-core/#{fixture_name}", __dir__)
      fixture = JSON.parse(File.read(fixture_path))
      input = fixture.fetch('input')
      request = {
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      }
      expected = fixture.fetch('expected')

      native = Rust::Merge::Provider.new.merge3(request)
      expect(native.fetch(:ok)).to be(false), "#{fixture_name}: #{native.inspect}"
      expect(native.fetch(:diagnostics).map { |diagnostic| diagnostic[:category] }).to include(
        fixture.dig('ruby_native_expected', 'diagnostic_category').to_sym
      )

      backends.each do |backend|
        result = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                            family: :rust,
                                                            dialect: :rust,
                                                            backend: backend,
                                                            profile_id: :source_preserving
                                                          ))
        expect(result.fetch(:ok)).to be(true), "#{backend} #{fixture_name}: #{result.inspect}"
        expect(result.fetch(:output)).to eq(expected.fetch('output')), "#{backend} #{fixture_name}"
      end
    end
  end

  it 'reports conflicting edits to the same Rust crate-doc region' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_syn_divergent_crate_doc_edits.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to be(false)
    expect(native.fetch(:diagnostics).map { |diagnostic| diagnostic[:category] }).to include(:merge_conflict)

    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.divergent-crate-docs')
      backends << :rust_syn
    end
    backends.each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                          family: :rust,
                                                          dialect: :rust,
                                                          backend: backend,
                                                          profile_id: :source_preserving
                                                        ))
      expect(result.fetch(:ok)).to be(false), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to be_nil
      expect(result.fetch(:diagnostics).map { |diagnostic| diagnostic[:category] }).to include(:merge_conflict)
    end
  end

  it 'composes documented file-edge additions with opposite-edge removals' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_edge_additions_with_owner_removals.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.edge-addition-owner-removal')
      backends << :rust_syn
    end

    fixture.fetch('cases').each do |case_data|
      input = case_data.fetch('input')
      request = {
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      }
      expected = case_data.dig('expected', 'output')
      native = Rust::Merge::Provider.new.merge3(request)
      expect(native.fetch(:ok)).to be(true), "#{case_data.fetch('name')}: #{native.inspect}"
      expect(native.fetch(:output)).to eq(expected), case_data.fetch('name')

      backends.each do |backend|
        result = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                            family: :rust,
                                                            dialect: :rust,
                                                            backend: backend,
                                                            profile_id: :source_preserving
                                                          ))
        expect(result.fetch(:ok)).to be(true), "#{backend} #{case_data.fetch('name')}: #{result.inspect}"
        expect(result.fetch(:output)).to eq(expected), "#{backend} #{case_data.fetch('name')}"
      end
    end
  end

  it 'preserves a one-sided owner reorder beside a documented edge addition' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_edge_addition_with_reorder.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }

    native = Rust::Merge::Provider.new.merge3(request)
    expect(native.fetch(:ok)).to be(true)
    expect(native.fetch(:output)).to eq(fixture.dig('ruby_native_expected', 'output'))

    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.edge-addition-reorder')
      backends << :rust_syn
    end
    backends.each do |backend|
      result = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                          family: :rust,
                                                          dialect: :rust,
                                                          backend: backend,
                                                          profile_id: :source_preserving
                                                        ))
      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    end
  end

  it 'composes two-tip additions from empty and comment-only bases' do
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_two_tip_additions_empty_base.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    backends = [:rust_tslp]
    if StructuredmergeCore.respond_to?(:register_rust_syn_parser)
      StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.empty-base-additions')
      backends << :rust_syn
    end

    fixture.fetch('cases').each do |case_data|
      input = case_data.fetch('input')
      expected_output = case_data.dig('expected', 'output')
      request = {
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      }
      native = Rust::Merge::Provider.new.merge3(request)
      expect(native.fetch(:ok)).to be(true), "#{case_data.fetch('name')}: #{native.inspect}"
      expect(native.fetch(:output)).to eq(expected_output), case_data.fetch('name')

      backends.each do |backend|
        rust = Rust::Merge::RustHostProvider.new.merge3(request.merge(
                                                          family: :rust,
                                                          dialect: :rust,
                                                          backend: backend,
                                                          profile_id: :source_preserving
                                                        ))
        expect(rust.fetch(:ok)).to be(true), "#{backend} #{case_data.fetch('name')}: #{rust.inspect}"
        expect(rust.fetch(:output)).to eq(expected_output), "#{backend} #{case_data.fetch('name')}"
      end
    end
  end
end
