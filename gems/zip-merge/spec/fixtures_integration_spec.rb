# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength -- complete ZIP planning and rendering fixture contract
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
# rubocop:enable Metrics/BlockLength

# rubocop:disable Metrics/BlockLength -- complete portable provider operation matrix
RSpec.describe 'Zip::Merge provider conformance' do
  subject(:provider) { Zip::Merge.merge_provider }

  let(:base_source) { Zip::Merge.new_stored_zip('docs/readme.md' => "# Base\n") }
  let(:theirs_source) { Zip::Merge.new_stored_zip('docs/readme.md' => "# Theirs\n") }
  let(:provider_conformance) do
    {
      dialect: :zip,
      backend: Zip::Merge::BACKEND_REFERENCE.id.to_sym,
      profile_id: :opaque_archive,
      role: :workflow,
      parse_failures: true,
      requests: {
        analyze: { source: base_source },
        diff2: { before_source: base_source, after_source: theirs_source },
        merge2: { current_source: base_source, incoming_source: theirs_source },
        merge3: {
          base_source: base_source,
          ours_source: base_source,
          theirs_source: theirs_source
        }
      },
      invalid_merge3: {
        base_source: base_source,
        ours_source: base_source,
        theirs_source: 'not a zip',
        source_role: :theirs
      },
      base_adversarial_merge3: {
        request: {
          base_source: base_source,
          ours_source: base_source,
          theirs_source: theirs_source
        },
        expected_value: theirs_source
      },
      parse_output: proc(&:b)
    }
  end

  it_behaves_like 'Ast::Merge::ProviderConformance'

  it 'retains ours as a valid archive when both archives changed' do
    ours = Zip::Merge.new_stored_zip('docs/readme.md' => "# Ours\n")
    result = provider.merge3(
      base_source: base_source,
      ours_source: ours,
      theirs_source: theirs_source,
      dialect: :zip,
      profile_id: :opaque_archive
    )

    expect(result).to include(ok: false, conflicted_output: ours)
    expect(Zip::Merge.parse_zip_inventory(result.fetch(:conflicted_output)).archive.entry_count).to eq(1)
    expect(result.fetch(:conflicts)).to contain_exactly(
      hash_including(category: :opaque_edit_edit)
    )
  end
end
# rubocop:enable Metrics/BlockLength

RSpec.describe 'Zip::Merge binary substrate integration' do
  it 'uses the shared binary substrate for merge reports and diagnostics' do
    report = Zip::Merge.empty_report
    diagnostic = Zip::Merge.render_error('unsafe_zip_member', '/entries/by_path/secret',
                                         'unsafe member').diagnostic

    expect(report).to be_a(TreeHaver::BinaryMergeReport)
    expect(report.format).to eq('zip')
    expect(report.schema).to eq('zip.ksy')
    expect(diagnostic).to be_a(TreeHaver::BinaryDiagnostic)
    expect(diagnostic.category).to eq('unsafe_zip_member')
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
