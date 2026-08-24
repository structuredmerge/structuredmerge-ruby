# frozen_string_literal: true

module Ast
  module Merge
    module RSpec
      # Executes the adversarial base-participation proof used by shared provider conformance.
      class ProviderConformance
        Result = Data.define(:passed, :provider_result, :actual_value, :expected_value)

        def initialize(provider:, request:, parse_output:, expected_value:)
          @provider = provider
          @request = request
          @parse_output = parse_output
          @expected_value = expected_value
        end

        def call
          provider_result = Ast::Merge::ProviderContract.validate_result!(:merge3, @provider.merge3(@request))
          actual_value = provider_result[:ok] ? @parse_output.call(provider_result.fetch(:output)) : nil
          Result.new(
            passed: provider_result[:ok] &&
              provider_result.dig(:verification, :base_participated) == true &&
              actual_value == @expected_value,
            provider_result: provider_result,
            actual_value: actual_value,
            expected_value: @expected_value
          )
        end
      end

      # Interprets the complete provider fixture as an executable advertising gate.
      class ProviderConformanceMatrix
        def initialize(fixture)
          @fixture = fixture.transform_keys(&:to_sym)
          @providers = @fixture.fetch(:providers)
          @conformance = @fixture.fetch(:executable_conformance)
        end

        def validate!
          provider_ids = @providers.map { |provider| fetch(provider, :provider_id) }
          covered = tested_provider_ids | blocked_provider_ids
          unless covered.sort == provider_ids.sort
            raise ArgumentError, 'Conformance matrix does not cover every provider'
          end
          raise ArgumentError, 'Conformance matrix contains unknown providers' unless (covered - provider_ids).empty?

          self
        end

        def tested_rows
          fetch(@conformance, :tested_rows)
        end

        def blocked_provider_ids
          fetch(@conformance, :blocked_provider_ids)
        end

        def advertised_provider_ids
          tested_provider_ids.sort.freeze
        end

        def tested?(provider_id:, dialect:, backend:, profile_id:)
          tested_rows.any? do |row|
            fetch(row, :provider_id) == provider_id.to_s &&
              fetch(row, :dialect) == dialect.to_s &&
              fetch(row, :backend) == backend.to_s &&
              fetch(row, :profile_id) == profile_id.to_s &&
              fetch(row, :status) == 'tested'
          end
        end

        private

        def tested_provider_ids
          tested_rows.filter_map do |row|
            next unless fetch(row, :status) == 'tested'

            fetch(row, :provider_id)
          end.uniq
        end

        def fetch(hash, key)
          hash.fetch(key) { hash.fetch(key.to_s) }
        end
      end
    end
  end
end
