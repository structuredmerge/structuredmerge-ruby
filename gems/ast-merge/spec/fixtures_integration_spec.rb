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

  def read_relative_file_tree(root)
    root = root.expand_path
    root.find.each_with_object({}) do |path, files|
      next if path.directory?

      rel = path.relative_path_from(root).to_s
      files[rel] = path.read
    end
  end

  def repo_temp_dir
    root = Pathname(__dir__).join("..", "..", "tmp").expand_path
    root.mkpath
    path = root.join("ast-merge-#{Process.pid}-#{Time.now.to_f.to_s.delete(".")}")
    path.mkpath
    path
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

  it "conforms to the slice-22 shared family feature profile fixture" do
    fixture = diagnostics_fixture("shared_family_feature_profile")

    feature_profile = {
      family: "example",
      supported_dialects: %w[alpha beta],
      supported_policies: [{ surface: "array", name: "destination_wins_array" }]
    }

    expect(json_ready(feature_profile)).to eq(json_ready(fixture[:feature_profile]))
  end

  it "conforms to the template source path mapping fixture" do
    fixture = diagnostics_fixture("template_source_path_mapping")

    fixture[:cases].each do |test_case|
      expect(described_class.normalize_template_source_path(test_case[:template_source_path])).to eq(
        test_case[:expected_destination_path]
      )
    end
  end

  it "conforms to the template target classification fixture" do
    fixture = diagnostics_fixture("template_target_classification")

    fixture[:cases].each do |test_case|
      expect(json_ready(described_class.classify_template_target_path(test_case[:destination_path]))).to eq(
        json_ready(test_case[:expected])
      )
    end
  end

  it "conforms to the template destination mapping fixture" do
    fixture = diagnostics_fixture("template_destination_mapping")

    fixture[:cases].each do |test_case|
      expect(
        described_class.resolve_template_destination_path(
          test_case[:logical_destination_path],
          test_case[:context]
        )
      ).to eq(test_case[:expected_destination_path])
    end
  end

  it "conforms to the template strategy selection fixture" do
    fixture = diagnostics_fixture("template_strategy_selection")

    fixture[:cases].each do |test_case|
      expect(
        described_class.select_template_strategy(
          test_case[:destination_path],
          test_case[:default_strategy],
          test_case[:overrides]
        )
      ).to eq(test_case[:expected_strategy])
    end
  end

  it "conforms to the template token keys fixture" do
    fixture = diagnostics_fixture("template_token_keys")

    fixture[:cases].each do |test_case|
      expect(
        described_class.template_token_keys(
          test_case[:content],
          test_case[:config]
        )
      ).to eq(test_case[:expected_token_keys])
    end
  end

  it "conforms to the template entry plan fixture" do
    fixture = diagnostics_fixture("template_entry_plan")

    expect(
      json_ready(
        described_class.plan_template_entries(
          fixture[:template_source_paths],
          fixture[:context],
          fixture[:default_strategy],
          fixture[:overrides]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it "conforms to the template entry token state fixture" do
    fixture = diagnostics_fixture("template_entry_token_state")

    expect(
      json_ready(
        described_class.enrich_template_plan_entries_with_token_state(
          fixture[:planned_entries],
          fixture[:template_contents],
          fixture[:replacements]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it "conforms to the template entry prepared content fixture" do
    fixture = diagnostics_fixture("template_entry_prepared_content")

    expect(
      json_ready(
        described_class.prepare_template_entries(
          fixture[:planned_entries],
          fixture[:template_contents],
          fixture[:replacements]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it "conforms to the template execution plan fixture" do
    fixture = diagnostics_fixture("template_execution_plan")

    expect(
      json_ready(
        described_class.plan_template_execution(
          fixture[:prepared_entries],
          fixture[:destination_contents]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it "conforms to the mini template tree plan fixture" do
    fixture = diagnostics_fixture("mini_template_tree_plan")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_plan")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    expect(
      json_ready(
        described_class.plan_template_tree_execution(
          template_contents.keys.sort,
          template_contents,
          destination_contents.keys.sort,
          destination_contents,
          fixture[:context],
          fixture[:default_strategy],
          fixture[:overrides],
          fixture[:replacements]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it "conforms to the mini template tree preview fixture" do
    plan_fixture = diagnostics_fixture("mini_template_tree_plan")
    preview_fixture = diagnostics_fixture("mini_template_tree_preview")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_plan")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    execution_plan = described_class.plan_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents.keys.sort,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    )

    expect(json_ready(described_class.preview_template_execution(execution_plan))).to eq(
      json_ready(preview_fixture[:expected_preview])
    )
  end

  it "conforms to the mini template tree apply fixture" do
    plan_fixture = diagnostics_fixture("mini_template_tree_plan")
    apply_fixture = diagnostics_fixture("mini_template_tree_apply")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_plan")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    execution_plan = described_class.plan_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents.keys.sort,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    )

    apply_result = described_class.apply_template_execution(execution_plan) do |entry|
      destination_path = entry[:destination_path] || entry["destination_path"]
      apply_fixture[:merge_results][destination_path] || apply_fixture[:merge_results][destination_path.to_sym]
    end

    expect(json_ready(apply_result)).to eq(json_ready(apply_fixture[:expected_result]))
  end

  it "conforms to the mini template tree convergence fixture" do
    plan_fixture = diagnostics_fixture("mini_template_tree_plan")
    apply_fixture = diagnostics_fixture("mini_template_tree_apply")
    convergence_fixture = diagnostics_fixture("mini_template_tree_convergence")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_plan")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    execution_plan = described_class.plan_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents.keys.sort,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    )
    apply_result = described_class.apply_template_execution(execution_plan) do |entry|
      destination_path = entry[:destination_path] || entry["destination_path"]
      apply_fixture[:merge_results][destination_path] || apply_fixture[:merge_results][destination_path.to_sym]
    end

    expect(
      json_ready(
        described_class.evaluate_template_tree_convergence(
          template_contents.keys.sort,
          template_contents,
          apply_result[:result_files],
          plan_fixture[:context],
          plan_fixture[:default_strategy],
          plan_fixture[:overrides],
          convergence_fixture[:replacements]
        )
      )
    ).to eq(json_ready(convergence_fixture[:expected]))
  end

  it "conforms to the mini template tree run fixture" do
    plan_fixture = diagnostics_fixture("mini_template_tree_plan")
    run_fixture = diagnostics_fixture("mini_template_tree_run")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_plan")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    ) do |entry|
      destination_path = entry[:destination_path] || entry["destination_path"]
      run_fixture[:merge_results][destination_path] || run_fixture[:merge_results][destination_path.to_sym]
    end

    expect(json_ready(run_result)).to eq(json_ready(run_fixture[:expected]))
  end

  it "conforms to the mini template tree run report fixture" do
    plan_fixture = diagnostics_fixture("mini_template_tree_plan")
    run_fixture = diagnostics_fixture("mini_template_tree_run")
    report_fixture = diagnostics_fixture("mini_template_tree_run_report")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_plan")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    ) do |entry|
      destination_path = entry[:destination_path] || entry["destination_path"]
      run_fixture[:merge_results][destination_path] || run_fixture[:merge_results][destination_path.to_sym]
    end

    expect(json_ready(described_class.report_template_tree_run(run_result))).to eq(json_ready(report_fixture[:expected]))
  end

  it "conforms to the mini template tree family merge callback fixture" do
    fixture = diagnostics_fixture("mini_template_tree_family_merge_callback")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_family_merge_callback")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      family = entry.dig(:classification, :family) || entry.dig("classification", "family")
      case family
      when "markdown"
        Markdown::Merge.merge_markdown(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "markdown"
        )
      else
        {
          ok: false,
          diagnostics: [{ severity: "error", category: "configuration_error", message: "missing family merge adapter for #{family}" }],
          policies: []
        }
      end
    end

    expect(json_ready(run_result)).to eq(json_ready(fixture[:expected]))
  end

  it "conforms to the mini template tree multi-family merge callback fixture" do
    fixture = diagnostics_fixture("mini_template_tree_multi_family_merge_callback")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_multi_family_merge_callback")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      family = entry.dig(:classification, :family) || entry.dig("classification", "family")
      case family
      when "markdown"
        Markdown::Merge.merge_markdown(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "markdown"
        )
      when "toml"
        Toml::Merge.merge_toml(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "toml"
        )
      when "ruby"
        Ruby::Merge.merge_ruby(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "ruby"
        )
      else
        {
          ok: false,
          diagnostics: [{ severity: "error", category: "configuration_error", message: "missing family merge adapter for #{family}" }],
          policies: []
        }
      end
    end

    expect(json_ready(run_result)).to eq(json_ready(fixture[:expected]))
  end

  it "conforms to the mini template tree multi-family run report fixture" do
    fixture = diagnostics_fixture("mini_template_tree_multi_family_merge_callback")
    report_fixture = diagnostics_fixture("mini_template_tree_multi_family_run_report")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_multi_family_merge_callback")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join("template"))
    destination_contents = read_relative_file_tree(fixture_dir.join("destination"))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      family = entry.dig(:classification, :family) || entry.dig("classification", "family")
      case family
      when "markdown"
        Markdown::Merge.merge_markdown(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "markdown"
        )
      when "toml"
        Toml::Merge.merge_toml(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "toml"
        )
      when "ruby"
        Ruby::Merge.merge_ruby(
          entry[:prepared_template_content] || entry["prepared_template_content"],
          entry[:destination_content] || entry["destination_content"],
          "ruby"
        )
      else
        {
          ok: false,
          diagnostics: [{ severity: "error", category: "configuration_error", message: "missing family merge adapter for #{family}" }],
          policies: []
        }
      end
    end

    expect(json_ready(described_class.report_template_tree_run(run_result))).to eq(json_ready(report_fixture[:expected]))
  end

  it "conforms to the mini template tree directory run report fixture" do
    fixture = diagnostics_fixture("mini_template_tree_directory_run_report")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_directory_run_report")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])

    run_result = described_class.run_template_tree_execution_from_directories(
      fixture_dir.join("template"),
      fixture_dir.join("destination"),
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      case entry[:classification][:family]
      when "markdown"
        Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
      when "toml"
        Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
      when "ruby"
        Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
      else
        {
          ok: false,
          diagnostics: [{ severity: "error", category: "configuration_error",
                          message: "missing family merge adapter for #{entry[:classification][:family]}" }]
        }
      end
    end

    expect(json_ready(described_class.report_template_tree_run(run_result))).to eq(json_ready(fixture[:expected]))
  end

  it "conforms to the mini template tree directory apply convergence fixture" do
    fixture = diagnostics_fixture("mini_template_tree_directory_apply_convergence")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_directory_apply_convergence")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    temp_dir = repo_temp_dir
    destination_root = temp_dir.join("destination")

    begin
      described_class.write_relative_file_tree(destination_root, read_relative_file_tree(fixture_dir.join("destination")))

      first_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join("template"),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when "markdown"
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
        when "toml"
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
        when "ruby"
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
        else
          {
            ok: false,
            diagnostics: [{ severity: "error", category: "configuration_error",
                            message: "missing family merge adapter for #{entry[:classification][:family]}" }]
          }
        end
      end

      expect(json_ready(described_class.report_template_tree_run(first_run))).to eq(
        json_ready(fixture[:expected_first_report])
      )
      expect(json_ready(described_class.read_relative_file_tree(destination_root))).to eq(
        json_ready(fixture[:expected_destination_files])
      )

      second_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join("template"),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when "markdown"
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
        when "toml"
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
        when "ruby"
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
        else
          {
            ok: false,
            diagnostics: [{ severity: "error", category: "configuration_error",
                            message: "missing family merge adapter for #{entry[:classification][:family]}" }]
          }
        end
      end

      expect(json_ready(described_class.report_template_tree_run(second_run))).to eq(
        json_ready(fixture[:expected_second_report])
      )
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the mini template tree directory apply report fixture" do
    fixture = diagnostics_fixture("mini_template_tree_directory_apply_report")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_directory_apply_report")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    temp_dir = repo_temp_dir
    destination_root = temp_dir.join("destination")

    begin
      described_class.write_relative_file_tree(destination_root, read_relative_file_tree(fixture_dir.join("destination")))

      first_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join("template"),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when "markdown"
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
        when "toml"
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
        when "ruby"
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
        else
          {
            ok: false,
            diagnostics: [{ severity: "error", category: "configuration_error",
                            message: "missing family merge adapter for #{entry[:classification][:family]}" }]
          }
        end
      end

      expect(json_ready(described_class.report_template_directory_apply(first_run))).to eq(
        json_ready(fixture[:expected_first_report])
      )

      second_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join("template"),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when "markdown"
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
        when "toml"
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
        when "ruby"
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
        else
          {
            ok: false,
            diagnostics: [{ severity: "error", category: "configuration_error",
                            message: "missing family merge adapter for #{entry[:classification][:family]}" }]
          }
        end
      end

      expect(json_ready(described_class.report_template_directory_apply(second_run))).to eq(
        json_ready(fixture[:expected_second_report])
      )
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the mini template tree directory plan report fixture" do
    fixture = diagnostics_fixture("mini_template_tree_directory_plan_report")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_directory_plan_report")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])

    execution_plan = described_class.plan_template_tree_execution_from_directories(
      fixture_dir.join("template"),
      fixture_dir.join("destination"),
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    )

    expect(json_ready(described_class.report_template_directory_plan(execution_plan))).to eq(
      json_ready(fixture[:expected])
    )
  end

  it "conforms to the mini template tree directory runner report fixture" do
    fixture = diagnostics_fixture("mini_template_tree_directory_runner_report")
    fixture_path = described_class.conformance_fixture_path(manifest, "diagnostics", "mini_template_tree_directory_runner_report")
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])

    dry_run_plan = described_class.plan_template_tree_execution_from_directories(
      fixture_dir.join("dry-run", "template"),
      fixture_dir.join("dry-run", "destination"),
      fixture.dig(:dry_run, :context),
      fixture.dig(:dry_run, :default_strategy),
      fixture.dig(:dry_run, :overrides),
      fixture.dig(:dry_run, :replacements)
    )
    expect(json_ready(described_class.report_template_directory_runner(dry_run_plan))).to eq(
      json_ready(fixture.dig(:dry_run, :expected))
    )

    temp_dir = repo_temp_dir
    destination_root = temp_dir.join("destination")
    begin
      described_class.write_relative_file_tree(
        destination_root,
        read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
      )

      apply_plan = described_class.plan_template_tree_execution_from_directories(
        fixture_dir.join("apply-run", "template"),
        destination_root,
        fixture.dig(:apply_run, :context),
        fixture.dig(:apply_run, :default_strategy),
        fixture.dig(:apply_run, :overrides),
        fixture.dig(:apply_run, :replacements)
      )
      apply_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join("apply-run", "template"),
        destination_root,
        fixture.dig(:apply_run, :context),
        fixture.dig(:apply_run, :default_strategy),
        fixture.dig(:apply_run, :overrides),
        fixture.dig(:apply_run, :replacements)
      ) do |entry|
        case entry[:classification][:family]
        when "markdown"
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
        when "toml"
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
        when "ruby"
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
        else
          {
            ok: false,
            diagnostics: [{ severity: "error", category: "configuration_error",
                            message: "missing family merge adapter for #{entry[:classification][:family]}" }]
          }
        end
      end

      expect(json_ready(described_class.report_template_directory_runner(apply_plan, apply_run))).to eq(
        json_ready(fixture.dig(:apply_run, :expected))
      )
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the template entry plan state fixture" do
    fixture = diagnostics_fixture("template_entry_plan_state")

    expect(
      json_ready(
        described_class.enrich_template_plan_entries(
          fixture[:planned_entries],
          fixture[:existing_destination_paths]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
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
    named_suite_runner_fixture = diagnostics_fixture("named_suite_runner")
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

    expect(json_ready(described_class.conformance_suite_definition(manifest, suite_definitions_fixture[:suite_selector]))).to eq(
      json_ready(suite_definitions_fixture[:expected])
    )
    expect(json_ready(described_class.conformance_suite_selectors(manifest))).to eq(json_ready(suite_names_fixture[:suite_selectors]))
    expect(json_ready(named_suite_plan_entry_fixture[:context])).to eq(json_ready(family_plan_context_fixture[:context]))

    named_entry = described_class.report_named_conformance_suite_entry(
      manifest,
      named_suite_entry_fixture[:suite_selector],
      named_suite_entry_fixture[:family_profile],
      {
        backend: "kreuzberg-language-pack",
        supports_dialects: false,
        supported_policies: [{ surface: "array", name: "destination_wins_array" }]
      },
      &execute_from(named_suite_entry_fixture[:executions])
    )
    expect(json_ready(named_entry)).to eq(json_ready(named_suite_entry_fixture[:expected_entry]))

    named_runner = described_class.run_named_conformance_suite(
      manifest,
      named_suite_runner_fixture[:suite_selector],
      named_suite_runner_fixture[:family_profile],
      {
        backend: "kreuzberg-language-pack",
        supports_dialects: false,
        supported_policies: [{ surface: "array", name: "destination_wins_array" }]
      },
      &execute_from(named_suite_runner_fixture[:executions])
    )
    expect(json_ready(named_runner)).to eq(json_ready(named_suite_runner_fixture[:expected_results]))

    named_plan_entry = described_class.plan_named_conformance_suite_entry(
      manifest,
      named_suite_plan_entry_fixture[:suite_selector],
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
      named_suite_results_fixture[:suite_selector],
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
      named_suite_report_fixture[:suite_selector],
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

    explicit_family = explicit_mode_fixture.dig(:manifest, :suite_descriptors)&.first&.dig(:subject, :grammar)
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
    replay_bundle_reviewed_nested_fixture = diagnostics_fixture("review_replay_bundle_reviewed_nested_executions")
    replay_bundle_application_fixture = diagnostics_fixture("review_replay_bundle_application")
    review_state_reviewed_nested_fixture = diagnostics_fixture("review_state_reviewed_nested_executions")
    review_state_roundtrip_fixture = diagnostics_fixture("review_state_json_roundtrip")
    replay_bundle_roundtrip_fixture = diagnostics_fixture("review_replay_bundle_json_roundtrip")
    review_state_envelope_fixture = diagnostics_fixture("review_state_envelope")
    replay_bundle_envelope_fixture = diagnostics_fixture("review_replay_bundle_envelope")
    review_state_envelope_rejection_fixture = diagnostics_fixture("review_state_envelope_rejection")
    replay_bundle_envelope_rejection_fixture = diagnostics_fixture("review_replay_bundle_envelope_rejection")
    reviewed_nested_execution_roundtrip_fixture = diagnostics_fixture("reviewed_nested_execution_json_roundtrip")
    reviewed_nested_execution_envelope_fixture = diagnostics_fixture("reviewed_nested_execution_envelope")
    reviewed_nested_execution_envelope_rejection_fixture = diagnostics_fixture("reviewed_nested_execution_envelope_rejection")
    reviewed_nested_execution_replay_application_fixture = diagnostics_fixture("review_replay_bundle_reviewed_nested_execution_application")
    reviewed_nested_execution_state_application_fixture = diagnostics_fixture("review_state_reviewed_nested_execution_application")
    review_proposal_fixture = diagnostics_fixture("family_context_review_proposal")
    explicit_decision_fixture = diagnostics_fixture("family_context_explicit_review_decision")
    explicit_bundle_fixture = diagnostics_fixture("explicit_review_replay_bundle_application")
    missing_context_fixture = diagnostics_fixture("explicit_review_decision_missing_context")
    family_mismatch_fixture = diagnostics_fixture("explicit_review_decision_family_mismatch")
    surface_fixture = diagnostics_fixture("surface_ownership")
    delegated_operation_fixture = diagnostics_fixture("delegated_child_operation")
    structured_edit_structure_profile_fixture = diagnostics_fixture("structured_edit_structure_profile")
    structured_edit_selection_profile_fixture = diagnostics_fixture("structured_edit_selection_profile")
    structured_edit_match_profile_fixture = diagnostics_fixture("structured_edit_match_profile")
    structured_edit_operation_profile_fixture = diagnostics_fixture("structured_edit_operation_profile")
    structured_edit_destination_profile_fixture = diagnostics_fixture("structured_edit_destination_profile")
    structured_edit_request_fixture = diagnostics_fixture("structured_edit_request")
    structured_edit_result_fixture = diagnostics_fixture("structured_edit_result")
    structured_edit_application_fixture = diagnostics_fixture("structured_edit_application")
    structured_edit_application_envelope_fixture = diagnostics_fixture("structured_edit_application_envelope")
    structured_edit_application_envelope_rejection_fixture = diagnostics_fixture("structured_edit_application_envelope_rejection")
    structured_edit_application_envelope_application_fixture = diagnostics_fixture("structured_edit_application_envelope_application")
    structured_edit_execution_report_fixture = diagnostics_fixture("structured_edit_execution_report")
    structured_edit_provider_execution_request_fixture = diagnostics_fixture("structured_edit_provider_execution_request")
    structured_edit_provider_execution_request_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_request_envelope")
    structured_edit_provider_execution_request_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_request_envelope_rejection")
    structured_edit_provider_execution_request_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_request_envelope_application")
    structured_edit_provider_execution_application_fixture = diagnostics_fixture("structured_edit_provider_execution_application")
    structured_edit_provider_execution_dispatch_fixture = diagnostics_fixture("structured_edit_provider_execution_dispatch")
    structured_edit_provider_execution_dispatch_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_dispatch_envelope")
    structured_edit_provider_execution_dispatch_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_dispatch_envelope_rejection")
    structured_edit_provider_execution_dispatch_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_dispatch_envelope_application")
    structured_edit_provider_execution_outcome_fixture = diagnostics_fixture("structured_edit_provider_execution_outcome")
    structured_edit_provider_execution_outcome_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_outcome_envelope")
    structured_edit_provider_execution_outcome_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_outcome_envelope_rejection")
    structured_edit_provider_execution_outcome_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_outcome_envelope_application")
    structured_edit_provider_batch_execution_outcome_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_outcome")
    structured_edit_provider_batch_execution_outcome_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_outcome_envelope")
    structured_edit_provider_batch_execution_outcome_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_outcome_envelope_rejection")
    structured_edit_provider_batch_execution_outcome_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_outcome_envelope_application")
    structured_edit_provider_execution_provenance_fixture = diagnostics_fixture("structured_edit_provider_execution_provenance")
    structured_edit_provider_execution_provenance_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_provenance_envelope")
    structured_edit_provider_execution_provenance_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_provenance_envelope_rejection")
    structured_edit_provider_execution_provenance_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_provenance_envelope_application")
    structured_edit_provider_batch_execution_provenance_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_provenance")
    structured_edit_provider_batch_execution_provenance_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_provenance_envelope")
    structured_edit_provider_batch_execution_provenance_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_provenance_envelope_rejection")
    structured_edit_provider_batch_execution_provenance_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_provenance_envelope_application")
    structured_edit_provider_execution_replay_bundle_fixture = diagnostics_fixture("structured_edit_provider_execution_replay_bundle")
    structured_edit_provider_execution_replay_bundle_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_replay_bundle_envelope")
    structured_edit_provider_execution_replay_bundle_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_replay_bundle_envelope_rejection")
    structured_edit_provider_execution_replay_bundle_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_replay_bundle_envelope_application")
    structured_edit_provider_batch_execution_replay_bundle_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_replay_bundle")
    structured_edit_provider_batch_execution_replay_bundle_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_replay_bundle_envelope")
    structured_edit_provider_batch_execution_replay_bundle_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_replay_bundle_envelope_rejection")
    structured_edit_provider_batch_execution_replay_bundle_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_replay_bundle_envelope_application")
    structured_edit_provider_executor_profile_fixture = diagnostics_fixture("structured_edit_provider_executor_profile")
    structured_edit_provider_executor_profile_envelope_fixture = diagnostics_fixture("structured_edit_provider_executor_profile_envelope")
    structured_edit_provider_executor_profile_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_executor_profile_envelope_rejection")
    structured_edit_provider_executor_profile_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_executor_profile_envelope_application")
    structured_edit_provider_executor_registry_fixture = diagnostics_fixture("structured_edit_provider_executor_registry")
    structured_edit_provider_executor_registry_envelope_fixture = diagnostics_fixture("structured_edit_provider_executor_registry_envelope")
    structured_edit_provider_executor_registry_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_executor_registry_envelope_rejection")
    structured_edit_provider_executor_registry_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_executor_registry_envelope_application")
    structured_edit_provider_executor_selection_policy_fixture = diagnostics_fixture("structured_edit_provider_executor_selection_policy")
    structured_edit_provider_executor_selection_policy_envelope_fixture = diagnostics_fixture("structured_edit_provider_executor_selection_policy_envelope")
    structured_edit_provider_executor_selection_policy_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_executor_selection_policy_envelope_rejection")
    structured_edit_provider_executor_selection_policy_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_executor_selection_policy_envelope_application")
    structured_edit_provider_executor_resolution_fixture = diagnostics_fixture("structured_edit_provider_executor_resolution")
    structured_edit_provider_executor_resolution_envelope_fixture = diagnostics_fixture("structured_edit_provider_executor_resolution_envelope")
    structured_edit_provider_executor_resolution_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_executor_resolution_envelope_rejection")
    structured_edit_provider_executor_resolution_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_executor_resolution_envelope_application")
    structured_edit_provider_execution_plan_fixture = diagnostics_fixture("structured_edit_provider_execution_plan")
    structured_edit_provider_execution_handoff_fixture = diagnostics_fixture("structured_edit_provider_execution_handoff")
    structured_edit_provider_execution_handoff_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_handoff_envelope")
    structured_edit_provider_execution_handoff_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_handoff_envelope_rejection")
    structured_edit_provider_execution_handoff_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_handoff_envelope_application")
    structured_edit_provider_execution_invocation_fixture = diagnostics_fixture("structured_edit_provider_execution_invocation")
    structured_edit_provider_execution_invocation_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_invocation_envelope")
    structured_edit_provider_execution_invocation_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_invocation_envelope_rejection")
    structured_edit_provider_execution_invocation_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_invocation_envelope_application")
    structured_edit_provider_batch_execution_invocation_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_invocation")
    structured_edit_provider_batch_execution_invocation_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_invocation_envelope")
    structured_edit_provider_batch_execution_invocation_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_invocation_envelope_rejection")
    structured_edit_provider_batch_execution_invocation_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_invocation_envelope_application")
    structured_edit_provider_execution_run_result_fixture = diagnostics_fixture("structured_edit_provider_execution_run_result")
    structured_edit_provider_execution_run_result_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_run_result_envelope")
    structured_edit_provider_execution_run_result_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_run_result_envelope_rejection")
    structured_edit_provider_execution_run_result_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_run_result_envelope_application")
    structured_edit_provider_batch_execution_run_result_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_run_result")
    structured_edit_provider_batch_execution_run_result_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_run_result_envelope")
    structured_edit_provider_batch_execution_run_result_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_run_result_envelope_rejection")
    structured_edit_provider_batch_execution_run_result_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_run_result_envelope_application")
    structured_edit_provider_execution_receipt_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt")
    structured_edit_provider_execution_receipt_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_envelope")
    structured_edit_provider_execution_receipt_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_envelope_rejection")
    structured_edit_provider_execution_receipt_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_envelope_application")
    structured_edit_provider_batch_execution_receipt_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt")
    structured_edit_provider_batch_execution_receipt_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_envelope")
    structured_edit_provider_batch_execution_receipt_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_envelope_rejection")
    structured_edit_provider_batch_execution_receipt_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_envelope_application")
    structured_edit_provider_execution_receipt_replay_request_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_replay_request")
    structured_edit_provider_execution_receipt_replay_request_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_replay_request_envelope")
    structured_edit_provider_execution_receipt_replay_request_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_replay_request_envelope_rejection")
    structured_edit_provider_execution_receipt_replay_request_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_receipt_replay_request_envelope_application")
    structured_edit_provider_batch_execution_receipt_replay_request_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_replay_request")
    structured_edit_provider_batch_execution_receipt_replay_request_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_replay_request_envelope")
    structured_edit_provider_batch_execution_receipt_replay_request_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_replay_request_envelope_rejection")
    structured_edit_provider_batch_execution_receipt_replay_request_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_receipt_replay_request_envelope_application")
    structured_edit_provider_batch_execution_handoff_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_handoff")
    structured_edit_provider_batch_execution_handoff_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_handoff_envelope")
    structured_edit_provider_batch_execution_handoff_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_handoff_envelope_rejection")
    structured_edit_provider_batch_execution_handoff_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_handoff_envelope_application")
    structured_edit_provider_execution_plan_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_plan_envelope")
    structured_edit_provider_execution_plan_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_plan_envelope_rejection")
    structured_edit_provider_execution_plan_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_plan_envelope_application")
    structured_edit_provider_batch_execution_plan_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_plan")
    structured_edit_provider_batch_execution_plan_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_plan_envelope")
    structured_edit_provider_batch_execution_plan_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_plan_envelope_rejection")
    structured_edit_provider_batch_execution_plan_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_plan_envelope_application")
    structured_edit_provider_execution_application_envelope_fixture = diagnostics_fixture("structured_edit_provider_execution_application_envelope")
    structured_edit_provider_execution_application_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_execution_application_envelope_rejection")
    structured_edit_provider_execution_application_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_execution_application_envelope_application")
    structured_edit_execution_report_envelope_fixture = diagnostics_fixture("structured_edit_execution_report_envelope")
    structured_edit_execution_report_envelope_rejection_fixture = diagnostics_fixture("structured_edit_execution_report_envelope_rejection")
    structured_edit_execution_report_envelope_application_fixture = diagnostics_fixture("structured_edit_execution_report_envelope_application")
    structured_edit_batch_request_fixture = diagnostics_fixture("structured_edit_batch_request")
    structured_edit_provider_batch_execution_request_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_request")
    structured_edit_provider_batch_execution_request_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_request_envelope")
    structured_edit_provider_batch_execution_request_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_request_envelope_rejection")
    structured_edit_provider_batch_execution_request_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_request_envelope_application")
    structured_edit_provider_batch_execution_dispatch_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_dispatch")
    structured_edit_provider_batch_execution_dispatch_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_dispatch_envelope")
    structured_edit_provider_batch_execution_dispatch_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_dispatch_envelope_rejection")
    structured_edit_provider_batch_execution_dispatch_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_dispatch_envelope_application")
    structured_edit_provider_batch_execution_report_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_report")
    structured_edit_provider_batch_execution_report_envelope_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_report_envelope")
    structured_edit_provider_batch_execution_report_envelope_rejection_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_report_envelope_rejection")
    structured_edit_provider_batch_execution_report_envelope_application_fixture = diagnostics_fixture("structured_edit_provider_batch_execution_report_envelope_application")
    structured_edit_batch_report_fixture = diagnostics_fixture("structured_edit_batch_report")
    structured_edit_batch_report_envelope_fixture = diagnostics_fixture("structured_edit_batch_report_envelope")
    structured_edit_batch_report_envelope_rejection_fixture = diagnostics_fixture("structured_edit_batch_report_envelope_rejection")
    structured_edit_batch_report_envelope_application_fixture = diagnostics_fixture("structured_edit_batch_report_envelope_application")
    projected_cases_fixture = diagnostics_fixture("projected_child_review_cases")

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

    replay_context, replay_decisions, replay_reviewed_nested = described_class.review_replay_bundle_inputs(review_replay_bundle: replay_bundle_fixture[:replay_bundle])
    expect(json_ready(replay_context)).to eq(json_ready(replay_bundle_fixture[:replay_bundle][:replay_context]))
    expect(json_ready(replay_decisions)).to eq(json_ready(replay_bundle_fixture[:replay_bundle][:decisions]))
    expect(json_ready(replay_reviewed_nested)).to eq(json_ready([]))

    replay_context_with_nested, replay_decisions_with_nested, replay_reviewed_nested_with_nested =
      described_class.review_replay_bundle_inputs(review_replay_bundle: replay_bundle_reviewed_nested_fixture[:replay_bundle])
    expect(json_ready(replay_context_with_nested)).to eq(json_ready(replay_bundle_reviewed_nested_fixture[:replay_bundle][:replay_context]))
    expect(json_ready(replay_decisions_with_nested)).to eq(json_ready(replay_bundle_reviewed_nested_fixture[:replay_bundle][:decisions]))
    expect(json_ready(replay_reviewed_nested_with_nested)).to eq(json_ready(replay_bundle_reviewed_nested_fixture[:replay_bundle][:reviewed_nested_executions]))

    replay_applied = described_class.review_conformance_manifest(
      replay_bundle_application_fixture[:manifest],
      replay_bundle_application_fixture[:options],
      &execute_from(replay_bundle_application_fixture[:executions])
    )
    expect(json_ready(replay_applied)).to eq(json_ready(replay_bundle_application_fixture[:expected_state]))

    replay_with_nested_applied = described_class.review_conformance_manifest(
      review_state_reviewed_nested_fixture[:manifest],
      review_state_reviewed_nested_fixture[:options],
      &execute_from(review_state_reviewed_nested_fixture[:executions])
    )
    expect(json_ready(replay_with_nested_applied)).to eq(json_ready(review_state_reviewed_nested_fixture[:expected_state]))

    replay_nested_runs = described_class.execute_review_replay_bundle_reviewed_nested_executions(
      reviewed_nested_execution_replay_application_fixture[:replay_bundle]
    ) do |execution, index|
      expected_output = reviewed_nested_execution_replay_application_fixture[:expected_results][index][:result][:output]
      {
        merge_parent: lambda {
          { ok: true, diagnostics: [], output: "#{execution[:family]}-merged-parent", policies: [] }
        },
        discover_operations: lambda { |_merged_output|
          {
            ok: true,
            diagnostics: [],
            operations: execution[:review_state][:accepted_groups].map do |group|
              if execution[:family] == "markdown"
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: "delegate_child_surface",
                  language_chain: %w[markdown typescript],
                  surface: {
                    surface_kind: "fenced_code_block",
                    effective_language: "typescript",
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: "owned_region", address: "/code_fence/0" },
                    reconstruction_strategy: "portable_write",
                    metadata: { family: "typescript" }
                  }
                }
              else
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: "delegate_child_surface",
                  language_chain: %w[ruby ruby],
                  surface: {
                    surface_kind: "yard_example",
                    effective_language: "ruby",
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: "owned_region", address: "/yard_example/1" },
                    reconstruction_strategy: "portable_write",
                    metadata: { family: "ruby" }
                  }
                }
              end
            end
          }
        },
        apply_resolved_outputs: lambda { |_merged_output, _operations, _apply_plan, applied_children|
          expect(json_ready(applied_children)).to eq(json_ready(execution[:applied_children]))
          { ok: true, diagnostics: [], output: expected_output, policies: [] }
        }
      }
    end
    expect(json_ready(replay_nested_runs.map { |run| { execution_family: run[:execution][:family], result: run[:result] } })).to eq(
      json_ready(reviewed_nested_execution_replay_application_fixture[:expected_results])
    )

    review_state_nested_runs = described_class.execute_review_state_reviewed_nested_executions(
      reviewed_nested_execution_state_application_fixture[:review_state]
    ) do |execution, index|
      expected_output = reviewed_nested_execution_state_application_fixture[:expected_results][index][:result][:output]
      {
        merge_parent: lambda {
          { ok: true, diagnostics: [], output: "#{execution[:family]}-merged-parent", policies: [] }
        },
        discover_operations: lambda { |_merged_output|
          {
            ok: true,
            diagnostics: [],
            operations: execution[:review_state][:accepted_groups].map do |group|
              if execution[:family] == "markdown"
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: "delegate_child_surface",
                  language_chain: %w[markdown typescript],
                  surface: {
                    surface_kind: "fenced_code_block",
                    effective_language: "typescript",
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: "owned_region", address: "/code_fence/0" },
                    reconstruction_strategy: "portable_write",
                    metadata: { family: "typescript" }
                  }
                }
              else
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: "delegate_child_surface",
                  language_chain: %w[ruby ruby],
                  surface: {
                    surface_kind: "yard_example",
                    effective_language: "ruby",
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: "owned_region", address: "/yard_example/1" },
                    reconstruction_strategy: "portable_write",
                    metadata: { family: "ruby" }
                  }
                }
              end
            end
          }
        },
        apply_resolved_outputs: lambda { |_merged_output, _operations, _apply_plan, applied_children|
          expect(json_ready(applied_children)).to eq(json_ready(execution[:applied_children]))
          { ok: true, diagnostics: [], output: expected_output, policies: [] }
        }
      }
    end
    expect(json_ready(review_state_nested_runs.map { |run| { execution_family: run[:execution][:family], result: run[:result] } })).to eq(
      json_ready(reviewed_nested_execution_state_application_fixture[:expected_results])
    )

    replay_bundle_envelope_reviewed_nested_fixture = diagnostics_fixture("review_replay_bundle_envelope_reviewed_nested_execution_application")
    replay_bundle_envelope_nested_application = described_class.execute_review_replay_bundle_envelope_reviewed_nested_executions(
      replay_bundle_envelope_reviewed_nested_fixture[:replay_bundle_envelope]
    ) do |execution, index|
      expected_output = replay_bundle_envelope_reviewed_nested_fixture[:expected_application][:results][index][:result][:output]
      {
        merge_parent: lambda {
          { ok: true, diagnostics: [], output: "#{execution[:family]}-merged-parent", policies: [] }
        },
        discover_operations: lambda { |_merged_output|
          { ok: true, diagnostics: [], operations: [] }
        },
        apply_resolved_outputs: lambda { |_merged_output, _operations, _apply_plan, _applied_children|
          { ok: true, diagnostics: [], output: expected_output, policies: [] }
        }
      }
    end
    expect(json_ready(replay_bundle_envelope_nested_application[:diagnostics])).to eq([])
    expect(json_ready(replay_bundle_envelope_nested_application[:results].map { |run| { execution_family: run[:execution][:family], result: run[:result] } })).to eq(
      json_ready(replay_bundle_envelope_reviewed_nested_fixture[:expected_application][:results])
    )

    review_state_envelope_reviewed_nested_fixture = diagnostics_fixture("review_state_envelope_reviewed_nested_execution_application")
    review_state_envelope_nested_application = described_class.execute_review_state_envelope_reviewed_nested_executions(
      review_state_envelope_reviewed_nested_fixture[:review_state_envelope]
    ) do |execution, index|
      expected_output = review_state_envelope_reviewed_nested_fixture[:expected_application][:results][index][:result][:output]
      {
        merge_parent: lambda {
          { ok: true, diagnostics: [], output: "#{execution[:family]}-merged-parent", policies: [] }
        },
        discover_operations: lambda { |_merged_output|
          { ok: true, diagnostics: [], operations: [] }
        },
        apply_resolved_outputs: lambda { |_merged_output, _operations, _apply_plan, _applied_children|
          { ok: true, diagnostics: [], output: expected_output, policies: [] }
        }
      }
    end
    expect(json_ready(review_state_envelope_nested_application[:diagnostics])).to eq([])
    expect(json_ready(review_state_envelope_nested_application[:results].map { |run| { execution_family: run[:execution][:family], result: run[:result] } })).to eq(
      json_ready(review_state_envelope_reviewed_nested_fixture[:expected_application][:results])
    )

    replay_bundle_envelope_reviewed_nested_rejection_fixture = diagnostics_fixture("review_replay_bundle_envelope_reviewed_nested_execution_rejection")
    replay_bundle_envelope_reviewed_nested_rejection_fixture[:cases].each do |test_case|
      rejected_application = described_class.execute_review_replay_bundle_envelope_reviewed_nested_executions(
        test_case[:replay_bundle_envelope]
      ) do
        raise "callbacks should not run for rejected replay bundle envelopes"
      end
      expect(json_ready(rejected_application)).to eq(json_ready(test_case[:expected_application]))
    end

    review_state_envelope_reviewed_nested_rejection_fixture = diagnostics_fixture("review_state_envelope_reviewed_nested_execution_rejection")
    review_state_envelope_reviewed_nested_rejection_fixture[:cases].each do |test_case|
      rejected_application = described_class.execute_review_state_envelope_reviewed_nested_executions(
        test_case[:review_state_envelope]
      ) do
        raise "callbacks should not run for rejected review state envelopes"
      end
      expect(json_ready(rejected_application)).to eq(json_ready(test_case[:expected_application]))
    end

    reviewed_nested_manifest_application_fixture = diagnostics_fixture("review_replay_bundle_envelope_reviewed_nested_manifest_application")
    reviewed_nested_manifest_application = described_class.review_and_execute_conformance_manifest_with_replay_bundle_envelope(
      reviewed_nested_manifest_application_fixture[:manifest],
      reviewed_nested_manifest_application_fixture[:options],
      reviewed_nested_manifest_application_fixture[:review_replay_bundle_envelope],
      execute: execute_from(reviewed_nested_manifest_application_fixture[:executions]),
      reviewed_nested_execution: lambda do |execution, index|
        expected_output = reviewed_nested_manifest_application_fixture[:expected_application][:results][index][:result][:output]
        {
          merge_parent: lambda {
            { ok: true, diagnostics: [], output: "#{execution[:family]}-merged-parent", policies: [] }
          },
          discover_operations: lambda { |_merged_output|
            { ok: true, diagnostics: [], operations: [] }
          },
          apply_resolved_outputs: lambda { |_merged_output, _operations, _apply_plan, _applied_children|
            { ok: true, diagnostics: [], output: expected_output, policies: [] }
          }
        }
      end
    )
    expect(json_ready(reviewed_nested_manifest_application[:state])).to eq(
      json_ready(reviewed_nested_manifest_application_fixture[:expected_state])
    )
    expect(json_ready(reviewed_nested_manifest_application[:results].map { |run| { execution_family: run[:execution][:family], result: run[:result] } })).to eq(
      json_ready(reviewed_nested_manifest_application_fixture[:expected_application][:results])
    )

    reviewed_nested_manifest_rejection_fixture = diagnostics_fixture("review_replay_bundle_envelope_reviewed_nested_manifest_rejection")
    reviewed_nested_manifest_rejection_fixture[:cases].each do |test_case|
      rejected_application = described_class.review_and_execute_conformance_manifest_with_replay_bundle_envelope(
        reviewed_nested_manifest_rejection_fixture[:manifest],
        reviewed_nested_manifest_rejection_fixture[:options],
        test_case[:review_replay_bundle_envelope],
        execute: execute_from(reviewed_nested_manifest_rejection_fixture[:executions]),
        reviewed_nested_execution: lambda do
          raise "callbacks should not run for rejected replay bundle envelopes"
        end
      )
      expect(json_ready(rejected_application)).to eq(
        json_ready(
          state: test_case[:expected_state],
          results: test_case[:expected_application][:results]
        )
      )
    end

    review_state_envelope = described_class.conformance_manifest_review_state_envelope(review_state_roundtrip_fixture[:state])
    roundtrip_state, roundtrip_error = described_class.import_conformance_manifest_review_state_envelope(review_state_envelope)
    expect(roundtrip_error).to be_nil
    expect(json_ready(roundtrip_state)).to eq(json_ready(review_state_roundtrip_fixture[:state]))

    replay_bundle_envelope = described_class.review_replay_bundle_envelope(replay_bundle_roundtrip_fixture[:replay_bundle])
    roundtrip_bundle, bundle_error = described_class.import_review_replay_bundle_envelope(replay_bundle_envelope)
    expect(bundle_error).to be_nil
    expect(json_ready(roundtrip_bundle)).to eq(json_ready(replay_bundle_roundtrip_fixture[:replay_bundle]))

    reviewed_nested_execution_envelope = described_class.reviewed_nested_execution_envelope(
      reviewed_nested_execution_roundtrip_fixture[:execution]
    )
    roundtrip_execution, execution_error = described_class.import_reviewed_nested_execution_envelope(
      reviewed_nested_execution_envelope
    )
    expect(execution_error).to be_nil
    expect(json_ready(roundtrip_execution)).to eq(json_ready(reviewed_nested_execution_roundtrip_fixture[:execution]))

    expect(json_ready(described_class.conformance_manifest_review_state_envelope(review_state_envelope_fixture[:state]))).to eq(
      json_ready(review_state_envelope_fixture[:expected_envelope])
    )
    expect(json_ready(described_class.review_replay_bundle_envelope(replay_bundle_envelope_fixture[:replay_bundle]))).to eq(
      json_ready(replay_bundle_envelope_fixture[:expected_envelope])
    )
    expect(json_ready(described_class.reviewed_nested_execution_envelope(reviewed_nested_execution_envelope_fixture[:execution]))).to eq(
      json_ready(reviewed_nested_execution_envelope_fixture[:expected_envelope])
    )

    review_state_envelope_rejection_fixture[:cases].each do |test_case|
      _state, envelope_error = described_class.import_conformance_manifest_review_state_envelope(test_case[:envelope])
      expect(json_ready(envelope_error)).to eq(json_ready(test_case[:expected_error]))
    end

    replay_bundle_envelope_rejection_fixture[:cases].each do |test_case|
      _bundle, bundle_rejection_error = described_class.import_review_replay_bundle_envelope(test_case[:envelope])
      expect(json_ready(bundle_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    reviewed_nested_execution_envelope_rejection_fixture[:cases].each do |test_case|
      _execution, execution_rejection_error = described_class.import_reviewed_nested_execution_envelope(test_case[:envelope])
      expect(json_ready(execution_rejection_error)).to eq(json_ready(test_case[:expected_error]))
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

    replay_bundle_envelope_application_fixture = diagnostics_fixture("review_replay_bundle_envelope_application")
    replay_bundle_envelope_applied = described_class.review_conformance_manifest_with_replay_bundle_envelope(
      replay_bundle_envelope_application_fixture[:manifest],
      replay_bundle_envelope_application_fixture[:options],
      replay_bundle_envelope_application_fixture[:review_replay_bundle_envelope],
      &execute_from(replay_bundle_envelope_application_fixture[:executions])
    )
    expect(json_ready(replay_bundle_envelope_applied)).to eq(
      json_ready(replay_bundle_envelope_application_fixture[:expected_state])
    )

    explicit_bundle_envelope_fixture = diagnostics_fixture("explicit_review_replay_bundle_envelope_application")
    explicit_envelope_applied = described_class.review_conformance_manifest_with_replay_bundle_envelope(
      explicit_bundle_envelope_fixture[:manifest],
      explicit_bundle_envelope_fixture[:options],
      explicit_bundle_envelope_fixture[:review_replay_bundle_envelope],
      &execute_from(explicit_bundle_envelope_fixture[:executions])
    )
    expect(json_ready(explicit_envelope_applied)).to eq(json_ready(explicit_bundle_envelope_fixture[:expected_state]))

    replay_bundle_envelope_rejection_fixture = diagnostics_fixture("review_replay_bundle_envelope_review_rejection")
    replay_bundle_envelope_rejection_fixture[:cases].each do |test_case|
      rejected_state = described_class.review_conformance_manifest_with_replay_bundle_envelope(
        replay_bundle_envelope_rejection_fixture[:manifest],
        replay_bundle_envelope_rejection_fixture[:options],
        test_case[:review_replay_bundle_envelope],
        &execute_from(replay_bundle_envelope_rejection_fixture[:executions])
      )
      expect(json_ready(rejected_state)).to eq(json_ready(test_case[:expected_state]))
    end

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

    surface = described_class.discovered_surface(
      surface_kind: surface_fixture.dig(:surface, :surface_kind),
      declared_language: surface_fixture.dig(:surface, :declared_language),
      effective_language: surface_fixture.dig(:surface, :effective_language),
      address: surface_fixture.dig(:surface, :address),
      parent_address: surface_fixture.dig(:surface, :parent_address),
      span: described_class.surface_span(
        start_line: surface_fixture.dig(:surface, :span, :start_line),
        end_line: surface_fixture.dig(:surface, :span, :end_line)
      ),
      owner: described_class.surface_owner_ref(
        kind: surface_fixture.dig(:surface, :owner, :kind),
        address: surface_fixture.dig(:surface, :owner, :address)
      ),
      reconstruction_strategy: surface_fixture.dig(:surface, :reconstruction_strategy),
      metadata: surface_fixture.dig(:surface, :metadata)
    )
    expect(json_ready(surface)).to eq(json_ready(surface_fixture[:surface]))

    delegated_operation = described_class.delegated_child_operation(
      operation_id: delegated_operation_fixture.dig(:operation, :operation_id),
      parent_operation_id: delegated_operation_fixture.dig(:operation, :parent_operation_id),
      requested_strategy: delegated_operation_fixture.dig(:operation, :requested_strategy),
      language_chain: delegated_operation_fixture.dig(:operation, :language_chain),
      surface: described_class.discovered_surface(
        surface_kind: delegated_operation_fixture.dig(:operation, :surface, :surface_kind),
        declared_language: delegated_operation_fixture.dig(:operation, :surface, :declared_language),
        effective_language: delegated_operation_fixture.dig(:operation, :surface, :effective_language),
        address: delegated_operation_fixture.dig(:operation, :surface, :address),
        parent_address: delegated_operation_fixture.dig(:operation, :surface, :parent_address),
        span: described_class.surface_span(
          start_line: delegated_operation_fixture.dig(:operation, :surface, :span, :start_line),
          end_line: delegated_operation_fixture.dig(:operation, :surface, :span, :end_line)
        ),
        owner: described_class.surface_owner_ref(
          kind: delegated_operation_fixture.dig(:operation, :surface, :owner, :kind),
          address: delegated_operation_fixture.dig(:operation, :surface, :owner, :address)
        ),
        reconstruction_strategy: delegated_operation_fixture.dig(:operation, :surface, :reconstruction_strategy),
        metadata: delegated_operation_fixture.dig(:operation, :surface, :metadata)
      )
    )
    expect(json_ready(delegated_operation)).to eq(json_ready(delegated_operation_fixture[:operation]))

    structured_edit_structure_profile_fixture[:cases].each do |entry|
      profile = described_class.structured_edit_structure_profile(
        owner_scope: entry.dig(:profile, :owner_scope),
        owner_selector: entry.dig(:profile, :owner_selector),
        owner_selector_family: entry.dig(:profile, :owner_selector_family),
        known_owner_selector: entry.dig(:profile, :known_owner_selector),
        supported_comment_regions: entry.dig(:profile, :supported_comment_regions),
        metadata: entry.dig(:profile, :metadata)
      )
      expect(json_ready(profile)).to eq(json_ready(entry[:profile]))
    end

    structured_edit_selection_profile_fixture[:cases].each do |entry|
      profile = described_class.structured_edit_selection_profile(
        owner_scope: entry.dig(:profile, :owner_scope),
        owner_selector: entry.dig(:profile, :owner_selector),
        owner_selector_family: entry.dig(:profile, :owner_selector_family),
        selector_kind: entry.dig(:profile, :selector_kind),
        selection_intent: entry.dig(:profile, :selection_intent),
        selection_intent_family: entry.dig(:profile, :selection_intent_family),
        known_selection_intent: entry.dig(:profile, :known_selection_intent),
        comment_region: entry.dig(:profile, :comment_region),
        include_trailing_gap: entry.dig(:profile, :include_trailing_gap),
        comment_anchored: entry.dig(:profile, :comment_anchored),
        metadata: entry.dig(:profile, :metadata)
      )
      expect(json_ready(profile)).to eq(json_ready(entry[:profile]))
    end

    structured_edit_match_profile_fixture[:cases].each do |entry|
      profile = described_class.structured_edit_match_profile(
        start_boundary: entry.dig(:profile, :start_boundary),
        start_boundary_family: entry.dig(:profile, :start_boundary_family),
        known_start_boundary: entry.dig(:profile, :known_start_boundary),
        end_boundary: entry.dig(:profile, :end_boundary),
        end_boundary_family: entry.dig(:profile, :end_boundary_family),
        known_end_boundary: entry.dig(:profile, :known_end_boundary),
        payload_kind: entry.dig(:profile, :payload_kind),
        payload_family: entry.dig(:profile, :payload_family),
        known_payload_kind: entry.dig(:profile, :known_payload_kind),
        comment_anchored: entry.dig(:profile, :comment_anchored),
        trailing_gap_extended: entry.dig(:profile, :trailing_gap_extended),
        metadata: entry.dig(:profile, :metadata)
      )
      expect(json_ready(profile)).to eq(json_ready(entry[:profile]))
    end

    structured_edit_operation_profile_fixture[:cases].each do |entry|
      profile = described_class.structured_edit_operation_profile(
        operation_kind: entry.dig(:profile, :operation_kind),
        operation_family: entry.dig(:profile, :operation_family),
        known_operation_kind: entry.dig(:profile, :known_operation_kind),
        source_requirement: entry.dig(:profile, :source_requirement),
        destination_requirement: entry.dig(:profile, :destination_requirement),
        replacement_source: entry.dig(:profile, :replacement_source),
        captures_source_text: entry.dig(:profile, :captures_source_text),
        supports_if_missing: entry.dig(:profile, :supports_if_missing),
        metadata: entry.dig(:profile, :metadata)
      )
      expect(json_ready(profile)).to eq(json_ready(entry[:profile]))
    end

    structured_edit_destination_profile_fixture[:cases].each do |entry|
      profile = described_class.structured_edit_destination_profile(
        resolution_kind: entry.dig(:profile, :resolution_kind),
        resolution_source: entry.dig(:profile, :resolution_source),
        anchor_boundary: entry.dig(:profile, :anchor_boundary),
        resolution_family: entry.dig(:profile, :resolution_family),
        resolution_source_family: entry.dig(:profile, :resolution_source_family),
        anchor_boundary_family: entry.dig(:profile, :anchor_boundary_family),
        known_resolution_kind: entry.dig(:profile, :known_resolution_kind),
        known_resolution_source: entry.dig(:profile, :known_resolution_source),
        known_anchor_boundary: entry.dig(:profile, :known_anchor_boundary),
        used_if_missing: entry.dig(:profile, :used_if_missing),
        metadata: entry.dig(:profile, :metadata)
      )
      expect(json_ready(profile)).to eq(json_ready(entry[:profile]))
    end

    structured_edit_request_fixture[:cases].each do |entry|
      request = described_class.structured_edit_request(
        operation_kind: entry.dig(:request, :operation_kind),
        content: entry.dig(:request, :content),
        source_label: entry.dig(:request, :source_label),
        target_selector: entry.dig(:request, :target_selector),
        target_selector_family: entry.dig(:request, :target_selector_family),
        destination_selector: entry.dig(:request, :destination_selector),
        destination_selector_family: entry.dig(:request, :destination_selector_family),
        payload_text: entry.dig(:request, :payload_text),
        if_missing: entry.dig(:request, :if_missing),
        metadata: entry.dig(:request, :metadata)
      )
      expect(json_ready(request)).to eq(json_ready(entry[:request]))
    end

    structured_edit_result_fixture[:cases].each do |entry|
      result = described_class.structured_edit_result(
        operation_kind: entry.dig(:result, :operation_kind),
        updated_content: entry.dig(:result, :updated_content),
        changed: entry.dig(:result, :changed),
        captured_text: entry.dig(:result, :captured_text),
        match_count: entry.dig(:result, :match_count),
        operation_profile: entry.dig(:result, :operation_profile),
        destination_profile: entry.dig(:result, :destination_profile),
        metadata: entry.dig(:result, :metadata)
      )
      expect(json_ready(result)).to eq(json_ready(entry[:result]))
    end

    structured_edit_application_fixture[:cases].each do |entry|
      application = described_class.structured_edit_application(
        request: entry.dig(:application, :request),
        result: entry.dig(:application, :result),
        metadata: entry.dig(:application, :metadata)
      )
      expect(json_ready(application)).to eq(json_ready(entry[:application]))
    end

    structured_edit_application_envelope = described_class.structured_edit_application_envelope(
      structured_edit_application_envelope_fixture[:structured_edit_application]
    )
    expect(json_ready(structured_edit_application_envelope)).to eq(
      json_ready(structured_edit_application_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_application, structured_edit_application_error =
      described_class.import_structured_edit_application_envelope(
        structured_edit_application_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_application_error).to be_nil
    expect(json_ready(imported_structured_edit_application)).to eq(
      json_ready(structured_edit_application_envelope_fixture[:structured_edit_application])
    )

    structured_edit_application_envelope_rejection_fixture[:cases].each do |test_case|
      _application, import_error = described_class.import_structured_edit_application_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_application, applied_structured_edit_error =
      described_class.import_structured_edit_application_envelope(
        structured_edit_application_envelope_application_fixture[:structured_edit_application_envelope]
      )
    expect(applied_structured_edit_error).to be_nil
    expect(json_ready(applied_structured_edit_application)).to eq(
      json_ready(structured_edit_application_envelope_application_fixture[:expected_application])
    )

    structured_edit_application_envelope_application_fixture[:cases].each do |test_case|
      _application, application_rejection_error =
        described_class.import_structured_edit_application_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_execution_report_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    structured_edit_provider_execution_request_fixture[:cases].each do |entry|
      execution_request = described_class.structured_edit_provider_execution_request(
        request: entry.dig(:execution_request, :request),
        provider_family: entry.dig(:execution_request, :provider_family),
        provider_backend: entry.dig(:execution_request, :provider_backend),
        metadata: entry.dig(:execution_request, :metadata)
      )
      expect(json_ready(execution_request)).to eq(json_ready(entry[:execution_request]))
    end

    structured_edit_provider_execution_request_envelope =
      described_class.structured_edit_provider_execution_request_envelope(
        structured_edit_provider_execution_request_envelope_fixture[:structured_edit_provider_execution_request]
      )
    expect(json_ready(structured_edit_provider_execution_request_envelope)).to eq(
      json_ready(structured_edit_provider_execution_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_request, structured_edit_provider_execution_request_error =
      described_class.import_structured_edit_provider_execution_request_envelope(
        structured_edit_provider_execution_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_request)).to eq(
      json_ready(structured_edit_provider_execution_request_envelope_fixture[:structured_edit_provider_execution_request])
    )

    structured_edit_provider_execution_request_envelope_rejection_fixture[:cases].each do |test_case|
      _execution_request, import_error =
        described_class.import_structured_edit_provider_execution_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_request, applied_structured_edit_provider_execution_request_error =
      described_class.import_structured_edit_provider_execution_request_envelope(
        structured_edit_provider_execution_request_envelope_application_fixture[:structured_edit_provider_execution_request_envelope]
      )
    expect(applied_structured_edit_provider_execution_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_request)).to eq(
      json_ready(structured_edit_provider_execution_request_envelope_application_fixture[:expected_execution_request])
    )

    structured_edit_provider_execution_request_envelope_application_fixture[:cases].each do |test_case|
      _execution_request, application_rejection_error =
        described_class.import_structured_edit_provider_execution_request_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_application_fixture[:cases].each do |entry|
      provider_execution_application = described_class.structured_edit_provider_execution_application(
        execution_request: entry.dig(:application, :execution_request),
        report: entry.dig(:application, :report),
        metadata: entry.dig(:application, :metadata)
      )
      expect(json_ready(provider_execution_application)).to eq(json_ready(entry[:application]))
    end

    structured_edit_provider_execution_dispatch_fixture[:cases].each do |entry|
      provider_execution_dispatch = described_class.structured_edit_provider_execution_dispatch(
        execution_request: entry.dig(:dispatch, :execution_request),
        resolved_provider_family: entry.dig(:dispatch, :resolved_provider_family),
        resolved_provider_backend: entry.dig(:dispatch, :resolved_provider_backend),
        executor_label: entry.dig(:dispatch, :executor_label),
        metadata: entry.dig(:dispatch, :metadata)
      )
      expect(json_ready(provider_execution_dispatch)).to eq(json_ready(entry[:dispatch]))
    end

    structured_edit_provider_execution_dispatch_envelope =
      described_class.structured_edit_provider_execution_dispatch_envelope(
        structured_edit_provider_execution_dispatch_envelope_fixture[:structured_edit_provider_execution_dispatch]
      )
    expect(json_ready(structured_edit_provider_execution_dispatch_envelope)).to eq(
      json_ready(structured_edit_provider_execution_dispatch_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_dispatch, structured_edit_provider_execution_dispatch_error =
      described_class.import_structured_edit_provider_execution_dispatch_envelope(
        structured_edit_provider_execution_dispatch_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_dispatch_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_dispatch)).to eq(
      json_ready(structured_edit_provider_execution_dispatch_envelope_fixture[:structured_edit_provider_execution_dispatch])
    )

    structured_edit_provider_execution_dispatch_envelope_rejection_fixture[:cases].each do |test_case|
      _provider_execution_dispatch, dispatch_rejection_error =
        described_class.import_structured_edit_provider_execution_dispatch_envelope(test_case[:envelope])
      expect(json_ready(dispatch_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_dispatch, applied_structured_edit_provider_execution_dispatch_error =
      described_class.import_structured_edit_provider_execution_dispatch_envelope(
        structured_edit_provider_execution_dispatch_envelope_application_fixture[:structured_edit_provider_execution_dispatch_envelope]
      )
    expect(applied_structured_edit_provider_execution_dispatch_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_dispatch)).to eq(
      json_ready(structured_edit_provider_execution_dispatch_envelope_application_fixture[:expected_dispatch])
    )

    structured_edit_provider_execution_dispatch_envelope_application_fixture[:cases].each do |test_case|
      _provider_execution_dispatch, dispatch_application_rejection_error =
        described_class.import_structured_edit_provider_execution_dispatch_envelope(test_case[:envelope])
      expect(json_ready(dispatch_application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_outcome_fixture[:cases].each do |entry|
      provider_execution_outcome = described_class.structured_edit_provider_execution_outcome(
        dispatch: entry.dig(:outcome, :dispatch),
        application: entry.dig(:outcome, :application),
        metadata: entry.dig(:outcome, :metadata)
      )
      expect(json_ready(provider_execution_outcome)).to eq(json_ready(entry[:outcome]))
    end

    structured_edit_provider_execution_outcome_envelope =
      described_class.structured_edit_provider_execution_outcome_envelope(
        structured_edit_provider_execution_outcome_envelope_fixture[:structured_edit_provider_execution_outcome]
      )
    expect(json_ready(structured_edit_provider_execution_outcome_envelope)).to eq(
      json_ready(structured_edit_provider_execution_outcome_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_outcome, structured_edit_provider_execution_outcome_error =
      described_class.import_structured_edit_provider_execution_outcome_envelope(
        structured_edit_provider_execution_outcome_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_outcome_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_outcome)).to eq(
      json_ready(structured_edit_provider_execution_outcome_envelope_fixture[:structured_edit_provider_execution_outcome])
    )

    structured_edit_provider_execution_outcome_envelope_rejection_fixture[:cases].each do |test_case|
      _provider_execution_outcome, import_error =
        described_class.import_structured_edit_provider_execution_outcome_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_outcome, applied_structured_edit_provider_execution_outcome_error =
      described_class.import_structured_edit_provider_execution_outcome_envelope(
        structured_edit_provider_execution_outcome_envelope_application_fixture[:structured_edit_provider_execution_outcome_envelope]
      )
    expect(applied_structured_edit_provider_execution_outcome_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_outcome)).to eq(
      json_ready(structured_edit_provider_execution_outcome_envelope_application_fixture[:expected_outcome])
    )

    structured_edit_provider_execution_outcome_envelope_application_fixture[:cases].each do |test_case|
      _provider_execution_outcome, application_rejection_error =
        described_class.import_structured_edit_provider_execution_outcome_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_outcome_fixture[:cases].each do |entry|
      batch_outcome = described_class.structured_edit_provider_batch_execution_outcome(
        outcomes: entry.dig(:batch_outcome, :outcomes),
        metadata: entry.dig(:batch_outcome, :metadata)
      )
      expect(json_ready(batch_outcome)).to eq(json_ready(entry[:batch_outcome]))
    end

    structured_edit_provider_batch_execution_outcome_envelope =
      described_class.structured_edit_provider_batch_execution_outcome_envelope(
        structured_edit_provider_batch_execution_outcome_envelope_fixture[:structured_edit_provider_batch_execution_outcome]
      )
    expect(json_ready(structured_edit_provider_batch_execution_outcome_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_outcome_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_outcome, structured_edit_provider_batch_execution_outcome_error =
      described_class.import_structured_edit_provider_batch_execution_outcome_envelope(
        structured_edit_provider_batch_execution_outcome_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_outcome_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_outcome)).to eq(
      json_ready(structured_edit_provider_batch_execution_outcome_envelope_fixture[:structured_edit_provider_batch_execution_outcome])
    )

    structured_edit_provider_batch_execution_outcome_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_outcome, import_error =
        described_class.import_structured_edit_provider_batch_execution_outcome_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_outcome, applied_structured_edit_provider_batch_execution_outcome_error =
      described_class.import_structured_edit_provider_batch_execution_outcome_envelope(
        structured_edit_provider_batch_execution_outcome_envelope_application_fixture[:structured_edit_provider_batch_execution_outcome_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_outcome_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_outcome)).to eq(
      json_ready(structured_edit_provider_batch_execution_outcome_envelope_application_fixture[:expected_batch_outcome])
    )

    structured_edit_provider_batch_execution_outcome_envelope_application_fixture[:cases].each do |test_case|
      _batch_outcome, application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_outcome_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_provenance_fixture[:cases].each do |entry|
      provenance = described_class.structured_edit_provider_execution_provenance(
        dispatch: entry.dig(:provenance, :dispatch),
        outcome: entry.dig(:provenance, :outcome),
        diagnostics: entry.dig(:provenance, :diagnostics),
        metadata: entry.dig(:provenance, :metadata)
      )
      expect(json_ready(provenance)).to eq(json_ready(entry[:provenance]))
    end

    structured_edit_provider_execution_provenance_envelope =
      described_class.structured_edit_provider_execution_provenance_envelope(
        structured_edit_provider_execution_provenance_envelope_fixture[:structured_edit_provider_execution_provenance]
      )
    expect(json_ready(structured_edit_provider_execution_provenance_envelope)).to eq(
      json_ready(structured_edit_provider_execution_provenance_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_provenance, structured_edit_provider_execution_provenance_error =
      described_class.import_structured_edit_provider_execution_provenance_envelope(
        structured_edit_provider_execution_provenance_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_provenance_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_provenance)).to eq(
      json_ready(structured_edit_provider_execution_provenance_envelope_fixture[:structured_edit_provider_execution_provenance])
    )

    structured_edit_provider_execution_provenance_envelope_rejection_fixture[:cases].each do |test_case|
      _provenance, import_error =
        described_class.import_structured_edit_provider_execution_provenance_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_provenance, applied_structured_edit_provider_execution_provenance_error =
      described_class.import_structured_edit_provider_execution_provenance_envelope(
        structured_edit_provider_execution_provenance_envelope_application_fixture[:structured_edit_provider_execution_provenance_envelope]
      )
    expect(applied_structured_edit_provider_execution_provenance_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_provenance)).to eq(
      json_ready(structured_edit_provider_execution_provenance_envelope_application_fixture[:expected_provenance])
    )

    structured_edit_provider_execution_provenance_envelope_application_fixture[:cases].each do |test_case|
      _provenance, application_rejection_error =
        described_class.import_structured_edit_provider_execution_provenance_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_provenance_fixture[:cases].each do |entry|
      batch_provenance = described_class.structured_edit_provider_batch_execution_provenance(
        provenances: entry.dig(:batch_provenance, :provenances),
        metadata: entry.dig(:batch_provenance, :metadata)
      )
      expect(json_ready(batch_provenance)).to eq(json_ready(entry[:batch_provenance]))
    end

    structured_edit_provider_batch_execution_provenance_envelope =
      described_class.structured_edit_provider_batch_execution_provenance_envelope(
        structured_edit_provider_batch_execution_provenance_envelope_fixture[:structured_edit_provider_batch_execution_provenance]
      )
    expect(json_ready(structured_edit_provider_batch_execution_provenance_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_provenance_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_provenance, structured_edit_provider_batch_execution_provenance_error =
      described_class.import_structured_edit_provider_batch_execution_provenance_envelope(
        structured_edit_provider_batch_execution_provenance_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_provenance_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_provenance)).to eq(
      json_ready(structured_edit_provider_batch_execution_provenance_envelope_fixture[:structured_edit_provider_batch_execution_provenance])
    )

    structured_edit_provider_batch_execution_provenance_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_provenance, import_error =
        described_class.import_structured_edit_provider_batch_execution_provenance_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_provenance, applied_structured_edit_provider_batch_execution_provenance_error =
      described_class.import_structured_edit_provider_batch_execution_provenance_envelope(
        structured_edit_provider_batch_execution_provenance_envelope_application_fixture[:structured_edit_provider_batch_execution_provenance_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_provenance_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_provenance)).to eq(
      json_ready(structured_edit_provider_batch_execution_provenance_envelope_application_fixture[:expected_batch_provenance])
    )

    structured_edit_provider_batch_execution_provenance_envelope_application_fixture[:cases].each do |test_case|
      _batch_provenance, application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_provenance_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_replay_bundle_fixture[:cases].each do |entry|
      replay_bundle = described_class.structured_edit_provider_execution_replay_bundle(
        execution_request: entry.dig(:replay_bundle, :execution_request),
        provenance: entry.dig(:replay_bundle, :provenance),
        metadata: entry.dig(:replay_bundle, :metadata)
      )
      expect(json_ready(replay_bundle)).to eq(json_ready(entry[:replay_bundle]))
    end

    structured_edit_provider_execution_replay_bundle_envelope =
      described_class.structured_edit_provider_execution_replay_bundle_envelope(
        structured_edit_provider_execution_replay_bundle_envelope_fixture[:structured_edit_provider_execution_replay_bundle]
      )
    expect(json_ready(structured_edit_provider_execution_replay_bundle_envelope)).to eq(
      json_ready(structured_edit_provider_execution_replay_bundle_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_replay_bundle, structured_edit_provider_execution_replay_bundle_error =
      described_class.import_structured_edit_provider_execution_replay_bundle_envelope(
        structured_edit_provider_execution_replay_bundle_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_replay_bundle_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_replay_bundle)).to eq(
      json_ready(structured_edit_provider_execution_replay_bundle_envelope_fixture[:structured_edit_provider_execution_replay_bundle])
    )

    structured_edit_provider_execution_replay_bundle_envelope_rejection_fixture[:cases].each do |test_case|
      _replay_bundle, import_error =
        described_class.import_structured_edit_provider_execution_replay_bundle_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_replay_bundle, applied_structured_edit_provider_execution_replay_bundle_error =
      described_class.import_structured_edit_provider_execution_replay_bundle_envelope(
        structured_edit_provider_execution_replay_bundle_envelope_application_fixture[:structured_edit_provider_execution_replay_bundle_envelope]
      )
    expect(applied_structured_edit_provider_execution_replay_bundle_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_replay_bundle)).to eq(
      json_ready(structured_edit_provider_execution_replay_bundle_envelope_application_fixture[:expected_replay_bundle])
    )

    structured_edit_provider_execution_replay_bundle_envelope_application_fixture[:cases].each do |test_case|
      _replay_bundle, application_rejection_error =
        described_class.import_structured_edit_provider_execution_replay_bundle_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_replay_bundle_fixture[:cases].each do |entry|
      batch_replay_bundle = described_class.structured_edit_provider_batch_execution_replay_bundle(
        replay_bundles: entry.dig(:batch_replay_bundle, :replay_bundles),
        metadata: entry.dig(:batch_replay_bundle, :metadata)
      )
      expect(json_ready(batch_replay_bundle)).to eq(json_ready(entry[:batch_replay_bundle]))
    end

    structured_edit_provider_batch_execution_replay_bundle_envelope =
      described_class.structured_edit_provider_batch_execution_replay_bundle_envelope(
        structured_edit_provider_batch_execution_replay_bundle_envelope_fixture[:structured_edit_provider_batch_execution_replay_bundle]
      )
    expect(json_ready(structured_edit_provider_batch_execution_replay_bundle_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_replay_bundle_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_replay_bundle, structured_edit_provider_batch_execution_replay_bundle_error =
      described_class.import_structured_edit_provider_batch_execution_replay_bundle_envelope(
        structured_edit_provider_batch_execution_replay_bundle_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_replay_bundle_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_replay_bundle)).to eq(
      json_ready(structured_edit_provider_batch_execution_replay_bundle_envelope_fixture[:structured_edit_provider_batch_execution_replay_bundle])
    )

    structured_edit_provider_batch_execution_replay_bundle_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_replay_bundle, import_error =
        described_class.import_structured_edit_provider_batch_execution_replay_bundle_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_replay_bundle, applied_structured_edit_provider_batch_execution_replay_bundle_error =
      described_class.import_structured_edit_provider_batch_execution_replay_bundle_envelope(
        structured_edit_provider_batch_execution_replay_bundle_envelope_application_fixture[:structured_edit_provider_batch_execution_replay_bundle_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_replay_bundle_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_replay_bundle)).to eq(
      json_ready(structured_edit_provider_batch_execution_replay_bundle_envelope_application_fixture[:expected_batch_replay_bundle])
    )

    structured_edit_provider_batch_execution_replay_bundle_envelope_application_fixture[:cases].each do |test_case|
      _batch_replay_bundle, application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_replay_bundle_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_executor_profile_fixture[:cases].each do |entry|
      executor_profile = described_class.structured_edit_provider_executor_profile(
        provider_family: entry.dig(:executor_profile, :provider_family),
        provider_backend: entry.dig(:executor_profile, :provider_backend),
        executor_label: entry.dig(:executor_profile, :executor_label),
        structure_profile: entry.dig(:executor_profile, :structure_profile),
        selection_profile: entry.dig(:executor_profile, :selection_profile),
        match_profile: entry.dig(:executor_profile, :match_profile),
        operation_profiles: entry.dig(:executor_profile, :operation_profiles),
        destination_profile: entry.dig(:executor_profile, :destination_profile),
        metadata: entry.dig(:executor_profile, :metadata)
      )
      expect(json_ready(executor_profile)).to eq(json_ready(entry[:executor_profile]))
    end

    structured_edit_provider_executor_profile_envelope =
      described_class.structured_edit_provider_executor_profile_envelope(
        structured_edit_provider_executor_profile_envelope_fixture[:structured_edit_provider_executor_profile]
      )
    expect(json_ready(structured_edit_provider_executor_profile_envelope)).to eq(
      json_ready(structured_edit_provider_executor_profile_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_executor_profile, structured_edit_provider_executor_profile_error =
      described_class.import_structured_edit_provider_executor_profile_envelope(
        structured_edit_provider_executor_profile_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_executor_profile_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_executor_profile)).to eq(
      json_ready(structured_edit_provider_executor_profile_envelope_fixture[:structured_edit_provider_executor_profile])
    )

    structured_edit_provider_executor_profile_envelope_rejection_fixture[:cases].each do |test_case|
      _executor_profile, import_error =
        described_class.import_structured_edit_provider_executor_profile_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_executor_profile, applied_structured_edit_provider_executor_profile_error =
      described_class.import_structured_edit_provider_executor_profile_envelope(
        structured_edit_provider_executor_profile_envelope_application_fixture[:structured_edit_provider_executor_profile_envelope]
      )
    expect(applied_structured_edit_provider_executor_profile_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_executor_profile)).to eq(
      json_ready(structured_edit_provider_executor_profile_envelope_application_fixture[:expected_executor_profile])
    )

    structured_edit_provider_executor_profile_envelope_application_fixture[:cases].each do |test_case|
      _executor_profile, application_rejection_error =
        described_class.import_structured_edit_provider_executor_profile_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_executor_registry_fixture[:cases].each do |entry|
      executor_registry = described_class.structured_edit_provider_executor_registry(
        executor_profiles: entry.dig(:executor_registry, :executor_profiles),
        metadata: entry.dig(:executor_registry, :metadata)
      )
      expect(json_ready(executor_registry)).to eq(json_ready(entry[:executor_registry]))
    end

    structured_edit_provider_executor_registry_envelope =
      described_class.structured_edit_provider_executor_registry_envelope(
        structured_edit_provider_executor_registry_envelope_fixture[:structured_edit_provider_executor_registry]
      )
    expect(json_ready(structured_edit_provider_executor_registry_envelope)).to eq(
      json_ready(structured_edit_provider_executor_registry_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_executor_registry, structured_edit_provider_executor_registry_error =
      described_class.import_structured_edit_provider_executor_registry_envelope(
        structured_edit_provider_executor_registry_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_executor_registry_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_executor_registry)).to eq(
      json_ready(structured_edit_provider_executor_registry_envelope_fixture[:structured_edit_provider_executor_registry])
    )

    structured_edit_provider_executor_registry_envelope_rejection_fixture[:cases].each do |test_case|
      _executor_registry, import_error =
        described_class.import_structured_edit_provider_executor_registry_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_executor_registry, applied_structured_edit_provider_executor_registry_error =
      described_class.import_structured_edit_provider_executor_registry_envelope(
        structured_edit_provider_executor_registry_envelope_application_fixture[:structured_edit_provider_executor_registry_envelope]
      )
    expect(applied_structured_edit_provider_executor_registry_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_executor_registry)).to eq(
      json_ready(structured_edit_provider_executor_registry_envelope_application_fixture[:expected_executor_registry])
    )

    structured_edit_provider_executor_registry_envelope_application_fixture[:cases].each do |test_case|
      _executor_registry, application_rejection_error =
        described_class.import_structured_edit_provider_executor_registry_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_executor_selection_policy_fixture[:cases].each do |entry|
      selection_policy = described_class.structured_edit_provider_executor_selection_policy(
        provider_family: entry.dig(:selection_policy, :provider_family),
        provider_backend: entry.dig(:selection_policy, :provider_backend),
        executor_label: entry.dig(:selection_policy, :executor_label),
        selection_mode: entry.dig(:selection_policy, :selection_mode),
        allow_registry_fallback: entry.dig(:selection_policy, :allow_registry_fallback),
        metadata: entry.dig(:selection_policy, :metadata)
      )
      expect(json_ready(selection_policy)).to eq(json_ready(entry[:selection_policy]))
    end

    structured_edit_provider_executor_selection_policy_envelope =
      described_class.structured_edit_provider_executor_selection_policy_envelope(
        structured_edit_provider_executor_selection_policy_envelope_fixture[:structured_edit_provider_executor_selection_policy]
      )
    expect(json_ready(structured_edit_provider_executor_selection_policy_envelope)).to eq(
      json_ready(structured_edit_provider_executor_selection_policy_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_executor_selection_policy, structured_edit_provider_executor_selection_policy_error =
      described_class.import_structured_edit_provider_executor_selection_policy_envelope(
        structured_edit_provider_executor_selection_policy_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_executor_selection_policy_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_executor_selection_policy)).to eq(
      json_ready(structured_edit_provider_executor_selection_policy_envelope_fixture[:structured_edit_provider_executor_selection_policy])
    )

    structured_edit_provider_executor_selection_policy_envelope_rejection_fixture[:cases].each do |test_case|
      _selection_policy, import_error =
        described_class.import_structured_edit_provider_executor_selection_policy_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_executor_selection_policy, applied_structured_edit_provider_executor_selection_policy_error =
      described_class.import_structured_edit_provider_executor_selection_policy_envelope(
        structured_edit_provider_executor_selection_policy_envelope_application_fixture[:structured_edit_provider_executor_selection_policy_envelope]
      )
    expect(applied_structured_edit_provider_executor_selection_policy_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_executor_selection_policy)).to eq(
      json_ready(structured_edit_provider_executor_selection_policy_envelope_application_fixture[:expected_selection_policy])
    )

    structured_edit_provider_executor_selection_policy_envelope_application_fixture[:cases].each do |test_case|
      _selection_policy, application_rejection_error =
        described_class.import_structured_edit_provider_executor_selection_policy_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_executor_resolution_fixture[:cases].each do |entry|
      executor_resolution = described_class.structured_edit_provider_executor_resolution(
        executor_registry: entry.dig(:executor_resolution, :executor_registry),
        selection_policy: entry.dig(:executor_resolution, :selection_policy),
        selected_executor_profile: entry.dig(:executor_resolution, :selected_executor_profile),
        metadata: entry.dig(:executor_resolution, :metadata)
      )
      expect(json_ready(executor_resolution)).to eq(json_ready(entry[:executor_resolution]))
    end

    structured_edit_provider_executor_resolution_envelope =
      described_class.structured_edit_provider_executor_resolution_envelope(
        structured_edit_provider_executor_resolution_envelope_fixture[:structured_edit_provider_executor_resolution]
      )
    expect(json_ready(structured_edit_provider_executor_resolution_envelope)).to eq(
      json_ready(structured_edit_provider_executor_resolution_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_executor_resolution, structured_edit_provider_executor_resolution_error =
      described_class.import_structured_edit_provider_executor_resolution_envelope(
        structured_edit_provider_executor_resolution_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_executor_resolution_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_executor_resolution)).to eq(
      json_ready(structured_edit_provider_executor_resolution_envelope_fixture[:structured_edit_provider_executor_resolution])
    )

    structured_edit_provider_executor_resolution_envelope_rejection_fixture[:cases].each do |test_case|
      _executor_resolution, import_error =
        described_class.import_structured_edit_provider_executor_resolution_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_executor_resolution, applied_structured_edit_provider_executor_resolution_error =
      described_class.import_structured_edit_provider_executor_resolution_envelope(
        structured_edit_provider_executor_resolution_envelope_application_fixture[:structured_edit_provider_executor_resolution_envelope]
      )
    expect(applied_structured_edit_provider_executor_resolution_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_executor_resolution)).to eq(
      json_ready(structured_edit_provider_executor_resolution_envelope_application_fixture[:expected_executor_resolution])
    )

    structured_edit_provider_executor_resolution_envelope_application_fixture[:cases].each do |test_case|
      _executor_resolution, application_rejection_error =
        described_class.import_structured_edit_provider_executor_resolution_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_plan_fixture[:cases].each do |entry|
      execution_plan = described_class.structured_edit_provider_execution_plan(
        execution_request: entry.dig(:execution_plan, :execution_request),
        executor_resolution: entry.dig(:execution_plan, :executor_resolution),
        metadata: entry.dig(:execution_plan, :metadata)
      )
      expect(json_ready(execution_plan)).to eq(json_ready(entry[:execution_plan]))
    end

    structured_edit_provider_execution_handoff_fixture[:cases].each do |entry|
      execution_handoff = described_class.structured_edit_provider_execution_handoff(
        execution_plan: entry.dig(:execution_handoff, :execution_plan),
        execution_dispatch: entry.dig(:execution_handoff, :execution_dispatch),
        metadata: entry.dig(:execution_handoff, :metadata)
      )
      expect(json_ready(execution_handoff)).to eq(json_ready(entry[:execution_handoff]))
    end

    structured_edit_provider_execution_handoff_envelope =
      described_class.structured_edit_provider_execution_handoff_envelope(
        structured_edit_provider_execution_handoff_envelope_fixture[:structured_edit_provider_execution_handoff]
      )
    expect(json_ready(structured_edit_provider_execution_handoff_envelope)).to eq(
      json_ready(structured_edit_provider_execution_handoff_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_handoff, structured_edit_provider_execution_handoff_error =
      described_class.import_structured_edit_provider_execution_handoff_envelope(
        structured_edit_provider_execution_handoff_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_handoff_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_handoff)).to eq(
      json_ready(structured_edit_provider_execution_handoff_envelope_fixture[:structured_edit_provider_execution_handoff])
    )

    structured_edit_provider_execution_handoff_envelope_rejection_fixture[:cases].each do |test_case|
      _execution_handoff, import_error =
        described_class.import_structured_edit_provider_execution_handoff_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_handoff, applied_structured_edit_provider_execution_handoff_error =
      described_class.import_structured_edit_provider_execution_handoff_envelope(
        structured_edit_provider_execution_handoff_envelope_application_fixture[:structured_edit_provider_execution_handoff_envelope]
      )
    expect(applied_structured_edit_provider_execution_handoff_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_handoff)).to eq(
      json_ready(structured_edit_provider_execution_handoff_envelope_application_fixture[:expected_execution_handoff])
    )

    structured_edit_provider_execution_handoff_envelope_application_fixture[:cases].each do |test_case|
      _execution_handoff, application_rejection_error =
        described_class.import_structured_edit_provider_execution_handoff_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_invocation_fixture[:cases].each do |entry|
      execution_invocation = described_class.structured_edit_provider_execution_invocation(
        execution_handoff: entry.dig(:execution_invocation, :execution_handoff),
        metadata: entry.dig(:execution_invocation, :metadata)
      )
      expect(json_ready(execution_invocation)).to eq(json_ready(entry[:execution_invocation]))
    end

    structured_edit_provider_execution_invocation_envelope =
      described_class.structured_edit_provider_execution_invocation_envelope(
        structured_edit_provider_execution_invocation_envelope_fixture[:structured_edit_provider_execution_invocation]
      )
    expect(json_ready(structured_edit_provider_execution_invocation_envelope)).to eq(
      json_ready(structured_edit_provider_execution_invocation_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_invocation, structured_edit_provider_execution_invocation_error =
      described_class.import_structured_edit_provider_execution_invocation_envelope(
        structured_edit_provider_execution_invocation_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_invocation_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_invocation)).to eq(
      json_ready(structured_edit_provider_execution_invocation_envelope_fixture[:structured_edit_provider_execution_invocation])
    )

    structured_edit_provider_execution_invocation_envelope_rejection_fixture[:cases].each do |test_case|
      _execution_invocation, import_error =
        described_class.import_structured_edit_provider_execution_invocation_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_invocation, applied_structured_edit_provider_execution_invocation_error =
      described_class.import_structured_edit_provider_execution_invocation_envelope(
        structured_edit_provider_execution_invocation_envelope_application_fixture[:structured_edit_provider_execution_invocation_envelope]
      )
    expect(applied_structured_edit_provider_execution_invocation_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_invocation)).to eq(
      json_ready(structured_edit_provider_execution_invocation_envelope_application_fixture[:expected_execution_invocation])
    )

    structured_edit_provider_execution_invocation_envelope_application_fixture[:cases].each do |test_case|
      _execution_invocation, execution_invocation_rejection_error =
        described_class.import_structured_edit_provider_execution_invocation_envelope(test_case[:envelope])
      expect(json_ready(execution_invocation_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_invocation_fixture[:cases].each do |entry|
      batch_execution_invocation = described_class.structured_edit_provider_batch_execution_invocation(
        invocations: entry.dig(:batch_execution_invocation, :invocations),
        metadata: entry.dig(:batch_execution_invocation, :metadata)
      )
      expect(json_ready(batch_execution_invocation)).to eq(json_ready(entry[:batch_execution_invocation]))
    end

    structured_edit_provider_batch_execution_invocation_envelope =
      described_class.structured_edit_provider_batch_execution_invocation_envelope(
        structured_edit_provider_batch_execution_invocation_envelope_fixture[:structured_edit_provider_batch_execution_invocation]
      )
    expect(json_ready(structured_edit_provider_batch_execution_invocation_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_invocation_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_invocation, structured_edit_provider_batch_execution_invocation_error =
      described_class.import_structured_edit_provider_batch_execution_invocation_envelope(
        structured_edit_provider_batch_execution_invocation_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_invocation_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_invocation)).to eq(
      json_ready(structured_edit_provider_batch_execution_invocation_envelope_fixture[:structured_edit_provider_batch_execution_invocation])
    )

    structured_edit_provider_batch_execution_invocation_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_execution_invocation, import_error =
        described_class.import_structured_edit_provider_batch_execution_invocation_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_invocation, applied_structured_edit_provider_batch_execution_invocation_error =
      described_class.import_structured_edit_provider_batch_execution_invocation_envelope(
        structured_edit_provider_batch_execution_invocation_envelope_application_fixture[:structured_edit_provider_batch_execution_invocation_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_invocation_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_invocation)).to eq(
      json_ready(structured_edit_provider_batch_execution_invocation_envelope_application_fixture[:expected_batch_execution_invocation])
    )

    structured_edit_provider_batch_execution_invocation_envelope_application_fixture[:cases].each do |test_case|
      _batch_execution_invocation, batch_execution_invocation_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_invocation_envelope(test_case[:envelope])
      expect(json_ready(batch_execution_invocation_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_run_result_fixture[:cases].each do |entry|
      execution_run_result = described_class.structured_edit_provider_execution_run_result(
        execution_invocation: entry.dig(:execution_run_result, :execution_invocation),
        outcome: entry.dig(:execution_run_result, :outcome),
        metadata: entry.dig(:execution_run_result, :metadata)
      )
      expect(json_ready(execution_run_result)).to eq(json_ready(entry[:execution_run_result]))
    end

    structured_edit_provider_execution_run_result_envelope =
      described_class.structured_edit_provider_execution_run_result_envelope(
        structured_edit_provider_execution_run_result_envelope_fixture[:structured_edit_provider_execution_run_result]
      )
    expect(json_ready(structured_edit_provider_execution_run_result_envelope)).to eq(
      json_ready(structured_edit_provider_execution_run_result_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_run_result, structured_edit_provider_execution_run_result_error =
      described_class.import_structured_edit_provider_execution_run_result_envelope(
        structured_edit_provider_execution_run_result_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_run_result_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_run_result)).to eq(
      json_ready(structured_edit_provider_execution_run_result_envelope_fixture[:structured_edit_provider_execution_run_result])
    )

    structured_edit_provider_execution_run_result_envelope_rejection_fixture[:cases].each do |test_case|
      _execution_run_result, import_error =
        described_class.import_structured_edit_provider_execution_run_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_run_result, applied_structured_edit_provider_execution_run_result_error =
      described_class.import_structured_edit_provider_execution_run_result_envelope(
        structured_edit_provider_execution_run_result_envelope_application_fixture[:structured_edit_provider_execution_run_result_envelope]
      )
    expect(applied_structured_edit_provider_execution_run_result_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_run_result)).to eq(
      json_ready(structured_edit_provider_execution_run_result_envelope_application_fixture[:expected_execution_run_result])
    )

    structured_edit_provider_execution_run_result_envelope_application_fixture[:cases].each do |test_case|
      _execution_run_result, execution_run_result_rejection_error =
        described_class.import_structured_edit_provider_execution_run_result_envelope(test_case[:envelope])
      expect(json_ready(execution_run_result_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_run_result_fixture[:cases].each do |entry|
      batch_execution_run_result = described_class.structured_edit_provider_batch_execution_run_result(
        run_results: entry.dig(:batch_execution_run_result, :run_results),
        metadata: entry.dig(:batch_execution_run_result, :metadata)
      )
      expect(json_ready(batch_execution_run_result)).to eq(json_ready(entry[:batch_execution_run_result]))
    end

    structured_edit_provider_batch_execution_run_result_envelope =
      described_class.structured_edit_provider_batch_execution_run_result_envelope(
        structured_edit_provider_batch_execution_run_result_envelope_fixture[:structured_edit_provider_batch_execution_run_result]
      )
    expect(json_ready(structured_edit_provider_batch_execution_run_result_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_run_result_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_run_result, structured_edit_provider_batch_execution_run_result_error =
      described_class.import_structured_edit_provider_batch_execution_run_result_envelope(
        structured_edit_provider_batch_execution_run_result_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_run_result_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_run_result)).to eq(
      json_ready(structured_edit_provider_batch_execution_run_result_envelope_fixture[:structured_edit_provider_batch_execution_run_result])
    )

    structured_edit_provider_batch_execution_run_result_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_execution_run_result, import_error =
        described_class.import_structured_edit_provider_batch_execution_run_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_run_result, applied_structured_edit_provider_batch_execution_run_result_error =
      described_class.import_structured_edit_provider_batch_execution_run_result_envelope(
        structured_edit_provider_batch_execution_run_result_envelope_application_fixture[:structured_edit_provider_batch_execution_run_result_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_run_result_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_run_result)).to eq(
      json_ready(structured_edit_provider_batch_execution_run_result_envelope_application_fixture[:expected_batch_execution_run_result])
    )

    structured_edit_provider_batch_execution_run_result_envelope_application_fixture[:cases].each do |test_case|
      _batch_execution_run_result, batch_execution_run_result_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_run_result_envelope(test_case[:envelope])
      expect(json_ready(batch_execution_run_result_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_fixture[:cases].each do |entry|
      execution_receipt = described_class.structured_edit_provider_execution_receipt(
        run_result: entry.dig(:execution_receipt, :run_result),
        provenance: entry.dig(:execution_receipt, :provenance),
        replay_bundle: entry.dig(:execution_receipt, :replay_bundle),
        metadata: entry.dig(:execution_receipt, :metadata)
      )
      expect(json_ready(execution_receipt)).to eq(json_ready(entry[:execution_receipt]))
    end

    structured_edit_provider_execution_receipt_envelope =
      described_class.structured_edit_provider_execution_receipt_envelope(
        structured_edit_provider_execution_receipt_envelope_fixture[:structured_edit_provider_execution_receipt]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt, structured_edit_provider_execution_receipt_error =
      described_class.import_structured_edit_provider_execution_receipt_envelope(
        structured_edit_provider_execution_receipt_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt)).to eq(
      json_ready(structured_edit_provider_execution_receipt_envelope_fixture[:structured_edit_provider_execution_receipt])
    )

    structured_edit_provider_execution_receipt_envelope_rejection_fixture[:cases].each do |test_case|
      _execution_receipt, import_error =
        described_class.import_structured_edit_provider_execution_receipt_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt, applied_structured_edit_provider_execution_receipt_error =
      described_class.import_structured_edit_provider_execution_receipt_envelope(
        structured_edit_provider_execution_receipt_envelope_application_fixture[:structured_edit_provider_execution_receipt_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt)).to eq(
      json_ready(structured_edit_provider_execution_receipt_envelope_application_fixture[:expected_execution_receipt])
    )

    structured_edit_provider_execution_receipt_envelope_application_fixture[:cases].each do |test_case|
      _execution_receipt, execution_receipt_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_envelope(test_case[:envelope])
      expect(json_ready(execution_receipt_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_fixture[:cases].each do |entry|
      batch_execution_receipt = described_class.structured_edit_provider_batch_execution_receipt(
        receipts: entry.dig(:batch_execution_receipt, :receipts),
        metadata: entry.dig(:batch_execution_receipt, :metadata)
      )
      expect(json_ready(batch_execution_receipt)).to eq(json_ready(entry[:batch_execution_receipt]))
    end

    structured_edit_provider_batch_execution_receipt_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_envelope(
        structured_edit_provider_batch_execution_receipt_envelope_fixture[:structured_edit_provider_batch_execution_receipt]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt, structured_edit_provider_batch_execution_receipt_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_envelope(
        structured_edit_provider_batch_execution_receipt_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_envelope_fixture[:structured_edit_provider_batch_execution_receipt])
    )

    structured_edit_provider_batch_execution_receipt_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_execution_receipt, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt, applied_structured_edit_provider_batch_execution_receipt_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_envelope(
        structured_edit_provider_batch_execution_receipt_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_envelope_application_fixture[:expected_batch_execution_receipt])
    )

    structured_edit_provider_batch_execution_receipt_envelope_application_fixture[:cases].each do |test_case|
      _batch_execution_receipt, batch_execution_receipt_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_envelope(test_case[:envelope])
      expect(json_ready(batch_execution_receipt_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_request_fixture[:cases].each do |entry|
      receipt_replay_request = described_class.structured_edit_provider_execution_receipt_replay_request(
        execution_receipt: entry.dig(:receipt_replay_request, :execution_receipt),
        replay_mode: entry.dig(:receipt_replay_request, :replay_mode),
        metadata: entry.dig(:receipt_replay_request, :metadata)
      )
      expect(json_ready(receipt_replay_request)).to eq(json_ready(entry[:receipt_replay_request]))
    end

    structured_edit_provider_execution_receipt_replay_request_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_request_envelope(
        structured_edit_provider_execution_receipt_replay_request_envelope_fixture[:structured_edit_provider_execution_receipt_replay_request]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_request_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_request, structured_edit_provider_execution_receipt_replay_request_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_request_envelope(
        structured_edit_provider_execution_receipt_replay_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_request)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_request_envelope_fixture[:structured_edit_provider_execution_receipt_replay_request])
    )

    structured_edit_provider_execution_receipt_replay_request_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_request, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_request, applied_structured_edit_provider_execution_receipt_replay_request_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_request_envelope(
        structured_edit_provider_execution_receipt_replay_request_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_request_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_request)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_request_envelope_application_fixture[:expected_receipt_replay_request])
    )

    structured_edit_provider_execution_receipt_replay_request_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_request, receipt_replay_request_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_request_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_request_fixture[:cases].each do |entry|
      batch_receipt_replay_request = described_class.structured_edit_provider_batch_execution_receipt_replay_request(
        requests: entry.dig(:batch_receipt_replay_request, :requests),
        metadata: entry.dig(:batch_receipt_replay_request, :metadata)
      )
      expect(json_ready(batch_receipt_replay_request)).to eq(json_ready(entry[:batch_receipt_replay_request]))
    end

    structured_edit_provider_batch_execution_receipt_replay_request_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_request_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_request]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_request_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_request, structured_edit_provider_batch_execution_receipt_replay_request_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_request_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_request])
    )

    structured_edit_provider_batch_execution_receipt_replay_request_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_request, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_request, applied_structured_edit_provider_batch_execution_receipt_replay_request_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_request_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_request_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_request_envelope_application_fixture[:expected_batch_receipt_replay_request])
    )

    structured_edit_provider_batch_execution_receipt_replay_request_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_request, batch_receipt_replay_request_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_request_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_handoff_fixture[:cases].each do |entry|
      batch_execution_handoff = described_class.structured_edit_provider_batch_execution_handoff(
        handoffs: entry.dig(:batch_execution_handoff, :handoffs),
        metadata: entry.dig(:batch_execution_handoff, :metadata)
      )
      expect(json_ready(batch_execution_handoff)).to eq(json_ready(entry[:batch_execution_handoff]))
    end

    structured_edit_provider_batch_execution_handoff_envelope =
      described_class.structured_edit_provider_batch_execution_handoff_envelope(
        structured_edit_provider_batch_execution_handoff_envelope_fixture[:structured_edit_provider_batch_execution_handoff]
      )
    expect(json_ready(structured_edit_provider_batch_execution_handoff_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_handoff_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_handoff, structured_edit_provider_batch_execution_handoff_error =
      described_class.import_structured_edit_provider_batch_execution_handoff_envelope(
        structured_edit_provider_batch_execution_handoff_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_handoff_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_handoff)).to eq(
      json_ready(structured_edit_provider_batch_execution_handoff_envelope_fixture[:structured_edit_provider_batch_execution_handoff])
    )

    structured_edit_provider_batch_execution_handoff_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_execution_handoff, import_error =
        described_class.import_structured_edit_provider_batch_execution_handoff_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_handoff, applied_structured_edit_provider_batch_execution_handoff_error =
      described_class.import_structured_edit_provider_batch_execution_handoff_envelope(
        structured_edit_provider_batch_execution_handoff_envelope_application_fixture[:structured_edit_provider_batch_execution_handoff_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_handoff_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_handoff)).to eq(
      json_ready(structured_edit_provider_batch_execution_handoff_envelope_application_fixture[:expected_batch_execution_handoff])
    )

    structured_edit_provider_batch_execution_handoff_envelope_application_fixture[:cases].each do |test_case|
      _batch_execution_handoff, batch_execution_handoff_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_handoff_envelope(test_case[:envelope])
      expect(json_ready(batch_execution_handoff_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_plan_envelope =
      described_class.structured_edit_provider_execution_plan_envelope(
        structured_edit_provider_execution_plan_envelope_fixture[:structured_edit_provider_execution_plan]
      )
    expect(json_ready(structured_edit_provider_execution_plan_envelope)).to eq(
      json_ready(structured_edit_provider_execution_plan_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_plan, structured_edit_provider_execution_plan_error =
      described_class.import_structured_edit_provider_execution_plan_envelope(
        structured_edit_provider_execution_plan_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_plan_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_plan)).to eq(
      json_ready(structured_edit_provider_execution_plan_envelope_fixture[:structured_edit_provider_execution_plan])
    )

    structured_edit_provider_execution_plan_envelope_rejection_fixture[:cases].each do |test_case|
      _execution_plan, import_error =
        described_class.import_structured_edit_provider_execution_plan_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_plan, applied_structured_edit_provider_execution_plan_error =
      described_class.import_structured_edit_provider_execution_plan_envelope(
        structured_edit_provider_execution_plan_envelope_application_fixture[:structured_edit_provider_execution_plan_envelope]
      )
    expect(applied_structured_edit_provider_execution_plan_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_plan)).to eq(
      json_ready(structured_edit_provider_execution_plan_envelope_application_fixture[:expected_execution_plan])
    )

    structured_edit_provider_execution_plan_envelope_application_fixture[:cases].each do |test_case|
      _execution_plan, application_rejection_error =
        described_class.import_structured_edit_provider_execution_plan_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_plan_fixture[:cases].each do |entry|
      batch_execution_plan = described_class.structured_edit_provider_batch_execution_plan(
        plans: entry.dig(:batch_execution_plan, :plans),
        metadata: entry.dig(:batch_execution_plan, :metadata)
      )
      expect(json_ready(batch_execution_plan)).to eq(json_ready(entry[:batch_execution_plan]))
    end

    structured_edit_provider_batch_execution_plan_envelope =
      described_class.structured_edit_provider_batch_execution_plan_envelope(
        structured_edit_provider_batch_execution_plan_envelope_fixture[:structured_edit_provider_batch_execution_plan]
      )
    expect(json_ready(structured_edit_provider_batch_execution_plan_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_plan_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_plan, structured_edit_provider_batch_execution_plan_error =
      described_class.import_structured_edit_provider_batch_execution_plan_envelope(
        structured_edit_provider_batch_execution_plan_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_plan_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_plan)).to eq(
      json_ready(structured_edit_provider_batch_execution_plan_envelope_fixture[:structured_edit_provider_batch_execution_plan])
    )

    structured_edit_provider_batch_execution_plan_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_execution_plan, import_error =
        described_class.import_structured_edit_provider_batch_execution_plan_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_plan, applied_structured_edit_provider_batch_execution_plan_error =
      described_class.import_structured_edit_provider_batch_execution_plan_envelope(
        structured_edit_provider_batch_execution_plan_envelope_application_fixture[:structured_edit_provider_batch_execution_plan_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_plan_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_plan)).to eq(
      json_ready(structured_edit_provider_batch_execution_plan_envelope_application_fixture[:expected_batch_execution_plan])
    )

    structured_edit_provider_batch_execution_plan_envelope_application_fixture[:cases].each do |test_case|
      _batch_execution_plan, batch_execution_plan_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_plan_envelope(test_case[:envelope])
      expect(json_ready(batch_execution_plan_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_application_envelope =
      described_class.structured_edit_provider_execution_application_envelope(
        structured_edit_provider_execution_application_envelope_fixture[:structured_edit_provider_execution_application]
      )
    expect(json_ready(structured_edit_provider_execution_application_envelope)).to eq(
      json_ready(structured_edit_provider_execution_application_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_application, structured_edit_provider_execution_application_error =
      described_class.import_structured_edit_provider_execution_application_envelope(
        structured_edit_provider_execution_application_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_application_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_application)).to eq(
      json_ready(structured_edit_provider_execution_application_envelope_fixture[:structured_edit_provider_execution_application])
    )

    structured_edit_provider_execution_application_envelope_rejection_fixture[:cases].each do |test_case|
      _provider_execution_application, import_error =
        described_class.import_structured_edit_provider_execution_application_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_application, applied_structured_edit_provider_execution_application_error =
      described_class.import_structured_edit_provider_execution_application_envelope(
        structured_edit_provider_execution_application_envelope_application_fixture[:structured_edit_provider_execution_application_envelope]
      )
    expect(applied_structured_edit_provider_execution_application_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_application)).to eq(
      json_ready(structured_edit_provider_execution_application_envelope_application_fixture[:expected_application])
    )

    structured_edit_provider_execution_application_envelope_application_fixture[:cases].each do |test_case|
      _provider_execution_application, application_rejection_error =
        described_class.import_structured_edit_provider_execution_application_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_execution_report_envelope = described_class.structured_edit_execution_report_envelope(
      structured_edit_execution_report_envelope_fixture[:structured_edit_execution_report]
    )
    expect(json_ready(structured_edit_execution_report_envelope)).to eq(
      json_ready(structured_edit_execution_report_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_execution_report, structured_edit_execution_report_error =
      described_class.import_structured_edit_execution_report_envelope(
        structured_edit_execution_report_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_execution_report_error).to be_nil
    expect(json_ready(imported_structured_edit_execution_report)).to eq(
      json_ready(structured_edit_execution_report_envelope_fixture[:structured_edit_execution_report])
    )

    structured_edit_execution_report_envelope_rejection_fixture[:cases].each do |test_case|
      _report, import_error = described_class.import_structured_edit_execution_report_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_execution_report, applied_structured_edit_execution_report_error =
      described_class.import_structured_edit_execution_report_envelope(
        structured_edit_execution_report_envelope_application_fixture[:structured_edit_execution_report_envelope]
      )
    expect(applied_structured_edit_execution_report_error).to be_nil
    expect(json_ready(applied_structured_edit_execution_report)).to eq(
      json_ready(structured_edit_execution_report_envelope_application_fixture[:expected_report])
    )

    structured_edit_execution_report_envelope_application_fixture[:cases].each do |test_case|
      _report, application_rejection_error =
        described_class.import_structured_edit_execution_report_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_batch_request_fixture[:cases].each do |entry|
      batch_request = described_class.structured_edit_batch_request(
        requests: entry.dig(:batch_request, :requests),
        metadata: entry.dig(:batch_request, :metadata)
      )
      expect(json_ready(batch_request)).to eq(json_ready(entry[:batch_request]))
    end

    structured_edit_provider_batch_execution_request_fixture[:cases].each do |entry|
      batch_execution_request = described_class.structured_edit_provider_batch_execution_request(
        requests: entry.dig(:batch_execution_request, :requests),
        metadata: entry.dig(:batch_execution_request, :metadata)
      )
      expect(json_ready(batch_execution_request)).to eq(json_ready(entry[:batch_execution_request]))
    end

    structured_edit_provider_batch_execution_request_envelope =
      described_class.structured_edit_provider_batch_execution_request_envelope(
        structured_edit_provider_batch_execution_request_envelope_fixture[:structured_edit_provider_batch_execution_request]
      )
    expect(json_ready(structured_edit_provider_batch_execution_request_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_request, structured_edit_provider_batch_execution_request_error =
      described_class.import_structured_edit_provider_batch_execution_request_envelope(
        structured_edit_provider_batch_execution_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_request_envelope_fixture[:structured_edit_provider_batch_execution_request])
    )

    structured_edit_provider_batch_execution_request_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_execution_request, import_error =
        described_class.import_structured_edit_provider_batch_execution_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_request, applied_structured_edit_provider_batch_execution_request_error =
      described_class.import_structured_edit_provider_batch_execution_request_envelope(
        structured_edit_provider_batch_execution_request_envelope_application_fixture[:structured_edit_provider_batch_execution_request_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_request_envelope_application_fixture[:expected_batch_execution_request])
    )

    structured_edit_provider_batch_execution_request_envelope_application_fixture[:cases].each do |test_case|
      _batch_execution_request, application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_request_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_dispatch_fixture[:cases].each do |entry|
      batch_execution_dispatch = described_class.structured_edit_provider_batch_execution_dispatch(
        dispatches: entry.dig(:batch_dispatch, :dispatches),
        metadata: entry.dig(:batch_dispatch, :metadata)
      )
      expect(json_ready(batch_execution_dispatch)).to eq(json_ready(entry[:batch_dispatch]))
    end

    structured_edit_provider_batch_execution_dispatch_envelope =
      described_class.structured_edit_provider_batch_execution_dispatch_envelope(
        structured_edit_provider_batch_execution_dispatch_envelope_fixture[:structured_edit_provider_batch_execution_dispatch]
      )
    expect(json_ready(structured_edit_provider_batch_execution_dispatch_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_dispatch_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_dispatch, structured_edit_provider_batch_execution_dispatch_error =
      described_class.import_structured_edit_provider_batch_execution_dispatch_envelope(
        structured_edit_provider_batch_execution_dispatch_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_dispatch_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_dispatch)).to eq(
      json_ready(structured_edit_provider_batch_execution_dispatch_envelope_fixture[:structured_edit_provider_batch_execution_dispatch])
    )

    structured_edit_provider_batch_execution_dispatch_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_dispatch, import_error =
        described_class.import_structured_edit_provider_batch_execution_dispatch_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_dispatch, applied_structured_edit_provider_batch_execution_dispatch_error =
      described_class.import_structured_edit_provider_batch_execution_dispatch_envelope(
        structured_edit_provider_batch_execution_dispatch_envelope_application_fixture[:structured_edit_provider_batch_execution_dispatch_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_dispatch_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_dispatch)).to eq(
      json_ready(structured_edit_provider_batch_execution_dispatch_envelope_application_fixture[:expected_batch_dispatch])
    )

    structured_edit_provider_batch_execution_dispatch_envelope_application_fixture[:cases].each do |test_case|
      _batch_dispatch, application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_dispatch_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_report_fixture[:cases].each do |entry|
      provider_batch_execution_report = described_class.structured_edit_provider_batch_execution_report(
        applications: entry.dig(:batch_report, :applications),
        diagnostics: entry.dig(:batch_report, :diagnostics),
        metadata: entry.dig(:batch_report, :metadata)
      )
      expect(json_ready(provider_batch_execution_report)).to eq(json_ready(entry[:batch_report]))
    end

    structured_edit_provider_batch_execution_report_envelope =
      described_class.structured_edit_provider_batch_execution_report_envelope(
        structured_edit_provider_batch_execution_report_envelope_fixture[:structured_edit_provider_batch_execution_report]
      )
    expect(json_ready(structured_edit_provider_batch_execution_report_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_report_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_report, structured_edit_provider_batch_execution_report_error =
      described_class.import_structured_edit_provider_batch_execution_report_envelope(
        structured_edit_provider_batch_execution_report_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_report_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_report)).to eq(
      json_ready(structured_edit_provider_batch_execution_report_envelope_fixture[:structured_edit_provider_batch_execution_report])
    )

    structured_edit_provider_batch_execution_report_envelope_rejection_fixture[:cases].each do |test_case|
      _provider_batch_execution_report, import_error =
        described_class.import_structured_edit_provider_batch_execution_report_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_report, applied_structured_edit_provider_batch_execution_report_error =
      described_class.import_structured_edit_provider_batch_execution_report_envelope(
        structured_edit_provider_batch_execution_report_envelope_application_fixture[:structured_edit_provider_batch_execution_report_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_report_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_report)).to eq(
      json_ready(structured_edit_provider_batch_execution_report_envelope_application_fixture[:expected_batch_report])
    )

    structured_edit_provider_batch_execution_report_envelope_application_fixture[:cases].each do |test_case|
      _provider_batch_execution_report, application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_report_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_batch_report_fixture[:cases].each do |entry|
      batch_report = described_class.structured_edit_batch_report(
        reports: entry.dig(:batch_report, :reports),
        diagnostics: entry.dig(:batch_report, :diagnostics),
        metadata: entry.dig(:batch_report, :metadata)
      )
      expect(json_ready(batch_report)).to eq(json_ready(entry[:batch_report]))
    end

    structured_edit_batch_report_envelope = described_class.structured_edit_batch_report_envelope(
      structured_edit_batch_report_envelope_fixture[:structured_edit_batch_report]
    )
    expect(json_ready(structured_edit_batch_report_envelope)).to eq(
      json_ready(structured_edit_batch_report_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_batch_report, structured_edit_batch_report_error =
      described_class.import_structured_edit_batch_report_envelope(
        structured_edit_batch_report_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_batch_report_error).to be_nil
    expect(json_ready(imported_structured_edit_batch_report)).to eq(
      json_ready(structured_edit_batch_report_envelope_fixture[:structured_edit_batch_report])
    )

    structured_edit_batch_report_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_report, import_error = described_class.import_structured_edit_batch_report_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_batch_report, applied_structured_edit_batch_report_error =
      described_class.import_structured_edit_batch_report_envelope(
        structured_edit_batch_report_envelope_application_fixture[:structured_edit_batch_report_envelope]
      )
    expect(applied_structured_edit_batch_report_error).to be_nil
    expect(json_ready(applied_structured_edit_batch_report)).to eq(
      json_ready(structured_edit_batch_report_envelope_application_fixture[:expected_batch_report])
    )

    structured_edit_batch_report_envelope_application_fixture[:cases].each do |test_case|
      _batch_report, application_rejection_error =
        described_class.import_structured_edit_batch_report_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    projected_cases = projected_cases_fixture[:cases].map do |entry|
      described_class.projected_child_review_case(
        case_id: entry[:case_id],
        parent_operation_id: entry[:parent_operation_id],
        child_operation_id: entry[:child_operation_id],
        surface_path: entry[:surface_path],
        delegated_case_id: entry[:delegated_case_id],
        delegated_apply_group: entry[:delegated_apply_group],
        delegated_runtime_surface_path: entry[:delegated_runtime_surface_path]
      )
    end
    expect(json_ready(projected_cases)).to eq(json_ready(projected_cases_fixture[:cases]))
  end

  it "conforms to the slice-227 projected child-review groups fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-227-projected-child-review-groups",
        "projected-child-review-groups.json"
      )
    )

    grouped = described_class.group_projected_child_review_cases(fixture[:cases])
    expect(json_ready(grouped)).to eq(json_ready(fixture[:expected_groups]))
  end

  it "conforms to the slice-230 projected child-review group progress fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-230-projected-child-review-group-progress",
        "projected-child-review-group-progress.json"
      )
    )

    progress = described_class.summarize_projected_child_review_group_progress(
      fixture[:groups],
      fixture[:resolved_case_ids]
    )
    expect(json_ready(progress)).to eq(json_ready(fixture[:expected_progress]))
  end

  it "conforms to the slice-233 projected child-review groups ready-for-apply fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-233-projected-child-review-groups-ready-for-apply",
        "projected-child-review-groups-ready-for-apply.json"
      )
    )

    ready_groups = described_class.select_projected_child_review_groups_ready_for_apply(
      fixture[:groups],
      fixture[:resolved_case_ids]
    )
    expect(json_ready(ready_groups)).to eq(json_ready(fixture[:expected_ready_groups]))
  end

  it "conforms to the slice-236 delegated child group review request fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-236-delegated-child-group-review-request",
        "delegated-child-group-review-request.json"
      )
    )

    expect(described_class.review_request_id_for_projected_child_group(fixture[:group])).to eq(
      fixture.dig(:expected_request, :id)
    )
    expect(
      json_ready(
        described_class.projected_child_group_review_request(fixture[:group], fixture[:family])
      )
    ).to eq(json_ready(fixture[:expected_request]))
  end

  it "conforms to the slice-237 delegated child groups accepted-for-apply fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-237-delegated-child-group-accepted-for-apply",
        "delegated-child-groups-accepted-for-apply.json"
      )
    )

    expect(
      json_ready(
        described_class.select_projected_child_review_groups_accepted_for_apply(
          fixture[:groups],
          fixture[:family],
          fixture[:decisions]
        )
      )
    ).to eq(json_ready(fixture[:expected_accepted_groups]))
  end

  it "conforms to the slice-240 delegated child group review-state fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-240-delegated-child-group-review-state",
        "delegated-child-group-review-state.json"
      )
    )

    expect(
      json_ready(
        described_class.review_projected_child_groups(
          fixture[:groups],
          fixture[:family],
          fixture[:decisions]
        )
      )
    ).to eq(json_ready(fixture[:expected_state]))
  end

  it "conforms to the slice-243 delegated child apply-plan fixture" do
    fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-243-delegated-child-apply-plan",
        "delegated-child-apply-plan.json"
      )
    )

    expect(
      json_ready(
        described_class.delegated_child_apply_plan(
          fixture[:review_state],
          fixture[:family]
        )
      )
    ).to eq(json_ready(fixture[:expected_plan]))
  end

  it "conforms to the slice-292 delegated child nested-output resolution fixture" do
    fixture = diagnostics_fixture("delegated_child_nested_output_resolution")

    expect(
      json_ready(
        described_class.resolve_delegated_child_outputs(
          fixture[:operations],
          fixture[:nested_outputs],
          default_family: fixture[:default_family],
          request_id_prefix: fixture[:request_id_prefix]
        )
      )
    ).to eq(json_ready(fixture[:expected]))
  end

  it "conforms to the slice-293 delegated child nested-output rejection fixture" do
    fixture = diagnostics_fixture("delegated_child_nested_output_rejection")

    expect(
      json_ready(
        described_class.resolve_delegated_child_outputs(
          fixture[:operations],
          fixture[:nested_outputs],
          default_family: fixture[:default_family],
          request_id_prefix: fixture[:request_id_prefix]
        )
      )
    ).to eq(json_ready(fixture[:expected]))
  end

  it "conforms to the slice-303 reviewed nested execution payload fixture" do
    fixture = diagnostics_fixture("reviewed_nested_execution_payload")

    expect(
      json_ready(
        described_class.reviewed_nested_execution(
          fixture[:family],
          fixture[:review_state],
          fixture[:applied_children]
        )
      )
    ).to eq(json_ready(fixture[:expected_execution]))
  end

  it "executes nested merge through merge, discovery, resolution, and apply" do
    nested_outputs = [
      {
        surface_address: "document[0] > fenced_code_block[/code_fence/0]",
        output: "export const feature = true;\n"
      }
    ]
    calls = []

    result = described_class.execute_nested_merge(
      nested_outputs,
      default_family: "markdown",
      request_id_prefix: "nested_markdown_child",
      merge_parent: lambda {
        calls << "merge"
        { ok: true, diagnostics: [], output: "merged-parent", policies: [] }
      },
      discover_operations: lambda { |merged_output|
        calls << "discover:#{merged_output}"
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{nested_outputs.first[:surface_address]}",
              parent_operation_id: "parent:merge",
              requested_strategy: "delegate_child_surface",
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: "fenced_code_block",
                effective_language: "typescript",
                address: nested_outputs.first[:surface_address],
                owner: { kind: "owned_region", address: "/code_fence/0" },
                reconstruction_strategy: "portable_write",
                metadata: { family: "typescript" }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, applied_children|
        calls << "apply:#{merged_output}"
        expect(operations.first[:operation_id]).to eq("operation:#{nested_outputs.first[:surface_address]}")
        expect(apply_plan.dig(:entries, 0, :family)).to eq("typescript")
        expect(applied_children.first[:operation_id]).to eq("operation:#{nested_outputs.first[:surface_address]}")
        { ok: true, diagnostics: [], output: "final-parent", policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: "final-parent", policies: []))
    expect(calls).to eq(["merge", "discover:merged-parent", "apply:merged-parent"])
  end

  it "returns nested parent-merge failure unchanged and skips later stages" do
    called = false

    result = described_class.execute_nested_merge(
      [],
      default_family: "markdown",
      request_id_prefix: "nested",
      merge_parent: lambda {
        {
          ok: false,
          diagnostics: [{ severity: "error", category: "parse_error", message: "parent failed" }],
          policies: []
        }
      },
      discover_operations: lambda { |_merged_output|
        called = true
        { ok: true, diagnostics: [], operations: [] }
      },
      apply_resolved_outputs: lambda {
        called = true
        { ok: true, diagnostics: [], output: "unused", policies: [] }
      }
    )

    expect(result[:ok]).to eq(false)
    expect(called).to eq(false)
  end

  it "executes delegated child apply plan through merge, discovery, and apply" do
    address = "document[0] > fenced_code_block[/code_fence/0]"

    result = described_class.execute_delegated_child_apply_plan(
      {
        entries: [
          {
            request_id: "projected_child_group:markdown:fence:typescript",
            family: "markdown",
            delegated_group: {
              delegated_apply_group: "markdown:fence:typescript",
              parent_operation_id: "parent:merge",
              child_operation_id: "operation:#{address}",
              delegated_runtime_surface_path: address,
              case_ids: [],
              delegated_case_ids: []
            },
            decision: {
              request_id: "projected_child_group:markdown:fence:typescript",
              action: "apply_delegated_child_group"
            }
          }
        ]
      },
      [{ operation_id: "operation:#{address}", output: "child-output\n" }],
      merge_parent: lambda {
        { ok: true, diagnostics: [], output: "merged-parent", policies: [] }
      },
      discover_operations: lambda { |_merged_output|
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{address}",
              parent_operation_id: "parent:merge",
              requested_strategy: "delegate_child_surface",
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: "fenced_code_block",
                effective_language: "typescript",
                address: address,
                owner: { kind: "owned_region", address: "/code_fence/0" },
                reconstruction_strategy: "portable_write",
                metadata: { family: "typescript" }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |_merged_output, _operations, apply_plan, applied_children|
        expect(apply_plan[:entries].length).to eq(1)
        expect(applied_children).to eq([{ operation_id: "operation:#{address}", output: "child-output\n" }])
        { ok: true, diagnostics: [], output: "final-parent", policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: "final-parent", policies: []))
  end

  it "executes reviewed nested merge from accepted review state" do
    address = "document[0] > fenced_code_block[/code_fence/0]"

    result = described_class.execute_reviewed_nested_merge(
      {
        requests: [],
        accepted_groups: [
          {
            delegated_apply_group: "markdown:fence:typescript",
            parent_operation_id: "parent:merge",
            child_operation_id: "operation:#{address}",
            delegated_runtime_surface_path: address,
            case_ids: [],
            delegated_case_ids: []
          }
        ],
        applied_decisions: [
          {
            request_id: "projected_child_group:markdown:fence:typescript",
            action: "apply_delegated_child_group"
          }
        ],
        diagnostics: []
      },
      "markdown",
      [{ operation_id: "operation:#{address}", output: "child-output\n" }],
      merge_parent: lambda {
        { ok: true, diagnostics: [], output: "merged-parent", policies: [] }
      },
      discover_operations: lambda { |_merged_output|
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{address}",
              parent_operation_id: "parent:merge",
              requested_strategy: "delegate_child_surface",
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: "fenced_code_block",
                effective_language: "typescript",
                address: address,
                owner: { kind: "owned_region", address: "/code_fence/0" },
                reconstruction_strategy: "portable_write",
                metadata: { family: "typescript" }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |_merged_output, _operations, apply_plan, _applied_children|
        expect(apply_plan.dig(:entries, 0, :request_id)).to eq("projected_child_group:markdown:fence:typescript")
        { ok: true, diagnostics: [], output: "final-parent", policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: "final-parent", policies: []))
  end

  it "executes reviewed nested execution payload directly" do
    address = "document[0] > fenced_code_block[/code_fence/0]"

    result = described_class.execute_reviewed_nested_execution(
      described_class.reviewed_nested_execution(
        "markdown",
        {
          requests: [],
          accepted_groups: [
            {
              delegated_apply_group: "markdown:fence:typescript",
              parent_operation_id: "parent:merge",
              child_operation_id: "operation:#{address}",
              delegated_runtime_surface_path: address,
              case_ids: [],
              delegated_case_ids: []
            }
          ],
          applied_decisions: [
            {
              request_id: "projected_child_group:markdown:fence:typescript",
              action: "apply_delegated_child_group"
            }
          ],
          diagnostics: []
        },
        [{ operation_id: "operation:#{address}", output: "child-output\n" }]
      ),
      merge_parent: lambda {
        { ok: true, diagnostics: [], output: "merged-parent", policies: [] }
      },
      discover_operations: lambda { |_merged_output|
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{address}",
              parent_operation_id: "parent:merge",
              requested_strategy: "delegate_child_surface",
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: "fenced_code_block",
                effective_language: "typescript",
                address: address,
                owner: { kind: "owned_region", address: "/code_fence/0" },
                reconstruction_strategy: "portable_write",
                metadata: { family: "typescript" }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |_merged_output, _operations, apply_plan, applied_children|
        expect(apply_plan.dig(:entries, 0, :request_id)).to eq("projected_child_group:markdown:fence:typescript")
        expect(applied_children).to eq([{ operation_id: "operation:#{address}", output: "child-output\n" }])
        { ok: true, diagnostics: [], output: "final-parent", policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: "final-parent", policies: []))
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

  it "conforms to the source-family suite-definition and named-suite plan fixtures" do
    suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-125-source-family-suite-definitions", "source-suite-definitions.json")
    )
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(
      json_ready(suite_fixture[:suite_selectors])
    )
    expect(
      described_class.conformance_suite_definition(
        suite_fixture[:manifest],
        suite_fixture[:suite_selectors].first
      )
    ).to eq(suite_fixture[:suite_definitions].first)

    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-126-source-family-named-suite-plans", "source-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    native_plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-127-source-family-native-suite-plans", "source-native-named-suite-plans.json")
    )
    expect(
      json_ready(
        described_class.plan_named_conformance_suites(
          native_plans_fixture[:manifest],
          native_plans_fixture[:contexts]
        )
      )
    ).to eq(json_ready(native_plans_fixture[:expected_entries]))
  end

  it "conforms to the source-family backend-restricted plan and report fixtures" do
    plans_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-129-source-family-backend-restricted-plans",
        "source-backend-restricted-plans.json"
      )
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-130-source-family-backend-restricted-report",
        "source-backend-restricted-report.json"
      )
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it "conforms to the TOML family suite-definition, named-suite plan, and manifest report fixtures" do
    suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-138-toml-family-suite-definitions", "toml-suite-definitions.json")
    )
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(json_ready(suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest], suite_fixture[:suite_selectors].first)).to eq(
      suite_fixture[:suite_definitions].first
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
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(json_ready(suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest], suite_fixture[:suite_selectors].first)).to eq(
      suite_fixture[:suite_definitions].first
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

  it "conforms to the Markdown family suite-definition, named-suite plan, and manifest report fixtures" do
    suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-200-markdown-family-suite-definitions", "markdown-suite-definitions.json")
    )
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(json_ready(suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest], suite_fixture[:suite_selectors].first)).to eq(
      suite_fixture[:suite_definitions].first
    )

    plans_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-201-markdown-family-named-suite-plans",
        "ruby-markdown-named-suite-plans.json"
      )
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-202-markdown-family-manifest-report",
        "ruby-markdown-manifest-report.json"
      )
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

  it "conforms to the slice-246 through slice-251 nested Markdown and Ruby suite fixtures" do
    markdown_suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-246-markdown-nested-suite-definitions", "markdown-nested-suite-definitions.json")
    )
    expect(json_ready(described_class.conformance_suite_selectors(markdown_suite_fixture[:manifest]))).to eq(json_ready(markdown_suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(markdown_suite_fixture[:manifest], markdown_suite_fixture[:suite_selectors].first)).to eq(
      markdown_suite_fixture[:suite_definitions].first
    )

    markdown_plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-247-markdown-nested-named-suite-plans", "markdown-nested-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(markdown_plans_fixture[:manifest], markdown_plans_fixture[:contexts]))
    ).to eq(json_ready(markdown_plans_fixture[:expected_entries]))

    markdown_report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-248-markdown-nested-manifest-report", "markdown-nested-manifest-report.json")
    )
    markdown_report = described_class.report_conformance_manifest(
      markdown_report_fixture[:manifest],
      markdown_report_fixture[:options],
      &execute_from(markdown_report_fixture[:executions])
    )
    expect(json_ready(markdown_report)).to eq(json_ready(markdown_report_fixture[:expected_report]))

    ruby_suite_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-249-ruby-nested-suite-definitions", "ruby-nested-suite-definitions.json")
    )
    expect(json_ready(described_class.conformance_suite_selectors(ruby_suite_fixture[:manifest]))).to eq(json_ready(ruby_suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(ruby_suite_fixture[:manifest], ruby_suite_fixture[:suite_selectors].first)).to eq(
      ruby_suite_fixture[:suite_definitions].first
    )

    ruby_plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-250-ruby-nested-named-suite-plans", "ruby-nested-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(ruby_plans_fixture[:manifest], ruby_plans_fixture[:contexts]))
    ).to eq(json_ready(ruby_plans_fixture[:expected_entries]))

    ruby_report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-251-ruby-nested-manifest-report", "ruby-nested-manifest-report.json")
    )
    ruby_report = described_class.report_conformance_manifest(
      ruby_report_fixture[:manifest],
      ruby_report_fixture[:options],
      &execute_from(ruby_report_fixture[:executions])
    )
    expect(json_ready(ruby_report)).to eq(json_ready(ruby_report_fixture[:expected_report]))
  end

  it "conforms to the polyglot YAML family named-suite plan and manifest report fixtures" do
    plans_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-185-yaml-family-polyglot-backend-named-suite-plans", "ruby-yaml-polyglot-named-suite-plans.json")
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-186-yaml-family-polyglot-backend-manifest-report", "ruby-yaml-polyglot-manifest-report.json")
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
    expect(json_ready(described_class.conformance_suite_selectors(manifest_fixture[:manifest]))).to eq(json_ready(manifest_fixture[:suite_selectors]))

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
    [
      [
        "slice-178-canonical-widened-suite-backend-plans",
        "ruby-canonical-widened-suite-backend-plans.json",
        "slice-179-canonical-widened-suite-backend-report",
        "ruby-canonical-widened-suite-backend-report.json",
        %w[
          slice-180-canonical-widened-suite-backend-review-state/ruby-canonical-widened-suite-backend-review-state.json
          slice-181-canonical-widened-suite-backend-reviewed-default/ruby-canonical-widened-suite-backend-reviewed-default.json
          slice-182-canonical-widened-suite-backend-replay-application/ruby-canonical-widened-suite-backend-replay-application.json
        ]
      ],
      [
        "slice-187-canonical-widened-suite-polyglot-backend-plans",
        "ruby-canonical-widened-suite-polyglot-backend-plans.json",
        "slice-188-canonical-widened-suite-polyglot-backend-report",
        "ruby-canonical-widened-suite-polyglot-backend-report.json",
        %w[
          slice-189-canonical-widened-suite-polyglot-backend-review-state/ruby-canonical-widened-suite-polyglot-backend-review-state.json
          slice-190-canonical-widened-suite-polyglot-backend-reviewed-default/ruby-canonical-widened-suite-polyglot-backend-reviewed-default.json
          slice-191-canonical-widened-suite-polyglot-backend-replay-application/ruby-canonical-widened-suite-polyglot-backend-replay-application.json
        ]
      ]
    ].each do |plans_slice, plans_file, report_slice, report_file, review_paths|
      plans_fixture = read_json(fixtures_root.join("diagnostics", plans_slice, plans_file))
      expect(
        json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
      ).to eq(json_ready(plans_fixture[:expected_entries]))

      report_fixture = read_json(fixtures_root.join("diagnostics", report_slice, report_file))
      report = described_class.report_conformance_manifest(
        report_fixture[:manifest],
        report_fixture[:options],
        &execute_from(report_fixture[:executions])
      )
      expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

      review_paths.each do |relative_path|
        fixture = read_json(fixtures_root.join("diagnostics", relative_path))
        state = described_class.review_conformance_manifest(
          fixture[:manifest],
          fixture[:options],
          &execute_from(fixture[:executions])
        )
        expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
      end
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

    %w[
      slice-192-backend-sensitive-aggregate-tree-sitter-review-state/backend-sensitive-aggregate-tree-sitter-review-state.json
      slice-193-backend-sensitive-aggregate-native-review-state/backend-sensitive-aggregate-native-review-state.json
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
end
