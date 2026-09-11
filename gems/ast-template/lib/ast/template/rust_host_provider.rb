# frozen_string_literal: true

require 'json'

module Ast
  module Template
    # Explicit report-only bridge for the portable Rust session contract.
    # Template execution and filesystem mutation remain Ruby-owned.
    class RustHostProvider
      PROVIDER_ID = 'rust.ast-template.session-reports'

      class << self
        def available?
          require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
          ::StructuredmergeHostPrototype.respond_to?(:report_ast_template_json)
        rescue LoadError
          false
        end
      end

      def provider_id = PROVIDER_ID

      def capabilities
        {
          operations: %i[options_report profile_report plan_report],
          backend: :rust_tslp,
          execution: :report_only,
          source_projection: :ruby_owned
        }.freeze
      end

      def report(request)
        raw = JSON.parse(host.report_ast_template_json(JSON.generate(request)))
        raw.transform_keys(&:to_sym)
      rescue KeyError, JSON::ParserError => e
        raise ArgumentError, e.message
      end

      def plan(request)
        report(request.merge(kind: 'plan'))
      end

      private

      def host
        require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
        ::StructuredmergeHostPrototype
      end
    end
  end
end
