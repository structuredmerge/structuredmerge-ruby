# frozen_string_literal: true

RSpec.describe TypeScript::Merge do
  def fixtures_root = Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  def read_json(path) = Ast::Merge.normalize_value(JSON.parse(path.read))
  def json_ready(value) = Ast::Merge.json_ready(value)

  it "conforms to the TypeScript source-family fixtures" do
    feature = read_json(fixtures_root.join("diagnostics", "slice-101-typescript-family-feature-profile", "typescript-feature-profile.json"))
    expect(json_ready(described_class.type_script_feature_profile)).to eq(json_ready(feature[:feature_profile]))

    analysis_fixture = read_json(fixtures_root.join("typescript", "slice-102-analysis", "module-owners.json"))
    analysis = described_class.parse_type_script(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    matching_fixture = read_json(fixtures_root.join("typescript", "slice-103-matching", "path-equality.json"))
    template = described_class.parse_type_script(matching_fixture[:template], "typescript")
    destination = described_class.parse_type_script(matching_fixture[:destination], "typescript")
    matching = described_class.match_type_script_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = read_json(fixtures_root.join("typescript", "slice-104-merge", "module-merge.json"))
    merge = described_class.merge_type_script(merge_fixture[:template], merge_fixture[:destination], "typescript")
    expect(merge[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge[:output]).to eq(merge_fixture.dig(:expected, :output))

    backends_fixture = read_json(fixtures_root.join("diagnostics", "slice-115-typescript-family-backends", "typescript-backends.json"))
    expect(described_class.available_type_script_backends.map(&:to_h)).to eq([{ id: "kreuzberg-language-pack", family: "tree-sitter" }])
    expect(json_ready(TreeHaver::BackendRegistry.fetch("kreuzberg-language-pack")&.to_h)).to eq(
      json_ready({ id: "kreuzberg-language-pack", family: "tree-sitter" })
    )
    expect(json_ready(backends_fixture[:backends])).to eq(json_ready(["kreuzberg-language-pack"]))

    backend_profiles = read_json(fixtures_root.join("diagnostics", "slice-122-source-family-backend-feature-profiles", "typescript-backend-feature-profiles.json"))
    expect(json_ready(described_class.type_script_backend_feature_profile)).to eq(
      json_ready(backend_profiles[:tree_sitter].merge(family: "typescript", supported_dialects: ["typescript"]))
    )

    plan_contexts = read_json(fixtures_root.join("diagnostics", "slice-123-source-family-plan-contexts", "typescript-plan-contexts.json"))
    expect(json_ready(described_class.type_script_plan_context)).to eq(json_ready(plan_contexts[:tree_sitter]))

    source_manifest = read_json(fixtures_root.join("conformance", "slice-124-source-family-manifest", "source-family-manifest.json"))
    expect(Ast::Merge.conformance_family_feature_profile_path(source_manifest, "typescript")).to eq(
      %w[diagnostics slice-101-typescript-family-feature-profile typescript-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "typescript", "analysis")).to eq(
      %w[typescript slice-102-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "typescript", "matching")).to eq(
      %w[typescript slice-103-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "typescript", "merge")).to eq(
      %w[typescript slice-104-merge module-merge.json]
    )

    canonical_manifest = read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
    expect(Ast::Merge.conformance_family_feature_profile_path(canonical_manifest, "typescript")).to eq(
      %w[diagnostics slice-101-typescript-family-feature-profile typescript-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "typescript", "analysis")).to eq(
      %w[typescript slice-102-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "typescript", "matching")).to eq(
      %w[typescript slice-103-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "typescript", "merge")).to eq(
      %w[typescript slice-104-merge module-merge.json]
    )
  end
end
