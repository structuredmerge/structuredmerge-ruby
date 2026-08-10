# frozen_string_literal: true

require 'digest'
require 'json'

module Ast
  module Merge
    # Offline parser and conformance gate for the portable benchmark exchange contract.
    module PortableBenchmarkContract
      SCHEMA_MAJOR = 1
      SCHEMA_PATTERN = %r{\Astructuredmerge\.benchmark(?:\.[a-z_]+)?/v(\d+)(?:\.\d+)?\z}
      ENUM_KEYS = %w[
        kinds operations partitions profiles outcomes oracle_classes equivalence_classes transformations
        false_auto_merge_severities preservation_requirements unsupported_policies budget_exceed_actions
        llm_hard_gate_forbidden_profiles quality_dimensions
      ].freeze
      QUALITY_EXCLUDED_OUTCOMES = %w[unsupported excluded_ambiguous].freeze
      ADAPTER_DIGEST_FIELDS = %w[source_sha artifact_sha256 version configuration_sha256].freeze
      HISTORY_FIELDS = %w[slice corpus_id manifest case_id merge_commit].freeze
      SHA256_PATTERN = /\A[0-9a-f]{64}\z/

      class ValidationError < Ast::Merge::Error; end

      # Parses, validates, and deterministically interprets a contract without executing its payloads.
      # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- Contract conformance keeps each envelope's validation together.
      class Consumer
        attr_reader :document, :contract_digest

        def self.parse(source)
          source = String(source)
          new(JSON.parse(source), contract_digest: Digest::SHA256.hexdigest(source)).tap(&:validate!)
        rescue JSON::ParserError => e
          raise ValidationError, "invalid benchmark contract JSON: #{e.message}"
        end

        def self.load_file(path)
          parse(File.binread(path))
        end

        def initialize(document, contract_digest: nil)
          @document = document
          @contract_digest = contract_digest || Digest::SHA256.hexdigest(canonical_json(document))
        end

        def validate!
          object!(@document, 'contract')
          validate_schema_versions!
          validate_enum_contract!
          validate_cases!
          validate_run!
          validate_results!
          validate_report!
          self
        end

        def canonical_summary
          validate!
          cases = fetch_array(@document, 'cases', 'contract')
          results = fetch_array(@document, 'case_results', 'contract')
          adapters = adapter_records
          excluded = results.select { |result| QUALITY_EXCLUDED_OUTCOMES.include?(result['outcome']) }
          false_auto_merges = results.filter_map do |result|
            next unless result['outcome'] == 'false_auto_merge' && result['score_eligible']

            { 'id' => result.fetch('id'), 'severity' => result.dig('dimensions', 'safety', 'severity') }
          end

          {
            'schema' => @document.fetch('schema_version'),
            'counts' => {
              'adapters' => adapters.length,
              'cases' => cases.length,
              'results' => results.length,
              'selected_cases' => @document.dig('run_manifest', 'selection', 'selected_case_ids').length,
              'score_eligible_results' => results.count { |result| result['score_eligible'] },
              'quality_denominator_excluded_results' => excluded.length,
              'eligible_false_auto_merges' => false_auto_merges.length
            },
            'case_ids_by_operation' => grouped_case_ids(cases, 'operations', 'operation'),
            'case_ids_by_partition' => grouped_case_ids(cases, 'partitions', 'partition'),
            'score_eligible_result_ids' => results.filter_map do |result|
              result['id'] if result['score_eligible']
            end.sort,
            'quality_denominator_excluded_result_ids' => excluded.map { |result| result.fetch('id') }.sort,
            'false_auto_merges' => false_auto_merges.sort_by { |entry| entry.fetch('id') },
            'safety_gate' => {
              'status' => false_auto_merges.empty? ? 'pass' : 'fail',
              'eligible_false_auto_merge_count' => false_auto_merges.length,
              'non_compensable' => true
            },
            'selection_reason_categories' => @document.dig('run_manifest', 'selection', 'explanation').keys.sort,
            'contract_digest' => @contract_digest
          }
        end

        alias summary canonical_summary

        private

        def validate_schema_versions!
          schema_values = [@document['schema_version']]
          schema_values.concat(fetch_array(@document, 'cases', 'contract').map { |entry| entry['schema_version'] })
          run = fetch_hash(@document, 'run_manifest', 'contract')
          report = fetch_hash(@document, 'aggregate_report', 'contract')
          schema_values.concat([run['schema_version'], report['schema_version']])

          schema_values.each_with_index do |schema, index|
            match = SCHEMA_PATTERN.match(schema.to_s)
            error!("schema version #{index} is invalid: #{schema.inspect}") unless match
            error!("unsupported benchmark schema major v#{match[1]}") unless match[1].to_i == SCHEMA_MAJOR
          end
        end

        def validate_enum_contract!
          contract = fetch_hash(@document, 'contract', 'contract')
          ENUM_KEYS.each do |key|
            values = fetch_array(contract, key, 'contract enums')
            error!("#{key} contains duplicate values") unless values.uniq.length == values.length
            error!("#{key} must contain only non-empty strings") unless values.all? do |value|
              value.is_a?(String) && !value.empty?
            end
          end
          error!('scalar scores must be prohibited') unless contract['scalar_score_allowed'] == false
          error!('false auto-merges must be non-compensable') unless contract['false_auto_merge_compensable'] == false
        end

        def validate_cases!
          cases = fetch_array(@document, 'cases', 'contract')
          validate_unique_ids!(cases, 'case')
          case_schema = fetch_hash(@document, 'case_schema', 'contract')
          required = fetch_array(case_schema, 'required', 'case schema')
          operation_fields = fetch_hash(case_schema, 'operation_required_fields', 'case schema')
          inline_limit = case_schema.dig('input_policy', 'inline_max_bytes')

          cases.each do |benchmark_case|
            id = benchmark_case['id']
            required_fields!(benchmark_case, required, "case #{id}")
            membership!(benchmark_case['kind'], 'kinds', "case #{id} kind")
            error!("case #{id} kind must be benchmark_case") unless benchmark_case['kind'] == 'benchmark_case'
            operation = membership!(benchmark_case['operation'], 'operations', "case #{id} operation")
            membership!(benchmark_case['partition'], 'partitions', "case #{id} partition")
            membership!(benchmark_case.dig('oracle', 'class'), 'oracle_classes', "case #{id} oracle")
            boolean!(benchmark_case.dig('oracle', 'score_eligible'), "case #{id} oracle score eligibility")
            membership!(benchmark_case['false_auto_merge_severity'], 'false_auto_merge_severities',
                        "case #{id} severity")
            validate_capabilities!(benchmark_case, id)
            validate_equivalence!(benchmark_case, id)
            validate_preservation!(benchmark_case, id)
            required_fields!(benchmark_case, operation_fields.fetch(operation), "case #{id} #{operation}")
            validate_case_inline_records!(benchmark_case, id, inline_limit)
            validate_history_reference!(benchmark_case, id) if operation == 'history_replay'
            validate_transformations!(benchmark_case, id) if operation == 'metamorphic'
          end

          case_ids = cases.map { |entry| entry.fetch('id') }
          cases.select { |entry| entry['operation'] == 'metamorphic' }.each do |entry|
            reference!(entry['parent_case_id'], case_ids, "case #{entry['id']} parent_case_id")
          end
        end

        def validate_run!
          run = fetch_hash(@document, 'run_manifest', 'contract')
          schema = fetch_hash(@document, 'run_manifest_schema', 'contract')
          required_fields!(run, fetch_array(schema, 'required', 'run schema'), 'run manifest')
          error!('run manifest kind must be run_manifest') unless run['kind'] == 'run_manifest'
          membership!(run['profile'], 'profiles', 'run profile')
          membership!(run['unsupported_policy'], 'unsupported_policies', 'unsupported policy')

          adapter_required = fetch_array(schema, 'adapter_identity_required', 'run schema')
          adapter_records.each do |adapter|
            required_fields!(adapter, ['id', *adapter_required], "adapter #{adapter['id']}")
          end
          validate_unique_ids!(adapter_records, 'adapter')

          cases = fetch_array(@document, 'cases', 'contract')
          case_ids = cases.map { |entry| entry.fetch('id') }
          selection = fetch_hash(run, 'selection', 'run manifest')
          selected = fetch_array(selection, 'selected_case_ids', 'run selection')
          excluded = fetch_array(selection, 'excluded_case_ids', 'run selection')
          error!('selected case IDs contain duplicates') unless selected.uniq.length == selected.length
          error!('excluded case IDs contain duplicates') unless excluded.uniq.length == excluded.length
          error!('selected and excluded case IDs overlap') unless (selected & excluded).empty?
          (selected + excluded).each { |id| reference!(id, case_ids, 'run selection case_id') }
          validate_selection_explanation!(selection, case_ids, schema)
          validate_llm_gate_profile!(run, cases, selected)
        end

        def validate_results!
          results = fetch_array(@document, 'case_results', 'contract')
          validate_unique_ids!(results, 'result')
          required = fetch_array(fetch_hash(@document, 'case_result_schema', 'contract'), 'required', 'result schema')
          run = fetch_hash(@document, 'run_manifest', 'contract')
          cases = fetch_array(@document, 'cases', 'contract').to_h { |entry| [entry.fetch('id'), entry] }
          adapter_ids = adapter_records.map { |entry| entry.fetch('id') }

          results.each do |result|
            id = result['id']
            required_fields!(result, required, "result #{id}")
            reference!(result['run_id'], [run['id']], "result #{id} run_id")
            reference!(result['case_id'], cases.keys, "result #{id} case_id")
            reference!(result['adapter_id'], adapter_ids, "result #{id} adapter_id")
            outcome = membership!(result['outcome'], 'outcomes', "result #{id} outcome")
            boolean!(result['score_eligible'], "result #{id} score eligibility")
            validate_result_eligibility!(result, cases.fetch(result['case_id']), run)
            validate_raw_inline_records!(result, id)
            validate_false_auto_merge!(result, outcome)
          end
        end

        def validate_report!
          report = fetch_hash(@document, 'aggregate_report', 'contract')
          schema = fetch_hash(@document, 'aggregate_report_schema', 'contract')
          run = fetch_hash(@document, 'run_manifest', 'contract')
          results = fetch_array(@document, 'case_results', 'contract')
          result_ids = results.map { |entry| entry.fetch('id') }
          error!('aggregate report kind must be aggregate_report') unless report['kind'] == 'aggregate_report'
          reference!(report['run_id'], [run['id']], 'aggregate report run_id')
          report_result_ids = fetch_array(report, 'raw_result_ids', 'aggregate report')
          error!('aggregate raw result IDs must exactly cover results') unless report_result_ids.sort == result_ids.sort
          unless report_result_ids.uniq.length == report_result_ids.length
            error!('aggregate raw result IDs contain duplicates')
          end

          required_strata = fetch_array(schema, 'required_strata', 'report schema')
          required_fields!(fetch_hash(report, 'stratification', 'aggregate report'), required_strata,
                           'report stratification')
          validate_outcome_counts!(report, results)
          validate_quality_denominators!(report, results, run)
          validate_paired_deltas!(report, results, run)
          validate_scalar_score!(report, schema)
          validate_safety_gate!(report, results)
        end

        def validate_capabilities!(benchmark_case, id)
          capabilities = fetch_array(benchmark_case, 'capabilities', "case #{id}")
          error!("case #{id} capabilities must be unique and sorted") unless capabilities == capabilities.uniq.sort
        end

        def validate_equivalence!(benchmark_case, id)
          fetch_array(benchmark_case, 'acceptable_equivalence', "case #{id}").each do |entry|
            membership!(entry['class'], 'equivalence_classes', "case #{id} equivalence")
          end
        end

        def validate_preservation!(benchmark_case, id)
          preservation = fetch_hash(benchmark_case, 'preservation_policy', "case #{id}")
          preservation.each_value do |requirement|
            membership!(requirement, 'preservation_requirements', "case #{id} preservation")
          end
        end

        def validate_transformations!(benchmark_case, id)
          fetch_array(benchmark_case, 'transformations', "case #{id}").each do |transformation|
            membership!(transformation['type'], 'transformations', "case #{id} transformation")
          end
        end

        def validate_case_inline_records!(benchmark_case, id, inline_limit)
          walk_hashes(benchmark_case) do |record|
            next unless record['mode'] == 'inline'

            bytes = record['bytes']
            error!("case #{id} inline bytes must be a string") unless bytes.is_a?(String)
            error!("case #{id} inline bytes exceed #{inline_limit}") if bytes.bytesize > inline_limit
            digest!(record['sha256'], bytes, "case #{id} inline input")
          end
        end

        def validate_raw_inline_records!(result, id)
          raw = fetch_hash(result, 'raw', "result #{id}")
          raw.each do |name, record|
            next unless record.is_a?(Hash) && record.key?('inline')

            inline = record['inline']
            error!("result #{id} raw #{name} inline content must be a string") unless inline.is_a?(String)
            error!("result #{id} raw #{name} byte length is not exact") unless record['bytes'] == inline.bytesize
            digest!(record['sha256'], inline, "result #{id} raw #{name}")
          end
        end

        def validate_history_reference!(benchmark_case, id)
          history = fetch_hash(benchmark_case, 'history_reference', "case #{id}")
          required_fields!(history, HISTORY_FIELDS, "case #{id} history reference")
          error!("case #{id} history reference must target Slice 1021") unless history['slice'] == 1021
          expected_manifest = 'diagnostics/slice-1021-reviewed-git-history-corpus/manifest.json'
          error!("case #{id} history manifest must target Slice 1021") unless history['manifest'] == expected_manifest
          error!("case #{id} history reference must not inline source bytes") if benchmark_case.key?('inputs')
        end

        def validate_selection_explanation!(selection, case_ids, schema)
          explanation = fetch_hash(selection, 'explanation', 'run selection')
          required_fields!(
            explanation,
            fetch_array(schema, 'fast_selection_required', 'run schema'),
            'selection explanation'
          )
          explanation.fetch('direct_cases').each do |reason|
            reason.fetch('case_ids').each { |id| reference!(id, case_ids, 'direct selection case_id') }
          end
          explanation.fetch('sentinels').each do |reason|
            reference!(reason['case_id'], case_ids, 'sentinel selection case_id')
          end
          explanation.fetch('neighbor_samples').each do |sample|
            (sample.fetch('population') + sample.fetch('selected_case_ids')).each do |id|
              reference!(id, case_ids, 'neighbor selection case_id')
            end
          end
          budget = fetch_hash(explanation, 'budget_exceed', 'selection explanation')
          membership!(budget['action'], 'budget_exceed_actions', 'budget exceed action')
          error!('budget exceed must regenerate the explanation') unless budget['regenerate_explanation'] == true
          error!('silent budget extension is prohibited') unless budget['silent_extension'] == false
        end

        def validate_llm_gate_profile!(run, cases, selected)
          forbidden = enum('llm_hard_gate_forbidden_profiles')
          return unless forbidden.include?(run['profile'])

          selected_cases = cases.select { |entry| selected.include?(entry['id']) }
          llm_hard_gate = selected_cases.any? do |entry|
            entry.dig('oracle', 'class') == 'llm' && entry.dig('oracle', 'score_eligible') == true
          end
          error!("LLM oracle cannot participate in #{run['profile']} hard gates") if llm_hard_gate
        end

        def validate_result_eligibility!(result, benchmark_case, run)
          outcome = result['outcome']
          expected = benchmark_case.dig('oracle', 'score_eligible') == true
          expected = false if QUALITY_EXCLUDED_OUTCOMES.include?(outcome)
          unless result['score_eligible'] == expected
            error!("result #{result['id']} score eligibility conflicts with case/outcome")
          end
          if outcome == 'unsupported' && run['unsupported_policy'] == 'coverage_only' && result['score_eligible']
            error!("result #{result['id']} unsupported outcome entered quality denominator")
          end
        end

        def validate_false_auto_merge!(result, outcome)
          safety = fetch_hash(fetch_hash(result, 'dimensions', "result #{result['id']}"), 'safety',
                              "result #{result['id']}")
          if outcome == 'false_auto_merge'
            error!("result #{result['id']} must identify a false auto-merge") unless safety['false_auto_merge'] == true
            unless safety['compensable'] == false
              error!("result #{result['id']} false auto-merge cannot be compensable")
            end
            membership!(safety['severity'], 'false_auto_merge_severities', "result #{result['id']} severity")
          elsif safety['false_auto_merge'] == true
            error!("result #{result['id']} safety classification conflicts with outcome")
          end
        end

        def validate_outcome_counts!(report, results)
          actual = enum('outcomes').to_h { |outcome| [outcome, results.count { |entry| entry['outcome'] == outcome }] }
          error!('aggregate outcome counts do not match raw results') unless report['outcome_counts'] == actual
        end

        def validate_quality_denominators!(report, results, run)
          eligible_count = results.count { |entry| entry['score_eligible'] }
          %w[effectiveness safety preservation].each do |dimension|
            actual = report.dig('dimensions', dimension, 'eligible')
            error!("aggregate #{dimension} denominator is incorrect") unless actual == eligible_count
          end
          excluded = results.select { |entry| QUALITY_EXCLUDED_OUTCOMES.include?(entry['outcome']) }
          error!('unsupported/excluded result entered quality denominator') if excluded.any? do |entry|
            entry['score_eligible']
          end
          return unless run['unsupported_policy'] == 'coverage_only'

          quality_failure = report.dig('dimensions', 'coverage', 'unsupported_is_quality_failure')
          error!('coverage-only unsupported results cannot be quality failures') unless quality_failure == false
        end

        def validate_paired_deltas!(report, results, run)
          by_id = results.to_h { |entry| [entry.fetch('id'), entry] }
          pairs = fetch_array(report, 'paired_deltas', 'aggregate report')
          pairs.each do |pair|
            base = by_id[pair['base_result_id']]
            candidate = by_id[pair['candidate_result_id']]
            error!("paired delta #{pair['case_id']} has dangling base result") unless base
            error!("paired delta #{pair['case_id']} has dangling candidate result") unless candidate
            paired_case_ids = [base['case_id'], candidate['case_id']].uniq
            error!("paired delta #{pair['case_id']} mixes cases") unless paired_case_ids == [pair['case_id']]
            unless base['adapter_id'] == run.dig('base_adapter', 'id')
              error!("paired delta #{pair['case_id']} base adapter is incorrect")
            end
            unless candidate['adapter_id'] == run.dig('candidate_adapter', 'id')
              error!("paired delta #{pair['case_id']} candidate adapter is incorrect")
            end
          end
        end

        def validate_scalar_score!(report, schema)
          error!('report schema must prohibit scalar scores') unless schema['scalar_score_allowed'] == false
          error!('aggregate scalar score is prohibited') unless report['scalar_score'].nil?
        end

        def validate_safety_gate!(report, results)
          false_auto_merges = results.count do |entry|
            entry['score_eligible'] && entry['outcome'] == 'false_auto_merge'
          end
          gate = fetch_hash(fetch_hash(report, 'gates', 'aggregate report'), 'safety', 'aggregate gates')
          expected_status = false_auto_merges.zero? ? 'pass' : 'fail'
          unless gate['status'] == expected_status
            error!('safety gate status does not reflect eligible false auto-merges')
          end
          unless gate['eligible_false_auto_merge_count'] == false_auto_merges
            error!('safety gate false-auto-merge count is incorrect')
          end
          error!('safety gate must be non-compensable') unless gate['non_compensable'] == true
          error!('safety gate must prohibit offsets') unless gate['offsets_allowed'] == []
        end

        def grouped_case_ids(cases, enum_key, field)
          enum(enum_key).to_h do |value|
            [value, cases.filter_map { |entry| entry['id'] if entry[field] == value }.sort]
          end
        end

        def adapter_records
          run = fetch_hash(@document, 'run_manifest', 'contract')
          [run['candidate_adapter'], run['base_adapter']].compact
        end

        def enum(key)
          fetch_array(fetch_hash(@document, 'contract', 'contract'), key, 'contract enums')
        end

        def membership!(value, enum_key, label)
          unless enum(enum_key).include?(value)
            error!("#{label} is not a declared #{enum_key} member: #{value.inspect}")
          end
          value
        end

        def required_fields!(object, fields, label)
          fields.each do |field|
            value = field.to_s.split('.').reduce(object) { |memo, part| memo.is_a?(Hash) ? memo[part] : nil }
            error!("#{label} is missing required field #{field}") if value.nil?
          end
        end

        def validate_unique_ids!(records, label)
          ids = records.map { |entry| entry['id'] }
          error!("#{label} IDs must be non-empty strings") unless ids.all? { |id| id.is_a?(String) && !id.empty? }
          error!("duplicate #{label} ID") unless ids.uniq.length == ids.length
        end

        def reference!(value, allowed, label)
          error!("#{label} is dangling: #{value.inspect}") unless allowed.include?(value)
        end

        def digest!(digest, content, label)
          error!("#{label} SHA-256 is malformed") unless SHA256_PATTERN.match?(digest.to_s)
          error!("#{label} SHA-256 does not match exact bytes") unless digest == Digest::SHA256.hexdigest(content)
        end

        def boolean!(value, label)
          error!("#{label} must be boolean") unless [true, false].include?(value)
        end

        def fetch_hash(object, key, label)
          value = object[key]
          error!("#{label}.#{key} must be an object") unless value.is_a?(Hash)
          value
        end

        def fetch_array(object, key, label)
          value = object[key]
          error!("#{label}.#{key} must be an array") unless value.is_a?(Array)
          value
        end

        def object!(value, label)
          error!("#{label} must be an object") unless value.is_a?(Hash)
        end

        def walk_hashes(value, &block)
          case value
          when Hash
            yield value
            value.each_value { |child| walk_hashes(child, &block) }
          when Array
            value.each { |child| walk_hashes(child, &block) }
          end
        end

        def canonical_json(value)
          case value
          when Hash
            JSON.generate(value.keys.sort.to_h { |key| [key, JSON.parse(canonical_json(value.fetch(key)))] })
          when Array
            JSON.generate(value.map { |entry| JSON.parse(canonical_json(entry)) })
          else
            JSON.generate(value)
          end
        end

        def error!(message)
          raise ValidationError, message
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      module_function

      def parse(source)
        Consumer.parse(source)
      end

      def load_file(path)
        Consumer.load_file(path)
      end
    end
  end
end
