# frozen_string_literal: true

require 'spec_helper'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- workflow behavior and shared provider conformance form one surface
RSpec.describe Yaml::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:backend) { :'kreuzberg-language-pack' }
  let(:base) { "obsolete: true\nstable: true\n" }
  let(:ours) { "obsolete: true\nstable: true\nours: left\n" }
  let(:theirs) { "stable: true\ntheirs: right\n" }

  it 'is the registered TSLP YAML workflow provider' do
    expect(provider).to have_attributes(provider_id: 'ruby.yaml', family: 'yaml')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[yaml],
      backends: [backend],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.yaml',
        family: :yaml,
        dialect: :yaml,
        backend: backend,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Yaml::Merge.merge_provider)
  end

  it 'uses the same substrate provider engine as parser-specific YAML providers' do
    expect(described_class.superclass).to equal(Yaml::Merge::SourcePreservingProvider)
  end

  it 'preserves exact source fragments for independent three-way additions' do
    result = provider.merge3(base_source: base, ours_source: ours, theirs_source: theirs)

    expect(result).to include(ok: true, output: "stable: true\nours: left\ntheirs: right\n")
    expect(result.dig(:render_report, :strategy)).to eq(:exact_mapping_entry_composite)
    expect(result.dig(:verification, :semantic_match)).to be(true)
    expect(result.dig(:verification, :base_participated)).to be(true)
  end

  it 'preserves comments and blank gaps during an exact merge2 replay' do
    source = "# retained\n\nstable: true # inline\n"
    result = provider.merge2(incoming_source: source, current_source: source)

    expect(result).to include(ok: true, output: source)
    expect(result.dig(:verification, :source_match)).to be(true)
  end

  it 'recursively adds template-only mapping leaves while retaining destination values' do
    incoming = <<~YAML
      patient:
        name:
          given: Pat
          family: Template
        active: false
    YAML
    current = <<~YAML
      patient:
        name:
          family: Destination
        active: true
    YAML
    expected = <<~YAML
      patient:
        name:
          given: Pat
          family: Destination
        active: true
    YAML

    result = provider.merge2(incoming_source: incoming, current_source: current)

    expect(result).to include(ok: true, output: expected)
    expect(result.dig(:render_report, :strategy)).to eq(:recursive_mapping_composite)
    expect(result.dig(:render_report, :synthesized_fragments)).to be_empty
    expect(result.dig(:verification, :semantic_match)).to be(true)
    expect(result.dig(:verification, :source_match)).to be(true)
  end
end

RSpec.describe 'Yaml::Merge workflow provider conformance' do
  subject(:provider) { Yaml::Merge.merge_provider }

  let(:stable) { "obsolete: true\nstable: true\n" }
  let(:provider_conformance) do
    {
      dialect: :yaml,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: "obsolete: true\nstable: false\n" },
        merge2: { current_source: stable, incoming_source: "added: true\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}ours: left\n",
          theirs_source: "#{stable}theirs: right\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "broken: [\n",
        theirs_source: "stable: true\n",
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: stable,
          ours_source: stable,
          theirs_source: "stable: true\n"
        },
        expected_value: { 'stable' => true }
      },
      parse_output: lambda { |source|
        result = Yaml::Merge.parse_yaml(source, 'yaml', backend: 'kreuzberg-language-pack')
        result.dig(:analysis, :document)
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
