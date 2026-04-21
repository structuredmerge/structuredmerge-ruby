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

  it "conforms to the YAML parse, structure, matching, merge, and feature fixtures through the substrate backend" do
    parse_fixture = yaml_fixture("parse_valid")
    structure_fixture = yaml_fixture("structure")
    matching_fixture = yaml_fixture("matching")
    merge_fixture = yaml_fixture("merge")

    parse_result = described_class.parse_yaml(parse_fixture[:source], parse_fixture[:dialect], backend: "kreuzberg-language-pack")
    expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
    expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

    structure_result = described_class.parse_yaml(structure_fixture[:source], structure_fixture[:dialect], backend: "kreuzberg-language-pack")
    expect(json_ready(structure_result.dig(:analysis, :owners))).to eq(json_ready(structure_fixture.dig(:expected, :owners)))

    template = described_class.parse_yaml(matching_fixture[:template], "yaml", backend: "kreuzberg-language-pack")
    destination = described_class.parse_yaml(matching_fixture[:destination], "yaml", backend: "kreuzberg-language-pack")
    matching_result = described_class.match_yaml_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching_result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )

    merge_result = described_class.merge_yaml(
      merge_fixture[:template],
      merge_fixture[:destination],
      "yaml",
      backend: "kreuzberg-language-pack"
    )
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    expect(json_ready(described_class.yaml_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
  end

  it "conforms to the slice-171 YAML backend feature profile fixtures" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-171-yaml-family-backend-feature-profiles",
        "ruby-yaml-backend-feature-profiles.json"
      )
    )

    expect(json_ready(described_class.available_yaml_backends.map(&:to_h))).to eq(
      json_ready([{ id: "kreuzberg-language-pack", family: "tree-sitter" }])
    )
    expect(json_ready(described_class.yaml_backend_feature_profile(backend: "kreuzberg-language-pack"))).to eq(
      json_ready(fixture[:tree_sitter])
    )
  end

  it "conforms to the slice-172 YAML backend plan-context fixtures" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-172-yaml-family-backend-plan-contexts",
        "ruby-yaml-plan-contexts.json"
      )
    )

    expect(json_ready(described_class.yaml_plan_context(backend: "kreuzberg-language-pack"))).to eq(
      json_ready(fixture[:tree_sitter])
    )
  end

  it "conforms to the slice-143 YAML family manifest fixture" do
    yaml_manifest = read_json(fixtures_root.join("conformance", "slice-143-yaml-family-manifest", "yaml-family-manifest.json"))

    expect(Ast::Merge.conformance_family_feature_profile_path(yaml_manifest, "yaml")).to eq(
      %w[diagnostics slice-95-yaml-family-feature-profile yaml-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(yaml_manifest, "yaml", "analysis")).to eq(
      %w[yaml slice-97-structure mapping-and-sequence.json]
    )
    expect(Ast::Merge.conformance_fixture_path(yaml_manifest, "yaml", "merge")).to eq(
      %w[yaml slice-99-merge mapping-merge.json]
    )
  end

  it "resolves YAML paths through the canonical manifest" do
    expect(Ast::Merge.conformance_family_feature_profile_path(manifest, "yaml")).to eq(
      %w[diagnostics slice-95-yaml-family-feature-profile yaml-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "yaml", "matching")).to eq(
      %w[yaml slice-98-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "yaml", "merge")).to eq(
      %w[yaml slice-99-merge mapping-merge.json]
    )
  end

  it "uses kreuzberg-language-pack by default when no explicit YAML backend is given" do
    fixture = yaml_fixture("merge")
    merge_result = described_class.merge_yaml(fixture[:template], fixture[:destination], "yaml")
    expect(merge_result[:ok]).to be(true)
    expect(merge_result[:output]).to eq(fixture.dig(:expected, :output))
  end
end
