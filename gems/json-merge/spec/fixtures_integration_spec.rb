# frozen_string_literal: true

RSpec.describe Json::Merge do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
  end

  def family_profile_fixture
    path = Ast::Merge.conformance_family_feature_profile_path(manifest, "json")
    read_json(fixtures_root.join(*path))
  end

  def json_fixture(role)
    path = Ast::Merge.conformance_fixture_path(manifest, "json", role)
    raise "missing json fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def jsonc_fixture(role)
    direct_paths = {
      "parse_comments" => %w[jsonc slice-04-parse comments-accepted.json],
      "structure_jsonc" => %w[jsonc slice-07-structure commented-object.json]
    }
    path = direct_paths[role]
    path && read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the jsonc comments-accepted fixture" do
    fixture = jsonc_fixture("parse_comments")
    result = described_class.parse_json(fixture[:source], fixture[:dialect])

    expect(result[:ok]).to eq(fixture.dig(:expected, :ok))
    expect(result.dig(:analysis, :allows_comments)).to eq(fixture.dig(:expected, :allows_comments))
    expect(json_ready(result[:diagnostics])).to eq(json_ready(fixture.dig(:expected, :diagnostics)))
  end

  it "conforms to the structure fixtures" do
    object_fixture = json_fixture("structure_json")
    object_result = described_class.parse_json(object_fixture[:source], object_fixture[:dialect])
    expect(object_result[:ok]).to be(true)
    expect(object_result.dig(:analysis, :root_kind)).to eq(object_fixture.dig(:expected, :root_kind))
    expect(
      json_ready(object_result.dig(:analysis, :owners).map { |owner| owner.compact })
    ).to eq(json_ready(object_fixture.dig(:expected, :owners)))

    jsonc_fixture_data = jsonc_fixture("structure_jsonc")
    jsonc_result = described_class.parse_json(jsonc_fixture_data[:source], jsonc_fixture_data[:dialect])
    expect(jsonc_result[:ok]).to be(true)
    expect(jsonc_result.dig(:analysis, :root_kind)).to eq(jsonc_fixture_data.dig(:expected, :root_kind))
    expect(
      json_ready(jsonc_result.dig(:analysis, :owners).map { |owner| owner.compact })
    ).to eq(json_ready(jsonc_fixture_data.dig(:expected, :owners)))
  end

  it "conforms to the owner matching fixture" do
    fixture = json_fixture("matching")
    template = described_class.parse_json(fixture[:template], "json")
    destination = described_class.parse_json(fixture[:destination], "json")
    result = described_class.match_json_owners(template[:analysis], destination[:analysis])

    expect(json_ready(result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(fixture.dig(:expected, :matched)))
    expect(json_ready(result[:unmatched_template])).to eq(json_ready(fixture.dig(:expected, :unmatched_template)))
    expect(json_ready(result[:unmatched_destination])).to eq(json_ready(fixture.dig(:expected, :unmatched_destination)))
  end

  it "conforms to the merge and fallback fixtures" do
    merge_fixture = json_fixture("merge_object")
    merge_result = described_class.merge_json(merge_fixture[:template], merge_fixture[:destination], "json")
    expect(merge_result[:ok]).to be(true)
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    invalid_template_fixture = json_fixture("merge_invalid_template")
    invalid_template_result = described_class.merge_json(invalid_template_fixture[:template], invalid_template_fixture[:destination], "json")
    expect(invalid_template_result[:ok]).to eq(invalid_template_fixture.dig(:expected, :ok))
    expect(
      json_ready(invalid_template_result[:diagnostics].map { |diagnostic| diagnostic.slice(:severity, :category) })
    ).to eq(json_ready(invalid_template_fixture.dig(:expected, :diagnostics)))

    invalid_destination_fixture = json_fixture("merge_invalid_destination")
    invalid_destination_result = described_class.merge_json(invalid_destination_fixture[:template], invalid_destination_fixture[:destination], "json")
    expect(invalid_destination_result[:ok]).to eq(invalid_destination_fixture.dig(:expected, :ok))
    expect(
      json_ready(invalid_destination_result[:diagnostics].map { |diagnostic| diagnostic.slice(:severity, :category) })
    ).to eq(json_ready(invalid_destination_fixture.dig(:expected, :diagnostics)))

    fallback_fixture = json_fixture("fallback")
    fallback_result = described_class.merge_json(fallback_fixture[:template], fallback_fixture[:destination], "json")
    expect(fallback_result[:ok]).to eq(fallback_fixture.dig(:expected, :ok))
    expect(fallback_result[:output]).to eq(fallback_fixture.dig(:expected, :output))
    expect(
      json_ready(fallback_result[:diagnostics].map { |diagnostic| diagnostic.slice(:severity, :category) })
    ).to eq(json_ready(fallback_fixture.dig(:expected, :diagnostics)))
  end

  it "conforms to the language-pack adapter fixture and shared family feature profile fixture" do
    adapter_fixture = json_fixture("tree_sitter_adapter")
    adapter_fixture[:cases].each do |test_case|
      result = described_class.parse_json_with_language_pack(test_case[:source], test_case[:dialect])
      expect(result[:ok]).to eq(test_case.dig(:expected, :ok))
      expect(
        json_ready(Array(result[:diagnostics]).map { |diagnostic| diagnostic.slice(:severity, :category) })
      ).to eq(json_ready(test_case.dig(:expected, :diagnostics).map { |diagnostic| diagnostic.slice(:severity, :category) }))
    end

    expect(json_ready(described_class.json_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
  end
end
