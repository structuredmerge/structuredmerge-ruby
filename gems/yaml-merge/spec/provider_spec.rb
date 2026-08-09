# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- delegation identity, byte fidelity, and conformance form one contract
RSpec.describe Yaml::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) { "obsolete: true\nstable: true\n" }
  let(:ours) { "obsolete: true\nstable: true\nours: left\n" }
  let(:theirs) { "stable: true\ntheirs: right\n" }

  it 'auto-registers the YAML workflow while retaining the Psych backend registration' do
    expect(provider).to have_attributes(provider_id: 'ruby.yaml', family: 'yaml')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[yaml],
      backends: [:'kreuzberg-language-pack'],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.yaml',
        family: :yaml,
        dialect: :yaml,
        backend: :'kreuzberg-language-pack',
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Yaml::Merge.merge_provider)
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

  {
    analyze: { source: "stable: true\n" },
    diff2: { before_source: "stable: true\n", after_source: "stable: false\n" },
    merge2: { current_source: "stable: true\n", incoming_source: "added: true\n" },
    merge3: {
      base_source: "stable: true\n",
      ours_source: "stable: true\nours: left\n",
      theirs_source: "stable: true\ntheirs: right\n"
    }
  }.each do |operation, operation_request|
    it "dispatches #{operation} to the exact Psych provider selector" do
      expect(Yaml::Merge::SmartMerger).not_to receive(:new)
      expect(Ast::Merge).to receive(:dispatch_provider).with(
        operation,
        hash_including(
          provider_id: 'ruby.yaml.psych',
          family: :yaml,
          dialect: :yaml,
          backend: :psych,
          profile_id: :source_preserving
        )
      ).and_call_original

      provider.public_send(
        operation,
        operation_request.merge(
          family: :yaml,
          dialect: :yaml,
          backend: :'kreuzberg-language-pack',
          profile_id: :source_preserving
        )
      )
    end
  end

  it 'changes only workflow identity while preserving delegated fields and bytes' do
    workflow = provider.merge3(
      base_source: base,
      ours_source: ours,
      theirs_source: theirs,
      family: :yaml,
      dialect: :yaml,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving
    )
    delegated = Ast::Merge.dispatch_provider(
      :merge3,
      base_source: base,
      ours_source: ours,
      theirs_source: theirs,
      provider_id: 'ruby.yaml.psych',
      family: :yaml,
      dialect: :yaml,
      backend: :psych,
      profile_id: :source_preserving
    )

    expect(workflow.except(:provider)).to eq(delegated.except(:provider))
    expect(workflow.dig(:provider, :provider_id)).to eq('ruby.yaml')
    expect(workflow.dig(:provider, :backend)).to eq(:'kreuzberg-language-pack')
    expect(workflow.dig(:provider, :delegated_provider)).to include(
      provider_id: 'ruby.yaml.psych',
      backend: :psych
    )
    expect(workflow.fetch(:output)).to eq("stable: true\nours: left\ntheirs: right\n")
    expect(workflow.dig(:verification, :base_participated)).to be(true)
    expect { JSON.generate(Ast::Merge.json_ready(workflow)) }.not_to raise_error
  end

  it 'preserves conflicted output and delegated diagnostics exactly' do
    request = {
      base_source: "value: base\n",
      ours_source: "value: ours\n",
      theirs_source: "value: theirs\n",
      family: :yaml,
      dialect: :yaml,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving
    }
    workflow = provider.merge3(request)
    delegated = Psych::Merge.merge_provider.merge3(request.merge(backend: :psych))

    expect(workflow.except(:provider)).to eq(delegated.except(:provider))
    expect(workflow.fetch(:conflicted_output)).to eq(delegated.fetch(:conflicted_output))
  end

  it 'attributes parse failures through the workflow selector' do
    result = Ast::Merge.dispatch_provider(
      :merge3,
      provider_id: 'ruby.yaml',
      family: :yaml,
      dialect: :yaml,
      backend: :'kreuzberg-language-pack',
      profile_id: :source_preserving,
      base_source: "stable: true\n",
      ours_source: "broken: [\n",
      theirs_source: "stable: true\ntheirs: right\n"
    )

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :parse_error, source_role: :ours))
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
        expected_value: Psych.safe_load("stable: true\n")
      },
      parse_output: ->(source) { Psych.safe_load(source) }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
