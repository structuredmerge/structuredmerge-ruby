# frozen_string_literal: true

module Ast
  module Merge
    # Validation and normalization for the portable merge-provider protocol.
    # rubocop:disable Metrics/ModuleLength -- protocol constants and validators form one public contract
    module ProviderContract
      OPERATIONS = %i[analyze diff2 merge2 merge3].freeze
      REQUIRED_METHODS = %i[provider_id family capabilities analyze diff2 merge2 merge3].freeze
      REQUEST_ROLES = {
        analyze: %i[source],
        diff2: %i[before_source after_source],
        merge2: %i[incoming_source current_source],
        merge3: %i[base_source ours_source theirs_source]
      }.freeze
      REQUIRED_RESULT_FIELDS = %i[
        schema
        operation
        ok
        provider
        profile
        diagnostics
        changes
        conflicts
        fallbacks
        render_report
        verification
      ].freeze
      REQUIRED_CAPABILITY_FIELDS = %i[
        operations
        dialects
        backends
        profiles
        role
        source_preservation
      ].freeze
      RESULT_SCHEMA = 'https://structuredmerge.org/schemas/provider-result/v1.json'
      PROVIDER_ROLES = %i[workflow backend].freeze

      class Error < Ast::Merge::Error; end
      class InvalidProviderError < Error; end
      class DuplicateProviderError < Error; end
      class InvalidRequestError < Error; end
      class InvalidResultError < Error; end

      module_function

      def validate_provider!(provider)
        validate_provider_methods!(provider)
        provider_id, family = validate_provider_identity!(provider)
        capabilities = normalize_hash(provider.capabilities)
        validate_capability_fields!(capabilities)
        operations = validate_operations!(capabilities[:operations])
        role = validate_role!(capabilities[:role])

        provider_registration(provider_id, family, capabilities, operations: operations, role: role)
      end

      def validate_request!(operation, request)
        operation = normalize_operation(operation)
        normalized = normalize_hash(request)
        validate_request_roles!(operation, normalized)
        if normalized[:provider_id].nil? && blank?(normalized[:family])
          raise InvalidRequestError, "#{operation} request requires family or provider_id"
        end

        normalized.freeze
      end

      def validate_result!(operation, result)
        operation = normalize_operation(operation)
        normalized = normalize_hash(result)
        validate_result_fields!(operation, normalized)
        validate_result_operation!(operation, normalized[:operation])
        validate_result_outcome!(operation, normalized)
        normalized.freeze
      end

      def normalize_operation(operation)
        normalized = normalize_identifier(operation).to_sym
        unless OPERATIONS.include?(normalized)
          raise InvalidRequestError, "Unknown provider operation: #{operation.inspect}"
        end

        normalized
      end

      def normalize_hash(value)
        raise ArgumentError, "Expected Hash, got #{value.class}" unless value.is_a?(Hash)

        value.to_h do |key, item|
          normalized_key = key.respond_to?(:to_sym) ? key.to_sym : key
          [normalized_key, item]
        end
      end

      def normalize_identifier(value)
        value.to_s.strip
      end

      def normalize_identifiers(values)
        Array(values).map { |value| normalize_identifier(value).to_sym }.uniq.freeze
      end

      def blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def truthy_key?(value, key)
        value.is_a?(Hash) && (value[key] == true || value[key.to_s] == true)
      end

      def validate_provider_methods!(provider)
        missing = REQUIRED_METHODS.reject { |method_name| provider.respond_to?(method_name) }
        raise InvalidProviderError, "Provider is missing required methods: #{missing.join(', ')}" unless missing.empty?
      end

      def validate_provider_identity!(provider)
        provider_id = normalize_identifier(provider.provider_id)
        family = normalize_identifier(provider.family)
        raise InvalidProviderError, 'provider_id must not be empty' if provider_id.empty?
        raise InvalidProviderError, 'family must not be empty' if family.empty?

        [provider_id, family.to_sym]
      end

      def validate_capability_fields!(capabilities)
        missing = REQUIRED_CAPABILITY_FIELDS.reject { |field| capabilities.key?(field) }
        raise InvalidProviderError, "Provider capabilities are missing: #{missing.join(', ')}" unless missing.empty?
      end

      def validate_operations!(values)
        operations = normalize_identifiers(values)
        unknown = operations - OPERATIONS
        raise InvalidProviderError, "Unknown provider operations: #{unknown.join(', ')}" unless unknown.empty?
        unless operations.sort == OPERATIONS.sort
          raise InvalidProviderError, "Provider must implement all operations: #{OPERATIONS.join(', ')}"
        end

        operations
      end

      def validate_role!(value)
        role = normalize_identifier(value).to_sym
        raise InvalidProviderError, "Unknown provider role: #{role}" unless PROVIDER_ROLES.include?(role)

        role
      end

      def normalized_capabilities(capabilities, operations:, role:)
        capabilities.merge(
          operations: operations,
          dialects: normalize_identifiers(capabilities[:dialects]),
          backends: normalize_identifiers(capabilities[:backends]),
          profiles: normalize_identifiers(capabilities[:profiles]),
          role: role
        ).freeze
      end

      def provider_registration(provider_id, family, capabilities, operations:, role:)
        {
          provider_id: provider_id,
          family: family,
          capabilities: normalized_capabilities(capabilities, operations: operations, role: role)
        }.freeze
      end

      def validate_request_roles!(operation, request)
        missing = REQUEST_ROLES.fetch(operation).select { |role| !request.key?(role) || request[role].nil? }
        raise InvalidRequestError, "#{operation} request is missing roles: #{missing.join(', ')}" unless missing.empty?
      end

      def validate_result_fields!(operation, result)
        missing = REQUIRED_RESULT_FIELDS.reject { |field| result.key?(field) }
        raise InvalidResultError, "#{operation} result is missing fields: #{missing.join(', ')}" unless missing.empty?
      end

      def validate_result_operation!(expected, actual)
        return if normalize_identifier(actual).to_sym == expected

        raise InvalidResultError, "Expected #{expected} result, got #{actual.inspect}"
      end

      def validate_result_outcome!(operation, result)
        unless [true, false].include?(result[:ok])
          raise InvalidResultError, "#{operation} result ok must be true or false"
        end
        return unless operation == :merge3 && result[:ok]
        return if truthy_key?(result[:verification], :base_participated)

        raise InvalidResultError, 'Successful merge3 result must verify base_participated'
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
