# frozen_string_literal: true

RSpec.describe Toml::Merge do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join('conformance', 'slice-24-manifest', 'family-feature-profiles.json'))
  end

  def family_profile_fixture
    read_json(fixtures_root.join('diagnostics', 'slice-90-toml-family-feature-profile', 'toml-feature-profile.json'))
  end

  def toml_fixture(role)
    path = {
      'parse_valid' => %w[toml slice-91-parse valid-document.json],
      'structure' => %w[toml slice-92-structure table-and-array.json],
      'matching' => %w[toml slice-93-matching path-equality.json],
      'merge' => %w[toml slice-94-merge table-merge.json]
    }.fetch(role)
    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it 'conforms to the TOML parse, structure, matching, and merge fixtures with the tree-sitter substrate' do
    parse_fixture = toml_fixture('parse_valid')
    parse_result = described_class.parse_toml(parse_fixture[:source], parse_fixture[:dialect])
    expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
    expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

    structure_fixture = toml_fixture('structure')
    structure_result = described_class.parse_toml(structure_fixture[:source], structure_fixture[:dialect])
    expect(json_ready(structure_result.dig(:analysis,
                                           :owners))).to eq(json_ready(structure_fixture.dig(:expected, :owners)))

    matching_fixture = toml_fixture('matching')
    template = described_class.parse_toml(matching_fixture[:template], 'toml')
    destination = described_class.parse_toml(matching_fixture[:destination], 'toml')
    matching_result = described_class.match_toml_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching_result[:matched].map do |match|
      [match[:template_path], match[:destination_path]]
    end)).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = toml_fixture('merge')
    merge_result = described_class.merge_toml(merge_fixture[:template], merge_fixture[:destination], 'toml')
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to include('title = "Structured Merge"')
    expect(merge_result[:output]).to include('name = "structuredmerge"')
    expect(merge_result[:output]).to include('tags = ["destination"]')
    expect(merge_result[:output]).to include('version = "0.2.0"')
    expect(merge_result[:output]).to include('authors = ["pb"]')
    expect(merge_result[:output]).to include('enabled = false')
    expect(merge_result[:output]).to include('release = true')
    expect(merge_result[:output]).not_to include('tags = ["template"]')
    expect(merge_result[:output]).not_to include('version = "0.1.0"')
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))
  end

  it 'keeps the shared family feature fixture stable while exposing the substrate backend feature profile' do
    expect(json_ready(described_class.toml_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
    expect(json_ready(described_class.available_toml_backends.map(&:to_h))).to eq(
      json_ready([
                   { id: 'kreuzberg-language-pack', family: 'tree-sitter' }
                 ])
    )
    expect(json_ready(TreeHaver::BackendRegistry.fetch('kreuzberg-language-pack')&.to_h)).to eq(
      json_ready({ id: 'kreuzberg-language-pack', family: 'tree-sitter' })
    )
  end

  it 'conforms to the slice-135 TOML backend feature profile fixtures' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-135-toml-family-backend-feature-profiles',
        'ruby-toml-backend-feature-profiles.json'
      )
    )

    expect(json_ready(described_class.toml_backend_feature_profile(backend: 'kreuzberg-language-pack'))).to include(
      json_ready(fixture[:tree_sitter])
    )
  end

  it 'conforms to the slice-136 TOML plan-context fixtures' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-136-toml-family-plan-contexts',
        'ruby-toml-plan-contexts.json'
      )
    )

    expect(json_ready(described_class.toml_plan_context(backend: 'kreuzberg-language-pack'))).to eq(
      json_ready(fixture[:tree_sitter])
    )
  end

  it 'conforms to the slice-137 TOML family manifest fixture' do
    manifest = read_json(fixtures_root.join('conformance', 'slice-137-toml-family-manifest',
                                            'toml-family-manifest.json'))

    expect(Ast::Merge.conformance_family_feature_profile_path(manifest, 'toml')).to eq(
      %w[diagnostics slice-90-toml-family-feature-profile toml-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, 'toml', 'analysis')).to eq(
      %w[toml slice-92-structure table-and-array.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, 'toml', 'matching')).to eq(
      %w[toml slice-93-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, 'toml', 'merge')).to eq(
      %w[toml slice-94-merge table-merge.json]
    )
  end

  it 'resolves TOML paths through the canonical manifest' do
    expect(Ast::Merge.conformance_family_feature_profile_path(manifest, 'toml')).to eq(
      %w[diagnostics slice-90-toml-family-feature-profile toml-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, 'toml', 'analysis')).to eq(
      %w[toml slice-92-structure table-and-array.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, 'toml', 'matching')).to eq(
      %w[toml slice-93-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, 'toml', 'merge')).to eq(
      %w[toml slice-94-merge table-merge.json]
    )
  end

  it 'rejects unsupported provider backend overrides' do
    result = described_class.parse_toml("title = \"x\"\n", 'toml', backend: 'bogus')
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to eq(
      [{ severity: 'error', category: 'unsupported_feature', message: 'Unsupported TOML backend bogus.' }]
    )
  end

  it 'preserves destination TOML comments and blank lines while adding template-only keys' do
    fixture = read_json(
      fixtures_root.join(
        'toml',
        'slice-721-formatting-preservation',
        'dotted-inline-comments-arrays.json'
      )
    )

    result = described_class.merge_toml(fixture[:template], fixture[:destination], fixture[:dialect])

    expect(result[:ok]).to eq(fixture.dig(:expected, :ok))
    expect(result[:output]).to include('# project configuration')
    expect(result[:output]).to include("\n\n# local operator notes\n")
    expect(result[:output]).to include('local = true')
    expect(result[:output]).to include('_.file = { path = ".env.local", redact = true }')
    expect(result[:output]).to include('_.path = ["exe", "bin"]')
    expect(result[:output]).to include('[[profiles.semantic-diff.attributes]]')
    expect(result[:output]).to include('diff = "smorg-rb"')
    expect(result[:output]).to eq(fixture.dig(:expected, :output))
  end

  it 'records emitter source provenance line metadata for raw source rendering' do
    emitter = described_class::Emitter.new
    emitter.emit_raw_lines(
      ['[env]', 'project = "kettle-jem"'],
      metadata: { source: :destination, original_line_start: 12 }
    )

    expect(emitter.lines).to eq(['[env]', 'project = "kettle-jem"'])
    expect(emitter.line_metadata).to eq(
      [
        { source: :destination, original_line: 12 },
        { source: :destination, original_line: 13 }
      ]
    )
  end

  it 'parses mise-style dotted env keys and inline tables' do
    source = <<~TOML
      [env]
      KJ_PROJECT_EMOJI = "🔮"
      _.file = { path = ".env.local", redact = true }
      _.path = ["exe", "bin"]
      _.source = ".config/mise/env.sh"
    TOML

    result = described_class.parse_toml(source, 'toml')

    expect(result.fetch(:ok)).to be(true)
    expect(result.dig(:analysis, :normalized_source)).to include('file = { path = ".env.local", redact = true }')
    expect(result.dig(:analysis, :owners)).to include(
      include(path: '/env/_/file', owner_kind: 'key_value', match_key: 'file')
    )
  end

  it 'projects arrays of tables through the TOML substrate' do
    source = <<~TOML
      version = 1

      [profiles.semantic-diff]
      description = "Semantic diff"

      [[profiles.semantic-diff.attributes]]
      pattern = "*.rb"
      diff = "smorg-rb"

      [[profiles.semantic-diff.git_config]]
      scope = "global"
      key = "diff.smorg-rb.command"
      value = "smorg-rb diff-driver"
    TOML

    result = described_class.parse_toml(source, 'toml')

    expect(result.fetch(:ok)).to be(true)
    expect(result.dig(:analysis, :normalized_source)).to include('[[profiles.semantic-diff.attributes]]')
    expect(result.dig(:analysis, :normalized_source)).to include('[[profiles.semantic-diff.git_config]]')
    expect(result.dig(:analysis, :owners)).to include(
      include(path: '/profiles/semantic-diff/attributes', owner_kind: 'table_array', match_key: 'attributes'),
      include(path: '/profiles/semantic-diff/git_config', owner_kind: 'table_array', match_key: 'git_config')
    )
  end

  it 'merges comment-free TOML arrays of tables with destination preference' do
    template = <<~TOML
      version = 1

      [profiles.semantic-diff]
      description = "Template driver"

      [[profiles.semantic-diff.attributes]]
      pattern = "*.rb"
      diff = "smorg-ruby"

      [profiles.textconv-normalized]
      description = "Template-only profile"

      [[profiles.textconv-normalized.attributes]]
      pattern = "*.json"
      diff = "smorg-json-textconv"
    TOML
    destination = <<~TOML
      version = 1

      [profiles.semantic-diff]
      description = "Destination driver"

      [[profiles.semantic-diff.attributes]]
      pattern = "*.rb"
      diff = "smorg-rb"
    TOML

    result = described_class.merge_toml(template, destination, 'toml')

    expect(result.fetch(:ok)).to be(true)
    expect(result.fetch(:output)).to include('diff = "smorg-rb"')
    expect(result.fetch(:output)).to include('description = "Destination driver"')
    expect(result.fetch(:output)).to include('[[profiles.textconv-normalized.attributes]]')
    expect(result.fetch(:output)).not_to include('smorg-ruby')
  end

  it 'exposes non-overlapping effective table ranges and source fragments through the TOML substrate' do
    source = <<~TOML
      title = "example"

      [env]
      project = "kettle-jem"
      path = ["exe", "bin"]

      [tools]
      ruby = "4.0.2"
    TOML

    analysis = described_class::FileAnalysis.new(source)
    expect(analysis).to be_valid

    table_ranges = analysis.tables.to_h do |table|
      [table.table_name, table.start_line..table.effective_end_line]
    end
    table_fragments = analysis.tables.to_h do |table|
      [table.table_name, table.content]
    end

    expect(table_ranges).to eq(
      'env' => 3..5,
      'tools' => 7..8
    )
    expect(table_fragments).to eq(
      'env' => "[env]\nproject = \"kettle-jem\"\npath = [\"exe\", \"bin\"]",
      'tools' => "[tools]\nruby = \"4.0.2\""
    )
  end

  it 'conforms to the slice-139 family named-suite plan fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-139-toml-family-named-suite-plans',
        'ruby-toml-named-suite-plans.json'
      )
    )

    entries = Ast::Merge.plan_named_conformance_suites(fixture[:manifest], fixture[:contexts])
    expect(json_ready(entries)).to eq(json_ready(fixture[:expected_entries]))
  end

  it 'conforms to the slice-140 family manifest report fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-140-toml-family-manifest-report',
        'ruby-toml-manifest-report.json'
      )
    )

    report = Ast::Merge.report_conformance_manifest(fixture[:manifest], fixture[:options]) do |run|
      key = "#{run[:ref][:family]}:#{run[:ref][:role]}:#{run[:ref][:case]}"
      fixture[:executions][key.to_sym] || fixture[:executions][key] || { outcome: 'failed',
                                                                         messages: ['missing execution'] }
    end

    expect(json_ready(report)).to eq(json_ready(fixture[:expected_report]))
  end
end
