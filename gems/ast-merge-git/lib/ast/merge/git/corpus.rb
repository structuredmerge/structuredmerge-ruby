# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'

module Ast
  module Merge
    module Git
      # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- evidence validation and raw-result assembly remain explicit and auditable
      # Validates and executes pinned Git-history corpus cases.
      class Corpus
        Error = Class.new(StandardError)
        CLASSIFICATIONS = %w[
          exact_automatic_resolution
          structurally_equivalent_resolution
          conflict_expected
          ambiguous_manual_review
          excluded
        ].freeze
        BACKLOG_STATUSES = %w[blocked admitted resolved].freeze
        SHA_PATTERN = /\A[0-9a-f]{40}\z/
        CASE_ID_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
        REQUIRED_CASE_KEYS = %w[
          case_id merge_commit base_commit parent_commits path blob_oids selector
          capability_tags stratum oracle
        ].freeze

        attr_reader :manifest

        def self.load(path)
          new(JSON.parse(File.binread(path)))
        rescue JSON::ParserError => e
          raise Error, "invalid manifest JSON: #{e.message}"
        rescue SystemCallError => e
          raise Error, "cannot read manifest: #{e.message}"
        end

        def initialize(manifest)
          @manifest = manifest
        end

        def validate!
          require_keys(manifest, %w[schema_version corpus_id source claim_policy admission_backlog cases], 'manifest')
          raise Error, 'schema_version must be 1' unless manifest['schema_version'] == 1

          validate_source!
          validate_backlog!
          raise Error, 'cases must be a non-empty array' unless manifest['cases'].is_a?(Array) && manifest['cases'].any?

          ids = manifest['cases'].map { |item| validate_case!(item) }
          raise Error, 'case_id values must be unique' unless ids.uniq.length == ids.length

          validate_admitted_backlog!(ids)

          true
        end

        def cases(case_id = nil)
          validate!
          return manifest['cases'] unless case_id

          [manifest['cases'].find { |item| item['case_id'] == case_id } ||
            raise(Error, "unknown case: #{case_id}")]
        end

        private

        def validate_source!
          source = manifest['source']
          require_keys(source, %w[repository remote_url revision spdx_license license_evidence_url oracle_rationale],
                       'source')
          validate_sha!(source['revision'], 'source.revision')
          raise Error, 'source.remote_url must use https' unless source['remote_url'].start_with?('https://')
          raise Error, 'source.license_evidence_url must use https' unless source['license_evidence_url'].start_with?('https://')
        end

        def validate_backlog!
          backlog = manifest['admission_backlog']
          raise Error, 'admission_backlog must be an array' unless backlog.is_a?(Array)

          backlog.each do |item|
            require_keys(item, %w[candidate_id status reason score_eligible], 'admission_backlog item')
            unless BACKLOG_STATUSES.include?(item['status'])
              raise Error, "#{item['candidate_id']}: unsupported backlog status"
            end
            if item['status'] == 'blocked' && item['score_eligible']
              raise Error, "#{item['candidate_id']}: blocked candidate cannot be score eligible"
            end
            next unless item['status'] == 'admitted'

            require_keys(item, %w[case_id], 'admitted backlog item')
          end
        end

        def validate_admitted_backlog!(case_ids)
          manifest['admission_backlog'].select { |item| item['status'] == 'admitted' }.each do |item|
            raise Error, "#{item['candidate_id']}: admitted case is missing" unless case_ids.include?(item['case_id'])

            admitted = manifest['cases'].find { |candidate| candidate['case_id'] == item['case_id'] }
            next if item['score_eligible'] == admitted.dig('oracle', 'score_eligible')

            raise Error, "#{item['candidate_id']}: backlog and case score eligibility differ"
          end
        end

        def validate_case!(item)
          require_keys(item, REQUIRED_CASE_KEYS, 'case')
          raise Error, 'case_id must be lowercase kebab-case' unless CASE_ID_PATTERN.match?(item['case_id'].to_s)

          validate_sha!(item['merge_commit'], "#{item['case_id']}.merge_commit")
          validate_sha!(item['base_commit'], "#{item['case_id']}.base_commit")
          parents = item['parent_commits']
          unless parents.is_a?(Array) && parents.length == 2
            raise Error,
                  "#{item['case_id']}: exactly two parents required"
          end

          parents.each { |sha| validate_sha!(sha, "#{item['case_id']}.parent_commits") }
          validate_blobs!(item)
          validate_selector!(item)
          validate_oracle!(item)
          item['case_id']
        end

        def validate_blobs!(item)
          require_keys(item['blob_oids'], %w[base ours theirs human], "#{item['case_id']}.blob_oids")
          item['blob_oids'].each_value { |oid| validate_sha!(oid, "#{item['case_id']}.blob_oids") }
          path = item['path']
          return unless path.empty? || Pathname(path).absolute? || path.split('/').include?('..')

          raise Error,
                "#{item['case_id']}: path must be relative"
        end

        def validate_selector!(item)
          selector = item['selector']
          require_keys(selector, %w[provider_id family dialect backend profile require], "#{item['case_id']}.selector")
          require_keys(item['stratum'], %w[provider dialect conflict_type], "#{item['case_id']}.stratum")
          return if item['capability_tags'].is_a?(Array) && item['capability_tags'].any?

          raise Error,
                "#{item['case_id']}: capability_tags must not be empty"
        end

        def validate_oracle!(item)
          oracle = item['oracle']
          require_keys(
            oracle,
            %w[classification human_resolution_rationale ambiguity_status reclassification_status
               false_auto_merge_review score_eligible],
            "#{item['case_id']}.oracle"
          )
          unless CLASSIFICATIONS.include?(oracle['classification'])
            raise Error, "#{item['case_id']}: unsupported oracle classification"
          end

          eligible = oracle['score_eligible']
          reviewed = oracle['false_auto_merge_review'] == 'complete'
          unscorable = %w[ambiguous_manual_review excluded].include?(oracle['classification'])
          raise Error, "#{item['case_id']}: case cannot be score eligible" if eligible && (!reviewed || unscorable)
          return unless oracle['classification'] == 'structurally_equivalent_resolution'

          require_keys(item, %w[conflict_evidence review], item['case_id'])
          require_keys(
            item['conflict_evidence'],
            %w[method result review_status],
            "#{item['case_id']}.conflict_evidence"
          )
          require_keys(item['review'], %w[provenance status], "#{item['case_id']}.review")
          require_keys(oracle, %w[provider_coverage], "#{item['case_id']}.oracle")
          coverage = oracle['provider_coverage']
          require_keys(coverage, %w[status reason], "#{item['case_id']}.oracle.provider_coverage")
          complete = item.dig('conflict_evidence', 'result') == 'content_conflict' &&
                     item.dig('conflict_evidence', 'review_status') == 'complete' &&
                     item.dig('review', 'status') == 'complete'
          raise Error, "#{item['case_id']}: reviewed conflict evidence is incomplete" unless complete
          return unless eligible && coverage['status'] != 'supported'

          raise Error, "#{item['case_id']}: unsupported provider coverage cannot be score eligible"
        end

        def require_keys(hash, keys, context)
          raise Error, "#{context} must be an object" unless hash.is_a?(Hash)

          missing = keys.reject { |key| hash.key?(key) }
          raise Error, "#{context} missing: #{missing.join(', ')}" if missing.any?
        end

        def validate_sha!(sha, context)
          raise Error, "#{context} must be a full lowercase SHA" unless SHA_PATTERN.match?(sha.to_s)
        end
      end

      # Executes validated corpus cases without changing the source checkout.
      class CorpusRunner
        DEFAULT_TIMEOUT = 30
        OUTCOMES = %w[
          correct_clean false_conflict true_conflict false_auto_merge error unsupported excluded_ambiguous
        ].freeze

        def initialize(corpus:, repository:, driver_path:, tmp_root:, timeout: DEFAULT_TIMEOUT)
          @corpus = corpus
          @repository = Pathname(repository).expand_path
          @driver_path = Pathname(driver_path).expand_path
          @tmp_root = Pathname(tmp_root).expand_path
          @timeout = Integer(timeout)
        end

        def run(case_id: nil)
          verify_environment!
          @corpus.cases(case_id).map { |item| run_case(item) }
        end

        private

        def verify_environment!
          raise Corpus::Error, "missing repository: #{@repository}" unless @repository.join('.git').exist?
          unless @driver_path.file? && @driver_path.executable?
            raise Corpus::Error,
                  "missing installed driver: #{@driver_path}"
          end
          raise Corpus::Error, 'tmp_root must be inside the ast-merge-git repository' unless inside_gem_root?(@tmp_root)

          status = git_source('status', '--porcelain')
          raise Corpus::Error, 'source repository is dirty; corpus reads require a clean checkout' unless status.empty?

          git_source('cat-file', '-e', "#{@corpus.manifest.dig('source', 'revision')}^{commit}")
        end

        def inside_gem_root?(path)
          root = Pathname(__dir__).join('..', '..', '..', '..').realpath
          resolved = path.exist? ? path.realpath : path.dirname.realpath.join(path.basename)
          resolved.to_s.start_with?("#{root}/")
        end

        def run_case(item)
          roles = prove_and_read_blobs(item)
          workspace = @tmp_root.join("#{item['case_id']}-#{Process.pid}")
          FileUtils.rm_rf(workspace)
          FileUtils.mkdir_p(workspace)
          git_workspace(workspace, 'init', '--quiet')
          configure_driver(workspace, item)

          baseline = execute_baseline(workspace, roles)
          candidate = execute_candidate(workspace, roles, item)
          rerun = execute_candidate(workspace, roles, item)
          build_result(item, roles, baseline, candidate, rerun)
        ensure
          FileUtils.rm_rf(workspace) if workspace
        end

        def prove_and_read_blobs(item)
          git_source(
            'merge-base',
            '--is-ancestor',
            item['merge_commit'],
            @corpus.manifest.dig('source', 'revision')
          )
          parents = git_source('rev-list', '--parents', '-n', '1', item['merge_commit']).split
          raise Corpus::Error, "#{item['case_id']}: merge must have exactly two parents" unless parents.length == 3
          raise Corpus::Error, "#{item['case_id']}: parent SHAs differ" unless parents.drop(1) == item['parent_commits']

          base = git_source('merge-base', *item['parent_commits']).strip
          raise Corpus::Error, "#{item['case_id']}: merge-base differs" unless base == item['base_commit']

          revisions = {
            'base' => item['base_commit'],
            'ours' => item['parent_commits'][0],
            'theirs' => item['parent_commits'][1],
            'human' => item['merge_commit']
          }
          revisions.to_h do |role, revision|
            spec = "#{revision}:#{item['path']}"
            oid = git_source('rev-parse', spec).strip
            raise Corpus::Error, "#{item['case_id']}: #{role} blob differs" unless oid == item.dig('blob_oids', role)

            [role, git_source_binary('cat-file', 'blob', spec)]
          end
        end

        def configure_driver(workspace, item)
          selector = item['selector']
          env = selector_env(selector).map { |key, value| "#{key}=#{Shellwords.escape(value)}" }.join(' ')
          command = "#{env} #{Shellwords.escape(@driver_path.to_s)} %O %A %B %P %L"
          git_workspace(workspace, 'config', 'merge.structuredmerge-corpus.name', 'StructuredMerge corpus driver')
          git_workspace(workspace, 'config', 'merge.structuredmerge-corpus.driver', command)
        end

        def execute_baseline(workspace, roles)
          write_roles(workspace, roles)
          timed_capture({}, 'git', 'merge-file', '-p', 'ours', 'base', 'theirs', chdir: workspace).then do |capture|
            capture.merge(output: capture[:stdout])
          end
        end

        def execute_candidate(workspace, roles, item)
          write_roles(workspace, roles)
          capture = timed_capture(
            candidate_env(item['selector']),
            @driver_path.to_s,
            'base',
            'ours',
            'theirs',
            item['path'],
            '7',
            chdir: workspace
          )
          capture.merge(output: workspace.join('ours').binread)
        end

        def write_roles(workspace, roles)
          %w[base ours theirs].each { |role| workspace.join(role).binwrite(roles.fetch(role)) }
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
          forbidden = ENV.keys.grep(/ORACLE|HUMAN|EXPECTED/i).to_h { |key| [key, nil] }
          forbidden.merge(selector_env(selector))
        end

        def build_result(item, roles, baseline, candidate, rerun)
          {
            schema_version: 1,
            case_id: item['case_id'],
            source: item.slice('merge_commit', 'base_commit', 'parent_commits', 'path', 'blob_oids'),
            oracle: item['oracle'],
            baseline: outcome(baseline, roles['human'], item, adapter: :git_merge_file),
            candidate: outcome(candidate, roles['human'], item, adapter: :structured_merge),
            human_result: { sha256: digest(roles['human']), bytes: roles['human'].bytesize },
            deterministic_rerun: deterministic?(candidate, rerun),
            claim_eligibility: claim_eligibility(item),
            runtime_policy: { comparable: false, deterministic: false }
          }
        end

        def outcome(capture, human, item, adapter:)
          output = capture.fetch(:output)
          markers = conflict_markers(output)
          exact = output == human
          provider = provider_equivalence(output, human, item, exact)
          exit_class = exit_classification(capture[:status], adapter)
          classified = classify(item, exit_class, exact || provider[:equivalent])
          {
            exit_status: capture[:status],
            exit_classification: exit_class,
            stdout: capture[:stdout],
            stderr: capture[:stderr],
            output: output,
            output_sha256: digest(output),
            exact_human_result: exact,
            structurally_equivalent_human_result: provider[:equivalent],
            provider_check: provider,
            parse_valid: provider[:available] ? provider[:valid] : nil,
            outcome: classified,
            conflict_markers: markers,
            duration_ns: capture[:duration_ns],
            runtime_comparable: false
          }
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
          status = timed_out ? 2 : process.value.exitstatus
          { stdout: stdout, stderr: stderr, status: status,
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

        def git_source(*args)
          run_git(@repository, *args)
        end

        def git_source_binary(*args)
          run_git(@repository, *args, binary: true)
        end

        def git_workspace(workspace, *args)
          run_git(workspace, *args)
        end

        def run_git(directory, *args, binary: false)
          options = args.last.is_a?(Hash) ? args.pop : {}
          stdout, stderr, status = Open3.capture3('git', '-C', directory.to_s, *args, binmode: true)
          raise Corpus::Error, "git #{args.first} failed: #{stderr.strip}" unless status.success?

          binary || options[:binary] ? stdout : stdout.force_encoding(Encoding::UTF_8)
        end

        def digest(content)
          Digest::SHA256.hexdigest(content)
        end

        def exit_classification(status, adapter)
          return 'error' unless status
          return status.zero? ? 'clean' : (status == 255 ? 'error' : 'conflict') if adapter == :git_merge_file

          { 0 => 'clean', 1 => 'conflict', 2 => 'error' }.fetch(status, 'error')
        end

        def classify(item, exit_class, equivalent)
          classification = item.dig('oracle', 'classification')
          return 'excluded_ambiguous' if %w[ambiguous_manual_review excluded].include?(classification)
          return 'error' if exit_class == 'error'
          return exit_class == 'conflict' ? 'true_conflict' : 'false_auto_merge' if classification == 'conflict_expected'
          return 'false_conflict' if exit_class == 'conflict'
          return 'correct_clean' if equivalent

          'false_auto_merge'
        end

        def deterministic?(first, second)
          %i[status stdout stderr].all? { |key| first[key] == second[key] } &&
            first[:output] == second[:output]
        end

        def claim_eligibility(item)
          oracle = item['oracle']
          eligible = oracle['score_eligible'] &&
                     oracle['false_auto_merge_review'] == 'complete' &&
                     !%w[ambiguous_manual_review excluded].include?(oracle['classification'])
          { score_eligible: eligible,
            quality_claim_allowed: eligible && @corpus.manifest.dig('claim_policy', 'quality_claims_allowed') }
        end

        def provider_equivalence(output, human, item, exact)
          selector = item.fetch('selector')
          method = 'selected_provider.diff2(expected_human, candidate_output).changes.empty?'
          if exact
            return { equivalent: true, available: true, valid: true,
                     provider_id: selector['provider_id'], method: 'exact_bytes' }
          end

          require selector.fetch('require')
          result = Ast::Merge.dispatch_provider(
            :diff2,
            {
              provider_id: selector.fetch('provider_id'),
              family: selector.fetch('family'),
              dialect: selector.fetch('dialect'),
              backend: selector.fetch('backend'),
              profile_id: selector.fetch('profile'),
              before_source: human,
              after_source: output,
              path_name: item.fetch('path')
            }
          )
          valid = result[:ok] == true
          { equivalent: valid && result.fetch(:changes).empty?, available: true, valid: valid,
            provider_id: selector['provider_id'], method: method,
            diagnostic_codes: Array(result[:diagnostics]).filter_map { |entry| entry[:code] || entry['code'] } }
        rescue Ast::Merge::Error, KeyError, LoadError => e
          { equivalent: false, available: false, valid: false,
            provider_id: selector['provider_id'], method: method,
            error: "#{e.class}: #{e.message}" }
        end

        # Conflict markers are Git's line protocol, not syntax nodes; byte scans
        # intentionally avoid parser-specific ownership claims.
        def conflict_markers(output)
          ranges = []
          start_byte = nil
          offset = 0
          output.each_line do |line|
            start_byte = offset if line.start_with?('<<<<<<<')
            if start_byte && line.start_with?('>>>>>>>')
              ranges << { start_byte: start_byte,
                          end_byte: offset + line.bytesize }
            end
            start_byte = nil if start_byte && line.start_with?('>>>>>>>')
            offset += line.bytesize
          end
          { present: ranges.any?, count: ranges.length, byte_ranges: ranges }
        end
      end

      # Explicitly acquires a pinned remote without changing an existing tree.
      class CorpusAcquirer
        class << self
          def acquire(corpus:, destination:, tmp_root:)
            corpus.validate!
            destination = Pathname(destination).expand_path
            tmp_root = Pathname(tmp_root).expand_path
            validate_destination!(destination, tmp_root)

            FileUtils.mkdir_p(destination.dirname)
            clone!(corpus.manifest.dig('source', 'remote_url'), destination)
            revision = corpus.manifest.dig('source', 'revision')
            git!('pinned revision missing after clone', '-C', destination.to_s, 'cat-file', '-e',
                 "#{revision}^{commit}")
            git!('pinned revision checkout failed', '-C', destination.to_s, 'checkout', '--detach', '--quiet',
                 revision)
            destination
          end

          private

          def validate_destination!(destination, tmp_root)
            gem_root = Pathname(__dir__).join('..', '..', '..', '..').realpath
            resolved_tmp = tmp_root.exist? ? tmp_root.realpath : tmp_root.dirname.realpath.join(tmp_root.basename)
            unless resolved_tmp.to_s.start_with?("#{gem_root}/")
              raise Corpus::Error, 'clone tmp root must be inside the ast-merge-git repository'
            end
            unless destination.to_s.start_with?("#{tmp_root}/")
              raise Corpus::Error, 'clone destination must be inside the configured repo-local tmp root'
            end
            raise Corpus::Error, "clone destination already exists: #{destination}" if destination.exist?
          end

          def clone!(remote, destination)
            git!('git clone failed', 'clone', '--no-checkout', '--filter=blob:none', remote, destination.to_s)
          end

          def git!(message, *arguments)
            _stdout, stderr, status = Open3.capture3('git', *arguments, binmode: true)
            raise Corpus::Error, "#{message}: #{stderr.strip}" unless status.success?
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
  end
end
