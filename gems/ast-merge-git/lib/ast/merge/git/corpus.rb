# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
require 'timeout'

module Ast
  module Merge
    module Git
      # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength -- evidence validation and raw-result assembly remain explicit and auditable
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
            raise Error, "#{item['candidate_id']}: blocked candidate cannot be score eligible" if item['score_eligible']
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
            selector_env(item['selector']),
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

        def build_result(item, roles, baseline, candidate, rerun)
          {
            schema_version: 1,
            case_id: item['case_id'],
            source: item.slice('merge_commit', 'base_commit', 'parent_commits', 'path', 'blob_oids'),
            oracle: item['oracle'],
            baseline: outcome(baseline, roles['human'], item),
            candidate: outcome(candidate, roles['human'], item),
            human_result: { sha256: digest(roles['human']), bytes: roles['human'].bytesize },
            deterministic_rerun: deterministic?(candidate, rerun),
            claim_eligibility: claim_eligibility(item),
            runtime_policy: { comparable: false, deterministic: false }
          }
        end

        def outcome(capture, human, item)
          output = capture.fetch(:output)
          markers = conflict_markers(output)
          exact = output == human
          {
            exit_status: capture[:status],
            exit_classification: exit_classification(capture[:status]),
            stdout: capture[:stdout],
            stderr: capture[:stderr],
            output: output,
            output_sha256: digest(output),
            exact_human_result: exact,
            structurally_equivalent_human_result: structural_equivalence(output, human, item, exact),
            parse_valid: parse_validity(output, item),
            conflict_markers: markers,
            duration_ns: capture[:duration_ns],
            runtime_comparable: false
          }
        end

        def timed_capture(env, *command, chdir:)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          stdout = stderr = status = nil
          Timeout.timeout(@timeout) do
            stdout, stderr, process_status = Open3.capture3(env, *command, chdir: chdir.to_s, binmode: true)
            status = process_status.exitstatus
          end
          { stdout: stdout, stderr: stderr, status: status,
            duration_ns: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started }
        rescue Timeout::Error
          raise Corpus::Error, "command timed out after #{@timeout}s: #{command.first}"
        rescue Errno::ENOENT => e
          raise Corpus::Error, "command missing: #{e.message}"
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

        def exit_classification(status)
          { 0 => 'clean', 1 => 'conflict', 2 => 'error' }.fetch(status, 'error')
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

        def parse_validity(output, item)
          return nil unless item.dig('selector', 'dialect') == 'ruby'

          require 'prism'
          Prism.parse(output).success?
        rescue LoadError
          nil
        end

        def structural_equivalence(output, human, item, exact)
          return true if exact
          return nil unless item.dig('selector', 'dialect') == 'ruby'

          require 'prism'
          left = Prism.parse(output)
          right = Prism.parse(human)
          return false unless left.success? && right.success?

          Prism.dump(output) == Prism.dump(human)
        rescue LoadError
          nil
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
      # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/MethodLength
    end
  end
end
