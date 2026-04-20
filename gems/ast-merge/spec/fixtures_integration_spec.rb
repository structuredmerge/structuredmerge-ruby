# frozen_string_literal: true

require "pathname"

RSpec.describe Ast::Merge do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join("conformance", "slice-24-manifest", "family-feature-profiles.json"))
  end

  def diagnostics_fixture(role)
    path = described_class.conformance_fixture_path(manifest, "diagnostics", role)
    raise "missing diagnostics fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    described_class.json_ready(value)
  end

  def execution_key(ref)
    "#{ref[:family]}:#{ref[:role]}:#{ref[:case]}"
  end

  def execute_from(executions)
    lambda do |run|
      key = execution_key(run[:ref])
      executions[key.to_sym] || executions[key] || { outcome: "failed", messages: ["missing execution"] }
    end
  end

  it "conforms to the shared diagnostic vocabulary fixture" do
    fixture = diagnostics_fixture("diagnostic_vocabulary")

    expect(%w[info warning error]).to eq(fixture[:severities])
    expect(%w[
      parse_error
      destination_parse_error
      unsupported_feature
      fallback_applied
      ambiguity
      assumed_default
      configuration_error
      replay_rejected
    ]).to eq(fixture[:categories])
  end

  it "conforms to the shared policy vocabulary and reporting fixtures" do
    policy_fixture = diagnostics_fixture("policy_vocabulary")
    reporting_fixture = diagnostics_fixture("policy_reporting")

    policies = [
      { surface: "fallback", name: "trailing_comma_destination_fallback" },
      { surface: "array", name: "destination_wins_array" }
    ]

    expect(%w[fallback array]).to eq(policy_fixture[:surfaces])
    expect(json_ready(policies)).to eq(json_ready(policy_fixture[:policies]))
    expect(json_ready(policies.reverse)).to eq(json_ready(reporting_fixture[:merge_policies]))
  end

  it "resolves canonical manifest paths, including widened source-family entries" do
    expect(described_class.conformance_family_feature_profile_path(manifest, "json")).to eq(
      %w[diagnostics slice-21-family-feature-profile json-feature-profile.json]
    )
    expect(described_class.conformance_fixture_path(manifest, "text", "analysis")).to eq(
      %w[text slice-03-analysis whitespace-and-blocks.json]
    )
    expect(described_class.conformance_family_feature_profile_path(manifest, "typescript")).to eq(
      %w[diagnostics slice-101-typescript-family-feature-profile typescript-feature-profile.json]
    )
    expect(described_class.conformance_fixture_path(manifest, "go", "analysis")).to eq(
      %w[go slice-110-analysis module-owners.json]
    )
  end

  it "conforms to the runner shape and summary fixtures" do
    runner_fixture = diagnostics_fixture("runner_shape")
    summary_fixture = diagnostics_fixture("runner_summary")

    case_ref = { family: "json", role: "tree_sitter_adapter", case: "valid_strict_json" }
    result = { ref: case_ref, outcome: "passed", messages: [] }

    expect(json_ready(case_ref)).to eq(json_ready(runner_fixture[:case_ref]))
    expect(json_ready(result)).to eq(json_ready(runner_fixture[:result]))

    summary = described_class.summarize_conformance_results(summary_fixture[:results])
    expect(json_ready(summary)).to eq(json_ready(summary_fixture[:summary]))
  end

  it "conforms to the selection fixtures" do
    %w[capability_selection backend_selection].each do |role|
      fixture = diagnostics_fixture(role)

      fixture[:cases].each do |test_case|
        selection = described_class.select_conformance_case(
          test_case[:ref],
          test_case[:requirements],
          test_case[:family_profile],
          test_case[:feature_profile]
        )
        expect(json_ready(selection.slice(:status, :messages))).to eq(json_ready(test_case[:expected]))
      end
    end
  end

  it "conforms to the case and suite runner fixtures" do
    case_fixture = diagnostics_fixture("case_runner")
    suite_fixture = diagnostics_fixture("suite_runner")

    case_fixture[:cases].each do |test_case|
      result = described_class.run_conformance_case(test_case[:run], &->(_run) { test_case[:execution] })
      expect(json_ready(result)).to eq(json_ready(test_case[:expected]))
    end

    suite_results = described_class.run_conformance_suite(suite_fixture[:cases], &execute_from(suite_fixture[:executions]))
    expect(json_ready(suite_results)).to eq(json_ready(suite_fixture[:expected_results]))
  end

  it "conforms to the suite plan and report fixtures" do
    suite_plan_fixture = diagnostics_fixture("suite_plan")
    planned_runner_fixture = diagnostics_fixture("planned_suite_runner")
    planned_report_fixture = diagnostics_fixture("planned_suite_report")
    suite_report_fixture = diagnostics_fixture("suite_report")
    manifest_requirements_fixture = diagnostics_fixture("manifest_requirements")
    backend_requirements_fixture = diagnostics_fixture("manifest_backend_requirements")
    backend_report_fixture = diagnostics_fixture("manifest_backend_report")

    plan = described_class.plan_conformance_suite(
      manifest,
      suite_plan_fixture[:family],
      suite_plan_fixture[:roles],
      suite_plan_fixture[:family_profile],
      suite_plan_fixture[:feature_profile]
    )
    expect(json_ready(plan)).to eq(json_ready(suite_plan_fixture[:expected]))

    planned_results = described_class.run_planned_conformance_suite(planned_runner_fixture[:plan], &execute_from(planned_runner_fixture[:executions]))
    expect(json_ready(planned_results)).to eq(json_ready(planned_runner_fixture[:expected_results]))

    report = described_class.report_planned_conformance_suite(planned_report_fixture[:plan], &execute_from(planned_report_fixture[:executions]))
    expect(json_ready(report)).to eq(json_ready(planned_report_fixture[:expected_report]))

    suite_report = described_class.report_conformance_suite(suite_report_fixture[:results])
    expect(json_ready(suite_report)).to eq(json_ready(suite_report_fixture[:report]))

    requirements_plan = described_class.plan_conformance_suite(
      manifest,
      manifest_requirements_fixture[:family],
      manifest_requirements_fixture[:roles],
      manifest_requirements_fixture[:family_profile]
    )
    actual_requirements = requirements_plan[:entries].to_h { |entry| [entry[:ref][:role], entry[:run][:requirements]] }
    expect(json_ready(actual_requirements)).to eq(json_ready(manifest_requirements_fixture[:expected_requirements]))

    backend_plan = described_class.plan_conformance_suite(
      backend_requirements_fixture[:manifest],
      backend_requirements_fixture[:family],
      backend_requirements_fixture[:roles],
      backend_requirements_fixture[:family_profile],
      backend_requirements_fixture[:feature_profile]
    )
    expect(json_ready(backend_plan)).to eq(json_ready(backend_requirements_fixture[:expected]))

    backend_report = described_class.report_planned_conformance_suite(
      backend_report_fixture[:expected_report][:results] ? described_class.plan_conformance_suite(
        backend_report_fixture[:manifest],
        backend_report_fixture[:family],
        backend_report_fixture[:roles],
        backend_report_fixture[:family_profile],
        backend_report_fixture[:feature_profile]
      ) : {},
      &->(_run) { { outcome: "failed", messages: ["unexpected execution"] } }
    )
    expect(json_ready(backend_report)).to eq(json_ready(backend_report_fixture[:expected_report]))
  end

  it "conforms to named suite planning and reporting fixtures" do
    suite_definitions_fixture = diagnostics_fixture("suite_definitions")
    named_suite_report_fixture = diagnostics_fixture("named_suite_report")
    suite_names_fixture = diagnostics_fixture("suite_names")
    named_suite_entry_fixture = diagnostics_fixture("named_suite_entry")
    named_suite_plan_entry_fixture = diagnostics_fixture("named_suite_plan_entry")
    family_plan_context_fixture = diagnostics_fixture("family_plan_context")
    named_suite_plans_fixture = diagnostics_fixture("named_suite_plans")
    named_suite_results_fixture = diagnostics_fixture("named_suite_results")
    named_suite_runner_entries_fixture = diagnostics_fixture("named_suite_runner_entries")
    named_suite_report_entries_fixture = diagnostics_fixture("named_suite_report_entries")
    named_suite_summary_fixture = diagnostics_fixture("named_suite_summary")
    named_suite_report_envelope_fixture = diagnostics_fixture("named_suite_report_envelope")
    named_suite_report_manifest_fixture = diagnostics_fixture("named_suite_report_manifest")

    expect(json_ready(described_class.conformance_suite_definition(manifest, suite_definitions_fixture[:suite_name]))).to eq(
      json_ready(suite_definitions_fixture[:expected])
    )
    expect(described_class.conformance_suite_names(manifest)).to eq(suite_names_fixture[:suite_names])
    expect(json_ready(named_suite_plan_entry_fixture[:context])).to eq(json_ready(family_plan_context_fixture[:context]))

    named_entry = described_class.report_named_conformance_suite_entry(
      manifest,
      named_suite_entry_fixture[:suite_name],
      named_suite_entry_fixture[:family_profile],
      {
        backend: "kreuzberg-language-pack",
        supports_dialects: false,
        supported_policies: [{ surface: "array", name: "destination_wins_array" }]
      },
      &execute_from(named_suite_entry_fixture[:executions])
    )
    expect(json_ready(named_entry)).to eq(json_ready(named_suite_entry_fixture[:expected_entry]))

    named_plan_entry = described_class.plan_named_conformance_suite_entry(
      manifest,
      named_suite_plan_entry_fixture[:suite_name],
      named_suite_plan_entry_fixture[:context]
    )
    expect(json_ready(named_plan_entry)).to eq(json_ready(named_suite_plan_entry_fixture[:expected_entry]))

    named_plans = described_class.plan_named_conformance_suites(
      manifest,
      named_suite_plans_fixture[:contexts]
    )
    expect(json_ready(named_plans)).to eq(json_ready(named_suite_plans_fixture[:expected_entries]))

    named_results = described_class.run_named_conformance_suite_entry(
      manifest,
      named_suite_results_fixture[:suite_name],
      named_suite_results_fixture[:family_profile],
      {
        backend: "kreuzberg-language-pack",
        supports_dialects: false,
        supported_policies: [{ surface: "array", name: "destination_wins_array" }]
      },
      &execute_from(named_suite_results_fixture[:executions])
    )
    expect(json_ready(named_results)).to eq(json_ready(named_suite_results_fixture[:expected_entry]))

    runner_entries = described_class.run_planned_named_conformance_suites(
      described_class.plan_named_conformance_suites(manifest, named_suite_runner_entries_fixture[:contexts]),
      &execute_from(named_suite_runner_entries_fixture[:executions])
    )
    expect(json_ready(runner_entries)).to eq(json_ready(named_suite_runner_entries_fixture[:expected_entries]))

    report = described_class.report_named_conformance_suite(
      manifest,
      named_suite_report_fixture[:suite_name],
      named_suite_report_fixture[:family_profile],
      {
        backend: "kreuzberg-language-pack",
        supports_dialects: false,
        supported_policies: [{ surface: "array", name: "destination_wins_array" }]
      },
      &execute_from(named_suite_report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(named_suite_report_fixture[:expected_report]))

    report_entries = described_class.report_planned_named_conformance_suites(
      described_class.plan_named_conformance_suites(manifest, named_suite_report_entries_fixture[:contexts]),
      &execute_from(named_suite_report_entries_fixture[:executions])
    )
    expect(json_ready(report_entries)).to eq(json_ready(named_suite_report_entries_fixture[:expected_entries]))

    summary = described_class.summarize_named_conformance_suite_reports(named_suite_summary_fixture[:entries])
    expect(json_ready(summary)).to eq(json_ready(named_suite_summary_fixture[:expected_summary]))

    envelope = described_class.report_named_conformance_suite_envelope(named_suite_report_envelope_fixture[:entries])
    expect(json_ready(envelope)).to eq(json_ready(named_suite_report_envelope_fixture[:expected_report]))

    manifest_report = described_class.report_named_conformance_suite_manifest(
      manifest,
      named_suite_report_manifest_fixture[:contexts],
      &execute_from(named_suite_report_manifest_fixture[:executions])
    )
    expect(json_ready(manifest_report)).to eq(json_ready(named_suite_report_manifest_fixture[:expected_report]))
  end

  it "conforms to manifest planning, defaulting, and review host fixtures" do
    default_context_fixture = diagnostics_fixture("default_family_context")
    explicit_mode_fixture = diagnostics_fixture("explicit_family_context_mode")
    missing_roles_fixture = diagnostics_fixture("missing_suite_roles")
    manifest_report_fixture = diagnostics_fixture("conformance_manifest_report")
    host_hints_fixture = diagnostics_fixture("review_host_hints")
    request_ids_fixture = diagnostics_fixture("review_request_ids")
    family_request_fixture = diagnostics_fixture("family_context_review_request")

    context, diagnostics = described_class.resolve_conformance_family_context(
      default_context_fixture[:family],
      family_profiles: { default_context_fixture[:family] => default_context_fixture[:family_profile] }
    )
    expect(json_ready(context)).to eq(json_ready(default_context_fixture[:expected_context]))
    expect(json_ready(diagnostics.first)).to eq(json_ready(default_context_fixture[:expected_diagnostic]))

    explicit_family = explicit_mode_fixture.dig(:manifest, :suites)&.values&.first&.dig(:family)
    missing_context, explicit_diagnostics = described_class.resolve_conformance_family_context(
      explicit_family,
      explicit_mode_fixture[:options]
    )
    expect(missing_context).to be_nil
    expect(json_ready(explicit_diagnostics.first)).to eq(json_ready(explicit_mode_fixture[:expected_diagnostic]))

    missing_roles_plan = described_class.plan_named_conformance_suites_with_diagnostics(
      missing_roles_fixture[:manifest],
      missing_roles_fixture[:options]
    )
    expect(json_ready(missing_roles_plan[:diagnostics].first)).to eq(json_ready(missing_roles_fixture[:expected_diagnostic]))

    manifest_report = described_class.report_conformance_manifest(
      manifest_report_fixture[:manifest],
      manifest_report_fixture[:options],
      &execute_from(manifest_report_fixture[:executions])
    )
    expect(json_ready(manifest_report)).to eq(json_ready(manifest_report_fixture[:expected_report]))

    expect(json_ready(described_class.conformance_review_host_hints(host_hints_fixture[:options]))).to eq(json_ready(host_hints_fixture[:expected_hints]))
    expect(described_class.conformance_manifest_review_request_ids(request_ids_fixture[:manifest], request_ids_fixture[:options])).to eq(request_ids_fixture[:expected_request_ids])

    _context, _diagnostics, requests, _decisions = described_class.review_conformance_family_context(
      family_request_fixture[:family],
      family_request_fixture[:options]
    )
    expect(json_ready(requests.first)).to eq(json_ready(family_request_fixture[:expected_request]))
  end

  it "conforms to review-state, replay, and explicit-context fixtures" do
    review_state_fixture = diagnostics_fixture("conformance_manifest_review_state")
    reviewed_default_fixture = diagnostics_fixture("reviewed_default_context")
    replay_compatibility_fixture = diagnostics_fixture("review_replay_compatibility")
    replay_rejection_fixture = diagnostics_fixture("review_replay_rejection")
    stale_decision_fixture = diagnostics_fixture("stale_review_decision")
    replay_bundle_fixture = diagnostics_fixture("review_replay_bundle")
    replay_bundle_application_fixture = diagnostics_fixture("review_replay_bundle_application")
    review_state_roundtrip_fixture = diagnostics_fixture("review_state_json_roundtrip")
    replay_bundle_roundtrip_fixture = diagnostics_fixture("review_replay_bundle_json_roundtrip")
    review_state_envelope_fixture = diagnostics_fixture("review_state_envelope")
    replay_bundle_envelope_fixture = diagnostics_fixture("review_replay_bundle_envelope")
    review_state_envelope_rejection_fixture = diagnostics_fixture("review_state_envelope_rejection")
    replay_bundle_envelope_rejection_fixture = diagnostics_fixture("review_replay_bundle_envelope_rejection")
    review_proposal_fixture = diagnostics_fixture("family_context_review_proposal")
    explicit_decision_fixture = diagnostics_fixture("family_context_explicit_review_decision")
    explicit_bundle_fixture = diagnostics_fixture("explicit_review_replay_bundle_application")
    missing_context_fixture = diagnostics_fixture("explicit_review_decision_missing_context")
    family_mismatch_fixture = diagnostics_fixture("explicit_review_decision_family_mismatch")

    state = described_class.review_conformance_manifest(
      review_state_fixture[:manifest],
      review_state_fixture[:options],
      &execute_from(review_state_fixture[:executions])
    )
    expect(json_ready(state)).to eq(json_ready(review_state_fixture[:expected_state]))

    reviewed_state = described_class.review_conformance_manifest(
      reviewed_default_fixture[:manifest],
      reviewed_default_fixture[:options],
      &execute_from(reviewed_default_fixture[:executions])
    )
    expect(json_ready(reviewed_state)).to eq(json_ready(reviewed_default_fixture[:expected_state]))

    expect(
      described_class.review_replay_context_compatible(
        replay_compatibility_fixture[:current_context],
        replay_compatibility_fixture[:compatible_context]
      )
    ).to eq(true)
    expect(
      described_class.review_replay_context_compatible(
        replay_compatibility_fixture[:current_context],
        replay_compatibility_fixture[:incompatible_context]
      )
    ).to eq(false)

    rejected_state = described_class.review_conformance_manifest(
      replay_rejection_fixture[:manifest],
      replay_rejection_fixture[:options],
      &execute_from(replay_rejection_fixture[:executions])
    )
    expect(json_ready(rejected_state)).to eq(json_ready(replay_rejection_fixture[:expected_state]))

    stale_state = described_class.review_conformance_manifest(
      stale_decision_fixture[:manifest],
      stale_decision_fixture[:options],
      &execute_from(stale_decision_fixture[:executions])
    )
    expect(json_ready(stale_state)).to eq(json_ready(stale_decision_fixture[:expected_state]))

    replay_context, replay_decisions = described_class.review_replay_bundle_inputs(review_replay_bundle: replay_bundle_fixture[:replay_bundle])
    expect(json_ready(replay_context)).to eq(json_ready(replay_bundle_fixture[:replay_bundle][:replay_context]))
    expect(json_ready(replay_decisions)).to eq(json_ready(replay_bundle_fixture[:replay_bundle][:decisions]))

    replay_applied = described_class.review_conformance_manifest(
      replay_bundle_application_fixture[:manifest],
      replay_bundle_application_fixture[:options],
      &execute_from(replay_bundle_application_fixture[:executions])
    )
    expect(json_ready(replay_applied)).to eq(json_ready(replay_bundle_application_fixture[:expected_state]))

    review_state_envelope = described_class.conformance_manifest_review_state_envelope(review_state_roundtrip_fixture[:state])
    roundtrip_state, roundtrip_error = described_class.import_conformance_manifest_review_state_envelope(review_state_envelope)
    expect(roundtrip_error).to be_nil
    expect(json_ready(roundtrip_state)).to eq(json_ready(review_state_roundtrip_fixture[:state]))

    replay_bundle_envelope = described_class.review_replay_bundle_envelope(replay_bundle_roundtrip_fixture[:replay_bundle])
    roundtrip_bundle, bundle_error = described_class.import_review_replay_bundle_envelope(replay_bundle_envelope)
    expect(bundle_error).to be_nil
    expect(json_ready(roundtrip_bundle)).to eq(json_ready(replay_bundle_roundtrip_fixture[:replay_bundle]))

    expect(json_ready(described_class.conformance_manifest_review_state_envelope(review_state_envelope_fixture[:state]))).to eq(
      json_ready(review_state_envelope_fixture[:expected_envelope])
    )
    expect(json_ready(described_class.review_replay_bundle_envelope(replay_bundle_envelope_fixture[:replay_bundle]))).to eq(
      json_ready(replay_bundle_envelope_fixture[:expected_envelope])
    )

    review_state_envelope_rejection_fixture[:cases].each do |test_case|
      _state, envelope_error = described_class.import_conformance_manifest_review_state_envelope(test_case[:envelope])
      expect(json_ready(envelope_error)).to eq(json_ready(test_case[:expected_error]))
    end

    replay_bundle_envelope_rejection_fixture[:cases].each do |test_case|
      _bundle, bundle_rejection_error = described_class.import_review_replay_bundle_envelope(test_case[:envelope])
      expect(json_ready(bundle_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    _proposal_context, _proposal_diagnostics, proposal_requests, = described_class.review_conformance_family_context(
      review_proposal_fixture[:family],
      review_proposal_fixture[:options]
    )
    expect(json_ready(proposal_requests.first)).to eq(json_ready(review_proposal_fixture[:expected_request]))

    explicit_context, explicit_diagnostics, explicit_requests, explicit_decisions = described_class.review_conformance_family_context(
      explicit_decision_fixture[:family],
      explicit_decision_fixture[:options]
    )
    expect(json_ready(explicit_context)).to eq(json_ready(explicit_decision_fixture[:expected_context]))
    expect(explicit_diagnostics).to eq([])
    expect(explicit_requests).to eq([])
    expect(json_ready(explicit_decisions)).to eq(json_ready(explicit_decision_fixture[:expected_applied_decisions]))

    explicit_applied = described_class.review_conformance_manifest(
      explicit_bundle_fixture[:manifest],
      explicit_bundle_fixture[:options],
      &execute_from(explicit_bundle_fixture[:executions])
    )
    expect(json_ready(explicit_applied)).to eq(json_ready(explicit_bundle_fixture[:expected_state]))

    _missing_context, missing_diagnostics, missing_requests, = described_class.review_conformance_family_context(
      missing_context_fixture[:family],
      missing_context_fixture[:options]
    )
    expect(json_ready(missing_diagnostics.first)).to eq(json_ready(missing_context_fixture[:expected_diagnostic]))
    expect(json_ready(missing_requests.first)).to eq(json_ready(missing_context_fixture[:expected_request]))

    _mismatch_context, mismatch_diagnostics, mismatch_requests, = described_class.review_conformance_family_context(
      family_mismatch_fixture[:family],
      family_mismatch_fixture[:options]
    )
    expect(json_ready(mismatch_diagnostics.first)).to eq(json_ready(family_mismatch_fixture[:expected_diagnostic]))
    expect(json_ready(mismatch_requests.first)).to eq(json_ready(family_mismatch_fixture[:expected_request]))
  end

  it "conforms to the widened source-family manifest and report fixtures" do
    source_manifest = read_json(fixtures_root.join("conformance", "slice-124-source-family-manifest", "source-family-manifest.json"))
    source_report_fixture = diagnostics_fixture("manifest_backend_report")
    mixed_source_report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-128-source-family-manifest-report", "source-manifest-report.json")
    )

    expect(described_class.conformance_family_feature_profile_path(source_manifest, "typescript")).to eq(
      %w[diagnostics slice-101-typescript-family-feature-profile typescript-feature-profile.json]
    )
    expect(described_class.conformance_fixture_path(source_manifest, "rust", "merge")).to eq(
      %w[rust slice-108-merge module-merge.json]
    )

    report = described_class.report_conformance_manifest(
      mixed_source_report_fixture[:manifest],
      mixed_source_report_fixture[:options],
      &execute_from(mixed_source_report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(mixed_source_report_fixture[:expected_report]))
    expect(source_report_fixture).not_to be_nil
  end

  it "conforms to the TOML family suite-definition, named-suite plan, and manifest report fixtures" do
    suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-138-toml-family-suite-definitions", "toml-suite-definitions.json")
    )
    expect(described_class.conformance_suite_names(suite_fixture[:manifest])).to eq(suite_fixture[:suite_names])
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest], "toml_portable")).to eq(
      suite_fixture.dig(:definitions, :toml_portable)
    )

    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-139-toml-family-named-suite-plans", "ruby-toml-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-140-toml-family-manifest-report", "ruby-toml-manifest-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it "conforms to the YAML family suite-definition, named-suite plan, and manifest report fixtures" do
    suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-144-yaml-family-suite-definitions", "yaml-suite-definitions.json")
    )
    expect(described_class.conformance_suite_names(suite_fixture[:manifest])).to eq(suite_fixture[:suite_names])
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest], "yaml_portable")).to eq(
      suite_fixture.dig(:definitions, :yaml_portable)
    )

    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-145-yaml-family-named-suite-plans", "ruby-yaml-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-146-yaml-family-manifest-report", "ruby-yaml-manifest-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it "conforms to the backend-aware YAML family named-suite plan and manifest report fixtures" do
    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-173-yaml-family-backend-named-suite-plans", "ruby-yaml-backend-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-174-yaml-family-backend-manifest-report", "ruby-yaml-backend-manifest-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it "conforms to the aggregate config-family manifest, plan, and report fixtures" do
    manifest_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-148-config-family-aggregate-manifest", "config-family-aggregate.json")
    )
    expect(described_class.conformance_suite_names(manifest_fixture[:manifest])).to eq(manifest_fixture[:suite_names])

    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-149-config-family-aggregate-suite-plans", "config-family-aggregate-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-150-config-family-aggregate-manifest-report",
        "config-family-aggregate-manifest-report.json"
      )
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it "conforms to the aggregate config-family review-state fixtures" do
    %w[
      slice-151-config-family-aggregate-review-state/config-family-aggregate-review-state.json
      slice-152-config-family-aggregate-reviewed-default/config-family-aggregate-reviewed-default.json
      slice-153-config-family-aggregate-replay-application/config-family-aggregate-replay-application.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join("diagnostics", relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it "conforms to the canonical stable-suite planning and review fixtures" do
    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-155-canonical-stable-suite-plans", "canonical-stable-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-156-canonical-stable-suite-report", "canonical-stable-suite-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

    review_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-157-canonical-stable-suite-review-state", "canonical-stable-suite-review-state.json")
    )
    state = described_class.review_conformance_manifest(
      review_fixture[:manifest],
      review_fixture[:options],
      &execute_from(review_fixture[:executions])
    )
    expect(json_ready(state)).to eq(json_ready(review_fixture[:expected_state]))
  end

  it "conforms to the canonical stable-suite backend fixtures" do
    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-175-canonical-stable-suite-backend-plans", "ruby-canonical-stable-suite-backend-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-176-canonical-stable-suite-backend-report", "ruby-canonical-stable-suite-backend-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

    review_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-177-canonical-stable-suite-backend-review-state", "ruby-canonical-stable-suite-backend-review-state.json")
    )
    state = described_class.review_conformance_manifest(
      review_fixture[:manifest],
      review_fixture[:options],
      &execute_from(review_fixture[:executions])
    )
    expect(json_ready(state)).to eq(json_ready(review_fixture[:expected_state]))
  end

  it "conforms to the source-family review-state fixtures" do
    %w[
      slice-158-source-family-review-state/source-family-review-state.json
      slice-159-source-family-reviewed-default/source-family-reviewed-default.json
      slice-160-source-family-replay-application/source-family-replay-application.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join("diagnostics", relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it "conforms to the canonical widened-suite fixtures" do
    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-162-canonical-widened-suite-plans", "canonical-widened-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-163-canonical-widened-suite-report", "canonical-widened-suite-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

    %w[
      slice-164-canonical-widened-suite-review-state/canonical-widened-suite-review-state.json
      slice-165-canonical-widened-suite-reviewed-default/canonical-widened-suite-reviewed-default.json
      slice-166-canonical-widened-suite-replay-application/canonical-widened-suite-replay-application.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join("diagnostics", relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it "conforms to the canonical widened-suite backend fixtures" do
    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-178-canonical-widened-suite-backend-plans", "ruby-canonical-widened-suite-backend-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-179-canonical-widened-suite-backend-report", "ruby-canonical-widened-suite-backend-report.json")
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

    %w[
      slice-180-canonical-widened-suite-backend-review-state/ruby-canonical-widened-suite-backend-review-state.json
      slice-181-canonical-widened-suite-backend-reviewed-default/ruby-canonical-widened-suite-backend-reviewed-default.json
      slice-182-canonical-widened-suite-backend-replay-application/ruby-canonical-widened-suite-backend-replay-application.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join("diagnostics", relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it "conforms to the backend-sensitive aggregate fixtures" do
    plans_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-167-backend-sensitive-aggregate-suite-plans",
        "backend-sensitive-aggregate-suite-plans.json"
      )
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    %w[
      slice-168-backend-sensitive-aggregate-tree-sitter-report/backend-sensitive-aggregate-tree-sitter-report.json
      slice-169-backend-sensitive-aggregate-native-report/backend-sensitive-aggregate-native-report.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join("diagnostics", relative_path))
      report = described_class.report_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(report)).to eq(json_ready(fixture[:expected_report]))
    end
  end
end
