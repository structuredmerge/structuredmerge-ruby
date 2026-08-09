# frozen_string_literal: true

module Yaml
  # Portable YAML workflow integration.
  module Merge
    # YAML workflow selector delegating source-preserving operations to Psych.
    class Provider
      BACKEND = :'kreuzberg-language-pack'
      DELEGATED_BACKEND = :psych
      DELEGATED_PROVIDER_ID = 'ruby.yaml.psych'
      DEFAULT_PROFILE = :source_preserving

      def provider_id = 'ruby.yaml'
      def family = 'yaml'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[yaml],
          backends: [BACKEND],
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          source_preservation: Psych::Merge.merge_provider.capabilities.fetch(:source_preservation)
        }.freeze
      end

      Ast::Merge::ProviderContract::OPERATIONS.each do |operation|
        define_method(operation) do |request|
          delegated = Ast::Merge.dispatch_provider(operation, delegated_request(request))
          delegated.merge(provider: workflow_identity(request, delegated))
        end
      end

      private

      def delegated_request(request)
        request.merge(
          provider_id: DELEGATED_PROVIDER_ID,
          family: :yaml,
          dialect: :yaml,
          backend: DELEGATED_BACKEND,
          profile_id: DEFAULT_PROFILE
        )
      end

      def workflow_identity(request, delegated)
        {
          provider_id: provider_id,
          family: family,
          dialect: request[:dialect] || :yaml,
          backend: request[:backend] || BACKEND,
          package: PACKAGE_NAME,
          package_version: Yaml::Merge::Version::VERSION,
          delegated_provider: delegated_identity(delegated.fetch(:provider))
        }
      end

      def delegated_identity(identity)
        {
          provider_id: identity.fetch(:provider_id),
          backend: identity.fetch(:backend),
          package: identity[:package],
          package_version: identity[:package_version]
        }.compact
      end
    end

    class << self
      def merge_provider
        @merge_provider ||= Provider.new
      end

      def register_provider!(replace: false)
        Ast::Merge.register_provider(merge_provider, replace: replace)
      end
    end
  end
end
