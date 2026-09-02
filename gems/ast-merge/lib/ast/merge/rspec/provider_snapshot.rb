# frozen_string_literal: true

require 'digest'
require 'json'
require 'ast/merge'
require 'tree_haver'

module Ast
  module Merge
    module RSpec
      # Captures the portable TreeHaver and provider projections used by the
      # cross-runtime contract fixtures. Native facts enter only through an
      # explicit, namespaced extension builder supplied by the provider suite.
      # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists -- the capture boundary mirrors the complete versioned contract
      class ProviderSnapshot
        PARSE_REQUEST_SCHEMA = 'structuredmerge.parse-request/v1'
        PARSE_RESULT_SCHEMA = 'structuredmerge.parse-result/v1'
        ANALYSIS_RESULT_SCHEMA = 'structuredmerge.analysis-result/v1'
        EXTENSION_SCHEMA_PATTERN = %r{\Astructuredmerge\.extension/[a-z0-9-]+/v\d+\z}
        NORMALIZED_CONTRACT = 'structuredmerge.normalized-node/v1'

        class Error < StandardError; end

        attr_reader :snapshot_id, :provider, :source, :language, :dialect, :backend_id,
                    :backend_identity, :parser_contract, :profile_id, :extension_builder

        def initialize(snapshot_id:, provider:, source:, language:, dialect:, backend_id:, backend_identity:,
                       parser_contract: nil, profile_id: :source_preserving, extension_builder: nil)
          @snapshot_id = required_string(snapshot_id, :snapshot_id)
          @provider = provider
          @source = source.to_s
          @language = required_string(language, :language)
          @dialect = required_string(dialect, :dialect)
          @backend_id = required_string(backend_id, :backend_id)
          @backend_identity = normalize_backend_identity(backend_identity)
          @parser_contract = parser_contract&.to_sym
          @profile_id = profile_id.to_sym
          @extension_builder = extension_builder
        end

        def capture
          tree = parse_tree
          projection = TreeProjection.new(tree, source).call
          provider_result = analyze
          extensions = build_extensions(tree, projection, provider_result)
          parse_request = build_parse_request
          parse_result = build_parse_result(parse_request, projection, extensions)

          {
            parse_request: parse_request,
            parse_result: parse_result,
            analysis_result: build_analysis_result(parse_request, parse_result, provider_result, extensions)
          }
        end

        def differential_replay(operation:, request:)
          operation = ProviderContract.normalize_operation(operation)
          original_request = ProviderContract.validate_request!(operation, request)
          replay_request = ProviderContract.validate_request!(operation, self.class.round_trip(original_request))
          original_result = ProviderContract.validate_result!(
            operation,
            provider.public_send(operation, original_request)
          )
          replay_result = ProviderContract.validate_result!(operation, provider.public_send(operation, replay_request))
          original_json = self.class.canonical_json(original_result)
          replay_json = self.class.canonical_json(replay_result)

          {
            operation: operation.to_s,
            equivalent: original_json == replay_json,
            original_sha256: Digest::SHA256.hexdigest(original_json),
            replay_sha256: Digest::SHA256.hexdigest(replay_json),
            output_bytes_equal: output_bytes(original_result) == output_bytes(replay_result)
          }
        end

        class << self
          def tree_sitter_extension(nodes:, **)
            {
              schema: 'structuredmerge.extension/tree-sitter/v1',
              namespace: 'tree-sitter',
              capabilities: ['grammar-node-types'],
              payload: {
                grammar_node_types: nodes.map { |node| node.fetch(:native_type).to_s }.uniq.sort
              }
            }
          end

          def canonical_json(value)
            JSON.generate(canonical_value(Ast::Merge.json_ready(value)))
          end

          def round_trip(value)
            JSON.parse(canonical_json(value), symbolize_names: true)
          end

          def extension_forwarding_digest(extension)
            forwarded = round_trip(extension.merge('x-unknown-forwarding-probe' => { 'retained' => true }))
            Digest::SHA256.hexdigest(canonical_json(forwarded))
          end

          private

          def canonical_value(value)
            case value
            when Array
              value.map { |item| canonical_value(item) }
            when Hash
              value.keys.map(&:to_s).sort.to_h do |key|
                item = value.key?(key) ? value[key] : value[key.to_sym]
                [key, canonical_value(item)]
              end
            else
              value
            end
          end
        end

        private

        def parse_tree
          TreeHaver.with_backend(backend_id) do
            options = {}
            options[:contract] = parser_contract if parser_contract
            TreeHaver.parser_for(language.to_sym, **options).parse(source)
          end
        end

        def analyze
          request = {
            provider_id: provider.provider_id,
            family: provider.family,
            source: source,
            dialect: dialect,
            backend: backend_id,
            profile_id: profile_id
          }
          ProviderContract.validate_result!(:analyze, provider.analyze(request))
        end

        def build_parse_request
          {
            schema: PARSE_REQUEST_SCHEMA,
            request_id: request_id,
            source: source_descriptor(include_content: true),
            language: language,
            dialect: dialect,
            selection: {
              backend: backend_id,
              preference: [],
              required_capabilities: backend_identity.fetch(:capabilities)
            },
            options: {
              comments: true,
              diagnostics: true,
              native_extensions: true,
              tokens: false
            },
            metadata: { snapshot_id: snapshot_id }
          }
        end

        def build_parse_result(parse_request, projection, extensions)
          {
            schema: PARSE_RESULT_SCHEMA,
            request_id: request_id,
            ok: projection.fetch(:diagnostics).none? { |diagnostic| diagnostic.fetch(:blocking) },
            source: source_descriptor,
            selection: selection_report,
            backend: backend_identity.merge(
              language: language,
              dialect: dialect,
              normalized_contract: NORMALIZED_CONTRACT
            ),
            root_id: projection.fetch(:root_id),
            nodes: projection.fetch(:nodes),
            comments: projection.fetch(:comments),
            diagnostics: projection.fetch(:diagnostics),
            extensions: extensions,
            metadata: {
              parse_request_sha256: Digest::SHA256.hexdigest(self.class.canonical_json(parse_request))
            }
          }
        end

        def build_analysis_result(parse_request, parse_result, provider_result, extensions)
          analysis = provider_result.fetch(:analysis, {})
          {
            schema: ANALYSIS_RESULT_SCHEMA,
            request_id: request_id,
            ok: provider_result.fetch(:ok),
            source: source_descriptor,
            provider: provider_result.fetch(:provider),
            profile: provider_result.fetch(:profile),
            parse_result_sha256: Digest::SHA256.hexdigest(self.class.canonical_json(parse_result)),
            analysis: analysis,
            owners: extract_owners(analysis),
            comment_regions: Array(analysis[:comment_regions] || analysis['comment_regions']),
            layout_gaps: Array(analysis[:layout_gaps] || analysis['layout_gaps']),
            attachments: Array(analysis[:attachments] || analysis['attachments']),
            ownership: Array(analysis[:ownership] || analysis['ownership']),
            diagnostics: provider_result.fetch(:diagnostics),
            extensions: extensions,
            metadata: {
              parse_request_sha256: Digest::SHA256.hexdigest(self.class.canonical_json(parse_request)),
              provider_result_schema: provider_result.fetch(:schema)
            }
          }
        end

        def extract_owners(analysis)
          %i[owners declarations entries].each do |key|
            value = analysis[key] || analysis[key.to_s]
            return value if value.is_a?(Array)
          end
          []
        end

        def build_extensions(tree, projection, provider_result)
          return [] unless extension_builder

          extension_value = extension_builder.call(
            tree: tree,
            nodes: projection.fetch(:nodes),
            provider_result: provider_result,
            source: source
          )
          extensions = extension_value.is_a?(Array) ? extension_value : [extension_value]
          extensions.map { |extension| normalize_extension(extension) }
        end

        def normalize_extension(extension)
          normalized = Ast::Merge.json_ready(extension)
          schema = normalized.fetch('schema', '').to_s
          namespace = normalized.fetch('namespace', '').to_s
          capabilities = Array(normalized['capabilities']).map(&:to_s).sort.uniq
          raise Error, "Invalid extension schema: #{schema.inspect}" unless schema.match?(EXTENSION_SCHEMA_PATTERN)
          raise Error, 'Extension namespace must not be empty' if namespace.empty?
          raise Error, 'Extension payload is required' unless normalized.key?('payload')

          normalized.merge(
            'capabilities' => capabilities,
            'opaque_forwarding_replay_sha256' => self.class.extension_forwarding_digest(normalized)
          )
        end

        def selection_report
          {
            mode: 'explicit',
            requested_backend: backend_id,
            preference: [],
            required_capabilities: backend_identity.fetch(:capabilities),
            candidates: [
              {
                backend_id: backend_id,
                available: true,
                compatible: true,
                selected: true,
                reasons: []
              }
            ],
            selected_backend: backend_id,
            selection_reason: 'explicit-compatible-backend',
            registry_digest: registry_digest
          }
        end

        def registry_digest
          registrations = TreeHaver.registered_languages(language.to_sym)
          portable = registrations.keys.map(&:to_s).sort.to_h do |key|
            config = registrations[key.to_sym] || {}
            [
              key,
              config.slice(:gem_name, :contract, :symbol).transform_values do |value|
                value.respond_to?(:name) && value.name ? value.name : value.to_s
              end
            ]
          end
          Digest::SHA256.hexdigest(self.class.canonical_json(portable))
        end

        def source_descriptor(include_content: false)
          descriptor = {
            source_id: "#{snapshot_id}:source",
            role: 'source',
            byte_length: source.bytesize,
            sha256: Digest::SHA256.hexdigest(source.b),
            encoding: source.encoding.name.downcase,
            bom: source.b.start_with?("\xEF\xBB\xBF".b),
            line_endings: line_ending_profile,
            final_newline: source.end_with?("\n", "\r")
          }
          descriptor[:content] = source if include_content
          descriptor
        end

        def line_ending_profile
          endings = source.scan(/\r\n|\r|\n/).uniq
          return 'none' if endings.empty?
          return 'mixed' if endings.length > 1

          { "\n" => 'lf', "\r\n" => 'crlf', "\r" => 'cr' }.fetch(endings.first)
        end

        def normalize_backend_identity(identity)
          normalized = Ast::Merge::ProviderContract.normalize_hash(identity)
          required = %i[id family host_runtime package parser capabilities]
          missing = required.reject { |key| normalized.key?(key) }
          raise Error, "Backend identity is missing: #{missing.join(', ')}" unless missing.empty?
          unless normalized.fetch(:id).to_s == backend_id
            raise Error, 'Backend identity does not match selected backend'
          end

          normalized.merge(capabilities: Array(normalized.fetch(:capabilities)).map(&:to_s).sort.uniq)
        end

        def required_string(value, name)
          normalized = value.to_s.strip
          raise Error, "#{name} must not be empty" if normalized.empty?

          normalized
        end

        def request_id
          "#{snapshot_id}:parse"
        end

        def output_bytes(result)
          output = result[:output] || result['output']
          output&.b
        end

        # Projects only the normalized TreeHaver contract. It never introspects
        # backend-native objects; providers retain those facts in extensions.
        class TreeProjection
          def initialize(tree, source)
            @tree = tree
            @source = source
            @nodes = []
            @comments = []
            @seen_comments = {}
          end

          def call
            root_id = project_node(@tree.root_node, nil)
            project_tree_comments
            {
              root_id: root_id,
              nodes: @nodes,
              comments: ordered_comments,
              diagnostics: diagnostics
            }
          end

          private

          def project_node(node, parent_id)
            id = "node:#{@nodes.length}"
            record = node_record(node, id, parent_id)
            @nodes << record
            children = node.children
            record[:children] = children.each_with_index.map do |child, index|
              { node_id: project_node(child, id), index: index }
            end
            record_comment(node, id) if record.fetch(:role) == 'comment'
            id
          end

          def project_tree_comments
            @tree.comments.each do |comment|
              key = comment_key(comment)
              next if @seen_comments[key]

              id = "node:#{@nodes.length}"
              @nodes << comment_record(comment, id)
              record_comment(comment, id)
            end
          end

          def node_record(node, id, parent_id)
            type = node.type.to_s
            {
              id: id,
              type: type,
              native_type: node.native_type.to_s,
              role: node_role(node, type),
              named: node.named?,
              missing: node.missing?,
              has_error: node.has_error?,
              span: span(node),
              parent_id: parent_id,
              children: [],
              semantic_roles: [],
              unsupported_features: [],
              extensions: [],
              metadata: {}
            }
          end

          def comment_record(comment, id)
            {
              id: id,
              type: comment.type.to_s,
              native_type: comment.type.to_s,
              role: 'comment',
              named: false,
              missing: false,
              has_error: false,
              span: span(comment),
              parent_id: nil,
              children: [],
              semantic_roles: ['comment'],
              unsupported_features: [],
              extensions: [],
              metadata: {}
            }
          end

          def node_role(node, type)
            return 'error' if node.has_error? || node.missing?
            return 'comment' if type.include?('comment')

            node.named? ? 'structural' : 'token'
          end

          def record_comment(comment, node_id)
            key = comment_key(comment)
            @seen_comments[key] = true
            @comments << {
              node_id: node_id,
              style: optional_value(comment, :style),
              native_kind: comment.type.to_s,
              attachment_hint: optional_value(comment, :attachment_hint) || 'unknown'
            }
          end

          def comment_key(comment)
            [comment.start_byte, comment.end_byte]
          end

          def ordered_comments
            nodes_by_id = @nodes.to_h { |node| [node.fetch(:id), node] }
            @comments.sort_by do |comment|
              range = nodes_by_id.fetch(comment.fetch(:node_id)).dig(:span, :range)
              [range.fetch(:start_byte), range.fetch(:end_byte), comment.fetch(:node_id)]
            end
          end

          def optional_value(object, method_name)
            object.respond_to?(method_name) && object.public_send(method_name)&.to_s
          end

          def span(node)
            {
              range: { start_byte: node.start_byte, end_byte: node.end_byte },
              start_point: point(node.start_point),
              end_point: point(node.end_point)
            }
          end

          def point(value)
            {
              row: value.respond_to?(:row) ? value.row : value[:row],
              column: value.respond_to?(:column) ? value.column : value[:column]
            }
          end

          def diagnostics
            [
              *@tree.errors.map { |error| diagnostic(error, 'error', true) },
              *@tree.warnings.map { |warning| diagnostic(warning, 'warning', false) }
            ]
          end

          def diagnostic(value, severity, blocking)
            {
              id: "diagnostic:#{severity}:#{value.class.name}:#{value}",
              severity: severity,
              category: 'parser_diagnostic',
              code: value.respond_to?(:type) ? value.type.to_s : nil,
              message: value.to_s,
              source_role: 'source',
              blocking: blocking,
              metadata: {}
            }
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists
    end
  end
end
