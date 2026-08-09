# frozen_string_literal: true

module Ruby
  # Portable Ruby workflow integration.
  module Merge
    # Ruby workflow selector delegating source-preserving operations to Prism.
    class Provider
      BACKEND = :prism
      DELEGATED_PROVIDER_ID = 'ruby.ruby.prism'
      DEFAULT_PROFILE = :source_preserving

      def provider_id = 'ruby.ruby'
      def family = 'ruby'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[ruby],
          backends: [BACKEND],
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          source_preservation: Prism::Merge.merge_provider.capabilities.fetch(:source_preservation)
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
          family: :ruby,
          dialect: :ruby,
          backend: BACKEND,
          profile_id: DEFAULT_PROFILE
        )
      end

      def workflow_identity(request, delegated)
        {
          provider_id: provider_id,
          family: family,
          dialect: request[:dialect] || :ruby,
          backend: request[:backend] || BACKEND,
          package: PACKAGE_NAME,
          package_version: Ruby::Merge::Version::VERSION,
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
