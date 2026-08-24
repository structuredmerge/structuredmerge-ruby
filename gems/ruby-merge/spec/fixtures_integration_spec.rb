# frozen_string_literal: true

require_relative 'spec_helper'

RUBY_MERGE = ::Ruby::Merge

# These structural value objects are shared by the examples below and must be
# defined outside the RSpec example-group block.
RubyMergeSpecSpan = Struct.new(:start_row, :start_col, :end_row, :end_col, keyword_init: true)
RubyMergeSpecStructureItem = Struct.new(:kind, :name, :span, keyword_init: true)
RubyMergeSpecImportItem = Struct.new(:source, :span, keyword_init: true)
RubyMergeSpecProcessAnalysis = Struct.new(:structure, :imports, keyword_init: true)

# This file is a single fixture-conformance contract by design. Keeping the
# examples together makes the fixture paths and backend expectations auditable.
# rubocop:disable Metrics/BlockLength
RSpec.describe 'Ruby::Merge' do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  def process_item(kind:, name:, start_row:, end_row:)
    RubyMergeSpecStructureItem.new(
      kind: kind,
      name: name,
      span: RubyMergeSpecSpan.new(start_row: start_row, start_col: 0, end_row: end_row, end_col: 3)
    )
  end

  def import_item(source:, start_row:, end_row:)
    RubyMergeSpecImportItem.new(
      source: source,
      span: RubyMergeSpecSpan.new(start_row: start_row, start_col: 0, end_row: end_row, end_col: 14)
    )
  end

  def ruby_parse_result(source, process_analysis)
    {
      ok: true,
      diagnostics: [],
      analysis: RUBY_MERGE.analyze_ruby_document(source, process_analysis: process_analysis),
      policies: []
    }
  end

  def expect_unsupported_ruby_merge(result)
    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to contain_exactly(
      hash_including(category: 'unsupported_feature')
    )
  end

  it 'detects Ruby coverage directive spans in the shared substrate detector' do
    spans = Ruby::Merge::BlockDirectiveDetector.new(
      [
        "# simplecov:disable\n",
        "puts 'hidden'\n",
        "# simplecov:enable\n",
        "# :nocov:\n",
        "puts 'legacy hidden'\n",
        "# :nocov:\n"
      ]
    ).detect_spans

    expect(spans.map { |span| [span.kind, span.start_line, span.end_line] }).to eq(
      [[:nocov, 1, 3], [:nocov, 4, 6]]
    )
  end

  it 'filters Ruby directive comments through the shared substrate detector' do
    expect(Ruby::Merge::BlockDirectiveDetector.directive_content?('simplecov:disable')).to be(true)
    expect(Ruby::Merge::BlockDirectiveDetector.directive_content?(':nocov:')).to be(true)
    expect(Ruby::Merge::BlockDirectiveDetector.directive_content?('kettle-jem:freeze')).to be(true)
    expect(Ruby::Merge::BlockDirectiveDetector.directive_content?('@param name [String]')).to be(false)
  end

  it 'parses Ruby doc-comment example blocks through shared substrate support' do
    entries = [
      { line: 10, raw: '# Performs work.' },
      { line: 11, raw: '# @example [Ruby]' },
      { line: 12, raw: '#   worker.call' },
      { line: 13, raw: '# @param worker [Worker]' }
    ]

    expect(Ruby::Merge::DocCommentSupport.doc_comment_content?('# frozen_string_literal: true')).to be(false)
    expect(Ruby::Merge::DocCommentSupport.doc_comment_content?('# simplecov:disable')).to be(false)
    expect(Ruby::Merge::DocCommentSupport.example_blocks(entries)).to contain_exactly(
      hash_including(
        tag_index: 1,
        tag_line: 11,
        tag_text: '@example [Ruby]',
        body_start_index: 2,
        body_end_index: 3,
        body_entries: [{ line: 12, raw: '#   worker.call' }],
        declared_language: 'ruby'
      )
    )
  end

  it 'detects Ruby magic comment header prefixes through shared substrate support' do
    lines = [
      "#!/usr/bin/env ruby\n",
      "# frozen_string_literal: true\n",
      "# warn_indent: true\n",
      "# warn_indent: false\n",
      "\n",
      "# body comment\n"
    ]

    prefix = Ruby::Merge::MagicCommentSupport.comment_only_prefix_info(lines)

    expect(Ruby::Merge::MagicCommentSupport.magic_comment_type_for_text('# coding: UTF-8')).to eq(:encoding)
    expect(prefix[:header_magic_comment_types]).to eq(
      2 => :frozen_string_literal,
      3 => :warn_indent,
      4 => :warn_indent
    )
    expect(prefix[:duplicate_magic_line_nums]).to contain_exactly(4)
    expect(prefix[:suppressed_line_nums]).to include(1, 2, 3, 4, 5)
  end

  it 'does not mix legacy declaration discovery into parser-backed Ruby structure' do
    source = <<~RUBY
      class TemplateOwned
      end

      module LegacyOnly
      end
    RUBY
    process_analysis = RubyMergeSpecProcessAnalysis.new(
      structure: [
        process_item(kind: 'class', name: 'TemplateOwned', start_row: 0, end_row: 1)
      ]
    )

    expect(RUBY_MERGE.collect_ruby_declaration_entries(source, process_analysis: process_analysis)).to contain_exactly(
      hash_including(
        path: '/declarations/TemplateOwned',
        name: 'TemplateOwned',
        kind: 'class',
        merge_key: 'class:TemplateOwned'
      )
    )
    expect(RUBY_MERGE.analyze_ruby_document(source,
                                            process_analysis: process_analysis).fetch(:owners)).to contain_exactly(
                                              {
                                                path: '/declarations/TemplateOwned',
                                                owner_kind: 'declaration',
                                                match_key: 'TemplateOwned'
                                              }
                                            )
  end

  it 'uses TSLP import records for parser-backed Ruby require owners' do
    source = <<~RUBY
      require "json"
      require "set"
    RUBY
    process_analysis = RubyMergeSpecProcessAnalysis.new(
      structure: [],
      imports: [
        import_item(source: 'json', start_row: 0, end_row: 0),
        import_item(source: 'set', start_row: 1, end_row: 1)
      ]
    )

    expect(RUBY_MERGE.analyze_ruby_document(source,
                                            process_analysis: process_analysis).fetch(:owners)).to contain_exactly(
                                              {
                                                path: '/requires/0',
                                                owner_kind: 'require',
                                                match_key: 'json'
                                              },
                                              {
                                                path: '/requires/1',
                                                owner_kind: 'require',
                                                match_key: 'set'
                                              }
                                            )
  end

  it 'derives require imports from the TreeHaver Ruby parse tree', :tslp_ruby_import_records do
    result = RUBY_MERGE.merge_ruby("require \"set\"\n", "require \"json\"\n", 'ruby', merge_template_requires: true)

    expect(result[:ok]).to be(true)
    expect(result[:output]).to include('require "json"')
    expect(result[:output]).to include('require "set"')
  end

  it 'exposes missing TSLP top-level call records as an unsupported capability',
     :not_tslp_ruby_top_level_call_records do
    result = RUBY_MERGE.merge_ruby("task :default do\nend\n", "task :default do\nend\n", 'ruby')

    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to contain_exactly(
      hash_including(
        category: 'unsupported_feature',
        message: include('unsupported top-level content')
      )
    )
  end

  it 'merges the TSLP-backed top-level declaration subset without legacy scanners' do
    template_source = <<~RUBY
      class Existing
        def template_change
          true
        end
      end

      module Added
      end
    RUBY
    destination_source = <<~RUBY
      class Existing
        def destination_owned
          true
        end
      end
    RUBY
    template_process = RubyMergeSpecProcessAnalysis.new(
      structure: [
        process_item(kind: 'class', name: 'Existing', start_row: 0, end_row: 4),
        process_item(kind: 'module', name: 'Added', start_row: 6, end_row: 7)
      ],
      imports: []
    )
    destination_process = RubyMergeSpecProcessAnalysis.new(
      structure: [
        process_item(kind: 'class', name: 'Existing', start_row: 0, end_row: 4)
      ],
      imports: []
    )

    allow(RUBY_MERGE).to receive(:parse_ruby) do |source, dialect|
      expect(dialect).to eq('ruby')
      if source == template_source
        ruby_parse_result(source,
                          template_process)
      else
        ruby_parse_result(source, destination_process)
      end
    end

    result = RUBY_MERGE.merge_ruby(template_source, destination_source, 'ruby')

    expect(result[:ok]).to be(true)
    expect(result[:output]).to include('def destination_owned')
    expect(result[:output]).to include('def template_change')
    expect(result[:output]).to include('module Added')
    expect(result.dig(:merge_planning, :intra_owner_merges, :strategy)).to eq('destination_wins_scoped_owner_body')
  end

  it 'preserves destination-owned blank gaps between retained top-level Ruby owners' do
    template_source = <<~RUBY
      class Existing
      end

      class Kept
      end
    RUBY
    destination_source = "class Existing\nend\n\n\nclass Kept\nend\n"
    template_process = RubyMergeSpecProcessAnalysis.new(
      structure: [
        process_item(kind: 'class', name: 'Existing', start_row: 0, end_row: 1),
        process_item(kind: 'class', name: 'Kept', start_row: 3, end_row: 4)
      ],
      imports: []
    )
    destination_process = RubyMergeSpecProcessAnalysis.new(
      structure: [
        process_item(kind: 'class', name: 'Existing', start_row: 0, end_row: 1),
        process_item(kind: 'class', name: 'Kept', start_row: 4, end_row: 5)
      ],
      imports: []
    )

    allow(RUBY_MERGE).to receive(:parse_ruby) do |source, dialect|
      expect(dialect).to eq('ruby')
      ruby_parse_result(source, source == template_source ? template_process : destination_process)
    end

    result = RUBY_MERGE.merge_ruby(template_source, destination_source, 'ruby')

    expect(result[:ok]).to be(true)
    expect(result[:output]).to eq(destination_source)
  end

  it 'fails closed when the TSLP-backed Ruby merge sees unmodeled top-level content' do
    template_source = <<~RUBY
      class Existing
      end
    RUBY
    destination_source = <<~RUBY
      class Existing
      end

      puts "unmodeled"
    RUBY
    template_process = RubyMergeSpecProcessAnalysis.new(
      structure: [process_item(kind: 'class', name: 'Existing', start_row: 0, end_row: 1)],
      imports: []
    )
    destination_process = RubyMergeSpecProcessAnalysis.new(
      structure: [process_item(kind: 'class', name: 'Existing', start_row: 0, end_row: 1)],
      imports: []
    )

    allow(RUBY_MERGE).to receive(:parse_ruby) do |source, _dialect|
      if source == template_source
        ruby_parse_result(source,
                          template_process)
      else
        ruby_parse_result(source, destination_process)
      end
    end

    result = RUBY_MERGE.merge_ruby(template_source, destination_source, 'ruby')

    expect(result[:ok]).to be(false)
    expect(result[:diagnostics]).to contain_exactly(
      hash_including(
        category: 'unsupported_feature',
        message: include('destination has unsupported top-level content on line(s) 4')
      )
    )
  end

  it 'conforms to the Ruby family substrate fixtures' do
    feature_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-214-ruby-family-feature-profile', 'ruby-feature-profile.json')
    )
    backend_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-215-ruby-family-backend-feature-profiles',
        'ruby-ruby-backend-feature-profiles.json'
      )
    )
    plan_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-216-ruby-family-plan-contexts', 'ruby-ruby-plan-contexts.json')
    )
    manifest_fixture = read_json(
      fixtures_root.join('conformance', 'slice-217-ruby-family-manifest', 'ruby-family-manifest.json')
    )
    analysis_fixture = read_json(fixtures_root.join('ruby', 'slice-218-analysis', 'module-owners.json'))
    matching_fixture = read_json(fixtures_root.join('ruby', 'slice-219-matching', 'path-equality.json'))
    surfaces_fixture = read_json(
      fixtures_root.join('ruby', 'slice-220-discovered-surfaces', 'doc-comment-surfaces.json')
    )
    child_fixture = read_json(
      fixtures_root.join('ruby', 'slice-221-delegated-child-operations', 'yard-example-child-operations.json')
    )

    expect(json_ready(RUBY_MERGE.ruby_feature_profile)).to eq(json_ready(feature_fixture[:feature_profile]))
    expect(json_ready(RUBY_MERGE.available_ruby_backends.map(&:to_h))).to eq(
      json_ready([{ id: 'kreuzberg-language-pack', family: 'tree-sitter' }])
    )
    expect(json_ready(TreeHaver::BackendRegistry.fetch('kreuzberg-language-pack')&.to_h)).to eq(
      json_ready({ id: 'kreuzberg-language-pack', family: 'tree-sitter' })
    )
    expect(json_ready(RUBY_MERGE.ruby_backend_feature_profile)).to eq(
      json_ready(backend_fixture[:tree_sitter].merge(family: 'ruby', supported_dialects: ['ruby']))
    )
    expect(json_ready(RUBY_MERGE.ruby_plan_context)).to eq(json_ready(plan_fixture[:tree_sitter]))
    expect(Ast::Merge.conformance_fixture_path(manifest_fixture, 'ruby', 'analysis')).to eq(
      %w[ruby slice-218-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest_fixture, 'ruby', 'merge')).to eq(
      %w[ruby slice-287-merge module-merge.json]
    )

    analysis = RUBY_MERGE.parse_ruby(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expected_owners = analysis_fixture.dig(:expected, :owners)
    unless TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expected_owners = expected_owners.reject do |owner|
        owner[:owner_kind] == 'require'
      end
    end
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(expected_owners))

    source_region_fixture = read_json(
      fixtures_root.join('ruby', 'slice-977-source-region-analysis', 'class-method-source-regions.json')
    )
    source_regions = RUBY_MERGE.ruby_source_regions(source_region_fixture[:source])
    expect(json_ready(source_regions)).to eq(json_ready(source_region_fixture[:expected]))
    file_edge_region_fixture = read_json(
      fixtures_root.join('ruby', 'slice-977-source-region-analysis', 'file-header-footer-regions.json')
    )
    file_edge_regions = RUBY_MERGE.ruby_source_regions(file_edge_region_fixture[:source])
    expect(json_ready(file_edge_regions)).to eq(json_ready(file_edge_region_fixture[:expected]))

    owner_identity_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-981-source-owner-identity-profile',
        'class-method-identity-profile.json'
      )
    )
    owner_identities = RUBY_MERGE.ruby_source_owner_identity_profile(owner_identity_fixture[:source])
    expect(json_ready(owner_identities)).to eq(json_ready(owner_identity_fixture.dig(:expected, :identities)))

    owner_matching_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-982-duplicate-owner-ordered-matching',
        'duplicate-method-ordered-matching.json'
      )
    )
    owner_matches = RUBY_MERGE.ruby_source_owner_identity_matches(
      owner_matching_fixture[:template],
      owner_matching_fixture[:destination]
    )
    expect(json_ready(owner_matches)).to eq(json_ready(owner_matching_fixture[:expected]))
    ambiguous_identity_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-984-ambiguous-visibility-owner-identity',
        'visibility-duplicate-method-identity.json'
      )
    )
    ambiguous_identity = RUBY_MERGE.ruby_ambiguous_source_owner_identity_report(
      ambiguous_identity_fixture[:source]
    )
    expect(json_ready(ambiguous_identity)).to eq(json_ready(ambiguous_identity_fixture[:expected]))

    rename_detection_fixture = read_json(
      fixtures_root.join('ruby', 'slice-985-clean-rename-detection', 'clean-method-rename.json')
    )
    rename_detection = RUBY_MERGE.ruby_rename_detection(
      rename_detection_fixture[:template],
      rename_detection_fixture[:destination]
    )
    expect(json_ready(rename_detection)).to eq(json_ready(rename_detection_fixture[:expected]))
    rename_conflict_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-986-rename-plus-edit-conflict',
        'rename-plus-edit-conflict.json'
      )
    )
    rename_conflicts = RUBY_MERGE.ruby_rename_plus_edit_conflicts(
      rename_conflict_fixture[:base],
      rename_conflict_fixture[:template],
      rename_conflict_fixture[:destination]
    )
    expect(json_ready(rename_conflicts)).to eq(json_ready(rename_conflict_fixture[:expected]))
    cross_container_move_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-987-cross-container-method-move',
        'cross-container-method-move.json'
      )
    )
    cross_container_move = RUBY_MERGE.ruby_cross_container_method_move_detection(
      cross_container_move_fixture[:template],
      cross_container_move_fixture[:destination]
    )
    expect(json_ready(cross_container_move)).to eq(json_ready(cross_container_move_fixture[:expected]))

    interstitial_require_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-988-interstitial-require-merge',
        'require-ordering-interstitial-merge.json'
      )
    )
    interstitial_require_merge = RUBY_MERGE.merge_ruby(
      interstitial_require_fixture[:template],
      interstitial_require_fixture[:destination],
      interstitial_require_fixture[:dialect],
      merge_template_requires: true
    )
    expect(json_ready(RUBY_MERGE.ruby_interstitial_merge_policy_profile)).to eq(
      json_ready(interstitial_require_fixture.dig(:expected, :policy))
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(interstitial_require_merge[:ok]).to eq(interstitial_require_fixture.dig(:expected, :merge, :ok))
      expect(interstitial_require_merge[:output]).to eq(interstitial_require_fixture.dig(:expected, :merge, :output))
    else
      expect(interstitial_require_merge[:ok]).to be(false)
      expect(interstitial_require_merge[:diagnostics]).to contain_exactly(
        hash_including(category: 'unsupported_feature')
      )
    end
    interstitial_comment_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-989-interstitial-comment-attachment',
        'interstitial-comment-attachment.json'
      )
    )
    interstitial_comments = RUBY_MERGE.ruby_interstitial_comment_attachment_report(
      interstitial_comment_fixture[:source]
    )
    expect(json_ready(interstitial_comments)).to eq(json_ready(interstitial_comment_fixture[:expected]))
    blank_line_fixture = read_json(
      fixtures_root.join('ruby', 'slice-990-blank-line-ownership', 'blank-line-ownership.json')
    )
    blank_line_ownership = RUBY_MERGE.ruby_blank_line_ownership_report(blank_line_fixture[:source])
    expect(json_ready(blank_line_ownership)).to eq(json_ready(blank_line_fixture[:expected]))
    file_edge_fixture = read_json(
      fixtures_root.join('ruby', 'slice-991-file-edge-merge', 'file-edge-merge.json')
    )
    file_edge_merge = RUBY_MERGE.merge_ruby(
      file_edge_fixture[:template],
      file_edge_fixture[:destination],
      file_edge_fixture[:dialect]
    )
    expect(file_edge_merge[:ok]).to eq(file_edge_fixture.dig(:expected, :ok))
    expect(file_edge_merge[:output]).to eq(file_edge_fixture.dig(:expected, :output))
    child_group_profile_fixture = read_json(
      fixtures_root.join('ruby', 'slice-992-child-group-profile', 'ruby-child-group-profile.json')
    )
    expect(json_ready(RUBY_MERGE.ruby_child_group_profile)).to eq(
      json_ready(child_group_profile_fixture[:expected])
    )

    fallback_policy_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-983-fallback-policy-profile',
        'ruby-fallback-policy-profile.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_fallback_policy_profile)).to eq(
      json_ready(fallback_policy_fixture[:expected])
    )
    fallback_activation_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-993-fallback-activation-report',
        'ruby-fallback-activation-report.json'
      )
    )
    fallback_activation = RUBY_MERGE.ruby_fallback_activation_report(
      reason: fallback_activation_fixture.dig(:expected, :reason),
      scope: fallback_activation_fixture.dig(:expected, :scope)
    )
    expect(json_ready(fallback_activation)).to eq(json_ready(fallback_activation_fixture[:expected]))
    never_worse_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-994-never-worse-fallback-mode',
        'ruby-never-worse-fallback-mode.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_never_worse_fallback_mode)).to eq(
      json_ready(never_worse_fixture[:expected])
    )
    fallback_scope_guard_fixture = read_json(
      fixtures_root.join('ruby', 'slice-995-fallback-scope-guard', 'ruby-fallback-scope-guard.json')
    )
    fallback_scope_guard = RUBY_MERGE.ruby_fallback_scope_guard_report(
      requested_scope: fallback_scope_guard_fixture.dig(:expected, :requested_scope),
      declared_scope: fallback_scope_guard_fixture.dig(:expected, :declared_scope)
    )
    expect(json_ready(fallback_scope_guard)).to eq(json_ready(fallback_scope_guard_fixture[:expected]))
    validation_profile_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-996-post-merge-validation-profile',
        'ruby-post-merge-validation-profile.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_post_merge_validation_profile)).to eq(
      json_ready(validation_profile_fixture[:expected])
    )
    data_loss_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-997-silent-data-loss-validation',
        'silent-data-loss-validation.json'
      )
    )
    data_loss_validation = RUBY_MERGE.ruby_silent_data_loss_validation_report(
      template_source: data_loss_fixture[:template],
      destination_source: data_loss_fixture[:destination],
      output: data_loss_fixture[:output]
    )
    expect(json_ready(data_loss_validation)).to eq(json_ready(data_loss_fixture[:expected]))
    conflict_diagnostics_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-998-conflict-diagnostics-profile',
        'ruby-conflict-diagnostics-profile.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_conflict_diagnostics_profile)).to eq(
      json_ready(conflict_diagnostics_fixture[:expected])
    )
    formatter_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-999-formatter-adapter-policy',
        'ruby-formatter-adapter-policy.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_formatter_policy_profile)).to eq(
      json_ready(formatter_fixture.dig(:expected, :policy))
    )
    formatter_report = RUBY_MERGE.ruby_formatter_adapter_report(
      pre_format_output: formatter_fixture[:pre_format_output],
      formatted_output: formatter_fixture[:formatted_output],
      policy: formatter_fixture.dig(:expected, :adapter_report, :policy),
      conflict_scope: formatter_fixture.dig(:expected, :adapter_report, :conflict_scope)
    )
    expect(json_ready(formatter_report)).to eq(json_ready(formatter_fixture.dig(:expected, :adapter_report)))
    ast_node_merge_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-1000-ast-node-merge-strategy',
        'ruby-ast-node-merge-strategy.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_ast_node_merge_strategy_profile)).to eq(
      json_ready(ast_node_merge_fixture.dig(:expected, :profile))
    )
    expression_candidate = ast_node_merge_fixture[:expression_level_candidate]
    expression_report = RUBY_MERGE.ruby_ast_node_merge_candidate_report(
      surface: expression_candidate[:surface],
      base: expression_candidate[:base],
      template: expression_candidate[:template],
      destination: expression_candidate[:destination]
    )
    expect(json_ready(expression_report)).to eq(
      json_ready(ast_node_merge_fixture.dig(:expected, :expression_level_report))
    )
    risky_candidate = ast_node_merge_fixture[:risky_reconstruction_candidate]
    risky_report = RUBY_MERGE.ruby_ast_node_merge_candidate_report(
      surface: risky_candidate[:surface],
      base: risky_candidate[:base],
      template: risky_candidate[:template],
      destination: risky_candidate[:destination],
      reconstruction_risk: true
    )
    expect(json_ready(risky_report)).to eq(
      json_ready(ast_node_merge_fixture.dig(:expected, :risky_reconstruction_report))
    )
    vcs_tool_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-1001-vcs-tool-integration',
        'ruby-vcs-tool-integration.json'
      )
    )
    expect(json_ready(RUBY_MERGE.ruby_vcs_tool_integration_profile)).to eq(
      json_ready(vcs_tool_fixture.dig(:expected, :profile))
    )
    invocation = vcs_tool_fixture[:sample_invocation]
    invocation_report = RUBY_MERGE.ruby_vcs_tool_invocation_report(
      host: invocation[:host],
      event: invocation[:event],
      path: invocation[:path],
      timeout_ms: invocation[:timeout_ms]
    )
    expect(json_ready(invocation_report)).to eq(
      json_ready(vcs_tool_fixture.dig(:expected, :invocation_report))
    )

    shadowing_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-960-duplicate-method-shadowing-projection',
        'duplicate-method-shadowing.json'
      )
    )
    shadowing_analysis = RUBY_MERGE.parse_ruby(shadowing_fixture[:source], shadowing_fixture[:dialect])
    expect(shadowing_analysis[:ok]).to be(true)
    expect(json_ready(shadowing_analysis.dig(:analysis, :method_shadowing))).to eq(
      json_ready(shadowing_fixture.dig(:expected, :method_shadowing))
    )
    expect(json_ready(shadowing_analysis.dig(:analysis, :diagnostics))).to eq(
      json_ready(shadowing_fixture.dig(:expected, :diagnostics))
    )

    method_move_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-961-method-move-detection-projection',
        'method-move-detection-projection.json'
      )
    )
    method_move_report = RUBY_MERGE.ruby_method_move_detection(
      method_move_fixture[:template],
      method_move_fixture[:destination],
      method_move_fixture[:dialect]
    )
    method_move_count = method_move_report[:matches].count { |entry| entry[:moved] }
    expect(method_move_report[:strategy]).to eq(method_move_fixture.dig(:expected, :strategy))
    expect(method_move_report.dig(:capability, :name)).to eq(method_move_fixture.dig(:expected, :capability))
    expect(method_move_report.dig(:capability, :enabled)).to eq(method_move_fixture.dig(:expected, :enabled))
    expect(method_move_report.dig(:capability,
                                  :default_enabled)).to eq(method_move_fixture.dig(:expected, :default_enabled))
    expect(method_move_report.dig(:capability, :requires_stable_node_identity)).to eq(
      method_move_fixture.dig(:expected, :requires_stable_node_identity)
    )
    expect(method_move_report[:matches].length).to eq(method_move_fixture.dig(:expected, :match_count))
    expect(method_move_count).to eq(method_move_fixture.dig(:expected, :move_count))
    expect(method_move_report.dig(:matches, 0,
                                  :signature)).to eq(method_move_fixture.dig(:expected, :first_moved_signature))
    expect(method_move_report.dig(:matches, 0,
                                  :from_index)).to eq(method_move_fixture.dig(:expected, :first_moved_from_index))
    expect(method_move_report.dig(:matches, 0,
                                  :to_index)).to eq(method_move_fixture.dig(:expected, :first_moved_to_index))

    merge_move_report_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-968-merge-move-detection-report',
        'merge-move-detection-report.json'
      )
    )
    merge_move_result = RUBY_MERGE.merge_ruby(
      merge_move_report_fixture[:template],
      merge_move_report_fixture[:destination],
      'ruby'
    )
    merge_matching_report = merge_move_result.fetch(:matching_reports).first
    merge_move_count = merge_matching_report.fetch(:matches).count { |entry| entry.fetch(:moved) }
    expect(merge_move_result[:ok]).to eq(merge_move_report_fixture.dig(:expected, :ok))
    expect(merge_move_result[:output]).to eq(merge_move_report_fixture.dig(:expected, :output))
    expect(merge_move_result.fetch(:matching_reports).length).to eq(
      merge_move_report_fixture.dig(:expected, :matching_report_count)
    )
    expect(merge_matching_report[:matching_id]).to eq(merge_move_report_fixture.dig(:expected, :matching_id))
    expect(merge_matching_report[:strategy]).to eq(merge_move_report_fixture.dig(:expected, :strategy))
    expect(merge_move_count).to eq(merge_move_report_fixture.dig(:expected, :move_count))
    expect(merge_matching_report.dig(:capability, :default_enabled)).to be(false)

    destination_order_move_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-969-move-detection-destination-order-policy',
        'move-detection-destination-order-policy.json'
      )
    )
    destination_order_move_result = RUBY_MERGE.merge_ruby(
      destination_order_move_fixture[:template],
      destination_order_move_fixture[:destination],
      'ruby'
    )
    destination_order_move_count = destination_order_move_result.dig(
      :merge_planning,
      :method_move_detection,
      :moved_method_count
    )
    expect(destination_order_move_result[:ok]).to eq(destination_order_move_fixture.dig(:expected, :ok))
    expect(destination_order_move_result[:output]).to eq(destination_order_move_fixture.dig(:expected, :output))
    expect(destination_order_move_result.dig(:merge_planning, :method_move_policy)).to eq(
      destination_order_move_fixture.dig(:expected, :method_move_policy)
    )
    expect(destination_order_move_result.dig(:merge_planning, :method_move_detection,
                                             :preserves_destination_order)).to eq(
                                               destination_order_move_fixture.dig(:expected,
                                                                                  :preserves_destination_order)
                                             )
    expect(destination_order_move_result.dig(:merge_planning, :method_move_detection,
                                             :suppresses_duplicate_moved_methods)).to eq(
                                               destination_order_move_fixture.dig(:expected,
                                                                                  :suppresses_duplicate_moved_methods)
                                             )
    expect(destination_order_move_count).to eq(destination_order_move_fixture.dig(:expected, :move_count))

    template = RUBY_MERGE.parse_ruby(matching_fixture[:template], matching_fixture[:dialect])
    destination = RUBY_MERGE.parse_ruby(matching_fixture[:destination], matching_fixture[:dialect])
    matching = RUBY_MERGE.match_ruby_owners(template[:analysis], destination[:analysis])
    expected_matches = matching_fixture.dig(:expected, :matched)
    unless TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expected_matches = expected_matches.reject do |template_path, _destination_path|
        template_path.start_with?('/requires/')
      end
    end
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(expected_matches)
    )
    expect(json_ready(matching[:unmatched_template])).to eq(json_ready(matching_fixture.dig(:expected,
                                                                                            :unmatched_template)))
    expect(json_ready(matching[:unmatched_destination])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_destination))
    )

    merge_fixture = read_json(fixtures_root.join('ruby', 'slice-287-merge', 'module-merge.json'))
    merge_result = RUBY_MERGE.merge_ruby(merge_fixture[:template], merge_fixture[:destination], 'ruby')
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
      expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))
    else
      expect(merge_result[:ok]).to be(false)
      expect(merge_result[:diagnostics]).to contain_exactly(
        hash_including(category: 'unsupported_feature')
      )
    end

    child_group_merge_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-978-independent-method-child-group-merge',
        'independent-method-additions.json'
      )
    )
    child_group_merge_result = RUBY_MERGE.merge_ruby(
      child_group_merge_fixture[:template],
      child_group_merge_fixture[:destination],
      child_group_merge_fixture[:dialect]
    )
    expect(child_group_merge_result[:ok]).to eq(child_group_merge_fixture.dig(:expected, :ok))
    expect(child_group_merge_result[:output]).to eq(child_group_merge_fixture.dig(:expected, :output))

    top_level_owner_merge_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-979-independent-function-owner-merge',
        'independent-function-additions.json'
      )
    )
    top_level_owner_merge_result = RUBY_MERGE.merge_ruby(
      top_level_owner_merge_fixture[:template],
      top_level_owner_merge_fixture[:destination],
      top_level_owner_merge_fixture[:dialect]
    )
    expect(top_level_owner_merge_result[:ok]).to eq(top_level_owner_merge_fixture.dig(:expected, :ok))
    expect(top_level_owner_merge_result[:output]).to eq(top_level_owner_merge_fixture.dig(:expected, :output))

    intra_owner_merge_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-980-same-owner-intra-owner-merge',
        'method-body-destination-wins.json'
      )
    )
    intra_owner_merge_result = RUBY_MERGE.merge_ruby(
      intra_owner_merge_fixture[:template],
      intra_owner_merge_fixture[:destination],
      intra_owner_merge_fixture[:dialect]
    )
    expect(intra_owner_merge_result[:ok]).to eq(intra_owner_merge_fixture.dig(:expected, :ok))
    expect(intra_owner_merge_result[:output]).to eq(intra_owner_merge_fixture.dig(:expected, :output))
    expect(json_ready(intra_owner_merge_result.dig(:merge_planning, :intra_owner_merges))).to eq(
      json_ready(intra_owner_merge_fixture.dig(:expected, :merge_planning, :intra_owner_merges))
    )

    advanced_leaf_fixture = read_json(
      fixtures_root.join('ruby', 'slice-720-advanced-leaf-merge', 'class-hash-leaf-merge.json')
    )
    advanced_leaf_result = RUBY_MERGE.merge_ruby(
      advanced_leaf_fixture[:template],
      advanced_leaf_fixture[:destination],
      'ruby'
    )
    expect(advanced_leaf_result[:ok]).to eq(advanced_leaf_fixture.dig(:expected, :ok))
    expect(advanced_leaf_result[:output]).to eq(advanced_leaf_fixture.dig(:expected, :output))

    class_method_fixture = read_json(
      fixtures_root.join('ruby', 'slice-941-template-only-class-method-merge', 'class-method-merge.json')
    )
    class_method_result = RUBY_MERGE.merge_ruby(
      class_method_fixture[:template],
      class_method_fixture[:destination],
      'ruby'
    )
    expect(class_method_result[:ok]).to eq(class_method_fixture.dig(:expected, :ok))
    expect(class_method_result[:output]).to eq(class_method_fixture.dig(:expected, :output))

    method_visibility_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-942-template-only-method-visibility-ordering',
        'public-method-before-private-section.json'
      )
    )
    method_visibility_result = RUBY_MERGE.merge_ruby(
      method_visibility_fixture[:template],
      method_visibility_fixture[:destination],
      'ruby'
    )
    expect(method_visibility_result[:ok]).to eq(method_visibility_fixture.dig(:expected, :ok))
    expect(method_visibility_result[:output]).to eq(method_visibility_fixture.dig(:expected, :output))

    nested_class_fixture = read_json(
      fixtures_root.join('ruby', 'slice-943-nested-class-method-merge', 'nested-class-method-merge.json')
    )
    nested_class_result = RUBY_MERGE.merge_ruby(
      nested_class_fixture[:template],
      nested_class_fixture[:destination],
      'ruby'
    )
    expect(nested_class_result[:ok]).to eq(nested_class_fixture.dig(:expected, :ok))
    expect(nested_class_result[:output]).to eq(nested_class_fixture.dig(:expected, :output))

    template_nested_class_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-944-template-only-nested-declaration-merge',
        'template-only-nested-class-merge.json'
      )
    )
    template_nested_class_result = RUBY_MERGE.merge_ruby(
      template_nested_class_fixture[:template],
      template_nested_class_fixture[:destination],
      'ruby'
    )
    expect(template_nested_class_result[:ok]).to eq(template_nested_class_fixture.dig(:expected, :ok))
    expect(template_nested_class_result[:output]).to eq(template_nested_class_fixture.dig(:expected, :output))

    private_method_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-945-template-owned-private-method-merge',
        'private-method-section-merge.json'
      )
    )
    private_method_result = RUBY_MERGE.merge_ruby(
      private_method_fixture[:template],
      private_method_fixture[:destination],
      'ruby'
    )
    expect(private_method_result[:ok]).to eq(private_method_fixture.dig(:expected, :ok))
    expect(private_method_result[:output]).to eq(private_method_fixture.dig(:expected, :output))

    existing_private_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-946-existing-private-section-method-merge',
        'private-method-into-existing-section.json'
      )
    )
    existing_private_result = RUBY_MERGE.merge_ruby(
      existing_private_fixture[:template],
      existing_private_fixture[:destination],
      'ruby'
    )
    expect(existing_private_result[:ok]).to eq(existing_private_fixture.dig(:expected, :ok))
    expect(existing_private_result[:output]).to eq(existing_private_fixture.dig(:expected, :output))

    protected_method_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-947-template-owned-protected-method-merge',
        'protected-method-section-merge.json'
      )
    )
    protected_method_result = RUBY_MERGE.merge_ruby(
      protected_method_fixture[:template],
      protected_method_fixture[:destination],
      'ruby'
    )
    expect(protected_method_result[:ok]).to eq(protected_method_fixture.dig(:expected, :ok))
    expect(protected_method_result[:output]).to eq(protected_method_fixture.dig(:expected, :output))

    existing_protected_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-948-existing-protected-section-method-merge',
        'protected-method-into-existing-section.json'
      )
    )
    existing_protected_result = RUBY_MERGE.merge_ruby(
      existing_protected_fixture[:template],
      existing_protected_fixture[:destination],
      'ruby'
    )
    expect(existing_protected_result[:ok]).to eq(existing_protected_fixture.dig(:expected, :ok))
    expect(existing_protected_result[:output]).to eq(existing_protected_fixture.dig(:expected, :output))

    public_method_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-949-template-public-method-merge',
        'public-method-without-marker.json'
      )
    )
    public_method_result = RUBY_MERGE.merge_ruby(
      public_method_fixture[:template],
      public_method_fixture[:destination],
      'ruby'
    )
    expect(public_method_result[:ok]).to eq(public_method_fixture.dig(:expected, :ok))
    expect(public_method_result[:output]).to eq(public_method_fixture.dig(:expected, :output))

    existing_public_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-950-existing-public-section-method-merge',
        'public-method-into-existing-section.json'
      )
    )
    existing_public_result = RUBY_MERGE.merge_ruby(
      existing_public_fixture[:template],
      existing_public_fixture[:destination],
      'ruby'
    )
    expect(existing_public_result[:ok]).to eq(existing_public_fixture.dig(:expected, :ok))
    expect(existing_public_result[:output]).to eq(existing_public_fixture.dig(:expected, :output))

    template_constant_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-951-template-only-class-constant-merge',
        'template-only-class-constant.json'
      )
    )
    template_constant_result = RUBY_MERGE.merge_ruby(
      template_constant_fixture[:template],
      template_constant_fixture[:destination],
      'ruby'
    )
    expect(template_constant_result[:ok]).to eq(template_constant_fixture.dig(:expected, :ok))
    expect(template_constant_result[:output]).to eq(template_constant_fixture.dig(:expected, :output))

    array_constant_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-952-class-array-constant-merge',
        'class-array-constant-merge.json'
      )
    )
    array_constant_result = RUBY_MERGE.merge_ruby(
      array_constant_fixture[:template],
      array_constant_fixture[:destination],
      'ruby'
    )
    expect(array_constant_result[:ok]).to eq(array_constant_fixture.dig(:expected, :ok))
    expect(array_constant_result[:output]).to eq(array_constant_fixture.dig(:expected, :output))

    multiline_array_constant_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-953-multiline-array-constant-merge',
        'multiline-array-constant-merge.json'
      )
    )
    multiline_array_constant_result = RUBY_MERGE.merge_ruby(
      multiline_array_constant_fixture[:template],
      multiline_array_constant_fixture[:destination],
      'ruby'
    )
    expect(multiline_array_constant_result[:ok]).to eq(multiline_array_constant_fixture.dig(:expected, :ok))
    expect(multiline_array_constant_result[:output]).to eq(multiline_array_constant_fixture.dig(:expected, :output))

    no_trailing_comma_array_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-962-multiline-array-no-trailing-comma-merge',
        'multiline-array-no-trailing-comma-merge.json'
      )
    )
    no_trailing_comma_array_result = RUBY_MERGE.merge_ruby(
      no_trailing_comma_array_fixture[:template],
      no_trailing_comma_array_fixture[:destination],
      'ruby'
    )
    expect(no_trailing_comma_array_result[:ok]).to eq(no_trailing_comma_array_fixture.dig(:expected, :ok))
    expect(no_trailing_comma_array_result[:output]).to eq(no_trailing_comma_array_fixture.dig(:expected, :output))

    percent_word_array_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-963-percent-word-array-constant-merge',
        'percent-word-array-constant-merge.json'
      )
    )
    percent_word_array_result = RUBY_MERGE.merge_ruby(
      percent_word_array_fixture[:template],
      percent_word_array_fixture[:destination],
      'ruby'
    )
    expect(percent_word_array_result[:ok]).to eq(percent_word_array_fixture.dig(:expected, :ok))
    expect(percent_word_array_result[:output]).to eq(percent_word_array_fixture.dig(:expected, :output))

    uppercase_percent_array_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-967-uppercase-percent-array-constant-merge',
        'uppercase-percent-array-constant-merge.json'
      )
    )
    uppercase_percent_array_result = RUBY_MERGE.merge_ruby(
      uppercase_percent_array_fixture[:template],
      uppercase_percent_array_fixture[:destination],
      'ruby'
    )
    expect(uppercase_percent_array_result[:ok]).to eq(uppercase_percent_array_fixture.dig(:expected, :ok))
    expect(uppercase_percent_array_result[:output]).to eq(uppercase_percent_array_fixture.dig(:expected, :output))

    alternate_percent_array_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-972-percent-array-alternate-delimiter-merge',
        'percent-array-alternate-delimiter-merge.json'
      )
    )
    alternate_percent_array_result = RUBY_MERGE.merge_ruby(
      alternate_percent_array_fixture[:template],
      alternate_percent_array_fixture[:destination],
      'ruby'
    )
    expect(alternate_percent_array_result[:ok]).to eq(alternate_percent_array_fixture.dig(:expected, :ok))
    expect(alternate_percent_array_result[:output]).to eq(alternate_percent_array_fixture.dig(:expected, :output))

    custom_percent_array_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-973-percent-array-custom-delimiter-merge',
        'percent-array-custom-delimiter-merge.json'
      )
    )
    custom_percent_array_result = RUBY_MERGE.merge_ruby(
      custom_percent_array_fixture[:template],
      custom_percent_array_fixture[:destination],
      'ruby'
    )
    expect(custom_percent_array_result[:ok]).to eq(custom_percent_array_fixture.dig(:expected, :ok))
    expect(custom_percent_array_result[:output]).to eq(custom_percent_array_fixture.dig(:expected, :output))

    hash_destination_style_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-964-hash-constant-destination-style-merge',
        'hash-constant-destination-style-merge.json'
      )
    )
    hash_destination_style_result = RUBY_MERGE.merge_ruby(
      hash_destination_style_fixture[:template],
      hash_destination_style_fixture[:destination],
      'ruby'
    )
    expect(hash_destination_style_result[:ok]).to eq(hash_destination_style_fixture.dig(:expected, :ok))
    expect(hash_destination_style_result[:output]).to eq(hash_destination_style_fixture.dig(:expected, :output))

    hash_rocket_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-965-hash-rocket-constant-merge',
        'hash-rocket-constant-merge.json'
      )
    )
    hash_rocket_result = RUBY_MERGE.merge_ruby(
      hash_rocket_fixture[:template],
      hash_rocket_fixture[:destination],
      'ruby'
    )
    expect(hash_rocket_result[:ok]).to eq(hash_rocket_fixture.dig(:expected, :ok))
    expect(hash_rocket_result[:output]).to eq(hash_rocket_fixture.dig(:expected, :output))

    string_hash_rocket_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-966-string-hash-rocket-constant-merge',
        'string-hash-rocket-constant-merge.json'
      )
    )
    string_hash_rocket_result = RUBY_MERGE.merge_ruby(
      string_hash_rocket_fixture[:template],
      string_hash_rocket_fixture[:destination],
      'ruby'
    )
    expect(string_hash_rocket_result[:ok]).to eq(string_hash_rocket_fixture.dig(:expected, :ok))
    expect(string_hash_rocket_result[:output]).to eq(string_hash_rocket_fixture.dig(:expected, :output))

    multiline_hash_trailing_comma_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-971-multiline-hash-trailing-comma-merge',
        'multiline-hash-trailing-comma-merge.json'
      )
    )
    multiline_hash_trailing_comma_result = RUBY_MERGE.merge_ruby(
      multiline_hash_trailing_comma_fixture[:template],
      multiline_hash_trailing_comma_fixture[:destination],
      'ruby'
    )
    expect(multiline_hash_trailing_comma_result[:ok]).to eq(multiline_hash_trailing_comma_fixture.dig(:expected, :ok))
    expect(multiline_hash_trailing_comma_result[:output]).to eq(multiline_hash_trailing_comma_fixture.dig(:expected,
                                                                                                          :output))

    hash_predicate_bang_key_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-974-hash-predicate-bang-key-merge',
        'hash-predicate-bang-key-merge.json'
      )
    )
    hash_predicate_bang_key_result = RUBY_MERGE.merge_ruby(
      hash_predicate_bang_key_fixture[:template],
      hash_predicate_bang_key_fixture[:destination],
      'ruby'
    )
    expect(hash_predicate_bang_key_result[:ok]).to eq(hash_predicate_bang_key_fixture.dig(:expected, :ok))
    expect(hash_predicate_bang_key_result[:output]).to eq(hash_predicate_bang_key_fixture.dig(:expected, :output))

    hash_quoted_label_key_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-975-hash-quoted-label-key-merge',
        'hash-quoted-label-key-merge.json'
      )
    )
    hash_quoted_label_key_result = RUBY_MERGE.merge_ruby(
      hash_quoted_label_key_fixture[:template],
      hash_quoted_label_key_fixture[:destination],
      'ruby'
    )
    expect(hash_quoted_label_key_result[:ok]).to eq(hash_quoted_label_key_fixture.dig(:expected, :ok))
    expect(hash_quoted_label_key_result[:output]).to eq(hash_quoted_label_key_fixture.dig(:expected, :output))

    nested_constant_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-954-nested-class-constant-merge',
        'nested-class-constant-merge.json'
      )
    )
    nested_constant_result = RUBY_MERGE.merge_ruby(
      nested_constant_fixture[:template],
      nested_constant_fixture[:destination],
      'ruby'
    )
    expect(nested_constant_result[:ok]).to eq(nested_constant_fixture.dig(:expected, :ok))
    expect(nested_constant_result[:output]).to eq(nested_constant_fixture.dig(:expected, :output))

    receiver_aware_method_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-955-class-instance-method-signature-merge',
        'class-instance-method-signature-merge.json'
      )
    )
    receiver_aware_method_result = RUBY_MERGE.merge_ruby(
      receiver_aware_method_fixture[:template],
      receiver_aware_method_fixture[:destination],
      'ruby'
    )
    expect(receiver_aware_method_result[:ok]).to eq(receiver_aware_method_fixture.dig(:expected, :ok))
    expect(receiver_aware_method_result[:output]).to eq(receiver_aware_method_fixture.dig(:expected, :output))

    operator_method_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-956-operator-method-signature-merge',
        'operator-method-signature-merge.json'
      )
    )
    operator_method_result = RUBY_MERGE.merge_ruby(
      operator_method_fixture[:template],
      operator_method_fixture[:destination],
      'ruby'
    )
    expect(operator_method_result[:ok]).to eq(operator_method_fixture.dig(:expected, :ok))
    expect(operator_method_result[:output]).to eq(operator_method_fixture.dig(:expected, :output))

    visibility_moved_method_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-957-visibility-moved-method-detection',
        'visibility-moved-method-detection.json'
      )
    )
    visibility_moved_method_result = RUBY_MERGE.merge_ruby(
      visibility_moved_method_fixture[:template],
      visibility_moved_method_fixture[:destination],
      'ruby'
    )
    expect(visibility_moved_method_result[:ok]).to eq(visibility_moved_method_fixture.dig(:expected, :ok))
    expect(visibility_moved_method_result[:output]).to eq(visibility_moved_method_fixture.dig(:expected, :output))

    declaration_kind_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-958-declaration-kind-aware-matching',
        'declaration-kind-aware-matching.json'
      )
    )
    declaration_kind_result = RUBY_MERGE.merge_ruby(
      declaration_kind_fixture[:template],
      declaration_kind_fixture[:destination],
      'ruby'
    )
    expect(declaration_kind_result[:ok]).to eq(declaration_kind_fixture.dig(:expected, :ok))
    expect(declaration_kind_result[:output]).to eq(declaration_kind_fixture.dig(:expected, :output))

    namespace_form_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-959-namespace-form-declaration-matching',
        'namespace-form-declaration-matching.json'
      )
    )
    namespace_form_result = RUBY_MERGE.merge_ruby(
      namespace_form_fixture[:template],
      namespace_form_fixture[:destination],
      'ruby'
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_namespace_form_equivalence)
      expect(namespace_form_result[:ok]).to eq(namespace_form_fixture.dig(:expected, :ok))
      expect(namespace_form_result[:output]).to eq(namespace_form_fixture.dig(:expected, :output))
    else
      expect(namespace_form_result[:ok]).to be(false)
      expect(namespace_form_result[:diagnostics]).to contain_exactly(
        hash_including(category: 'unsupported_feature')
      )
    end

    invalid_template_fixture = read_json(fixtures_root.join('ruby', 'slice-287-merge', 'invalid-template.json'))
    invalid_template_result = RUBY_MERGE.merge_ruby(
      invalid_template_fixture[:template],
      invalid_template_fixture[:destination],
      'ruby'
    )
    expect(invalid_template_result[:ok]).to be(false)
    expect(
      json_ready(
        invalid_template_result[:diagnostics].map { |entry| entry.slice(:severity, :category) }
      )
    ).to eq(json_ready(invalid_template_fixture.dig(:expected, :diagnostics)))

    invalid_destination_fixture = read_json(fixtures_root.join('ruby', 'slice-287-merge', 'invalid-destination.json'))
    invalid_destination_result = RUBY_MERGE.merge_ruby(
      invalid_destination_fixture[:template],
      invalid_destination_fixture[:destination],
      'ruby'
    )
    expect(invalid_destination_result[:ok]).to be(false)
    expect(
      json_ready(
        invalid_destination_result[:diagnostics].map { |entry| entry.slice(:severity, :category) }
      )
    ).to eq(json_ready(invalid_destination_fixture.dig(:expected, :diagnostics)))

    gemfile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        source "https://gem.coop"
        gemspec
        eval_gemfile "gemfiles/modular/style.gemfile"
        gem "rake"
      RUBY
      <<~RUBY,
        source "https://rubygems.org"
        gem "rspec"
        eval_gemfile "gemfiles/modular/style.gemfile"
      RUBY
      'ruby'
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_top_level_call_records)
      expect(gemfile_merge[:ok]).to be(true)
      expect(gemfile_merge[:output]).to include('source "https://gem.coop"')
      expect(gemfile_merge[:output]).to include('gemspec')
      expect(gemfile_merge[:output].scan('eval_gemfile "gemfiles/modular/style.gemfile"').size).to eq(1)
      expect(gemfile_merge[:output]).to include('gem "rspec"')
      expect(gemfile_merge[:output]).to include('gem "rake"')
    else
      expect_unsupported_ruby_merge(gemfile_merge)
    end

    modular_gemfile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        gem "reek", "~> 6.5"

        platform :mri do
          gem "rubocop-lts", "~> 23.0"
          gem "rubocop-ruby2_3"
        end
      RUBY
      <<~RUBY,
        # frozen_string_literal: true

        # Destination style guidance.

        gem "reek", "~> 6.5"

        platform :mri do
          gem "rubocop-lts", "~> 24.0"
          gem "rubocop-ruby3_2"
        end
      RUBY
      'ruby'
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_top_level_call_records)
      expect(modular_gemfile_merge[:ok]).to be(true)
      expect(modular_gemfile_merge[:output]).to include('# frozen_string_literal: true')
      expect(modular_gemfile_merge[:output]).to include('# Destination style guidance.')
      expect(modular_gemfile_merge[:output]).to include('platform :mri do')
      expect(modular_gemfile_merge[:output]).to include('gem "rubocop-ruby3_2"')
    else
      expect_unsupported_ruby_merge(modular_gemfile_merge)
    end

    rakefile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        desc "Default task"
        task :default do
          puts "template"
        end

        desc "CI"
        task :ci do
          sh "bundle exec rspec"
        end
      RUBY
      <<~RUBY,
        desc "Default task"
        task :default do
          puts "destination"
        end
      RUBY
      'ruby'
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_top_level_call_records)
      expect(rakefile_merge[:ok]).to be(true)
      expect(rakefile_merge[:output].scan(/task\s+:default/).size).to eq(1)
      expect(rakefile_merge[:output]).to include('puts "destination"')
      expect(rakefile_merge[:output]).to include('task :ci')
    else
      expect_unsupported_ruby_merge(rakefile_merge)
    end

    relocated_rakefile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        # Define a base default task early so other files can enhance it.
        desc "Default tasks aggregator"
        task :default do
          puts "Default task complete."
        end

        # External gems that define tasks - add here!
        require "kettle/dev"
      RUBY
      <<~RUBY,
        # Define a base default task early so other files can enhance it.
        desc "Default tasks aggregator"
        # External gems that define tasks - add here!
        require "kettle/dev"

        task :default do
          # simplecov:disable
          puts "Default task complete."
          # simplecov:enable
        end
      RUBY
      'ruby'
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_top_level_call_records) &&
       TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(relocated_rakefile_merge[:ok]).to be(true)
      expect(relocated_rakefile_merge[:output].scan(/task\s+:default/).size).to eq(1)
      expect(relocated_rakefile_merge[:output].scan('# simplecov:disable').size).to eq(1)
      expect(relocated_rakefile_merge[:output].scan('# simplecov:enable').size).to eq(1)
      expect(relocated_rakefile_merge[:output]).to include('desc "Default tasks aggregator"')
      expect(relocated_rakefile_merge[:output]).to include(<<~RUBY)
        task :default do
          # simplecov:disable
          puts "Default task complete."
          # simplecov:enable
        end
      RUBY
      description_index = relocated_rakefile_merge[:output].index('desc "Default tasks aggregator"')
      task_index = relocated_rakefile_merge[:output].index('task :default do')
      expect(description_index).to be < task_index
    else
      expect_unsupported_ruby_merge(relocated_rakefile_merge)
    end

    rescue_task_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        begin
          require "kettle/jem"
        rescue LoadError
          desc("(stub) kettle:jem:selftest is unavailable")
          task("kettle:jem:selftest") do
            warn("NOTE: not installed")
          end
        end
      RUBY
      <<~RUBY,
        begin
          require "kettle/jem"
        rescue LoadError
          # simplecov:disable
          desc("(stub) kettle:jem:selftest is unavailable")
          task("kettle:jem:selftest") do
            warn("NOTE: not installed")
          end
          # simplecov:enable
        end
      RUBY
      'ruby'
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_top_level_call_records) &&
       TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(rescue_task_merge[:ok]).to be(true)
      expect(rescue_task_merge[:output].scan('task("kettle:jem:selftest")').size).to eq(1)
      expect(rescue_task_merge[:output].scan('# simplecov:disable').size).to eq(1)
      expect(rescue_task_merge[:output].scan('# simplecov:enable').size).to eq(1)
    else
      expect_unsupported_ruby_merge(rescue_task_merge)
    end

    rakefile_require_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        require "kettle/dev"
      RUBY
      <<~RUBY,
        require "bundler/setup"
      RUBY
      'ruby',
      merge_template_requires: true
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(rakefile_require_merge[:ok]).to be(true)
      expect(rakefile_require_merge[:output]).to include('require "bundler/setup"')
      expect(rakefile_require_merge[:output]).to include('require "kettle/dev"')
    else
      expect_unsupported_ruby_merge(rakefile_require_merge)
    end

    nocov_require_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
      RUBY
      <<~RUBY,
        # simplecov:disable
        require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
        # simplecov:enable
      RUBY
      'ruby',
      merge_template_requires: true
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(nocov_require_merge[:ok]).to be(true)
      expect(nocov_require_merge[:output]).to include(<<~RUBY)
        # simplecov:disable
        require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
        # simplecov:enable
      RUBY
      expect(nocov_require_merge[:output].scan('# simplecov:disable').size).to eq(1)
      expect(nocov_require_merge[:output].scan('# simplecov:enable').size).to eq(1)
    else
      expect_unsupported_ruby_merge(nocov_require_merge)
    end

    nested_require_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?

        begin
          require "kettle/dev"
          require "kettle/jem"
        rescue LoadError
        end
      RUBY
      <<~RUBY,
        # simplecov:disable
        require "bundler/gem_tasks" if !Dir[File.join(__dir__, "*.gemspec")].empty?
        # simplecov:enable

        begin
          require "kettle/dev"
          require "kettle/jem"
        rescue LoadError
        end
      RUBY
      'ruby',
      merge_template_requires: true
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(nested_require_merge[:ok]).to be(true)
      expect(nested_require_merge[:output].scan('# simplecov:disable').size).to eq(1)
      expect(nested_require_merge[:output].scan('# simplecov:enable').size).to eq(1)
    else
      expect_unsupported_ruby_merge(nested_require_merge)
    end

    surfaces_analysis = RUBY_MERGE.parse_ruby(surfaces_fixture[:source], 'ruby')
    expect(surfaces_analysis[:ok]).to be(true)
    expect(json_ready(RUBY_MERGE.ruby_discovered_surfaces(surfaces_analysis[:analysis]))).to eq(
      json_ready(surfaces_fixture[:expected])
    )

    child_analysis = RUBY_MERGE.parse_ruby(child_fixture[:source], 'ruby')
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
      fixtures_root.join('ruby', 'slice-229-projected-child-review-groups', 'yard-example-review-groups.json')
    )
    expect(json_ready(Ast::Merge.group_projected_child_review_cases(grouped_fixture[:cases]))).to eq(
      json_ready(grouped_fixture[:expected_groups])
    )

    progress_fixture = read_json(
      fixtures_root.join('ruby', 'slice-232-projected-child-review-group-progress', 'yard-example-review-progress.json')
    )
    expect(
      json_ready(
        Ast::Merge.summarize_projected_child_review_group_progress(
          progress_fixture[:groups],
          progress_fixture[:resolved_case_ids]
        )
      )
    ).to eq(json_ready(progress_fixture[:expected_progress]))

    ready_fixture = read_json(
      fixtures_root.join('ruby', 'slice-235-projected-child-review-groups-ready-for-apply',
                         'yard-example-ready-groups.json')
    )
    expect(
      json_ready(
        Ast::Merge.select_projected_child_review_groups_ready_for_apply(
          ready_fixture[:groups],
          ready_fixture[:resolved_case_ids]
        )
      )
    ).to eq(json_ready(ready_fixture[:expected_ready_groups]))

    transport_fixture = read_json(
      fixtures_root.join('ruby', 'slice-239-delegated-child-review-transport', 'yard-example-review-transport.json')
    )
    expect(
      json_ready(
        Ast::Merge.projected_child_group_review_request(transport_fixture[:group], transport_fixture[:family])
      )
    ).to eq(json_ready(transport_fixture[:expected_request]))
    expect(
      json_ready(
        Ast::Merge.select_projected_child_review_groups_accepted_for_apply(
          transport_fixture[:groups],
          transport_fixture[:family],
          transport_fixture[:decisions]
        )
      )
    ).to eq(json_ready(transport_fixture[:expected_accepted_groups]))

    state_fixture = read_json(
      fixtures_root.join('ruby', 'slice-242-delegated-child-review-state', 'yard-example-review-state.json')
    )
    expect(
      json_ready(
        Ast::Merge.review_projected_child_groups(
          state_fixture[:groups],
          state_fixture[:family],
          state_fixture[:decisions]
        )
      )
    ).to eq(json_ready(state_fixture[:expected_state]))

    apply_plan_fixture = read_json(
      fixtures_root.join('ruby', 'slice-245-delegated-child-apply-plan', 'yard-example-apply-plan.json')
    )
    expect(
      json_ready(
        Ast::Merge.delegated_child_apply_plan(
          apply_plan_fixture[:review_state],
          apply_plan_fixture[:family]
        )
      )
    ).to eq(json_ready(apply_plan_fixture[:expected_plan]))

    apply_output_fixture = read_json(
      fixtures_root.join('ruby', 'slice-289-delegated-child-apply-output', 'yard-example-applied-output.json')
    )
    apply_output_result = RUBY_MERGE.apply_ruby_delegated_child_outputs(
      apply_output_fixture[:source],
      apply_output_fixture[:delegated_operations],
      apply_output_fixture[:apply_plan],
      apply_output_fixture[:applied_children]
    )
    expect(apply_output_result[:ok]).to eq(apply_output_fixture.dig(:expected, :ok))
    expect(apply_output_result[:output]).to eq(apply_output_fixture.dig(:expected, :output))

    nested_merge_fixture = read_json(
      fixtures_root.join('ruby', 'slice-291-nested-merge', 'yard-example-nested-merge.json')
    )
    nested_merge_result = RUBY_MERGE.merge_ruby_with_nested_outputs(
      nested_merge_fixture[:template],
      nested_merge_fixture[:destination],
      'ruby',
      nested_merge_fixture[:nested_outputs]
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(nested_merge_result[:ok]).to eq(nested_merge_fixture.dig(:expected, :ok))
      expect(nested_merge_result[:output]).to eq(nested_merge_fixture.dig(:expected, :output))
    else
      expect_unsupported_ruby_merge(nested_merge_result)
    end

    reviewed_nested_merge_fixture = read_json(
      fixtures_root.join('ruby', 'slice-299-reviewed-nested-merge', 'yard-example-reviewed-nested-merge.json')
    )
    reviewed_nested_merge_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs(
      reviewed_nested_merge_fixture[:template],
      reviewed_nested_merge_fixture[:destination],
      'ruby',
      reviewed_nested_merge_fixture[:review_state],
      reviewed_nested_merge_fixture[:applied_children]
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(reviewed_nested_merge_result[:ok]).to eq(reviewed_nested_merge_fixture.dig(:expected, :ok))
      expect(reviewed_nested_merge_result[:output]).to eq(reviewed_nested_merge_fixture.dig(:expected, :output))
    else
      expect_unsupported_ruby_merge(reviewed_nested_merge_result)
    end

    review_artifact_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-310-reviewed-nested-review-artifact-application',
        'yard-example-reviewed-nested-review-artifact-application.json'
      )
    )
    replay_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
      review_artifact_fixture[:template],
      review_artifact_fixture[:destination],
      'ruby',
      review_artifact_fixture[:replay_bundle]
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(replay_result[:ok]).to eq(review_artifact_fixture.dig(:expected, :ok))
      expect(replay_result[:output]).to eq(review_artifact_fixture.dig(:expected, :output))
    else
      expect_unsupported_ruby_merge(replay_result)
    end
    state_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state(
      review_artifact_fixture[:template],
      review_artifact_fixture[:destination],
      'ruby',
      review_artifact_fixture[:review_state]
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(state_result[:ok]).to eq(review_artifact_fixture.dig(:expected, :ok))
      expect(state_result[:output]).to eq(review_artifact_fixture.dig(:expected, :output))
    else
      expect_unsupported_ruby_merge(state_result)
    end

    rejection_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-312-reviewed-nested-review-artifact-rejection',
        'yard-example-reviewed-nested-review-artifact-rejection.json'
      )
    )
    replay_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
      rejection_fixture[:template],
      rejection_fixture[:destination],
      'ruby',
      rejection_fixture[:replay_bundle]
    )
    expect(json_ready(replay_rejection)).to eq(json_ready(rejection_fixture[:expected].merge(policies: [])))
    state_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state(
      rejection_fixture[:template],
      rejection_fixture[:destination],
      'ruby',
      rejection_fixture[:review_state]
    )
    expect(json_ready(state_rejection)).to eq(json_ready(rejection_fixture[:expected_review_state].merge(policies: [])))

    envelope_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-314-reviewed-nested-review-artifact-envelope-application',
        'yard-example-reviewed-nested-review-artifact-envelope-application.json'
      )
    )
    replay_envelope_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
      envelope_fixture[:template],
      envelope_fixture[:destination],
      'ruby',
      envelope_fixture[:replay_bundle_envelope]
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(replay_envelope_result[:ok]).to eq(envelope_fixture.dig(:expected, :ok))
      expect(replay_envelope_result[:output]).to eq(envelope_fixture.dig(:expected, :output))
    else
      expect_unsupported_ruby_merge(replay_envelope_result)
    end
    state_envelope_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
      envelope_fixture[:template],
      envelope_fixture[:destination],
      'ruby',
      envelope_fixture[:review_state_envelope]
    )
    if TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records)
      expect(state_envelope_result[:ok]).to eq(envelope_fixture.dig(:expected, :ok))
      expect(state_envelope_result[:output]).to eq(envelope_fixture.dig(:expected, :output))
    else
      expect_unsupported_ruby_merge(state_envelope_result)
    end

    envelope_rejection_fixture = read_json(
      fixtures_root.join(
        'ruby',
        'slice-316-reviewed-nested-review-artifact-envelope-rejection',
        'yard-example-reviewed-nested-review-artifact-envelope-rejection.json'
      )
    )
    replay_envelope_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
      envelope_rejection_fixture[:template],
      envelope_rejection_fixture[:destination],
      'ruby',
      envelope_rejection_fixture[:replay_bundle_envelope]
    )
    expect(json_ready(replay_envelope_rejection)).to eq(
      json_ready(envelope_rejection_fixture[:expected_replay_bundle].merge(policies: []))
    )
    state_envelope_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
      envelope_rejection_fixture[:template],
      envelope_rejection_fixture[:destination],
      'ruby',
      envelope_rejection_fixture[:review_state_envelope]
    )
    expect(json_ready(state_envelope_rejection)).to eq(
      json_ready(envelope_rejection_fixture[:expected_review_state].merge(policies: []))
    )
  end
end
# rubocop:enable Metrics/BlockLength
