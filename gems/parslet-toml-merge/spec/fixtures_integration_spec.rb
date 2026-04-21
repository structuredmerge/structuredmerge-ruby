# frozen_string_literal: true

RSpec.describe Parslet::Toml::Merge do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
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

  it "exposes the TOML family through the Parslet provider backend" do
    family_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-90-toml-family-feature-profile",
        "toml-feature-profile.json"
      )
    )
    feature_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-269-toml-provider-feature-profiles",
        "ruby-toml-provider-feature-profiles.json"
      )
    )
    plan_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-270-toml-provider-plan-contexts",
        "ruby-toml-provider-plan-contexts.json"
      )
    )

    expect(json_ready(described_class.toml_feature_profile)).to eq(json_ready(family_fixture[:feature_profile]))
    expect(json_ready(described_class.available_toml_backends.map(&:to_h))).to eq(
      json_ready([{ id: "parslet", family: "peg" }])
    )
    expect(json_ready(described_class.toml_backend_feature_profile)).to eq(
      json_ready(feature_fixture.dig(:providers, :parslet, :feature_profile))
    )
    expect(json_ready(described_class.toml_plan_context)).to eq(
      json_ready(plan_fixture.dig(:providers, :parslet))
    )
  end

  it "conforms to the shared TOML analysis, matching, and merge fixtures" do
    parse_fixture = toml_fixture("parse_valid")
    parse_result = described_class.parse_toml(parse_fixture[:source], parse_fixture[:dialect])
    expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
    expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

    structure_fixture = toml_fixture("structure")
    structure_result = described_class.parse_toml(structure_fixture[:source], structure_fixture[:dialect])
    expect(json_ready(structure_result.dig(:analysis, :owners))).to eq(
      json_ready(structure_fixture.dig(:expected, :owners))
    )

    matching_fixture = toml_fixture("matching")
    template = described_class.parse_toml(matching_fixture[:template], "toml")
    destination = described_class.parse_toml(matching_fixture[:destination], "toml")
    matching_result = described_class.match_toml_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching_result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )

    merge_fixture = toml_fixture("merge")
    merge_result = described_class.merge_toml(merge_fixture[:template], merge_fixture[:destination], "toml")
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))
  end

  it "rejects unsupported provider backend overrides" do
    result = described_class.parse_toml("title = \"x\"\n", "toml", backend: "citrus")
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to eq(
      [{ severity: "error", category: "unsupported_feature", message: "Unsupported TOML backend citrus." }]
    )
  end

  it "conforms to the provider named-suite plan and manifest-report fixtures" do
    plans_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-271-toml-provider-named-suite-plans",
        "ruby-toml-provider-named-suite-plans.json"
      )
    )
    report_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-272-toml-provider-manifest-report",
        "ruby-toml-provider-manifest-report.json"
      )
    )

    contexts = plans_fixture.dig(:contexts, :parslet)
    expect(json_ready(Ast::Merge.plan_named_conformance_suites(plans_fixture[:manifest], contexts))).to eq(
      json_ready(plans_fixture.dig(:expected_entries, :parslet))
    )

    entries = Ast::Merge.report_planned_named_conformance_suites(
      Ast::Merge.plan_named_conformance_suites(report_fixture[:manifest], report_fixture.dig(:options, :parslet, :contexts))
    ) do |run|
      key = "#{run[:ref][:family]}:#{run[:ref][:role]}:#{run[:ref][:case]}"
      executions = report_fixture.dig(:executions, :parslet) || report_fixture["executions"]["parslet"]
      executions[key.to_sym] || executions[key] || { outcome: "failed", messages: ["missing execution"] }
    end

    expect(json_ready(Ast::Merge.report_named_conformance_suite_envelope(entries))).to eq(
      json_ready(report_fixture.dig(:expected_reports, :parslet))
    )
  end
end
