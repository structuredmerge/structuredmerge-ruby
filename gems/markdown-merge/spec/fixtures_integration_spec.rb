# frozen_string_literal: true

RSpec.describe Markdown::Merge do
  let(:markdown_merge) { ::Markdown::Merge }
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the slice-194 Markdown feature profile fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-194-markdown-family-feature-profile",
        "markdown-feature-profile.json"
      )
    )

    expect(json_ready(markdown_merge.markdown_feature_profile)).to eq(json_ready(fixture[:feature_profile]))
  end

  it "conforms to the slice-195 Markdown backend feature profile fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-195-markdown-family-backend-feature-profiles",
        "ruby-markdown-backend-feature-profiles.json"
      )
    )

    expect(json_ready(markdown_merge.available_markdown_backends.map(&:to_h))).to eq(
      json_ready([
        { id: "kramdown", family: "native" },
        { id: "kreuzberg-language-pack", family: "tree-sitter" }
      ])
    )
    expect(json_ready(markdown_merge.markdown_backend_feature_profile(backend: "kramdown"))).to eq(
      json_ready(fixture[:native].merge(family: "markdown", supported_dialects: ["markdown"]))
    )
    expect(json_ready(markdown_merge.markdown_backend_feature_profile(backend: "kreuzberg-language-pack"))).to eq(
      json_ready(fixture[:tree_sitter].merge(family: "markdown", supported_dialects: ["markdown"]))
    )
  end

  it "conforms to the slice-196 Markdown plan-context fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-196-markdown-family-plan-contexts",
        "ruby-markdown-plan-contexts.json"
      )
    )

    expect(json_ready(markdown_merge.markdown_plan_context(backend: "kramdown"))).to eq(json_ready(fixture[:native]))
    expect(json_ready(markdown_merge.markdown_plan_context(backend: "kreuzberg-language-pack"))).to eq(
      json_ready(fixture[:tree_sitter])
    )
  end

  it "conforms to the slice-197 Markdown family manifest fixture" do
    manifest = read_json(
      fixtures_root.join("conformance", "slice-197-markdown-family-manifest", "markdown-family-manifest.json")
    )

    expect(Ast::Merge.conformance_family_feature_profile_path(manifest, "markdown")).to eq(
      %w[diagnostics slice-194-markdown-family-feature-profile markdown-feature-profile.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "markdown", "analysis")).to eq(
      %w[markdown slice-198-analysis headings-and-code-fences.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest, "markdown", "matching")).to eq(
      %w[markdown slice-199-matching path-equality.json]
    )
  end

  it "conforms to the slice-198 Markdown analysis fixture" do
    fixture = read_json(fixtures_root.join("markdown", "slice-198-analysis", "headings-and-code-fences.json"))

    %w[kramdown kreuzberg-language-pack].each do |backend|
      result = markdown_merge.parse_markdown(fixture[:source], fixture[:dialect], backend: backend)
      expect(result[:ok]).to be(true)
      expect(result.dig(:analysis, :root_kind)).to eq(fixture.dig(:expected, :root_kind))
      expect(json_ready(result.dig(:analysis, :owners))).to eq(
        json_ready(
          fixture.dig(:expected, :owners).map do |owner|
            {
              path: owner[:path],
              owner_kind: owner[:owner_kind],
              match_key: owner[:match_key],
              **(owner[:level] ? { level: owner[:level] } : {}),
              **(owner[:info_string] ? { info_string: owner[:info_string] } : {})
            }
          end
        )
      )
    end
  end

  it "conforms to the slice-199 Markdown matching fixture" do
    fixture = read_json(fixtures_root.join("markdown", "slice-199-matching", "path-equality.json"))

    %w[kramdown kreuzberg-language-pack].each do |backend|
      template = markdown_merge.parse_markdown(fixture[:template], fixture[:dialect], backend: backend)
      destination = markdown_merge.parse_markdown(fixture[:destination], fixture[:dialect], backend: backend)
      result = markdown_merge.match_markdown_owners(template[:analysis], destination[:analysis])

      expect(json_ready(result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
        json_ready(fixture.dig(:expected, :matched))
      )
      expect(json_ready(result[:unmatched_template])).to eq(json_ready(fixture.dig(:expected, :unmatched_template)))
      expect(json_ready(result[:unmatched_destination])).to eq(
        json_ready(fixture.dig(:expected, :unmatched_destination))
      )
    end
  end
end
