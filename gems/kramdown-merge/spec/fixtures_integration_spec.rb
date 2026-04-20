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
    family_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-194-markdown-family-feature-profile",
        "markdown-feature-profile.json"
      )
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
      json_ready([{ id: "kramdown", family: "native" }])
    )
    expect(json_ready(described_class.markdown_backend_feature_profile)).to eq(
      json_ready(feature_fixture.dig(:providers, :kramdown, :feature_profile))
    )
    expect(json_ready(described_class.markdown_plan_context)).to eq(json_ready(plan_fixture.dig(:providers, :kramdown)))
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

  it "conforms to the provider named-suite plan and manifest-report fixtures" do
    plans_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-206-markdown-provider-named-suite-plans",
        "ruby-markdown-provider-named-suite-plans.json"
      )
    )
    report_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-207-markdown-provider-manifest-report",
        "ruby-markdown-provider-manifest-report.json"
      )
    )

    contexts = plans_fixture.dig(:contexts, :kramdown)
    expect(json_ready(Ast::Merge.plan_named_conformance_suites(plans_fixture[:manifest], contexts))).to eq(
      json_ready(plans_fixture.dig(:expected_entries, :kramdown))
    )

    executions = report_fixture[:executions]
    entries = Ast::Merge.report_planned_named_conformance_suites(
      Ast::Merge.plan_named_conformance_suites(report_fixture[:manifest], report_fixture.dig(:options, :kramdown, :contexts))
    ) do |run|
      key = "#{run[:ref][:family]}:#{run[:ref][:role]}:#{run[:ref][:case]}"
      executions[key.to_sym] || executions[key] || { outcome: "failed", messages: ["missing execution"] }
    end

    expect(json_ready(Ast::Merge.report_named_conformance_suite_envelope(entries))).to eq(
      json_ready(report_fixture.dig(:expected_reports, :kramdown))
    )
  end
end
