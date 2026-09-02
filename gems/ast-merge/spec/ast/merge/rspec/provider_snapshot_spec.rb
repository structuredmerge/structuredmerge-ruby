# frozen_string_literal: true

require 'ast/merge/rspec/provider_snapshot'

module ProviderSnapshotSpecSupport
  Point = Data.define(:row, :column)
  Node = Data.define(:type, :native_type, :start_byte, :end_byte, :children, :named, :missing, :has_error) do
    def start_point = Point.new(0, start_byte)
    def end_point = Point.new(0, end_byte)
    def named? = named
    def missing? = missing
    # rubocop:disable Naming/PredicatePrefix -- mirrors the TreeHaver node contract
    def has_error? = has_error
    # rubocop:enable Naming/PredicatePrefix
  end
  Comment = Data.define(:type, :start_byte, :end_byte, :style, :attachment_hint) do
    def start_point = Point.new(0, start_byte)
    def end_point = Point.new(0, end_byte)
  end
  Tree = Data.define(:root_node, :comments, :errors, :warnings)
end

# rubocop:disable Metrics/BlockLength -- one cohesive contract-harness example group
RSpec.describe Ast::Merge::RSpec::ProviderSnapshot do
  let(:source) { "# retained\nkey = true\n" }
  let(:comment) { ProviderSnapshotSpecSupport::Comment.new('line_comment', 0, 10, :line, :leading) }
  let(:child) { ProviderSnapshotSpecSupport::Node.new('pair', 'native_pair', 11, 21, [], true, false, false) }
  let(:root) do
    ProviderSnapshotSpecSupport::Node.new(
      'document',
      'native_document',
      0,
      source.bytesize,
      [child],
      true,
      false,
      false
    )
  end
  let(:tree) { ProviderSnapshotSpecSupport::Tree.new(root, [comment], [], []) }
  let(:parser) { instance_double('TreeHaver::Parser', parse: tree) }
  let(:provider) do
    Class.new do
      def provider_id = 'ruby.spec'
      def family = 'spec'

      def analyze(request)
        Ast::Merge::ProviderResult.build(
          operation: :analyze,
          success: true,
          envelope: {
            provider: { provider_id: provider_id, family: family, backend: request.fetch(:backend) },
            profile: { profile_id: request.fetch(:profile_id) },
            verification: { source_parsed: true }
          },
          analysis: { owners: [{ id: 'key' }] }
        )
      end

      def merge2(request)
        Ast::Merge::ProviderResult.build(
          operation: :merge2,
          success: true,
          envelope: {
            provider: { provider_id: provider_id, family: family },
            profile: { profile_id: :source_preserving },
            verification: { output_reparsed: true }
          },
          output: "#{request.fetch(:current_source)}#{request.fetch(:incoming_source)}"
        )
      end
    end.new
  end
  let(:backend_identity) do
    {
      id: 'spec',
      family: 'native',
      host_runtime: 'ruby',
      package: 'spec-parser',
      parser: 'SpecParser',
      capabilities: %w[comments normalized_tree exact_source_spans]
    }
  end
  let(:extension_builder) do
    lambda do |tree:, **|
      {
        schema: 'structuredmerge.extension/spec/v1',
        namespace: 'spec',
        capabilities: %w[native-kinds comments native-kinds],
        payload: { comment_count: tree.comments.length }
      }
    end
  end
  let(:snapshot) do
    described_class.new(
      snapshot_id: 'snapshot.spec',
      source_id: 'fixture:spec:retained-key',
      provider: provider,
      source: source,
      language: :spec,
      dialect: :spec,
      backend_id: :spec,
      backend_identity: backend_identity,
      parser_contract: :spec,
      extension_builder: extension_builder
    )
  end

  before do
    allow(TreeHaver).to receive(:with_backend).with('spec').and_yield
    allow(TreeHaver).to receive(:parser_for).with(:spec, contract: :spec).and_return(parser)
    allow(TreeHaver).to receive(:registered_languages).with(:spec).and_return(
      spec: { gem_name: 'spec-parser', contract: :spec }
    )
  end

  it 'captures deterministic normalized parse and analysis projections through TreeHaver' do
    capture = snapshot.capture

    expect(capture.dig(:parse_request, :schema)).to eq('structuredmerge.parse-request/v1')
    expect(capture.dig(:parse_result, :schema)).to eq('structuredmerge.parse-result/v1')
    expect(capture.dig(:analysis_result, :schema)).to eq('structuredmerge.analysis-result/v1')
    expect(capture.dig(:parse_result, :selection, :selected_backend)).to eq('spec')
    expect(capture.dig(:parse_request, :source, :source_id)).to eq('fixture:spec:retained-key')
    expect(capture.dig(:parse_result, :request_id)).to end_with(Digest::SHA256.hexdigest(source)[0, 12])
    expect(capture.dig(:parse_result, :nodes).map { |node| node[:native_type] }).to eq(
      %w[native_document native_pair line_comment]
    )
    expect(capture.dig(:parse_result, :comments, 0)).to include(
      node_id: 'node:2', native_kind: 'line_comment', attachment_hint: 'leading'
    )
    expect(capture.dig(:analysis_result, :owners)).to eq([{ id: 'key' }])
    expect(capture.dig(:parse_result, :extensions, 0, 'capabilities')).to eq(%w[comments native-kinds])
    expect(capture.dig(:parse_result, :extensions, 0, 'opaque_forwarding_replay_sha256')).to match(/\A[0-9a-f]{64}\z/)
    expect(described_class.canonical_json(snapshot.capture)).to eq(described_class.canonical_json(capture))
  end

  it 'replays a serialized request without changing provider output' do
    evidence = snapshot.differential_replay(
      operation: :merge2,
      request: {
        provider_id: provider.provider_id,
        family: provider.family,
        incoming_source: "incoming\n",
        current_source: "current\n",
        backend: :spec,
        profile_id: :source_preserving
      }
    )

    expect(evidence).to include(operation: 'merge2', equivalent: true, output_bytes_equal: true)
    expect(evidence[:original_sha256]).to eq(evidence[:replay_sha256])
    expect(evidence[:transported_request]).to eq(described_class.round_trip(evidence[:original_request]))
    expect(described_class.canonical_json(evidence[:transported_result])).to eq(
      described_class.canonical_json(evidence[:original_result])
    )
  end

  it 'rejects extensions without a versioned StructuredMerge namespace' do
    invalid = described_class.new(
      snapshot_id: 'snapshot.invalid',
      provider: provider,
      source: source,
      language: :spec,
      dialect: :spec,
      backend_id: :spec,
      backend_identity: backend_identity,
      parser_contract: :spec,
      extension_builder: ->(**) { { schema: 'invalid', namespace: 'spec', capabilities: [] } }
    )

    expect { invalid.capture }.to raise_error(described_class::Error, /Invalid extension schema/)
  end
end
# rubocop:enable Metrics/BlockLength
