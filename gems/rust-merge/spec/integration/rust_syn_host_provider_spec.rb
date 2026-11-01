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

  it 'matches the shared Rust block-doc two-tip addition fixture' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_block_doc_two_tip_additions.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.block-doc-merge3')
    native = Rust::Merge::Provider.new.merge3(
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )
    rust = described_class.new.merge3(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )

    [native, rust].each do |result|
      expect(result.fetch(:ok)).to eq(fixture.dig('expected', 'ok')), result.inspect
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    end
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

  it 'compares directional comment and gap ownership through native and rust_syn providers' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge2_directional_comment_gap_ownership.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      incoming_source: input.fetch('incoming'),
      current_source: input.fetch('current')
    }

    native = Rust::Merge::Provider.new.merge2(request)
    expect(native.fetch(:ok)).to eq(fixture.dig('ruby_native_expected', 'ok')), native.inspect
    expect(native.fetch(:output)).to eq(fixture.dig('ruby_native_expected', 'output'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.directional-comment-gap')
    %i[rust_tslp rust_syn].each do |backend|
      rust = described_class.new.merge2(request.merge(
                                          family: :rust,
                                          dialect: :rust,
                                          backend: backend,
                                          profile_id: :source_preserving
                                        ))

      expect(rust.fetch(:ok)).to eq(fixture.dig('expected', 'ok')), "#{backend}: #{rust.inspect}"
      expect(rust.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
      expect(rust.fetch(:verification)).to include(
        directional_roles_preserved: true,
        output_reparsed: true
      )
    end
  end

  it 'merges named macro definitions as whole owners through rust_syn' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path('../../../../../fixtures/polyglot/typed-core/rust_macro_definition_merge3.json',
                                    __dir__)
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    native = Rust::Merge::Provider.new.merge3(request)
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.macro-owner')
    rust = described_class.new.merge3(request.merge(
                                        family: :rust,
                                        dialect: :rust,
                                        backend: :rust_syn,
                                        profile_id: :source_preserving
                                      ))

    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(rust.fetch(:ok)).to be(true), rust.inspect
    expect(native.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    expect(rust.fetch(:output)).to eq(fixture.dig('expected', 'output'))
  end

  it 'distinguishes negative trait and inherent impl owners using native syn facts' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_impl_polarity_inherent_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.impl-forms')
    provider = described_class.new
    result = provider.merge3(request.merge(
                               family: :rust,
                               dialect: :rust,
                               backend: :rust_syn,
                               profile_id: :source_preserving
                             ))
    analysis = provider.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: input.fetch('base')
    )

    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    expect(analysis.fetch(:ok)).to eq(true), analysis.inspect
    expect(analysis.dig(:analysis, :declarations).map { |owner| owner.fetch(:path) })
      .to include(*fixture.dig('expected', 'impl_owner_paths'))
  end

  it 'merges trait impl owners using native syn identity' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_impl_owner_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.impl-owner')
    result = described_class.new.merge3(request.merge(
                                          family: :rust,
                                          dialect: :rust,
                                          backend: :rust_syn,
                                          profile_id: :source_preserving
                                        ))

    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))

    analysis = described_class.new.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: input.fetch('base')
    )
    expect(analysis.fetch(:ok)).to eq(true), analysis.inspect
    expect(analysis.dig(:analysis, :declarations).map { |owner| owner.fetch(:path) })
      .to include(fixture.dig('expected', 'impl_owner_path'))
  end

  it 'distinguishes concrete generic impl owners through native syn' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_impl_concrete_generic_identity_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    tree_sitter = Rust::Merge::Provider.new.analyze(source: input.fetch('base'))
    expect(tree_sitter).to include(ok: fixture.dig('expected', 'ruby_tree_sitter_boundary', 'ok'))
    expect(tree_sitter.dig(:diagnostics, 0, :category).to_s)
      .to eq(fixture.dig('expected', 'ruby_tree_sitter_boundary', 'diagnostic_category'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.generic-impl')
    provider = described_class.new
    result = provider.merge3(
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs'),
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving
    )
    analysis = provider.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: input.fetch('base')
    )

    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    expect(analysis.fetch(:ok)).to eq(true), analysis.inspect
    expect(analysis.dig(:analysis, :declarations).map { |owner| owner.fetch(:path) })
      .to include(*fixture.dig('expected', 'impl_owner_paths'))
  end

  it 'merges trait aliases with independent edits through native syn' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_trait_alias_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    tree_sitter = Rust::Merge::Provider.new.analyze(source: input.fetch('base'))
    expect(tree_sitter).to include(ok: fixture.dig('expected', 'ruby_tree_sitter_boundary', 'ok'))
    expect(tree_sitter.dig(:diagnostics, 0, :category).to_s)
      .to eq(fixture.dig('expected', 'ruby_tree_sitter_boundary', 'diagnostic_category'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.trait-alias')
    provider = described_class.new
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    result = provider.merge3(request.merge(
                               family: :rust,
                               dialect: :rust,
                               backend: :rust_syn,
                               profile_id: :source_preserving
                             ))
    analysis = provider.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: input.fetch('base')
    )
    diff = provider.diff2(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      before_source: input.fetch('base'),
      after_source: input.fetch('ours')
    )
    directional = provider.merge2(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      incoming_source: input.fetch('base'),
      current_source: ''
    )

    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    expect(analysis.fetch(:ok)).to eq(true), analysis.inspect
    expect(analysis.dig(:analysis, :declarations).map { |owner| owner.fetch(:path) })
      .to include(fixture.dig('expected', 'trait_alias_path'))
    expect(diff.fetch(:ok)).to eq(true), diff.inspect
    expect(diff.fetch(:changes).map { |change| change.fetch(:path) })
      .to include(fixture.dig('expected', 'trait_alias_path'))
    expect(directional.fetch(:ok)).to eq(true), directional.inspect
    expect(directional.fetch(:output)).to eq(input.fetch('base'))
  end

  it 'merges extern-crate alias changes with independent function edits through rust_syn' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_extern_crate_owner_merge3.json',
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
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.extern-crate')
    rust = described_class.new.merge3(request.merge(
                                        family: :rust,
                                        dialect: :rust,
                                        backend: :rust_syn,
                                        profile_id: :source_preserving
                                      ))

    [native, rust].each do |result|
      expect(result.fetch(:ok)).to eq(true), result.inspect
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    end
  end

  it 'merges unique top-level macro invocations as syn-backed owners' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_macro_invocation_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    request = {
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    }
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.macro-invocation')
    result = described_class.new.merge3(request)

    parser_paths = fixture.dig('expected', 'parser_paths')
    native_parse = Rust::Merge::Provider.new.analyze(source: input.fetch('base'))
    tree_sitter_parse = described_class.new.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_tslp,
      profile_id: :source_preserving,
      source: input.fetch('base')
    )
    syn_parse = described_class.new.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: input.fetch('base')
    )

    expect(native_parse.fetch(:ok)).to eq(parser_paths.dig('ruby_native', 'ok')), native_parse.inspect
    expect(tree_sitter_parse.fetch(:ok)).to eq(parser_paths.dig('rust_treesitter', 'ok'))
    expect(tree_sitter_parse.dig(:diagnostics, 0, :category).to_s)
      .to eq(parser_paths.dig('rust_treesitter', 'category'))
    expect(syn_parse.fetch(:ok)).to eq(parser_paths.dig('rust_syn', 'ok')), syn_parse.inspect
    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))

    duplicate = fixture.fetch('duplicate_identity')
    native_failure = Rust::Merge::Provider.new.analyze(source: duplicate.fetch('source'))
    rust_failure = described_class.new.analyze(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      source: duplicate.fetch('source')
    )
    expect(native_failure.fetch(:ok)).to eq(false)
    expect(native_failure.dig(:diagnostics, 0, :category).to_s)
      .to eq(duplicate.dig('expected', 'ruby_native_category'))
    expect(rust_failure.fetch(:ok)).to eq(false)
    expect(rust_failure.dig(:diagnostics, 0, :category).to_s)
      .to eq(duplicate.dig('expected', 'rust_syn_host_category'))
  end

  it 'keeps preamble comments and removes comments owned by deleted Rust items' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_multiple_deletions_keep_preamble_comment_and_remove_attached_comment.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected = fixture.fetch('expected')
    native = Rust::Merge::Provider.new.merge3(
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )
    expect(native.fetch(:ok)).to eq(expected.dig('ruby_native', 'ok'))
    expect(native.dig(:diagnostics, 0, :category).to_s)
      .to eq(expected.dig('ruby_native', 'diagnostic_category'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.deleted-comment-ownership')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      )
      provider_expected = expected.dig('rust_host', backend.to_s)
      expect(result.fetch(:ok)).to eq(provider_expected.fetch('ok')), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(provider_expected.fetch('output')) if provider_expected['output']
      if provider_expected['diagnostic_code']
        expect(result.dig(:diagnostics, 0, :code).to_s)
          .to eq(provider_expected.fetch('diagnostic_code'))
      end
    end
  end

  it 'rehomes a deleted owner comment across a retained-owner reorder through syn' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_comment_rehome_with_reorder_and_independent_edit.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    expected = fixture.fetch('expected')
    native = Rust::Merge::Provider.new.merge3(
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )
    expect(native.fetch(:ok)).to eq(expected.dig('ruby_native', 'ok'))
    expect(native.dig(:diagnostics, 0, :category).to_s)
      .to eq(expected.dig('ruby_native', 'diagnostic_category'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.comment-rehome-reorder')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        base_source: input.fetch('base'),
        ours_source: input.fetch('ours'),
        theirs_source: input.fetch('theirs')
      )
      provider_expected = expected.dig('rust_host', backend.to_s)
      expect(result.fetch(:ok)).to eq(provider_expected.fetch('ok')), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(provider_expected.fetch('output')) if provider_expected['output']
      next unless provider_expected['diagnostic_code']

      expect(result.dig(:diagnostics, 0, :code).to_s)
        .to eq(provider_expected.fetch('diagnostic_code'))
      expect(result.dig(:conflicts, 0, :typed_record, :canonical, :classification, :extra, 'family_guard'))
        .to eq(provider_expected.fetch('diagnostic_code'))
    end
  end

  it 'preserves comments around syn-backed macro invocation owners' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_syn_macro_invocation_comments_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.macro-comments')
    result = described_class.new.merge3(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )

    expect(result.fetch(:ok)).to eq(true), result.inspect
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
      tree_sitter_result = if expected.key?('rust_treesitter_ok')
                             described_class.new.analyze(
                               family: :rust,
                               dialect: :rust,
                               backend: :rust_tslp,
                               profile_id: :source_preserving,
                               source: source
                             )
                           end

      expect(native_result.fetch(:ok)).to eq(expected.fetch('ruby_native_ok', expected.fetch('ok')))
      if tree_sitter_result
        expect(tree_sitter_result.fetch(:ok)).to eq(expected.fetch('rust_treesitter_ok'))
        if expected['rust_treesitter_category']
          category = tree_sitter_result.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category).to_s }
          expect(category).to include(expected.fetch('rust_treesitter_category'))
        end
      end
      expect(rust_result.fetch(:ok)).to eq(expected.fetch('rust_syn_host_ok', expected.fetch('ok')))
      native_categories = native_result.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category).to_s }
      rust_categories = rust_result.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category).to_s }
      expect(native_categories).to include(expected.fetch('ruby_native_category')) if expected['ruby_native_category']
      expect(rust_categories).to include(expected.fetch('rust_syn_host_category')) if expected['rust_syn_host_category']

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
      tree_sitter_merge = if expected.key?('rust_treesitter_merge_ok')
                            described_class.new.merge3(
                              family: :rust,
                              dialect: :rust,
                              backend: :rust_tslp,
                              profile_id: :source_preserving,
                              base_source: input.fetch('base'),
                              ours_source: input.fetch('ours'),
                              theirs_source: input.fetch('theirs')
                            )
                          end
      expect(native_merge.fetch(:ok)).to eq(expected.fetch('ruby_native_merge_ok', false))
      if tree_sitter_merge
        expect(tree_sitter_merge.fetch(:ok)).to eq(expected.fetch('rust_treesitter_merge_ok'))
        if expected['rust_treesitter_merge_category']
          categories = tree_sitter_merge.fetch(:diagnostics).map { |diagnostic| diagnostic.fetch(:category).to_s }
          expect(categories).to include(expected.fetch('rust_treesitter_merge_category'))
        end
        if expected['rust_treesitter_merge_output']
          expect(tree_sitter_merge.fetch(:output)).to eq(expected.fetch('rust_treesitter_merge_output'))
        end
      end
      expect(rust_merge.fetch(:ok)).to eq(expected.fetch('rust_syn_host_merge_ok', false))
      if expected['rust_syn_host_merge_output']
        expect(rust_merge.fetch(:output)).to eq(expected.fetch('rust_syn_host_merge_output'))
      end
      native_merge_categories = native_merge.fetch(:diagnostics).map do |diagnostic|
        diagnostic.fetch(:category).to_s
      end
      rust_merge_categories = rust_merge.fetch(:diagnostics).map do |diagnostic|
        diagnostic.fetch(:category).to_s
      end
      if expected['ruby_native_category']
        expect(native_merge_categories).to include(expected.fetch('ruby_native_category'))
      end
      if expected['rust_syn_host_category']
        expect(rust_merge_categories).to include(expected.fetch('rust_syn_host_category'))
      end
    end
  end

  it 'fails closed on native Rust syntax errors' do
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
    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_syn_parse_diagnostic_span.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    source = fixture.dig('input', 'source')
    malformed = provider.analyze(request.merge(source: source))
    ruby_native = Rust::Merge::Provider.new.analyze(source: source)
    rust_tslp = provider.analyze(request.merge(backend: :rust_tslp, source: source))

    expect(ruby_native.fetch(:ok)).to be(false)
    expect(ruby_native.dig(:diagnostics, 0, :category).to_s)
      .to eq(fixture.dig('expected', 'ruby_native_category'))
    expect(rust_tslp.fetch(:ok)).to be(false)
    expect(rust_tslp.dig(:diagnostics, 0, :category).to_s)
      .to eq(fixture.dig('expected', 'rust_tslp_category'))
    expect(malformed.fetch(:ok)).to be(false)
    malformed_messages = malformed.fetch(:diagnostics).map { |item| item.fetch(:message) }.join
    expect(malformed_messages).to include('native parser rejected input')
    source_span = malformed.dig(:diagnostics, 0, :typed_record, :canonical, :source_refs, 0, :span)
    expect(source_span.dig(:range, :start_byte))
      .to eq(fixture.dig('expected', 'diagnostic_byte_range', 0))
    expect(source_span.dig(:range, :end_byte))
      .to eq(fixture.dig('expected', 'diagnostic_byte_range', 1))
  end
  it 'treats a syn foreign module as one owner and preserves its attached comment' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_foreign_mod_owner_merge3.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.foreign-mod')
    provider = described_class.new
    request = {
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs'),
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving
    }

    result = provider.merge3(request)
    analysis = provider.analyze(request.slice(:family, :dialect, :backend, :profile_id).merge(
                                  source: input.fetch('base')
                                ))

    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
    expect(analysis.fetch(:ok)).to eq(true), analysis.inspect
    expect(analysis.dig(:analysis, :declarations).map { |owner| owner.fetch(:path) })
      .to include(fixture.dig('expected', 'foreign_mod_path'))
  end

  it 'reports a portable conflict when Rust tips impose cyclic owner orders' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_two_sided_owner_reorder_boundary.json',
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
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(fixture.dig('expected', 'ruby_native_expected', 'output'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.two-sided-reorder-conflict')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to be(false), "#{backend}: #{result.inspect}"
      expect(result[:output]).to be_nil
      expect(result.fetch(:diagnostics).first.fetch(:category)).to eq(:merge_conflict)
      conflict = result.fetch(:conflicts).fetch(0).fetch(:typed_record).fetch(:canonical)
      expect(conflict.fetch(:id)).to eq(fixture.dig('expected', 'conflict_id'))
      expect(conflict.fetch(:subject).fetch(:structural_path)).to eq(fixture.dig('expected', 'path'))
      expect(conflict.fetch(:roles)).to eq(%i[base ours theirs])
    end
  end

  it 'keeps same-spelling Rust type and value owners distinct through syn' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_same_spelling_type_and_value_owners.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.namespaces')
    provider = described_class.new
    request = {
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving
    }
    analysis = provider.analyze(request.merge(source: input.fetch('base')))
    result = provider.merge3(request.merge(
                               base_source: input.fetch('base'),
                               ours_source: input.fetch('ours'),
                               theirs_source: input.fetch('theirs')
                             ))

    expect(analysis.fetch(:ok)).to eq(true), analysis.inspect
    expect(analysis.dig(:analysis, :declarations).map { |owner| owner.fetch(:path) })
      .to include(*fixture.dig('expected', 'owner_paths'))
    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
  end

  it 'composes a one-sided reorder with a documented stable interior-gap addition' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_reorder_with_interior_addition.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.interior-reorder-addition')
    result = described_class.new.merge3(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )

    expect(result.fetch(:ok)).to eq(true), result.inspect
    expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output'))
  end

  it 'composes a reordered Rust owner with an edge addition and blank-line gaps' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_edge_addition_with_reorder_and_layout_gaps.json',
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
    expect(native.fetch(:ok)).to be(false), native.inspect
    expect(native.dig(:conflicts, 0, :category)).to eq(:unmanaged_source_change)

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.edge-add-gap-reorder')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
    end
  end

  it 'merges compatible disjoint owner reorders with Rust source identities' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_compatible_two_sided_reorders.json',
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
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(fixture.dig('expected', 'ruby_native_output'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.compatible-reorders')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
    end
  end

  it 'composes acyclic two-tip reorders around a documented interior addition' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_compatible_reorders_with_interior_addition.json',
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
    expect(native.fetch(:ok)).to be(true), native.inspect
    expect(native.fetch(:output)).to eq(fixture.dig('ruby_native_expected', 'output'))

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.reorders-with-interior-addition')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
    end
  end

  it 'composes compatible Rust reorders with controller-owned blank-line gaps' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_compatible_reorders_with_owned_gaps.json',
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
    expect(native.fetch(:ok)).to be(false), native.inspect
    expect(native.dig(:conflicts, 0, :category)).to eq(:unmanaged_source_change)

    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.reorders-with-owned-gaps')
    %i[rust_tslp rust_syn].each do |backend|
      result = described_class.new.merge3(
        family: :rust,
        dialect: :rust,
        backend: backend,
        profile_id: :source_preserving,
        **request
      )
      expect(result.fetch(:ok)).to be(true), "#{backend}: #{result.inspect}"
      expect(result.fetch(:output)).to eq(fixture.dig('expected', 'output')), backend.to_s
    end
  end

  it 'reports an owner-order conflict when a reorder crosses the other tip’s new owner gap' do
    skip 'compiled native syn registration is unavailable' unless
      StructuredmergeCore.respond_to?(:register_rust_syn_parser)

    fixture_path = File.expand_path(
      '../../../../../fixtures/polyglot/typed-core/rust_merge3_reorder_crossed_gap_boundary.json',
      __dir__
    )
    fixture = JSON.parse(File.read(fixture_path))
    input = fixture.fetch('input')
    StructuredmergeCore.register_rust_syn_parser('rust.syn.ruby.crossed-gap')
    result = described_class.new.merge3(
      family: :rust,
      dialect: :rust,
      backend: :rust_syn,
      profile_id: :source_preserving,
      base_source: input.fetch('base'),
      ours_source: input.fetch('ours'),
      theirs_source: input.fetch('theirs')
    )

    expect(result.fetch(:ok)).to eq(false), result.inspect
    expect(result[:output]).to be_nil
    expect(result.dig(:conflicts, 0, :typed_record, :canonical, :id)).to eq('rust-owner-order-divergence')
    expect(result.dig(:conflicts, 0, :typed_record, :canonical, :subject, :structural_path)).to eq('<owner-order>')
  end
end
