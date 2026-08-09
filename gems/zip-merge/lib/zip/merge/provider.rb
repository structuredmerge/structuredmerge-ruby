# frozen_string_literal: true

module Zip
  module Merge
    # Validates ZIP inputs while applying the safety-first opaque binary policy.
    # rubocop:disable Metrics/MethodLength -- provider envelope is one public result contract
    class Provider < Binary::Merge::Provider
      PARSE_ERRORS = [RuntimeError, NoMethodError, TypeError, KeyError].freeze

      def provider_id = 'ruby.zip'
      def family = 'zip'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[zip],
          backends: [Zip::Merge::BACKEND_REFERENCE.id.to_sym],
          profiles: %i[opaque_archive],
          role: :workflow,
          source_preservation: %i[exact_source opaque_conflict_retains_ours]
        }.freeze
      end

      def analyze(request)
        inventory = parse(request.fetch(:source), :source, :analyze, request)
        return inventory if provider_result?(inventory)

        result(:analyze, request, analysis: inventory)
      end

      def diff2(request)
        failure = validate_sources(request, :diff2, before_source: :before, after_source: :after)
        failure || super
      end

      def merge2(request)
        failure = validate_sources(request, :merge2, current_source: :current, incoming_source: :incoming)
        failure || super
      end

      def merge3(request)
        failure = validate_sources(
          request,
          :merge3,
          base_source: :base,
          ours_source: :ours,
          theirs_source: :theirs
        )
        failure || super
      end

      private

      def validate_sources(request, operation, roles)
        roles.each do |request_key, source_role|
          parsed = parse(request.fetch(request_key), source_role, operation, request)
          return parsed if provider_result?(parsed)
        end
        nil
      end

      def parse(source, source_role, operation, request)
        Zip::Merge.parse_zip_inventory(source)
      rescue *PARSE_ERRORS => e
        failure(
          operation,
          request,
          category: :parse_error,
          message: "Invalid ZIP #{source_role} source: #{e.message}",
          source_role: source_role
        )
      end

      def provider_result?(value)
        value.is_a?(Hash) && value[:schema] == Ast::Merge::ProviderContract::RESULT_SCHEMA
      end

      def envelope(request, **fields)
        {
          provider: {
            provider_id: provider_id,
            family: family,
            dialect: request[:dialect] || :zip,
            backend: request[:backend],
            package: 'zip-merge',
            package_version: Zip::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || :opaque_archive }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end

# Provider registration entry point.
module Zip
  # ZIP provider registration.
  module Merge
    module_function

    def merge_provider
      @merge_provider ||= Provider.new
    end

    def register_provider!
      Ast::Merge.register_provider(merge_provider, replace: true)
    end
  end
end
