# frozen_string_literal: true

RSpec.describe Psych::Merge do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "exposes the YAML family through the Psych provider backend" do
    family_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-95-yaml-family-feature-profile",
        "yaml-feature-profile.json"
      )
    )
    feature_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-277-yaml-provider-feature-profiles",
        "ruby-yaml-provider-feature-profiles.json"
      )
    )
    plan_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-278-yaml-provider-plan-contexts",
        "ruby-yaml-provider-plan-contexts.json"
      )
    )

    expect(json_ready(::Psych::Merge.yaml_feature_profile)).to eq(json_ready(family_fixture[:feature_profile]))
    expect(json_ready(::Psych::Merge.available_yaml_backends.map(&:to_h))).to eq(
      json_ready([{ id: "psych", family: "native" }])
    )
    expect(json_ready(TreeHaver::BackendRegistry.fetch("psych")&.to_h)).to eq(
      json_ready({ id: "psych", family: "native" })
    )
    expect(json_ready(::Psych::Merge.yaml_backend_feature_profile)).to eq(
      json_ready(feature_fixture.dig(:providers, :psych, :feature_profile))
    )
    expect(json_ready(::Psych::Merge.yaml_plan_context)).to eq(json_ready(plan_fixture.dig(:providers, :psych)))
  end

  it "conforms to the shared YAML analysis, matching, and merge fixtures" do
    parse_fixture = read_json(fixtures_root.join("yaml", "slice-96-parse", "valid-document.json"))
    parse_result = ::Psych::Merge.parse_yaml(parse_fixture[:source], parse_fixture[:dialect])
    expect(parse_result[:ok]).to eq(parse_fixture.dig(:expected, :ok))
    expect(parse_result.dig(:analysis, :root_kind)).to eq(parse_fixture.dig(:expected, :root_kind))

    structure_fixture = read_json(fixtures_root.join("yaml", "slice-97-structure", "mapping-and-sequence.json"))
    structure_result = ::Psych::Merge.parse_yaml(structure_fixture[:source], structure_fixture[:dialect])
    expect(json_ready(structure_result.dig(:analysis, :owners))).to eq(json_ready(structure_fixture.dig(:expected, :owners)))

    matching_fixture = read_json(fixtures_root.join("yaml", "slice-98-matching", "path-equality.json"))
    template = ::Psych::Merge.parse_yaml(matching_fixture[:template], "yaml")
    destination = ::Psych::Merge.parse_yaml(matching_fixture[:destination], "yaml")
    matching_result = ::Psych::Merge.match_yaml_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching_result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )
    expect(json_ready(matching_result[:unmatched_template])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_template))
    )
    expect(json_ready(matching_result[:unmatched_destination])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_destination))
    )

    merge_fixture = read_json(fixtures_root.join("yaml", "slice-99-merge", "mapping-merge.json"))
    merge_result = ::Psych::Merge.merge_yaml(merge_fixture[:template], merge_fixture[:destination], "yaml")
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))
  end

  it "rejects unsupported provider backend overrides" do
    result = ::Psych::Merge.parse_yaml("root: value\n", "yaml", backend: "kreuzberg-language-pack")
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to eq(
      [{ severity: "error", category: "unsupported_feature", message: "Unsupported YAML backend kreuzberg-language-pack." }]
    )
  end

  it "conforms to the provider named-suite plan and manifest-report fixtures" do
    plans_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-279-yaml-provider-named-suite-plans",
        "ruby-yaml-provider-named-suite-plans.json"
      )
    )
    report_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-280-yaml-provider-manifest-report",
        "ruby-yaml-provider-manifest-report.json"
      )
    )

    contexts = plans_fixture.dig(:contexts, :psych)
    expect(json_ready(Ast::Merge.plan_named_conformance_suites(plans_fixture[:manifest], contexts))).to eq(
      json_ready(plans_fixture.dig(:expected_entries, :psych))
    )

    entries = Ast::Merge.report_planned_named_conformance_suites(
      Ast::Merge.plan_named_conformance_suites(report_fixture[:manifest], report_fixture.dig(:options, :psych, :contexts))
    ) do |run|
      key = "#{run[:ref][:family]}:#{run[:ref][:role]}:#{run[:ref][:case]}"
      executions = report_fixture.dig(:executions, :psych) || report_fixture["executions"]["psych"]
      executions[key.to_sym] || executions[key] || { outcome: "failed", messages: ["missing execution"] }
    end

    expect(json_ready(Ast::Merge.report_named_conformance_suite_envelope(entries))).to eq(
      json_ready(report_fixture.dig(:expected_reports, :psych))
    )
  end
end
