# frozen_string_literal: true

require 'json'

module Ast
  module Merge
    module Git
      # Versioned JSONL protocol for repeated benchmark operations in one Ruby process.
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ModuleLength, Metrics/PerceivedComplexity -- protocol validation and dispatch remain explicit
      module BenchmarkAdapter
        REQUEST_SCHEMA = 'structuredmerge.benchmark.adapter-request/v1'
        RESPONSE_SCHEMA = 'structuredmerge.benchmark.adapter-response/v1'
        OPERATIONS = %w[diff2 merge2 merge3].freeze
        SOURCE_ROLES = {
          'diff2' => %w[before after],
          'merge2' => %w[incoming current],
          'merge3' => %w[base ours theirs]
        }.freeze

        module_function

        def serve(input: $stdin, output: $stdout)
          input.each_line do |line|
            next if line.strip.empty?

            response = execute(JSON.parse(line))
            output.puts(JSON.generate(response))
            output.flush
          rescue JSON::ParserError => e
            output.puts(JSON.generate(error_response(nil, e)))
            output.flush
          end
        end

        def execute(request)
          started = monotonic_nanoseconds
          operation, selector, sources = validate_request(request)
          require selector.fetch('require')
          result = dispatch(operation, selector, sources, request.fetch('path_name'))

          response_for(request.fetch('request_id'), operation, result, monotonic_nanoseconds - started)
        rescue ArgumentError, Ast::Merge::Error, KeyError, LoadError => e
          error_response(request.is_a?(Hash) ? request['request_id'] : nil, e, started: started)
        end

        def validate_request(request)
          raise ArgumentError, 'request must be an object' unless request.is_a?(Hash)
          raise ArgumentError, 'unsupported request schema' unless request['schema_version'] == REQUEST_SCHEMA

          operation = request.fetch('operation')
          raise ArgumentError, "unsupported operation: #{operation.inspect}" unless OPERATIONS.include?(operation)

          selector = request.fetch('selector')
          raise ArgumentError, 'selector must be an object' unless selector.is_a?(Hash)

          %w[provider_id family dialect backend profile require].each { |key| selector.fetch(key) }
          encoded_sources = request.fetch('sources')
          raise ArgumentError, 'sources must be an object' unless encoded_sources.is_a?(Hash)

          sources = SOURCE_ROLES.fetch(operation).to_h do |role|
            [role, decode_source(encoded_sources.fetch(role))]
          end
          [operation, selector, sources]
        rescue ArgumentError => e
          raise ArgumentError, "invalid base64 source: #{e.message}" if e.message.include?('invalid base64')

          raise
        end
        private_class_method :validate_request

        def dispatch(operation, selector, sources, path_name)
          request = {
            provider_id: selector.fetch('provider_id'),
            family: selector.fetch('family'),
            dialect: selector.fetch('dialect'),
            backend: selector.fetch('backend'),
            profile_id: selector.fetch('profile'),
            path_name: path_name
          }

          case operation
          when 'diff2'
            Ast::Merge.dispatch_provider(
              :diff2,
              request.merge(before_source: sources.fetch('before'), after_source: sources.fetch('after'))
            )
          when 'merge2'
            Ast::Merge.dispatch_provider(
              :merge2,
              request.merge(incoming_source: sources.fetch('incoming'), current_source: sources.fetch('current'))
            )
          when 'merge3'
            Ast::Merge::Git.merge3(
              request.merge(
                base_source: sources.fetch('base'),
                ours_source: sources.fetch('ours'),
                theirs_source: sources.fetch('theirs')
              )
            )
          end
        end
        private_class_method :dispatch

        def response_for(request_id, operation, result, duration_ns)
          output = operation_output(operation, result)
          {
            'schema_version' => RESPONSE_SCHEMA,
            'request_id' => request_id,
            'process_id' => Process.pid,
            'operation' => operation,
            'status' => operation_status(operation, result),
            'duration_ns' => duration_ns,
            'output_base64' => encode_source(output),
            'result' => Ast::Merge.json_ready(
              result.slice(:ok, :changes, :conflicts, :diagnostics, :verification)
            ),
            'stderr' => ''
          }
        end
        private_class_method :response_for

        def operation_output(operation, result)
          case operation
          when 'diff2'
            JSON.generate(Ast::Merge.json_ready(result.fetch(:changes, [])))
          when 'merge2'
            result[:ok] ? result.fetch(:output) : ''
          when 'merge3'
            result[:ok] ? result.fetch(:merged_source) : result.fetch(:conflicted_source, '').to_s
          end
        end
        private_class_method :operation_output

        def operation_status(operation, result)
          return 0 if result[:ok]
          return 1 if operation == 'merge3' && result.fetch(:conflicts, []).any?

          2
        end
        private_class_method :operation_status

        def encode_source(source)
          [source.b].pack('m0')
        end

        def decode_source(encoded)
          encoded.unpack1('m0')
        end

        def error_response(request_id, error, started: nil)
          {
            'schema_version' => RESPONSE_SCHEMA,
            'request_id' => request_id,
            'process_id' => Process.pid,
            'status' => 2,
            'duration_ns' => started ? monotonic_nanoseconds - started : 0,
            'output_base64' => '',
            'result' => {},
            'stderr' => error.message
          }
        end
        private_class_method :error_response

        def monotonic_nanoseconds
          Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        end
        private_class_method :monotonic_nanoseconds
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ModuleLength, Metrics/PerceivedComplexity
    end
  end
end
