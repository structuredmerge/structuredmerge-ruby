# frozen_string_literal: true

RSpec.describe Json::Merge do
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
    path = Ast::Merge.conformance_family_feature_profile_path(manifest, 'json')
    read_json(fixtures_root.join(*path))
  end

  def json_fixture(role)
    path = Ast::Merge.conformance_fixture_path(manifest, 'json', role)
    raise "missing json fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def jsonc_fixture(role)
    direct_paths = {
      'parse_comments' => %w[jsonc slice-04-parse comments-accepted.json],
      'structure_jsonc' => %w[jsonc slice-07-structure commented-object.json]
    }
    path = direct_paths[role]
    path && read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it 'conforms to the jsonc comments-accepted fixture' do
    fixture = jsonc_fixture('parse_comments')
    result = described_class.parse_json(fixture[:source], fixture[:dialect])

    expect(result[:ok]).to eq(fixture.dig(:expected, :ok))
    expect(result.dig(:analysis, :allows_comments)).to eq(fixture.dig(:expected, :allows_comments))
    expect(json_ready(result[:diagnostics])).to eq(json_ready(fixture.dig(:expected, :diagnostics)))
  end

  it 'parses JSONC comments and trailing commas through the normalized JSON5 backend' do
    source = <<~JSONC
      // devcontainer configuration
      {
        "customizations": {
          "jetbrains": { "backend": "RubyMine" },
        },
      }
    JSONC

    result = described_class.parse_json(source, 'jsonc')

    expect(result[:ok]).to be(true)
    expect(result.dig(:analysis, :root_kind)).to eq('object')
    expect(described_class.json_value_for_source(source, dialect: 'jsonc')).to eq(
      'customizations' => { 'jetbrains' => { 'backend' => 'RubyMine' } }
    )
  end

  it 'rejects JSON5-only syntax while accepting the JSONC subset' do
    invalid_sources = {
      'unquoted object key' => '{name: "value"}',
      'single-quoted string' => "{'name': 'value'}",
      'hexadecimal number' => '{"value": 0x2A}',
      'non-finite number' => '{"value": Infinity}',
      'leading plus number' => '{"value": +1}'
    }

    invalid_sources.each do |description, source|
      result = described_class.parse_json(source, 'jsonc')

      expect(result[:ok]).to be(false), description
      expect(result.dig(:diagnostics, 0, :message)).to include('JSONC rejects'), description
    end
  end

  it 'exposes JSON TreeHaver backend availability and plan context' do
    expect(json_ready(described_class.available_json_backends.map(&:to_h))).to eq(
      [{ 'id' => 'kreuzberg-language-pack', 'family' => 'tree-sitter' }]
    )

    profile = described_class.json_backend_feature_profile
    expect(profile[:backend]).to eq('kreuzberg-language-pack')
    expect(json_ready(profile[:backend_ref])).to eq(
      { 'id' => 'kreuzberg-language-pack', 'family' => 'tree-sitter' }
    )

    expect(json_ready(described_class.json_plan_context.dig(:feature_profile))).to include(
      'backend' => 'kreuzberg-language-pack',
      'supports_dialects' => true
    )
  end

  it 'parses through an explicit JSON TreeHaver backend and rejects unsupported backends' do
    fixture = json_fixture('structure_json')
    result = described_class.parse_json(
      fixture[:source],
      fixture[:dialect],
      backend: 'kreuzberg-language-pack'
    )
    unsupported = described_class.parse_json(fixture[:source], fixture[:dialect], backend: :direct_json)

    expect(result[:ok]).to be(true)
    expect(unsupported[:ok]).to be(false)
    expect(unsupported.dig(:diagnostics, 0, :category)).to eq('unsupported_feature')
  end

  it 'rejects comments in strict JSON without rejecting comment-like string content' do
    strict_result = described_class.parse_json("{\n  // nope\n  \"name\": \"Ruby\"\n}\n", 'json')
    string_result = described_class.parse_json("{\"url\":\"https://example.test/path\"}\n", 'json')

    expect(strict_result[:ok]).to be(false)
    expect(strict_result.dig(:diagnostics, 0, :message)).to eq('Comments are not supported for json.')
    expect(string_result[:ok]).to be(true)
  end

  it 'self-registers the JSON backend for direct file analysis' do
    source = <<~JSON
      {
        "name": "Ruby",
        "customizations": {
          "jetbrains": {
            "backend": "RubyMine"
          }
        }
      }
    JSON

    analysis = described_class::FileAnalysis.new(source)

    expect(analysis).to be_valid
    expect(analysis.root_object).not_to be_nil
    expect(analysis.errors).to be_empty
  end

  it 'conforms to the structure fixtures' do
    object_fixture = json_fixture('structure_json')
    object_result = described_class.parse_json(object_fixture[:source], object_fixture[:dialect])
    expect(object_result[:ok]).to be(true)
    expect(object_result.dig(:analysis, :root_kind)).to eq(object_fixture.dig(:expected, :root_kind))
    expect(
      json_ready(object_result.dig(:analysis, :owners).map { |owner| owner.compact })
    ).to eq(json_ready(object_fixture.dig(:expected, :owners)))

    jsonc_fixture_data = jsonc_fixture('structure_jsonc')
    jsonc_result = described_class.parse_json(jsonc_fixture_data[:source], jsonc_fixture_data[:dialect])
    expect(jsonc_result[:ok]).to be(true)
    expect(jsonc_result.dig(:analysis, :root_kind)).to eq(jsonc_fixture_data.dig(:expected, :root_kind))
    expect(
      json_ready(jsonc_result.dig(:analysis, :owners).map { |owner| owner.compact })
    ).to eq(json_ready(jsonc_fixture_data.dig(:expected, :owners)))
  end

  it 'conforms to the owner matching fixture' do
    fixture = json_fixture('matching')
    template = described_class.parse_json(fixture[:template], 'json')
    destination = described_class.parse_json(fixture[:destination], 'json')
    result = described_class.match_json_owners(template[:analysis], destination[:analysis])

    expect(json_ready(result[:matched].map do |match|
      [match[:template_path], match[:destination_path]]
    end)).to eq(json_ready(fixture.dig(:expected, :matched)))
    expect(json_ready(result[:unmatched_template])).to eq(json_ready(fixture.dig(:expected, :unmatched_template)))
    expect(json_ready(result[:unmatched_destination])).to eq(json_ready(fixture.dig(:expected, :unmatched_destination)))
  end

  it 'conforms to the merge and fallback fixtures' do
    merge_fixture = json_fixture('merge_object')
    merge_result = described_class.merge_json(merge_fixture[:template], merge_fixture[:destination], 'json')
    expect(merge_result[:ok]).to be(true)
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    invalid_template_fixture = json_fixture('merge_invalid_template')
    invalid_template_result = described_class.merge_json(invalid_template_fixture[:template],
                                                         invalid_template_fixture[:destination], 'json')
    expect(invalid_template_result[:ok]).to eq(invalid_template_fixture.dig(:expected, :ok))
    expect(
      json_ready(invalid_template_result[:diagnostics].map { |diagnostic| diagnostic.slice(:severity, :category) })
    ).to eq(json_ready(invalid_template_fixture.dig(:expected, :diagnostics)))

    invalid_destination_fixture = json_fixture('merge_invalid_destination')
    invalid_destination_result = described_class.merge_json(invalid_destination_fixture[:template],
                                                            invalid_destination_fixture[:destination], 'json')
    expect(invalid_destination_result[:ok]).to eq(invalid_destination_fixture.dig(:expected, :ok))
    expect(
      json_ready(invalid_destination_result[:diagnostics].map { |diagnostic| diagnostic.slice(:severity, :category) })
    ).to eq(json_ready(invalid_destination_fixture.dig(:expected, :diagnostics)))

    fallback_fixture = json_fixture('fallback')
    fallback_result = described_class.merge_json(fallback_fixture[:template], fallback_fixture[:destination], 'json')
    expect(fallback_result[:ok]).to be(false)
    expect(
      json_ready(fallback_result[:diagnostics].map { |diagnostic| diagnostic.slice(:severity, :category) })
    ).to eq(json_ready([{ severity: 'error', category: 'destination_parse_error' }]))
  end

  it 'records emitter source provenance line metadata for raw source rendering' do
    emitter = described_class::Emitter.new
    emitter.emit_raw_lines(
      ['{', '  "name": "example"', '}'],
      metadata: { source: :destination, original_line_start: 7 }
    )

    expect(emitter.lines).to eq(['{', '  "name": "example"', '}'])
    expect(emitter.line_metadata).to eq(
      [
        { source: :destination, original_line: 7 },
        { source: :destination, original_line: 8 },
        { source: :destination, original_line: 9 }
      ]
    )
  end

  it 'preserves atomic subtree formatting while merging object children' do
    template = <<~JSON
      {
        "array": ["template"],
        "object": {"template": true},
        "template_only": {"compact": true}
      }
    JSON
    destination = <<~JSON
      {
        "array": ["destination"],
        "object": {"destination": true},
        "destination_only": {"compact": true}
      }
    JSON

    result = described_class.merge_json(template, destination, 'json')

    expect(result[:ok]).to be(true)
    expect(result[:output]).to eq(<<~JSON)
      {
        "array": ["destination"],
        "object": {
          "template": true,
          "destination": true
        },
        "destination_only": {"compact": true},
        "template_only": {"compact": true}
      }
    JSON
  end

  it 'merges JSONC documents with trailing commas through the JSON5-normalized path' do
    template = <<~JSONC
      {
        "template": true,
      }
    JSONC
    destination = <<~JSONC
      // retained destination comment
      {
        "destination": true,
      }
    JSONC

    result = described_class.merge_json(template, destination, 'jsonc')

    expect(result[:ok]).to be(true)
    expect(result[:output]).to include('"destination": true')
    expect(result[:output]).to include('"template": true')
  end

  it 'rejects unsupported direct merger dialects' do
    expect do
      described_class::SmartMerger.new('{"value": true}', '{"value": true}', dialect: :json5)
    end.to raise_error(ArgumentError, /Expected json or jsonc/)
  end

  it 'conforms to the shared family feature profile fixture' do
    expected_profile = family_profile_fixture[:feature_profile].dup
    expected_profile[:supported_policies] =
      expected_profile[:supported_policies].reject { |policy| policy[:surface] == 'fallback' }

    expect(json_ready(described_class.json_feature_profile)).to eq(json_ready(expected_profile))
  end
end
