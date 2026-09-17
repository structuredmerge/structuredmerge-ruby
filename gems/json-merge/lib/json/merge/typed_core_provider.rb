# frozen_string_literal: true

require 'digest'
require 'json'

module Json
  module Merge
    # Typed request/result adaptation only. Rust owns analysis, diff and merging.
    class TypedCoreProvider
      DIALECTS = %i[json jsonc json5].freeze
      ROLES = { analyze: %i[source], diff2: %i[before after], merge2: %i[incoming current], merge3: %i[base ours theirs] }.freeze
      VERIFICATION_FIELDS = %i[consumed_source_roles directional_roles_preserved base_participated classification_reached output_reparsed structural_equivalence preservation retained_source_regions].freeze
      # Only generated read-only data records are projected. Registry objects,
      # operation controls and executable handles must never be traversed.
      DATA_RECORDS = %w[OperationResult ResultProvider ResultProfile ResultParserSelection
        ResultVerification PreservationProperty ResultSourceRegion ResultRange ResultSpan ResultPoint
        ResultAnalysis ResultDiff ResultChange ResultConflict ResultDiagnostic
        DiagnosticRecord PortableDiagnostic DiagnosticOrigin DiagnosticSourceRef DiagnosticSubjectRef
        ConflictRecord PortableConflict ConflictSubject ConflictSourceAlternative ConflictClassification
        ConflictLocalization ConflictResolution ExactConflictRegion NativeExtension].freeze

      def self.available?
        require 'structuredmerge_core' unless defined?(::StructuredmergeCore)
        ::StructuredmergeCore.respond_to?(:execute_operation) && TreeHaver::Backends::RustTslp.available?
      rescue LoadError
        false
      end

      def provider_id = 'rust.json'
      def family = 'json'

      def capabilities
        { operations: ROLES.keys, dialects: DIALECTS, backends: [:rust_tslp],
          profiles: [:source_preserving], role: :workflow,
          source_preservation: %i[exact_source byte_spans reparse] }.freeze
      end

      ROLES.each_key do |operation|
        define_method(operation) { |request| execute(operation, request) }
      end

      private

      def core = ::StructuredmergeCore

      def execute(operation, request)
        fields = ROLES.fetch(operation).map { |role| role == :source ? :source : :"#{role}_source" }
        allowed = fields + %i[dialect provider_id family backend profile_id request_id]
        unless (request.keys - allowed).empty? &&
            DIALECTS.include?(request.fetch(:dialect, :json).to_s.to_sym) &&
            [nil, 'rust_tslp'].include?(request[:backend]&.to_s) &&
            [nil, 'source_preserving'].include?(request[:profile_id]&.to_s) &&
            [nil, provider_id].include?(request[:provider_id]) && [nil, family].include?(request[:family]&.to_s)
          return Ast::Merge::ProviderResult.unsupported(operation: operation, message: 'Typed JSON provider cannot honor the requested fields or selectors')
        end
        return Ast::Merge::ProviderResult.unsupported(operation: operation, message: 'structuredmerge-core is unavailable') unless self.class.available?

        dialect = request.fetch(:dialect, :json).to_s
        parser_id = TreeHaver::Backends::RustTslp.register_language_parser(dialect == 'json' ? 'json' : 'json5')
        sources = ROLES.fetch(operation).zip(fields).to_h do |role, field|
          text = request.fetch(field)
          unless text.is_a?(String) && [Encoding::UTF_8, Encoding::US_ASCII, Encoding::ASCII_8BIT].include?(text.encoding)
            raise ArgumentError, 'JSON source must contain UTF-8 bytes'
          end
          text = text.dup.force_encoding(Encoding::UTF_8)
          raise ArgumentError, 'JSON source must be valid UTF-8' unless text.valid_encoding?

          text.freeze
          [role, core::OperationSource.new(source_id: role.to_s, role: role, content: text,
            encoding: 'utf-8', byte_length: text.bytesize, sha256: Digest::SHA256.hexdigest(text), extra: {})]
        end
        typed_request = core::OperationRequest.new(schema: 'structuredmerge.operation-request/v1',
          request_id: request[:request_id] || "ruby-json-#{operation}", operation: policy(operation), sources: sources,
          provider_selection: core::MergeProviderSelection.new(provider_id: 'kernel.json', family: family,
            dialect: dialect, profile_id: 'kernel.json.nested.v1', required_capabilities: [operation.to_s], extra: {}),
          parser_selection: core::OperationParserSelection.new(backend: parser_id, preference: [], required_capabilities: [], extra: {}),
          extensions: [], metadata: {}, extra: {})
        result = core.execute_operation(typed_request,
          core::ParseLimits.new(max_batch_items: 3, max_input_bytes: 64 * 1024 * 1024, max_nodes: 1_000_000, max_diagnostics: 1000))
        project(operation, request, result)
      rescue KeyError, ArgumentError, TypeError => e
        Ast::Merge::ProviderResult.invalid_request(operation: operation, message: e.message)
      rescue RuntimeError => e
        Ast::Merge::ProviderResult.build(operation: operation, success: false,
          envelope: { diagnostics: [{ category: :provider_failure, severity: :error, blocking: true, message: e.message }] })
      end

      def policy(operation)
        case operation
        when :analyze
          core::OperationPolicy.from_analyze(core::AnalyzePolicy.new(extra: {}))
        when :diff2
          core::OperationPolicy.from_diff2(core::DiffPolicy.new(comparison_profile: 'exact-source-owners', equivalence: ['exact-source'], extra: {}))
        when :merge2
          core::OperationPolicy.from_merge2(core::DirectionalMergePolicy.new(directional_merge: 'template-into-current', render_policy: 'source-preserving', extra: {}))
        when :merge3
          core::OperationPolicy.from_merge3(core::ThreeWayMergePolicy.new(render_policy: 'source-preserving', fallback_policy: 'none', extra: {}))
        end
      end

      # Only open metadata values are encoded by the generated binding; never
      # send or decode a whole-operation JSON string.
      def metadata(values)
        values.to_h { |key, value| [key, JSON.parse(value)] }
      end

      def project(operation, request, result)
        changes = result.changes.map do |change|
          states = metadata(change.role_states)
          { id: change.id, path: change.path, subject_ref: change.subject_ref, change: change.classification.to_sym,
            before: revision(states['before'], :before), after: revision(states['after'], :after),
            source_spans: change.source_spans, metadata: metadata(change.metadata) }
        end
        diagnostics = result.diagnostics.map do |record|
          diagnostic = record.canonical || record.migration
          { id: diagnostic.id, code: diagnostic.code, category: diagnostic.category.to_sym,
            severity: diagnostic.severity.to_sym, message: diagnostic.message, blocking: diagnostic.blocking, typed_record: record }
        end
        conflicts = result.conflicts.map do |record|
          canonical = record.canonical
          native = canonical && metadata(canonical.classification.extra)['native_conflict']
          native || { typed_record: record }
        end
        verification = VERIFICATION_FIELDS.to_h { |field| [field, result.verification.public_send(field)] }
        verification[:rust_core] = true
        payload = { output: result.output, typed_result: result }
        if result.analysis
          facts = metadata(result.analysis.extra)
          payload[:analysis] = { backend: :rust_tslp, valid: true, facts: facts,
            declarations: facts.fetch('owners').map do |owner|
              { path: owner.fetch('path'), signature: owner.fetch('path'), source_role: :source,
                line_range: line_range(owner.fetch('span')), byte_range: owner.fetch('span').fetch('range') }
            end }
        end
        payload[:diff] = { changes: changes } if result.diff
        projected = Ast::Merge::ProviderResult.build(operation: operation, success: result.ok,
          envelope: { provider: { provider_id: provider_id, family: family, dialect: request.fetch(:dialect, :json),
            backend: :rust_tslp, package: 'json-merge', package_version: Json::Merge::Version::VERSION },
            profile: { profile_id: :source_preserving, core_profile_id: result.profile.profile_id },
            diagnostics: diagnostics, changes: changes, conflicts: conflicts,
            render_report: metadata(result.render_report), verification: verification }, **payload)
        portable(projected)
      end

      def portable(value)
        case value
        when Hash then value.sort_by { |key, _item| key.to_s }.to_h { |key, item| [key, portable(item)] }
        when Array then value.map { |item| portable(item) }
        when String, Symbol, Numeric, TrueClass, FalseClass, NilClass then value
        else
          name = value.class.name
          unless name&.start_with?('StructuredmergeCore::') && DATA_RECORDS.include?(name.delete_prefix('StructuredmergeCore::'))
            raise TypeError, 'Unsupported typed core data record'
          end
          value.class.public_instance_methods(false).sort.to_h do |field|
            raise TypeError, 'Unexpected executable method on core data record' unless value.method(field).arity.zero?

            item = value.public_send(field)
            item = metadata(item) if %i[extra metadata data role_states render_report].include?(field)
            item = item.map { |entry| metadata(entry) } if field == :fallbacks
            item = JSON.parse(item) if field == :payload
            [field, portable(item)]
          end
        end
      end

      def revision(state, role)
        return { present: false, source_role: role, line_range: [nil, nil] } unless state

        span = state.fetch('owner', state).fetch('span')
        { present: true, source_role: role, line_range: line_range(span), byte_range: span.fetch('range') }
      end

      def line_range(span)
        start = span.fetch('start_point')
        finish = span.fetch('end_point')
        end_row = finish.fetch('row')
        end_row -= 1 if finish.fetch('column').zero? && end_row > start.fetch('row')
        [start.fetch('row') + 1, end_row + 1]
      end
    end
  end
end
