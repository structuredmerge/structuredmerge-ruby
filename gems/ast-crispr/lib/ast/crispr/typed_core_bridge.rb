# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Ast
  module Crispr
    # Transport adaptation only. Classification and rendering are core-owned;
    # this adapter never selects AST nodes or writes files.
    module TypedCoreBridge
      REQUEST_FIELDS = {
        'match' => %w[start_boundary end_boundary payload_kind],
        'selection' => %w[owner_scope owner_selector selector_kind selection_intent comment_region include_trailing_gap],
        'destination' => %w[resolution_kind resolution_source anchor_boundary used_if_missing],
        'operation' => %w[operation_kind source_requirement destination_requirement replacement_source captures_source_text supports_if_missing]
      }.freeze
      REPORT_FIELDS = {
        'match' => %w[start_boundary start_boundary_family known_start_boundary end_boundary end_boundary_family known_end_boundary payload_kind payload_family known_payload_kind comment_anchored trailing_gap_extended],
        'selection' => %w[owner_scope owner_selector owner_selector_family known_owner_selector selector_kind selector_kind_family known_selector_kind selection_intent selection_intent_family known_selection_intent comment_region comment_region_family known_comment_region comment_anchored include_trailing_gap],
        'destination' => %w[resolution_kind resolution_family known_resolution_kind resolution_source resolution_source_family known_resolution_source anchor_boundary anchor_boundary_family known_anchor_boundary used_if_missing append_fallback anchored],
        'operation' => %w[operation_kind operation_family known_operation_kind source_requirement known_source_requirement destination_requirement known_destination_requirement replacement_source known_replacement_source captures_source_text supports_if_missing selects_source requires_source supports_destination requires_destination explicit_replacement may_reuse_captured_text]
      }.freeze
      FLAGS = %w[include_trailing_gap used_if_missing captures_source_text supports_if_missing].freeze
      OPERATORS = { '==' => 'equal', '!=' => 'not_equal', '<=' => 'at_most', '>=' => 'at_least', '<' => 'less_than', '>' => 'greater_than' }.freeze

      def core_report(request)
        request = request.transform_keys(&:to_s)
        kind = request.fetch('kind')
        case kind
        when 'boundary'
          boundary_hash(StructuredmergeCore.report_structural_boundary)
        when 'limit'
          spec = request['spec']
          constraints = spec.nil? ? nil : limit_constraints(spec)
          result = StructuredmergeCore.report_structural_limit(StructuredmergeCore::CrisprLimitRequest.new(constraints: constraints, counts: []))
          { 'description' => result.description }
        when 'batch_operations', 'operation'
          operations = kind == 'operation' ? [request] : request.fetch('operations')
          result = StructuredmergeCore.report_structural_operations(operations.map { |item| profile_request('operation', item.transform_keys(&:to_s)) })
          profiles = result.operation_profiles.map { |profile| report_hash('operation', profile) }
          kind == 'operation' ? profiles.first : { 'operation_count' => result.operation_count, 'operation_kinds' => result.operation_kinds, 'operation_profiles' => profiles }
        when 'match', 'selection', 'destination'
          result = StructuredmergeCore.public_send("report_structural_#{kind}", profile_request(kind, request))
          report_hash(kind, result)
        else
          raise ArgumentError, "unsupported ast-crispr report kind #{kind.inspect}"
        end
      end

      def core_source_edits(request)
        request = request.transform_keys(&:to_s)
        source = request.fetch('source').dup.force_encoding(Encoding::UTF_8)
        raise ArgumentError, 'source must be valid UTF-8' unless source.valid_encoding?

        edits = request.fetch('edits').map do |entry|
          entry = entry.transform_keys(&:to_s)
          StructuredmergeCore::ExplicitSourceEdit.new(start_byte: entry.fetch('start_byte'),
            end_byte: entry.fetch('end_byte'), replacement: entry.fetch('replacement'))
        end
        crlf = source.scan("\r\n").length
        descriptor = StructuredmergeCore::SourceDescriptor.new(source_id: 'explicit-source', role: 'source',
          byte_length: source.bytesize, sha256: Digest::SHA256.hexdigest(source), encoding: 'utf8',
          bom: source.start_with?("\uFEFF"), final_newline: source.end_with?("\n", "\r"),
          line_endings: StructuredmergeCore::LineEndings.new(lf: source.count("\n") - crlf, crlf: crlf, bare_cr: source.count("\r") - crlf))
        input = StructuredmergeCore::SourceEditRequest.new(request_id: SecureRandom.uuid,
          source: StructuredmergeCore::SourceInput.new(descriptor: descriptor, bytes: source.bytes), edits: edits)
        limits = StructuredmergeCore::SourceEditLimits.new(max_input_bytes: source.bytesize,
          max_output_bytes: source.bytesize + edits.sum { |edit| edit.replacement.bytesize }, max_edits: edits.length)
        result = StructuredmergeCore.apply_explicit_source_edits(input, limits)
        { 'ok' => true, 'output' => result.output, 'edit_count' => result.edit_count, 'source_projection' => 'explicit_byte_ranges' }
      rescue RuntimeError => e
        raise unless e.message.start_with?('source_edit.rejected:')

        { 'ok' => false, 'edit_count' => edits.length, 'source_projection' => 'explicit_byte_ranges',
          'diagnostics' => [{ 'severity' => 'error', 'category' => 'source_edit_rejected', 'message' => e.message.delete_prefix('source_edit.rejected: ') }] }
      end

      private

      def profile_request(kind, request)
        fields = REQUEST_FIELDS.fetch(kind).to_h do |field|
          value = if FLAGS.include?(field)
                    request[field] == true
                  elsif field == 'comment_region'
                    request[field].is_a?(String) ? request[field] : nil
                  else
                    request.fetch(field).tap { |item| raise ArgumentError, "#{field} must be a string" unless item.is_a?(String) }
                  end
          [field.to_sym, value]
        end
        StructuredmergeCore.const_get("Crispr#{kind.capitalize}Request").new(**fields)
      end

      def report_hash(kind, report)
        REPORT_FIELDS.fetch(kind).to_h { |field| [field, report.public_send(field)] }
      end

      def boundary_hash(report)
        result = %w[package layer status base_contract_package initial_exports future_exports].to_h { |field| [field, report.public_send(field)] }
        result['relationship'] = %w[ast_merge ast_crispr provider_packages ast_template].to_h { |field| [field, report.relationship.public_send(field)] }
        result['metadata'] = %w[source decision].to_h { |field| [field, report.metadata.public_send(field)] }
        result['implementations'] = report.implementations.map do |item|
          row = { 'language' => item.language, 'package_name' => item.package_name }
          { 'import' => :import_path, 'require' => :require_path, 'crate' => :crate_name }.each do |key, field|
            value = item.public_send(field)
            row[key] = value unless value.nil?
          end
          row
        end
        result
      end

      def limit_constraints(spec)
        case spec
        when Array
          spec.flat_map { |entry| limit_constraints(entry) }
        when Hash
          spec = spec.transform_keys(&:to_s)
          constraints = { 'exactly' => 'equal', 'at_most' => 'at_most', 'at_least' => 'at_least' }.filter_map do |key, operator|
            value = spec[key]
            limit_constraint(operator, value) if value.is_a?(Integer) && value >= 0
          end
          constraints << limit_constraint('at_most', 1) if spec['none_or_one'] == true
          raise ArgumentError, 'ast-crispr limit must define at least one constraint' if constraints.empty?

          constraints
        when String
          # This parses the limit expression DSL, not source-code structure.
          match = /\A(==|!=|<=|>=|<|>)\s*(\+?\d+)\z/.match(spec.strip)
          raise ArgumentError, 'Invalid ast-crispr limit expression' unless match

          [limit_constraint(OPERATORS.fetch(match[1]), Integer(match[2], 10))]
        else
          raise ArgumentError, 'Unsupported ast-crispr limit specification'
        end
      end

      def limit_constraint(operator, value)
        StructuredmergeCore::CrisprLimitConstraint.new(operator: operator, value: value)
      end
    end
  end
end
