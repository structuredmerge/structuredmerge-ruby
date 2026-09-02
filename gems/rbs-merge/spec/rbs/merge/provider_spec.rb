# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider safety, provenance, and conformance form one executable contract
RSpec.describe Rbs::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) do
    <<~RBS
      # exact preamble
      class Alpha
        def value: () -> String
      end

      class Beta
        def value: () -> Integer
      end
    RBS
  end

  it 'auto-registers the ruby.rbs workflow for native RBS and TSLP' do
    expect(provider).to have_attributes(provider_id: 'ruby.rbs', family: 'rbs')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[rbs],
      backends: %i[rbs tslp kreuzberg-language-pack],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.rbs',
        family: :rbs,
        dialect: :rbs,
        backend: :rbs,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Rbs::Merge.merge_provider)
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.rbs',
        family: :rbs,
        dialect: :rbs,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Rbs::Merge.merge_provider)
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.rbs',
        family: :rbs,
        dialect: :rbs,
        backend: :tslp,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Rbs::Merge.merge_provider)
  end

  it 'analyzes native declarations with source-role and line provenance' do
    result = provider.analyze(source: base)

    expect(result).to include(ok: true, operation: :analyze)
    expect(result.dig(:analysis, :backend)).to eq('rbs')
    expect(result.dig(:analysis, :declarations)).to contain_exactly(
      hash_including(signature: [:class, 'Alpha'], source_role: :source, line_range: [2, 4]),
      hash_including(signature: [:class, 'Beta'], source_role: :source, line_range: [6, 8])
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'distinguishes every safely owned top-level declaration signature' do
    source = <<~RBS
      class Example
      end
      module Namespace
      end
      interface _Readable
      end
      type token = String
      VERSION: String
      $stdout: IO
    RBS

    signatures = provider.analyze(source: source).dig(:analysis, :declarations).map { |item| item.fetch(:signature) }

    expect(signatures).to eq(
      [
        [:class, 'Example'],
        [:module, 'Namespace'],
        [:interface, '_Readable'],
        [:type_alias, 'token'],
        [:constant, 'VERSION'],
        [:global, '$stdout']
      ]
    )
  end

  it 'diffs additions, edits, and deletions with source ranges' do
    after = base.sub('class Alpha', 'class Gamma').sub('Integer', 'bool')
    result = provider.diff2(before_source: base, after_source: after)

    expect(result).to include(ok: true, operation: :diff2)
    expect(result.fetch(:changes).map { |change| change[:change] }).to contain_exactly(:deleted, :added, :edited)
    expect(result.fetch(:changes)).to include(
      hash_including(after: hash_including(source_role: :after, line_range: [2, 4]))
    )
  end

  it 'performs a two-way incoming overlay and appends incoming-only declarations' do
    current = "class Current\nend\n"
    incoming = "class Current\n  def added: () -> void\nend\nclass Incoming\nend\n"

    result = provider.merge2(current_source: current, incoming_source: incoming)

    expect(result).to include(ok: true, operation: :merge2, output: incoming)
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'preserves destination member customizations during a two-way merge' do
    incoming = "class Api\n  def call: () -> String\nend\n\nclass Required\nend\n"
    current = "class Api\n  def call: () -> bool\nend\n"
    expected = "class Api\n  def call: () -> bool\nend\n\nclass Required\nend\n"

    result = provider.merge2(current_source: current, incoming_source: incoming)

    expect(result).to include(ok: true, operation: :merge2, output: expected)
    expect(result.dig(:render_report, :strategy)).to eq(:rbs_substrate)
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ordered_declaration_signatures_verified: true
    )
  end

  it 'merges independent top-level edits while preserving exact source and ours order' do
    ours = base.sub('String', 'bool')
    theirs = base.sub('Integer', 'untyped')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true, output: ours.sub('Integer', 'untyped'))
    expect(result.dig(:render_report, :strategy)).to eq(:exact_declaration_composite)
    expect(result.dig(:render_report, :line_records)).to include(
      hash_including(source_role: :ours),
      hash_including(source_role: :theirs)
    )
    expect(result.fetch(:verification)).to include(
      output_reparsed: true,
      semantic_match: true,
      ordered_declaration_signatures_verified: true,
      ast_attributes_verified: true,
      base_participated: true
    )
  end

  it 'keeps ours order and appends theirs-only declarations' do
    ours = "#{base}class OursOnly\nend\n"
    theirs = "#{base}class TheirsOnly\nend\n"
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true)
    expect(result.fetch(:output)).to end_with("class OursOnly\nend\nclass TheirsOnly\nend\n")
  end

  it 'synthesizes only a provenance-recorded separator for a no-final-newline source' do
    stable = "class Stable\nend\n"
    ours = "class Stable\nend\nclass Ours\nend"
    theirs = "class Stable\nend\nclass Theirs\nend\n"
    result = provider.merge3(base_source: stable, ours_source: ours, theirs_source: theirs)

    expect(result).to include(
      ok: true,
      output: "class Stable\nend\nclass Ours\nend\nclass Theirs\nend\n"
    )
    expect(result.dig(:render_report, :synthesized_fragments)).to include(
      hash_including(reason: :declaration_separator, metadata: hash_including(source_role: :ours, copied_source: true))
    )
  end

  it 'returns an exact valid winner including comments, spacing, order, and missing final newline' do
    exact = "# replacement docs\n\nclass Zed\n  def x: ( String ) -> Integer\nend"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'copies an exact winner with reopened declaration identities byte-for-byte' do
    exact = <<~RBS
      # first reopening
      class Duplicate
        def first: () -> String
      end

      # second reopening
      class Duplicate
        def second: () -> Integer
      end
    RBS
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :ambiguous_owner, source_role: :theirs, blocking: false)
    )
    expect(result.fetch(:verification)).to include(
      byte_exact: true,
      semantic_match: true,
      ordered_declaration_signatures_verified: true,
      ast_attributes_verified: true,
      planned_declaration_count: 2,
      output_declaration_count: 2,
      base_participated: true
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  it 'preserves complex native RBS syntax byte-for-byte instead of canonicalizing it' do
    exact = <<~'RBS'.chomp
      # generic docs
      %a{stable}
      class Box[out T]
        def map: [U] (T value) { (T) -> U } -> (U | nil)
               | (?T) -> (U & Object)
      end
    RBS

    result = provider.merge3(base_source: base, ours_source: base, theirs_source: exact)

    expect(result).to include(ok: true, output: exact)
  end

  it 'accepts an empty exact revision as deletion of every declaration' do
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: '')

    expect(result).to include(ok: true, output: '')
    expect(result.dig(:verification, :semantic_match)).to be(true)
  end

  it 'localizes divergent edits only to a proven top-level declaration range' do
    ours = base.sub('String', 'bool')
    theirs = base.sub('String', 'untyped')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
    expect(result.fetch(:conflicted_output)).to start_with("# exact preamble\n<<<<<<< ours\n")
    expect(result.fetch(:conflicted_output)).to end_with("class Beta\n  def value: () -> Integer\nend\n")
    expect(result.fetch(:conflicts)).to include(hash_including(category: :edit_edit))
  end

  it 'fully conflicts a delete/edit divergence because ours has no source range to localize' do
    ours = base.lines.take(5).join
    theirs = base.sub('Integer', 'bool')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :delete_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    expect(result.fetch(:fallbacks)).to include(hash_including(reason: :source_ownership_unproven))
  end

  it 'fully conflicts unmanaged comment or layout changes during a structural composite' do
    ours = base.sub('# exact preamble', '# ours changed unmanaged docs')
    theirs = base.sub('Integer', 'bool')
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unmanaged_source_change))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'fully conflicts directives during a composite because their source ownership is unmanaged' do
    directed = "use Foo::*\n#{base}"
    ours = "#{directed}class Ours\nend\n"
    theirs = directed.sub('Integer', 'bool')
    result = provider.merge3(base_source: directed, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :unsafe_directives))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'conflicts nested edits conservatively at their proven top-level declaration owner' do
    nested_base = "class Container\n  def left: () -> String\n  def right: () -> Integer\nend\n"
    ours = nested_base.sub('String', 'bool')
    theirs = nested_base.sub('Integer', 'untyped')
    result = provider.merge3(base_source: nested_base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit))
    expect(result.dig(:render_report, :strategy)).to eq(:declaration_localized_conflict)
  end

  it 'rejects duplicate declaration identities in a divergent structural composite with a full-file conflict' do
    duplicate = "class Duplicate\nend\nclass Duplicate\nend\n"
    theirs = base.sub('Integer', 'bool')
    result = provider.merge3(base_source: base, ours_source: duplicate, theirs_source: theirs)

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:conflicts)).to contain_exactly(hash_including(category: :ambiguous_owner))
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
  end

  it 'rejects malformed syntax in the selected exact winner with its source role' do
    invalid = "class Broken\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: invalid)

    expect(result).to include(ok: false, source_role: :theirs)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, blocking: true, message: /theirs parse error/)
    )
  end

  it 'rejects unsafe native source ranges with a full-file conflict' do
    location = Data.define(:start_line, :end_line, :start_column, :start_pos, :end_pos)
                   .new(start_line: 1, end_line: 1, start_column: 2, start_pos: 2, end_pos: 8)

    expect(provider.send(:safe_range?, '  X: int', location)).to be(false)
  end

  it 'attributes syntax failures to their source role and remains JSON serializable' do
    result = provider.merge3(base_source: base, ours_source: "class Broken\n", theirs_source: base)

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :parse_error, message: /ours parse error/)
    )
    expect { JSON.generate(Ast::Merge.json_ready(result)) }.not_to raise_error
  end

  context 'with the TSLP backend' do
    before do
      skip 'tree-sitter-rbs grammar is unavailable' unless TreeHaver::GrammarFinder.new(:rbs).available?
    end

    it 'analyzes and diffs normalized declarations' do
      analysis = provider.analyze(source: base, backend: :tslp)
      diff = provider.diff2(
        before_source: base,
        after_source: base.sub('Integer', 'bool'),
        backend: :tslp
      )

      expect(analysis).to include(ok: true)
      expect(analysis.dig(:provider, :backend)).to eq(:tslp)
      expect(analysis.dig(:analysis, :backend)).to eq('tree_sitter')
      expect(analysis.dig(:analysis, :declarations).map { |item| item.fetch(:signature) }).to eq(
        [[:class, 'Alpha'], [:class, 'Beta']]
      )
      expect(diff.fetch(:changes)).to contain_exactly(hash_including(change: :edited))
    end

    it 'performs exact two-way and composite three-way merges' do
      current = "class Current\nend\n"
      incoming = "class Current\n  def added: () -> void\nend\nclass Incoming\nend\n"
      merge2 = provider.merge2(current_source: current, incoming_source: incoming, backend: :tslp)
      ours = base.sub('String', 'bool')
      theirs = base.sub('Integer', 'untyped')
      merge3 = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs, backend: :tslp)

      expect(merge2).to include(ok: true, output: incoming)
      expect(merge2.dig(:verification, :semantic_match)).to be(true)
      expect(merge3).to include(ok: true, output: ours.sub('Integer', 'untyped'))
      expect(merge3.fetch(:verification)).to include(
        semantic_match: true,
        ordered_declaration_signatures_verified: true,
        ast_attributes_verified: true,
        base_participated: true
      )
    end

    it 'fails closed on malformed syntax' do
      result = provider.merge3(
        base_source: base,
        ours_source: "class Broken\n",
        theirs_source: base,
        backend: :tslp
      )

      expect(result).to include(ok: false, source_role: :ours)
      expect(result.fetch(:diagnostics)).to contain_exactly(
        hash_including(category: :parse_error, blocking: true)
      )
    end
  end
end

RSpec.describe 'Rbs::Merge provider conformance' do
  subject(:provider) { Rbs::Merge.merge_provider }

  let(:stable) { "class Stable\nend\n" }
  let(:provider_conformance) do
    {
      dialect: :rbs,
      backend: :rbs,
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: "class Stable\n  def x: () -> void\nend\n" },
        merge2: { current_source: stable, incoming_source: "class Added\nend\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}class Ours\nend\n",
          theirs_source: "#{stable}class Theirs\nend\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "class Broken\n",
        theirs_source: stable,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "class Obsolete\nend\n#{stable}",
          ours_source: "class Obsolete\nend\n#{stable}",
          theirs_source: stable
        },
        expected_value: [[:class, 'Stable']]
      },
      parse_output: lambda { |source|
        analysis = TreeHaver.with_backend(:rbs) { Rbs::Merge::FileAnalysis.new(source) }
        analysis.statements.map(&:signature)
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
