# frozen_string_literal: true

RSpec.describe Go::Merge do
  def fixtures_root = Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  def read_json(path) = Ast::Merge.normalize_value(JSON.parse(path.read))
  def json_ready(value) = Ast::Merge.json_ready(value)

  it "conforms to the Go source-family fixtures" do
    feature = read_json(fixtures_root.join("diagnostics", "slice-109-go-family-feature-profile", "go-feature-profile.json"))
    expect(json_ready(described_class.go_feature_profile)).to eq(json_ready(feature[:feature_profile]))

    analysis_fixture = read_json(fixtures_root.join("go", "slice-110-analysis", "module-owners.json"))
    analysis = described_class.parse_go(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    matching_fixture = read_json(fixtures_root.join("go", "slice-111-matching", "path-equality.json"))
    template = described_class.parse_go(matching_fixture[:template], "go")
    destination = described_class.parse_go(matching_fixture[:destination], "go")
    matching = described_class.match_go_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = read_json(fixtures_root.join("go", "slice-112-merge", "module-merge.json"))
    merge = described_class.merge_go(merge_fixture[:template], merge_fixture[:destination], "go")
    expect(merge[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge[:output]).to eq(merge_fixture.dig(:expected, :output))

    backends_fixture = read_json(fixtures_root.join("diagnostics", "slice-113-go-family-backends", "go-backends.json"))
    expect(described_class.available_go_backends.map(&:to_h)).to eq([{ id: "kreuzberg-language-pack", family: "tree-sitter" }])
    expect(json_ready(TreeHaver::BackendRegistry.fetch("kreuzberg-language-pack")&.to_h)).to eq(
      json_ready({ id: "kreuzberg-language-pack", family: "tree-sitter" })
    )
    expect(json_ready(backends_fixture[:backends])).to eq(json_ready(["kreuzberg-language-pack"]))

    backend_profiles = read_json(fixtures_root.join("diagnostics", "slice-122-source-family-backend-feature-profiles", "go-backend-feature-profiles.json"))
    expect(json_ready(described_class.go_backend_feature_profile)).to eq(
      json_ready(backend_profiles[:tree_sitter].merge(family: "go", supported_dialects: ["go"]))
    )

    plan_contexts = read_json(fixtures_root.join("diagnostics", "slice-123-source-family-plan-contexts", "go-plan-contexts.json"))
    expect(json_ready(described_class.go_plan_context)).to eq(json_ready(plan_contexts[:tree_sitter]))

    source_manifest = read_json(fixtures_root.join("conformance", "slice-124-source-family-manifest", "source-family-manifest.json"))
    expect(Ast::Merge.conformance_family_feature_profile_path(source_manifest, "go")).to eq(
      %w[diagnostics slice-109-go-family-feature-profile go-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "go", "analysis")).to eq(
      %w[go slice-110-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "go", "matching")).to eq(
      %w[go slice-111-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "go", "merge")).to eq(
      %w[go slice-112-merge module-merge.json]
    )

    canonical_manifest = read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
    expect(Ast::Merge.conformance_family_feature_profile_path(canonical_manifest, "go")).to eq(
      %w[diagnostics slice-109-go-family-feature-profile go-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "go", "analysis")).to eq(
      %w[go slice-110-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "go", "matching")).to eq(
      %w[go slice-111-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "go", "merge")).to eq(
      %w[go slice-112-merge module-merge.json]
    )
  end
end
