# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'json'

# rubocop:disable Metrics/BlockLength -- examples exercise the complete safety-focused CLI/API contract
RSpec.describe Ast::Merge::Git::LocalBenchmark do
  let(:corpus_path) do
    Pathname(__dir__).join(
      '..', '..', '..', '..', 'fixtures', 'diagnostics',
      'slice-1023-local-paired-benchmark', 'corpus.json'
    ).expand_path
  end
  let(:benchmark) { described_class.load(corpus_path) }
  let(:tmp_root) { Pathname(__dir__).join('..', 'tmp', "local-benchmark-spec-#{Process.pid}").expand_path }
  let(:driver) { Gem.bin_path('ast-merge-git', 'ast-merge-git') }
  let(:runner) do
    Ast::Merge::Git::LocalBenchmarkRunner.new(
      benchmark: benchmark,
      driver_path: driver,
      tmp_root: tmp_root
    )
  end

  after { FileUtils.rm_rf(tmp_root) }

  it 'validates the exact canonical authored corpus and inline digests' do
    expect(benchmark.validate!).to be(true)
    expect(benchmark.cases.length).to eq(16)
    expect(benchmark.document.fetch('expected_summary')).to include(
      'case_count' => 16,
      'partition_counts' => { 'sentinel' => 7, 'gold' => 7, 'metamorphic' => 2 },
      'operation_counts' => { 'merge2' => 1, 'merge3' => 13, 'metamorphic' => 2 }
    )
    expect(benchmark.document.fetch('profiles').keys).to eq(%w[micro dev nightly competitive])
    expect(benchmark.document.fetch('provenance')).to include(
      'spdx_license' => 'CC0-1.0',
      'authorship' => 'project_authored',
      'author_review' => 'reviewed'
    )
  end

  it 'selects the exact micro sentinels and explains every selection category' do
    selection = benchmark.select(profile: 'micro', changed_paths: ['gems/json-merge/lib/json/merge.rb'])

    expect(selection.fetch('selected_case_ids')).to eq(
      %w[
        case.merge3.json.independent-fields.v1
        case.merge3.json.same-owner-conflict.v1
        case.merge3.json.malformed-ours.v1
        case.merge2.jsonc.current-layout-preservation.v1
        case.merge3.jsonc.comment-preservation.v1
        case.merge3.json5.order-format.v1
        case.merge3.json.duplicate-identity.v1
      ]
    )
    expect(selection.fetch('explanation')).to include(
      'profile_rule' => 'mandatory sentinels only',
      'budget_rule' => 'selection fits declared case budget; no silent extension or dropping'
    )
    expect(selection.dig('neighbor_sample', 'selected_case_ids')).to be_empty
  end

  it 'maps changed paths to all directly affected cases plus deterministic neighbors' do
    first = benchmark.select(profile: 'dev', changed_paths: ['gems/json-merge/lib/provider.rb'])
    second = benchmark.select(profile: 'dev', changed_paths: ['gems/json-merge/lib/provider.rb'])

    expect(first).to eq(second)
    expect(first.fetch('inferred_capabilities')).to eq(%w[json json5 jsonc metamorphic])
    expect(first.fetch('direct_cases')).to include(
      'case.merge3.jsonc.comment-preservation.v1',
      'case.merge3.json5.order-format.v1',
      'case.metamorphic.jsonc.comment-format.v1'
    )
    expect(first.dig('neighbor_sample', 'selected_case_ids')).to eq(
      %w[case.merge3.toml.independent-tables.v1 case.merge3.yaml.delete-modify.v1]
    )
  end

  it 'selects all admitted cases only for nightly and competitive tiers' do
    expected_ids = benchmark.cases.map { |item| item.fetch('id') }

    nightly = benchmark.select(profile: 'nightly')
    competitive = benchmark.select(profile: 'competitive')

    expect(nightly).to include(
      'selection_mode' => 'all',
      'competitor_policy' => 'none',
      'selected_case_ids' => expected_ids,
      'excluded_case_ids' => []
    )
    expect(competitive).to include(
      'selection_mode' => 'all',
      'competitor_policy' => 'configured',
      'selected_case_ids' => expected_ids,
      'excluded_case_ids' => []
    )
    expect(competitive.dig('explanation', 'profile_rule')).to eq('all admitted cases in canonical corpus order')
  end

  it 'rejects malformed cases before execution' do
    document = JSON.parse(corpus_path.binread)
    document.dig('cases', 0, 'inputs', 'base')['sha256'] = '0' * 64

    expect { described_class.new(document).validate! }.to raise_error(
      described_class::Error,
      /SHA-256 does not match exact bytes/
    )
  end

  it 'rejects an exact oracle artifact that diverges from expected output bytes' do
    document = JSON.parse(corpus_path.binread)
    item = document.fetch('cases').find { |candidate| candidate.dig('oracle', 'class') == 'exact' }
    item.dig('oracle', 'artifact')['bytes'] = "different\n"
    item.dig('oracle', 'artifact')['sha256'] = Digest::SHA256.hexdigest("different\n")

    expect { described_class.new(document).validate! }.to raise_error(
      described_class::Error,
      /exact oracle artifact must match expected output bytes/
    )
  end

  it 'uses each selected provider diff for semantic equivalence across executable dialects' do
    variants = {
      'json' => ["{\"a\":1,\"b\":2}\n", "{ \"b\": 2, \"a\": 1 }\n"],
      'jsonc' => ["{\n  // retained\n  \"a\": 1\n}\n", "{\n// retained\n\"a\":1\n}\n"],
      'json5' => ["{ a: 1, b: 2, }\n", "{b:2,a:1}\n"],
      'ruby' => ["class A\n  def x = 1\nend\n", "\nclass A\n  def x = 1\nend\n"],
      'yaml' => ["a: 1\nb: 2\n", "b: 2\na: 1\n"],
      'toml' => ["a = 1\nb = 2\n", "b = 2\na = 1\n"],
      'markdown' => ["# A\none\n# B\ntwo\n", "# B\ntwo\n# A\none\n"],
      'html' => ["<div id=\"a\">x</div>\n", "\n<div id=\"a\">x</div>\n"],
      'bash' => ["f() { echo x; }\n", "\nf() { echo x; }\n"],
      'typescript' => ["function f() { return 1; }\n", "\nfunction f() { return 1; }\n"]
    }

    variants.each do |dialect, (expected, output)|
      item = semantic_case(dialect, expected)
      checks = runner.send(:equivalence_checks, item, output)

      expect(checks).to include(
        'exact' => false,
        'structural' => true,
        'accepted_equivalence' => 'structural_ast',
        'acceptable' => true
      ), dialect
    end
  end

  it 'enforces exact source preservation even when provider semantics match' do
    item = semantic_case('json5', "{ a: 1, }\n")
    item['preservation_policy']['formatting'] = 'required'

    checks = runner.send(:equivalence_checks, item, "{a:1}\n")

    expect(checks).to include(
      'structural' => true,
      'equivalence_acceptable' => true,
      'preservation_acceptable' => false,
      'acceptable' => false
    )
    expect(checks.fetch('preservation_violations')).to include('formatting')
    expect(runner.send(:classify, item, 0, checks)).to eq('correct_clean')
  end

  it 'does not infer unrelated preservation losses from byte inequality' do
    item = semantic_case('json5', "{ a: 1, }\n")
    item['preservation_policy'].transform_values! { 'required' }

    checks = runner.send(:equivalence_checks, item, "{a:1}\n".b)

    expect(checks.fetch('preservation_violations')).to contain_exactly('formatting', 'source_regions')
    expect(checks.fetch('preservation_unverified')).to contain_exactly('comments', 'order')
    expect(checks.fetch('preservation_evaluations')).to include(
      'encoding' => 'pass',
      'line_endings' => 'pass',
      'unknown_fields' => 'pass'
    )
  end

  it 'does not use structural equality unless the ordered policy names the selected provider' do
    item = semantic_case('json', "{\"a\":1}\n")
    item['acceptable_equivalence'] = [{ 'class' => 'exact_bytes' }]
    absent = runner.send(:equivalence_checks, item, "{ \"a\": 1 }\n")
    item['acceptable_equivalence'] << {
      'class' => 'structural_ast', 'provider' => 'ruby.not-selected', 'required' => true
    }
    mismatched = runner.send(:equivalence_checks, item, "{ \"a\": 1 }\n")

    expect(absent).to include('structural' => true, 'acceptable' => false)
    expect(mismatched).to include('structural' => true, 'acceptable' => false)
  end

  it 'reports unknown localization rather than matching incompatible coordinate spaces' do
    item = { 'expected_conflict_regions' => [{ 'id' => 'left' }, { 'id' => 'right' }] }
    evidence = runner.send(:region_evidence, item, [{ 'start_byte' => 4, 'end_byte' => 20 }])

    expect(evidence).to include(
      'matched_region_ids' => [],
      'missed_region_ids' => %w[left right],
      'false_positive_region_ids' => ['observed.1'],
      'localization_status' => 'unknown',
      'localization_error_bytes' => nil
    )
  end

  it 'reports no extras when neither expected nor observed regions exist' do
    evidence = runner.send(:region_evidence, { 'expected_conflict_regions' => [] }, [])

    expect(evidence).to include(
      'matched_region_ids' => [],
      'missed_region_ids' => [],
      'false_positive_region_ids' => [],
      'localization_status' => 'not_applicable'
    )
  end

  it 'includes changed-path capabilities and the complete rationale digest in cache identity' do
    selection = benchmark.select(profile: 'dev', changed_paths: ['gems/json-merge/lib/provider.rb'])
    changed = Marshal.load(Marshal.dump(selection))
    changed['explanation']['budget_rule'] = 'different rationale with the same selected set'
    first = runner.send(:cache_identity, selection)
    second = runner.send(:cache_identity, changed)

    expect(first).to include(
      'changed_paths' => selection['changed_paths'],
      'inferred_capabilities' => selection['inferred_capabilities']
    )
    expect(first['selected_case_ids']).to eq(second['selected_case_ids'])
    expect(first['selection_explanation_sha256']).not_to eq(second['selection_explanation_sha256'])
    expect(first['sha256']).not_to eq(second['sha256'])
  end

  it 'records complete Ruby golden-master adapter and parser provenance in every run manifest' do
    selection = benchmark.select(profile: 'micro')
    manifest = runner.send(:run_manifest, selection)

    expect(manifest).to include(
      'schema_version' => 'structuredmerge.benchmark.run-manifest/v1',
      'sha256' => match(/\A[0-9a-f]{64}\z/)
    )
    expect(manifest.fetch('adapter')).to include(
      'adapter_id' => 'ruby-gm.ast-merge-git',
      'implementation' => 'ruby-golden-master',
      'package' => 'ast-merge-git',
      'package_version' => Ast::Merge::Git::VERSION,
      'source' => include(
        'repository' => 'structuredmerge/structuredmerge-ruby',
        'revision' => match(/\A[0-9a-f]{40}\z/),
        'dirty' => satisfy { |value| [true, false].include?(value) }
      ),
      'artifact' => include('path' => driver, 'sha256' => match(/\A[0-9a-f]{64}\z/))
    )
    expect(manifest.fetch('configuration')).to include(
      'profile' => 'micro',
      'selected_case_ids' => selection.fetch('selected_case_ids'),
      'network_policy' => 'denied'
    )
    manifest.dig('configuration', 'cases').each do |case_configuration|
      expect(case_configuration).to include(
        'merge_provider' => include('provider_id' => 'ruby.json', 'require_path' => 'json/merge'),
        'parser_provider' => include(
          'requested_backend_id' => 'kreuzberg-language-pack',
          'backend_family' => 'tree-sitter',
          'selection_mode' => 'explicit'
        )
      )
    end
    expect(manifest.fetch('environment')).to include(
      'ruby' => RUBY_DESCRIPTION,
      'ruby_engine' => RUBY_ENGINE,
      'ruby_version' => RUBY_VERSION,
      'rubygems' => Gem::VERSION,
      'platform' => RUBY_PLATFORM,
      'allowlisted_env' => include('TREE_HAVER_BACKEND', 'TSLP_DEV')
    )
  end

  it 'carries run-manifest identity into cache and aggregate report evidence' do
    run = runner.run(profile: 'micro')
    report = Ast::Merge::Git::LocalBenchmarkReport.build(run)

    expect(run.dig('cache_identity', 'run_manifest_sha256')).to eq(run.dig('run_manifest', 'sha256'))
    expect(run.dig('cache_identity', 'configuration_sha256')).to eq(
      runner.send(:canonical_digest, run.dig('run_manifest', 'configuration'))
    )
    expect(run.dig('cache_identity', 'parser_providers')).to eq(
      [
        {
          'requested_backend_id' => 'kreuzberg-language-pack',
          'backend_family' => 'tree-sitter',
          'selection_mode' => 'explicit'
        }
      ]
    )
    expect(report.fetch('run_manifest')).to eq(run.fetch('run_manifest'))
  end

  it 'measures repeated requests in one persistent process without classifying quality' do
    performance = runner.performance(profile: 'micro', iterations: 2)

    expect(performance).to include(
      'schema_version' => 'structuredmerge.benchmark.performance-run/v1',
      'kind' => 'performance_only',
      'quality_classification_performed' => false
    )
    expect(performance.dig('run_manifest', 'configuration', 'execution')).to include(
      'kind' => 'performance',
      'adapter_mode' => 'persistent-jsonl',
      'iterations' => 2
    )
    expect(performance.fetch('samples').length).to eq(14)
    expect(performance.dig('session', 'process_ids').length).to eq(1)
    expect(performance.dig('samples', 0, 'runtime', 'measurement_class')).to eq(
      'session_startup_and_first_request'
    )
    performance.fetch('samples').drop(1).each do |sample|
      expect(sample).to include(
        'process_id' => performance.dig('session', 'process_ids').first,
        'runtime' => include(
          'adapter_duration_ns' => be_positive,
          'harness_overhead_ns' => be >= 0,
          'round_trip_duration_ns' => be_positive,
          'measurement_class' => 'warm_persistent_process'
        )
      )
    end
    runtimes = performance.fetch('samples').map { |sample| sample.fetch('runtime') }
    expect(performance.fetch('timing')).to include(
      'spawn_duration_ns' => be_positive,
      'adapter_execution_total_ns' => runtimes.sum { |runtime| runtime.fetch('adapter_duration_ns') },
      'harness_overhead_total_ns' => runtimes.sum { |runtime| runtime.fetch('harness_overhead_ns') },
      'round_trip_total_ns' => runtimes.sum { |runtime| runtime.fetch('round_trip_duration_ns') },
      'quality_classification_uses_these_values' => false
    )
    runtimes.each do |runtime|
      expect(runtime.fetch('adapter_duration_ns') + runtime.fetch('harness_overhead_ns')).to eq(
        runtime.fetch('round_trip_duration_ns')
      )
    end
  end

  it 'round-trips arbitrary bytes through the benchmark adapter transport' do
    source = "\x00\xFFline\r\n".b

    encoded = Ast::Merge::Git::BenchmarkAdapter.encode_source(source)

    expect(Ast::Merge::Git::BenchmarkAdapter.decode_source(encoded)).to eq(source)
    expect(encoded.encoding).to eq(Encoding::US_ASCII)
  end

  it 'runs independent correctness cases in bounded workers and restores corpus order' do
    parallel_runner = Ast::Merge::Git::LocalBenchmarkRunner.new(
      benchmark: benchmark,
      driver_path: driver,
      tmp_root: tmp_root,
      workers: 3
    )

    run = parallel_runner.run(profile: 'micro')
    selected_ids = run.dig('selection', 'selected_case_ids')

    expect(run.fetch('execution')).to include(
      'workers_requested' => 3,
      'workers_used' => 3
    )
    expect(run.dig('execution', 'worker_process_ids')).to all(be_a(Integer))
    expect(run.dig('execution', 'worker_process_ids').uniq.length).to eq(3)
    expect(run.dig('run_manifest', 'configuration', 'execution')).to eq(
      'kind' => 'correctness',
      'adapter_mode' => 'cold-process',
      'workers' => 3
    )
    expect(run.fetch('results').each_slice(2).map { |pair| pair.first.fetch('case_id') }).to eq(selected_ids)
  end

  it 'rejects unbounded worker counts before execution' do
    expect do
      Ast::Merge::Git::LocalBenchmarkRunner.new(
        benchmark: benchmark,
        driver_path: driver,
        tmp_root: tmp_root,
        workers: Ast::Merge::Git::LocalBenchmarkRunner::MAX_WORKERS + 1
      )
    end.to raise_error(Ast::Merge::Git::LocalBenchmark::Error, /workers must be between/)
  end

  it 'never injects oracle or expected material into candidate arguments or selector environment' do
    FileUtils.mkdir_p(tmp_root)
    log_path = tmp_root.join('invocations.jsonl')
    recording_driver = tmp_root.join('recording-driver')
    recording_driver.binwrite(<<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      File.open(#{log_path.to_s.inspect}, 'ab') do |file|
        file.puts(JSON.generate('argv' => ARGV, 'selector_env' => ENV.select { |key, _| key.start_with?('AST_MERGE_') },
                                'forbidden_env' => ENV.select { |key, _| key.match?(/ORACLE|EXPECTED/i) }))
      end
      File.binwrite(ARGV.fetch(1), File.binread(ARGV.fetch(0)))
    RUBY
    FileUtils.chmod(0o755, recording_driver)
    previous = ENV['BENCHMARK_EXPECTED_ORACLE_BYTES']
    ENV['BENCHMARK_EXPECTED_ORACLE_BYTES'] = benchmark.cases.first.dig('oracle', 'artifact', 'bytes')
    described_class_runner(recording_driver).run(profile: 'micro')
    invocations = log_path.readlines.map { |line| JSON.parse(line) }

    expect(invocations).not_to be_empty
    expect(invocations).to all(satisfy do |invocation|
      merge3 = invocation['argv'].length == 5 && invocation['argv'].first(3) == %w[base ours theirs]
      merge2 = invocation['argv'].length == 4 && invocation['argv'].first == 'benchmark-provider-merge2'
      (merge3 || merge2) &&
        invocation['selector_env'].keys.all? { |key| key.start_with?('AST_MERGE_') } &&
        invocation['forbidden_env'].empty?
    end)
  ensure
    ENV['BENCHMARK_EXPECTED_ORACLE_BYTES'] = previous
  end

  it 'terminates and reaps a timed-out child process' do
    FileUtils.mkdir_p(tmp_root)
    pid_path = tmp_root.join('timed-out.pid')
    sleeper = tmp_root.join('sleeper')
    sleeper.binwrite(<<~RUBY)
      #!/bin/sh
      printf '%s' "$$" > #{pid_path}
      exec sleep 30
    RUBY
    FileUtils.chmod(0o755, sleeper)
    short_runner = described_class_runner(sleeper)
    short_runner.instance_variable_set(:@timeout, 1)

    capture = short_runner.send(:timed_capture, {}, sleeper.to_s, chdir: tmp_root)
    pid = Integer(pid_path.read)

    expect(capture).to include(status: 2)
    expect(capture[:stderr]).to include('timeout after 1s')
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  end

  it 'runs the corrected JSON5 and conservative TOML cases cleanly with exact native source' do
    run = runner.run(profile: 'dev', changed_paths: ['gems/json-merge/lib/provider.rb'])
    candidates = run.fetch('results').select { |result| result['adapter_role'] == 'candidate' }
    json5 = candidates.find { |result| result['case_id'] == 'case.merge3.json5.order-format.v1' }
    toml = candidates.find { |result| result['case_id'] == 'case.merge3.toml.independent-tables.v1' }

    expect(json5).to include('outcome' => 'correct_clean')
    expect(json5.dig('checks', 'exact')).to be(true)
    expect(json5.dig('raw', 'output', 'inline')).to include('first: 2', 'second: 2')
    expect(toml).to include('outcome' => 'correct_clean')
    expect(toml.dig('checks', 'exact')).to be(true)
    expect(toml.dig('raw', 'output', 'inline')).to eq("left = 2\nright = 2\n")
  end

  it 'executes provider diff2 through the installed driver boundary' do
    FileUtils.mkdir_p(tmp_root)
    source = tmp_root.join('source.json')
    transformed = tmp_root.join('transformed.json')
    source.binwrite("{\"a\":1,\"b\":2}\n")
    transformed.binwrite("{\n  \"b\": 2,\n  \"a\": 1\n}\n")
    env = {
      'AST_MERGE_PROVIDER' => 'ruby.json',
      'AST_MERGE_FAMILY' => 'json',
      'AST_MERGE_DIALECT' => 'json',
      'AST_MERGE_BACKEND' => 'kreuzberg-language-pack',
      'AST_MERGE_PROFILE' => 'source_preserving',
      'AST_MERGE_REQUIRE' => 'json/merge'
    }

    stdout, stderr, status = Open3.capture3(
      env,
      driver,
      'benchmark-provider-diff',
      source.to_s,
      transformed.to_s,
      'metamorphic.json'
    )
    result = JSON.parse(stdout)

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(result).to include('ok' => true, 'operation' => 'diff2', 'changes' => [])
  end

  it 'executes merge2 through the provider boundary against an explicit overwrite baseline' do
    baseline, candidate = runner.send(:execute_case, merge2_case)

    expect(baseline).to include(
      'adapter_id' => 'template.overwrite',
      'adapter_role' => 'baseline',
      'outcome' => 'false_auto_merge'
    )
    expect(candidate).to include(
      'adapter_id' => 'ast-merge-provider.merge2',
      'adapter_role' => 'candidate',
      'outcome' => 'correct_clean',
      'deterministic_correctness_rerun' => true
    )
    expect(JSON.parse(candidate.dig('raw', 'output', 'inline'))).to eq(
      'managed' => 1,
      'recommended' => true,
      'local' => true
    )
  end

  it 'executes a pinned merge competitor without letting its results alter the candidate safety gate' do
    FileUtils.mkdir_p(tmp_root)
    competitor = tmp_root.join('mergiraf')
    competitor.binwrite(<<~SH)
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        printf '%s\n' 'mergiraf 0.18.0'
        exit 0
      fi
      if [ -n "$BENCHMARK_EXPECTED_ORACLE_BYTES" ]; then
        exit 9
      fi
      git merge-file -p "$3" "$2" "$4" >"$6"
    SH
    FileUtils.chmod(0o755, competitor)
    competitive_runner = Ast::Merge::Git::LocalBenchmarkRunner.new(
      benchmark: benchmark,
      driver_path: driver,
      tmp_root: tmp_root.join('competitive-runs'),
      competitor_paths: { 'mergiraf' => competitor }
    )
    expect { competitive_runner.run(profile: 'micro') }.to raise_error(
      Ast::Merge::Git::LocalBenchmark::Error,
      /competitor adapters require the competitive profile/
    )
    previous = ENV['BENCHMARK_EXPECTED_ORACLE_BYTES']
    ENV['BENCHMARK_EXPECTED_ORACLE_BYTES'] = 'must-not-reach-competitor'
    report = Ast::Merge::Git::LocalBenchmarkReport.build(competitive_runner.run(profile: 'competitive'))

    expect(report.dig('dimensions', 'competitive', 'configured', 'mergiraf')).to include(
      'source_revision' => '13b813c02da9511c7433131aed142473ffe62d52',
      'reported_version' => 'mergiraf 0.18.0'
    )
    expect(report.dig('dimensions', 'competitive')).to include(
      'unsupported_case_ids' => [
        'case.merge2.jsonc.current-layout-preservation.v1',
        'case.merge3.jsonc.comment-preservation.v1',
        'case.merge3.json5.order-format.v1',
        'case.metamorphic.json.reorder-format.v1',
        'case.metamorphic.jsonc.comment-format.v1'
      ],
      'affects_candidate_safety_gate' => false
    )
    expect(report.dig('dimensions', 'safety', 'gate')).to eq('pass')
  ensure
    ENV['BENCHMARK_EXPECTED_ORACLE_BYTES'] = previous
  end

  context 'with the installed paired drivers' do
    subject(:run) do
      Ast::Merge::Git::LocalBenchmarkRunner.new(
        benchmark: benchmark,
        driver_path: driver,
        tmp_root: tmp_root
      ).run(profile: 'micro')
    end

    it 'turns a Git text conflict into a structurally verified candidate clean result' do
      results = run.fetch('results').select do |item|
        item['case_id'] == 'case.merge3.json.independent-fields.v1'
      end

      expect(results.map { |item| item['outcome'] }).to eq(%w[false_conflict correct_clean])
      expect(results.last.dig('checks', 'parse_validity_only_accepted')).to be(false)
      expect(results.last.dig('checks', 'acceptable')).to be(true)
      expect(results.last.fetch('deterministic_correctness_rerun')).to be(true)
    end

    it 'preserves intentional-conflict safety and accepts expected malformed-input rejection' do
      by_case = run.fetch('results').group_by { |item| item['case_id'] }
      conflict = by_case.fetch('case.merge3.json.same-owner-conflict.v1')
      malformed = by_case.fetch('case.merge3.json.malformed-ours.v1').last

      expect(conflict.map { |item| item['outcome'] }).to eq(%w[true_conflict true_conflict])
      expect(malformed['outcome']).to eq('correct_clean')
      expect(malformed.fetch('diagnostics').map { |item| item['message'] }.join).to include('ours parse error')
    end

    it 'preserves cwd, serializes as JSON, and calculates a stable cache identity' do
      cwd = Dir.pwd
      first = run
      second = run

      expect(Dir.pwd).to eq(cwd)
      expect(first.dig('cache_identity', 'sha256')).to eq(second.dig('cache_identity', 'sha256'))
      expect { JSON.generate(first) }.not_to raise_error
    end
  end

  # rubocop:disable Metrics/MethodLength -- complete benchmark evidence is intentionally explicit
  def merge2_case
    incoming = "{\"managed\":2,\"recommended\":true}\n"
    current = "{\"managed\":1,\"local\":true}\n"
    expected = "{\"managed\":1,\"recommended\":true,\"local\":true}\n"
    {
      'schema_version' => 'structuredmerge.benchmark/v1',
      'kind' => 'benchmark_case',
      'id' => 'case.merge2.json.current-owned-fields.v1',
      'operation' => 'merge2',
      'family' => 'json',
      'provider' => 'ruby.json',
      'dialect' => 'json',
      'capabilities' => %w[merge2 source_preserving structural_paths],
      'partition' => 'gold',
      'provenance' => benchmark.cases.first.fetch('provenance'),
      'oracle' => {
        'class' => 'structural_ast',
        'artifact' => inline_record(expected),
        'admission' => 'reviewed',
        'score_eligible' => true,
        'procedure' => 'Compare selected-provider structure and preservation requirements.'
      },
      'acceptable_equivalence' => [{
        'class' => 'structural_ast',
        'provider' => 'ruby.json',
        'required' => true
      }],
      'preservation_policy' => {
        'comments' => 'not_applicable',
        'formatting' => 'allowed_to_change',
        'order' => 'allowed_to_change',
        'encoding' => 'required',
        'line_endings' => 'required',
        'unknown_fields' => 'required',
        'source_regions' => 'allowed_to_change'
      },
      'false_auto_merge_severity' => 'high',
      'selector' => benchmark.cases.first.fetch('selector'),
      'inputs' => {
        'incoming' => inline_record(incoming),
        'current' => inline_record(current)
      },
      'independent_edits' => [
        { 'id' => 'incoming.recommended', 'side' => 'incoming', 'path' => '/recommended' },
        { 'id' => 'current.local', 'side' => 'current', 'path' => '/local' }
      ],
      'independent_edit_ids' => %w[incoming.recommended current.local],
      'expected_conflict_regions' => [],
      'expected' => { 'outcome' => 'clean', 'output' => inline_record(expected) },
      'expected_conflicts' => false
    }
  end
  # rubocop:enable Metrics/MethodLength

  def inline_record(bytes)
    { 'mode' => 'inline', 'bytes' => bytes, 'sha256' => Digest::SHA256.hexdigest(bytes) }
  end

  def semantic_case(dialect, expected)
    item = Marshal.load(Marshal.dump(benchmark.cases.find { |candidate| candidate['dialect'] == dialect }))
    item['expected'] = semantic_expected(expected)
    item['acceptable_equivalence'] = semantic_equivalence_policy(item)
    item['preservation_policy'] = semantic_preservation(item)
    item
  end

  def semantic_expected(expected)
    {
      'outcome' => 'clean',
      'output' => { 'mode' => 'inline', 'bytes' => expected, 'sha256' => Digest::SHA256.hexdigest(expected) }
    }
  end

  def semantic_equivalence_policy(item)
    [
      { 'class' => 'exact_bytes' },
      { 'class' => 'structural_ast', 'provider' => item.dig('selector', 'provider_id'), 'required' => true }
    ]
  end

  def semantic_preservation(item)
    item.fetch('preservation_policy').keys.to_h { |key| [key, 'allowed_to_change'] }.merge(
      'encoding' => 'required', 'line_endings' => 'required', 'unknown_fields' => 'required'
    )
  end

  def described_class_runner(driver_path)
    Ast::Merge::Git::LocalBenchmarkRunner.new(
      benchmark: benchmark,
      driver_path: driver_path,
      tmp_root: tmp_root.join('recorded-runs')
    )
  end

  it 'executes metamorphic cases as paired textual-versus-structural no-edit probes' do
    run = Ast::Merge::Git::LocalBenchmarkRunner.new(
      benchmark: benchmark,
      driver_path: driver,
      tmp_root: tmp_root
    ).run(profile: 'dev', changed_paths: ['gems/json-merge/lib/provider.rb'])
    report = Ast::Merge::Git::LocalBenchmarkReport.build(run)
    metamorphic = run.fetch('results').select { |result| result.dig('case_tags', 'operation') == 'metamorphic' }
    baseline = metamorphic.select { |result| result['adapter_role'] == 'baseline' }
    candidate = metamorphic.select { |result| result['adapter_role'] == 'candidate' }

    expect(baseline.map { |result| result['outcome'] }).to eq(%w[false_conflict false_conflict])
    expect(candidate.map { |result| result['outcome'] }).to eq(%w[correct_clean correct_clean])
    expect(candidate).to all(satisfy do |result|
      result.dig('checks', 'declared_invariants').all? { |invariant| invariant['matched'] } &&
        result['deterministic_correctness_rerun'] == true
    end)
    expect(report.fetch('newly_passing_case_ids')).to include(
      'case.metamorphic.json.reorder-format.v1',
      'case.metamorphic.jsonc.comment-format.v1'
    )
    expect(report.dig('dimensions', 'coverage', 'unsupported_case_ids')).to be_empty
    expect(report.dig('dimensions', 'coverage', 'unsupported_is_quality_failure')).to be(false)
    expect(report['scalar_score']).to be_nil
    expect { JSON.generate(report) }.not_to raise_error
  end

  it 'makes a simulated false auto-merge non-compensably fail the safety gate' do
    FileUtils.mkdir_p(tmp_root)
    unsafe_driver = tmp_root.join('unsafe-driver')
    unsafe_driver.binwrite("#!/usr/bin/env ruby\nexit 0\n")
    FileUtils.chmod(0o755, unsafe_driver)
    run = Ast::Merge::Git::LocalBenchmarkRunner.new(
      benchmark: benchmark,
      driver_path: unsafe_driver,
      tmp_root: tmp_root.join('runs')
    ).run(profile: 'micro')
    report = Ast::Merge::Git::LocalBenchmarkReport.build(run)

    expect(report.dig('dimensions', 'safety')).to include(
      'gate' => 'fail',
      'non_compensable' => true
    )
    expect(report.dig('dimensions', 'safety', 'false_auto_merge_result_ids')).not_to be_empty
  end
end
# rubocop:enable Metrics/BlockLength
