# frozen_string_literal: true

require 'json'
require 'ast/merge'

module Ast
  module Merge
    module Git
      # Explicit Git-driver provider backed by the Rust ast-merge-git crate.
      # It is opt-in and intentionally does not replace format-native providers.
      class RustHostProvider
        PROVIDER_ID = 'rust.git.json'
        FAMILY = 'json'
        DIALECTS = %i[json jsonc json5].freeze

        class << self
          def available?
            require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
            ::StructuredmergeHostPrototype.respond_to?(:merge_ast_merge_git_json)
          rescue LoadError
            false
          end
        end

        def provider_id = PROVIDER_ID

        def family = FAMILY

        def capabilities
          {
            operations: Ast::Merge::ProviderContract::OPERATIONS,
            dialects: DIALECTS,
            backends: [:rust_tslp],
            profiles: [:source_preserving],
            role: :workflow,
            source_preservation: %i[exact_source declaration_fragments line_provenance reparse]
          }.freeze
        end

        def analyze(request)
          unsupported(:analyze, request, 'Rust ast-merge-git exposes Git merge3 only.')
        end

        def diff2(request)
          unsupported(:diff2, request, 'Rust ast-merge-git exposes Git merge3 only.')
        end

        def merge2(request)
          unsupported(:merge2, request, 'Rust ast-merge-git exposes Git merge3 only.')
        end

        def merge3(request)
          raw = JSON.parse(
            host.merge_ast_merge_git_json(
              request.fetch(:base_source),
              request.fetch(:ours_source),
              request.fetch(:theirs_source),
              request.fetch(:dialect).to_s
            )
          )
          conflicts = Array(raw['conflicts']).map do |conflict|
            conflict.transform_keys(&:to_sym)
          end
          diagnostics = Array(raw['diagnostics']).map { |diagnostic| normalize_diagnostic(diagnostic) }
          clean = raw['ok'] == true
          Ast::Merge::ProviderResult.build(
            operation: :merge3,
            success: clean,
            envelope: {
              provider: { provider_id: PROVIDER_ID, family: FAMILY, backend: :rust_tslp },
              profile: { profile_id: request[:profile_id] || :source_preserving },
              diagnostics: diagnostics,
              conflicts: conflicts,
              changes: Array(raw['change_classifications']),
              render_report: raw['render_report'] || {},
              verification: { rust_host: true, source_preserving: true, base_participated: true }
            },
            output: clean ? raw['merged_source'] : nil,
            conflicted_output: clean ? nil : raw['conflicted_source']
          )
        rescue KeyError, JSON::ParserError => e
          unsupported(:merge3, request, e.message)
        end

        private

        def host
          require 'structuredmerge_host_prototype' unless defined?(::StructuredmergeHostPrototype)
          ::StructuredmergeHostPrototype
        end

        def unsupported(operation, request, message)
          Ast::Merge::ProviderResult.build(
            operation: operation,
            success: false,
            envelope: {
              provider: { provider_id: PROVIDER_ID, family: FAMILY, backend: :rust_tslp },
              profile: { profile_id: request[:profile_id] || :source_preserving },
              diagnostics: [{ category: :unsupported_capability, severity: :error, message: message, blocking: true }]
            }
          )
        end

        def normalize_diagnostic(diagnostic)
          diagnostic.transform_keys(&:to_sym).merge(
            category: diagnostic.fetch('category', 'unknown').to_sym,
            severity: diagnostic.fetch('severity', 'error').to_sym,
            blocking: diagnostic.fetch('severity', 'error') == 'error'
          )
        end
      end
    end
  end
end

Ast::Merge::Git.register_rust_host_provider! if Ast::Merge::Git::RustHostProvider.available?
