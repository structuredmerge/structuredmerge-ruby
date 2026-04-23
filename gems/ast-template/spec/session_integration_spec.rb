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

    resolved[:template_root] = fixture_dir.join(resolved[:template_root]).to_s
    resolved[:destination_root] = fixture_dir.join(resolved[:destination_root]).to_s
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
end
