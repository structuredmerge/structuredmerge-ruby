# frozen_string_literal: true

require 'ast/merge'
require_relative 'git/version'
require_relative 'git/benchmark_adapter'
require_relative 'git/corpus'
require_relative 'git/local_benchmark'

module Ast
  module Merge
    # Adapts Git merge-driver roles and outcomes to the portable provider API.
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ModuleLength -- Git protocol translation is one cohesive adapter boundary
    module Git
      PACKAGE_NAME = 'ast-merge-git'
      EXIT_SUCCESS = 0
      EXIT_CONFLICT = 1
      EXIT_ERROR = 2
      CONFLICT_POLICIES = %i[write leave_ours].freeze
      ADAPTER_ERROR_CATEGORIES = %i[
        file_error
        invalid_provider_output
        invalid_provider_result
      ].freeze

      module_function

      def merge3(request)
        normalized = normalize_request(request)
        provider_result = Ast::Merge.dispatch_provider(:merge3, provider_request(normalized))
        adapt_provider_result(provider_result)
      rescue Ast::Merge::ProviderContract::Error, ArgumentError, KeyError => e
        adapt_provider_result(adapter_failure(:invalid_provider_result, e.message))
      end

      def merge_files(base_path:, ours_path:, theirs_path:, conflict_policy: :write, **request)
        policy = normalize_conflict_policy(conflict_policy)
        result = merge3(
          request.merge(
            base_source: File.binread(base_path),
            ours_source: File.binread(ours_path),
            theirs_source: File.binread(theirs_path),
            path_name: request[:path_name] || ours_path
          )
        )
        write_result(result, ours_path, policy)
      rescue SystemCallError => e
        file_failure = adapt_provider_result(adapter_failure(:file_error, e.message))
        file_failure.merge(git: git_report(file_failure, ours_path, policy, output_written: false))
      end

      def run(argv, env: ENV, stderr: $stderr)
        load_provider_requirements(env['AST_MERGE_REQUIRE'])
        request = command_request(argv, env)
        result = merge_files(**request)
        emit_diagnostics(result, stderr)
        result.dig(:git, :exit_code)
      rescue ArgumentError, LoadError => e
        stderr.puts("#{PACKAGE_NAME}: #{e.message}")
        EXIT_ERROR
      end

      def git_exit_code(result)
        return EXIT_SUCCESS if result[:ok]
        return EXIT_ERROR if adapter_error?(result)
        return EXIT_CONFLICT unless result.fetch(:conflicts, []).empty?

        EXIT_ERROR
      end

      def adapter_error?(result)
        result.fetch(:diagnostics, []).any? do |item|
          ADAPTER_ERROR_CATEGORIES.include?(item[:category].to_s.to_sym)
        end
      end
      private_class_method :adapter_error?

      def provider_request(request)
        request.slice(
          :provider_id,
          :family,
          :dialect,
          :backend,
          :profile_id,
          :base_source,
          :ours_source,
          :theirs_source,
          :path_name,
          :labels,
          :conflict_marker_size
        ).compact
      end
      private_class_method :provider_request

      def adapt_provider_result(result)
        if result[:ok]
          output = result[:output]
          unless output.is_a?(String)
            return invalid_output_result(result, 'Successful provider result is missing String output.')
          end

          result.merge(
            merged_source: output,
            conflicted_source: nil,
            change_classifications: result.fetch(:changes)
          )
        else
          conflicted = result[:conflicted_output]
          if conflicted && !conflicted.is_a?(String)
            return invalid_output_result(result, 'Provider conflicted_output must be a String when present.')
          end

          result.merge(
            merged_source: nil,
            conflicted_source: conflicted,
            change_classifications: result.fetch(:changes)
          )
        end
      end
      private_class_method :adapt_provider_result

      def invalid_output_result(result, message)
        result.merge(
          ok: false,
          output: nil,
          merged_source: nil,
          conflicted_source: nil,
          diagnostics: result.fetch(:diagnostics) + [diagnostic(:invalid_provider_output, message)]
        )
      end
      private_class_method :invalid_output_result

      def adapter_failure(category, message)
        Ast::Merge::ProviderResult.build(
          operation: :merge3,
          success: false,
          envelope: {
            provider: { adapter: PACKAGE_NAME },
            diagnostics: [diagnostic(category, message)],
            verification: { base_participated: false }
          }
        )
      end
      private_class_method :adapter_failure

      def diagnostic(category, message)
        {
          severity: :error,
          category: category,
          message: message,
          blocking: true
        }
      end
      private_class_method :diagnostic

      def write_result(result, ours_path, policy)
        if missing_required_conflict_output?(result, policy)
          result = invalid_output_result(result, 'Conflict write policy requires String conflicted_output.')
        end
        output = writable_output(result, policy)
        File.binwrite(ours_path, output) if output
        result.merge(git: git_report(result, ours_path, policy, output_written: !output.nil?))
      rescue SystemCallError => e
        failed = result.merge(
          ok: false,
          diagnostics: result.fetch(:diagnostics) + [diagnostic(:file_error, e.message)]
        )
        failed.merge(git: git_report(failed, ours_path, policy, output_written: false))
      end
      private_class_method :write_result

      def missing_required_conflict_output?(result, policy)
        policy == :write &&
          !result[:ok] &&
          !result.fetch(:conflicts, []).empty? &&
          !result[:conflicted_source].is_a?(String)
      end
      private_class_method :missing_required_conflict_output?

      def writable_output(result, policy)
        return result.fetch(:merged_source) if result[:ok]
        return unless policy == :write
        return if result.fetch(:conflicts, []).empty?

        result[:conflicted_source]
      end
      private_class_method :writable_output

      def git_report(result, ours_path, policy, output_written:)
        {
          exit_code: git_exit_code(result),
          output_written: output_written,
          output_path: ours_path.to_s,
          conflict_policy: policy
        }
      end
      private_class_method :git_report

      def normalize_request(request)
        request.transform_keys(&:to_sym).then do |normalized|
          normalized[:family] ||= normalized.delete(:language)
          normalized[:labels] = normalize_labels(normalized)
          normalized
        end
      end
      private_class_method :normalize_request

      def normalize_labels(request)
        labels = request.fetch(:labels, {}).transform_keys(&:to_sym)
        labels[:base] ||= request[:base_label]
        labels[:ours] ||= request[:ours_label]
        labels[:theirs] ||= request[:theirs_label]
        labels.compact
      end
      private_class_method :normalize_labels

      def normalize_conflict_policy(policy)
        normalized = policy.to_s.strip.to_sym
        return normalized if CONFLICT_POLICIES.include?(normalized)

        raise ArgumentError, "Unknown conflict policy: #{policy.inspect}"
      end
      private_class_method :normalize_conflict_policy

      def command_request(argv, env)
        unless argv.length.between?(3, 8)
          raise ArgumentError,
                'usage: ast-merge-git BASE OURS THEIRS [PATH [MARKER_SIZE [BASE_LABEL OURS_LABEL THEIRS_LABEL]]]'
        end

        family = env['AST_MERGE_FAMILY']
        provider_id = env['AST_MERGE_PROVIDER']
        if family.to_s.empty? && provider_id.to_s.empty?
          raise ArgumentError, 'AST_MERGE_FAMILY or AST_MERGE_PROVIDER is required'
        end

        {
          base_path: argv.fetch(0),
          ours_path: argv.fetch(1),
          theirs_path: argv.fetch(2),
          path_name: argv[3],
          conflict_marker_size: argv[4],
          labels: { base: argv[5], ours: argv[6], theirs: argv[7] }.compact,
          family: family,
          provider_id: provider_id,
          dialect: env['AST_MERGE_DIALECT'],
          backend: env['AST_MERGE_BACKEND'],
          profile_id: env['AST_MERGE_PROFILE'],
          conflict_policy: env.fetch('AST_MERGE_CONFLICT_POLICY', :write)
        }.compact
      end
      private_class_method :command_request

      def load_provider_requirements(value)
        value.to_s.split(',').map(&:strip).reject(&:empty?).each { |require_path| require require_path }
      end
      private_class_method :load_provider_requirements

      def emit_diagnostics(result, stderr)
        result.fetch(:diagnostics).each do |item|
          stderr.puts("#{PACKAGE_NAME}: #{item[:category]}: #{item[:message]}")
        end
      end
      private_class_method :emit_diagnostics
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ModuleLength
  end
end
