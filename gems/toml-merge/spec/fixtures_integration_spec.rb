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

  %w[citrus parslet].each do |backend|
    it "conforms to the TOML parse, structure, matching, and merge fixtures with #{backend}" do
      parse_fixture = toml_fixture("parse_valid")
      parse_result = described_class.parse_toml(parse_fixture[:source], parse_fixture[:dialect], backend: backend)
      expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
      expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

      structure_fixture = toml_fixture("structure")
      structure_result = described_class.parse_toml(structure_fixture[:source], structure_fixture[:dialect], backend: backend)
      expect(json_ready(structure_result.dig(:analysis, :owners))).to eq(json_ready(structure_fixture.dig(:expected, :owners)))

      matching_fixture = toml_fixture("matching")
      template = described_class.parse_toml(matching_fixture[:template], "toml", backend: backend)
      destination = described_class.parse_toml(matching_fixture[:destination], "toml", backend: backend)
      matching_result = described_class.match_toml_owners(template[:analysis], destination[:analysis])
      expect(json_ready(matching_result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

      merge_fixture = toml_fixture("merge")
      merge_result = described_class.merge_toml(merge_fixture[:template], merge_fixture[:destination], "toml", backend: backend)
      expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
      expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))
    end
  end

  it "keeps the shared family feature fixture stable while exposing backend-specific feature profiles" do
    expect(json_ready(described_class.toml_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
    expect(json_ready(described_class.toml_backend_feature_profile(backend: "citrus")[:backend_ref])).to eq(
      json_ready({ id: "citrus", family: "peg" })
    )
    expect(json_ready(described_class.toml_backend_feature_profile(backend: "parslet")[:backend_ref])).to eq(
      json_ready({ id: "parslet", family: "peg" })
    )
  end

  it "conforms to the slice-135 TOML backend feature profile fixtures" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-135-toml-family-backend-feature-profiles",
        "ruby-toml-backend-feature-profiles.json"
      )
    )

    expect(json_ready(described_class.toml_backend_feature_profile(backend: "citrus"))).to include(
      json_ready(fixture[:citrus])
    )
    expect(json_ready(described_class.toml_backend_feature_profile(backend: "parslet"))).to include(
      json_ready(fixture[:parslet])
    )
  end

  it "conforms to the slice-136 TOML plan-context fixtures" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-136-toml-family-plan-contexts",
        "ruby-toml-plan-contexts.json"
      )
    )

    expect(json_ready(described_class.toml_plan_context(backend: "citrus"))).to eq(json_ready(fixture[:citrus]))
    expect(json_ready(described_class.toml_plan_context(backend: "parslet"))).to eq(json_ready(fixture[:parslet]))
  end

  it "conforms to the slice-137 TOML family manifest fixture" do
    manifest = read_json(fixtures_root.join("conformance", "slice-137-toml-family-manifest", "toml-family-manifest.json"))

    expect(Ast::Merge.conformance_family_feature_profile_path(manifest, "toml")).to eq(
      %w[diagnostics slice-90-toml-family-feature-profile toml-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "toml", "analysis")).to eq(
      %w[toml slice-92-structure table-and-array.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "toml", "matching")).to eq(
      %w[toml slice-93-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "toml", "merge")).to eq(
      %w[toml slice-94-merge table-merge.json]
    )
  end

  it "resolves TOML paths through the canonical manifest" do
    expect(Ast::Merge.conformance_family_feature_profile_path(manifest, "toml")).to eq(
      %w[diagnostics slice-90-toml-family-feature-profile toml-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "toml", "analysis")).to eq(
      %w[toml slice-92-structure table-and-array.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "toml", "matching")).to eq(
      %w[toml slice-93-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "toml", "merge")).to eq(
      %w[toml slice-94-merge table-merge.json]
    )
  end

  it "uses the tree_haver backend context when no explicit TOML backend is given" do
    TreeHaver.with_backend("parslet") do
      fixture = toml_fixture("merge")
      merge_result = described_class.merge_toml(fixture[:template], fixture[:destination], "toml")
      expect(merge_result[:ok]).to be(true)
      expect(merge_result[:output]).to eq(fixture.dig(:expected, :output))
    end
  end
end
