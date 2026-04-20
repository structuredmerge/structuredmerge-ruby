# frozen_string_literal: true

RSpec.describe Yaml::Merge do
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
    read_json(fixtures_root.join("diagnostics", "slice-95-yaml-family-feature-profile", "yaml-feature-profile.json"))
  end

  def yaml_fixture(role)
    path = {
      "parse_valid" => %w[yaml slice-96-parse valid-document.json],
      "structure" => %w[yaml slice-97-structure mapping-and-sequence.json],
      "matching" => %w[yaml slice-98-matching path-equality.json],
      "merge" => %w[yaml slice-99-merge mapping-merge.json]
    }.fetch(role)
    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the YAML parse, structure, matching, merge, and feature fixtures" do
    parse_fixture = yaml_fixture("parse_valid")
    parse_result = described_class.parse_yaml(parse_fixture[:source], parse_fixture[:dialect])
    expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
    expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

    structure_fixture = yaml_fixture("structure")
    structure_result = described_class.parse_yaml(structure_fixture[:source], structure_fixture[:dialect])
    expect(json_ready(structure_result.dig(:analysis, :owners))).to eq(json_ready(structure_fixture.dig(:expected, :owners)))

    matching_fixture = yaml_fixture("matching")
    template = described_class.parse_yaml(matching_fixture[:template], "yaml")
    destination = described_class.parse_yaml(matching_fixture[:destination], "yaml")
    matching_result = described_class.match_yaml_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching_result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = yaml_fixture("merge")
    merge_result = described_class.merge_yaml(merge_fixture[:template], merge_fixture[:destination], "yaml")
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    expect(json_ready(described_class.yaml_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
  end
end
