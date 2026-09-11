# frozen_string_literal: true

require 'json'

# rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity

module Ast
  module Merge
    # Opt-in provider adapter for operations implemented by the compiled Rust
    # host. Concrete format gems supply the host method names and metadata.
    class RustHostProvider
      class << self
        def available?(required_methods = [])
          require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
          required_methods.all? { |method_name| ::StructuredmergeHostPrototype.respond_to?(method_name) }
        rescue LoadError
          false
        end
      end

      def initialize(provider_id:, family:, dialect:, package:, package_version:, host_methods:)
        @provider_id = provider_id
        @family = family
        @dialect = dialect
        @package = package
        @package_version = package_version
        @host_methods = host_methods.freeze
      end

      attr_reader :provider_id, :family

      def capabilities
        {
          operations: ProviderContract::OPERATIONS,
          dialects: [@dialect],
          backends: [:rust_tslp],
          profiles: [:source_preserving],
          role: :workflow,
          source_preservation: %i[exact_source declaration_fragments line_provenance reparse]
        }.freeze
      end

      def analyze(request)
        raw = call_host(:analyze, request.fetch(:source), request.fetch(:dialect).to_s)
        return failure(:analyze, request, raw) unless raw.fetch('ok')

        analysis = raw.fetch('analysis')
        success(
          :analyze,
          request,
          analysis: {
            backend: :rust_tslp,
            valid: true,
            declarations: Array(analysis['owners']).map do |owner|
            {
              path: logical_owner_path(owner),
              signature: logical_owner_path(owner),
                source_role: :source,
                line_range: owner.fetch('line_range', [nil, nil])
              }
            end
          },
          verification: { source_parsed: true, rust_host: true }
        )
      rescue KeyError, JSON::ParserError => e
        failure(:analyze, request, error_payload('parse_error', e.message, 'source'))
      end

      def diff2(request)
        before = analysis_for(request.fetch(:before_source), request.fetch(:dialect).to_s)
        return failure(:diff2, request, before) unless before.fetch('ok')

        after = analysis_for(request.fetch(:after_source), request.fetch(:dialect).to_s)
        return failure(:diff2, request, after) unless after.fetch('ok')

        before_owners = owner_map(before)
        after_owners = owner_map(after)
        changes = (before_owners.keys | after_owners.keys).filter_map do |path|
          next if before_owners[path] == after_owners[path]

          change = if before_owners.key?(path)
                     after_owners.key?(path) ? :edited : :deleted
                   else
                     :added
                   end
          { path: path, change: change }
        end
        success(
          :diff2,
          request,
          envelope: {
            changes: changes,
            verification: { before_parsed: true, after_parsed: true, rust_host: true }
          },
          diff: { changes: changes }
        )
      rescue KeyError, JSON::ParserError => e
        failure(:diff2, request, error_payload('parse_error', e.message, 'source'))
      end

      def merge2(request)
        raw = call_host(
          :merge2,
          request.fetch(:incoming_source),
          request.fetch(:current_source),
          request.fetch(:dialect).to_s
        )
        merge_result(:merge2, request, raw)
      rescue KeyError, JSON::ParserError => e
        failure(:merge2, request, error_payload('parse_error', e.message, 'source'))
      end

      def merge3(request)
        raw = call_host(
          :merge3,
          request.fetch(:base_source),
          request.fetch(:ours_source),
          request.fetch(:theirs_source),
          request.fetch(:dialect).to_s
        )
        merge_result(:merge3, request, raw)
      rescue KeyError, JSON::ParserError => e
        failure(:merge3, request, error_payload('parse_error', e.message, 'source'))
      end

      private

      def host
        require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
        ::StructuredmergeHostPrototype
      end

      def call_host(operation, *args)
        JSON.parse(host.public_send(@host_methods.fetch(operation), *args))
      end

      def analysis_for(source, dialect)
        call_host(:analyze, source, dialect)
      end

      def owner_map(raw)
        analysis = raw.fetch('analysis')
        declarations = Array(analysis['declarations'])
        unless declarations.empty?
          return declarations.to_h do |declaration|
            [logical_owner_path(declaration), declaration.merge('path' => logical_owner_path(declaration))]
          end
        end

        analysis.fetch('owners').to_h do |owner|
          [logical_owner_path(owner), owner.merge('path' => logical_owner_path(owner))]
        end
      end

      def logical_owner_path(owner)
        match_key = owner['match_key']
        return owner.fetch('path') if match_key.nil? || match_key.empty?

        kind = if owner['owner_kind'].nil? || owner['owner_kind'] == 'declaration'
                 'function'
               else
                 owner.fetch('owner_kind')
               end
        "[:#{kind}, #{match_key.inspect}]"
      end

      def merge_result(operation, request, raw)
        diagnostics = raw.fetch('diagnostics', []).map { |diagnostic| normalize_diagnostic(diagnostic) }
        conflicts = raw.fetch('conflicts', [])
        success = operation == :merge2 ? raw.fetch('ok') : raw.fetch('outcome') == 'clean'
        envelope = {
          provider: provider_metadata(request),
          profile: { profile_id: request[:profile_id] || :source_preserving },
          diagnostics: diagnostics,
          conflicts: conflicts,
          verification: {
            rust_host: true,
            source_preserving: true,
            base_participated: operation == :merge3
          }
        }
        ProviderResult.build(operation: operation, success: success, envelope: envelope, output: raw['output'])
      end

      def success(operation, request, envelope: {}, **payload)
        ProviderResult.build(operation: operation, success: true, envelope: {
          provider: provider_metadata(request),
          profile: { profile_id: request[:profile_id] || :source_preserving },
          verification: payload.delete(:verification) || {}
        }.merge(envelope), **payload)
      end

      def failure(operation, request, raw)
        diagnostics = Array(raw['diagnostics']).map { |diagnostic| normalize_diagnostic(diagnostic) }
        diagnostics = [normalize_diagnostic(raw)] if diagnostics.empty?
        ProviderResult.build(
          operation: operation,
          success: false,
          envelope: {
            provider: provider_metadata(request),
            profile: { profile_id: request[:profile_id] || :source_preserving },
            diagnostics: diagnostics,
            verification: { rust_host: true }
          }
        )
      end

      def error_payload(category, message, source_role)
        {
          'diagnostics' => [{
            'category' => category,
            'message' => "#{source_role} parse error: #{message}",
            'severity' => 'error'
          }]
        }
      end

      def normalize_diagnostic(diagnostic)
        diagnostic.transform_keys(&:to_sym).merge(
          category: diagnostic.fetch('category', 'parse_error').to_sym,
          severity: diagnostic.fetch('severity', 'error').to_sym,
          blocking: true
        )
      end

      def provider_metadata(request)
        {
          provider_id: provider_id,
          family: family,
          dialect: request[:dialect] || @dialect,
          backend: :rust_tslp,
          package: @package,
          package_version: @package_version
        }
      end
    end
  end
end

# rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
