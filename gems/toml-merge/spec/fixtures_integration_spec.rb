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

  it "conforms to the TOML parse, structure, matching, and merge fixtures with the tree-sitter substrate" do
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
  end

  it "keeps the shared family feature fixture stable while exposing the substrate backend feature profile" do
    expect(json_ready(described_class.toml_feature_profile)).to eq(json_ready(family_profile_fixture[:feature_profile]))
    expect(json_ready(described_class.available_toml_backends.map(&:to_h))).to eq(
      json_ready([{ id: "kreuzberg-language-pack", family: "tree-sitter" }])
    )
    expect(json_ready(TreeHaver::BackendRegistry.fetch("kreuzberg-language-pack")&.to_h)).to eq(
      json_ready({ id: "kreuzberg-language-pack", family: "tree-sitter" })
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

    expect(json_ready(described_class.toml_backend_feature_profile)).to include(
      json_ready(fixture[:tree_sitter])
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

    expect(json_ready(described_class.toml_plan_context)).to eq(json_ready(fixture[:tree_sitter]))
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

  it "rejects unsupported provider backend overrides" do
    result = described_class.parse_toml("title = \"x\"\n", "toml", backend: "parslet")
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to eq(
      [{ severity: "error", category: "unsupported_feature", message: "Unsupported TOML backend parslet." }]
    )
  end

  it "conforms to the slice-139 family named-suite plan fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-139-toml-family-named-suite-plans",
        "ruby-toml-named-suite-plans.json"
      )
    )

    entries = Ast::Merge.plan_named_conformance_suites(fixture[:manifest], fixture[:contexts])
    expect(json_ready(entries)).to eq(json_ready(fixture[:expected_entries]))
  end

  it "conforms to the slice-140 family manifest report fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-140-toml-family-manifest-report",
        "ruby-toml-manifest-report.json"
      )
    )

    report = Ast::Merge.report_conformance_manifest(fixture[:manifest], fixture[:options]) do |run|
      key = "#{run[:ref][:family]}:#{run[:ref][:role]}:#{run[:ref][:case]}"
      fixture[:executions][key.to_sym] || fixture[:executions][key] || { outcome: "failed", messages: ["missing execution"] }
    end

    expect(json_ready(report)).to eq(json_ready(fixture[:expected_report]))
  end
end
