# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tree_haver'

module Ast
  module Merge
    module Git
      # Offline Slice 1022-compatible corpus validation and deterministic selection.
      # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- benchmark evidence is intentionally explicit
      class LocalBenchmark
        Error = Class.new(StandardError)
        SCHEMA = 'structuredmerge.benchmark.corpus/v1'
        CASE_SCHEMA = 'structuredmerge.benchmark/v1'
        OPERATIONS = %w[merge2 merge3 metamorphic diff].freeze
        EXECUTABLE_OPERATIONS = %w[merge2 merge3 metamorphic].freeze
        PARTITIONS = %w[sentinel gold metamorphic].freeze
        EXPECTATIONS = %w[clean conflict error excluded_ambiguous].freeze
        SEVERITIES = %w[none low high critical].freeze
        PRESERVATION = %w[required allowed_to_change not_applicable].freeze
        TRANSFORMATIONS = %w[
          rename move reorder formatting comment independent_edit delete_modify duplicate_key_identity
          schema_aware_mutation
        ].freeze
        METAMORPHIC_INVARIANTS = %w[
          comment-retained no-semantic-edit same-json-value same-jsonc-value
        ].freeze
        ID_PATTERN = /\A[a-z0-9]+(?:[.-][a-z0-9]+)*\z/
        PROVENANCE_FIELDS = %w[
          origin_uri revision spdx_license license_evidence_uri authorship author_review reviewer derivation
        ].freeze
        SELECTOR_FIELDS = %w[provider_id family dialect backend profile require].freeze
        INPUT_ROLES = {
          'merge2' => %w[incoming current],
          'merge3' => %w[base ours theirs],
          'metamorphic' => %w[source transformed],
          'diff' => %w[before after]
        }.freeze
        PROFILE_POLICIES = {
          'micro' => %w[sentinels none],
          'dev' => %w[affected none],
          'nightly' => %w[all none],
          'competitive' => %w[all configured]
        }.freeze

        attr_reader :document, :corpus_digest, :path

        def self.load(path)
          source = File.binread(path)
          new(JSON.parse(source), path: path, corpus_digest: Digest::SHA256.hexdigest(source)).tap(&:validate!)
        rescue JSON::ParserError => e
          raise Error, "invalid corpus JSON: #{e.message}"
        rescue SystemCallError => e
          raise Error, "cannot read corpus: #{e.message}"
        end

        def initialize(document, path: nil, corpus_digest: nil)
          @document = document
          @path = path && Pathname(path).expand_path
          @corpus_digest = corpus_digest || digest(canonical_json(document))
        end

        def validate!
          require_keys(document, %w[schema_version kind id version extends provenance profiles capability_map
                                    selection competitors cases expected_summary], 'corpus')
          error!('unsupported corpus schema') unless document['schema_version'] == SCHEMA
          error!('corpus must extend Slice 1022 v1') unless document['extends'] == CASE_SCHEMA
          error!('network must be denied') unless document['network_policy'] == 'denied'
          error!('services must be empty') unless document['services'] == []
          validate_provenance!(document['provenance'], 'corpus')
          validate_profiles!
          validate_capability_map!
          validate_competitors!
          validate_cases!
          validate_summary!
          true
        end

        def cases
          validate!
          document.fetch('cases')
        end

        def select(profile:, changed_paths: [])
          validate!
          profile = profile.to_s
          definition = document.fetch('profiles')[profile]
          error!("unknown profile: #{profile}") unless definition
          paths = changed_paths.map(&:to_s).uniq.sort
          inferred = paths.to_h { |changed| [changed, capabilities_for(changed)] }
          capabilities = inferred.values.flatten.uniq.sort
          direct = cases.select { |item| direct_case?(item, capabilities) }.map { |item| item.fetch('id') }
          sentinels = definition.fetch('mandatory_sentinels')
          base = ordered(sentinels + direct)
          population = cases.map { |item| item.fetch('id') } - base
          neighbors = if definition.fetch('selection_mode') == 'affected'
                        neighbor_order(population).first(definition.fetch('neighbor_count'))
                      else
                        []
                      end
          selected = selected_ids_for(definition.fetch('selection_mode'), sentinels, base, neighbors)
          if selected.length > definition.dig('budgets', 'case_count')
            error!("profile #{profile} case budget does not fit selection")
          end

          {
            'profile' => profile,
            'selection_mode' => definition.fetch('selection_mode'),
            'competitor_policy' => definition.fetch('competitor_policy'),
            'seed' => document.dig('selection', 'seed'),
            'selected_case_ids' => selected,
            'excluded_case_ids' => cases.map { |item| item.fetch('id') } - selected,
            'changed_paths' => inferred.map { |changed, caps| { 'path' => changed, 'capabilities' => caps } },
            'inferred_capabilities' => capabilities,
            'direct_cases' => direct,
            'direct_case_reasons' => capabilities.to_h do |capability|
              matching = cases.filter_map do |item|
                item['id'] if direct_case?(item, [capability])
              end
              [capability, matching]
            end,
            'sentinels' => sentinels,
            'neighbor_sample' => {
              'population' => population,
              'ordering_algorithm' => document.dig('selection', 'neighbor_order'),
              'seed' => document.dig('selection', 'seed'),
              'selected_case_ids' => neighbors
            },
            'unsupported_selected_cases' => selected.reject do |id|
              EXECUTABLE_OPERATIONS.include?(case_by_id(id)['operation'])
            end,
            'budgets' => definition.fetch('budgets'),
            'explanation' => explanation(
              definition.fetch('selection_mode'),
              inferred: inferred,
              direct: direct,
              sentinels: sentinels,
              population: population,
              neighbors: neighbors
            )
          }
        end

        def case_by_id(id)
          document.fetch('cases').find { |item| item['id'] == id } || error!("unknown case: #{id}")
        end

        private

        def validate_profiles!
          unless document['profiles'].keys.sort == PROFILE_POLICIES.keys.sort
            error!('profiles must be exactly micro, dev, nightly, and competitive')
          end
          document['profiles'].each do |name, profile|
            require_keys(
              profile,
              %w[selection_mode competitor_policy mandatory_sentinels neighbor_count budgets],
              "profile #{name}"
            )
            require_keys(profile['budgets'], %w[wall_seconds case_count output_bytes], "profile #{name} budgets")
            actual = [profile['selection_mode'], profile['competitor_policy']]
            error!("profile #{name} policy differs") unless actual == PROFILE_POLICIES.fetch(name)
          end
        end

        def validate_capability_map!
          error!('capability_map must not be empty') unless document['capability_map'].is_a?(Array) &&
                                                            document['capability_map'].any?
          document['capability_map'].each do |entry|
            require_keys(entry, %w[path_prefix capabilities], 'capability map entry')
            error!('capability map path must be relative') if Pathname(entry['path_prefix']).absolute?
            unless entry['capabilities'] == entry['capabilities'].sort
              error!('capability map capabilities must be sorted')
            end
          end
        end

        def validate_competitors!
          document.fetch('competitors').each do |id, competitor|
            require_keys(
              competitor,
              %w[adapter_id source_url source_revision version spdx_license reuse_posture toolchain
                 build_command operations dialects],
              "competitor #{id}"
            )
            error!("competitor #{id}: adapter ID differs") unless competitor['adapter_id'] == id
            unless /\A[0-9a-f]{40}\z/.match?(competitor['source_revision'])
              error!("competitor #{id}: source revision must be a full SHA")
            end
            error!("competitor #{id}: only merge3 is admitted") unless competitor['operations'] == ['merge3']
            next if competitor['dialects'] == competitor['dialects'].sort

            error!("competitor #{id}: dialects must be sorted")
          end
        end

        def validate_cases!
          records = document['cases']
          error!('cases must not be empty') unless records.is_a?(Array) && records.any?
          ids = records.map { |item| validate_case!(item) }
          error!('duplicate case ID') unless ids.uniq.length == ids.length
          id_set = ids.to_h { |id| [id, true] }
          records.select { |item| item['operation'] == 'metamorphic' }.each do |item|
            error!("#{item['id']}: parent case is dangling") unless id_set[item['parent_case_id']]
          end
          sentinels = records.select { |item| item['partition'] == 'sentinel' }.map { |item| item['id'] }
          document['profiles'].each_value do |profile|
            error!('profile sentinels differ from corpus sentinels') unless profile['mandatory_sentinels'] == sentinels
          end
        end

        def validate_case!(item)
          require_keys(item, %w[schema_version kind id operation family provider dialect capabilities partition
                                provenance oracle acceptable_equivalence preservation_policy
                                false_auto_merge_severity selector inputs independent_edits independent_edit_ids
                                expected_conflict_regions], 'case')
          id = item['id']
          error!("#{id}: invalid stable case ID") unless ID_PATTERN.match?(id.to_s)
          error!("#{id}: incompatible case schema") unless item['schema_version'] == CASE_SCHEMA
          error!("#{id}: invalid kind") unless item['kind'] == 'benchmark_case'
          error!("#{id}: unsupported operation") unless OPERATIONS.include?(item['operation'])
          error!("#{id}: unsupported partition") unless PARTITIONS.include?(item['partition'])
          unless item['capabilities'] == item['capabilities'].uniq.sort
            error!("#{id}: capabilities must be unique and sorted")
          end
          error!("#{id}: unsupported severity") unless SEVERITIES.include?(item['false_auto_merge_severity'])
          validate_provenance!(item['provenance'], id)
          validate_oracle!(item, id)
          validate_selector!(item['selector'], id)
          validate_inputs!(item, id)
          validate_edits!(item, id)
          validate_preservation!(item, id)
          validate_operation!(item, id)
          id
        end

        def validate_provenance!(provenance, label)
          require_keys(provenance, PROVENANCE_FIELDS, "#{label} provenance")
          error!("#{label}: authorship must be reviewed") unless provenance['author_review'] == 'reviewed'
          error!("#{label}: SPDX license is required") if provenance['spdx_license'].to_s.empty?
        end

        def validate_oracle!(item, id)
          oracle = item['oracle']
          require_keys(oracle, %w[class artifact admission score_eligible procedure], "#{id} oracle")
          validate_inline!(oracle['artifact'], "#{id} oracle artifact")
          error!("#{id}: oracle procedure cannot accept parse validity alone") if oracle['procedure'].to_s.empty?
          error!("#{id}: acceptable equivalence must be explicit") unless item['acceptable_equivalence'].is_a?(Array) &&
                                                                          item['acceptable_equivalence'].any?
          return unless oracle['class'] == 'exact' && item.dig('expected', 'outcome') == 'clean'
          return if oracle.dig('artifact', 'bytes') == item.dig('expected', 'output', 'bytes')

          error!("#{id}: exact oracle artifact must match expected output bytes")
        end

        def validate_selector!(selector, id)
          require_keys(selector, SELECTOR_FIELDS, "#{id} selector")
        end

        def validate_inputs!(item, id)
          roles = INPUT_ROLES.fetch(item['operation'])
          require_keys(item['inputs'], roles, "#{id} inputs")
          item['inputs'].each { |role, record| validate_inline!(record, "#{id} #{role}") }
        end

        def validate_inline!(record, label)
          require_keys(record, %w[mode bytes sha256], label)
          error!("#{label}: only inline authored evidence is admitted") unless record['mode'] == 'inline'
          error!("#{label}: input exceeds Slice 1022 inline limit") if record['bytes'].bytesize > 4096
          error!("#{label}: SHA-256 does not match exact bytes") unless record['sha256'] == digest(record['bytes'])
        end

        def validate_edits!(item, id)
          edits = item['independent_edits']
          error!("#{id}: independent edits must be an array") unless edits.is_a?(Array)
          edit_ids = edits.map { |edit| edit.fetch('id') }
          error!("#{id}: duplicate independent edit ID") unless edit_ids.uniq.length == edit_ids.length
          error!("#{id}: independent edit IDs differ") unless item['independent_edit_ids'] == edit_ids
        end

        def validate_preservation!(item, id)
          required = %w[comments formatting order encoding line_endings unknown_fields source_regions]
          require_keys(item['preservation_policy'], required, "#{id} preservation")
          return if item['preservation_policy'].values.all? { |value| PRESERVATION.include?(value) }

          error!("#{id}: invalid preservation requirement")
        end

        def validate_operation!(item, id)
          if %w[merge2 merge3].include?(item['operation'])
            require_keys(item, %w[expected expected_conflicts], id)
            expectation = item.dig('expected', 'outcome')
            error!("#{id}: unsupported expected outcome") unless EXPECTATIONS.include?(expectation)
            output = item.dig('expected', 'output')
            validate_inline!(output, "#{id} expected output") if output
            expected_conflict = expectation == 'conflict'
            error!("#{id}: conflict expectation mismatch") unless item['expected_conflicts'] == expected_conflict
          elsif item['operation'] == 'metamorphic'
            validate_metamorphic!(item, id)
          end
        end

        def validate_metamorphic!(item, id)
          require_keys(item, %w[generator parent_case_id transformations expected_invariants], id)
          require_keys(item['generator'], %w[id version sha256 seed], "#{id} generator")
          digest = item.dig('generator', 'sha256')
          error!("#{id}: generator SHA-256 is malformed") unless /\A[0-9a-f]{64}\z/.match?(digest)
          error!("#{id}: expected invariants must not be empty") if item['expected_invariants'].empty?
          unknown_invariants = item['expected_invariants'] - METAMORPHIC_INVARIANTS
          error!("#{id}: unsupported expected invariants: #{unknown_invariants.join(', ')}") if unknown_invariants.any?
          item['transformations'].each do |transformation|
            require_keys(transformation, %w[id type parameters], "#{id} transformation")
            error!("#{id}: unknown transformation") unless TRANSFORMATIONS.include?(transformation['type'])
            next if transformation.dig('parameters', 'deterministic')

            error!("#{id}: transformation must be deterministic")
          end
        end

        def validate_summary!
          summary = document['expected_summary']
          error!('expected case count differs') unless summary['case_count'] == document['cases'].length
          actual = document['cases'].group_by { |item| item['partition'] }.transform_values(&:length)
          error!('expected partition counts differ') unless summary['partition_counts'] == actual
          operations = document['cases'].group_by { |item| item['operation'] }.transform_values(&:length)
          error!('expected operation counts differ') unless summary['operation_counts'] == operations
          families = document['cases'].map { |item| item['family'] }.uniq.sort
          error!('expected families differ') unless summary['families'] == families
          expected_micro = document.dig('profiles', 'micro', 'mandatory_sentinels')
          error!('expected micro case IDs differ') unless summary['micro_case_ids'] == expected_micro
        end

        def capabilities_for(path)
          document['capability_map'].filter_map do |entry|
            entry['capabilities'] if path.start_with?(entry['path_prefix'])
          end.flatten.uniq.sort
        end

        def direct_case?(item, capabilities)
          case_capabilities = item['capabilities'] + [item['family'], item['dialect']]
          (case_capabilities & capabilities).any?
        end

        def ordered(ids)
          order = document['cases'].map { |item| item['id'] }
          ids.uniq.sort_by { |id| order.index(id) }
        end

        def neighbor_order(ids)
          seed = document.dig('selection', 'seed')
          ids.sort_by { |id| [digest("#{seed}\0#{id}"), id] }
        end

        def selected_ids_for(mode, sentinels, base, neighbors)
          case mode
          when 'sentinels' then sentinels
          when 'affected' then ordered(base + neighbors)
          when 'all' then cases.map { |item| item.fetch('id') }
          else error!("unknown selection mode: #{mode}")
          end
        end

        def explanation(selection_mode, details)
          {
            'profile_rule' => {
              'sentinels' => 'mandatory sentinels only',
              'affected' => 'sentinels + direct + neighbors',
              'all' => 'all admitted cases in canonical corpus order'
            }.fetch(selection_mode),
            'changed_paths' => details[:inferred].map { |path, caps| "#{path} => #{caps.join(',')}" },
            'direct_cases' => details[:direct],
            'sentinels' => details[:sentinels],
            'neighbors' => {
              'population' => details[:population],
              'algorithm' => document.dig('selection', 'neighbor_order'),
              'selected' => details[:neighbors]
            },
            'budget_rule' => 'selection fits declared case budget; no silent extension or dropping'
          }
        end

        def require_keys(hash, keys, label)
          error!("#{label} must be an object") unless hash.is_a?(Hash)
          missing = keys.reject { |key| hash.key?(key) }
          error!("#{label} missing: #{missing.join(', ')}") if missing.any?
        end

        def digest(content)
          Digest::SHA256.hexdigest(content)
        end

        def canonical_json(value)
          JSON.generate(deep_sort(value))
        end

        def deep_sort(value)
          case value
          when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
          when Array then value.map { |item| deep_sort(item) }
          else value
          end
        end

        def error!(message)
          raise Error, message
        end
      end

      # Owns one long-lived benchmark adapter subprocess and its JSONL exchange.
      class BenchmarkAdapterSession
        attr_reader :spawn_duration_ns

        def initialize(driver_path:, chdir:, timeout:, env: {})
          @driver_path = Pathname(driver_path).expand_path
          @chdir = Pathname(chdir).expand_path
          @timeout = timeout
          @env = env
        end

        def start
          return self if @process

          started = monotonic_nanoseconds
          @stdin, @stdout, @stderr, @process = Open3.popen3(
            @env,
            @driver_path.to_s,
            'benchmark-provider-session',
            chdir: @chdir.to_s
          )
          [@stdin, @stdout, @stderr].each(&:binmode)
          @stderr_reader = Thread.new { @stderr.read }
          @spawn_duration_ns = monotonic_nanoseconds - started
          @request_count = 0
          self
        rescue Errno::ENOENT => e
          raise LocalBenchmark::Error, "cannot start benchmark adapter session: #{e.message}"
        end

        def request(payload)
          start
          started = monotonic_nanoseconds
          @stdin.puts(JSON.generate(payload))
          @stdin.flush
          line = read_response_line
          response = JSON.parse(line)
          @request_count += 1
          response.merge(
            'round_trip_duration_ns' => monotonic_nanoseconds - started,
            'session_request_index' => @request_count
          )
        rescue Errno::EPIPE, IOError, JSON::ParserError => e
          raise LocalBenchmark::Error, "benchmark adapter session failed: #{e.message}#{stderr_suffix}"
        end

        def close
          return unless @process

          @stdin.close unless @stdin.closed?
          terminate unless @process.join(1)
          @stderr_reader.join(1)
        ensure
          [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
          @process = nil
        end

        private

        def read_response_line
          reader = Thread.new { @stdout.gets }
          unless reader.join(@timeout)
            terminate
            raise LocalBenchmark::Error, "benchmark adapter session timed out after #{@timeout}s#{stderr_suffix}"
          end

          reader.value || raise(LocalBenchmark::Error, "benchmark adapter session closed#{stderr_suffix}")
        end

        def terminate
          Process.kill('TERM', @process.pid)
          return if @process.join(1)

          Process.kill('KILL', @process.pid)
          @process.join
        rescue Errno::ESRCH, Errno::ECHILD
          @process.join
        end

        def stderr_suffix
          return '' unless @stderr_reader&.join(0)

          stderr = @stderr_reader.value
          stderr.empty? ? '' : ": #{stderr}"
        end

        def monotonic_nanoseconds
          Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        end
      end

      # Executes the same authored merge bytes through Git and the installed driver.
      class LocalBenchmarkRunner
        DEFAULT_TIMEOUT = 30
        MAX_WORKERS = 32
        ADAPTER_DESCRIPTOR_SCHEMA = 'structuredmerge.benchmark.adapter-descriptor/v1'
        MERGIRAF_EXTENSIONS = {
          'bash' => 'sh',
          'html' => 'html',
          'json' => 'json',
          'markdown' => 'md',
          'ruby' => 'rb',
          'toml' => 'toml',
          'typescript' => 'ts',
          'yaml' => 'yaml'
        }.freeze

        # rubocop:disable Metrics/ParameterLists -- runner dependencies and resource limits remain explicit
        def initialize(benchmark:, driver_path:, tmp_root:, timeout: DEFAULT_TIMEOUT, competitor_paths: {}, workers: 1,
                       adapter_descriptor: nil)
          @benchmark = benchmark
          @driver_path = Pathname(driver_path).expand_path
          @tmp_root = Pathname(tmp_root).expand_path
          @timeout = Integer(timeout)
          @competitor_paths = competitor_paths.transform_values { |path| Pathname(path).expand_path }
          @workers = Integer(workers)
          error!("workers must be between 1 and #{MAX_WORKERS}") unless @workers.between?(1, MAX_WORKERS)
          @adapter_descriptor = load_adapter_descriptor(adapter_descriptor)
        end
        # rubocop:enable Metrics/ParameterLists

        def run(profile:, changed_paths: [])
          verify_environment!
          selection = @benchmark.select(profile: profile, changed_paths: changed_paths)
          if @competitor_paths.any? && selection.fetch('competitor_policy') != 'configured'
            error!('competitor adapters require the competitive profile')
          end
          execution = {
            'kind' => 'correctness',
            'adapter_mode' => 'cold-process',
            'workers' => @workers
          }
          manifest = run_manifest(selection, execution: execution)
          original_cwd = Dir.pwd
          results, worker_process_ids = execute_selected_cases(
            selection.fetch('selected_case_ids'),
            competitors: selection.fetch('competitor_policy') == 'configured'
          )
          raise LocalBenchmark::Error, 'runner changed its working directory' unless Dir.pwd == original_cwd

          {
            'schema_version' => 'structuredmerge.benchmark.run/v1',
            'kind' => 'paired_local_run',
            'corpus_id' => @benchmark.document['id'],
            'corpus_digest' => @benchmark.corpus_digest,
            'selection' => selection,
            'run_manifest' => manifest,
            'cache_identity' => cache_identity(selection, manifest),
            'competitors' => competitor_provenance,
            'execution' => {
              'workers_requested' => @workers,
              'workers_used' => worker_process_ids.length,
              'worker_process_ids' => worker_process_ids
            },
            'results' => results
          }
        ensure
          Dir.chdir(original_cwd) if original_cwd && Dir.pwd != original_cwd
        end

        def performance(profile:, changed_paths: [], iterations: 1)
          verify_environment!
          count = Integer(iterations)
          error!('iterations must be positive') unless count.positive?

          selection = @benchmark.select(profile: profile, changed_paths: changed_paths)
          execution = {
            'kind' => 'performance',
            'adapter_mode' => 'persistent-jsonl',
            'iterations' => count,
            'timing_components' => %w[spawn adapter_execution harness_overhead round_trip]
          }
          manifest = run_manifest(selection, execution: execution)
          FileUtils.mkdir_p(@tmp_root)
          session = BenchmarkAdapterSession.new(
            driver_path: @driver_path,
            chdir: @tmp_root,
            timeout: @timeout,
            env: oracle_free_env
          ).start
          samples = selection.fetch('selected_case_ids').flat_map do |id|
            item = @benchmark.case_by_id(id)
            Array.new(count) do |index|
              performance_sample(session, item, index + 1)
            end
          end
          {
            'schema_version' => 'structuredmerge.benchmark.performance-run/v1',
            'kind' => 'performance_only',
            'quality_classification_performed' => false,
            'selection' => selection,
            'run_manifest' => manifest,
            'cache_identity' => cache_identity(selection, manifest),
            'session' => {
              'adapter_mode' => 'persistent-jsonl',
              'spawn_duration_ns' => session.spawn_duration_ns,
              'process_ids' => samples.map { |sample| sample['process_id'] }.uniq
            },
            'timing' => performance_timing(samples, session.spawn_duration_ns),
            'samples' => samples
          }
        ensure
          session&.close
        end

        private

        def execute_selected_cases(case_ids, competitors:)
          return [[], []] if case_ids.empty?
          if @workers == 1
            return [execute_case_group(case_ids.each_with_index.to_a, competitors: competitors), [Process.pid]]
          end

          error!('parallel benchmark workers require Process.fork') unless Process.respond_to?(:fork)

          groups = Array.new([@workers, case_ids.length].min) { [] }
          case_ids.each_with_index { |id, index| groups[index % groups.length] << [id, index] }
          execute_case_groups(groups, competitors: competitors)
        end

        def execute_case_groups(groups, competitors:)
          root = @tmp_root.join("workers-#{Process.pid}-#{monotonic_nanoseconds}")
          FileUtils.mkdir_p(root)
          workers = groups.each_with_index.map do |group, index|
            result_path = root.join("worker-#{index}.marshal")
            pid = fork_case_group(group, result_path, competitors: competitors)
            { pid: pid, result_path: result_path }
          end
          statuses = workers.to_h do |worker|
            pid, status = Process.wait2(worker.fetch(:pid))
            [pid, status]
          end
          payloads = workers.map do |worker|
            result_path = worker.fetch(:result_path)
            error!("benchmark worker #{worker.fetch(:pid)} produced no result") unless result_path.file?

            # The parent reads only a result written by its own forked child in a private run directory.
            Marshal.load(result_path.binread) # rubocop:disable Security/MarshalLoad
          end
          failed = workers.find { |worker| !statuses.fetch(worker.fetch(:pid)).success? }
          if failed
            payload = payloads.fetch(workers.index(failed))
            details = payload[:error]&.first(2)&.join(': ') || statuses.fetch(failed.fetch(:pid)).inspect
            error!("benchmark worker #{failed.fetch(:pid)} failed: #{details}")
          end
          entries = payloads.flat_map { |payload| payload.fetch(:entries) }
          [entries.sort_by(&:first).flat_map(&:last), payloads.map { |payload| payload.fetch(:process_id) }]
        ensure
          FileUtils.rm_rf(root) if root
        end

        def fork_case_group(group, result_path, competitors:)
          fork do
            payload = {
              process_id: Process.pid,
              entries: execute_case_group_entries(group, competitors: competitors)
            }
            result_path.binwrite(Marshal.dump(payload))
            exit! 0
          rescue Exception => e # rubocop:disable Lint/RescueException -- worker must serialize all failures
            result_path.binwrite(
              Marshal.dump(process_id: Process.pid, entries: [], error: [e.class.name, e.message, e.backtrace])
            )
            exit! 1
          end
        end

        def execute_case_group(indexed_case_ids, competitors:)
          execute_case_group_entries(indexed_case_ids, competitors: competitors).sort_by(&:first).flat_map(&:last)
        end

        def execute_case_group_entries(indexed_case_ids, competitors:)
          indexed_case_ids.map do |id, index|
            item = @benchmark.case_by_id(id)
            competitor_results = competitors ? execute_competitors(item) : []
            [index, execute_case(item) + competitor_results]
          end
        end

        def monotonic_nanoseconds
          Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        end

        def verify_environment!
          error!("missing installed driver: #{@driver_path}") unless @driver_path.file? && @driver_path.executable?
          @competitor_paths.each do |id, path|
            error!("unknown competitor: #{id}") unless @benchmark.document.fetch('competitors').key?(id)
            error!("missing competitor executable: #{path}") unless path.file? && path.executable?
          end
          root = Pathname(__dir__).join('..', '..', '..', '..').realpath
          resolved = @tmp_root.exist? ? @tmp_root.realpath : @tmp_root.dirname.realpath.join(@tmp_root.basename)
          error!('tmp_root must be inside the ast-merge-git repository') unless resolved.to_s.start_with?("#{root}/")
        end

        def execute_case(item)
          return unsupported_candidate(item) unless candidate_supports?(item)
          return execute_merge2_case(item) if item['operation'] == 'merge2'
          return execute_merge3_case(item) if item['operation'] == 'merge3'
          return execute_metamorphic_case(item) if item['operation'] == 'metamorphic'

          unsupported_pair(item)
        end

        def unsupported_candidate(item)
          [execute_baseline_for(item), raw_result(
            item,
            'structuredmerge.unsupported',
            nil,
            outcome: 'unsupported',
            unsupported_reason: "candidate does not support #{item['operation']}/#{item['family']}/#{item['dialect']}"
          )]
        end

        def execute_baseline_for(item)
          workspace = @tmp_root.join("#{safe_id(item['id'])}-unsupported-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          if item['operation'] == 'merge2'
            write_merge2_roles(item, workspace)
            execute_merge2_baseline(item, workspace)
          elsif item['operation'] == 'metamorphic'
            write_metamorphic_roles(item, workspace)
            execute_metamorphic_baseline(item, workspace)
          else
            write_roles(item, workspace)
            execute_baseline(item, workspace)
          end
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def candidate_supports?(item)
          return true unless @adapter_descriptor

          support = @adapter_descriptor.fetch('supports')
          if support['combinations']
            return support.fetch('combinations').any? do |combination|
              combination.fetch('family') == item.fetch('family') &&
              combination.fetch('dialects').include?(item.fetch('dialect')) &&
              combination.fetch('operations').include?(item.fetch('operation'))
            end
          end

          support.fetch('operations').include?(item.fetch('operation')) &&
            support.fetch('families').include?(item.fetch('family')) &&
            support.fetch('dialects').include?(item.fetch('dialect'))
        end

        def execute_competitors(item)
          @competitor_paths.map do |id, path|
            metadata = @benchmark.document.dig('competitors', id)
            unless metadata['operations'].include?(item['operation']) && metadata['dialects'].include?(item['dialect'])
              next raw_result(
                item,
                id,
                nil,
                outcome: 'unsupported',
                unsupported_reason: "#{id} does not support #{item['operation']}/#{item['dialect']}"
              )
            end

            execute_competitor(item, id, path)
          end
        end

        def execute_competitor(item, id, path)
          return execute_mergiraf(item, path) if id == 'mergiraf'
          return execute_git_competitor(item, path) if id == 'git'

          error!("unsupported competitor adapter: #{id}")
        end

        def execute_git_competitor(item, path)
          workspace = @tmp_root.join("#{safe_id(item['id'])}-git-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          write_roles(item, workspace)
          capture = timed_capture(
            oracle_free_env,
            path.to_s,
            'merge-file',
            '-p',
            'ours',
            'base',
            'theirs',
            chdir: workspace
          )
          raw_result(item, 'git', capture)
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def execute_mergiraf(item, path)
          workspace = @tmp_root.join("#{safe_id(item['id'])}-mergiraf-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          write_roles(item, workspace)
          output = workspace.join('output')
          capture = timed_capture(
            oracle_free_env,
            path.to_s,
            'merge',
            'base',
            'ours',
            'theirs',
            '--output',
            output.to_s,
            '--path-name',
            "#{item['id']}.#{MERGIRAF_EXTENSIONS.fetch(item['dialect'])}",
            '--conflict-marker-size',
            '7',
            chdir: workspace
          )
          capture[:output] = output.file? ? output.binread : ''
          raw_result(item, 'mergiraf', capture)
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def execute_merge3_case(item)
          workspace = @tmp_root.join("#{safe_id(item['id'])}-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          baseline = execute_baseline(item, workspace)
          candidate = execute_candidate(item, workspace)
          rerun = execute_candidate(item, workspace)
          candidate['deterministic_correctness_rerun'] = correctness_record(candidate) == correctness_record(rerun)
          [baseline, candidate]
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def execute_merge2_case(item)
          workspace = @tmp_root.join("#{safe_id(item['id'])}-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          write_merge2_roles(item, workspace)
          baseline = execute_merge2_baseline(item, workspace)
          candidate = execute_merge2_candidate(item, workspace)
          rerun = execute_merge2_candidate(item, workspace)
          candidate['deterministic_correctness_rerun'] = correctness_record(candidate) == correctness_record(rerun)
          [baseline, candidate]
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def execute_metamorphic_case(item)
          workspace = @tmp_root.join("#{safe_id(item['id'])}-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          write_metamorphic_roles(item, workspace)
          baseline = execute_metamorphic_baseline(item, workspace)
          candidate = execute_metamorphic_candidate(item, workspace)
          rerun = execute_metamorphic_candidate(item, workspace)
          candidate['deterministic_correctness_rerun'] = correctness_record(candidate) == correctness_record(rerun)
          [baseline, candidate]
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def unsupported_pair(item)
          %w[git.unsupported structuredmerge.unsupported].map do |adapter|
            raw_result(item, adapter, nil, outcome: 'unsupported',
                                           unsupported_reason: "no installed #{item['operation']} adapter")
          end
        end

        def execute_baseline(item, workspace)
          write_roles(item, workspace)
          capture = timed_capture({}, 'git', 'merge-file', '-p', 'ours', 'base', 'theirs', chdir: workspace)
          capture[:output] = capture[:stdout]
          raw_result(item, 'git.merge-file', capture)
        end

        def execute_candidate(item, workspace)
          write_roles(item, workspace)
          selector = item.fetch('selector')
          capture = timed_capture(
            candidate_env(selector),
            @driver_path.to_s, 'base', 'ours', 'theirs', "#{item['id']}.#{item['dialect']}", '7',
            chdir: workspace
          )
          capture[:output] = workspace.join('ours').binread
          raw_result(item, 'ast-merge-git', capture)
        end

        def write_roles(item, workspace)
          %w[base ours theirs].each do |role|
            workspace.join(role).binwrite(item.dig('inputs', role, 'bytes'))
          end
        end

        def write_merge2_roles(item, workspace)
          %w[incoming current].each do |role|
            workspace.join(role).binwrite(item.dig('inputs', role, 'bytes'))
          end
        end

        def execute_merge2_baseline(item, workspace)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          output = workspace.join('incoming').binread
          capture = {
            stdout: '',
            stderr: '',
            status: 0,
            output: output,
            duration_ns: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started
          }
          raw_result(item, 'template.overwrite', capture)
        end

        def execute_merge2_candidate(item, workspace)
          selector = item.fetch('selector')
          capture = timed_capture(
            candidate_env(selector),
            @driver_path.to_s,
            'benchmark-provider-merge2',
            'incoming',
            'current',
            "#{item['id']}.#{item['dialect']}",
            chdir: workspace
          )
          result = capture[:stdout].empty? ? {} : JSON.parse(capture[:stdout])
          capture[:output] = capture[:status].zero? ? result.fetch('output') : ''
          raw_result(item, 'ast-merge-provider.merge2', capture)
        rescue JSON::ParserError, KeyError => e
          capture ||= { stdout: '', stderr: '', status: 2, duration_ns: 0 }
          capture[:stderr] = [capture[:stderr], e.message].reject(&:empty?).join("\n")
          capture[:status] = 2
          capture[:output] = ''
          raw_result(item, 'ast-merge-provider.merge2', capture)
        end

        def write_metamorphic_roles(item, workspace)
          %w[source transformed].each do |role|
            workspace.join(role).binwrite(item.dig('inputs', role, 'bytes'))
          end
        end

        def execute_metamorphic_baseline(item, workspace)
          capture = timed_capture(
            {},
            'git', 'diff', '--no-index', '--no-color', '--no-ext-diff', '--', 'source', 'transformed',
            chdir: workspace
          )
          capture[:output] = capture[:stdout]
          metamorphic_result(
            item,
            'git.diff',
            'baseline',
            capture,
            edit_signal: capture[:status] == 1
          )
        end

        def execute_metamorphic_candidate(item, workspace)
          capture, changes = capture_provider_diff(item, workspace)
          metamorphic_result(
            item,
            'ast-merge-provider.diff2',
            'candidate',
            capture,
            edit_signal: changes.any?
          )
        end

        def capture_provider_diff(item, workspace)
          selector = item.fetch('selector')
          capture = timed_capture(
            candidate_env(selector),
            @driver_path.to_s,
            'benchmark-provider-diff',
            'source',
            'transformed',
            "#{item['id']}.#{item['dialect']}",
            chdir: workspace
          )
          result = capture[:stdout].empty? ? {} : JSON.parse(capture[:stdout])
          changes = capture[:status].zero? ? result.fetch('changes') : []
          capture[:output] = JSON.generate(changes)
          [capture, changes]
        rescue JSON::ParserError, KeyError => e
          capture ||= { stdout: '', stderr: '', status: 2, duration_ns: 0 }
          capture[:stderr] = [capture[:stderr], e.message].reject(&:empty?).join("\n")
          capture[:status] = 2
          capture[:output] = ''
          [capture, []]
        end

        def timed_capture(env, *command, chdir:)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          stdin, stdout_io, stderr_io, process = Open3.popen3(env, *command, chdir: chdir.to_s)
          [stdin, stdout_io, stderr_io].each(&:binmode)
          stdin.close
          stdout_reader = Thread.new { stdout_io.read }
          stderr_reader = Thread.new { stderr_io.read }
          timed_out = process.join(@timeout).nil?
          terminate_process(process) if timed_out
          stdout = stdout_reader.value
          stderr = stderr_reader.value
          stderr = [stderr, "timeout after #{@timeout}s"].reject(&:empty?).join("\n") if timed_out
          { stdout: stdout, stderr: stderr, status: timed_out ? 2 : process.value.exitstatus,
            duration_ns: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started }
        rescue Errno::ENOENT => e
          { stdout: '', stderr: e.message, status: 2, output: '', duration_ns: 0 }
        ensure
          [stdin, stdout_io, stderr_io].compact.each { |io| io.close unless io.closed? }
        end

        def terminate_process(process)
          Process.kill('TERM', process.pid)
          return if process.join(1)

          Process.kill('KILL', process.pid)
          process.join
        rescue Errno::ESRCH, Errno::ECHILD
          process.join
        end

        def raw_result(item, adapter, capture, outcome: nil, unsupported_reason: nil)
          output = capture&.fetch(:output, '') || ''
          checks = equivalence_checks(item, output)
          markers = conflict_regions(output)
          classified = outcome || classify(
            item,
            capture.fetch(:status),
            checks,
            stderr: capture.fetch(:stderr, '')
          )
          eligible = item.dig('oracle', 'score_eligible') && !%w[unsupported excluded_ambiguous].include?(classified)
          {
            'schema_version' => 'structuredmerge.benchmark.result/v1',
            'id' => "result.#{safe_id(item['id'])}.#{safe_id(adapter)}",
            'case_id' => item['id'],
            'adapter_id' => adapter,
            'adapter_role' => adapter_role(adapter),
            'case_tags' => item.slice(
              'operation', 'partition', 'family', 'provider', 'dialect',
              'capabilities', 'false_auto_merge_severity'
            ),
            'outcome' => classified,
            'score_eligible' => eligible,
            'provenance' => item['provenance'],
            'process' => capture && { 'status' => capture[:status],
                                      'exit_classification' => exit_class(capture[:status]) },
            'raw' => {
              'stdout' => raw_record(capture&.fetch(:stdout, '') || ''),
              'stderr' => raw_record(capture&.fetch(:stderr, '') || ''),
              'output' => raw_record(output)
            },
            'diagnostics' => diagnostics(capture&.fetch(:stderr, '') || '', unsupported_reason),
            'conflict_regions' => region_evidence(item, markers),
            'checks' => checks,
            'independent_edit_evidence' => independent_edit_evidence(item, checks, classified),
            'dimensions' => dimensions(item, classified, checks),
            'runtime' => capture && { 'duration_ns' => capture[:duration_ns], 'comparable' => true }
          }
        end

        def adapter_role(adapter)
          return 'baseline' if adapter.start_with?('git.') || adapter == 'template.overwrite'

          candidates = %w[
            ast-merge-git
            ast-merge-provider.diff2
            ast-merge-provider.merge2
            structuredmerge.unsupported
          ]
          return 'candidate' if candidates.include?(adapter)

          'competitor'
        end

        def metamorphic_result(item, adapter, adapter_role, capture, edit_signal:)
          checks = metamorphic_checks(item, edit_signal)
          classified = if capture[:status].nil? || capture[:status] >= 2
                         'error'
                       elsif checks['acceptable']
                         'correct_clean'
                       else
                         'false_conflict'
                       end
          eligible = item.dig('oracle', 'score_eligible') && classified != 'error'
          {
            'schema_version' => 'structuredmerge.benchmark.result/v1',
            'id' => "result.#{safe_id(item['id'])}.#{safe_id(adapter)}",
            'case_id' => item['id'],
            'adapter_id' => adapter,
            'adapter_role' => adapter_role,
            'case_tags' => item.slice(
              'operation', 'partition', 'family', 'provider', 'dialect',
              'capabilities', 'false_auto_merge_severity'
            ),
            'outcome' => classified,
            'score_eligible' => eligible,
            'provenance' => item['provenance'],
            'process' => {
              'status' => capture[:status],
              'exit_classification' => metamorphic_exit_class(adapter_role, capture[:status])
            },
            'raw' => {
              'stdout' => raw_record(capture[:stdout]),
              'stderr' => raw_record(capture[:stderr]),
              'output' => raw_record(capture[:output])
            },
            'diagnostics' => diagnostics(capture[:stderr], nil),
            'conflict_regions' => region_evidence(item, []),
            'checks' => checks,
            'independent_edit_evidence' => {},
            'dimensions' => dimensions(item, classified, checks),
            'runtime' => { 'duration_ns' => capture[:duration_ns], 'comparable' => true }
          }
        end

        def metamorphic_checks(item, edit_signal)
          evaluations = item.fetch('expected_invariants').map do |invariant|
            matched, evidence = evaluate_metamorphic_invariant(item, invariant, edit_signal)
            { 'id' => invariant, 'matched' => matched, 'evidence' => evidence }
          end
          accepted = evaluations.all? { |evaluation| evaluation['matched'] }
          {
            'declared_invariants' => evaluations,
            'accepted_equivalence' => accepted ? 'declared_invariants' : nil,
            'acceptable_equivalence_evaluations' => [{
              'class' => 'declared_invariants',
              'matched' => accepted
            }],
            'parse_validity_only_accepted' => false,
            'generator_replay' => {
              'generator_id' => item.dig('generator', 'id'),
              'generator_version' => item.dig('generator', 'version'),
              'seed' => item.dig('generator', 'seed'),
              'transformation_ids' => item.fetch('transformations').map { |transformation| transformation['id'] },
              'authored_bytes_digest_verified' => true
            },
            'preservation_violations' => [],
            'acceptable' => accepted
          }
        end

        def evaluate_metamorphic_invariant(item, invariant, edit_signal)
          case invariant
          when 'same-json-value', 'same-jsonc-value'
            [json_values_equal?(item), 'JSON-family values parsed from source and transformed bytes']
          when 'no-semantic-edit'
            [!edit_signal, 'adapter emitted no edit units']
          when 'comment-retained'
            [json_comments_retained?(item), 'JSONC AST comment content retained']
          else
            [false, 'unsupported invariant']
          end
        end

        def json_values_equal?(item)
          require 'json/merge'
          selector = item.fetch('selector')
          source = Json::Merge.json_value_for_source(
            item.dig('inputs', 'source', 'bytes'),
            dialect: selector.fetch('dialect').to_sym,
            backend: selector.fetch('backend')
          )
          transformed = Json::Merge.json_value_for_source(
            item.dig('inputs', 'transformed', 'bytes'),
            dialect: selector.fetch('dialect').to_sym,
            backend: selector.fetch('backend')
          )
          source == transformed
        rescue Json::Merge::ParseError, LoadError
          false
        end

        def json_comments_retained?(item)
          require 'json/merge'
          selector = item.fetch('selector')
          source = Json::Merge::FileAnalysis.new(
            item.dig('inputs', 'source', 'bytes'),
            dialect: selector.fetch('dialect').to_sym
          )
          transformed = Json::Merge::FileAnalysis.new(
            item.dig('inputs', 'transformed', 'bytes'),
            dialect: selector.fetch('dialect').to_sym
          )
          source.valid? && transformed.valid? &&
            source.comment_nodes.map(&:normalized_content) == transformed.comment_nodes.map(&:normalized_content)
        rescue TreeHaver::Error, LoadError
          false
        end

        def metamorphic_exit_class(adapter_role, status)
          return 'error' if status.nil? || status >= 2
          return status == 1 ? 'differences' : 'no_differences' if adapter_role == 'baseline'

          'analyzed'
        end

        def classify(item, status, checks, stderr: '')
          expected = item.dig('expected', 'outcome')
          return 'excluded_ambiguous' if expected == 'excluded_ambiguous'

          if expected == 'error'
            return 'error' if status.nil?

            return expected_error_diagnostic?(status, stderr) ? 'correct_clean' : 'error' if status >= 2

            return status == 1 ? 'false_conflict' : 'false_auto_merge'
          end
          return 'error' if status.nil? || status >= 2
          return status == 1 ? 'true_conflict' : 'false_auto_merge' if expected == 'conflict'
          return 'false_conflict' if status == 1
          return 'correct_clean' if checks['equivalence_acceptable']

          'false_auto_merge'
        end

        def expected_error_diagnostic?(status, stderr)
          status >= 2 && /\A[^:\r\n]+: (?:destination_)?parse_error:/i.match?(stderr.to_s)
        end

        def equivalence_checks(item, output)
          expected = item.dig('expected', 'output', 'bytes')
          exact = !expected.nil? && output == expected
          structural = structural_equivalence(item, output, expected)
          evaluations = item.fetch('acceptable_equivalence').map do |policy|
            matched = case policy.fetch('class')
                      when 'exact_bytes' then exact
                      when 'structural_ast' then structural == true && structural_provider_matches?(item, policy)
                      else false
                      end
            { 'class' => policy.fetch('class'), 'matched' => matched }
          end
          selected = evaluations.find { |evaluation| evaluation['matched'] }
          checks = {
            'exact' => exact,
            'structural' => structural,
            'structural_provider' => item.dig('selector', 'provider_id'),
            'acceptable_equivalence_evaluations' => evaluations,
            'accepted_equivalence' => selected&.fetch('class'),
            'parse_validity_only_accepted' => false
          }
          preservation = preservation_evaluations(item, checks, output)
          violations = preservation.filter_map { |name, status| name if status == 'fail' }
          unverified = preservation.filter_map { |name, status| name if status == 'unverified' }
          equivalence_acceptable = !selected.nil?
          preservation_acceptable = violations.empty? && unverified.empty?
          checks.merge(
            'preservation_evaluations' => preservation,
            'preservation_violations' => violations,
            'preservation_unverified' => unverified,
            'equivalence_acceptable' => equivalence_acceptable,
            'preservation_acceptable' => preservation_acceptable,
            'acceptable' => equivalence_acceptable && preservation_acceptable
          )
        end

        def structural_equivalence(item, output, expected)
          return nil unless expected

          selector = item.fetch('selector')
          require selector.fetch('require')
          result = Ast::Merge.dispatch_provider(
            :diff2,
            {
              provider_id: selector.fetch('provider_id'),
              family: selector.fetch('family'),
              dialect: selector.fetch('dialect'),
              backend: selector.fetch('backend'),
              profile_id: selector.fetch('profile'),
              before_source: expected,
              after_source: output,
              path_name: "#{item['id']}.#{item['dialect']}"
            }
          )
          result[:ok] == true && result.fetch(:changes).empty?
        rescue Ast::Merge::Error, KeyError, LoadError
          false
        end

        def structural_provider_matches?(item, policy)
          policy['provider'].to_s == item.dig('selector', 'provider_id').to_s
        end

        def dimensions(item, outcome, checks)
          eligible = item.dig('oracle', 'score_eligible')
          {
            'safety' => {
              'eligible' => eligible,
              'false_auto_merge' => outcome == 'false_auto_merge',
              'severity' => item['false_auto_merge_severity'],
              'compensable' => false
            },
            'effectiveness' => {
              'eligible' => eligible,
              'success' => %w[correct_clean true_conflict].include?(outcome)
            },
            'preservation' => {
              'eligible' => eligible,
              'requirements' => item['preservation_policy'],
              'violations' => checks.fetch('preservation_violations', []),
              'unverified' => checks.fetch('preservation_unverified', [])
            },
            'performance' => { 'quality_offset_allowed' => false }
          }
        end

        def preservation_evaluations(item, checks, output)
          expected = item.dig('expected', 'output', 'bytes')
          return {} unless expected

          item['preservation_policy'].to_h do |name, requirement|
            next [name, 'not_required'] unless requirement == 'required'
            next [name, 'pass'] if checks['exact']

            [name, preservation_evaluation(name, output, expected, checks)]
          end
        end

        def preservation_evaluation(name, output, expected, checks)
          case name
          when 'encoding'
            encoding_signature(output) == encoding_signature(expected) ? 'pass' : 'fail'
          when 'line_endings'
            line_ending_style(output) == line_ending_style(expected) ? 'pass' : 'fail'
          when 'unknown_fields'
            checks['structural'] == true ? 'pass' : 'unverified'
          when 'formatting', 'source_regions'
            output == expected ? 'pass' : 'fail'
          else
            'unverified'
          end
        end

        def encoding_signature(content)
          bytes = content.b
          bom = if bytes.start_with?("\xEF\xBB\xBF".b)
                  'utf-8-bom'
                elsif bytes.start_with?("\xFF\xFE".b)
                  'utf-16le-bom'
                elsif bytes.start_with?("\xFE\xFF".b)
                  'utf-16be-bom'
                end
          return bom if bom

          bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? ? 'utf-8' : 'binary'
        end

        def line_ending_style(content)
          return 'crlf' if content.include?("\r\n")

          'lf'
        end

        def independent_edit_evidence(item, checks, outcome)
          item['independent_edit_ids'].to_h do |id|
            [id,
             { 'preserved' => outcome == 'correct_clean' && checks['acceptable'], 'method' => 'oracle equivalence' }]
          end
        end

        def conflict_regions(output)
          ranges = []
          start_byte = nil
          offset = 0
          output.each_line do |line|
            start_byte = offset if line.start_with?('<<<<<<<')
            if start_byte && line.start_with?('>>>>>>>')
              ranges << { 'start_byte' => start_byte, 'end_byte' => offset + line.bytesize }
              start_byte = nil
            end
            offset += line.bytesize
          end
          ranges
        end

        def region_evidence(item, observed)
          expected = item['expected_conflict_regions']
          observed = observed.each_with_index.map { |region, index| region.merge('id' => "observed.#{index + 1}") }
          localization_status = expected.empty? && observed.empty? ? 'not_applicable' : 'unknown'
          {
            'expected' => expected,
            'observed' => observed,
            'matched_region_ids' => [],
            'missed_region_ids' => expected.map { |region| region['id'] },
            'false_positive_region_ids' => observed.map { |region| region['id'] },
            'localization_status' => localization_status,
            'matching_basis' => 'unknown: expected role ranges/paths and observed output ranges have no proven mapping',
            'localization_error_bytes' => nil
          }
        end

        def raw_record(content)
          { 'inline' => content, 'bytes' => content.bytesize, 'sha256' => Digest::SHA256.hexdigest(content) }
        end

        def diagnostics(stderr, unsupported_reason)
          lines = stderr.lines.map(&:strip).reject(&:empty?)
          lines << unsupported_reason if unsupported_reason
          lines.map do |line|
            match = /\A[^:\r\n]+: ([a-z_]+):/i.match(line)
            category = match&.[](1) || (unsupported_reason == line ? 'unsupported' : 'process')
            { 'severity' => 'error', 'category' => category, 'message' => line }
          end
        end

        def selector_env(selector)
          {
            'AST_MERGE_PROVIDER' => selector['provider_id'],
            'AST_MERGE_FAMILY' => selector['family'],
            'AST_MERGE_DIALECT' => selector['dialect'],
            'AST_MERGE_BACKEND' => selector['backend'],
            'AST_MERGE_PROFILE' => selector['profile'],
            'AST_MERGE_REQUIRE' => selector['require']
          }
        end

        def candidate_env(selector)
          oracle_free_env.merge(selector_env(selector))
        end

        def oracle_free_env
          ENV.keys.grep(/(?:ORACLE|EXPECTED)/i).to_h { |name| [name, nil] }
        end

        def run_manifest(selection, execution: { 'kind' => 'correctness', 'adapter_mode' => 'cold-process' })
          configuration = benchmark_configuration(selection, execution: execution)
          manifest = {
            'schema_version' => 'structuredmerge.benchmark.run-manifest/v1',
            'adapter' => adapter_identity,
            'configuration' => configuration,
            'environment' => run_environment,
            'corpus' => {
              'id' => @benchmark.document.fetch('id'),
              'sha256' => @benchmark.corpus_digest
            }
          }
          manifest.merge('sha256' => canonical_digest(manifest))
        end

        def cache_identity(selection, manifest = run_manifest(selection))
          configuration = manifest.fetch('configuration')
          competitors = competitor_provenance
          identity = {
            'adapter_id' => manifest.dig('adapter', 'adapter_id'),
            'adapter_source_sha' => manifest.dig('adapter', 'source', 'revision'),
            'adapter_artifact_sha256' => manifest.dig('adapter', 'artifact', 'sha256'),
            'configuration_sha256' => canonical_digest(configuration),
            'parser_providers' => configuration.fetch('cases').map do |item|
              item.fetch('parser_provider')
            end.uniq,
            'run_manifest_sha256' => manifest.fetch('sha256'),
            'competitors' => competitors,
            'corpus_sha256' => @benchmark.corpus_digest,
            'environment' => manifest.fetch('environment'),
            'profile' => selection['profile'],
            'changed_paths' => selection['changed_paths'],
            'inferred_capabilities' => selection['inferred_capabilities'],
            'selection_explanation_sha256' => Digest::SHA256.hexdigest(
              JSON.generate(deep_sort(selection.fetch('explanation')))
            ),
            'selected_case_ids' => selection['selected_case_ids']
          }
          identity.merge('sha256' => Digest::SHA256.hexdigest(JSON.generate(identity)))
        end

        def benchmark_configuration(selection, execution:)
          provider = @adapter_descriptor&.fetch('provider')
          {
            'profile' => selection.fetch('profile'),
            'changed_paths' => selection.fetch('changed_paths'),
            'inferred_capabilities' => selection.fetch('inferred_capabilities'),
            'selected_case_ids' => selection.fetch('selected_case_ids'),
            'timeout_seconds' => @timeout,
            'network_policy' => @benchmark.document.fetch('network_policy'),
            'competitor_ids' => @competitor_paths.keys.sort,
            'execution' => execution,
            'cases' => selection.fetch('selected_case_ids').map do |id|
              item = @benchmark.case_by_id(id)
              selector = item.fetch('selector')
              backend_ref = TreeHaver::BackendRegistry.fetch(selector.fetch('backend')) unless provider
              case_configuration = {
                'case_id' => id,
                'operation' => item.fetch('operation'),
                'merge_provider' => adapter_merge_provider(item) || {
                  'provider_id' => selector.fetch('provider_id'),
                  'require_path' => selector.fetch('require')
                },
                'parser_provider' => provider&.fetch('parser_provider') || {
                  'requested_backend_id' => selector.fetch('backend'),
                  'backend_family' => backend_ref&.family,
                  'selection_mode' => 'explicit'
                },
                'selector' => selector
              }
              case_configuration['selector_role'] = 'oracle_context' if provider
              case_configuration
            end
          }
        end

        def adapter_merge_provider(item)
          return unless @adapter_descriptor

          provider = @adapter_descriptor.fetch('provider')
          provider.dig('merge_providers', item.fetch('family')) || provider['merge_provider']
        end

        def performance_sample(session, item, iteration)
          request_id = "#{item.fetch('id')}.#{iteration}"
          response = session.request(benchmark_adapter_request(item, request_id))
          output = BenchmarkAdapter.decode_source(response.fetch('output_base64'))
          adapter_duration = response.fetch('duration_ns')
          round_trip_duration = response.fetch('round_trip_duration_ns')
          harness_overhead = [round_trip_duration - adapter_duration, 0].max
          measurement_class = if response.fetch('session_request_index') == 1
                                'session_startup_and_first_request'
                              else
                                'warm_persistent_process'
                              end
          {
            'case_id' => item.fetch('id'),
            'request_id' => request_id,
            'iteration' => iteration,
            'operation' => response['operation'],
            'process_id' => response.fetch('process_id'),
            'status' => response.fetch('status'),
            'result' => response.fetch('result'),
            'diagnostics' => diagnostics(response.fetch('stderr'), nil),
            'output' => raw_record(output),
            'runtime' => {
              'adapter_duration_ns' => adapter_duration,
              'harness_overhead_ns' => harness_overhead,
              'round_trip_duration_ns' => round_trip_duration,
              'measurement_class' => measurement_class
            }
          }
        rescue ArgumentError => e
          error!("invalid adapter response for #{request_id}: #{e.message}")
        end

        def performance_timing(samples, spawn_duration)
          runtimes = samples.map { |sample| sample.fetch('runtime') }
          {
            'spawn_duration_ns' => spawn_duration,
            'adapter_execution_total_ns' => runtimes.sum { |runtime| runtime.fetch('adapter_duration_ns') },
            'harness_overhead_total_ns' => runtimes.sum { |runtime| runtime.fetch('harness_overhead_ns') },
            'round_trip_total_ns' => runtimes.sum { |runtime| runtime.fetch('round_trip_duration_ns') },
            'first_request_includes_runtime_startup' => true,
            'quality_classification_uses_these_values' => false
          }
        end

        def benchmark_adapter_request(item, request_id)
          operation, roles = benchmark_adapter_operation(item)
          {
            'schema_version' => BenchmarkAdapter::REQUEST_SCHEMA,
            'request_id' => request_id,
            'operation' => operation,
            'selector' => item.fetch('selector'),
            'path_name' => "#{item.fetch('id')}.#{item.fetch('dialect')}",
            'sources' => roles.to_h do |adapter_role, corpus_role|
              [adapter_role, BenchmarkAdapter.encode_source(item.dig('inputs', corpus_role, 'bytes'))]
            end
          }
        end

        def benchmark_adapter_operation(item)
          case item.fetch('operation')
          when 'merge2' then ['merge2', { 'incoming' => 'incoming', 'current' => 'current' }]
          when 'merge3' then ['merge3', { 'base' => 'base', 'ours' => 'ours', 'theirs' => 'theirs' }]
          when 'metamorphic' then ['diff2', { 'before' => 'source', 'after' => 'transformed' }]
          when 'diff' then ['diff2', { 'before' => 'before', 'after' => 'after' }]
          else error!("unsupported benchmark adapter operation: #{item.fetch('operation')}")
          end
        end

        def source_provenance(root: Pathname(__dir__).join('..', '..', '..', '..').expand_path,
                              repository: 'structuredmerge/structuredmerge-ruby', label: 'Ruby golden-master')
          revision, revision_status = Open3.capture2('git', '-C', root.to_s, 'rev-parse', 'HEAD')
          error!("cannot determine #{label} source revision") unless revision_status.success?

          status, status_result = Open3.capture2('git', '-C', root.to_s, 'status', '--porcelain',
                                                 '--untracked-files=no')
          error!("cannot determine #{label} source state") unless status_result.success?

          {
            'repository' => repository,
            'revision' => revision.strip,
            'dirty' => !status.empty?
          }
        end

        def adapter_identity
          artifact = {
            'path' => @driver_path.to_s,
            'sha256' => Digest::SHA256.file(@driver_path).hexdigest
          }
          unless @adapter_descriptor
            return {
              'adapter_id' => 'ruby-gm.ast-merge-git',
              'implementation' => 'ruby-golden-master',
              'package' => Ast::Merge::Git::PACKAGE_NAME,
              'package_version' => Ast::Merge::Git::VERSION,
              'source' => source_provenance,
              'artifact' => artifact
            }
          end

          declared = @adapter_descriptor.fetch('adapter')
          source = declared.fetch('source')
          declared.slice('adapter_id', 'implementation', 'package', 'package_version').merge(
            'source' => source_provenance(
              root: @adapter_descriptor.fetch('source_root'),
              repository: source.fetch('repository'),
              label: declared.fetch('adapter_id')
            ),
            'artifact' => artifact
          )
        end

        def run_environment
          return benchmark_environment unless @adapter_descriptor

          {
            'harness' => benchmark_environment,
            'adapter' => @adapter_descriptor.fetch('environment')
          }
        end

        def load_adapter_descriptor(path)
          return unless path

          descriptor_path = Pathname(path).expand_path
          descriptor = JSON.parse(descriptor_path.binread)
          unless descriptor['schema_version'] == ADAPTER_DESCRIPTOR_SCHEMA
            error!('unsupported adapter descriptor schema')
          end
          %w[adapter source_root provider supports environment].each do |key|
            error!("adapter descriptor missing #{key}") unless descriptor.key?(key)
          end
          %w[adapter_id implementation package package_version source].each do |key|
            error!("adapter descriptor missing adapter.#{key}") unless descriptor.fetch('adapter').key?(key)
          end
          unless descriptor.dig('adapter', 'source', 'repository')
            error!('adapter descriptor missing adapter.source.repository')
          end
          provider = descriptor.fetch('provider')
          error!('adapter descriptor missing provider.parser_provider') unless provider.key?('parser_provider')
          unless provider.key?('merge_provider') || provider['merge_providers'].is_a?(Hash)
            error!('adapter descriptor requires provider.merge_provider or provider.merge_providers')
          end
          %w[operations families dialects].each do |key|
            values = descriptor.fetch('supports')[key]
            unless values.is_a?(Array) && values.any?
              error!("adapter descriptor supports.#{key} must be a non-empty array")
            end
          end
          validate_support_combinations!(descriptor.fetch('supports'))
          source_root = Pathname(descriptor.fetch('source_root'))
          source_root = descriptor_path.dirname.join(source_root) unless source_root.absolute?
          descriptor.merge('source_root' => source_root.expand_path)
        rescue JSON::ParserError => e
          error!("invalid adapter descriptor JSON: #{e.message}")
        rescue SystemCallError => e
          error!("cannot read adapter descriptor: #{e.message}")
        end

        def validate_support_combinations!(support)
          return unless support.key?('combinations')

          combinations = support.fetch('combinations')
          unless combinations.is_a?(Array) && combinations.any?
            error!('adapter descriptor supports.combinations must be a non-empty array')
          end
          combinations.each do |combination|
            error!('adapter support combination requires family') unless combination['family'].is_a?(String)
            %w[operations dialects].each do |key|
              values = combination[key]
              unless values.is_a?(Array) && values.any?
                error!("adapter support combination #{key} must be a non-empty array")
              end
            end
          end
        end

        def benchmark_environment
          allowlisted = %w[
            BUNDLE_GEMFILE
            STRUCTUREDMERGE_DEV
            TREE_HAVER_BACKEND
            TREE_HAVER_NATIVE_BACKEND
            TREE_HAVER_RUBY_BACKEND
            TSLP_DEV
          ].to_h { |name| [name, ENV[name]] }
          {
            'git' => git_environment,
            'ruby' => RUBY_DESCRIPTION,
            'ruby_engine' => defined?(RUBY_ENGINE) ? RUBY_ENGINE : 'ruby',
            'ruby_version' => RUBY_VERSION,
            'rubygems' => Gem::VERSION,
            'bundler' => Gem.loaded_specs['bundler']&.version&.to_s,
            'platform' => RUBY_PLATFORM,
            'host_os' => RbConfig::CONFIG['host_os'],
            'host_cpu' => RbConfig::CONFIG['host_cpu'],
            'allowlisted_env' => allowlisted
          }
        end

        def git_environment
          executable, = Open3.capture2('sh', '-c', 'command -v git')
          version, status = Open3.capture2('git', '--version')
          return { 'available' => false } unless status.success?

          path = Pathname(executable.strip)
          {
            'available' => true,
            'path' => path.to_s,
            'version' => version.strip,
            'sha256' => path.file? ? Digest::SHA256.file(path).hexdigest : nil
          }
        rescue SystemCallError
          { 'available' => false }
        end

        def canonical_digest(value)
          Digest::SHA256.hexdigest(JSON.generate(deep_sort(value)))
        end

        def competitor_provenance
          @competitor_provenance ||= @competitor_paths.to_h do |id, path|
            metadata = @benchmark.document.fetch('competitors').fetch(id)
            capture = timed_capture(oracle_free_env, path.to_s, '--version', chdir: path.dirname)
            error!("#{id} version probe failed: #{capture[:stderr].strip}") unless capture[:status].zero?
            expected = "#{metadata.fetch('adapter_id')} #{metadata.fetch('version')}"
            error!("#{id} version differs: #{capture[:stdout].strip}") unless capture[:stdout].strip == expected

            [id, metadata.merge(
              'binary_path' => path.to_s,
              'binary_sha256' => Digest::SHA256.file(path).hexdigest,
              'reported_version' => capture[:stdout].strip
            )]
          end
        end

        def deep_sort(value)
          case value
          when Hash then value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
          when Array then value.map { |item| deep_sort(item) }
          else value
          end
        end

        def correctness_record(result)
          result.reject { |key, _value| %w[runtime deterministic_correctness_rerun].include?(key) }
        end

        def exit_class(status)
          { 0 => 'clean', 1 => 'conflict', 2 => 'error' }.fetch(status, 'error')
        end

        def safe_id(value)
          value.gsub(/[^a-zA-Z0-9.-]/, '-')
        end

        def error!(message)
          raise LocalBenchmark::Error, message
        end
      end

      # Builds a non-scalar paired report from local benchmark raw evidence.
      class LocalBenchmarkReport
        SUCCESS = %w[correct_clean true_conflict].freeze

        def self.build(run)
          new(run).build
        end

        def initialize(run)
          @run = run
          @results = run.fetch('results')
        end

        def build
          pairs = @results.group_by { |result| result['case_id'] }.values.map { |items| transition(items) }
          false_auto_merges = candidate_eligible.select { |item| item['outcome'] == 'false_auto_merge' }
          preservation_failures = candidate_eligible.select do |item|
            item.dig('dimensions', 'preservation', 'violations').any? ||
              item.dig('dimensions', 'preservation', 'unverified').any?
          end
          unexpected_errors = candidate_results.select { |item| item['outcome'] == 'error' }
          {
            'schema_version' => 'structuredmerge.benchmark.report/v1',
            'kind' => 'paired_aggregate_report',
            'corpus_id' => @run['corpus_id'],
            'corpus_digest' => @run['corpus_digest'],
            'selection' => @run['selection'],
            'run_manifest' => @run.fetch('run_manifest'),
            'cache_identity' => @run['cache_identity'],
            'dimensions' => {
              'safety' => {
                'eligible' => candidate_eligible.length,
                'false_auto_merge_result_ids' => false_auto_merges.map { |item| item['id'] },
                'gate' => false_auto_merges.empty? ? 'pass' : 'fail',
                'non_compensable' => true
              },
              'effectiveness' => outcome_counts,
              'preservation' => {
                'eligible' => candidate_eligible.length,
                'violation_result_ids' => candidate_eligible.filter_map do |item|
                  item['id'] if item.dig('dimensions', 'preservation', 'violations').any?
                end,
                'unverified_result_ids' => candidate_eligible.filter_map do |item|
                  item['id'] if item.dig('dimensions', 'preservation', 'unverified').any?
                end,
                'gate' => preservation_failures.empty? ? 'pass' : 'fail'
              },
              'performance' => performance,
              'reliability' => {
                'error_result_ids' => unexpected_errors.map { |item| item['id'] },
                'gate' => unexpected_errors.empty? ? 'pass' : 'fail'
              },
              'coverage' => coverage,
              'competitive' => competitive
            },
            'strata' => strata,
            'transitions' => pairs,
            'newly_passing_case_ids' => pairs.filter_map { |pair| pair['case_id'] if pair['newly_passing'] },
            'newly_failing_case_ids' => pairs.filter_map { |pair| pair['case_id'] if pair['newly_failing'] },
            'changed_conflict_case_ids' => pairs.filter_map { |pair| pair['case_id'] if pair['changed_conflict'] },
            'hard_gate_failed' => false_auto_merges.any? || preservation_failures.any? || unexpected_errors.any?,
            'scalar_score' => nil
          }
        end

        private

        def eligible
          @eligible ||= @results.select { |item| item['score_eligible'] }
        end

        def candidate_eligible
          eligible.select { |item| item['adapter_role'] == 'candidate' }
        end

        def candidate_results
          @results.select { |item| item['adapter_role'] == 'candidate' }
        end

        def outcome_counts
          %w[correct_clean false_conflict true_conflict false_auto_merge error unsupported
             excluded_ambiguous].to_h do |outcome|
            [outcome, @results.count { |item| item['outcome'] == outcome }]
          end
        end

        def transition(items)
          baseline = items.find { |item| item['adapter_role'] == 'baseline' }
          candidate = items.find { |item| item['adapter_role'] == 'candidate' }
          {
            'case_id' => items.first['case_id'],
            'baseline_result_id' => baseline['id'],
            'candidate_result_id' => candidate['id'],
            'from' => baseline['outcome'],
            'to' => candidate['outcome'],
            'newly_passing' => !SUCCESS.include?(baseline['outcome']) && SUCCESS.include?(candidate['outcome']),
            'newly_failing' => SUCCESS.include?(baseline['outcome']) && !SUCCESS.include?(candidate['outcome']),
            'changed_conflict' => conflict?(baseline) && conflict?(candidate) &&
              baseline.dig('raw', 'output', 'sha256') != candidate.dig('raw', 'output', 'sha256')
          }
        end

        def conflict?(result)
          %w[false_conflict true_conflict].include?(result['outcome'])
        end

        def performance
          @results.group_by { |item| item['adapter_id'] }.transform_values do |items|
            values = items.filter_map { |item| item.dig('runtime', 'duration_ns') }
            { 'samples' => values.length, 'total_ns' => values.sum, 'runtime_values_excluded_from_correctness' => true }
          end
        end

        def coverage
          selected = @run.dig('selection', 'selected_case_ids').length
          unsupported = @results.select do |item|
            item['adapter_role'] == 'candidate' && item['outcome'] == 'unsupported'
          end
          { 'selected_cases' => selected, 'executed_candidate_cases' => selected - unsupported.length,
            'unsupported_case_ids' => unsupported.map { |item| item['case_id'] },
            'unsupported_is_quality_failure' => false }
        end

        def competitive
          results = @results.select { |item| item['adapter_role'] == 'competitor' }
          {
            'configured' => @run.fetch('competitors'),
            'outcomes' => results.group_by { |item| item['outcome'] }.transform_values(&:length),
            'unsupported_case_ids' => results.filter_map do |item|
              item['case_id'] if item['outcome'] == 'unsupported'
            end,
            'false_auto_merge_result_ids' => results.filter_map do |item|
              item['id'] if item['outcome'] == 'false_auto_merge'
            end,
            'affects_candidate_safety_gate' => false
          }
        end

        def strata
          case_results = @results.select { |item| item['adapter_role'] == 'candidate' }
          tag_fields = %w[operation partition family provider dialect false_auto_merge_severity]
          tag_strata = tag_fields.to_h do |field|
            [field, case_results.group_by { |item| item.dig('case_tags', field) }.transform_values(&:length)]
          end
          transitions = @results.group_by { |item| item['case_id'] }.values
          tag_strata.merge(
            'capability' => case_results.each_with_object(Hash.new(0)) do |item, counts|
              item.dig('case_tags', 'capabilities').each { |capability| counts[capability] += 1 }
            end,
            'outcome' => @results.group_by { |item| item['outcome'] }.transform_values(&:length),
            'adapter' => @results.group_by { |item| item['adapter_id'] }.transform_values(&:length),
            'transition' => transitions.each_with_object(Hash.new(0)) do |items, counts|
              pair = transition(items)
              counts["#{pair['from']}->#{pair['to']}"] += 1
            end
          )
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
  end
end
