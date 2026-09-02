# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- provider contract, conformance, and adversarial cases share one executable surface
RSpec.describe Psych::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) { "# retained\nalpha: base\nbeta: base\n" }
  let(:ours) { "# retained\nalpha: ours\nbeta: base\nours_only: left\n" }
  let(:theirs) { "# retained\nalpha: base\nbeta: theirs\ntheirs_only: right\n" }

  it 'advertises and auto-registers the Psych YAML backend provider' do
    expect(provider).to have_attributes(provider_id: 'ruby.yaml.psych', family: 'yaml')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[yaml],
      backends: %i[psych],
      profiles: %i[source_preserving],
      role: :backend
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.yaml.psych',
        family: :yaml,
        dialect: :yaml,
        backend: :psych,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Psych::Merge.merge_provider)
  end

  it 'analyzes ordered top-level mapping entries through Psych AST attributes' do
    result = provider.analyze(source: "plain: value\nquoted: \"value\"\nnested:\n  enabled: true\n")

    expect(result).to include(ok: true, operation: :analyze)
    expect(result.dig(:analysis, :backend)).to eq('psych')
    expect(result.dig(:analysis, :entries).map { |entry| entry[:key] }).to eq(%w[plain quoted nested])
    expect(result.dig(:analysis, :entries, 1, :attributes, :attributes, :quoted)).to be(true)
    expect(result.fetch(:extensions)).to contain_exactly(
      hash_including(
        schema: 'structuredmerge.extension/ruby-psych/v1',
        namespace: 'ruby-psych',
        capabilities: %w[aliases anchors documents scalar-styles tags],
        payload: hash_including(native_tree_visibility: 'provider_internal')
      )
    )
    expect(result.dig(:verification, :source_parsed)).to be(true)
  end

  it 'returns exact winner bytes only after validating the selected revision' do
    winner = "---\r\nalpha: \"theirs\" # exact\r\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: winner)

    expect(result).to include(ok: true, output: winner)
    expect(result.dig(:render_report, :strategy)).to eq(:exact_revision)
    expect(result.dig(:verification, :byte_exact)).to be(true)
    expect(result.dig(:verification, :source_role)).to eq(:theirs)
  end

  it 'keeps non-winning diagnostics nonblocking for an exact valid winner' do
    duplicate = "alpha: 1\nalpha: 2\n"
    result = provider.merge3(base_source: duplicate, ours_source: duplicate, theirs_source: "alpha: 3\n")

    expect(result).to include(ok: true, output: "alpha: 3\n")
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :duplicate_key, source_role: :base, blocking: false)
    )
  end

  it 'permits composite-unsafe YAML when an exact side wins byte-for-byte' do
    anchored = "defaults: &defaults\n  enabled: true\ncopy: *defaults\n"
    result = provider.merge3(base_source: base, ours_source: base, theirs_source: anchored)

    expect(result).to include(ok: true, output: anchored)
    expect(result.dig(:verification, :byte_exact)).to be(true)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :anchor, source_role: :theirs, blocking: false)
    )
  end

  it 'rejects an invalid exact winner' do
    invalid = "alpha: [\n"
    result = provider.merge3(base_source: base, ours_source: invalid, theirs_source: invalid)

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :parse_error, source_role: :ours, blocking: true)
    )
  end

  it 'preserves ours layout and comments while importing exact theirs entries in order' do
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(
      ok: true,
      output: "# retained\nalpha: ours\nbeta: theirs\nours_only: left\ntheirs_only: right\n"
    )
    expect(result.dig(:render_report, :strategy)).to eq(:exact_mapping_entry_composite)
    expect(result.dig(:render_report, :synthesized_fragments)).to be_empty
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

  it 'preserves exact nested value fragments and scalar styles' do
    stable = "left:\n  value: base\nright: 'base'\n"
    left = "left:\n  value: ours\nright: 'base'\n"
    right = "left:\n  value: base\nright: \"theirs\"\n"
    result = provider.merge3(base_source: stable, ours_source: left, theirs_source: right)

    expect(result).to include(ok: true, output: "left:\n  value: ours\nright: \"theirs\"\n")
    expect(result.dig(:verification, :source_match)).to be(true)
    expect(result.dig(:verification, :ast_attributes_match)).to be(true)
  end

  it 'combines base-aware add edit and delete decisions' do
    result = provider.merge3(
      base_source: "delete: yes\nedit: base\nkeep: yes\n",
      ours_source: "edit: base\nkeep: yes\nours: added\n",
      theirs_source: "delete: yes\nedit: theirs\nkeep: yes\ntheirs: added\n"
    )

    expect(result).to include(
      ok: true,
      output: "edit: theirs\nkeep: yes\nours: added\ntheirs: added\n"
    )
  end

  it 'synthesizes only a newline separator for a no-final-newline append' do
    result = provider.merge3(
      base_source: "stable: true\n",
      ours_source: "stable: true\nours: 1",
      theirs_source: "stable: true\ntheirs: 2\n"
    )

    expect(result).to include(ok: true, output: "stable: true\nours: 1\ntheirs: 2\n")
    expect(result.dig(:render_report, :synthesized_fragments)).to contain_exactly(
      hash_including(reason: :mapping_entry_separator)
    )
  end

  it 'localizes divergent same-key conflicts when comment ownership is provable' do
    stable = "stable: true\n# value docs\nvalue: base\ntail: true\n"
    left = "stable: true\n# left docs\nvalue: ours\ntail: true\n"
    right = "stable: true\n# right docs\nvalue: theirs\ntail: true\n"
    result = provider.merge3(base_source: stable, ours_source: left, theirs_source: right)

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicted_output)).to start_with("stable: true\n<<<<<<< ours\n")
    expect(result.fetch(:conflicted_output)).to include("# left docs\nvalue: ours\n")
    expect(result.fetch(:conflicted_output)).to end_with(">>>>>>> theirs\ntail: true\n")
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :edit_edit, path: '/value')
    )
    expect(result.dig(:render_report, :strategy)).to eq(:mapping_entry_localized_conflict)
  end

  it 'uses a full-file conflict when leading comment ownership is not provable' do
    result = provider.merge3(
      base_source: "# heading\nvalue: base\n",
      ours_source: "# ours heading\nvalue: ours\n",
      theirs_source: "# theirs heading\nvalue: theirs\n"
    )

    expect(result).to include(ok: false)
    expect(result.dig(:render_report, :strategy)).to eq(:full_file_conflict)
    expect(result.fetch(:fallbacks)).to include(hash_including(reason: :unmanaged_source_change))
  end

  it 'reports divergent deletion and edit as a public JSON-safe conflict' do
    result = provider.merge3(
      base_source: "stable: true\nvalue: base\n",
      ours_source: "stable: true\n",
      theirs_source: "stable: true\nvalue: theirs\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to include(hash_including(category: :delete_edit, path: '/value'))
    expect { JSON.generate(result) }.not_to raise_error
  end

  it 'rejects unsafe YAML features for composite merges with source roles' do
    unsafe_sources = {
      alias: "defaults: &defaults\n  enabled: true\ncopy: *defaults\n",
      merge_key: "base: &base\n  enabled: true\ncopy:\n  <<: *base\n",
      duplicate_key: "alpha: 1\nalpha: 2\n",
      multiple_documents: "---\nalpha: 1\n---\nbeta: 2\n",
      non_mapping_root: "- alpha\n- beta\n",
      directive: "%YAML 1.2\n---\nalpha: 1\n",
      flow_collection: "alpha: {nested: true}\n",
      complex_key: "? [alpha, beta]\n: value\n"
    }

    unsafe_sources.each do |category, source|
      result = provider.merge3(base_source: base, ours_source: source, theirs_source: ours)

      expect(result).to include(ok: false, source_role: :ours), category.to_s
      expect(result.fetch(:diagnostics)).to include(hash_including(source_role: :ours)), category.to_s
    end
  end

  it 'rejects independently changed unmanaged layout and comments' do
    result = provider.merge3(
      base_source: "# heading\nalpha: base\nbeta: base\n",
      ours_source: "# heading\n\nalpha: ours\nbeta: base\n",
      theirs_source: "# heading\nalpha: base\nbeta: theirs\n"
    )

    expect(result).to include(ok: false)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :unmanaged_source_change, path: '<document>')
    )
  end

  it 'rejects unsafe merge2 input and attributes the source role' do
    result = provider.merge2(current_source: "alpha: 1\n", incoming_source: "alpha: [\n")

    expect(result).to include(ok: false, source_role: :incoming)
    expect(result.fetch(:diagnostics)).to include(
      hash_including(category: :parse_error, source_role: :incoming)
    )
  end
end

RSpec.describe 'Psych::Merge provider conformance' do
  subject(:provider) { Psych::Merge.merge_provider }

  def parsed_mapping(source)
    Psych.safe_load(source, aliases: false).to_a
  end

  let(:stable) { "stable: true\n" }
  let(:ours_add) { "stable: true\nours: left\n" }
  let(:theirs_add) { "stable: true\ntheirs: right\n" }
  let(:provider_conformance) do
    {
      dialect: :yaml,
      backend: :psych,
      profile_id: :source_preserving,
      role: :backend,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: ours_add },
        merge2: { current_source: ours_add, incoming_source: theirs_add },
        merge3: { base_source: stable, ours_source: ours_add, theirs_source: theirs_add }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "broken: [\n",
        theirs_source: theirs_add,
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: "obsolete: true\nstable: true\n",
          ours_source: "obsolete: true\nstable: true\n",
          theirs_source: stable
        },
        expected_value: parsed_mapping(stable)
      },
      parse_output: method(:parsed_mapping)
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
