# frozen_string_literal: true

RSpec.describe Zip::Merge do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    JSON.parse(path.read, symbolize_names: true)
  end

  it 'parses, plans, and raw-preserves stored ZIP members' do
    current_source = described_class.new_stored_zip(
      'META-INF/MANIFEST.MF' => "Manifest-Version: 1.0\n",
      'docs/readme.md' => "# Old\n"
    )
    ancestor = described_class.parse_zip_inventory(current_source)
    incoming = described_class.parse_zip_inventory(described_class.new_stored_zip(
                                                     'META-INF/MANIFEST.MF' => "Manifest-Version: 1.0\n",
                                                     'docs/readme.md' => "# New\n"
                                                   ))
    plan = described_class.plan_zip_merge(ancestor, ancestor, incoming)

    output, inventory, report = described_class.render_with_raw_preservation(
      source: current_source,
      plan: plan,
      member_bytes: { 'docs/readme.md' => "# New\n" }
    )

    expect(inventory.archive.entry_count).to eq(2)
    expect(plan.merge_report.nested_dispatches.first.family).to eq('markdown')
    expect(report.preserved_ranges.length).to eq(1)
    expect(output).to start_with(current_source.byteslice(0...report.preserved_ranges.first.length))
  end

  it 'conforms to the slice-736 raw-preservation edge-case fixture categories' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-736-zip-raw-preservation-edge-cases',
                                           'zip-raw-preservation-edge-cases.json'))
    categories = fixture.fetch(:rejections).to_h { |item| [item.fetch(:label), item.fetch(:category)] }

    expect(fixture.dig(:success, :expected_nested_family)).to eq('markdown')
    expect(categories.fetch('unsupported-compression')).to eq('unsupported_compression')
    expect(categories.fetch('archive-comment')).to eq('archive_comment')
    expect(categories.fetch('encrypted-member')).to eq('encrypted_member')
  end
end

RSpec.describe 'Zip::Merge TreeHaver backend registration' do
  it 'registers the ZIP Kaitai backend through TreeHaver parser lookup' do
    source = Zip::Merge.new_stored_zip('docs/readme.md' => "# Readme\n")
    parser = TreeHaver.parser_for(:zip, backend_type: :kaitai)
    inventory = parser.parse(source)

    expect(inventory).to be_a(TreeHaver::ZipFamilyReport)
    expect(inventory.archive.schema).to eq('zip.ksy')
    expect(inventory.entries.map(&:normalized_path)).to eq(['docs/readme.md'])
  end
end
