# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- complete shared binary fixture contract
RSpec.describe Binary::Merge do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    JSON.parse(path.read, symbolize_names: true)
  end

  it 'assembles a binary preservation report from the shared binary fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-723-binary-core-contract', 'binary-core.json'))
    ranges = fixture.dig(:merge_report, :preserved_ranges).map do |range|
      TreeHaver::ByteRange.new(**range)
    end

    report = described_class.preservation_report(
      format: fixture.dig(:merge_report, :format),
      schema: fixture.dig(:merge_report, :schema),
      matched_schema_paths: fixture.dig(:merge_report, :matched_schema_paths),
      preserved_ranges: ranges
    )
    diagnostic = described_class.unsafe_diagnostic(
      schema_path: '/chunks/2',
      byte_range: TreeHaver::ByteRange.new(start_byte: 78, end_byte: 96),
      message: 'critical image data mutation is not enabled'
    )

    expect(described_class.binary_feature_profile[:family]).to eq('binary')
    expect(report.preserved_ranges.first.length).to eq(25)
    expect(report.rewritten_nodes).to eq([])
    expect(diagnostic.category).to eq('unsafe_binary_mutation')
  end
end
# rubocop:enable Metrics/BlockLength

# rubocop:disable Metrics/BlockLength -- complete portable provider operation matrix
RSpec.describe 'Binary::Merge provider conformance' do
  subject(:provider) { Binary::Merge.merge_provider }

  let(:provider_conformance) do
    {
      dialect: :binary,
      backend: :raw_bytes,
      profile_id: :opaque_document,
      role: :workflow,
      parse_failures: false,
      requests: {
        analyze: { source: "\x00stable".b },
        diff2: { before_source: "\x00stable".b, after_source: "\x00changed".b },
        merge2: { current_source: "\x00ours".b, incoming_source: "\x00theirs".b },
        merge3: {
          base_source: "\x00base".b,
          ours_source: "\x00base".b,
          theirs_source: "\x00theirs".b
        }
      },
      base_adversarial_merge3: {
        request: {
          base_source: "\x00obsolete".b,
          ours_source: "\x00obsolete".b,
          theirs_source: ''.b
        },
        expected_value: ''.b
      },
      parse_output: proc(&:b)
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'

  it 'retains ours byte-for-byte without inserting conflict markers' do
    ours = "\x00ours\xFF".b
    result = provider.merge3(
      base_source: "\x00base".b,
      ours_source: ours,
      theirs_source: "\x00theirs".b,
      dialect: :binary,
      profile_id: :opaque_document
    )

    expect(result).to include(ok: false, operation: :merge3, conflicted_output: ours)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :opaque_edit_edit, path: '')
    )
    expect(result.dig(:verification, :ours_preserved_exactly)).to be(true)
  end

  it 'preserves current bytes explicitly when merge2 inputs differ' do
    result = provider.merge2(current_source: "\x00current".b, incoming_source: "\x00incoming".b)

    expect(result).to include(ok: true, output: "\x00current".b)
    expect(result.fetch(:fallbacks)).to contain_exactly(
      hash_including(category: :opaque_binary_preserve_current)
    )
  end
end
# rubocop:enable Metrics/BlockLength
