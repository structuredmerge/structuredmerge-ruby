# frozen_string_literal: true

RSpec.describe Toml::Merge do
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
    read_json(fixtures_root.join("diagnostics", "slice-90-toml-family-feature-profile", "toml-feature-profile.json"))
  end

  def toml_fixture(role)
    path = {
      "parse_valid" => %w[toml slice-91-parse valid-document.json],
      "structure" => %w[toml slice-92-structure table-and-array.json],
      "matching" => %w[toml slice-93-matching path-equality.json],
      "merge" => %w[toml slice-94-merge table-merge.json]
    }.fetch(role)
    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the TOML parse, structure, matching, merge, and feature fixtures" do
    parse_fixture = toml_fixture("parse_valid")
    parse_result = described_class.parse_toml(parse_fixture[:source], parse_fixture[:dialect])
    expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
    expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

    structure_fixture = toml_fixture("structure")
    structure_result = described_class.parse_toml(structure_fixture[:source], structure_fixture[:dialect])
    expect(json_ready(structure_result.dig(:analysis, :owners))).to eq(json_ready(structure_fixture.dig(:expected, :owners)))

    matching_fixture = toml_fixture("matching")
    template = described_class.parse_toml(matching_fixture[:template], "toml")
    destination = described_class.parse_toml(matching_fixture[:destination], "toml")
    matching_result = described_class.match_toml_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching_result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = toml_fixture("merge")
    merge_result = described_class.merge_toml(merge_fixture[:template], merge_fixture[:destination], "toml")
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    expect(json_ready(described_class.toml_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
  end
end
