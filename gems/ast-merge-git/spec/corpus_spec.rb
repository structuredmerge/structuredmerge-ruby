# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'

# rubocop:disable Metrics/BlockLength, Metrics/MethodLength -- synthetic history setup documents the complete portable case contract
RSpec.describe Ast::Merge::Git::Corpus do
  def workspace
    Pathname(__dir__).join('..', 'tmp', "corpus-spec-#{Process.pid}").expand_path
  end

  def git(*args)
    stdout, stderr, status = Open3.capture3('git', '-C', workspace.to_s, *args)
    raise stderr unless status.success?

    stdout.strip
  end

  def commit(message)
    git('add', 'sample.rb')
    git('-c', 'user.name=Corpus Test', '-c', 'user.email=corpus@example.invalid', 'commit', '-q', '-m', message)
    git('rev-parse', 'HEAD')
  end

  def blob(revision)
    git('rev-parse', "#{revision}:sample.rb")
  end

  def synthetic_manifest
    base = commit('base')
    git('checkout', '-q', '-b', 'feature')
    workspace.join('sample.rb').binwrite("VALUE = 1\nputs VALUE\n")
    theirs = commit('feature')
    git('checkout', '-q', 'main')
    git('-c', 'user.name=Corpus Test', '-c', 'user.email=corpus@example.invalid',
        'merge', '--no-ff', '-q', '-m', 'merge feature', 'feature')
    merge = git('rev-parse', 'HEAD')

    {
      'schema_version' => 1,
      'corpus_id' => 'synthetic',
      'source' => {
        'repository' => 'synthetic/local',
        'remote_url' => 'https://example.invalid/synthetic.git',
        'revision' => merge,
        'spdx_license' => 'MIT',
        'license_evidence_url' => 'https://example.invalid/LICENSE',
        'oracle_rationale' => 'Synthetic exact-resolution test.'
      },
      'claim_policy' => { 'quality_claims_allowed' => false, 'runtime_comparable' => false },
      'admission_backlog' => [{
        'candidate_id' => 'synthetic-conflict',
        'status' => 'blocked',
        'reason' => 'No conflict oracle in the synthetic history.',
        'score_eligible' => false
      }],
      'cases' => [{
        'case_id' => 'synthetic-clean',
        'merge_commit' => merge,
        'base_commit' => base,
        'parent_commits' => [base, theirs],
        'path' => 'sample.rb',
        'blob_oids' => {
          'base' => blob(base),
          'ours' => blob(base),
          'theirs' => blob(theirs),
          'human' => blob(merge)
        },
        'selector' => {
          'provider_id' => 'ruby.ruby.prism',
          'family' => 'ruby',
          'dialect' => 'ruby',
          'backend' => 'prism',
          'profile' => 'source_preserving',
          'require' => 'prism/merge'
        },
        'capability_tags' => %w[merge3 ruby prism clean_history],
        'stratum' => {
          'provider' => 'ruby.ruby.prism',
          'dialect' => 'ruby',
          'conflict_type' => 'clean_history_preservation'
        },
        'oracle' => {
          'classification' => 'exact_automatic_resolution',
          'human_resolution_rationale' => 'Feature side is preserved exactly.',
          'ambiguity_status' => 'reviewed_unambiguous',
          'reclassification_status' => 'not_reclassified',
          'false_auto_merge_review' => 'pending',
          'score_eligible' => false
        }
      }]
    }
  end

  before do
    FileUtils.rm_rf(workspace)
    FileUtils.mkdir_p(workspace)
    git('init', '-q', '-b', 'main')
    workspace.join('sample.rb').binwrite("VALUE = 1\n")
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  it 'validates every canonical real-history manifest and its admission state' do
    directory = Pathname(__dir__).join(
      '..', '..', '..', '..', 'fixtures', 'diagnostics',
      'slice-1021-reviewed-git-history-corpus'
    ).expand_path
    paths = directory.glob('manifest*.json').sort
    corpora = paths.map { |path| described_class.load(path) }

    expect(paths.map(&:basename).map(&:to_s)).to eq(
      %w[
        manifest.alef.json
        manifest.cargo-toml.json
        manifest.git-bash.json
        manifest.json
        manifest.kubernetes.json
        manifest.rbs.json
        manifest.typescript.json
      ]
    )
    expect(corpora).to all(satisfy(&:validate!))
    expect(corpora.sum { |corpus| corpus.manifest.fetch('cases').length }).to eq(13)
    expect(corpora.sum do |corpus|
      corpus.manifest.fetch('cases').count { |item| item.dig('oracle', 'score_eligible') }
    end).to eq(10)
    expect(corpora).to all(satisfy do |corpus|
      corpus.manifest.dig('claim_policy', 'quality_claims_allowed') == false
    end)
  end

  it 'runs synthetic history through baseline and the installed driver deterministically' do
    corpus = described_class.new(synthetic_manifest)
    driver = Gem.bin_path('ast-merge-git', 'ast-merge-git')
    runner = Ast::Merge::Git::CorpusRunner.new(
      corpus: corpus,
      repository: workspace,
      driver_path: driver,
      tmp_root: Pathname(__dir__).join('..', 'tmp', 'corpus').expand_path
    )

    result = runner.run.first

    expect(result[:baseline]).to include(exit_classification: 'clean', exact_human_result: true)
    expect(result[:candidate]).to include(exit_classification: 'clean', exact_human_result: true, parse_valid: true)
    expect(result.dig(:candidate, :outcome)).to eq('correct_clean')
    expect(result.dig(:candidate, :provider_check)).to include(
      provider_id: 'ruby.ruby.prism', method: 'exact_bytes', equivalent: true
    )
    expect(result[:deterministic_rerun]).to be(true)
    expect(result.dig(:claim_eligibility, :score_eligible)).to be(false)
    expect(result.dig(:candidate, :runtime_comparable)).to be(false)
  end

  it 'rejects octopus metadata and premature score eligibility' do
    manifest = synthetic_manifest
    octopus = Marshal.load(Marshal.dump(manifest))
    octopus['cases'][0]['parent_commits'] << octopus['cases'][0]['base_commit']
    expect { described_class.new(octopus).validate! }.to raise_error(described_class::Error, /exactly two parents/)

    manifest['cases'][0]['oracle']['score_eligible'] = true
    expect do
      described_class.new(manifest).validate!
    end.to raise_error(described_class::Error, /cannot be score eligible/)
  end

  it 'rejects case IDs that could escape the repo-local workspace' do
    manifest = synthetic_manifest
    manifest['cases'][0]['case_id'] = '../../outside'

    expect do
      described_class.new(manifest).validate!
    end.to raise_error(described_class::Error, /case_id must be lowercase kebab-case/)
  end

  it 'classifies git merge-file conflict counts as conflicts rather than process errors' do
    corpus = described_class.new(synthetic_manifest)
    runner = Ast::Merge::Git::CorpusRunner.new(
      corpus: corpus,
      repository: workspace,
      driver_path: Gem.bin_path('ast-merge-git', 'ast-merge-git'),
      tmp_root: Pathname(__dir__).join('..', 'tmp', 'corpus').expand_path
    )

    expect(runner.send(:exit_classification, 5, :git_merge_file)).to eq('conflict')
    expect(runner.send(:exit_classification, 7, :git_merge_file)).to eq('conflict')
    expect(runner.send(:exit_classification, 255, :git_merge_file)).to eq('error')
    expect(runner.send(:exit_classification, 2, :structured_merge)).to eq('error')
  end

  it 'rejects dirty source history instead of mutating it' do
    corpus = described_class.new(synthetic_manifest)
    workspace.join('untracked.rb').binwrite("DIRTY = true\n")
    runner = Ast::Merge::Git::CorpusRunner.new(
      corpus: corpus,
      repository: workspace,
      driver_path: Gem.bin_path('ast-merge-git', 'ast-merge-git'),
      tmp_root: Pathname(__dir__).join('..', 'tmp', 'corpus').expand_path
    )

    expect { runner.run }.to raise_error(described_class::Error, /source repository is dirty/)
  end

  it 'classifies all seven Slice 1022 outcomes without scalar compensation' do
    runner = Ast::Merge::Git::CorpusRunner.allocate
    clean = { 'oracle' => { 'classification' => 'structurally_equivalent_resolution' } }
    conflict = { 'oracle' => { 'classification' => 'conflict_expected' } }
    excluded = { 'oracle' => { 'classification' => 'excluded' } }
    unsupported = Marshal.load(Marshal.dump(clean))
    unsupported['oracle']['provider_coverage'] = { 'status' => 'unsupported' }

    expect(runner.send(:classify, clean, 'clean', true, adapter: :structured_merge)).to eq('correct_clean')
    expect(runner.send(:classify, clean, 'conflict', false, adapter: :git_merge_file)).to eq('false_conflict')
    expect(runner.send(:classify, conflict, 'conflict', false, adapter: :structured_merge)).to eq('true_conflict')
    expect(runner.send(:classify, conflict, 'clean', true, adapter: :structured_merge)).to eq('false_auto_merge')
    expect(runner.send(:classify, clean, 'clean', false, adapter: :structured_merge)).to eq('false_auto_merge')
    expect(runner.send(:classify, clean, 'error', false, adapter: :structured_merge)).to eq('error')
    expect(runner.send(:classify, unsupported, 'error', false, adapter: :structured_merge)).to eq('unsupported')
    expect(runner.send(:classify, excluded, 'clean', true, adapter: :structured_merge)).to eq('excluded_ambiguous')
    expect(Ast::Merge::Git::CorpusRunner::OUTCOMES).to eq(
      %w[correct_clean false_conflict true_conflict false_auto_merge error unsupported excluded_ambiguous]
    )
  end

  it 'uses selected-provider diff2 rather than parse validity for structural equivalence' do
    runner = Ast::Merge::Git::CorpusRunner.allocate
    item = synthetic_manifest.fetch('cases').first
    expected = "class Example\n  def value = 1\nend\n"
    output = "\nclass Example\n  def value = 1\nend\n"

    evidence = runner.send(:provider_equivalence, output, expected, item, false)

    expect(evidence).to include(
      equivalent: true,
      available: true,
      valid: true,
      provider_id: 'ruby.ruby.prism',
      method: 'selected_provider.diff2(expected_human, candidate_output).changes.empty?'
    )
  end

  it 'rejects clone destinations that lexically escape the configured tmp root' do
    tmp_root = Pathname(__dir__).join('..', 'tmp', "corpus-acquire-spec-#{Process.pid}").expand_path
    escaped = tmp_root.join('..', 'escaped', 'repository')

    expect do
      Ast::Merge::Git::CorpusAcquirer.send(:validate_destination!, escaped, tmp_root)
    end.to raise_error(described_class::Error, /destination must be inside/)
  ensure
    FileUtils.rm_rf(tmp_root)
  end

  it 'does not expose human oracle bytes to the candidate process' do
    manifest = synthetic_manifest
    corpus = described_class.new(manifest)
    root = Pathname(__dir__).join('..', 'tmp', "corpus-oracle-spec-#{Process.pid}").expand_path
    log = root.join('candidate.json')
    driver = root.join('recording-driver')
    FileUtils.mkdir_p(root)
    driver.binwrite(<<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      File.binwrite(#{log.to_s.inspect}, JSON.generate(
        'argv' => ARGV,
        'forbidden_env' => ENV.select { |key, _| key.match?(/ORACLE|HUMAN|EXPECTED/i) }
      ))
      File.binwrite(ARGV.fetch(1), File.binread(ARGV.fetch(0)))
    RUBY
    FileUtils.chmod(0o755, driver)
    previous = ENV['CORPUS_HUMAN_ORACLE_BYTES']
    ENV['CORPUS_HUMAN_ORACLE_BYTES'] = git('show', "#{manifest['cases'][0]['merge_commit']}:sample.rb")
    runner = Ast::Merge::Git::CorpusRunner.new(
      corpus: corpus, repository: workspace, driver_path: driver, tmp_root: root
    )

    runner.run
    invocation = JSON.parse(log.binread)
    expect(invocation.fetch('argv').length).to eq(5)
    expect(invocation.fetch('argv').first(3)).to eq(%w[base ours theirs])
    expect(invocation.fetch('forbidden_env')).to be_empty
  ensure
    ENV['CORPUS_HUMAN_ORACLE_BYTES'] = previous
    FileUtils.rm_rf(root) if root
  end

  it 'terminates and reaps a timed-out child process' do
    root = Pathname(__dir__).join('..', 'tmp', "corpus-timeout-spec-#{Process.pid}").expand_path
    pid_path = root.join('child.pid')
    sleeper = root.join('sleeper')
    FileUtils.mkdir_p(root)
    sleeper.binwrite(<<~SH)
      #!/bin/sh
      printf '%s' "$$" > #{pid_path}
      exec sleep 30
    SH
    FileUtils.chmod(0o755, sleeper)
    runner = Ast::Merge::Git::CorpusRunner.allocate
    runner.instance_variable_set(:@timeout, 1)

    capture = runner.send(:timed_capture, {}, sleeper.to_s, chdir: root)
    pid = Integer(pid_path.read)

    expect(capture).to include(status: 2)
    expect(capture[:stderr]).to include('timeout after 1s')
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  ensure
    FileUtils.rm_rf(root) if root
  end
end
# rubocop:enable Metrics/BlockLength, Metrics/MethodLength
