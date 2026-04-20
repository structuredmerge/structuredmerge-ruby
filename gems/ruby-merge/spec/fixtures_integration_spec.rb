# frozen_string_literal: true

require_relative "spec_helper"

RUBY_MERGE = ::Ruby::Merge

RSpec.describe "Ruby::Merge" do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the Ruby family substrate fixtures" do
    feature_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-214-ruby-family-feature-profile", "ruby-feature-profile.json")
    )
    backend_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-215-ruby-family-backend-feature-profiles",
        "ruby-ruby-backend-feature-profiles.json"
      )
    )
    plan_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-216-ruby-family-plan-contexts", "ruby-ruby-plan-contexts.json")
    )
    manifest_fixture = read_json(
      fixtures_root.join("conformance", "slice-217-ruby-family-manifest", "ruby-family-manifest.json")
    )
    analysis_fixture = read_json(fixtures_root.join("ruby", "slice-218-analysis", "module-owners.json"))
    matching_fixture = read_json(fixtures_root.join("ruby", "slice-219-matching", "path-equality.json"))
    surfaces_fixture = read_json(
      fixtures_root.join("ruby", "slice-220-discovered-surfaces", "doc-comment-surfaces.json")
    )
    child_fixture = read_json(
      fixtures_root.join("ruby", "slice-221-delegated-child-operations", "yard-example-child-operations.json")
    )

    expect(json_ready(RUBY_MERGE.ruby_feature_profile)).to eq(json_ready(feature_fixture[:feature_profile]))
    expect(json_ready(RUBY_MERGE.available_ruby_backends.map(&:to_h))).to eq(
      json_ready([{ id: "kreuzberg-language-pack", family: "tree-sitter" }])
    )
    expect(json_ready(RUBY_MERGE.ruby_backend_feature_profile)).to eq(
      json_ready(backend_fixture[:tree_sitter].merge(family: "ruby", supported_dialects: ["ruby"]))
    )
    expect(json_ready(RUBY_MERGE.ruby_plan_context)).to eq(json_ready(plan_fixture[:tree_sitter]))
    expect(Ast::Merge.conformance_fixture_path(manifest_fixture, "ruby", "analysis")).to eq(
      %w[ruby slice-218-analysis module-owners.json]
    )

    analysis = RUBY_MERGE.parse_ruby(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    template = RUBY_MERGE.parse_ruby(matching_fixture[:template], matching_fixture[:dialect])
    destination = RUBY_MERGE.parse_ruby(matching_fixture[:destination], matching_fixture[:dialect])
    matching = RUBY_MERGE.match_ruby_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )
    expect(json_ready(matching[:unmatched_template])).to eq(json_ready(matching_fixture.dig(:expected, :unmatched_template)))
    expect(json_ready(matching[:unmatched_destination])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_destination))
    )

    surfaces_analysis = RUBY_MERGE.parse_ruby(surfaces_fixture[:source], "ruby")
    expect(surfaces_analysis[:ok]).to be(true)
    expect(json_ready(RUBY_MERGE.ruby_discovered_surfaces(surfaces_analysis[:analysis]))).to eq(
      json_ready(surfaces_fixture[:expected])
    )

    child_analysis = RUBY_MERGE.parse_ruby(child_fixture[:source], "ruby")
    expect(child_analysis[:ok]).to be(true)
    expect(
      json_ready(
        RUBY_MERGE.ruby_delegated_child_operations(
          child_analysis[:analysis],
          parent_operation_id: child_fixture[:parent_operation_id]
        )
      )
    ).to eq(json_ready(child_fixture[:expected]))

    grouped_fixture = read_json(
      fixtures_root.join("ruby", "slice-229-projected-child-review-groups", "yard-example-review-groups.json")
    )
    expect(json_ready(Ast::Merge.group_projected_child_review_cases(grouped_fixture[:cases]))).to eq(
      json_ready(grouped_fixture[:expected_groups])
    )

    progress_fixture = read_json(
      fixtures_root.join("ruby", "slice-232-projected-child-review-group-progress", "yard-example-review-progress.json")
    )
    expect(
      json_ready(
        Ast::Merge.summarize_projected_child_review_group_progress(
          progress_fixture[:groups],
          progress_fixture[:resolved_case_ids]
        )
      )
    ).to eq(json_ready(progress_fixture[:expected_progress]))
  end
end
