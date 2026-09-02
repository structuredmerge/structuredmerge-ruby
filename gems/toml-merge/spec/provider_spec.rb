# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- workflow fidelity and safety cases exercise one public contract
RSpec.describe Toml::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) { "# retained\nalpha = \"base\"\nbeta = 1\n" }
  let(:ours) { "# retained\nalpha = 'ours'\nbeta = 1\nours_only = [1, 2]\n" }
  let(:theirs) { "# retained\nalpha = \"base\"\nbeta = 2_000\ntheirs_only = { enabled = true }\n" }

  it 'advertises and auto-registers the TOML workflow without replacing backend providers' do
    expect(provider).to have_attributes(provider_id: 'ruby.toml', family: 'toml', role: :workflow)
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[toml],
      backends: [:'kreuzberg-language-pack'],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.toml',
        family: :toml,
        dialect: :toml,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Toml::Merge.merge_provider)
  end

  it 'is only a KLP configuration of the shared source-preserving algorithm' do
    source = File.read(File.expand_path('../lib/toml/merge/provider.rb', __dir__))

    expect(described_class.superclass).to equal(Toml::Merge::SourcePreservingProvider)
    expect(source).not_to include(
      'Citrus', 'Parslet', 'SmartMerger', 'def analyze', 'def diff2', 'def merge2', 'def merge3'
    )
  end

  it 'analyzes KLP nodes with exact source ranges and JSON-safe attributes' do
    result = provider.analyze(
      source: "first = 1\n# array docs\narray = [1, 2_000]\npublished = 1979-05-27\ninline = { enabled = true }\n"
    )

    expect(result).to include(ok: true, operation: :analyze)
    expect(result.dig(:analysis, :backend)).to eq('kreuzberg-language-pack')
    expect(result.dig(:analysis, :document_attributes)).to eq(
      type: 'document',
      canonical_type: 'document',
      signature: ['document']
    )
    expect(result.dig(:analysis, :entries)).to include(
      hash_including(
        key: 'array',
        source_role: :source,
        source_lines: [2, 3],
        attributes: hash_including(type: 'array', canonical_type: 'array', signature: ['array', 2])
      ),
      hash_including(
        key: 'published',
        source_lines: [4, 4],
        attributes: hash_including(type: 'local_date', canonical_type: 'datetime')
      ),
      hash_including(
        key: 'inline',
        source_lines: [5, 5],
        attributes: hash_including(type: 'inline_table', canonical_type: 'inline_table')
      )
    )
    expect(result.dig(:verification, :source_parsed)).to be(true)
    expect { JSON.generate(result) }.not_to raise_error
  end

  it 'validates then copies exact winners byte-for-byte' do
    winner = "alpha = 'theirs' # exact\r\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: winner)

    expect(result).to include(ok: true, output: winner)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.dig(:verification, :byte_exact)).to be(true)
    expect(result.dig(:verification, :source_role)).to eq(:theirs)
    expect(result.dig(:verification, :base_participated)).to be(true)
  end

  it 'makes independent root decisions and preserves exact selected fragments' do
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(
      ok: true,
      output: "# retained\nalpha = 'ours'\nbeta = 2_000\nours_only = [1, 2]\ntheirs_only = { enabled = true }\n"
    )
    expect(result.dig(:render_report, :strategy)).to eq(:exact_mapping_entry_composite)
    expect(result.dig(:verification, :semantic_match)).to be(true)
    expect(result.dig(:verification, :ast_attributes_match)).to be(true)
    expect(result.dig(:verification, :entry_sources)).to eq(
      [
        { key: 'alpha', source_role: :ours, source_lines: [2, 2] },
        { key: 'beta', source_role: :theirs, source_lines: [3, 3] },
        { key: 'ours_only', source_role: :ours, source_lines: [4, 4] },
        { key: 'theirs_only', source_role: :theirs, source_lines: [4, 4] }
      ]
    )
  end

  it 'routes nested table merge2 through the shared TOML substrate' do
    fixture = JSON.parse(
      File.read(
        File.expand_path(
          '../../../../fixtures/toml/slice-720-advanced-leaf-merge/nested-table-leaf-merge.json',
          __dir__
        )
      ),
      symbolize_names: true
    )
    result = provider.merge2(
      current_source: fixture.fetch(:destination),
      incoming_source: fixture.fetch(:template)
    )

    expect(result).to include(ok: true, output: fixture.dig(:expected, :output))
    expect(result.dig(:render_report, :strategy)).to eq(:toml_substrate)
    expect(result.dig(:verification, :output_reparsed)).to be(true)
    expect(result.dig(:verification, :backend)).to eq('kreuzberg-language-pack')
  end

  it 'preserves the shared advanced dotted-key fixture through the TSLP substrate' do
    fixture = JSON.parse(
      File.read(
        File.expand_path(
          '../../../../fixtures/toml/slice-721-formatting-preservation/dotted-inline-comments-arrays.json',
          __dir__
        )
      ),
      symbolize_names: true
    )
    result = provider.merge2(
      current_source: fixture.fetch(:destination),
      incoming_source: fixture.fetch(:template)
    )

    expect(result).to include(ok: true, output: fixture.dig(:expected, :output))
  end

  it 'preserves KLP temporal numeric string array and inline-table source fidelity' do
    result = provider.merge3(
      base_source: "stable = true\n",
      ours_source: "stable = true\ndate = 1979-05-27\nmask = 0xDEAD_BEEF\nliteral = 'value'\n",
      theirs_source: "stable = true\nnumbers = [1, 2_000]\nsettings = { enabled = true }\n"
    )

    expect(result).to include(
      ok: true,
      output: "stable = true\ndate = 1979-05-27\nmask = 0xDEAD_BEEF\nliteral = 'value'\n" \
              "numbers = [1, 2_000]\nsettings = { enabled = true }\n"
    )
    expect(result.dig(:verification, :source_match)).to be(true)
    expect { JSON.generate(result) }.not_to raise_error
  end

  it 'combines base-aware additions edits and deletions' do
    result = provider.merge3(
      base_source: "delete = true\nedit = 'base'\nkeep = true\n",
      ours_source: "edit = 'base'\nkeep = true\nours = 'added'\n",
      theirs_source: "delete = true\nedit = \"theirs\"\nkeep = true\ntheirs = 1_000\n"
    )

    expect(result).to include(
      ok: true,
      output: "edit = \"theirs\"\nkeep = true\nours = 'added'\ntheirs = 1_000\n"
    )
  end

  it 'synthesizes only a separator when appending after no-final-newline' do
    result = provider.merge3(
      base_source: "stable = true\n",
      ours_source: "stable = true\nours = 1",
      theirs_source: "stable = true\ntheirs = 2\n"
    )

    expect(result).to include(ok: true, output: "stable = true\nours = 1\ntheirs = 2\n")
    expect(result.dig(:render_report, :synthesized_fragments)).to contain_exactly(
      hash_including(reason: :mapping_entry_separator)
    )
  end

  it 'localizes edit/edit and delete/edit conflicts with proven ownership' do
    stable = "stable = true\n# value docs\nvalue = 'base'\ntail = true\n"
    edit = provider.merge3(
      base_source: stable,
      ours_source: "stable = true\n# left docs\nvalue = 'ours'\ntail = true\n",
      theirs_source: "stable = true\n# right docs\nvalue = 'theirs'\ntail = true\n"
    )
    deletion = provider.merge3(
      base_source: "stable = true\nvalue = 'base'\n",
      ours_source: "stable = true\n",
      theirs_source: "stable = true\nvalue = 'theirs'\n"
    )

    expect(edit).to include(ok: false)
    expect(edit.fetch(:conflicted_output)).to start_with("stable = true\n<<<<<<< ours\n")
    expect(edit.fetch(:conflicts)).to contain_exactly(hash_including(category: :edit_edit, path: '/value'))
    expect(edit.dig(:render_report, :strategy)).to eq(:mapping_entry_localized_conflict)
    expect(deletion.fetch(:conflicts)).to include(hash_including(category: :delete_edit, path: '/value'))
    expect(deletion.dig(:render_report, :strategy)).to eq(:mapping_entry_localized_conflict)
    expect { JSON.generate(deletion) }.not_to raise_error
  end

  it 'uses a full-file conflict for independently changed unmanaged comments' do
    result = provider.merge3(
      base_source: "# heading\nvalue = 'base'\n",
      ours_source: "# ours heading\nvalue = 'ours'\n",
      theirs_source: "# theirs heading\nvalue = 'theirs'\n"
    )

    expect(result).to include(ok: false)
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    expect(result.fetch(:fallbacks)).to include(hash_including(reason: :unmanaged_source_change))
  end

  it 'blocks composite duplicate dotted table and array-of-table structures with source roles' do
    unsafe_sources = {
      duplicate_key: "alpha = 1\nalpha = 2\n",
      dotted_key: "alpha.beta = 1\n",
      table: "[alpha]\nbeta = 1\n",
      array_of_tables: "[[alpha]]\nbeta = 1\n"
    }

    unsafe_sources.each do |category, source|
      result = provider.merge3(base_source: base, ours_source: source, theirs_source: ours)

      expect(result).to include(ok: false, source_role: :ours), category.to_s
      expect(result.fetch(:diagnostics)).to include(
        hash_including(category: category, source_role: :ours, blocking: true)
      ), category.to_s
    end
  end

  it 'allows a structurally unsafe exact one-sided valid winner' do
    table = "[alpha]\nbeta = 1\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: table)

    expect(result).to include(ok: true, output: table)
    expect(result.dig(:verification, :byte_exact)).to be(true)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :table, source_role: :theirs, blocking: false)
    )
  end

  it 'attributes parse failures to the exact source role' do
    merge3 = provider.merge3(base_source: base, ours_source: "broken = [\n", theirs_source: ours)
    merge2 = provider.merge2(current_source: "alpha = 1\n", incoming_source: "broken = [\n")

    expect(merge3).to include(ok: false, source_role: :ours)
    expect(merge3.fetch(:diagnostics)).to include(hash_including(category: :parse_error, source_role: :ours))
    expect(merge2).to include(ok: false, source_role: :incoming)
    expect(merge2.fetch(:diagnostics)).to include(hash_including(category: :parse_error, source_role: :incoming))
  end
end

RSpec.describe 'Toml::Merge workflow provider conformance' do
  subject(:provider) { Toml::Merge.merge_provider }

  def parsed_root_pairs(source)
    TreeHaver.with_backend('kreuzberg-language-pack') do
      analysis = Toml::Merge::FileAnalysis.new(source)
      raise analysis.errors.map(&:to_s).join('; ') unless analysis.valid?

      analysis.root_pairs.to_h { |pair| [pair.key_name, pair.value_node.text] }
    end
  end

  let(:stable) { "stable = true\n" }
  let(:ours_add) { "stable = true\nours = 'left'\n" }
  let(:theirs_add) { "stable = true\ntheirs = [1, 2]\n" }
  let(:provider_conformance) do
    {
      dialect: :toml,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: ours_add },
        merge2: { current_source: ours_add, incoming_source: theirs_add },
        merge3: { base_source: stable, ours_source: ours_add, theirs_source: theirs_add }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "broken = [\n",
        theirs_source: theirs_add,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "obsolete = true\nstable = true\n",
          ours_source: "obsolete = true\nstable = true\n",
          theirs_source: stable
        },
        expected_value: parsed_root_pairs(stable)
      },
      parse_output: method(:parsed_root_pairs)
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
