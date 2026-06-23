# frozen_string_literal: true

require_relative 'spec_helper'

PRISM_MERGE = ::Prism::Merge

RSpec.describe 'Prism::Merge' do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it 'exposes the Ruby family through the Prism provider backend' do
    family_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-214-ruby-family-feature-profile', 'ruby-feature-profile.json')
    )
    feature_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-222-ruby-provider-feature-profiles',
                         'ruby-provider-feature-profiles.json')
    )
    plan_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-223-ruby-provider-plan-contexts', 'ruby-provider-plan-contexts.json')
    )

    expect(json_ready(PRISM_MERGE.ruby_feature_profile)).to eq(json_ready(family_fixture[:feature_profile]))
    expect(json_ready(PRISM_MERGE.available_ruby_backends.map(&:to_h))).to eq(
      json_ready([{ id: 'prism', family: 'native' }])
    )
    expect(json_ready(TreeHaver::BackendRegistry.fetch('prism')&.to_h)).to eq(
      json_ready({ id: 'prism', family: 'native' })
    )
    expect(json_ready(PRISM_MERGE.ruby_backend_feature_profile)).to eq(
      json_ready(feature_fixture.dig(:providers, :prism, :feature_profile))
    )
    expect(json_ready(PRISM_MERGE.ruby_plan_context)).to eq(json_ready(plan_fixture.dig(:providers, :prism)))
  end

  it 'merges Gemfile DSL with Prism-native signatures' do
    result = PRISM_MERGE.merge_ruby(
      <<~RUBY,
        source "https://gem.coop"
        gemspec
        eval_gemfile "gemfiles/modular/style.gemfile" if ENV.fetch("K_JEM_STYLE", "false").casecmp("true").zero?
        gem "rake"
      RUBY
      <<~RUBY,
        source "https://rubygems.org"
        gem "rspec"
        eval_gemfile "gemfiles/modular/style.gemfile"
      RUBY
      'ruby',
      preference: :template,
      signature_generator: PRISM_MERGE.ruby_dsl_signature_generator
    )

    expect(result[:ok]).to be(true)
    expect(result[:output]).to include('source "https://gem.coop"')
    expect(result[:output]).not_to include('source "https://rubygems.org"')
    expect(result[:output]).to include('eval_gemfile "gemfiles/modular/style.gemfile" if ENV.fetch("K_JEM_STYLE", "false").casecmp("true").zero?')
    expect(result[:output].split('eval_gemfile "gemfiles/modular/style.gemfile"', -1).size).to eq(2)
    expect(result[:output]).to include('gem "rspec"')
    expect(result[:output]).to include('gem "rake"')
  end

  it 'adds template-only top-level nodes at their template anchor' do
    result = PRISM_MERGE.merge_ruby(
      <<~RUBY,
        # frozen_string_literal: true

        begin
          require "kettle-soup-cover"
          require "simplecov"
        rescue LoadError
        end

        require "kettle/test/rspec"

        RSpec.configure do |config|
          config.example_status_persistence_file_path = ".rspec_status"
        end
      RUBY
      <<~RUBY,
        # frozen_string_literal: true

        require "example/custom"

        RSpec.configure do |config|
          config.include_context "with mocked git adapter"
        end
      RUBY
      'ruby',
      preference: :destination,
      add_template_only_nodes: true,
      merge_template_requires: true,
      signature_generator: PRISM_MERGE.ruby_dsl_signature_generator
    )

    expect(result[:ok]).to be(true)
    expect(result[:output].index('require "kettle-soup-cover"')).to be < result[:output].index('require "example/custom"')
    expect(result[:output]).to include('require "simplecov"')
    expect(result[:output]).to include('require "kettle/test/rspec"')
    expect(result[:output]).to include('require "example/custom"')
    expect(result[:output]).to include('config.include_context "with mocked git adapter"')
  end

  it 'does not move template-only requires before a later matched coverage bootstrap' do
    result = PRISM_MERGE.merge_ruby(
      <<~RUBY,
        # frozen_string_literal: true

        begin
          require "kettle-soup-cover"
          require "simplecov"
        rescue LoadError
        end

        require "kettle/test/rspec"


        # This library
        require "example/gem"

        RSpec.configure do |config|
          config.example_status_persistence_file_path = ".rspec_status"
        end
      RUBY
      <<~RUBY,
        # frozen_string_literal: true

        require "kettle/test/rspec"

        # This library
        require "example/gem"

        # Internal ENV config
        require_relative "config/debug"

        begin
          require "kettle-soup-cover"
          require "simplecov"
        rescue LoadError
        end

        # this library
        require "example-gem"

        RSpec.configure do |config|
          config.include_context "with mocked git adapter"
        end
      RUBY
      'ruby',
      preference: :destination,
      add_template_only_nodes: true,
      merge_template_requires: true,
      signature_generator: PRISM_MERGE.ruby_dsl_signature_generator(require_aliases: [['example-gem', 'example/gem']])
    )

    expect(result[:ok]).to be(true)
    expect(result[:output]).not_to include('require "example/gem"')
    expect(result[:output].scan('require "example-gem"').size).to eq(1)
    expect(result[:output].index('require "kettle-soup-cover"')).to be < result[:output].index('require "example-gem"')
    expect(result[:output]).not_to include("require \"kettle/test/rspec\"\n\n\n# Internal ENV config")
  end

  it 'projects the structured-edit provider profile through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-424-ruby-structured-edit-provider-profiles',
        'ruby-structured-edit-provider-profiles.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_provider_profile)).to eq(json_ready(fixture.dig(:providers,
                                                                                                       :prism)))
  end

  it 'projects the structured-edit request through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-428-ruby-structured-edit-request-projection',
        'ruby-structured-edit-request-projection.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_request_projection)).to eq(
      json_ready(fixture.dig(:providers, :prism))
    )
  end

  it 'projects the structured-edit result through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-430-ruby-structured-edit-result-projection',
        'ruby-structured-edit-result-projection.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_result_projection)).to eq(
      json_ready(fixture.dig(:providers, :prism))
    )
  end

  it 'projects the structured-edit application through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-433-ruby-structured-edit-application-projection',
        'ruby-structured-edit-application-projection.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_application_projection)).to eq(
      json_ready(fixture.dig(:providers, :prism))
    )
  end

  it 'projects the structured-edit execution report through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-447-ruby-structured-edit-execution-report-projection',
        'ruby-structured-edit-execution-report-projection.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_execution_report_projection)).to eq(
      json_ready(fixture.dig(:providers, :prism))
    )
  end

  it 'projects the structured-edit batch request through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-449-ruby-structured-edit-batch-request-projection',
        'ruby-structured-edit-batch-request-projection.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_batch_request_projection)).to eq(
      json_ready(fixture.dig(:providers, :prism))
    )
  end

  it 'projects the structured-edit batch report through Prism' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-451-ruby-structured-edit-batch-report-projection',
        'ruby-structured-edit-batch-report-projection.json'
      )
    )

    expect(json_ready(PRISM_MERGE.ruby_structured_edit_batch_report_projection)).to eq(
      json_ready(fixture.dig(:providers, :prism))
    )
  end

  it 'projects Prism AST facts into the normalized tree-haver parse shape' do
    fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-935-prism-normalized-parse',
        'class-method-normalized-tree.json'
      )
    )

    result = PRISM_MERGE.parse_ruby_normalized(fixture[:source], fixture[:dialect])
    expect(json_ready(result)).to eq(json_ready(fixture[:expected]))
  end

  it 'projects Prism comments and Ruby directives into normalized metadata' do
    fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-936-prism-comment-directive-metadata',
        'comment-directives-normalized-tree.json'
      )
    )

    result = PRISM_MERGE.parse_ruby_normalized(fixture[:source], fixture[:dialect])
    comment_nodes = result[:nodes].select { |node| node[:role] == 'comment' }
    child_ids_by_id = result[:nodes].to_h { |node| [node[:id], node[:child_ids]] }

    expect(json_ready(comment_nodes)).to eq(json_ready(fixture[:expected_comment_nodes]))
    expected_parent_links = fixture[:expected_parent_links]
    selected_parent_links = expected_parent_links.to_h do |id, _child_ids|
      [id, child_ids_by_id.fetch(id.to_s)]
    end
    expect(json_ready(selected_parent_links)).to eq(
      json_ready(fixture[:expected_parent_links])
    )
  end

  it 'projects Prism parse errors into the normalized parse failure shape' do
    fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-937-prism-parse-error-projection',
        'missing-end-normalized-error.json'
      )
    )

    result = PRISM_MERGE.parse_ruby_normalized(fixture[:source], fixture[:dialect])
    expect(json_ready(result)).to eq(json_ready(fixture[:expected]))
  end

  it 'executes a source-preserving Prism replace-node edit projection' do
    fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-938-prism-edit-projection-replace-node',
        'method-replace-node.json'
      )
    )

    result = PRISM_MERGE.apply_edit_projection(fixture[:request])
    expect(json_ready(result)).to eq(json_ready(fixture[:expected_result]))
  end

  it 'executes a source-preserving Prism delete-node edit projection' do
    fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-939-prism-edit-projection-delete-node',
        'method-delete-node.json'
      )
    )

    result = PRISM_MERGE.apply_edit_projection(fixture[:request])
    expect(json_ready(result)).to eq(json_ready(fixture[:expected_result]))
  end

  it 'executes a source-preserving Prism insert-child edit projection' do
    fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-940-prism-edit-projection-insert-child',
        'method-insert-child.json'
      )
    )

    result = PRISM_MERGE.apply_edit_projection(fixture[:request])
    expect(json_ready(result)).to eq(json_ready(fixture[:expected_result]))
  end

  it 'builds the shared Ruby analysis from Prism nodes' do
    analysis_fixture = read_json(fixtures_root.join('ruby', 'slice-218-analysis', 'module-owners.json'))
    surfaces_fixture = read_json(
      fixtures_root.join('ruby', 'slice-220-discovered-surfaces', 'doc-comment-surfaces.json')
    )

    analysis = PRISM_MERGE.parse_ruby(analysis_fixture[:source], analysis_fixture[:dialect])
    surfaces_analysis = PRISM_MERGE.parse_ruby(surfaces_fixture[:source], 'ruby')

    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))
    expect(json_ready(PRISM_MERGE.ruby_discovered_surfaces(surfaces_analysis[:analysis]))).to eq(
      json_ready(surfaces_fixture[:expected])
    )
  end

  it 'conforms to the shared Ruby family fixtures' do
    analysis_fixture = read_json(fixtures_root.join('ruby', 'slice-218-analysis', 'module-owners.json'))
    matching_fixture = read_json(fixtures_root.join('ruby', 'slice-219-matching', 'path-equality.json'))
    surfaces_fixture = read_json(
      fixtures_root.join('ruby', 'slice-220-discovered-surfaces', 'doc-comment-surfaces.json')
    )
    child_fixture = read_json(
      fixtures_root.join('ruby', 'slice-221-delegated-child-operations', 'yard-example-child-operations.json')
    )

    analysis = PRISM_MERGE.parse_ruby(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    template = PRISM_MERGE.parse_ruby(matching_fixture[:template], matching_fixture[:dialect])
    destination = PRISM_MERGE.parse_ruby(matching_fixture[:destination], matching_fixture[:dialect])
    result = PRISM_MERGE.match_ruby_owners(template[:analysis], destination[:analysis])
    expect(json_ready(result[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )
    expect(json_ready(result[:unmatched_template])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_template))
    )
    expect(json_ready(result[:unmatched_destination])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_destination))
    )

    merge_fixture = read_json(fixtures_root.join('ruby', 'slice-287-merge', 'module-merge.json'))
    merge_result = PRISM_MERGE.merge_ruby(merge_fixture[:template], merge_fixture[:destination], 'ruby')
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    surfaces_analysis = PRISM_MERGE.parse_ruby(surfaces_fixture[:source], 'ruby')
    expect(json_ready(PRISM_MERGE.ruby_discovered_surfaces(surfaces_analysis[:analysis]))).to eq(
      json_ready(surfaces_fixture[:expected])
    )

    child_analysis = PRISM_MERGE.parse_ruby(child_fixture[:source], 'ruby')
    expect(
      json_ready(
        PRISM_MERGE.ruby_delegated_child_operations(
          child_analysis[:analysis],
          parent_operation_id: child_fixture[:parent_operation_id]
        )
      )
    ).to eq(json_ready(child_fixture[:expected]))

    reviewed_nested_merge_fixture = read_json(
      fixtures_root.join('ruby', 'slice-299-reviewed-nested-merge', 'yard-example-reviewed-nested-merge.json')
    )
    reviewed_nested_merge_result = PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs(
      reviewed_nested_merge_fixture[:template],
      reviewed_nested_merge_fixture[:destination],
      'ruby',
      reviewed_nested_merge_fixture[:review_state],
      reviewed_nested_merge_fixture[:applied_children]
    )
    expect(reviewed_nested_merge_result[:ok]).to eq(reviewed_nested_merge_fixture.dig(:expected, :ok))
    expect(reviewed_nested_merge_result[:output]).to eq(reviewed_nested_merge_fixture.dig(:expected, :output))

    review_artifact_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-310-reviewed-nested-review-artifact-application',
        'yard-example-reviewed-nested-review-artifact-application.json'
      )
    )
    replay_result = PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
      review_artifact_fixture[:template],
      review_artifact_fixture[:destination],
      'ruby',
      review_artifact_fixture[:replay_bundle]
    )
    expect(replay_result[:ok]).to eq(review_artifact_fixture.dig(:expected, :ok))
    expect(replay_result[:output]).to eq(review_artifact_fixture.dig(:expected, :output))
    state_result = PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state(
      review_artifact_fixture[:template],
      review_artifact_fixture[:destination],
      'ruby',
      review_artifact_fixture[:review_state]
    )
    expect(state_result[:ok]).to eq(review_artifact_fixture.dig(:expected, :ok))
    expect(state_result[:output]).to eq(review_artifact_fixture.dig(:expected, :output))

    rejection_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-312-reviewed-nested-review-artifact-rejection',
        'yard-example-reviewed-nested-review-artifact-rejection.json'
      )
    )
    expect(
      json_ready(PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
                   rejection_fixture[:template],
                   rejection_fixture[:destination],
                   'ruby',
                   rejection_fixture[:replay_bundle]
                 ))
    ).to eq(json_ready(rejection_fixture[:expected].merge(policies: [])))
    expect(
      json_ready(PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state(
                   rejection_fixture[:template],
                   rejection_fixture[:destination],
                   'ruby',
                   rejection_fixture[:review_state]
                 ))
    ).to eq(json_ready(rejection_fixture[:expected_review_state].merge(policies: [])))

    envelope_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-314-reviewed-nested-review-artifact-envelope-application',
        'yard-example-reviewed-nested-review-artifact-envelope-application.json'
      )
    )
    replay_envelope_result = PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
      envelope_fixture[:template],
      envelope_fixture[:destination],
      'ruby',
      envelope_fixture[:replay_bundle_envelope]
    )
    expect(replay_envelope_result[:ok]).to eq(envelope_fixture.dig(:expected, :ok))
    expect(replay_envelope_result[:output]).to eq(envelope_fixture.dig(:expected, :output))
    state_envelope_result = PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
      envelope_fixture[:template],
      envelope_fixture[:destination],
      'ruby',
      envelope_fixture[:review_state_envelope]
    )
    expect(state_envelope_result[:ok]).to eq(envelope_fixture.dig(:expected, :ok))
    expect(state_envelope_result[:output]).to eq(envelope_fixture.dig(:expected, :output))

    envelope_rejection_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-316-reviewed-nested-review-artifact-envelope-rejection',
        'yard-example-reviewed-nested-review-artifact-envelope-rejection.json'
      )
    )
    expect(
      json_ready(PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
                   envelope_rejection_fixture[:template],
                   envelope_rejection_fixture[:destination],
                   'ruby',
                   envelope_rejection_fixture[:replay_bundle_envelope]
                 ))
    ).to eq(json_ready(envelope_rejection_fixture[:expected_replay_bundle].merge(policies: [])))
    expect(
      json_ready(PRISM_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
                   envelope_rejection_fixture[:template],
                   envelope_rejection_fixture[:destination],
                   'ruby',
                   envelope_rejection_fixture[:review_state_envelope]
                 ))
    ).to eq(json_ready(envelope_rejection_fixture[:expected_review_state].merge(policies: [])))
  end

  it 'conforms to the provider named-suite plan and manifest-report fixtures' do
    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-224-ruby-provider-named-suite-plans',
                         'ruby-provider-named-suite-plans.json')
    )
    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-225-ruby-provider-manifest-report', 'ruby-provider-manifest-report.json')
    )

    contexts = plans_fixture.dig(:contexts, :prism)
    expect(json_ready(Ast::Merge.plan_named_conformance_suites(plans_fixture[:manifest], contexts))).to eq(
      json_ready(plans_fixture.dig(:expected_entries, :prism))
    )

    executions = report_fixture[:executions]
    entries = Ast::Merge.report_planned_named_conformance_suites(
      Ast::Merge.plan_named_conformance_suites(report_fixture[:manifest],
                                               report_fixture.dig(:options, :prism, :contexts))
    ) do |run|
      key = "#{run[:ref][:family]}:#{run[:ref][:role]}:#{run[:ref][:case]}"
      executions[key.to_sym] || executions[key] || { outcome: 'failed', messages: ['missing execution'] }
    end

    expect(json_ready(Ast::Merge.report_named_conformance_suite_envelope(entries))).to eq(
      json_ready(report_fixture.dig(:expected_reports, :prism))
    )
  end

  it 'rejects unsupported provider backend overrides' do
    result = PRISM_MERGE.parse_ruby("module Demo\nend\n", 'ruby', backend: 'kreuzberg-language-pack')
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to eq(
      [{ severity: 'error', category: 'unsupported_feature',
         message: 'Unsupported Ruby backend kreuzberg-language-pack.' }]
    )
  end
end
