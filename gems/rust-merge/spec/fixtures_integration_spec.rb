# frozen_string_literal: true

RSpec.describe Rust::Merge do
  def fixtures_root = Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  def read_json(path) = Ast::Merge.normalize_value(JSON.parse(path.read))
  def json_ready(value) = Ast::Merge.json_ready(value)

  it "conforms to the Rust source-family fixtures" do
    feature = read_json(fixtures_root.join("diagnostics", "slice-105-rust-family-feature-profile", "rust-feature-profile.json"))
    expect(json_ready(described_class.rust_feature_profile)).to eq(json_ready(feature[:feature_profile]))

    analysis_fixture = read_json(fixtures_root.join("rust", "slice-106-analysis", "module-owners.json"))
    analysis = described_class.parse_rust(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    matching_fixture = read_json(fixtures_root.join("rust", "slice-107-matching", "path-equality.json"))
    template = described_class.parse_rust(matching_fixture[:template], "rust")
    destination = described_class.parse_rust(matching_fixture[:destination], "rust")
    matching = described_class.match_rust_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(json_ready(matching_fixture.dig(:expected, :matched)))

    merge_fixture = read_json(fixtures_root.join("rust", "slice-108-merge", "module-merge.json"))
    merge = described_class.merge_rust(merge_fixture[:template], merge_fixture[:destination], "rust")
    expect(merge[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge[:output]).to eq(merge_fixture.dig(:expected, :output))

    backend_profiles = read_json(fixtures_root.join("diagnostics", "slice-122-source-family-backend-feature-profiles", "rust-backend-feature-profiles.json"))
    expect(json_ready(described_class.rust_backend_feature_profile)).to eq(
      json_ready(backend_profiles[:tree_sitter].merge(family: "rust", supported_dialects: ["rust"]))
    )

    plan_contexts = read_json(fixtures_root.join("diagnostics", "slice-123-source-family-plan-contexts", "rust-plan-contexts.json"))
    expect(json_ready(described_class.rust_plan_context)).to eq(json_ready(plan_contexts[:tree_sitter]))

    source_manifest = read_json(fixtures_root.join("conformance", "slice-124-source-family-manifest", "source-family-manifest.json"))
    expect(Ast::Merge.conformance_family_feature_profile_path(source_manifest, "rust")).to eq(
      %w[diagnostics slice-105-rust-family-feature-profile rust-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "rust", "analysis")).to eq(
      %w[rust slice-106-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "rust", "matching")).to eq(
      %w[rust slice-107-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(source_manifest, "rust", "merge")).to eq(
      %w[rust slice-108-merge module-merge.json]
    )

    canonical_manifest = read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
    expect(Ast::Merge.conformance_family_feature_profile_path(canonical_manifest, "rust")).to eq(
      %w[diagnostics slice-105-rust-family-feature-profile rust-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "rust", "analysis")).to eq(
      %w[rust slice-106-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "rust", "matching")).to eq(
      %w[rust slice-107-matching path-equality.json]
    )
    expect(Ast::Merge.conformance_fixture_path(canonical_manifest, "rust", "merge")).to eq(
      %w[rust slice-108-merge module-merge.json]
    )
  end
end
