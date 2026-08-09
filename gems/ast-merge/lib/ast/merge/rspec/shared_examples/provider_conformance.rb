# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- complete executable provider contract is intentionally shared
RSpec.shared_examples 'Ast::Merge::ProviderConformance' do
  let(:provider_capabilities) { provider.capabilities }
  let(:provider_selectors) do
    {
      provider_id: provider.provider_id,
      family: provider.family,
      dialect: provider_conformance.fetch(:dialect),
      backend: provider_conformance.fetch(:backend),
      profile_id: provider_conformance.fetch(:profile_id)
    }
  end

  before do
    Ast::Merge.register_provider(provider, replace: true)
  end

  it 'validates and resolves every advertised selector in the conformance row' do
    registration = Ast::Merge::ProviderContract.validate_provider!(provider)

    expect(registration.fetch(:capabilities)).to include(
      operations: Ast::Merge::ProviderContract::OPERATIONS,
      role: provider_conformance.fetch(:role)
    )
    expect(provider_capabilities.fetch(:dialects)).to include(provider_conformance.fetch(:dialect))
    expect(provider_capabilities.fetch(:backends)).to include(provider_conformance.fetch(:backend))
    expect(provider_capabilities.fetch(:profiles)).to include(provider_conformance.fetch(:profile_id))
    expect(Ast::Merge.resolve_provider(**provider_selectors, operation: :merge3)).to equal(provider)
  end

  it 'executes every advertised operation with its required source roles' do
    provider_conformance.fetch(:requests).each do |operation, request|
      result = Ast::Merge.dispatch_provider(operation, provider_selectors.merge(request))

      expect(result.fetch(:ok)).to be(true), "#{provider.provider_id} advertised unsupported #{operation}"
      expect(result.fetch(:operation)).to eq(operation)
      expect(result.fetch(:diagnostics)).to be_an(Array)
      expect(Ast::Merge::ProviderContract.validate_result!(operation, result)).to eq(result)
    end
  end

  it 'reports missing request roles instead of invoking another operation' do
    provider_conformance.fetch(:requests).each_key do |operation|
      result = Ast::Merge.dispatch_provider(operation, provider_selectors)

      expect(result).to include(ok: false, operation: operation)
      expect(result.fetch(:diagnostics)).to contain_exactly(
        hash_including(category: :invalid_request)
      )
    end
  end

  it 'reports a source-role parse diagnostic' do
    invalid = provider_conformance.fetch(:invalid_merge3)
    result = Ast::Merge.dispatch_provider(:merge3, provider_selectors.merge(invalid))

    expect(result).to include(ok: false, source_role: invalid.fetch(:source_role))
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :parse_error))
  end

  it 'uses the base in an adversarial merge3 that merge2 substitution gets wrong' do
    adversarial = provider_conformance.fetch(:base_adversarial_merge3)
    proof = Ast::Merge::RSpec::ProviderConformance.new(
      provider: provider,
      request: provider_selectors.merge(adversarial.fetch(:request)),
      parse_output: provider_conformance.fetch(:parse_output),
      expected_value: adversarial.fetch(:expected_value)
    ).call
    result = proof.provider_result

    expect(proof.passed).to be(true)
    expect(result.dig(:verification, :base_participated)).to be(true)
    expect(proof.actual_value).to eq(adversarial.fetch(:expected_value))
  end

  it 'reports source preservation, synthesis, reparsing, and semantic verification' do
    synthesis = provider_conformance.fetch(:synthesized_merge3)
    result = Ast::Merge.dispatch_provider(:merge3, provider_selectors.merge(synthesis.fetch(:request)))

    expect(result).to include(ok: true)
    expect(result.dig(:verification, :output_reparsed)).to be(true)
    expect(result.dig(:verification, :semantic_match)).to be(true)
    expect(result.dig(:render_report, :synthesized_fragments)).not_to be_empty
    expect(result.dig(:render_report, :line_records)).not_to be_empty
  end

  it 'rejects selectors outside advertised dialect capabilities' do
    request = provider_selectors.merge(
      provider_conformance.fetch(:requests).fetch(:merge3),
      dialect: :unadvertised
    )
    result = Ast::Merge.dispatch_provider(:merge3, request)

    expect(result).to include(ok: false, operation: :merge3)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :unsupported_capability)
    )
  end
end
# rubocop:enable Metrics/BlockLength
