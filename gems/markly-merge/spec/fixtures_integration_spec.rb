# frozen_string_literal: true

RSpec.describe Markly::Merge do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "exposes the Markdown family through the Markly provider backend" do
    family_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-194-markdown-family-feature-profile", "markdown-feature-profile.json")
    )
    feature_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-204-markdown-provider-feature-profiles",
        "ruby-markdown-provider-feature-profiles.json"
      )
    )
    plan_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-205-markdown-provider-plan-contexts",
        "ruby-markdown-provider-plan-contexts.json"
      )
    )

    expect(json_ready(described_class.markdown_feature_profile)).to eq(json_ready(family_fixture[:feature_profile]))
    expect(json_ready(described_class.available_markdown_backends.map(&:to_h))).to eq(
      json_ready([{ id: "markly", family: "native" }])
    )
    expect(json_ready(described_class.markdown_backend_feature_profile)).to eq(
      json_ready(feature_fixture.dig(:providers, :markly, :feature_profile))
    )
    expect(json_ready(described_class.markdown_plan_context)).to eq(json_ready(plan_fixture.dig(:providers, :markly)))
  end

  it "conforms to the shared Markdown analysis and matching fixtures" do
    analysis_fixture = read_json(fixtures_root.join("markdown", "slice-198-analysis", "headings-and-code-fences.json"))
    matching_fixture = read_json(fixtures_root.join("markdown", "slice-199-matching", "path-equality.json"))

    analysis = described_class.parse_markdown(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    template = described_class.parse_markdown(matching_fixture[:template], matching_fixture[:dialect])
    destination = described_class.parse_markdown(matching_fixture[:destination], matching_fixture[:dialect])
    result = described_class.match_markdown_owners(template[:analysis], destination[:analysis])

    expect(json_ready(result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )
  end
end
