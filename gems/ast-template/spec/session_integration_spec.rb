# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Ast::Template do
  let(:repo_root) { Pathname(__dir__).join("../../../..").expand_path }
  let(:fixture_dir) { repo_root.join("fixtures/diagnostics/slice-353-template-directory-session-report") }
  let(:fixture) { JSON.parse(fixture_dir.join("template-directory-session-report.json").read, symbolize_names: true) }

  def json_ready(value)
    JSON.parse(JSON.generate(value), symbolize_names: true)
  end

  def repo_temp_dir(name)
    root = repo_root.join("ruby/gems/ast-template/tmp")
    FileUtils.mkdir_p(root)
    Pathname(Dir.mktmpdir(name, root.to_s))
  end

  def merge_callback(entry)
    family = entry.dig(:classification, :family)
    case family
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
                        message: "missing family merge adapter for #{family}" }],
        policies: []
      }
    end
  end

  it "conforms to the template directory session report fixture" do
    dry_run = fixture[:dry_run]
    dry_run_actual = described_class.plan_template_directory_session_from_directories(
      fixture_dir.join("dry-run", "template"),
      fixture_dir.join("dry-run", "destination"),
      dry_run[:context],
      dry_run[:default_strategy],
      dry_run[:overrides],
      dry_run[:replacements]
    )
    expect(json_ready(dry_run_actual)).to eq(json_ready(dry_run[:expected]))

    temp_dir = repo_temp_dir("session")
    destination_root = temp_dir.join("destination")
    begin
      Ast::Merge.write_relative_file_tree(
        destination_root,
        Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
      )

      apply_run = fixture[:apply_run]
      apply_actual = described_class.apply_template_directory_session_to_directory(
        fixture_dir.join("apply-run", "template"),
        destination_root,
        apply_run[:context],
        apply_run[:default_strategy],
        apply_run[:overrides],
        apply_run[:replacements]
      ) { |entry| merge_callback(entry) }
      expect(json_ready(apply_actual)).to eq(json_ready(apply_run[:expected]))

      reapply_run = fixture[:reapply_run]
      reapply_actual = described_class.reapply_template_directory_session_to_directory(
        fixture_dir.join("apply-run", "template"),
        destination_root,
        reapply_run[:context],
        reapply_run[:default_strategy],
        reapply_run[:overrides],
        reapply_run[:replacements]
      ) { |entry| merge_callback(entry) }
      expect(json_ready(reapply_actual)).to eq(json_ready(reapply_run[:expected]))
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the template directory adapter registry report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-354-template-directory-adapter-registry-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-adapter-registry-report.json").read, symbolize_names: true)

    full_registry = {
      "markdown" => method(:markdown_adapter).to_proc,
      "ruby" => method(:ruby_adapter).to_proc,
      "toml" => method(:toml_adapter).to_proc
    }
    partial_registry = {
      "markdown" => method(:markdown_adapter).to_proc,
      "toml" => method(:toml_adapter).to_proc
    }

    {
      full_registry: full_registry,
      partial_registry: partial_registry
    }.each do |key, registry|
      temp_dir = repo_temp_dir("registry")
      destination_root = temp_dir.join("destination")
      begin
        Ast::Merge.write_relative_file_tree(
          destination_root,
          Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
        )

        actual = described_class.apply_template_directory_session_with_registry_to_directory(
          fixture_dir.join("apply-run", "template"),
          destination_root,
          fixture.dig(key, :context),
          fixture.dig(key, :default_strategy),
          fixture.dig(key, :overrides),
          fixture.dig(key, :replacements),
          registry
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      ensure
        temp_dir.rmtree if temp_dir.exist?
      end
    end
  end

  it "conforms to the template directory default adapter discovery report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-355-template-directory-default-adapter-discovery-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-default-adapter-discovery-report.json").read, symbolize_names: true)

    %i[default_discovery filtered_discovery].each do |key|
      temp_dir = repo_temp_dir("discovery")
      destination_root = temp_dir.join("destination")
      begin
        Ast::Merge.write_relative_file_tree(
          destination_root,
          Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
        )

        actual = described_class.apply_template_directory_session_with_default_registry_to_directory(
          fixture_dir.join("apply-run", "template"),
          destination_root,
          fixture.dig(key, :context),
          fixture.dig(key, :default_strategy),
          fixture.dig(key, :overrides),
          fixture.dig(key, :replacements),
          fixture.dig(key, :allowed_families)
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      ensure
        temp_dir.rmtree if temp_dir.exist?
      end
    end
  end

  it "conforms to the template directory adapter capability report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-356-template-directory-adapter-capability-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-adapter-capability-report.json").read, symbolize_names: true)

    full_registry = {
      "markdown" => method(:markdown_adapter).to_proc,
      "ruby" => method(:ruby_adapter).to_proc,
      "toml" => method(:toml_adapter).to_proc
    }
    partial_registry = {
      "markdown" => method(:markdown_adapter).to_proc,
      "toml" => method(:toml_adapter).to_proc
    }

    expect(
      json_ready(
        described_class.report_adapter_capabilities_from_directories(
          fixture_dir.join("apply-run", "template"),
          fixture_dir.join("apply-run", "destination"),
          fixture.dig(:full_registry, :context),
          fixture.dig(:full_registry, :default_strategy),
          fixture.dig(:full_registry, :overrides),
          fixture.dig(:full_registry, :replacements),
          full_registry
        )
      )
    ).to eq(json_ready(fixture.dig(:full_registry, :expected)))

    expect(
      json_ready(
        described_class.report_adapter_capabilities_from_directories(
          fixture_dir.join("apply-run", "template"),
          fixture_dir.join("apply-run", "destination"),
          fixture.dig(:partial_registry, :context),
          fixture.dig(:partial_registry, :default_strategy),
          fixture.dig(:partial_registry, :overrides),
          fixture.dig(:partial_registry, :replacements),
          partial_registry
        )
      )
    ).to eq(json_ready(fixture.dig(:partial_registry, :expected)))

    expect(
      json_ready(
        described_class.report_default_adapter_capabilities_from_directories(
          fixture_dir.join("apply-run", "template"),
          fixture_dir.join("apply-run", "destination"),
          fixture.dig(:filtered_discovery, :context),
          fixture.dig(:filtered_discovery, :default_strategy),
          fixture.dig(:filtered_discovery, :overrides),
          fixture.dig(:filtered_discovery, :replacements),
          fixture.dig(:filtered_discovery, :allowed_families)
        )
      )
    ).to eq(json_ready(fixture.dig(:filtered_discovery, :expected)))
  end

  it "conforms to the template directory session envelope report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-357-template-directory-session-envelope-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-envelope-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.plan_template_directory_session_envelope_from_directories(
          fixture_dir.join("dry-run", "template"),
          fixture_dir.join("dry-run", "destination"),
          fixture.dig(:dry_run, :context),
          fixture.dig(:dry_run, :default_strategy),
          fixture.dig(:dry_run, :overrides),
          fixture.dig(:dry_run, :replacements),
          fixture.dig(:dry_run, :allowed_families)
        )
      )
    ).to eq(json_ready(fixture.dig(:dry_run, :expected)))

    %i[apply_run filtered_discovery].each do |key|
      temp_dir = repo_temp_dir("envelope")
      destination_root = temp_dir.join("destination")
      begin
        Ast::Merge.write_relative_file_tree(
          destination_root,
          Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
        )

        actual = described_class.apply_template_directory_session_envelope_with_default_registry_to_directory(
          fixture_dir.join("apply-run", "template"),
          destination_root,
          fixture.dig(key, :context),
          fixture.dig(key, :default_strategy),
          fixture.dig(key, :overrides),
          fixture.dig(key, :replacements),
          fixture.dig(key, :allowed_families)
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      ensure
        temp_dir.rmtree if temp_dir.exist?
      end
    end
  end

  it "conforms to the template directory session status report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-358-template-directory-session-status-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-status-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.report_template_directory_session_status(
          described_class.plan_template_directory_session_envelope_from_directories(
            fixture_dir.join("dry-run", "template"),
            fixture_dir.join("dry-run", "destination"),
            fixture.dig(:dry_run, :context),
            fixture.dig(:dry_run, :default_strategy),
            fixture.dig(:dry_run, :overrides),
            fixture.dig(:dry_run, :replacements),
            fixture.dig(:dry_run, :allowed_families)
          )
        )
      )
    ).to eq(json_ready(fixture.dig(:dry_run, :expected)))

    %i[apply_run filtered_discovery].each do |key|
      temp_dir = repo_temp_dir("status")
      destination_root = temp_dir.join("destination")
      begin
        Ast::Merge.write_relative_file_tree(
          destination_root,
          Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
        )

        actual = described_class.report_template_directory_session_status(
          described_class.apply_template_directory_session_envelope_with_default_registry_to_directory(
            fixture_dir.join("apply-run", "template"),
            destination_root,
            fixture.dig(key, :context),
            fixture.dig(key, :default_strategy),
            fixture.dig(key, :overrides),
            fixture.dig(key, :replacements),
            fixture.dig(key, :allowed_families)
          )
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      ensure
        temp_dir.rmtree if temp_dir.exist?
      end
    end
  end

  it "conforms to the template directory session diagnostics report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-359-template-directory-session-diagnostics-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-diagnostics-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.plan_template_directory_session_diagnostics_from_directories(
          fixture_dir.join("dry-run", "template"),
          fixture_dir.join("dry-run", "destination"),
          fixture.dig(:dry_run, :context),
          fixture.dig(:dry_run, :default_strategy),
          fixture.dig(:dry_run, :overrides),
          fixture.dig(:dry_run, :replacements),
          fixture.dig(:dry_run, :allowed_families)
        )
      )
    ).to eq(json_ready(fixture.dig(:dry_run, :expected)))

    %i[apply_run filtered_discovery].each do |key|
      temp_dir = repo_temp_dir("diagnostics")
      destination_root = temp_dir.join("destination")
      begin
        Ast::Merge.write_relative_file_tree(
          destination_root,
          Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
        )

        actual = described_class.apply_template_directory_session_diagnostics_with_default_registry_to_directory(
          fixture_dir.join("apply-run", "template"),
          destination_root,
          fixture.dig(key, :context),
          fixture.dig(key, :default_strategy),
          fixture.dig(key, :overrides),
          fixture.dig(key, :replacements),
          fixture.dig(key, :allowed_families)
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      ensure
        temp_dir.rmtree if temp_dir.exist?
      end
    end
  end

  it "conforms to the template directory session outcome report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-360-template-directory-session-outcome-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-outcome-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.plan_template_directory_session_outcome_from_directories(
          fixture_dir.join("dry-run", "template"),
          fixture_dir.join("dry-run", "destination"),
          fixture.dig(:dry_run, :context),
          fixture.dig(:dry_run, :default_strategy),
          fixture.dig(:dry_run, :overrides),
          fixture.dig(:dry_run, :replacements),
          fixture.dig(:dry_run, :allowed_families)
        )
      )
    ).to eq(json_ready(fixture.dig(:dry_run, :expected)))

    %i[apply_run filtered_discovery].each do |key|
      temp_dir = repo_temp_dir("outcome")
      destination_root = temp_dir.join("destination")
      begin
        Ast::Merge.write_relative_file_tree(
          destination_root,
          Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
        )

        actual = described_class.apply_template_directory_session_outcome_with_default_registry_to_directory(
          fixture_dir.join("apply-run", "template"),
          destination_root,
          fixture.dig(key, :context),
          fixture.dig(key, :default_strategy),
          fixture.dig(key, :overrides),
          fixture.dig(key, :replacements),
          fixture.dig(key, :allowed_families)
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      ensure
        temp_dir.rmtree if temp_dir.exist?
      end
    end
  end

  it "conforms to the template directory session outcome transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-407-template-directory-session-outcome-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-outcome-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = test_case.fetch(:input)
      expected = test_case.fetch(:expected_envelope)

      expect(json_ready(described_class.template_directory_session_outcome_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_outcome_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session outcome transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-408-template-directory-session-outcome-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-outcome-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      expect(described_class.import_template_directory_session_outcome_envelope(test_case.fetch(:envelope))).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session outcome envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-409-template-directory-session-outcome-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-outcome-envelope-application.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      outcome, error = described_class.import_template_directory_session_outcome_envelope(test_case.fetch(:envelope))

      expect(error).to be_nil
      expect(json_ready(outcome)).to eq(json_ready(test_case.fetch(:expected)))
    end

    fixture.fetch(:rejections).each do |test_case|
      expect(described_class.import_template_directory_session_outcome_envelope(test_case.fetch(:envelope))).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session runner report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-361-template-directory-session-runner-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.run_template_directory_session_with_default_registry_to_directory(
          fixture.dig(:plan_run, :mode),
          fixture_dir.join("dry-run", "template"),
          fixture_dir.join("dry-run", "destination"),
          fixture.dig(:plan_run, :context),
          fixture.dig(:plan_run, :default_strategy),
          fixture.dig(:plan_run, :overrides),
          fixture.dig(:plan_run, :replacements),
          fixture.dig(:plan_run, :allowed_families)
        )
      )
    ).to eq(json_ready(fixture.dig(:plan_run, :expected)))

    temp_dir = repo_temp_dir("runner")
    destination_root = temp_dir.join("destination")
    begin
      Ast::Merge.write_relative_file_tree(
        destination_root,
        Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
      )

      %i[apply_run reapply_run].each do |key|
        actual = described_class.run_template_directory_session_with_default_registry_to_directory(
          fixture.dig(key, :mode),
          fixture_dir.join("apply-run", "template"),
          destination_root,
          fixture.dig(key, :context),
          fixture.dig(key, :default_strategy),
          fixture.dig(key, :overrides),
          fixture.dig(key, :replacements),
          fixture.dig(key, :allowed_families)
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      end
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the template directory session options report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-362-template-directory-session-options-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-options-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.run_template_directory_session_with_options(
          fixture.dig(:plan_run, :options).merge(
            template_root: fixture_dir.join("dry-run", "template"),
            destination_root: fixture_dir.join("dry-run", "destination")
          )
        )
      )
    ).to eq(json_ready(fixture.dig(:plan_run, :expected)))

    temp_dir = repo_temp_dir("options")
    destination_root = temp_dir.join("destination")
    begin
      Ast::Merge.write_relative_file_tree(
        destination_root,
        Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
      )

      %i[apply_run reapply_run].each do |key|
        actual = described_class.run_template_directory_session_with_options(
          fixture.dig(key, :options).merge(
            template_root: fixture_dir.join("apply-run", "template"),
            destination_root: destination_root
          )
        )
        expect(json_ready(actual)).to eq(json_ready(fixture.dig(key, :expected)))
      end
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the template directory session profile report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-363-template-directory-session-profile-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-profile-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.run_template_directory_session_with_profile(
          profiles,
          fixture.dig(:plan_run, :profile),
          {
            template_root: fixture_dir.join("dry-run", "template"),
            destination_root: fixture_dir.join("dry-run", "destination")
          }
        )
      )
    ).to eq(json_ready(fixture.dig(:plan_run, :expected)))

    temp_dir = repo_temp_dir("profiles")
    destination_root = temp_dir.join("destination")
    begin
      Ast::Merge.write_relative_file_tree(
        destination_root,
        Ast::Merge.read_relative_file_tree(fixture_dir.join("apply-run", "destination"))
      )

      expect(
        json_ready(
          described_class.run_template_directory_session_with_profile(
            profiles,
            fixture.dig(:apply_run, :profile),
            {
              template_root: fixture_dir.join("apply-run", "template"),
              destination_root: destination_root
            }
          )
        )
      ).to eq(json_ready(fixture.dig(:apply_run, :expected)))

      expect(
        json_ready(
          described_class.run_template_directory_session_with_profile(
            profiles,
            fixture.dig(:reapply_run, :profile),
            fixture.dig(:reapply_run, :overrides).merge(
              template_root: fixture_dir.join("apply-run", "template"),
              destination_root: destination_root
            )
          )
        )
      ).to eq(json_ready(fixture.dig(:reapply_run, :expected)))
    ensure
      temp_dir.rmtree if temp_dir.exist?
    end
  end

  it "conforms to the template directory session configuration report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-364-template-directory-session-configuration-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-configuration-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.report_template_directory_session_options_configuration(
          fixture.dig(:options_valid, :options)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_valid, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_options_configuration(
          fixture.dig(:options_missing_roots, :options)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_missing_roots, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_profile_configuration(
          profiles,
          fixture.dig(:profile_valid, :profile),
          fixture.dig(:profile_valid, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_valid, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_profile_configuration(
          profiles,
          fixture.dig(:profile_missing_profile, :profile),
          fixture.dig(:profile_missing_profile, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_missing_profile, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_profile_configuration(
          profiles,
          fixture.dig(:profile_missing_roots, :profile),
          fixture.dig(:profile_missing_roots, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_missing_roots, :expected)))
  end

  it "conforms to the template directory session profile configuration outcome report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-365-template-directory-session-profile-configuration-outcome-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-profile-configuration-outcome-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.run_template_directory_session_with_profile(
          profiles,
          fixture.dig(:missing_profile, :profile),
          fixture.dig(:missing_profile, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:missing_profile, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_with_profile(
          profiles,
          fixture.dig(:missing_roots, :profile),
          fixture.dig(:missing_roots, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:missing_roots, :expected)))
  end

  it "conforms to the template directory session options configuration outcome report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-366-template-directory-session-options-configuration-outcome-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-options-configuration-outcome-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.run_template_directory_session_with_options(
          fixture.dig(:missing_both_roots, :options)
        )
      )
    ).to eq(json_ready(fixture.dig(:missing_both_roots, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_with_options(
          fixture.dig(:missing_destination_root, :options)
        )
      )
    ).to eq(json_ready(fixture.dig(:missing_destination_root, :expected)))
  end

  it "conforms to the template directory session request report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-367-template-directory-session-request-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-request-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.report_template_directory_session_options_request(
          fixture.dig(:options_valid, :options)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_valid, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_options_request(
          fixture.dig(:options_invalid, :options)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_invalid, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_profile_request(
          profiles,
          fixture.dig(:profile_valid, :profile),
          fixture.dig(:profile_valid, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_valid, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_profile_request(
          profiles,
          fixture.dig(:profile_invalid, :profile),
          fixture.dig(:profile_invalid, :overrides)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_invalid, :expected)))
  end

  it "conforms to the template directory session request outcome report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-368-template-directory-session-request-outcome-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-request-outcome-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.run_template_directory_session_request(
          request_with_resolved_fixture_paths(fixture.dig(:options_ready, :request), fixture_dir)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_request(
          request_with_resolved_fixture_paths(fixture.dig(:options_blocked, :request), fixture_dir)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_blocked, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_request(
          request_with_resolved_fixture_paths(fixture.dig(:profile_ready, :request), fixture_dir)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_request(
          request_with_resolved_fixture_paths(fixture.dig(:profile_blocked, :request), fixture_dir)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_blocked, :expected)))
  end

  it "conforms to the template directory session request runner report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-369-template-directory-session-request-runner-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-request-runner-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_request(
          runner_request_with_resolved_fixture_paths(fixture.dig(:options_ready, :request), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:options_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_request(
          runner_request_with_resolved_fixture_paths(fixture.dig(:options_blocked, :request), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:options_blocked, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_request(
          runner_request_with_resolved_fixture_paths(fixture.dig(:profile_ready, :request), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_request(
          runner_request_with_resolved_fixture_paths(fixture.dig(:profile_blocked, :request), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_blocked, :expected)))
  end

  it "conforms to the template directory session request transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-404-template-directory-session-request-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-request-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = request_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = request_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_request_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_request_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session request transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-405-template-directory-session-request-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-request-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = request_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_request_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session request envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-406-template-directory-session-request-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-request-envelope-application.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = request_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      request, error = described_class.import_template_directory_session_request_envelope(envelope)

      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session_request(request))
      ).to eq(json_ready(resolve_session_outcome_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = request_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_request_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session runner request transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-398-template-directory-session-runner-request-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-request-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = runner_request_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = runner_request_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_runner_request_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_runner_request_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session runner request transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-399-template-directory-session-runner-request-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-request-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = runner_request_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_runner_request_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session runner request envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-400-template-directory-session-runner-request-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-request-envelope-application.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    fixture.fetch(:cases).each do |test_case|
      envelope = runner_request_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      request, error = described_class.import_template_directory_session_runner_request_envelope(envelope)

      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session_runner_request(request, profiles))
      ).to eq(json_ready(resolve_session_outcome_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = runner_request_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_runner_request_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session runner input report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-370-template-directory-session-runner-input-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-input-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_input(
          fixture.dig(:options_ready, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_ready, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_input(
          fixture.dig(:options_blocked, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_blocked, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_input(
          fixture.dig(:profile_ready, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_ready, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_input(
          fixture.dig(:profile_blocked, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_blocked, :expected)))
  end

  it "conforms to the template directory session runner payload report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-371-template-directory-session-runner-payload-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-payload-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_payload(
          fixture.dig(:options_explicit, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_explicit, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_payload(
          fixture.dig(:options_inferred, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:options_inferred, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_payload(
          fixture.dig(:profile_default_name, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_default_name, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_runner_payload(
          fixture.dig(:profile_explicit_name, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_explicit_name, :expected)))
  end

  it "conforms to the template directory session runner payload outcome report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-372-template-directory-session-runner-payload-outcome-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-payload-outcome-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_payload(
          runner_payload_with_resolved_fixture_paths(fixture.dig(:options_ready, :payload), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:options_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_payload(
          runner_payload_with_resolved_fixture_paths(fixture.dig(:options_blocked, :payload), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:options_blocked, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_payload(
          runner_payload_with_resolved_fixture_paths(fixture.dig(:profile_ready, :payload), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_runner_payload(
          runner_payload_with_resolved_fixture_paths(fixture.dig(:profile_blocked, :payload), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:profile_blocked, :expected)))
  end

  it "conforms to the template directory session runner payload transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-401-template-directory-session-runner-payload-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-payload-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = runner_payload_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = runner_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_runner_payload_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_runner_payload_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session runner payload transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-402-template-directory-session-runner-payload-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-payload-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = runner_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_runner_payload_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session runner payload envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-403-template-directory-session-runner-payload-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-runner-payload-envelope-application.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    fixture.fetch(:cases).each do |test_case|
      envelope = runner_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      payload, error = described_class.import_template_directory_session_runner_payload_envelope(envelope)

      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session_runner_payload(payload, profiles))
      ).to eq(json_ready(resolve_session_outcome_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = runner_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_runner_payload_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session entrypoint outcome report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-373-template-directory-session-entrypoint-outcome-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-entrypoint-outcome-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.run_template_directory_session_entrypoint(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:payload_ready, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:payload_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_entrypoint(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:request_blocked, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:request_blocked, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_entrypoint(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:request_ready, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:request_ready, :expected)))

    expect(
      json_ready(
        described_class.run_template_directory_session_entrypoint(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:payload_blocked, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:payload_blocked, :expected)))
  end

  it "conforms to the template directory session entrypoint report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-374-template-directory-session-entrypoint-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-entrypoint-report.json").read, symbolize_names: true)

    expect(
      json_ready(
        described_class.report_template_directory_session_entrypoint(
          fixture.dig(:payload_ready, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:payload_ready, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_entrypoint(
          fixture.dig(:request_blocked, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:request_blocked, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_entrypoint(
          fixture.dig(:request_ready, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:request_ready, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_entrypoint(
          fixture.dig(:payload_blocked, :input)
        )
      )
    ).to eq(json_ready(fixture.dig(:payload_blocked, :expected)))
  end

  it "conforms to the template directory session resolution report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-375-template-directory-session-resolution-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-resolution-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.report_template_directory_session_resolution(
          fixture.dig(:payload_ready, :input),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:payload_ready, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_resolution(
          fixture.dig(:request_blocked, :input),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:request_blocked, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_resolution(
          fixture.dig(:request_ready, :input),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:request_ready, :expected)))

    expect(
      json_ready(
        described_class.report_template_directory_session_resolution(
          fixture.dig(:payload_blocked, :input),
          profiles
        )
      )
    ).to eq(json_ready(fixture.dig(:payload_blocked, :expected)))
  end

  it "conforms to the template directory session inspection report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-376-template-directory-session-inspection-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-inspection-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    expect(
      json_ready(
        described_class.report_template_directory_session_inspection(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:payload_ready, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(resolve_session_inspection_expected_paths(fixture.dig(:payload_ready, :expected), fixture_dir)))

    expect(
      json_ready(
        described_class.report_template_directory_session_inspection(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:request_blocked, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(resolve_session_inspection_expected_paths(fixture.dig(:request_blocked, :expected), fixture_dir)))

    expect(
      json_ready(
        described_class.report_template_directory_session_inspection(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:request_ready, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(resolve_session_inspection_expected_paths(fixture.dig(:request_ready, :expected), fixture_dir)))

    expect(
      json_ready(
        described_class.report_template_directory_session_inspection(
          entrypoint_with_resolved_fixture_paths(fixture.dig(:payload_blocked, :input), fixture_dir),
          profiles
        )
      )
    ).to eq(json_ready(resolve_session_inspection_expected_paths(fixture.dig(:payload_blocked, :expected), fixture_dir)))
  end

  it "conforms to the template directory session inspection transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-410-template-directory-session-inspection-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-inspection-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = resolve_session_inspection_expected_paths(test_case.fetch(:input), fixture_dir)
      expected = inspection_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_inspection_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_inspection_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session inspection transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-411-template-directory-session-inspection-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-inspection-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = inspection_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_inspection_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session inspection envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-412-template-directory-session-inspection-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-inspection-envelope-application.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = inspection_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      inspection, error = described_class.import_template_directory_session_inspection_envelope(envelope)

      expect(error).to be_nil
      expect(json_ready(inspection)).to eq(json_ready(resolve_session_inspection_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = inspection_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_inspection_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session dispatch report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-377-template-directory-session-dispatch-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-dispatch-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    %i[inspect_payload_ready inspect_request_blocked run_request_ready run_payload_blocked].each do |key|
      input = fixture.dig(key, :input)
      expect(
        json_ready(
          described_class.run_template_directory_session_dispatch(
            input[:operation],
            entrypoint_with_resolved_fixture_paths(input[:entrypoint], fixture_dir),
            profiles
          )
        )
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(fixture.dig(key, :expected), fixture_dir)))
    end
  end

  it "conforms to the template directory session command report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-378-template-directory-session-command-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    %i[inspect_payload_ready run_request_ready run_payload_blocked].each do |key|
      expect(
        json_ready(
          described_class.run_template_directory_session_command(
            command_with_resolved_fixture_paths(fixture.dig(key, :input), fixture_dir),
            profiles
          )
        )
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(fixture.dig(key, :expected), fixture_dir)))
    end
  end

  it "conforms to the template directory session command payload report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-379-template-directory-session-command-payload-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-payload-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    %i[inspect_ready run_profile_ready run_profile_blocked].each do |key|
      expect(
        json_ready(
          described_class.run_template_directory_session_command_payload(
            command_payload_with_resolved_fixture_paths(fixture.dig(key, :input), fixture_dir),
            profiles
          )
        )
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(fixture.dig(key, :expected), fixture_dir)))
    end
  end

  it "conforms to the template directory session dispatch rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-380-template-directory-session-dispatch-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-dispatch-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = test_case.fetch(:input)
      expect do
        described_class.run_template_directory_session_dispatch(
          input.fetch(:operation),
          entrypoint_with_resolved_fixture_paths(input.fetch(:entrypoint), fixture_dir),
          {}
        )
      end.to raise_error(ArgumentError, test_case.fetch(:expected_error))
    end
  end

  it "conforms to the template directory session command rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-381-template-directory-session-command-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      expect do
        described_class.run_template_directory_session_command(
          command_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir),
          {}
        )
      end.to raise_error(ArgumentError, test_case.fetch(:expected_error))
    end
  end

  it "conforms to the template directory session command payload rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-382-template-directory-session-command-payload-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-payload-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      expect do
        described_class.run_template_directory_session_command_payload(
          command_payload_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir),
          {}
        )
      end.to raise_error(ArgumentError, test_case.fetch(:expected_error))
    end
  end

  it "conforms to the template directory session command transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-389-template-directory-session-command-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = command_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = command_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_command_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_command_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session command transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-390-template-directory-session-command-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = command_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_command_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session command envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-391-template-directory-session-command-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-envelope-application.json").read, symbolize_names: true)
    profiles = fixture.fetch(:profiles).transform_keys(&:to_s)

    fixture.fetch(:cases).each do |test_case|
      envelope = command_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      command, error = described_class.import_template_directory_session_command_envelope(envelope)
      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session_command(command, profiles))
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = command_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_command_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session command payload transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-392-template-directory-session-command-payload-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-payload-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = command_payload_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = command_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_command_payload_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_command_payload_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session command payload transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-393-template-directory-session-command-payload-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-payload-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = command_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_command_payload_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session entrypoint transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-395-template-directory-session-entrypoint-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-entrypoint-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = entrypoint_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = entrypoint_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_entrypoint_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_entrypoint_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session entrypoint transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-396-template-directory-session-entrypoint-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-entrypoint-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = entrypoint_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_entrypoint_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session entrypoint envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-397-template-directory-session-entrypoint-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-entrypoint-envelope-application.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    fixture.fetch(:cases).each do |test_case|
      envelope = entrypoint_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      entrypoint, error = described_class.import_template_directory_session_entrypoint_envelope(envelope)

      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session_entrypoint(entrypoint, profiles))
      ).to eq(json_ready(resolve_session_outcome_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = entrypoint_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_entrypoint_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session command payload envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-394-template-directory-session-command-payload-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-command-payload-envelope-application.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    fixture.fetch(:cases).each do |test_case|
      envelope = command_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      payload, error = described_class.import_template_directory_session_command_payload_envelope(envelope)

      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session_command_payload(payload, profiles))
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = command_payload_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_command_payload_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session invocation report fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-383-template-directory-session-invocation-report")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-invocation-report.json").read, symbolize_names: true)
    profiles = fixture[:profiles].transform_keys(&:to_s)

    %i[inspect_nested_payload_ready run_nested_request_ready run_flat_profile_blocked].each do |key|
      expect(
        json_ready(
          described_class.run_template_directory_session(
            invocation_with_resolved_fixture_paths(fixture.dig(key, :input), fixture_dir),
            profiles
          )
        )
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(fixture.dig(key, :expected), fixture_dir)))
    end
  end

  it "conforms to the template directory session invocation rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-384-template-directory-session-invocation-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-invocation-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      expect do
        described_class.run_template_directory_session(
          invocation_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir),
          {}
        )
      end.to raise_error(ArgumentError, test_case.fetch(:expected_error))
    end
  end

  it "conforms to the template directory session invocation JSON roundtrip fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-385-template-directory-session-invocation-json-roundtrip")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-invocation-json-roundtrip.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = invocation_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      round_tripped = JSON.parse(JSON.generate(input), symbolize_names: true)
      expect(json_ready(round_tripped)).to eq(json_ready(input))
    end
  end

  it "conforms to the template directory session invocation transport envelope fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-386-template-directory-session-invocation-transport-envelope")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-invocation-envelope.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      input = invocation_with_resolved_fixture_paths(test_case.fetch(:input), fixture_dir)
      expected = invocation_envelope_with_resolved_fixture_paths(test_case.fetch(:expected_envelope), fixture_dir)

      expect(json_ready(described_class.template_directory_session_invocation_envelope(input))).to eq(json_ready(expected))
      expect(described_class.import_template_directory_session_invocation_envelope(expected)).to eq([input, nil])
    end
  end

  it "conforms to the template directory session invocation transport rejection fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-387-template-directory-session-invocation-transport-rejection")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-invocation-envelope-rejection.json").read, symbolize_names: true)

    fixture.fetch(:cases).each do |test_case|
      envelope = invocation_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_invocation_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  it "conforms to the template directory session invocation envelope application fixture" do
    fixture_dir = repo_root.join("fixtures/diagnostics/slice-388-template-directory-session-invocation-envelope-application")
    fixture = JSON.parse(fixture_dir.join("template-directory-session-invocation-envelope-application.json").read, symbolize_names: true)
    profiles = fixture.fetch(:profiles).transform_keys(&:to_s)

    fixture.fetch(:cases).each do |test_case|
      envelope = invocation_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      invocation, error = described_class.import_template_directory_session_invocation_envelope(envelope)
      expect(error).to be_nil
      expect(
        json_ready(described_class.run_template_directory_session(invocation, profiles))
      ).to eq(json_ready(resolve_session_dispatch_expected_paths(test_case.fetch(:expected), fixture_dir)))
    end

    fixture.fetch(:rejections).each do |test_case|
      envelope = invocation_envelope_with_resolved_fixture_paths(test_case.fetch(:envelope), fixture_dir)
      expect(described_class.import_template_directory_session_invocation_envelope(envelope)).to eq([nil, test_case.fetch(:expected_error)])
    end
  end

  def markdown_adapter(entry)
    Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
  end

  def toml_adapter(entry)
    Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
  end

  def ruby_adapter(entry)
    Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
  end

  def request_with_resolved_fixture_paths(request, fixture_dir)
    normalized = Marshal.load(Marshal.dump(request))
    resolved = normalized[:resolved_options]
    return normalized unless resolved

    normalized[:resolved_options] = options_with_resolved_fixture_paths(resolved, fixture_dir)
    normalized
  end

  def request_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    if normalized[:request]
      normalized[:request] = request_with_resolved_fixture_paths(normalized[:request], fixture_dir)
    end
    normalized
  end

  def options_with_resolved_fixture_paths(options, fixture_dir)
    normalized = Marshal.load(Marshal.dump(options))
    if normalized[:template_root].to_s.length.positive?
      normalized[:template_root] = fixture_dir.join(normalized[:template_root]).to_s
    end
    if normalized[:destination_root].to_s.length.positive?
      normalized[:destination_root] = fixture_dir.join(normalized[:destination_root]).to_s
    end
    normalized
  end

  def runner_request_with_resolved_fixture_paths(request, fixture_dir)
    normalized = Marshal.load(Marshal.dump(request))
    options = normalized[:options]
    if options
      if options[:template_root].to_s.length.positive?
        options[:template_root] = fixture_dir.join(options[:template_root]).to_s
      end
      if options[:destination_root].to_s.length.positive?
        options[:destination_root] = fixture_dir.join(options[:destination_root]).to_s
      end
    end
    overrides = normalized[:overrides]
    if overrides
      if overrides[:template_root].to_s.length.positive?
        overrides[:template_root] = fixture_dir.join(overrides[:template_root]).to_s
      end
      if overrides[:destination_root].to_s.length.positive?
        overrides[:destination_root] = fixture_dir.join(overrides[:destination_root]).to_s
      end
    end
    normalized
  end

  def runner_payload_with_resolved_fixture_paths(payload, fixture_dir)
    normalized = Marshal.load(Marshal.dump(payload))
    if normalized[:template_root].to_s.length.positive?
      normalized[:template_root] = fixture_dir.join(normalized[:template_root]).to_s
    end
    if normalized[:destination_root].to_s.length.positive?
      normalized[:destination_root] = fixture_dir.join(normalized[:destination_root]).to_s
    end
    normalized
  end

  def runner_payload_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    if normalized[:payload]
      normalized[:payload] = runner_payload_with_resolved_fixture_paths(normalized[:payload], fixture_dir)
    end
    normalized
  end

  def entrypoint_with_resolved_fixture_paths(entrypoint, fixture_dir)
    normalized = Marshal.load(Marshal.dump(entrypoint))
    if normalized[:payload]
      normalized[:payload] = runner_payload_with_resolved_fixture_paths(normalized[:payload], fixture_dir)
    end
    if normalized[:request]
      normalized[:request] = runner_request_with_resolved_fixture_paths(normalized[:request], fixture_dir)
    end
    normalized
  end

  def entrypoint_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    if normalized[:entrypoint]
      normalized[:entrypoint] = entrypoint_with_resolved_fixture_paths(normalized[:entrypoint], fixture_dir)
    end
    normalized
  end

  def runner_request_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    if normalized[:request]
      normalized[:request] = runner_request_with_resolved_fixture_paths(normalized[:request], fixture_dir)
    end
    normalized
  end

  def resolve_session_inspection_expected_paths(report, fixture_dir)
    normalized = Ast::Merge.deep_dup(report)
    if normalized[:entrypoint_report]&.dig(:runner_request)
      normalized[:entrypoint_report][:runner_request] =
        runner_request_with_resolved_fixture_paths(normalized[:entrypoint_report][:runner_request], fixture_dir)
    end
    if normalized[:session_resolution]&.dig(:runner_request)
      normalized[:session_resolution][:runner_request] =
        runner_request_with_resolved_fixture_paths(normalized[:session_resolution][:runner_request], fixture_dir)
    end
    if normalized[:session_resolution]&.dig(:session_request, :resolved_options)
      normalized[:session_resolution][:session_request][:resolved_options] =
        options_with_resolved_fixture_paths(
          normalized[:session_resolution][:session_request][:resolved_options],
          fixture_dir
        )
    end
    normalized
  end

  def inspection_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    if normalized[:inspection]
      normalized[:inspection] = resolve_session_inspection_expected_paths(normalized[:inspection], fixture_dir)
    end
    normalized
  end

  def resolve_session_dispatch_expected_paths(report, fixture_dir)
    normalized = Ast::Merge.deep_dup(report)
    if normalized[:inspection]
      normalized[:inspection] = resolve_session_inspection_expected_paths(normalized[:inspection], fixture_dir)
    end
    normalized
  end

  def resolve_session_outcome_expected_paths(report, fixture_dir)
    normalized = Ast::Merge.deep_dup(report)
    fixture_dir
    normalized
  end

  def command_with_resolved_fixture_paths(command, fixture_dir)
    normalized = Marshal.load(Marshal.dump(command))
    if normalized[:payload]
      normalized[:payload] = runner_payload_with_resolved_fixture_paths(normalized[:payload], fixture_dir)
    end
    if normalized[:request]
      normalized[:request] = runner_request_with_resolved_fixture_paths(normalized[:request], fixture_dir)
    end
    normalized
  end

  def command_payload_with_resolved_fixture_paths(command, fixture_dir)
    runner_payload_with_resolved_fixture_paths(command, fixture_dir)
  end

  def command_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    normalized[:command] = command_with_resolved_fixture_paths(normalized.fetch(:command), fixture_dir)
    normalized
  end

  def command_payload_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    normalized[:payload] = command_payload_with_resolved_fixture_paths(normalized.fetch(:payload), fixture_dir)
    normalized
  end

  def invocation_with_resolved_fixture_paths(invocation, fixture_dir)
    normalized = Marshal.load(Marshal.dump(invocation))
    if normalized[:payload]
      normalized[:payload] = runner_payload_with_resolved_fixture_paths(normalized[:payload], fixture_dir)
    end
    if normalized[:request]
      normalized[:request] = runner_request_with_resolved_fixture_paths(normalized[:request], fixture_dir)
    end
    if normalized[:template_root]
      normalized[:template_root] = fixture_dir.join(normalized[:template_root]).to_s
    end
    if normalized[:destination_root]
      normalized[:destination_root] = fixture_dir.join(normalized[:destination_root]).to_s
    end
    normalized
  end

  def invocation_envelope_with_resolved_fixture_paths(envelope, fixture_dir)
    normalized = Marshal.load(Marshal.dump(envelope))
    normalized[:invocation] = invocation_with_resolved_fixture_paths(normalized.fetch(:invocation), fixture_dir)
    normalized
  end

end
