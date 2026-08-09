# frozen_string_literal: true

module Ast
  module Merge
    # Registers providers and dispatches portable merge operations.
    # rubocop:disable Metrics/ClassLength -- registry selection and dispatch remain one cohesive boundary
    class ProviderRegistry
      @default_mutex = Mutex.new

      class << self
        def default
          @default_mutex.synchronize { @default ||= new }
        end
      end

      def initialize
        @mutex = Mutex.new
        @registrations = {}
      end

      def register(provider, replace: false)
        registration = ProviderContract.validate_provider!(provider)
        provider_id = registration.fetch(:provider_id)

        @mutex.synchronize do
          if @registrations.key?(provider_id) && !replace
            raise ProviderContract::DuplicateProviderError, "Provider already registered: #{provider_id}"
          end

          @registrations[provider_id] = registration.merge(provider: provider).freeze
        end
        provider
      end

      def fetch(provider_id)
        @mutex.synchronize { @registrations[provider_id.to_s] }
      end

      def providers
        @mutex.synchronize do
          @registrations.values.sort_by { |registration| registration.fetch(:provider_id) }
        end
      end

      # rubocop:disable Metrics/ParameterLists -- selectors mirror the portable request envelope
      def resolve(provider_id: nil, family: nil, dialect: nil, backend: nil, profile_id: nil, operation: nil)
        selectors = normalize_selectors(
          family: family,
          dialect: dialect,
          backend: backend,
          profile_id: profile_id,
          operation: operation
        )
        return resolve_by_id(provider_id, selectors) if provider_id

        candidates = providers.select { |registration| matches?(registration, selectors) }
        candidates.min_by { |registration| preference(registration, selectors) }&.fetch(:provider)
      end
      # rubocop:enable Metrics/ParameterLists

      def dispatch(operation, request)
        operation = ProviderContract.normalize_operation(operation)
        normalized_request = validate_request(operation, request)
        return normalized_request if invalid_request_result?(normalized_request)

        provider = resolve_for_request(operation, normalized_request)
        return unsupported_result(operation, normalized_request) unless provider

        result = provider.public_send(operation, normalized_request)
        ProviderContract.validate_result!(operation, result)
      end

      def clear
        @mutex.synchronize { @registrations.clear }
        self
      end

      private

      def resolve_by_id(provider_id, selectors)
        registration = fetch(provider_id)
        return unless registration && selector_match?(registration, selectors)

        registration.fetch(:provider)
      end

      def matches?(registration, selectors)
        return false unless selector_match?(registration, selectors)

        capabilities = registration.fetch(:capabilities)
        if selectors[:backend]
          capabilities.fetch(:backends).include?(selectors[:backend])
        else
          capabilities.fetch(:role) == :workflow
        end
      end

      def preference(registration, selectors)
        capabilities = registration.fetch(:capabilities)
        backend_penalty = selectors[:backend] && !capabilities.fetch(:backends).include?(selectors[:backend]) ? 1 : 0
        priority = Integer(capabilities.fetch(:priority, 0))
        [backend_penalty, -priority, registration.fetch(:provider_id)]
      end

      def selector_match?(registration, selectors)
        capabilities = registration.fetch(:capabilities)
        family_matches?(registration, selectors[:family]) &&
          capability_matches?(capabilities, :operations, selectors[:operation]) &&
          capability_matches?(capabilities, :dialects, selectors[:dialect]) &&
          capability_matches?(capabilities, :backends, selectors[:backend]) &&
          capability_matches?(capabilities, :profiles, selectors[:profile_id])
      end

      def family_matches?(registration, family)
        family.nil? || registration.fetch(:family) == family
      end

      def capability_matches?(capabilities, key, requested)
        requested.nil? || capabilities.fetch(key).include?(requested)
      end

      def normalize_selectors(family:, dialect:, backend:, profile_id:, operation:)
        {
          family: normalize_selector(family),
          dialect: normalize_selector(dialect),
          backend: normalize_selector(backend),
          profile_id: normalize_selector(profile_id),
          operation: operation && ProviderContract.normalize_operation(operation)
        }
      end

      def normalize_selector(value)
        return if ProviderContract.blank?(value)

        value.to_s.strip.to_sym
      end

      def validate_request(operation, request)
        ProviderContract.validate_request!(operation, request)
      rescue ProviderContract::InvalidRequestError => e
        ProviderResult.invalid_request(operation: operation, message: e.message)
      end

      def invalid_request_result?(value)
        value[:operation] && value[:ok] == false
      end

      def resolve_for_request(operation, request)
        resolve(
          provider_id: request[:provider_id],
          family: request[:family],
          dialect: request[:dialect],
          backend: request[:backend],
          profile_id: request[:profile_id],
          operation: operation
        )
      end

      def selection_fields(request)
        request.slice(:provider_id, :family, :dialect, :backend, :profile_id).compact
      end

      def selection_summary(request)
        selection_fields(request).map { |key, value| "#{key}=#{value.inspect}" }.join(', ')
      end

      def unsupported_result(operation, request)
        ProviderResult.unsupported(
          operation: operation,
          message: "No provider matches #{selection_summary(request)}",
          selectors: selection_fields(request)
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
