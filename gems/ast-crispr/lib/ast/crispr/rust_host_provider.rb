# frozen_string_literal: true

require 'json'

module Ast
  module Crispr
    # Explicit profile/report bridge to the Rust ast-crispr kernel.
    # Source selection and edits remain owned by Ruby until their execution
    # envelope has equivalent source-projection semantics.
    class RustHostProvider
      PROVIDER_ID = 'rust.ast-crispr.profile'

      class << self
        def available?
          require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
          ::StructuredmergeHostPrototype.respond_to?(:report_ast_crispr_json)
        rescue LoadError
          false
        end
      end

      def provider_id = PROVIDER_ID

      def capabilities
        {
          operations: %i[boundary limit match selection destination operation batch_operations],
          backend: :rust_tslp,
          execution: :profile_reports_only,
          source_projection: :ruby_owned
        }.freeze
      end

      def report(request)
        raise Error.new('Rust ast-crispr host is unavailable', code: 'ast_crispr_rust_host_unavailable') unless self.class.available?

        JSON.parse(StructuredmergeHostPrototype.report_ast_crispr_json(JSON.generate(request)))
      rescue JSON::ParserError => e
        raise Error.new("Rust ast-crispr returned invalid JSON: #{e.message}", code: 'ast_crispr_rust_host_invalid_response')
      end
    end
  end
end
