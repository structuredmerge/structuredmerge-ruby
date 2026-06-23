# frozen_string_literal: true

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
