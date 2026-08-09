# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider ownership and conservative Rust boundaries form one contract
RSpec.describe Rust::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~RUST
      use crate::shared;

      /// alpha docs
      #[inline]
      fn alpha() -> &'static str {
          "alpha"
      }

      fn beta() -> i32 {
          2
      }
    RUST
  end

  it 'registers the exact Rust workflow selector and supports all operations' do
    expect(provider).to have_attributes(provider_id: 'ruby.rust', family: 'rust')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[rust],
      backends: [:'kreuzberg-language-pack'],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.rust',
        family: :rust,
        dialect: :rust,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Rust::Merge.merge_provider)
  end

  it 'derives stable identities for Rust imports, declarations, impls, and macros from the AST' do
    source = <<~RUST
      use crate::{alpha, beta};
      extern crate alloc as memory;
      mod nested;
      struct Shape<T> { value: T }
      enum Choice { One }
      union Storage { value: u32 }
      type Name<T> = Vec<T>;
      const LIMIT: usize = 1;
      static ENABLED: bool = true;
      trait Render<T> {}
      fn run<T>() {}
      impl<T> !Send for Shape<T> {}
      impl<T> Render<T> for Shape<T> {}
      macro_rules! build { () => {} }
      build!();
    RUST
    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }

    expect(signatures).to include(
      [:extern_crate, 'alloc'],
      [:module, 'nested'],
      [:struct, 'Shape'],
      [:enum, 'Choice'],
      [:union, 'Storage'],
      [:type, 'Name'],
      [:const, 'LIMIT'],
      [:static, 'ENABLED'],
      [:trait, 'Render'],
      [:function, 'run'],
      [:impl, 'Send', 'Shape', :negative, 1],
      [:impl, 'Render', 'Shape', :positive, 1],
      [:macro, 'build'],
      [:macro_invocation, 'build']
    )
    expect(signatures).to include(satisfy { |value| value.first == :use_tree && value.last == 'crate' })
  end

  it 'supports the legacy parse, owner matching, and destination-wins merge API' do
    parsed = Rust::Merge.parse_rust("fn stable() {}\n", 'rust')
    merged = Rust::Merge.merge_rust("fn added() {}\n", "fn stable() {}\n", 'rust')

    expect(parsed).to include(ok: true)
    expect(Rust::Merge.match_rust_owners([{ path: '/a' }], [{ path: '/a' }])).not_to be_nil
    expect(merged).to include(ok: true)
    expect(merged.fetch(:output)).to include('fn stable()', 'fn added()')
  end

  it 'diffs additions, edits, and deletions in a JSON-ready envelope' do
    after = base.sub('fn alpha', 'fn gamma').sub("\n    2\n", "\n    3\n")
    result = provider.diff2(before_source: base, after_source: after)

    expect(result.fetch(:changes).map { |change| change[:change] }).to contain_exactly(:deleted, :added, :edited)
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'implements merge2 and performs a true base-aware independent merge3' do
    incoming = "#{base}fn incoming() {}\n"
    expect(provider.merge2(current_source: base, incoming_source: incoming)).to include(
      ok: true,
      operation: :merge2,
      output: incoming
    )

    ours = "#{base.sub('"alpha"', '"ours"')}struct Ours;\n"
    theirs = "#{base.sub("\n    2\n", "\n    3\n")}trait Theirs {}\n"
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('"ours"', '3', 'struct Ours;', 'trait Theirs')
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ast_attributes_verified: true,
      base_participated: true
    )
  end

  it 'honors a base deletion and orders independent uses before declarations' do
    old_base = "#{base}fn obsolete() {}\n"
    deleted = provider.merge3(
      base_source: old_base,
      ours_source: "#{old_base}fn ours() {}\n",
      theirs_source: base
    )
    expect(deleted.fetch(:output)).not_to include('obsolete')

    ours = base.sub('use crate::shared;', "use crate::ours;\nuse crate::shared;")
    theirs = base.sub('use crate::shared;', "use crate::theirs;\nuse crate::shared;")
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)
    expect(result).to include(ok: true)
    expect(result.fetch(:output).index('use crate::theirs;')).to be < result.fetch(:output).index('fn alpha')
  end

  it 'keeps use identity stable across aliases and localizes divergent owner edits' do
    use_base = "use crate::shared as value;\nfn stable() {}\n"
    result = provider.merge3(
      base_source: use_base,
      ours_source: use_base.sub('as value', 'as ours'),
      theirs_source: use_base.sub('as value', 'as theirs')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output)).to end_with("fn stable() {}\n")
  end

  it 'uses trait, target, polarity, and generic arity for impl identity' do
    source = <<~RUST
      struct Value<T>(T);
      trait Convert<T> {}
      impl<T> Convert<T> for Value<T> {}
      impl<T, U> Convert<T> for Value<U> {}
      impl<T> !Send for Value<T> {}
      impl<T> Value<T> {}
    RUST
    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }

    expect(signatures.count { |signature| signature.first == :impl }).to eq(4)
    expect(signatures).to include(
      [:impl, 'Convert', 'Value', :positive, 1],
      [:impl, 'Convert', 'Value', :positive, 2],
      [:impl, 'Send', 'Value', :negative, 1],
      [:impl, nil, 'Value', :positive, 1]
    )
  end

  it 'ignores comments when deriving impl trait and target identity' do
    plain = provider.analyze(source: "impl Trait for Value {}\n")
    commented = provider.analyze(source: "impl Trait /* structural note */ for Value {}\n")

    expect(plain.dig(:analysis, :declarations, 0, :signature)).to eq(
      commented.dig(:analysis, :declarations, 0, :signature)
    )
  end

  it 'attaches attributes and docs to exact owner ranges and preserves a no-final-newline winner' do
    exact = "/// docs\n#[cold]\nfn chosen( ) { }\n\nfn stable() {}".chomp
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.fetch(:verification)).to include(
      byte_exact: true,
      semantic_match: true,
      ordered_declaration_signatures_verified: true,
      ast_attributes_verified: true
    )
  end

  it 'keeps crate attributes before a newly inserted first use and attaches spaced outer attributes' do
    attributed = "#![allow(dead_code)]\n\n/// docs\n\n#[cold]\n\nfn stable() {}\n"
    theirs = "#![allow(dead_code)]\n\nuse crate::added;\n/// docs\n\n#[cold]\n\nfn stable() {}\n"
    result = provider.merge3(base_source: attributed, ours_source: attributed, theirs_source: theirs)

    expect(result).to include(ok: true, output: theirs)
    expect(result.fetch(:verification)).to include(semantic_match: true)
  end

  it 'accepts parser-valid duplicate exact winners with nonblocking diagnostics' do
    exact = "fn duplicate() {}\nfn duplicate() {}\nimpl Thing {}\nimpl Thing {}\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :ambiguous_owner, blocking: false, source_role: :theirs)
    )
  end

  it 'blocks ambiguous duplicate owners in composites and malformed roles' do
    ambiguous = "fn duplicate() {}\nfn duplicate() {}\n"
    expect(provider.analyze(source: ambiguous)).to include(
      ok: false,
      diagnostics: include(hash_including(category: :ambiguous_owner))
    )

    malformed = provider.merge3(base_source: base, ours_source: "fn broken( {\n", theirs_source: base)
    expect(malformed).to include(ok: false, source_role: :ours)
    expect(malformed.fetch(:diagnostics)).to contain_exactly(hash_including(category: :parse_error, blocking: true))
  end

  it 'fails closed when compound use membership changes across revisions' do
    compound = "use crate::{alpha, beta};\nfn stable() {}\n"
    result = provider.merge3(
      base_source: compound,
      ours_source: compound.sub('beta', 'ours'),
      theirs_source: compound.sub('beta', 'theirs')
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unproven_compound_ownership))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'selects a one-sided compound use edit as one whole owner' do
    compound = "use crate::{alpha, beta};\nfn stable() {}\n"
    theirs = compound.sub('beta', 'beta, gamma')
    result = provider.merge3(base_source: compound, ours_source: compound, theirs_source: theirs)

    expect(result).to include(ok: true, output: theirs)
    expect(result.fetch(:output).scan('use crate::').length).to eq(1)
  end

  it 'treats repeated macro invocations conservatively and preserves independent macro owners' do
    expect(provider.analyze(source: "build!();\nbuild!();\n")).to include(
      ok: false,
      diagnostics: include(hash_including(category: :ambiguous_owner))
    )

    macro_base = "macro_rules! build { () => {} }\nfn stable() {}\n"
    result = provider.merge3(
      base_source: macro_base,
      ours_source: "#{macro_base}left!();\n",
      theirs_source: "#{macro_base}right!();\n"
    )
    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to include('left!();', 'right!();')
  end

  it 'uses full-file fallback for independently changed unmanaged crate source' do
    unmanaged = "#![allow(dead_code)]\nfn stable() {}\n"
    result = provider.merge3(
      base_source: unmanaged,
      ours_source: unmanaged.sub('dead_code', 'unused'),
      theirs_source: "#{unmanaged}fn theirs() {}\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unmanaged_source_change))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end
end

RSpec.describe 'Rust provider conformance' do
  subject(:provider) { Rust::Merge.merge_provider }

  let(:stable) { "fn stable() {}\n" }
  let(:provider_conformance) do
    {
      dialect: :rust,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: stable.sub('{}', '{ return; }') },
        merge2: { current_source: stable, incoming_source: "#{stable}struct Added;\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}struct Ours;\n",
          theirs_source: "#{stable}trait Theirs {}\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "fn broken( {\n",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "fn obsolete() {}\n#{stable}",
          ours_source: "fn obsolete() {}\n#{stable}",
          theirs_source: stable
        },
        expected_value: [[:function, 'stable']]
      },
      parse_output: lambda { |source|
        Rust::Merge::FileAnalysis.new(source).declarations.map(&:signature)
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
