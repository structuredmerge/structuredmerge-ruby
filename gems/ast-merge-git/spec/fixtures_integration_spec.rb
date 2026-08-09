# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'json'

# Format-neutral provider double used to exercise registry dispatch.
class NeutralGitProvider
  attr_reader :requests, :merge2_calls

  def initialize(&merge3_result)
    @merge3_result = merge3_result
    @requests = []
    @merge2_calls = 0
  end

  def provider_id = 'test.neutral'
  def family = 'neutral'

  def capabilities
    {
      operations: Ast::Merge::ProviderContract::OPERATIONS,
      dialects: %i[plain],
      backends: %i[test],
      profiles: %i[source_preserving],
      role: :workflow,
      source_preservation: %i[exact_source]
    }
  end

  def analyze(_request) = operation_result(:analyze)
  def diff2(_request) = operation_result(:diff2)

  def merge2(_request)
    @merge2_calls += 1
    operation_result(:merge2)
  end

  def merge3(request)
    @requests << request
    @merge3_result.call(request)
  end

  private

  def operation_result(operation)
    Ast::Merge::ProviderResult.build(
      operation: operation,
      success: true,
      envelope: { provider: { provider_id: provider_id } }
    )
  end
end

# rubocop:disable Metrics/BlockLength -- adapter outcomes share one provider test surface
RSpec.describe Ast::Merge::Git do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def adapter_fixture
    JSON.parse(
      fixtures_root
        .join('diagnostics', 'slice-1020-format-neutral-git-adapter', 'format-neutral-git-adapter.json')
        .read,
      symbolize_names: true
    )
  end

  # rubocop:disable Metrics/MethodLength -- complete provider envelope is intentional test evidence
  def provider_result(success:, output: nil, conflicted_output: nil, conflicts: [])
    Ast::Merge::ProviderResult.build(
      operation: :merge3,
      success: success,
      envelope: {
        provider: { provider_id: 'test.neutral' },
        conflicts: conflicts,
        changes: [{ path: '/owner', ours: :edited, theirs: :unchanged }],
        render_report: { strategy: :exact_source },
        verification: { base_participated: true }
      },
      **{ output: output, conflicted_output: conflicted_output }.compact
    )
  end
  # rubocop:enable Metrics/MethodLength

  def request
    {
      family: :neutral,
      dialect: :plain,
      backend: :test,
      profile_id: :source_preserving,
      base_source: "base\n",
      ours_source: "ours\n",
      theirs_source: "theirs\n"
    }
  end

  def register(provider)
    Ast::Merge.register_provider(provider, replace: true)
  end

  def workspace
    Pathname(__dir__).join('..', 'tmp', "git-adapter-#{Process.pid}").expand_path
  end

  before do
    FileUtils.mkdir_p(workspace)
  end

  after do
    FileUtils.rm_rf(workspace)
  end

  it 'dispatches merge3 without knowing the provider format' do
    provider = register(NeutralGitProvider.new { provider_result(success: true, output: "merged\n") })

    result = described_class.merge3(request)

    expect(result).to include(ok: true, merged_source: "merged\n", conflicted_source: nil)
    expect(result.fetch(:change_classifications)).to eq(result.fetch(:changes))
    expect(result.dig(:render_report, :strategy)).to eq(:exact_source)
    expect(provider.requests.first).to include(
      base_source: "base\n",
      ours_source: "ours\n",
      theirs_source: "theirs\n"
    )
  end

  it 'conforms to the portable format-neutral adapter fixture' do
    adapter_fixture.fetch(:cases).each do |test_case|
      outcome = test_case.fetch(:provider_outcome)
      register(NeutralGitProvider.new do
        provider_result(
          success: outcome.fetch(:ok),
          output: outcome[:output],
          conflicted_output: outcome[:conflicted_output],
          conflicts: outcome.fetch(:conflicts)
        )
      end)

      result = described_class.merge3(request)
      expected = test_case.fetch(:expected)
      expect(result[:ok]).to eq(expected[:ok]), test_case.fetch(:case_id)
      expect(result[:merged_source]).to eq(expected[:merged_source]), test_case.fetch(:case_id)
      expect(result[:conflicted_source]).to eq(expected[:conflicted_source]), test_case.fetch(:case_id)
      expect(described_class.git_exit_code(result)).to eq(expected[:exit_code]), test_case.fetch(:case_id)
      next unless expected[:diagnostic_category]

      expect(result.fetch(:diagnostics)).to include(
        hash_including(category: expected[:diagnostic_category].to_sym)
      )
    end
  end

  it 'never falls back from unsupported merge3 to merge2' do
    provider = register(NeutralGitProvider.new { provider_result(success: true, output: "unused\n") })

    result = described_class.merge3(request.merge(dialect: :unsupported))

    expect(result).to include(ok: false)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :unsupported_capability)
    )
    expect(provider.merge2_calls).to eq(0)
    expect(described_class.git_exit_code(result)).to eq(described_class::EXIT_ERROR)
  end

  it 'rejects successful provider results without String output' do
    register(NeutralGitProvider.new { provider_result(success: true) })

    result = described_class.merge3(request)

    expect(result).to include(ok: false, merged_source: nil)
    expect(result.fetch(:diagnostics)).to contain_exactly(
      hash_including(category: :invalid_provider_output)
    )
  end

  it 'writes successful provider output to ours and returns Git success' do
    register(NeutralGitProvider.new { provider_result(success: true, output: "merged\n") })
    base, ours, theirs = write_role_files

    result = described_class.merge_files(
      base_path: base,
      ours_path: ours,
      theirs_path: theirs,
      **request.except(:base_source, :ours_source, :theirs_source)
    )

    expect(ours.binread).to eq("merged\n")
    expect(result.fetch(:git)).to include(exit_code: 0, output_written: true, conflict_policy: :write)
  end

  it 'writes provider conflict output under the explicit write policy' do
    conflict = { conflict_id: 'neutral-owner', category: :edit_edit, path: '/owner' }
    register(NeutralGitProvider.new do
      provider_result(
        success: false,
        conflicted_output: "<<<<<<< ours\nours\n=======\ntheirs\n>>>>>>> theirs\n",
        conflicts: [conflict]
      )
    end)
    base, ours, theirs = write_role_files

    result = described_class.merge_files(
      base_path: base,
      ours_path: ours,
      theirs_path: theirs,
      **request.except(:base_source, :ours_source, :theirs_source)
    )

    expect(ours.binread).to start_with('<<<<<<< ours')
    expect(result.fetch(:git)).to include(exit_code: 1, output_written: true)
  end

  it 'leaves ours untouched under the explicit leave_ours conflict policy' do
    conflict = { conflict_id: 'neutral-owner', category: :edit_edit, path: '/owner' }
    register(NeutralGitProvider.new do
      provider_result(success: false, conflicted_output: "conflict\n", conflicts: [conflict])
    end)
    base, ours, theirs = write_role_files

    result = described_class.merge_files(
      base_path: base,
      ours_path: ours,
      theirs_path: theirs,
      conflict_policy: :leave_ours,
      **request.except(:base_source, :ours_source, :theirs_source)
    )

    expect(ours.binread).to eq("ours\n")
    expect(result.fetch(:git)).to include(exit_code: 1, output_written: false, conflict_policy: :leave_ours)
  end

  it 'fails explicitly when the write policy receives no conflict output' do
    conflict = { conflict_id: 'neutral-owner', category: :edit_edit, path: '/owner' }
    register(NeutralGitProvider.new do
      provider_result(success: false, conflicts: [conflict])
    end)
    base, ours, theirs = write_role_files

    result = described_class.merge_files(
      base_path: base,
      ours_path: ours,
      theirs_path: theirs,
      **request.except(:base_source, :ours_source, :theirs_source)
    )

    expect(ours.binread).to eq("ours\n")
    expect(result.fetch(:git)).to include(exit_code: 2, output_written: false)
    expect(result.fetch(:diagnostics)).to include(hash_including(category: :invalid_provider_output))
  end

  it 'maps Git positional roles, labels, and marker size into the provider request' do
    provider = register(NeutralGitProvider.new { provider_result(success: true, output: "merged\n") })
    base, ours, theirs = write_role_files
    stderr = StringIO.new

    exit_code = described_class.run(
      [base.to_s, ours.to_s, theirs.to_s, 'sample.neutral', '9', 'ancestor', 'current', 'incoming'],
      env: {
        'AST_MERGE_FAMILY' => 'neutral',
        'AST_MERGE_DIALECT' => 'plain',
        'AST_MERGE_BACKEND' => 'test',
        'AST_MERGE_PROFILE' => 'source_preserving'
      },
      stderr: stderr
    )

    expect(exit_code).to eq(0)
    expect(provider.requests.last).to include(
      path_name: 'sample.neutral',
      conflict_marker_size: '9',
      labels: { base: 'ancestor', ours: 'current', theirs: 'incoming' }
    )
    expect(stderr.string).to be_empty
  end

  it 'loads a configured provider package without a runtime family dependency' do
    base, ours, theirs = write_role_files(
      base: "{\"shared\":true}\n",
      ours: "{\"shared\":true,\"ours\":1}\n",
      theirs: "{\"shared\":true,\"theirs\":2}\n"
    )
    stderr = StringIO.new

    exit_code = described_class.run(
      [base.to_s, ours.to_s, theirs.to_s, 'package.json', '7'],
      env: {
        'AST_MERGE_REQUIRE' => 'json/merge',
        'AST_MERGE_FAMILY' => 'json',
        'AST_MERGE_DIALECT' => 'json'
      },
      stderr: stderr
    )

    expect(exit_code).to eq(0)
    expect(JSON.parse(ours.binread)).to eq('shared' => true, 'ours' => 1, 'theirs' => 2)
    expect(stderr.string).to be_empty
  end

  def write_role_files(base: "base\n", ours: "ours\n", theirs: "theirs\n")
    paths = %w[base ours theirs].map { |role| workspace.join(role) }
    paths.zip([base, ours, theirs]).each { |path, content| path.binwrite(content) }
    paths
  end
end
# rubocop:enable Metrics/BlockLength
