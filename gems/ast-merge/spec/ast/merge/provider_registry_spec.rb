# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable Metrics/BlockLength -- provider protocol behavior is kept in one cohesive contract spec
RSpec.describe Ast::Merge::ProviderRegistry do
  subject(:registry) { described_class.new }

  let(:provider_class) do
    Class.new do
      attr_reader :requests

      # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists -- compact configurable provider test double
      def initialize(provider_id:, family:, role: :workflow, backends: [], dialects: [:json], priority: 0)
        @provider_id = provider_id
        @family = family
        @capabilities = {
          operations: %i[analyze diff2 merge2 merge3],
          dialects: dialects,
          backends: backends,
          profiles: [:default],
          role: role,
          priority: priority,
          source_preservation: [:comments]
        }
        @requests = []
      end
      # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

      attr_reader :provider_id, :family, :capabilities

      %i[analyze diff2 merge2 merge3].each do |operation|
        define_method(operation) do |request|
          @requests << [operation, request]
          Ast::Merge::ProviderResult.build(
            operation: operation,
            success: true,
            envelope: {
              provider: { provider_id: provider_id, family: family },
              verification: { base_participated: operation == :merge3 }
            },
            output: request.values_at(:base_source, :ours_source, :theirs_source).compact.join('|')
          )
        end
      end
    end
  end

  let(:workflow_provider) do
    provider_class.new(provider_id: 'ruby.json', family: 'json', backends: [:prism])
  end

  before do
    registry.register(workflow_provider)
  end

  it 'registers and resolves a workflow provider by family, dialect, and operation' do
    expect(
      registry.resolve(family: :json, dialect: :json, operation: :merge3)
    ).to equal(workflow_provider)
  end

  it 'selects an explicitly requested backend instead of the workflow provider' do
    backend_provider = provider_class.new(
      provider_id: 'ruby.json.alternate',
      family: 'json',
      role: :backend,
      backends: [:alternate]
    )
    registry.register(backend_provider)

    expect(
      registry.resolve(family: :json, dialect: :json, backend: :alternate, operation: :merge3)
    ).to equal(backend_provider)
  end

  it 'does not bypass dialect capabilities when resolving an explicit provider ID' do
    expect(
      registry.resolve(provider_id: 'ruby.json', dialect: :json5, operation: :merge3)
    ).to be_nil
  end

  it 'rejects duplicate provider IDs unless replacement is explicit' do
    replacement = provider_class.new(provider_id: 'ruby.json', family: 'json')

    expect { registry.register(replacement) }
      .to raise_error(Ast::Merge::ProviderContract::DuplicateProviderError)

    expect(registry.register(replacement, replace: true)).to equal(replacement)
    expect(registry.fetch('ruby.json').fetch(:provider)).to equal(replacement)
  end

  it 'rejects providers that do not implement every operation' do
    incomplete_provider = Object.new
    allow(incomplete_provider).to receive_messages(
      provider_id: 'ruby.incomplete',
      family: 'incomplete',
      capabilities: {}
    )

    expect { registry.register(incomplete_provider) }
      .to raise_error(Ast::Merge::ProviderContract::InvalidProviderError, /analyze, diff2, merge2, merge3/)
  end

  it 'dispatches merge3 with distinct base, ours, and theirs roles' do
    result = registry.dispatch(
      :merge3,
      family: :json,
      dialect: :json,
      base_source: '{"base":true}',
      ours_source: '{"ours":true}',
      theirs_source: '{"theirs":true}'
    )

    expect(result).to include(
      operation: :merge3,
      ok: true,
      output: '{"base":true}|{"ours":true}|{"theirs":true}'
    )
    expect(workflow_provider.requests.last).to match(
      [
        :merge3,
        hash_including(
          base_source: '{"base":true}',
          ours_source: '{"ours":true}',
          theirs_source: '{"theirs":true}'
        )
      ]
    )
  end

  {
    analyze: {
      source: 'source'
    },
    diff2: {
      before_source: 'before',
      after_source: 'after'
    },
    merge2: {
      incoming_source: 'incoming',
      current_source: 'current'
    }
  }.each do |operation, roles|
    it "dispatches #{operation} with its distinct source roles" do
      result = registry.dispatch(operation, { family: :json, dialect: :json }.merge(roles))

      expect(result).to include(operation: operation, ok: true)
      expect(workflow_provider.requests.last).to match([operation, hash_including(roles)])
    end

    it "rejects #{operation} when a required source role is missing" do
      result = registry.dispatch(operation, family: :json, dialect: :json)

      expect(result).to include(operation: operation, ok: false)
      expect(result.fetch(:diagnostics)).to include(hash_including(category: :invalid_request))
    end
  end

  it 'returns an invalid request result without invoking the provider when merge3 omits the base' do
    result = registry.dispatch(
      :merge3,
      family: :json,
      dialect: :json,
      ours_source: '{}',
      theirs_source: '{}'
    )

    expect(result).to include(operation: :merge3, ok: false)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :invalid_request))
    expect(workflow_provider.requests).to be_empty
  end

  it 'returns an unsupported result when no provider matches the requested dialect' do
    result = registry.dispatch(
      :merge3,
      family: :json,
      dialect: :json5,
      base_source: '{}',
      ours_source: '{}',
      theirs_source: '{}'
    )

    expect(result).to include(operation: :merge3, ok: false)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :unsupported_capability))
  end

  it 'rejects a successful merge3 result that does not verify base participation' do
    allow(workflow_provider).to receive(:merge3).and_return(
      Ast::Merge::ProviderResult.build(
        operation: :merge3,
        success: true,
        envelope: { provider: { provider_id: 'ruby.json', family: 'json' }, verification: {} }
      )
    )

    expect do
      registry.dispatch(
        :merge3,
        family: :json,
        dialect: :json,
        base_source: '{}',
        ours_source: '{}',
        theirs_source: '{}'
      )
    end.to raise_error(Ast::Merge::ProviderContract::InvalidResultError, /base_participated/)
  end

  it 'prevents operation payloads from overriding mandatory result fields' do
    expect do
      Ast::Merge::ProviderResult.build(operation: :analyze, success: true, ok: false)
    end.to raise_error(ArgumentError, /reserved fields: ok/)
  end
end
# rubocop:enable Metrics/BlockLength
