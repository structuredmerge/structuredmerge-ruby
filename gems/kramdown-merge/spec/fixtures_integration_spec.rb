# frozen_string_literal: true

RSpec.describe Kramdown::Merge do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "exposes the Markdown family through the Kramdown provider backend" do
    feature_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-194-markdown-family-feature-profile",
        "markdown-feature-profile.json"
      )
    )
    plan_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-196-markdown-family-plan-contexts",
        "ruby-markdown-plan-contexts.json"
      )
    )

    expect(json_ready(described_class.markdown_feature_profile)).to eq(json_ready(feature_fixture[:feature_profile]))
    expect(json_ready(described_class.available_markdown_backends.map(&:to_h))).to eq(
      json_ready([{ id: "kramdown", family: "native" }])
    )
    expect(json_ready(described_class.markdown_backend_feature_profile)).to eq(
      json_ready({ family: "markdown", supported_dialects: ["markdown"], supported_policies: [], backend: "kramdown" })
    )
    expect(json_ready(described_class.markdown_plan_context)).to eq(json_ready(plan_fixture[:native]))
  end

  it "conforms to the shared Markdown analysis and matching fixtures" do
    analysis_fixture = read_json(
      fixtures_root.join("markdown", "slice-198-analysis", "headings-and-code-fences.json")
    )
    matching_fixture = read_json(
      fixtures_root.join("markdown", "slice-199-matching", "path-equality.json")
    )

    analysis = described_class.parse_markdown(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(analysis.dig(:analysis, :root_kind)).to eq("document")

    template = described_class.parse_markdown(matching_fixture[:template], matching_fixture[:dialect])
    destination = described_class.parse_markdown(matching_fixture[:destination], matching_fixture[:dialect])
    result = described_class.match_markdown_owners(template[:analysis], destination[:analysis])

    expect(json_ready(result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )
    expect(json_ready(result[:unmatched_template])).to eq(json_ready(matching_fixture.dig(:expected, :unmatched_template)))
    expect(json_ready(result[:unmatched_destination])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_destination))
    )
  end

  it "rejects unsupported provider backend overrides" do
    result = described_class.parse_markdown("# Title\n", "markdown", backend: "kreuzberg-language-pack")
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to eq(
      [{ severity: "error", category: "unsupported_feature", message: "Unsupported Markdown backend kreuzberg-language-pack." }]
    )
  end
end
