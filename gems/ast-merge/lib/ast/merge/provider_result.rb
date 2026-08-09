# frozen_string_literal: true

module Ast
  module Merge
    # Constructs provider result envelopes and substrate-level failures.
    class ProviderResult
      DEFAULT_ENVELOPE = {
        provider: {}.freeze,
        profile: {}.freeze,
        diagnostics: [].freeze,
        changes: [].freeze,
        conflicts: [].freeze,
        fallbacks: [].freeze,
        render_report: {}.freeze,
        verification: {}.freeze
      }.freeze

      class << self
        def build(operation:, success:, envelope: {}, **payload)
          reserved_payload_fields = ProviderContract::REQUIRED_RESULT_FIELDS & payload.keys
          unless reserved_payload_fields.empty?
            raise ArgumentError, "Payload contains reserved fields: #{reserved_payload_fields.join(', ')}"
          end

          payload.merge(DEFAULT_ENVELOPE).merge(envelope).merge(
            schema: ProviderContract::RESULT_SCHEMA,
            operation: ProviderContract.normalize_operation(operation),
            ok: success
          )
        end

        def invalid_request(operation:, message:)
          failure(operation: operation, category: :invalid_request, message: message)
        end

        def unsupported(operation:, message:, selectors: {})
          failure(
            operation: operation,
            category: :unsupported_capability,
            message: message,
            profile: selectors
          )
        end

        private

        def failure(operation:, category:, message:, profile: {})
          build(
            operation: operation,
            success: false,
            envelope: {
              profile: profile,
              diagnostics: [{ category: category, severity: :error, message: message, blocking: true }]
            }
          )
        end
      end
    end
  end
end
