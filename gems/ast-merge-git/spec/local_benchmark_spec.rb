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
    expect(benchmark.cases.length).to eq(15)
    expect(benchmark.document.fetch('expected_summary')).to include(
      'case_count' => 15,
      'partition_counts' => { 'sentinel' => 3, 'gold' => 10, 'metamorphic' => 2 },
      'operation_counts' => { 'merge3' => 13, 'metamorphic' => 2 }
    )
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

    expect(checks).to include('structural' => true, 'acceptable' => false)
    expect(checks.fetch('preservation_violations')).to include('formatting')
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
      invocation['argv'].length == 5 &&
        invocation['argv'].first(3) == %w[base ours theirs] &&
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
    previous = ENV['BENCHMARK_EXPECTED_ORACLE_BYTES']
    ENV['BENCHMARK_EXPECTED_ORACLE_BYTES'] = 'must-not-reach-competitor'
    report = Ast::Merge::Git::LocalBenchmarkReport.build(competitive_runner.run(profile: 'micro'))

    expect(report.dig('dimensions', 'competitive', 'configured', 'mergiraf')).to include(
      'source_revision' => '13b813c02da9511c7433131aed142473ffe62d52',
      'reported_version' => 'mergiraf 0.18.0'
    )
    expect(report.dig('dimensions', 'competitive')).to include(
      'outcomes' => { 'false_conflict' => 2, 'true_conflict' => 1 },
      'unsupported_case_ids' => [],
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

    it 'preserves intentional-conflict safety and attributes malformed ours errors' do
      by_case = run.fetch('results').group_by { |item| item['case_id'] }
      conflict = by_case.fetch('case.merge3.json.same-owner-conflict.v1')
      malformed = by_case.fetch('case.merge3.json.malformed-ours.v1').last

      expect(conflict.map { |item| item['outcome'] }).to eq(%w[true_conflict true_conflict])
      expect(malformed['outcome']).to eq('error')
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
