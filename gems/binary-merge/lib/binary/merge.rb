# frozen_string_literal: true

require 'tree_haver'

module Binary
  module Merge
    PACKAGE_NAME = 'binary-merge'

    module_function

    def binary_feature_profile
      {
        family: 'binary',
        supported_dialects: [],
        supported_policies: []
      }
    end

    def render_policy(schema_path:, byte_range:, operation:, disposition:, reason:)
      TreeHaver::BinaryRenderPolicy.new(
        schema_path: schema_path,
        byte_range: byte_range,
        operation: operation,
        disposition: disposition,
        reason: reason
      )
    end

    def unsafe_diagnostic(schema_path:, byte_range:, message:, category: 'unsafe_binary_mutation')
      TreeHaver::BinaryDiagnostic.new(
        severity: 'error',
        category: category,
        message: message,
        schema_path: schema_path,
        byte_range: byte_range
      )
    end

    def preservation_report(format:, schema:, matched_schema_paths:, preserved_ranges:)
      TreeHaver::BinaryMergeReport.new(
        format: format,
        schema: schema,
        matched_schema_paths: matched_schema_paths,
        preserved_ranges: preserved_ranges,
        rewritten_nodes: [],
        checksum_updates: [],
        nested_dispatches: [],
        diagnostics: []
      )
    end
  end
end
