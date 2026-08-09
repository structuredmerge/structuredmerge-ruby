# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ast/merge/rspec/shared_examples'

# rubocop:disable Metrics/BlockLength -- delegation identity, byte fidelity, and conformance form one contract
RSpec.describe Ruby::Merge::Provider do
  subject(:provider) { described_class.new }

  let(:base) { "OBSOLETE = true\nSTABLE = true\n" }
  let(:ours) { "OBSOLETE = true\nSTABLE = true\nOURS = :left\n" }
  let(:theirs) { "STABLE = true\nTHEIRS = :right\n" }

  it 'auto-registers the Ruby workflow while retaining the Prism backend registration' do
    expect(provider).to have_attributes(provider_id: 'ruby.ruby', family: 'ruby')
    expect(provider.capabilities).to include(
      operations: %i[analyze diff2 merge2 merge3],
      dialects: %i[ruby],
      backends: %i[prism],
      profiles: %i[source_preserving],
      role: :workflow
    )
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.ruby',
        family: :ruby,
        dialect: :ruby,
        backend: :prism,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Ruby::Merge.merge_provider)
    expect(
      Ast::Merge.resolve_provider(
        provider_id: 'ruby.ruby.prism',
        family: :ruby,
        dialect: :ruby,
        backend: :prism,
        profile_id: :source_preserving,
        operation: :merge3
      )
    ).to equal(Prism::Merge.merge_provider)
  end

  {
    analyze: { source: "STABLE = true\n" },
    diff2: { before_source: "STABLE = true\n", after_source: "STABLE = false\n" },
    merge2: { current_source: "STABLE = true\n", incoming_source: "ADDED = true\n" },
    merge3: {
      base_source: "STABLE = true\n",
      ours_source: "STABLE = true\nOURS = :left\n",
      theirs_source: "STABLE = true\nTHEIRS = :right\n"
    }
  }.each do |operation, operation_request|
    it "dispatches #{operation} to the exact Prism provider selector" do
      expect(Ast::Merge).to receive(:dispatch_provider).with(
        operation,
        hash_including(
          provider_id: 'ruby.ruby.prism',
          family: :ruby,
          dialect: :ruby,
          backend: :prism,
          profile_id: :source_preserving
        )
      ).and_call_original

      provider.public_send(
        operation,
        operation_request.merge(
          family: :ruby,
          dialect: :ruby,
          backend: :prism,
          profile_id: :source_preserving
        )
      )
    end
  end

  it 'contains no direct SmartMerger or two-way fallback path' do
    source = File.read(File.expand_path('../lib/ruby/merge/provider.rb', __dir__))

    expect(source).not_to include('SmartMerger', 'merge2(')
  end

  it 'changes only workflow identity while preserving delegated fields and bytes' do
    request = {
      base_source: base,
      ours_source: ours,
      theirs_source: theirs,
      family: :ruby,
      dialect: :ruby,
      backend: :prism,
      profile_id: :source_preserving
    }
    workflow = provider.merge3(request)
    delegated = Ast::Merge.dispatch_provider(
      :merge3,
      request.merge(provider_id: 'ruby.ruby.prism')
    )

    expect(workflow.except(:provider)).to eq(delegated.except(:provider))
    expect(workflow.dig(:provider, :provider_id)).to eq('ruby.ruby')
    expect(workflow.dig(:provider, :backend)).to eq(:prism)
    expect(workflow.dig(:provider, :delegated_provider)).to include(
      provider_id: 'ruby.ruby.prism',
      backend: :prism
    )
    expect(workflow.fetch(:output)).to eq("STABLE = true\nOURS = :left\nTHEIRS = :right\n")
    expect(workflow.dig(:verification, :base_participated)).to be(true)
    expect { JSON.generate(Ast::Merge.json_ready(workflow)) }.not_to raise_error
  end

  it 'preserves conflicted output and delegated diagnostics exactly' do
    request = {
      base_source: "VALUE = :base\n",
      ours_source: "VALUE = :ours\n",
      theirs_source: "VALUE = :theirs\n",
      family: :ruby,
      dialect: :ruby,
      backend: :prism,
      profile_id: :source_preserving
    }
    workflow = provider.merge3(request)
    delegated = Prism::Merge.merge_provider.merge3(request)

    expect(workflow.except(:provider)).to eq(delegated.except(:provider))
    expect(workflow.fetch(:conflicted_output)).to eq(delegated.fetch(:conflicted_output))
  end

  it 'attributes parse failures through the workflow selector' do
    result = Ast::Merge.dispatch_provider(
      :merge3,
      provider_id: 'ruby.ruby',
      family: :ruby,
      dialect: :ruby,
      backend: :prism,
      profile_id: :source_preserving,
      base_source: "STABLE = true\n",
      ours_source: "class Broken\n",
      theirs_source: "STABLE = true\nTHEIRS = :right\n"
    )

    expect(result).to include(ok: false, source_role: :ours)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :parse_error, message: /ours parse error/))
  end
end

RSpec.describe 'Ruby::Merge workflow provider conformance' do
  subject(:provider) { Ruby::Merge.merge_provider }

  let(:stable) { "OBSOLETE = true\nSTABLE = true\n" }
  let(:provider_conformance) do
    {
      dialect: :ruby,
      backend: :prism,
      profile_id: :source_preserving,
      role: :workflow,
      requests: {
        analyze: { source: stable },
        diff2: { before_source: stable, after_source: "OBSOLETE = true\nSTABLE = false\n" },
        merge2: { current_source: stable, incoming_source: "ADDED = true\n" },
        merge3: {
          base_source: stable,
          ours_source: "#{stable}OURS = :left\n",
          theirs_source: "#{stable}THEIRS = :right\n"
        }
      },
      invalid_merge3: {
        base_source: stable,
        ours_source: "class Broken\n",
        theirs_source: "STABLE = true\n",
        source_role: :ours
      },
      base_adversarial_merge3: {
        request: {
          base_source: stable,
          ours_source: stable,
          theirs_source: "STABLE = true\n"
        },
        expected_value: [:STABLE]
      },
      parse_output: lambda { |source|
        Prism.parse(source).value.statements.body.filter_map do |node|
          node.name if node.is_a?(Prism::ConstantWriteNode)
        end
      }
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'
end
# rubocop:enable Metrics/BlockLength
