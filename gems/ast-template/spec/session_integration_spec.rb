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
end
