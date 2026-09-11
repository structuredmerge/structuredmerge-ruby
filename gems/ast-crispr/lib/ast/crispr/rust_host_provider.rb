# frozen_string_literal: true

require 'json'

module Ast
  module Crispr
    # Explicit profile and source-projection bridge to the Rust ast-crispr
    # kernel. Structural node selection remains owned by Ruby.
    class RustHostProvider
      PROVIDER_ID = 'rust.ast-crispr.profile'

      class << self
        def available?
          require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
          ::StructuredmergeHostPrototype.respond_to?(:report_ast_crispr_json) &&
            ::StructuredmergeHostPrototype.respond_to?(:apply_ast_crispr_source_edits_json)
        rescue LoadError
          false
        end
      end

      def provider_id = PROVIDER_ID

      def capabilities
        {
          operations: %i[boundary limit match selection destination operation batch_operations explicit_source_edits],
          backend: :rust_tslp,
          execution: :profile_reports_and_explicit_source_edits,
          source_projection: :explicit_byte_ranges,
          structural_selection: :ruby_owned
        }.freeze
      end

      def report(request)
        raise Error.new('Rust ast-crispr host is unavailable', code: 'ast_crispr_rust_host_unavailable') unless self.class.available?

        JSON.parse(StructuredmergeHostPrototype.report_ast_crispr_json(JSON.generate(request)))
      rescue JSON::ParserError => e
        raise Error.new("Rust ast-crispr returned invalid JSON: #{e.message}", code: 'ast_crispr_rust_host_invalid_response')
      end

      def apply_source_edits(request)
        raise Error.new('Rust ast-crispr host is unavailable', code: 'ast_crispr_rust_host_unavailable') unless self.class.available?

        JSON.parse(StructuredmergeHostPrototype.apply_ast_crispr_source_edits_json(JSON.generate(request)))
      rescue JSON::ParserError => e
        raise Error.new("Rust ast-crispr returned invalid JSON: #{e.message}", code: 'ast_crispr_rust_host_invalid_response')
      end
    end
  end
end
