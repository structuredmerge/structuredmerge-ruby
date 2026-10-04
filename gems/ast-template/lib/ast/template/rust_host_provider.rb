# frozen_string_literal: true

require_relative 'typed_core_bridge'

module Ast
  module Template
    # Explicit report-only bridge for the portable Rust session contract.
    # Template execution and filesystem mutation remain Ruby-owned.
    class RustHostProvider
      include TypedCoreBridge
      PROVIDER_ID = 'rust.ast-template.session-reports'

      class << self
        def available?
          require 'structuredmerge_core' unless defined?(::StructuredmergeCore)
          %i[report_template_options report_template_profile plan_template_directory].all? do |name|
            ::StructuredmergeCore.respond_to?(name)
          end
        rescue LoadError
          false
        end
      end

      def provider_id = PROVIDER_ID

      def capabilities
        {
          operations: %i[options_report profile_report plan_report],
          backend: :rust_tslp,
          execution: :report_and_plan_only,
          source_projection: :ruby_owned
        }.freeze
      end

      def report(request)
        core_report(request)
      rescue KeyError, ArgumentError, TypeError => e
        raise RuntimeError, e.message
      end

      def plan(request)
        report(request.merge(kind: 'plan'))
      end

      private

      def host
        require 'structuredmerge_core' unless defined?(::StructuredmergeCore)
        ::StructuredmergeCore
      end
    end
  end
end
