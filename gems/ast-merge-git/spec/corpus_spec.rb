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
          'provider_id' => 'ruby.ruby',
          'family' => 'ruby',
          'dialect' => 'ruby',
          'backend' => 'prism',
          'profile' => 'source_preserving',
          'require' => 'ruby/merge'
        },
        'capability_tags' => %w[merge3 ruby prism clean_history],
        'stratum' => {
          'provider' => 'ruby.ruby',
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

  it 'validates the canonical real-history manifest' do
    path = Pathname(__dir__).join(
      '..', '..', '..', '..', 'fixtures', 'diagnostics',
      'slice-1021-reviewed-git-history-corpus', 'manifest.json'
    ).expand_path

    corpus = described_class.load(path)
    expect(corpus.validate!).to be(true)
    expect(corpus.manifest.fetch('cases').length).to eq(3)
    expect(corpus.manifest.dig('claim_policy', 'quality_claims_allowed')).to be(false)
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
end
# rubocop:enable Metrics/BlockLength, Metrics/MethodLength
