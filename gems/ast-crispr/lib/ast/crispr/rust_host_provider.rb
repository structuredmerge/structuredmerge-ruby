# frozen_string_literal: true

require_relative 'typed_core_bridge'

module Ast
  module Crispr
    # Explicit profile and source-projection bridge to the Rust ast-crispr
    # kernel. Structural node selection remains owned by Ruby.
    class RustHostProvider
      include TypedCoreBridge
      PROVIDER_ID = 'rust.ast-crispr.profile'

      class << self
        def available?
          require 'structuredmerge_core' unless defined?(::StructuredmergeCore)
          %i[report_structural_boundary report_structural_limit report_structural_match
            report_structural_selection report_structural_destination report_structural_operations
            apply_explicit_source_edits].all? { |method| ::StructuredmergeCore.respond_to?(method) }
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

        core_report(request)
      rescue KeyError, ArgumentError, TypeError => e
        raise RuntimeError, e.message
      end

      def apply_source_edits(request)
        raise Error.new('Rust ast-crispr host is unavailable', code: 'ast_crispr_rust_host_unavailable') unless self.class.available?

        core_source_edits(request)
      rescue KeyError, ArgumentError, TypeError => e
        raise RuntimeError, e.message
      end
    end
  end
end
