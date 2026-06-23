# frozen_string_literal: true

RSpec.describe Ast::Merge do
  def fixtures_root
    Pathname(__dir__).join('..', '..', '..', '..', 'fixtures').expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def manifest
    @manifest ||= read_json(fixtures_root.join('conformance', 'slice-24-manifest', 'family-feature-profiles.json'))
  end

  def diagnostics_fixture(role)
    path = described_class.conformance_fixture_path(manifest, 'diagnostics', role)
    raise "missing diagnostics fixture for #{role}" unless path

    read_json(fixtures_root.join(*path))
  end

  def json_ready(value)
    described_class.json_ready(value)
  end

  def fixture_deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end

  def sorted_validation_messages(diagnostics)
    diagnostics.map(&:message).sort
  end

  def active_profile_contract(profile)
    described_class::ActiveProfileView.new(
      **profile.merge(
        rule_counts: described_class::ActiveProfileRuleCounts.new(**profile[:rule_counts]),
        validation: described_class::ActiveProfileValidationSummary.new(**profile[:validation])
      )
    )
  end

  def promotion_policy_entry_contract(entry)
    described_class::ProfilePromotionPolicyEntry.new(
      **entry.merge(
        recommendation_gate: described_class::ProfileRecommendationGate.new(**entry[:recommendation_gate]),
        default_gate: described_class::ProfileDefaultGate.new(**entry[:default_gate])
      )
    )
  end

  def promotion_report_contract(fixture)
    described_class::ProfilePromotionReport.new(
      **fixture.merge(
        active_profile: fixture[:active_profile] && active_profile_contract(fixture[:active_profile]),
        hard_gates: fixture[:hard_gates].map { |gate| described_class::ProfilePromotionHardGate.new(**gate) },
        metrics: described_class::ProfilePromotionMetrics.new(**fixture[:metrics])
      )
    )
  end

  def promotion_policy_contract(fixture)
    described_class::ProfilePromotionPolicy.new(
      **fixture.merge(
        profiles: fixture[:profiles].map { |entry| promotion_policy_entry_contract(entry) }
      )
    )
  end

  def promotion_evaluation_contract(fixture)
    described_class::ProfilePromotionEvaluation.new(**fixture)
  end

  def profile_selection_requirement_contract(fixture)
    described_class::ProfileSelectionRequirement.new(**fixture)
  end

  it 'conforms to the merge-gem authoring guide contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-839-merge-gem-authoring-guide-contract',
        'merge-gem-authoring-guide-contract.json'
      )
    )

    expect(fixture.dig(:source, :old_document)).to eq('reference/ast-merge/BUILD_A_MERGE_GEM.md')
    expect(fixture.fetch(:portable_contracts).map { |contract| contract.fetch(:id) }).to include(
      'normalized-node-tree',
      'cursor-duplicate-matching',
      'recursive-scope',
      'position-aware-template-only',
      'shared-before-bespoke'
    )
    expect(fixture.fetch(:portable_contracts).map { |contract| contract.fetch(:status) }.uniq).to eq(['keep'])
    expect(fixture.fetch(:retired_requirements).map { |requirement| requirement.fetch(:id) }).to include(
      'mandatory-old-base-classes',
      'merge-gem-registry',
      'rspec-shared-examples-as-portable-conformance'
    )
    expect(fixture.dig(:contributor_guidance, :recommended_order).first).to eq('add or extend conformance fixtures')
    expect(fixture.dig(:contributor_guidance, :ownership_routing, :multiple_unrelated_formats)).to eq(
      'ast-merge or tree_haver'
    )
  end

  it 'conforms to the merge approach overview alignment fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-840-merge-approach-overview-alignment',
        'merge-approach-overview-alignment.json'
      )
    )

    expect(fixture.dig(:source, :old_document)).to eq('reference/ast-merge/MERGE_APPROACH.md')
    expect(fixture.fetch(:kept_principles).map { |principle| principle.fetch(:id) }).to eq(
      %w[
        signature-not-cardinality
        cursor-duplicate-consumption
        recursive-body-scope
        anchor-aware-template-only
      ]
    )
    expect(fixture.fetch(:replaced_notes).map { |note| note.fetch(:decision) }.uniq).to eq(
      ['discard_as_portable_architecture']
    )
    expect(fixture.dig(:portable_language, :destination_only_policy)).to eq(
      'preserve unless explicit removal policy applies'
    )
    expect(fixture.dig(:portable_language, :template_only_policy)).to eq('anchor-aware insertion')
  end

  it 'conforms to the ast-merge base class inventory fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-841-ast-merge-base-class-inventory',
        'ast-merge-base-class-inventory.json'
      )
    )
    classifications = fixture.fetch(:classifications).to_h do |entry|
      [entry.fetch(:old_surface), entry]
    end

    expect(classifications.fetch('SmartMergerBase').fetch(:classification)).to eq('active_ruby_provider_substrate')
    expect(classifications.fetch('FileAnalyzable').fetch(:classification)).to eq('active_ruby_provider_substrate')
    expect(classifications.fetch('MergeResultBase').fetch(:classification)).to eq('active_ruby_provider_substrate')
    expect(classifications.fetch('DebugLogger').fetch(:classification)).to eq('active_ruby_provider_substrate')
    expect(classifications.fetch('Runtime Ruleset unresolved review-state support').fetch(:action)).to eq(
      'keep_active_contracts'
    )
    expect(fixture.fetch(:surviving_ruby_adapter_conveniences)).to include(
      'SmartMergerBase',
      'FileAnalyzable',
      'MergeResultBase',
      'DebugLogger'
    )
    expect(fixture.fetch(:decision)).to include('port format-neutral Ruby substrate')
  end

  it 'conforms to the Ruby ast-merge reference contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1004-ruby-ast-merge-reference-contract',
        'ruby-ast-merge-reference-contract.json'
      )
    )

    expect(json_ready(described_class.ruby_reference_merge_orchestration_contract_report)).to eq(
      json_ready(fixture[:expected])
    )
  end

  it 'conforms to the Ruby-only surface disposition fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1005-ruby-only-surface-disposition',
        'ruby-only-surface-disposition.json'
      )
    )

    expect(json_ready(described_class.ruby_only_surface_disposition_report)).to eq(
      json_ready(fixture[:expected])
    )
  end

  it 'conforms to the Ruby downstream merge gem feature matrix fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1006-ruby-downstream-merge-gem-feature-matrix',
        'ruby-downstream-merge-gem-feature-matrix.json'
      )
    )

    expect(json_ready(described_class.ruby_downstream_merge_gem_feature_matrix)).to eq(
      json_ready(fixture[:expected])
    )
  end

  it 'conforms to the spec terminology glossary fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1007-spec-terminology-glossary',
        'spec-terminology-glossary.json'
      )
    )

    expect(json_ready(described_class.spec_terminology_glossary_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the corruption-healing boundary fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1008-corruption-healing-boundary',
        'corruption-healing-boundary.json'
      )
    )

    expect(json_ready(described_class.corruption_healing_boundary_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the ruleset runtime translation fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1009-ruleset-runtime-translation',
        'ruleset-runtime-translation.json'
      )
    )

    expect(json_ready(described_class.ruleset_runtime_translation_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the owner-selection substrate fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1010-owner-selection-substrate',
        'owner-selection-substrate.json'
      )
    )

    expect(json_ready(described_class.owner_selection_substrate_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the attachment-strategy substrate fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1011-attachment-strategy-substrate',
        'attachment-strategy-substrate.json'
      )
    )

    expect(json_ready(described_class.attachment_strategy_substrate_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the layout-policy substrate fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1012-layout-policy-substrate',
        'layout-policy-substrate.json'
      )
    )

    expect(json_ready(described_class.layout_policy_substrate_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the logical-owner substrate fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1013-logical-owner-substrate',
        'logical-owner-substrate.json'
      )
    )

    expect(json_ready(described_class.logical_owner_substrate_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the render source-shaper contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1014-render-source-shaper-contract',
        'render-source-shaper-contract.json'
      )
    )

    expect(json_ready(described_class.render_source_shaper_contract_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the comment-model contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1015-comment-model-contract',
        'comment-model-contract.json'
      )
    )

    expect(json_ready(described_class.comment_model_contract_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the Ruby shared conformance contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-1016-ruby-shared-conformance-contract',
        'ruby-shared-conformance-contract.json'
      )
    )

    expect(json_ready(described_class.ruby_shared_conformance_contract_report)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the match refiner utility inventory fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-842-match-refiner-utility-inventory',
        'match-refiner-utility-inventory.json'
      )
    )

    expect(fixture.fetch(:generic_patterns).map { |pattern| pattern.fetch(:id) }).to include(
      'greedy-one-to-one',
      'scored-match-result',
      'content-weighted-score',
      'token-jaccard-score',
      'composite-refiner-pipeline'
    )
    expect(fixture.dig(:default_policy, :fuzzy_matching_default)).to eq('disabled')
    ruby_method = fixture.fetch(:format_specific_patterns).find do |pattern|
      pattern.fetch(:id) == 'ruby-method-refiner'
    end
    expect(ruby_method.fetch(:decision)).to include('do_not_enable_by_default')
    json_object = fixture.fetch(:format_specific_patterns).find do |pattern|
      pattern.fetch(:id) == 'json-object-refiner'
    end
    expect(json_object.fetch(:decision)).to eq('preserved_by_slice_745_as_future_fuzzy_owner_matching')
    expect(fixture.fetch(:decision)).to include('do not port old fuzzy refiners')
  end

  it 'conforms to the freeze block directive vocabulary fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-843-freeze-block-directive-vocabulary',
        'freeze-block-directive-vocabulary.json'
      )
    )

    freeze = fixture.fetch(:directive_kinds).find { |entry| entry.fetch(:kind) == 'freeze' }
    node_freeze = fixture.fetch(:directive_kinds).find { |entry| entry.fetch(:kind) == 'node_freeze' }
    expect(freeze).to include(open: 'freeze', close: 'unfreeze', merge_policy: 'destination')
    expect(node_freeze).to include(merge_policy: 'destination_for_attached_node')
    expect(fixture.fetch(:marker_styles).map { |style| style.fetch(:style) }).to eq(
      %w[hash_comment html_comment c_style_line c_style_block]
    )
    expect(fixture.fetch(:validity_rules)).to include(
      'crossing_or_offset_overlapping_spans_are_invalid',
      'unmatched_close_marker_reports_diagnostic',
      'unclosed_open_marker_reports_diagnostic'
    )
    expect(fixture.fetch(:decision)).to include('Do not port old FreezeNodeBase')
  end

  it 'conforms to the template-only partial-template helper inventory fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-844-template-only-partial-template-helper-inventory',
        'template-only-partial-template-helper-inventory.json'
      )
    )

    expect(fixture.fetch(:portable_template_only_contracts).map { |contract| contract.fetch(:id) }).to eq(
      %w[
        exact-match-before-insertion
        destination-order-preservation
        neighbor-anchored-template-only
        delayed-interior-group-flush
        deterministic-prefix-tail
      ]
    )
    expect(fixture.fetch(:portable_partial_template_contracts).map { |contract| contract.fetch(:id) }).to include(
      'section-selector',
      'key-path-selector',
      'missing-target-policy',
      'diff-node-mapping'
    )
    expect(fixture.fetch(:retired_public_surfaces).map { |surface| surface.fetch(:old_surface) }).to include(
      'PartialTemplateMergerBase',
      'KeyPathPartialTemplateMergerBase',
      'DiffMapperBase',
      'FileAlignerBase'
    )
    expect(fixture.dig(:helper_api_policy, :exposed_now)).to be(false)
    expect(fixture.dig(:helper_api_policy, :promotion_condition)).to include('at least two active families')
    expect(fixture.fetch(:current_fixture_evidence)).to include(
      'slice-941-ruby-template-only-class-method-merge',
      'slice-920-ast-crispr-destination-profile-helpers'
    )
  end

  it 'conforms to the comment layout structural edit helper inventory fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-845-comment-layout-structural-edit-helper-inventory',
        'comment-layout-structural-edit-helper-inventory.json'
      )
    )

    expect(fixture.fetch(:portable_comment_contracts).map { |contract| contract.fetch(:id) }).to include(
      'comment-region-kinds',
      'comment-style-identifiers',
      'freeze-directive-integration',
      'region-text-submerge-gate'
    )
    expect(fixture.fetch(:portable_layout_contracts).map { |contract| contract.fetch(:id) }).to eq(
      %w[
        gap-kinds
        single-output-controller
        controller-fallback
        layout-render-reporting
      ]
    )
    expect(fixture.fetch(:portable_structural_edit_contracts).map { |contract| contract.fetch(:id) }).to include(
      'exact-splice',
      'remove-with-rehome-report',
      'passive-rehome-plan',
      'selector-to-destination-profile'
    )
    expect(fixture.dig(:renderer_ownership, :shared_contract_owns)).to include('remove/rehome transfer records')
    expect(fixture.dig(:renderer_ownership, :provider_renderer_owns)).to include('render and reparse verification')
    expect(fixture.fetch(:retired_public_surfaces).map { |surface| surface.fetch(:old_surface) }).to include(
      'Text::* SmartMerger stack'
    )
    expect(fixture.fetch(:decision)).to include('Do not copy the old public helper class hierarchy')
  end

  it 'conforms to the slice-955 comment trivia attachment contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-955-comment-trivia-attachment-contract',
        'comment-trivia-attachment-contract.json'
      )
    )
    owner_class = Struct.new(:id, :kind, :line_range, keyword_init: true)
    owners = fixture.fetch(:owner_nodes).to_h do |node|
      [node.fetch(:id),
       owner_class.new(id: node.fetch(:id), kind: node.fetch(:kind), line_range: node.fetch(:line_range))]
    end

    regions = fixture.fetch(:comment_regions).to_h do |region_fixture|
      style = region_fixture.fetch(:style).to_sym
      nodes = region_fixture.fetch(:nodes).map do |node_fixture|
        described_class::Comment::Line.new(
          text: node_fixture.fetch(:text),
          line_number: node_fixture.fetch(:line_number),
          style: style
        )
      end
      region = described_class::Comment::Region.new(
        kind: region_fixture.fetch(:kind),
        nodes: nodes,
        metadata: { floating: region_fixture.fetch(:floating) }
      )
      expected = region_fixture.fetch(:expected)

      expect(region.start_line).to eq(expected.fetch(:start_line))
      expect(region.end_line).to eq(expected.fetch(:end_line))
      expect(region.text).to eq(expected.fetch(:text))
      expect(region.normalized_content).to eq(expected.fetch(:normalized_content))
      expect(region.signature.map(&:to_s)).to eq(expected.fetch(:signature))
      expect(region.freeze_actions('smorg').map(&:to_s)).to eq(expected.fetch(:freeze_actions))

      [region_fixture.fetch(:id), region]
    end

    gaps = fixture.fetch(:layout_gaps).to_h do |gap_fixture|
      gap = described_class::Layout::Gap.new(
        kind: gap_fixture.fetch(:kind),
        start_line: gap_fixture.fetch(:start_line),
        end_line: gap_fixture.fetch(:end_line),
        lines: gap_fixture.fetch(:lines),
        before_owner: owners[gap_fixture.fetch(:before_owner_id)],
        after_owner: owners[gap_fixture.fetch(:after_owner_id)],
        controller_side: gap_fixture.fetch(:controller_side)
      )
      expected = gap_fixture.fetch(:expected)

      expect(gap.line_count).to eq(expected.fetch(:line_count))
      expect(gap.blank_line_count).to eq(expected.fetch(:blank_line_count))
      expect(gap.controller&.id).to eq(expected.fetch(:controller_owner_id))
      expect(gap.fallback_controller&.id).to eq(expected.fetch(:fallback_owner_id))
      if expected.key?(:effective_controller_with_after_removed)
        expect(gap.effective_controller(removed_owners: [gap.after_owner])&.id).to eq(
          expected.fetch(:effective_controller_with_after_removed)
        )
      end

      [gap_fixture.fetch(:id), gap]
    end

    attachments = fixture.fetch(:attachments).map do |attachment_fixture|
      owner = owners.fetch(attachment_fixture.fetch(:owner_id))
      attachment = described_class::Comment::Attachment.new(
        owner: owner,
        leading_region: regions[attachment_fixture.fetch(:leading_region_id)],
        inline_region: regions[attachment_fixture.fetch(:inline_region_id)],
        trailing_region: regions[attachment_fixture.fetch(:trailing_region_id)],
        orphan_regions: attachment_fixture.fetch(:orphan_region_ids).map { |id| regions.fetch(id) },
        leading_gap: gaps[attachment_fixture.fetch(:leading_gap_id)],
        trailing_gap: gaps[attachment_fixture.fetch(:trailing_gap_id)],
        metadata: attachment_fixture.fetch(:metadata)
      )
      expected = attachment_fixture.fetch(:expected)

      expect(attachment.regions.length).to eq(expected.fetch(:region_count))
      expect(attachment.layout_gaps.length).to eq(expected.fetch(:layout_gap_count))
      expect(attachment.empty?).to eq(expected.fetch(:empty))
      expect(attachment.leading_region_layout_owned?).to eq(expected.fetch(:leading_region_layout_owned))
      expect(attachment.trailing_region_layout_owned?).to eq(expected.fetch(:trailing_region_layout_owned))
      expect(attachment.freeze_marker?('smorg')).to eq(expected.fetch(:freeze_marker))

      attachment
    end

    expect(owners.length).to eq(fixture.dig(:expected, :owner_count))
    expect(regions.length).to eq(fixture.dig(:expected, :comment_region_count))
    expect(gaps.length).to eq(fixture.dig(:expected, :layout_gap_count))
    expect(attachments.length).to eq(fixture.dig(:expected, :attachment_count))
    expect(described_class::Comment::Region::KINDS.map(&:to_s)).to eq(fixture.dig(:expected,
                                                                                  :portable_comment_region_kinds))
    expect(described_class::Layout::Gap::KINDS.map(&:to_s)).to eq(fixture.dig(:expected, :portable_layout_gap_kinds))
    expect(fixture.fetch(:contract_rules).first).to include('passive data')
  end

  it 'conforms to the slice-956 merge result decision contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-956-merge-result-decision-contract',
        'merge-result-decision-contract.json'
      )
    )
    result_class = Class.new(described_class::MergeResultBase) do
      def add_fixture_line(content, decision:, source:, line:)
        @lines << content
        track_decision(decision.to_sym, source.to_sym, line: line)
      end
    end
    result = result_class.new

    fixture.fetch(:decisions).each do |decision|
      result.add_fixture_line(
        decision.fetch(:id),
        decision: decision.fetch(:decision),
        source: decision.fetch(:source),
        line: decision.fetch(:line)
      )
    end

    source_summary = result.decisions.each_with_object(Hash.new(0)) do |decision, summary|
      summary[decision.fetch(:source)] += 1
    end
    unresolved_count = result.decisions.count { |decision| decision.fetch(:decision) == :unresolved }
    ordered_ids = result.lines
    expected = fixture.fetch(:expected)

    expect(result.decisions.length).to eq(expected.fetch(:decision_count))
    expect(ordered_ids).to eq(expected.fetch(:ordered_decision_ids))
    expect(result.decision_summary.transform_keys(&:to_s)).to eq(expected.fetch(:decision_summary).transform_keys(&:to_s))
    expect(source_summary.transform_keys(&:to_s)).to eq(expected.fetch(:source_summary).transform_keys(&:to_s))
    expect(unresolved_count).to eq(expected.fetch(:unresolved_count))
    expect(unresolved_count.positive?).to eq(expected.fetch(:review_required))
    expect(result.line_count).to eq(expected.fetch(:line_count))
  end

  it 'conforms to the slice-957 freeze directive execution contract fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-957-freeze-directive-execution-contract',
        'freeze-directive-execution-contract.json'
      )
    )
    valid_count = 0
    invalid_count = 0

    fixture.fetch(:cases).each do |test_case|
      style = test_case.fetch(:style).to_sym
      token = test_case.fetch(:token)
      lines = test_case.fetch(:lines)
      expected = test_case.fetch(:expected)
      blocks = []
      diagnostics = []
      open_line = nil
      start_marker = nil

      lines.each_with_index do |line, index|
        line_number = index + 1
        if described_class::FreezeNodeBase.freeze_start?(line, style)
          if open_line
            diagnostics << { category: 'nested_freeze_open', severity: 'error', line: line_number }
          else
            open_line = line_number
            start_marker = line
          end
        elsif described_class::FreezeNodeBase.freeze_end?(line, style)
          if open_line.nil?
            diagnostics << { category: 'unmatched_freeze_close', severity: 'error', line: line_number }
          else
            node = described_class::FreezeNodeBase.new(
              start_line: open_line,
              end_line: line_number,
              lines: lines[(open_line - 1)...line_number],
              start_marker: start_marker,
              end_marker: line,
              pattern_type: style
            )
            blocks << {
              id: "freeze:#{test_case.fetch(:id)}:#{open_line}-#{line_number}",
              style: test_case.fetch(:style),
              token: token,
              start_line: node.start_line,
              end_line: node.end_line,
              reason: node.reason.to_s,
              content_lines: lines[(open_line - 1)...line_number],
              merge_policy: node.merge_policy.to_s,
              decision: node.merge_type.to_s,
              signature: ['freeze_block', open_line.to_s, line_number.to_s]
            }
            open_line = nil
            start_marker = nil
          end
        end
      end

      if open_line
        diagnostics << { category: 'unclosed_freeze_open', severity: 'error', line: open_line }
        blocks = []
      elsif diagnostics.any?
        blocks = []
      end

      expected.fetch(:valid) ? valid_count += 1 : invalid_count += 1
      expect(blocks.length).to eq(expected.fetch(:block_count))
      expect(diagnostics.length).to eq(expected.fetch(:diagnostic_count))
      expect(diagnostics.empty?).to eq(expected.fetch(:valid))
      expect(blocks).to eq(expected.fetch(:blocks)) if blocks.any?
      if diagnostics.any?
        expected.fetch(:diagnostics).each_with_index do |expected_diagnostic, index|
          expect(diagnostics.fetch(index)).to include(expected_diagnostic)
        end
      end
      expected.fetch(:line_queries).each do |query|
        block = blocks.find do |candidate|
          query.fetch(:line).between?(candidate.fetch(:start_line), candidate.fetch(:end_line))
        end
        expect(!block.nil?).to eq(query.fetch(:in_freeze))
        expect(block&.fetch(:id)).to eq(query.fetch(:block_id))
      end
    end

    expect(fixture.fetch(:cases).length).to eq(fixture.dig(:expected, :case_count))
    expect(valid_count).to eq(fixture.dig(:expected, :valid_case_count))
    expect(invalid_count).to eq(fixture.dig(:expected, :invalid_case_count))
  end

  it 'conforms to the RSpec shared examples dependency tag inventory fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-846-rspec-shared-examples-dependency-tag-inventory',
        'rspec-shared-examples-dependency-tag-inventory.json'
      )
    )

    expect(fixture.fetch(:portable_replacements).map { |replacement| replacement.fetch(:id) }).to include(
      'reproducible-merge-fixtures',
      'partial-merge-fixtures',
      'dependency-tags-to-requirements',
      'skipped-results',
      'unresolved-contract-fixtures',
      'comment-layout-fixtures'
    )
    expect(fixture.fetch(:ruby_local_helpers).map { |helper| helper.fetch(:id) }).to eq(
      %w[
        testable-node-builder
        fixture-assertion-wrappers
      ]
    )
    expect(fixture.fetch(:ruby_local_helpers).map { |helper| helper.fetch(:allowed) }.uniq).to eq([true])
    expect(fixture.fetch(:retired_public_surfaces).map { |surface| surface.fetch(:old_surface) }).to include(
      'MergeGemRegistry',
      'positive/negative dependency tags',
      'base-class shared examples'
    )
    expect(fixture.fetch(:decision)).to include('Do not port old RSpec shared examples or dependency tags')
  end

  it 'conforms to the slice-790 generic merge IR fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-790-generic-merge-ir', 'generic-merge-ir.json'))
    raw = fixture[:merge_ir]
    merge_ir = described_class::MergeIR.new(
      version: raw[:version],
      tree_id: raw[:tree_id],
      source: raw[:source],
      node_classes: raw[:node_classes].map { |entry| described_class::MergeIRNodeClass.new(**entry) },
      ordered_nodes: raw[:ordered_nodes].map { |entry| described_class::MergeIROrderedNode.new(**entry) },
      changes: raw[:changes].map { |entry| described_class::MergeIRChange.new(**entry) },
      diagnostics: raw[:diagnostics]
    )

    expect(merge_ir.version).to eq(fixture.dig(:expected, :version))
    expect(merge_ir.node_classes.length).to eq(fixture.dig(:expected, :node_class_count))
    expect(merge_ir.ordered_nodes.length).to eq(fixture.dig(:expected, :ordered_node_count))
    expect(merge_ir.changes.map(&:kind)).to eq(fixture.dig(:expected, :change_kinds))
    expect(merge_ir.node_classes.first.node_ids.fetch(:left)).to eq('left-import-fmt')
    expect(merge_ir.changes.fetch(1).class_id).to eq('class-import-strings')
  end

  it 'conforms to the slice-906 merge engine suite setting fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-906-merge-engine-suite-setting',
                                           'merge-engine-suite-setting.json'))
    settings = fixture[:settings]
    expected = fixture[:expected]

    expect(described_class.normalize_merge_engine).to eq(expected[:default_engine])
    expect(described_class.normalize_merge_engine(settings[:experimental_engine])).to eq(expected[:experimental_engine])
    expect(settings[:supported_engines].length).to eq(expected[:supported_engine_count])
    expect(described_class::MERGE_ENGINE_ENVIRONMENT_VARIABLE).to eq(expected[:environment_variable])
    expect(settings[:experimental_policy]).to eq(expected[:experimental_policy])
    expect(settings[:runs_same_suite]).to eq(expected[:runs_same_suite])
    expect(described_class.merge_engine_from_environment(described_class::MERGE_ENGINE_ENVIRONMENT_VARIABLE => settings[:experimental_engine])).to eq('merge_ir_experimental')

    manifest = {
      family_feature_profiles: [],
      suite_descriptors: [
        {
          kind: 'family',
          subject: { grammar: 'go' },
          roles: ['case']
        }
      ],
      families: {
        go: [
          {
            role: 'case',
            path: ['go', 'case.json']
          }
        ]
      }
    }
    plan = described_class.plan_named_conformance_suites_with_diagnostics(
      manifest,
      family_profiles: {
        go: {
          family: 'go',
          supported_dialects: [],
          supported_policies: []
        }
      },
      merge_engine: 'merge_ir_experimental'
    )

    expect(plan[:entries].length).to eq(1)
    expect(plan.dig(:entries, 0, :plan, :merge_engine)).to eq('merge_ir_experimental')
    expect(plan.dig(:entries, 0, :plan, :entries, 0, :run, :merge_engine)).to eq('merge_ir_experimental')
  end

  it 'conforms to the slice-791 pairwise matchings fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-791-pairwise-matchings', 'pairwise-matchings.json'))
    matchings = fixture[:pairwise_matchings].map do |raw|
      described_class::PairwiseMatching.new(
        matching_id: raw[:matching_id],
        from_revision: raw[:from_revision],
        to_revision: raw[:to_revision],
        matches: raw[:matches].map { |entry| described_class::PairwiseNodeMatch.new(**entry) },
        unmatched_from: raw[:unmatched_from],
        unmatched_to: raw[:unmatched_to]
      )
    end

    expect(matchings.map(&:matching_id)).to eq(fixture.dig(:expected, :matching_ids))
    expect(matchings.sum { |matching| matching.matches.length }).to eq(fixture.dig(:expected, :total_match_count))
    expect(matchings.fetch(0).unmatched_to.fetch(0)).to eq('left-import-os')
    expect(matchings.fetch(1).unmatched_from.fetch(0)).to eq('base-decl-greet')
    expect(matchings.fetch(2).matches.fetch(1).diagnostics.fetch(0)).to eq('sibling position changed')
  end

  it 'conforms to the slice-792 class mapping fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-792-class-mapping', 'class-mapping.json'))
    raw = fixture[:class_mapping]
    report = described_class::ClassMappingReport.new(
      mapping_id: raw[:mapping_id],
      source_matching_ids: raw[:source_matching_ids],
      node_classes: raw[:node_classes].map { |entry| described_class::ClassMappingNodeClass.new(**entry) },
      diagnostics: raw[:diagnostics].map { |entry| described_class::ClassMappingDiagnostic.new(**entry) }
    )

    expect(report.node_classes.length).to eq(fixture.dig(:expected, :class_count))
    expect(report.diagnostics.map(&:category)).to eq(fixture.dig(:expected, :diagnostic_categories))
    expect(report.diagnostics.map(&:class_id)).to eq(fixture.dig(:expected, :conflicted_class_ids))
    expect(report.node_classes.fetch(2).node_ids).not_to have_key(:right)
    expect(report.diagnostics.fetch(1).category).to eq('delete_edit_disagreement')
  end

  it 'conforms to the slice-793 PCS change-set generation fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-793-pcs-change-set-generation',
                                           'pcs-change-set-generation.json'))
    raw_pcs = fixture[:pcs]
    pcs = described_class::PCS.new(
      pcs_id: raw_pcs[:pcs_id],
      tree_id: raw_pcs[:tree_id],
      base_revision: raw_pcs[:base_revision],
      constraints: raw_pcs[:constraints].map { |entry| described_class::PCSConstraint.new(**entry) }
    )
    change_sets = fixture[:change_sets].map do |raw|
      described_class::ChangeSet.new(
        change_set_id: raw[:change_set_id],
        side: raw[:side],
        changes: raw[:changes].map { |entry| described_class::ChangeSetChange.new(**entry) },
        diagnostics: raw[:diagnostics]
      )
    end

    expect(pcs.constraints.length).to eq(fixture.dig(:expected, :pcs_constraint_count))
    expect(change_sets.length).to eq(fixture.dig(:expected, :change_set_count))
    expect(change_sets.flat_map do |change_set|
      change_set.changes.map(&:kind)
    end).to eq(fixture.dig(:expected, :change_kinds))
    expect(change_sets.sum do |change_set|
      change_set.diagnostics.length
    end).to eq(fixture.dig(:expected, :diagnostic_count))
    expect(pcs.constraints.fetch(2).predecessor_class_id).to eq('class-import-strings')
    expect(change_sets.fetch(1).changes.fetch(1).kind).to eq('delete')
  end

  it 'conforms to the slice-794 raw merge change-set union fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-794-raw-merge-change-set-union',
                                           'raw-merge-change-set-union.json'))
    raw = fixture[:raw_merge]
    raw_merge = described_class::RawMerge.new(
      raw_merge_id: raw[:raw_merge_id],
      input_change_set_ids: raw[:input_change_set_ids],
      changes: raw[:changes].map { |entry| described_class::RawMergeChange.new(**entry) },
      diagnostics: raw[:diagnostics]
    )
    sides = raw_merge.changes.each_with_object([]) do |change, memo|
      memo << change.side unless memo.include?(change.side)
    end

    expect(raw_merge.changes.length).to eq(fixture.dig(:expected, :raw_change_count))
    expect(raw_merge.input_change_set_ids.length).to eq(fixture.dig(:expected, :input_change_set_count))
    expect(sides).to eq(fixture.dig(:expected, :sides))
    expect(raw_merge.changes.count { |change| change.class_id == 'class-decl-greet' }).to eq(2)
    expect(raw_merge.diagnostics.first).to eq('raw merge intentionally preserves both sides before inconsistency detection')
  end

  it 'conforms to the slice-795 inconsistency detection fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-795-inconsistency-detection',
                                           'inconsistency-detection.json'))
    raw = fixture[:inconsistency_report]
    report = described_class::InconsistencyReport.new(
      report_id: raw[:report_id],
      raw_merge_id: raw[:raw_merge_id],
      inconsistencies: raw[:inconsistencies].map { |entry| described_class::MergeInconsistency.new(**entry) },
      diagnostics: raw[:diagnostics]
    )

    expect(report.inconsistencies.length).to eq(fixture.dig(:expected, :inconsistency_count))
    expect(report.inconsistencies.map(&:category)).to eq(fixture.dig(:expected, :categories))
    expect(report.inconsistencies.count do |item|
      item.severity == 'error'
    end).to eq(fixture.dig(:expected, :blocking_count))
    expect(report.inconsistencies.fetch(1).change_ids.fetch(1)).to eq('right-delete-greet')
  end

  it 'conforms to the slice-907 merge IR experimental evaluation fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-907-merge-ir-experimental-evaluation',
                                           'merge-ir-experimental-evaluation.json'))
    request = fixture[:request]
    expected = fixture[:expected]
    change_sets = request[:change_sets].map do |raw|
      described_class::ChangeSet.new(
        change_set_id: raw[:change_set_id],
        side: raw[:side],
        changes: raw[:changes].map { |entry| described_class::ChangeSetChange.new(**entry) },
        diagnostics: raw[:diagnostics]
      )
    end
    report = described_class.evaluate_merge_ir_change_sets(
      request[:merge_engine],
      request[:raw_merge_id],
      request[:report_id],
      change_sets
    )
    categories = report.inconsistency_report.inconsistencies.map(&:category)
    blocking_count = report.inconsistency_report.inconsistencies.count do |inconsistency|
      inconsistency.severity == 'error'
    end

    expect(report.merge_engine).to eq(expected[:merge_engine])
    expect(report.raw_merge.changes.length).to eq(expected[:raw_change_count])
    expect(report.raw_merge.input_change_set_ids.length).to eq(expected[:input_change_set_count])
    expect(categories).to eq(expected[:categories])
    expect(blocking_count).to eq(expected[:blocking_count])
    expect(report.outcome).to eq(expected[:outcome])
  end

  it 'conforms to the slice-796 merge IR comparison fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-796-merge-ir-comparison', 'merge-ir-comparison.json'))
    raw = fixture[:comparison]
    report = described_class::MergeIRComparisonReport.new(
      comparison_id: raw[:comparison_id],
      baseline: raw[:baseline],
      prototype: raw[:prototype],
      cases: raw[:cases].map { |entry| described_class::MergeIRComparisonCase.new(**entry) },
      summary: described_class::MergeIRComparisonSummary.new(**raw[:summary])
    )

    expect(report.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(report.cases.map(&:family)).to eq(fixture.dig(:expected, :families))
    expect(report.summary.merge_ir_wins).to eq(fixture.dig(:expected, :merge_ir_wins))
    expect(report.summary.recommendation).to eq(fixture.dig(:expected, :recommendation))
    expect(report.cases.fetch(4).merge_ir_advantage).to eq('defer')
  end

  it 'conforms to the slice-797 structural matching baseline fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-797-structural-matching-baseline',
                                           'structural-matching-baseline.json'))
    raw = fixture[:matching]
    report = described_class::StructuralMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      from_revision: raw[:from_revision],
      to_revision: raw[:to_revision],
      matches: raw[:matches].map { |entry| described_class::StructuralPathMatch.new(**entry) },
      unmatched_from: raw[:unmatched_from],
      unmatched_to: raw[:unmatched_to],
      diagnostics: raw[:diagnostics]
    )

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(report.unmatched_from.length).to eq(fixture.dig(:expected, :unmatched_from_count))
    expect(report.unmatched_to.length).to eq(fixture.dig(:expected, :unmatched_to_count))
    expect(fixture.dig(:expected, :move_detection)).to be(false)
    expect(report.matches.fetch(1).from_path).to eq('/declarations/Greet')
  end

  it 'conforms to the slice-798 signature matching commutative parent fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-798-signature-matching-commutative-parent',
                                           'signature-matching-commutative-parent.json'))
    parent = described_class::SignatureMatchingParent.new(**fixture[:parent])
    raw = fixture[:matching]
    report = described_class::SignatureMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      parent_policy: raw[:parent_policy],
      signature_components: raw[:signature_components],
      from_revision: raw[:from_revision],
      to_revision: raw[:to_revision],
      matches: raw[:matches].map { |entry| described_class::SignatureNodeMatch.new(**entry) },
      unmatched_from: raw[:unmatched_from],
      unmatched_to: raw[:unmatched_to],
      diagnostics: raw[:diagnostics]
    )

    expect(parent.child_order).to eq(fixture.dig(:expected, :parent_policy))
    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.parent_policy).to eq(fixture.dig(:expected, :parent_policy))
    expect(report.signature_components).to eq(fixture.dig(:expected, :signature_components))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(report.unmatched_from.length).to eq(fixture.dig(:expected, :unmatched_from_count))
    expect(report.unmatched_to.length).to eq(fixture.dig(:expected, :unmatched_to_count))
    expect(fixture.dig(:expected, :order_sensitive)).to be(false)
    expect(report.matches.fetch(0).signature).to eq(fixture.dig(:expected, :first_match_signature))
    expect(report.matches.fetch(0).to_path).to eq(fixture.dig(:expected, :first_match_to_path))
  end

  it 'conforms to the slice-799 source-text normalized leaf matching fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-799-source-text-normalized-leaf-matching',
                                           'source-text-normalized-leaf-matching.json'))
    raw = fixture[:matching]
    report = described_class::SourceTextNormalizedMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      from_revision: raw[:from_revision],
      to_revision: raw[:to_revision],
      normalization: raw[:normalization],
      leaf_kinds: raw[:leaf_kinds],
      matches: raw[:matches].map { |entry| described_class::SourceTextNormalizedMatch.new(**entry) },
      unmatched_from: raw[:unmatched_from],
      unmatched_to: raw[:unmatched_to],
      diagnostics: raw[:diagnostics]
    )

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.normalization).to eq(fixture.dig(:expected, :normalization))
    expect(report.leaf_kinds).to eq(fixture.dig(:expected, :leaf_kinds))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(report.unmatched_from.length).to eq(fixture.dig(:expected, :unmatched_from_count))
    expect(report.unmatched_to.length).to eq(fixture.dig(:expected, :unmatched_to_count))
    expect(report.matches.fetch(0).normalized_text).to eq(fixture.dig(:expected, :first_match_normalized_text))
    expect(report.matches.fetch(0).confidence).to be >= fixture.dig(:expected, :minimum_confidence)
  end

  it 'conforms to the slice-800 move detection opt-in fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-800-move-detection-opt-in',
                                           'move-detection-opt-in.json'))
    raw = fixture[:matching]
    report = described_class::MoveDetectionMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      from_revision: raw[:from_revision],
      to_revision: raw[:to_revision],
      capability: described_class::MoveDetectionCapability.new(**raw[:capability]),
      matches: raw[:matches].map { |entry| described_class::MoveDetectionMatch.new(**entry) },
      unmatched_from: raw[:unmatched_from],
      unmatched_to: raw[:unmatched_to],
      diagnostics: raw[:diagnostics]
    )
    move_count = report.matches.count(&:moved)

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.capability.name).to eq(fixture.dig(:expected, :capability))
    expect(report.capability.enabled).to eq(fixture.dig(:expected, :enabled))
    expect(report.capability.default_enabled).to eq(fixture.dig(:expected, :default_enabled))
    expect(report.capability.requires_stable_node_identity).to eq(fixture.dig(:expected,
                                                                              :requires_stable_node_identity))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(move_count).to eq(fixture.dig(:expected, :move_count))
    expect(report.matches.fetch(0).signature).to eq(fixture.dig(:expected, :first_moved_signature))
    expect(report.matches.fetch(0).from_index).to eq(fixture.dig(:expected, :first_moved_from_index))
    expect(report.matches.fetch(0).to_index).to eq(fixture.dig(:expected, :first_moved_to_index))
  end

  it 'conforms to the slice-801 rename-aware matching gated fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-801-rename-aware-matching-gated',
                                           'rename-aware-matching-gated.json'))
    raw = fixture[:matching]
    report = described_class::RenameAwareMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      from_revision: raw[:from_revision],
      to_revision: raw[:to_revision],
      capability: described_class::RenameAwareCapability.new(**raw[:capability]),
      candidates: raw[:candidates].map { |entry| described_class::RenameAwareCandidate.new(**entry) },
      matches: raw[:matches].map { |entry| described_class::SignatureNodeMatch.new(**entry) },
      unmatched_from: raw[:unmatched_from],
      unmatched_to: raw[:unmatched_to],
      diagnostics: raw[:diagnostics]
    )

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.capability.name).to eq(fixture.dig(:expected, :capability))
    expect(report.capability.status).to eq(fixture.dig(:expected, :status))
    expect(report.capability.enabled).to eq(fixture.dig(:expected, :enabled))
    expect(report.capability.requires_explicit_profile).to eq(fixture.dig(:expected, :requires_explicit_profile))
    expect(report.capability.requires_diagnostics).to eq(fixture.dig(:expected, :requires_diagnostics))
    expect(report.candidates.length).to eq(fixture.dig(:expected, :candidate_count))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(report.candidates.fetch(0).selected).to eq(fixture.dig(:expected, :first_candidate_selected))
    expect(report.candidates.fetch(0).stable_body_hash).to eq(fixture.dig(:expected, :first_candidate_body_hash))
  end

  it 'conforms to the slice-802 ambiguity diagnostics fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-802-ambiguity-diagnostics',
                                           'ambiguity-diagnostics.json'))
    raw = fixture[:matching]
    report = described_class::AmbiguityMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      scope_path: raw[:scope_path],
      ambiguous: raw[:ambiguous],
      matches: raw[:matches].map { |entry| described_class::SignatureNodeMatch.new(**entry) },
      ambiguities: raw[:ambiguities].map { |entry| described_class::MatchingAmbiguity.new(**entry) },
      diagnostics: raw[:diagnostics]
    )

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.scope_path).to eq(fixture.dig(:expected, :scope_path))
    expect(report.ambiguous).to eq(fixture.dig(:expected, :ambiguous))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(report.ambiguities.length).to eq(fixture.dig(:expected, :ambiguity_count))
    expect(report.diagnostics.fetch(0).fetch(:category)).to eq(fixture.dig(:expected, :diagnostic_category))
    expect(report.ambiguities.fetch(0).signature).to eq(fixture.dig(:expected, :first_ambiguity_signature))
    expect(report.ambiguities.fetch(0).reason).to eq(fixture.dig(:expected, :first_ambiguity_reason))
    expect(report.ambiguities.fetch(0).selected).to eq(fixture.dig(:expected, :first_ambiguity_selected))
  end

  it 'conforms to the slice-803 duplicate signature tie-break fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-803-duplicate-signature-tie-break',
                                           'duplicate-signature-tie-break.json'))
    raw = fixture[:matching]
    report = described_class::TieBreakMatchingReport.new(
      matching_id: raw[:matching_id],
      strategy: raw[:strategy],
      scope_path: raw[:scope_path],
      tie_break_rules: raw[:tie_break_rules],
      matches: raw[:matches].map do |entry|
        described_class::TieBreakMatch.new(
          **entry.merge(
            rejected_candidates: entry[:rejected_candidates].map do |candidate|
              described_class::RejectedTieBreakCandidate.new(**candidate)
            end
          )
        )
      end,
      diagnostics: raw[:diagnostics]
    )

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.scope_path).to eq(fixture.dig(:expected, :scope_path))
    expect(report.tie_break_rules).to eq(fixture.dig(:expected, :tie_break_rules))
    expect(report.matches.length).to eq(fixture.dig(:expected, :match_count))
    expect(report.matches.fetch(0).signature).to eq(fixture.dig(:expected, :first_match_signature))
    expect(report.matches.fetch(0).selected_by).to eq(fixture.dig(:expected, :first_match_selected_by))
    expect(report.matches.fetch(0).rejected_candidates.length).to eq(fixture.dig(:expected, :rejected_candidate_count))
    expect(report.matches.fetch(0).rejected_candidates.fetch(0).rejected_by).to eq(fixture.dig(:expected,
                                                                                               :first_rejected_by))
  end

  it 'conforms to the slice-804 matching debug artifacts fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-804-matching-debug-artifacts',
                                           'matching-debug-artifacts.json'))
    raw = fixture[:debug_artifacts]
    artifacts = described_class::MatchingDebugArtifacts.new(
      artifact_id: raw[:artifact_id],
      matching_id: raw[:matching_id],
      enabled: raw[:enabled],
      owner_sets: raw[:owner_sets].map { |entry| described_class::MatchingDebugOwnerSet.new(**entry) },
      candidates: raw[:candidates].map { |entry| described_class::MatchingDebugCandidate.new(**entry) },
      selected_matches: raw[:selected_matches].map { |entry| described_class::MatchingDebugSelectedMatch.new(**entry) },
      rejected_matches: raw[:rejected_matches].map { |entry| described_class::MatchingDebugRejectedMatch.new(**entry) },
      diagnostics: raw[:diagnostics]
    )

    expect(artifacts.enabled).to eq(fixture.dig(:expected, :enabled))
    expect(artifacts.owner_sets.length).to eq(fixture.dig(:expected, :owner_set_count))
    expect(artifacts.candidates.length).to eq(fixture.dig(:expected, :candidate_count))
    expect(artifacts.selected_matches.length).to eq(fixture.dig(:expected, :selected_count))
    expect(artifacts.rejected_matches.length).to eq(fixture.dig(:expected, :rejected_count))
    expect(artifacts.rejected_matches.fetch(0).reason).to eq(fixture.dig(:expected, :first_rejection_reason))
  end

  it 'conforms to the slice-805 fallback scopes fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-805-fallback-scopes', 'fallback-scopes.json'))
    raw = fixture[:fallback]
    report = described_class::FallbackScopeReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      scopes: raw[:scopes].map { |entry| described_class::FallbackScopeDefinition.new(**entry) },
      default_order: raw[:default_order],
      diagnostics: raw[:diagnostics]
    )

    expect(report.scopes.length).to eq(fixture.dig(:expected, :scope_count))
    expect(report.default_order).to eq(fixture.dig(:expected, :default_order))
    expect(report.scopes.fetch(0).scope).to eq(fixture.dig(:expected, :first_scope))
    expect(report.scopes.fetch(-1).scope).to eq(fixture.dig(:expected, :last_scope))
    expect(report.scopes.fetch(-1).requires_source_span).to eq(fixture.dig(:expected, :whole_file_requires_source_span))
  end

  it 'conforms to the slice-806 conflict categories fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-806-conflict-categories', 'conflict-categories.json'))
    raw = fixture[:conflicts]
    report = described_class::ConflictCategoryReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      categories: raw[:categories],
      conflicts: raw[:conflicts].map { |entry| described_class::MergeConflict.new(**entry) },
      diagnostics: raw[:diagnostics]
    )
    parse_limited = report.conflicts.find { |conflict| conflict.category == 'parse_limited' }

    expect(report.categories.length).to eq(fixture.dig(:expected, :category_count))
    expect(report.conflicts.length).to eq(fixture.dig(:expected, :conflict_count))
    expect(report.categories.fetch(0)).to eq(fixture.dig(:expected, :first_category))
    expect(report.categories.fetch(-1)).to eq(fixture.dig(:expected, :last_category))
    expect(parse_limited.fallback_scope).to eq(fixture.dig(:expected, :parse_limited_fallback_scope))
  end

  it 'conforms to the slice-807 local line-based fallback fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-807-local-line-based-fallback',
                                           'local-line-based-fallback.json'))
    raw = fixture[:fallback]
    report = described_class::LocalLineFallbackReport.new(
      fallback_id: raw[:fallback_id],
      strategy: raw[:strategy],
      scope: raw[:scope],
      path: raw[:path],
      owner_path: raw[:owner_path],
      base_span: described_class::LineSpan.new(**raw[:base_span]),
      left_span: described_class::LineSpan.new(**raw[:left_span]),
      right_span: described_class::LineSpan.new(**raw[:right_span]),
      result: raw[:result],
      conflict_category: raw[:conflict_category],
      diagnostics: raw[:diagnostics]
    )

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.scope).to eq(fixture.dig(:expected, :scope))
    expect(report.path).to eq(fixture.dig(:expected, :path))
    expect(report.result).to eq(fixture.dig(:expected, :result))
    expect(report.conflict_category).to eq(fixture.dig(:expected, :conflict_category))
    expect(report.left_span.end_line - report.left_span.start_line + 1).to eq(fixture.dig(:expected, :left_line_count))
    expect(report.right_span.end_line - report.right_span.start_line + 1).to eq(fixture.dig(:expected,
                                                                                            :right_line_count))
  end

  it 'conforms to the slice-808 conflict marker rendering fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-808-conflict-marker-rendering',
                                           'conflict-marker-rendering.json'))
    report = described_class::ConflictMarkerRenderingReport.new(**fixture[:rendering])

    expect(report.strategy).to eq(fixture.dig(:expected, :strategy))
    expect(report.marker_size).to eq(fixture.dig(:expected, :marker_size))
    expect(report.path_label).to eq(fixture.dig(:expected, :path_label))
    expect(report.include_base).to eq(fixture.dig(:expected, :include_base))
    expect(report.output).to start_with(fixture.dig(:expected, :starts_with))
    expect(report.output).to include(fixture.dig(:expected, :contains_base_marker))
    expect(report.output).to end_with(fixture.dig(:expected, :ends_with))
  end

  it 'conforms to the slice-809 typed conflict handler extension points fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-809-typed-conflict-handler-extension-points',
                                           'typed-conflict-handler-extension-points.json'))
    raw = fixture[:handlers]
    report = described_class::ConflictHandlerRegistryReport.new(
      registry_id: raw[:registry_id],
      version: raw[:version],
      handlers: raw[:handlers].map { |entry| described_class::ConflictHandlerRegistration.new(**entry) },
      diagnostics: raw[:diagnostics]
    )
    enabled_count = report.handlers.count(&:enabled)

    expect(report.handlers.length).to eq(fixture.dig(:expected, :handler_count))
    expect(enabled_count).to eq(fixture.dig(:expected, :enabled_count))
    expect(report.handlers.fetch(0).conflict_category).to eq(fixture.dig(:expected, :first_handler_category))
    expect(report.handlers.fetch(1).fallback_scope).to eq(fixture.dig(:expected, :second_handler_scope))
  end

  it 'conforms to the slice-810 generic conflict handler execution fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-810-generic-conflict-handler-execution',
                                           'generic-conflict-handler-execution.json'))
    raw = fixture[:execution]
    execution = described_class::GenericConflictHandlerExecution.new(
      execution_id: raw[:execution_id],
      version: raw[:version],
      cases: raw[:cases].map do |entry|
        result = entry[:expected_result]
        described_class::GenericConflictHandlerCase.new(
          case_id: entry[:case_id],
          handler_id: entry[:handler_id],
          conflict_category: entry[:conflict_category],
          parent_policy: entry[:parent_policy],
          base_children: (entry[:base_children] || []).map { |node| described_class::HandlerChildNode.new(**node) },
          left_insertions: (entry[:left_insertions] || []).map { |node| described_class::HandlerChildNode.new(**node) },
          right_insertions: (entry[:right_insertions] || []).map do |node|
            described_class::HandlerChildNode.new(**node)
          end,
          base_members: (entry[:base_members] || []).map { |member| described_class::HandlerKeyedMember.new(**member) },
          left_edits: (entry[:left_edits] || []).map { |member| described_class::HandlerKeyedMember.new(**member) },
          right_edits: (entry[:right_edits] || []).map { |member| described_class::HandlerKeyedMember.new(**member) },
          expected_result: described_class::GenericConflictHandlerResult.new(
            resolved: result[:resolved],
            merged_children: if result.key?(:merged_children)
                               result[:merged_children].map do |node|
                                 described_class::HandlerChildNode.new(**node)
                               end
                             end,
            merged_members: if result.key?(:merged_members)
                              result[:merged_members].map do |member|
                                described_class::HandlerKeyedMember.new(**member)
                              end
                            end,
            diagnostics: result[:diagnostics]
          )
        )
      end,
      diagnostics: raw[:diagnostics]
    )
    resolved_count = execution.cases.count { |handler_case| handler_case.expected_result.resolved }
    results = execution.cases.map { |handler_case| described_class.execute_generic_conflict_handler(handler_case) }

    execution.cases.zip(results).each do |handler_case, result|
      expect(result).to eq(handler_case.expected_result)
    end

    expect(execution.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(resolved_count).to eq(fixture.dig(:expected, :resolved_count))
    expect(execution.cases.fetch(0).handler_id).to eq(fixture.dig(:expected, :first_handler_id))
    expect(results.fetch(0).merged_children.length).to eq(fixture.dig(:expected, :first_merged_child_count))
    expect(execution.cases.fetch(1).handler_id).to eq(fixture.dig(:expected, :second_handler_id))
    expect(results.fetch(1).merged_members.length).to eq(fixture.dig(:expected, :second_merged_member_count))
  end

  it 'conforms to the slice-811 language profile handler registration fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-811-language-profile-handler-registration',
                                           'language-profile-handler-registration.json'))
    raw = fixture[:profile_handlers]
    registry = described_class::LanguageProfileHandlerRegistry.new(
      profile_id: raw[:profile_id],
      language: raw[:language],
      version: raw[:version],
      registrations: raw[:registrations].map do |entry|
        described_class::LanguageProfileHandlerRegistration.new(**entry)
      end,
      diagnostics: raw[:diagnostics]
    )
    enabled_count = registry.registrations.count(&:enabled)
    roles = registry.registrations.map(&:role)
    duplicate_member_handler = registry.registrations.find do |registration|
      registration.role == 'duplicate_members'
    end.handler_id

    expect(registry.language).to eq(fixture.dig(:expected, :language))
    expect(registry.registrations.length).to eq(fixture.dig(:expected, :registration_count))
    expect(enabled_count).to eq(fixture.dig(:expected, :enabled_count))
    expect(roles).to eq(fixture.dig(:expected, :roles))
    expect(duplicate_member_handler).to eq(fixture.dig(:expected, :duplicate_member_handler))
  end

  it 'conforms to the slice-812 fallback usage machine output fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-812-fallback-usage-machine-output',
                                           'fallback-usage-machine-output.json'))
    raw = fixture[:fallback_usage]
    machine_output = described_class::FallbackUsageMachineOutput.new(
      fallbacks: raw.dig(:machine_output, :fallbacks).map { |entry| described_class::FallbackUsageEntry.new(**entry) },
      summary: described_class::FallbackUsageSummary.new(**raw.dig(:machine_output, :summary))
    )
    report = described_class::FallbackUsageReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      mode: raw[:mode],
      quiet_by_default: raw[:quiet_by_default],
      machine_output: machine_output,
      git_driver_output: described_class::GitDriverOutput.new(**raw[:git_driver_output]),
      diagnostics: raw[:diagnostics]
    )

    expect(report.mode).to eq(fixture.dig(:expected, :mode))
    expect(report.quiet_by_default).to eq(fixture.dig(:expected, :quiet_by_default))
    expect(report.machine_output.summary.fallback_count).to eq(fixture.dig(:expected, :fallback_count))
    expect(report.machine_output.summary.conflict_count).to eq(fixture.dig(:expected, :conflict_count))
    expect(report.git_driver_output.stdout).to eq(fixture.dig(:expected, :stdout))
    expect(report.git_driver_output.stderr).to eq(fixture.dig(:expected, :stderr))
    expect(report.git_driver_output.exit_code).to eq(fixture.dig(:expected, :exit_code))
    expect(report.machine_output.fallbacks.fetch(0).scope).to eq(fixture.dig(:expected, :first_fallback_scope))
  end

  it 'conforms to the slice-813 render strategy metadata fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-813-render-strategy-metadata',
                                           'render-strategy-metadata.json'))
    raw = fixture[:render_plan]
    report = described_class::RenderPlanReport.new(
      plan_id: raw[:plan_id],
      version: raw[:version],
      language: raw[:language],
      strategies: raw[:strategies].map do |entry|
        span = entry[:span] && described_class::RenderByteSpan.new(**entry[:span])
        described_class::RenderStrategyMetadata.new(**entry.merge(span: span))
      end,
      diagnostics: raw[:diagnostics]
    )
    strategies = report.strategies.map(&:strategy)

    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.strategies.length).to eq(fixture.dig(:expected, :strategy_count))
    expect(strategies).to eq(fixture.dig(:expected, :strategies))
    expect(report.strategies.fetch(0).preserves_source_fragment).to eq(fixture.dig(:expected,
                                                                                   :source_reuse_preserves_fragment))
    expect(report.strategies.fetch(-1).requires_reparse).to eq(fixture.dig(:expected, :full_file_requires_reparse))
  end

  it 'conforms to the slice-814 reparse after render verification fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-814-reparse-after-render-verification',
                                           'reparse-after-render-verification.json'))
    report = described_class::RenderVerificationReport.new(**fixture[:render_verification])

    expect(report.mode).to eq(fixture.dig(:expected, :mode))
    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.attempted).to eq(fixture.dig(:expected, :attempted))
    expect(report.passed).to eq(fixture.dig(:expected, :passed))
    expect(report.hard_gate).to eq(fixture.dig(:expected, :hard_gate))
    expect(report.parse_errors.length).to eq(fixture.dig(:expected, :parse_error_count))
    expect(report.render_strategy).to eq(fixture.dig(:expected, :render_strategy))
  end

  it 'conforms to the slice-815 formatting preservation metrics fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-815-formatting-preservation-metrics',
                                           'formatting-preservation-metrics.json'))
    raw = fixture[:conformance_report]
    report = described_class::FormattingPreservationConformanceReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      suite: raw[:suite],
      case_id: raw[:case_id],
      language: raw[:language],
      formatting_metrics: described_class::FormattingPreservationMetrics.new(**raw[:formatting_metrics]),
      diagnostics: raw[:diagnostics]
    )

    expect(report.suite).to eq(fixture.dig(:expected, :suite))
    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.formatting_metrics.expected_output_line_diff_size).to eq(fixture.dig(:expected, :line_diff_size))
    expect(report.formatting_metrics.expected_output_character_diff_size).to eq(fixture.dig(:expected,
                                                                                            :character_diff_size))
    expect(report.formatting_metrics.formatting_preservation_score).to eq(fixture.dig(:expected, :score))
  end

  it 'conforms to the slice-816 formatting recommendation gate fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-816-formatting-recommendation-gate',
                                           'formatting-recommendation-gate.json'))
    raw = fixture[:recommendation_gate]
    gate = described_class::FormattingRecommendationGate.new(
      gate_id: raw[:gate_id],
      version: raw[:version],
      threshold: raw[:threshold],
      passed: raw[:passed],
      weights: described_class::FormattingRecommendationWeights.new(**raw[:weights]),
      metrics: described_class::FormattingPreservationMetrics.new(**raw[:metrics]),
      diagnostics: raw[:diagnostics]
    )

    expect(gate.threshold).to eq(fixture.dig(:expected, :threshold))
    expect(gate.passed).to eq(fixture.dig(:expected, :passed))
    expect(gate.weights.expected_output_line_diff_size).to eq(fixture.dig(:expected, :line_weight))
    expect(gate.weights.expected_output_character_diff_size).to eq(fixture.dig(:expected, :character_weight))
    expect(gate.metrics.formatting_preservation_score).to eq(fixture.dig(:expected, :score))
  end

  it 'conforms to the slice-817 formatting hard gates fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-817-formatting-hard-gates',
                                           'formatting-hard-gates.json'))
    raw = fixture[:hard_gate_report]
    report = described_class::FormattingHardGateReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      gates: raw[:gates].map { |gate| described_class::FormattingHardGate.new(**gate) },
      diagnostics: raw[:diagnostics]
    )
    passed_count = report.gates.count(&:passed)
    weighted_count = report.gates.count(&:weighted)

    expect(report.gates.length).to eq(fixture.dig(:expected, :gate_count))
    expect(passed_count == report.gates.length).to eq(fixture.dig(:expected, :all_passed))
    expect(weighted_count).to eq(fixture.dig(:expected, :weighted_gate_count))
    expect(report.gates.fetch(0).name).to eq(fixture.dig(:expected, :first_gate))
    expect(report.gates.fetch(1).name).to eq(fixture.dig(:expected, :second_gate))
  end

  it 'conforms to the slice-818 secondary formatting metrics fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-818-secondary-formatting-metrics',
                                           'secondary-formatting-metrics.json'))
    report = described_class::SecondaryFormattingMetricsReport.new(**fixture[:secondary_metrics])

    expect(report.unchanged_line_churn).to eq(fixture.dig(:expected, :unchanged_line_churn))
    expect(report.output_diff_size).to eq(fixture.dig(:expected, :output_diff_size))
    expect(report.source_fragment_retention).to eq(fixture.dig(:expected, :source_fragment_retention))
    expect(report.weighted).to eq(fixture.dig(:expected, :weighted))
  end

  it 'conforms to the slice-819 token span preservation metrics fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-819-token-span-preservation-metrics',
                                           'token-span-preservation-metrics.json'))
    report = described_class::TokenSpanPreservationMetricsReport.new(**fixture[:token_span_metrics])

    expect(report.source_spans_available).to eq(fixture.dig(:expected, :source_spans_available))
    expect(report.token_preservation).to eq(fixture.dig(:expected, :token_preservation))
    expect(report.span_preservation).to eq(fixture.dig(:expected, :span_preservation))
    expect(report.weighted).to eq(fixture.dig(:expected, :weighted))
  end

  it 'conforms to the slice-820 formatting edge fixtures fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-820-formatting-edge-fixtures',
                                           'formatting-edge-fixtures.json'))
    raw = fixture[:fixture_suite]
    suite = described_class::FormattingEdgeFixtureSuite.new(
      suite_id: raw[:suite_id],
      version: raw[:version],
      cases: raw[:cases].map { |fixture_case| described_class::FormattingEdgeFixtureCase.new(**fixture_case) },
      diagnostics: raw[:diagnostics]
    )
    categories = suite.cases.map(&:category)
    conflict_marker_case_count = suite.cases.count(&:requires_conflict_markers)

    expect(suite.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(categories).to eq(fixture.dig(:expected, :categories))
    expect(conflict_marker_case_count).to eq(fixture.dig(:expected, :conflict_marker_case_count))
  end

  it 'conforms to the slice-821 unsafe render fallback or failure fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-821-unsafe-render-fallback-or-failure',
                                           'unsafe-render-fallback-or-failure.json'))
    report = described_class::RenderSafetyReport.new(**fixture[:render_safety])

    expect(report.safe_to_render).to eq(fixture.dig(:expected, :safe_to_render))
    expect(fixture.dig(:expected, :allowed_outcomes)).to include(report.outcome)
    expect(report.outcome).to eq(fixture.dig(:expected, :outcome))
    expect(report.fallback_strategy).to eq(fixture.dig(:expected, :fallback_strategy))
    expect(report.diagnostics.length).to eq(fixture.dig(:expected, :diagnostic_count))
  end

  it 'conforms to the slice-822 native provider metadata fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-822-native-provider-metadata',
                                           'native-provider-metadata.json'))
    report = described_class::NativeProviderMetadataReport.new(**fixture[:provider_metadata])

    expect(report.provider_id).to eq(fixture.dig(:expected, :provider_id))
    expect(report.family).to eq(fixture.dig(:expected, :family))
    expect(report.host_language).to eq(fixture.dig(:expected, :host_language))
    expect(report.target_language).to eq(fixture.dig(:expected, :target_language))
    expect(report.parser_name).to eq(fixture.dig(:expected, :parser_name))
    expect(report.parse_error_behavior).to eq(fixture.dig(:expected, :parse_error_behavior))
    expect(report.source_span_support).to eq(fixture.dig(:expected, :source_span_support))
    expect(report.render_support).to eq(fixture.dig(:expected, :render_support))
    expect(report.semantic_role_support).to eq(fixture.dig(:expected, :semantic_role_support))
    expect(report.retains_native_tree).to eq(fixture.dig(:expected, :retains_native_tree))
    expect(report.metadata_policy).to eq(fixture.dig(:expected, :metadata_policy))
  end

  it 'conforms to the slice-823 host language native provider contracts fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-823-host-language-native-provider-contracts',
                                           'host-language-native-provider-contracts.json'))
    raw = fixture[:native_provider_contracts]
    contracts = described_class::HostLanguageNativeProviderContracts.new(
      suite_id: raw[:suite_id],
      version: raw[:version],
      providers: raw[:providers].map { |provider| described_class::HostLanguageNativeProviderContract.new(**provider) },
      diagnostics: raw[:diagnostics]
    )
    provider_ids = contracts.providers.map(&:provider_id)
    ruby_provider_count = contracts.providers.count { |provider| provider.host_language == 'ruby' }

    expect(contracts.providers.length).to eq(fixture.dig(:expected, :provider_count))
    expect(provider_ids).to eq(fixture.dig(:expected, :provider_ids))
    expect(ruby_provider_count).to eq(fixture.dig(:expected, :ruby_provider_count))
    expect(contracts.providers.fetch(0).parser_name).to eq(fixture.dig(:expected, :first_provider_parser))
  end

  it 'conforms to the slice-1010 native parser defaults fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-1010-native-parser-defaults',
                                           'native-parser-defaults.json'))
    raw = fixture[:native_parser_defaults]
    contract = described_class::NativeParserDefaultsContract.new(
      contract_id: raw[:contract_id],
      version: raw[:version],
      defaults: raw[:defaults].map { |entry| described_class::NativeParserDefault.new(**entry) },
      diagnostics: raw[:diagnostics]
    )
    ruby_defaults = contract.defaults.select { |entry| entry.implementation == 'ruby' }
    markdown_default = ruby_defaults.find { |entry| entry.family == 'markdown' }

    expect(contract.contract_id).to eq(fixture.dig(:expected, :contract_id))
    expect(contract.defaults.length).to eq(fixture.dig(:expected, :default_count))
    expect(ruby_defaults.map(&:default_provider_id)).to eq(fixture.dig(:expected, :ruby_defaults))
    expect(markdown_default.default_backend).to eq(fixture.dig(:expected, :markdown_default_backend))
    expect(contract.defaults.map(&:generic_substrate_backend).uniq).to eq([fixture.dig(:expected, :fallback_backend)])
  end

  it 'conforms to the slice-824 Go native proving ground fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-824-go-native-proving-ground',
                                           'go-native-proving-ground.json'))
    report = described_class::NativeProviderProvingGroundReport.new(**fixture[:proving_ground])

    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.providers.length).to eq(fixture.dig(:expected, :provider_count))
    expect(report.providers).to eq(fixture.dig(:expected, :providers))
    expect(report.checks).to eq(fixture.dig(:expected, :checks))
  end

  it 'conforms to the slice-825 go-dst provider stack fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-825-go-dst-provider-stack',
                                           'go-dst-provider-stack.json'))
    report = described_class::GoDSTProviderStackReport.new(**fixture[:provider_stack])

    expect(report.provider_id).to eq(fixture.dig(:expected, :provider_id))
    expect(report.module).to eq(fixture.dig(:expected, :module))
    expect(report.backend_family).to eq(fixture.dig(:expected, :backend_family))
    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.compares_with.length).to eq(fixture.dig(:expected, :comparison_count))
  end

  it 'conforms to the slice-826 Go provider comparison fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-826-go-provider-comparison',
                                           'go-provider-comparison.json'))
    report = described_class::GoProviderComparisonReport.new(**fixture[:comparison])

    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.providers.length).to eq(fixture.dig(:expected, :provider_count))
    expect(report.dimensions.length).to eq(fixture.dig(:expected, :dimension_count))
    expect(report.dimensions.include?('backend_deficiencies')).to eq(fixture.dig(:expected,
                                                                                 :includes_backend_deficiencies))
  end

  it 'conforms to the slice-827 backend parity fixtures fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-827-backend-parity-fixtures',
                                           'backend-parity-fixtures.json'))
    raw = fixture[:parity_suite]
    suite = described_class::BackendParitySuite.new(
      suite_id: raw[:suite_id],
      version: raw[:version],
      language: raw[:language],
      cases: raw[:cases].map { |parity_case| described_class::BackendParityCase.new(**parity_case) },
      diagnostics: raw[:diagnostics]
    )
    native_providers = suite.cases.map(&:native_provider)
    source_span_case_count = suite.cases.count { |parity_case| parity_case.dimensions.include?('source_spans') }

    expect(suite.language).to eq(fixture.dig(:expected, :language))
    expect(suite.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(native_providers).to eq(fixture.dig(:expected, :native_providers))
    expect(suite.cases.fetch(0).tree_sitter_provider).to eq(fixture.dig(:expected, :tree_sitter_provider))
    expect(source_span_case_count).to eq(fixture.dig(:expected, :source_span_case_count))
  end

  it 'conforms to the slice-828 provider richness projection fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-828-provider-richness-projection',
                                           'provider-richness-projection.json'))
    raw = fixture[:projection]
    projection = described_class::ProviderRichnessProjection.new(
      projection_id: raw[:projection_id],
      version: raw[:version],
      provider_id: raw[:provider_id],
      node_path: raw[:node_path],
      generic_roles: raw[:generic_roles],
      generic_signature: described_class::ProviderRichnessSignature.new(**raw[:generic_signature]),
      private_metadata: raw[:private_metadata],
      requires_private_fields: raw[:requires_private_fields],
      diagnostics: raw[:diagnostics]
    )
    metadata_namespace = fixture.dig(:expected, :private_metadata_namespace).to_sym

    expect(projection.provider_id).to eq(fixture.dig(:expected, :provider_id))
    expect(projection.generic_roles.length).to eq(fixture.dig(:expected, :role_count))
    expect(projection.generic_signature.kind).to eq(fixture.dig(:expected, :signature_kind))
    expect(projection.generic_signature.name).to eq(fixture.dig(:expected, :signature_name))
    expect(projection.requires_private_fields).to eq(fixture.dig(:expected, :requires_private_fields))
    expect(projection.private_metadata.key?(metadata_namespace)).to eq(true)
  end

  it 'conforms to the slice-829 backend gap conformance report fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-829-backend-gap-conformance-report',
                                           'backend-gap-conformance-report.json'))
    raw = fixture[:report]
    report = described_class::BackendGapConformanceReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      language: raw[:language],
      provider_id: raw[:provider_id],
      compared_provider_id: raw[:compared_provider_id],
      gaps: raw[:gaps].map { |gap| described_class::BackendGapConformanceGap.new(**gap) },
      summary: described_class::BackendGapConformanceSummary.new(**raw[:summary]),
      diagnostics: raw[:diagnostics]
    )

    expect(report.language).to eq(fixture.dig(:expected, :language))
    expect(report.provider_id).to eq(fixture.dig(:expected, :provider_id))
    expect(report.compared_provider_id).to eq(fixture.dig(:expected, :compared_provider_id))
    expect(report.gaps.length).to eq(fixture.dig(:expected, :gap_count))
    expect(report.summary.fallback_count).to eq(fixture.dig(:expected, :fallback_count))
    expect(report.summary.silently_normalized).to eq(fixture.dig(:expected, :silently_normalized))
    expect(report.gaps.fetch(0).diagnostic_code).to eq(fixture.dig(:expected, :first_diagnostic_code))
  end

  it 'conforms to the slice-901 false textual conflicts fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-901-false-textual-conflicts',
                                           'false-textual-conflicts.json'))
    raw = fixture[:suite]
    suite = described_class::FalseTextualConflictSuite.new(
      suite_id: raw[:suite_id],
      version: raw[:version],
      source: raw[:source],
      cases: raw[:cases].map { |conflict_case| described_class::FalseTextualConflictCase.new(**conflict_case) },
      diagnostics: raw[:diagnostics]
    )
    languages = suite.cases.map(&:language)
    categories = suite.cases.map(&:category)
    unresolved_conflict_count = suite.cases.count(&:expected_unresolved_conflict)

    expect(suite.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(languages).to eq(fixture.dig(:expected, :languages))
    expect(categories).to eq(fixture.dig(:expected, :categories))
    expect(unresolved_conflict_count).to eq(fixture.dig(:expected, :expected_unresolved_conflict_count))
  end

  it 'conforms to the slice-902 git driver smoke fixtures fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-902-git-driver-smoke-fixtures',
                                           'git-driver-smoke-fixtures.json'))
    raw = fixture[:suite]
    suite = described_class::GitDriverSmokeSuite.new(
      suite_id: raw[:suite_id],
      version: raw[:version],
      driver_name: raw[:driver_name],
      cases: raw[:cases].map { |smoke_case| described_class::GitDriverSmokeCase.new(**smoke_case) },
      diagnostics: raw[:diagnostics]
    )
    first_case = suite.cases.fetch(0)
    placeholder_set = [
      first_case.ancestor_placeholder,
      first_case.current_placeholder,
      first_case.other_placeholder,
      first_case.path_placeholder
    ]
    updated_current_file_count = suite.cases.count(&:expected_current_file_updated)

    expect(suite.driver_name).to eq(fixture.dig(:expected, :driver_name))
    expect(suite.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(placeholder_set).to eq(fixture.dig(:expected, :placeholder_set))
    expect(updated_current_file_count).to eq(fixture.dig(:expected, :updated_current_file_count))
  end

  it 'conforms to the slice-903 diff driver smoke fixtures fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-903-diff-driver-smoke-fixtures',
                                           'diff-driver-smoke-fixtures.json'))
    raw = fixture[:suite]
    suite = described_class::DiffDriverSmokeSuite.new(
      suite_id: raw[:suite_id],
      version: raw[:version],
      driver_name: raw[:driver_name],
      cases: raw[:cases].map { |smoke_case| described_class::DiffDriverSmokeCase.new(**smoke_case) },
      diagnostics: raw[:diagnostics]
    )
    argument_counts = suite.cases.map(&:argument_count)
    structured_diff_count = suite.cases.count { |smoke_case| smoke_case.expected_output_kind == 'structured_diff' }

    expect(suite.driver_name).to eq(fixture.dig(:expected, :driver_name))
    expect(suite.cases.length).to eq(fixture.dig(:expected, :case_count))
    expect(argument_counts).to eq(fixture.dig(:expected, :argument_counts))
    expect(structured_diff_count).to eq(fixture.dig(:expected, :structured_diff_count))
  end

  it 'conforms to the slice-904 performance guardrails fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-904-performance-guardrails',
                                           'performance-guardrails.json'))
    raw = fixture[:guardrails]
    guardrails = described_class::PerformanceGuardrails.new(
      guardrail_id: raw[:guardrail_id],
      version: raw[:version],
      max_bytes: raw[:max_bytes],
      max_nodes: raw[:max_nodes],
      max_match_candidates: raw[:max_match_candidates],
      timeout_ms: raw[:timeout_ms],
      timeout_diagnostic: described_class::PerformanceTimeoutDiagnostic.new(**raw[:timeout_diagnostic]),
      diagnostics: raw[:diagnostics]
    )

    expect(guardrails.max_bytes).to eq(fixture.dig(:expected, :max_bytes))
    expect(guardrails.max_nodes).to eq(fixture.dig(:expected, :max_nodes))
    expect(guardrails.max_match_candidates).to eq(fixture.dig(:expected, :max_match_candidates))
    expect(guardrails.timeout_ms).to eq(fixture.dig(:expected, :timeout_ms))
    expect(guardrails.timeout_diagnostic.code).to eq(fixture.dig(:expected, :timeout_code))
    expect(guardrails.timeout_diagnostic.fallback).to eq(fixture.dig(:expected, :fallback))
  end

  it 'conforms to the slice-905 profile conformance reports fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-905-profile-conformance-reports',
                                           'profile-conformance-reports.json'))
    raw = fixture[:report]
    report = described_class::ProfileConformanceReport.new(
      report_id: raw[:report_id],
      version: raw[:version],
      profile: raw[:profile],
      enabled_rules: raw[:enabled_rules],
      skipped_rules: raw[:skipped_rules].map { |skipped_rule| described_class::ProfileSkippedRule.new(**skipped_rule) },
      fallback_count: raw[:fallback_count],
      unresolved_conflict_count: raw[:unresolved_conflict_count],
      diagnostics: raw[:diagnostics]
    )

    expect(report.profile).to eq(fixture.dig(:expected, :profile))
    expect(report.enabled_rules.length).to eq(fixture.dig(:expected, :enabled_rule_count))
    expect(report.skipped_rules.length).to eq(fixture.dig(:expected, :skipped_rule_count))
    expect(report.fallback_count).to eq(fixture.dig(:expected, :fallback_count))
    expect(report.unresolved_conflict_count).to eq(fixture.dig(:expected, :unresolved_conflict_count))
    expect(report.skipped_rules.fetch(0).rule).to eq(fixture.dig(:expected, :skipped_rule))
  end

  def content_recipe_execution_request(recipe_name:, recipe_version:, relative_path:, provider_family:,
                                       template_content:, destination_content:, steps:, provider_backend: nil, runtime_context: nil, metadata: nil)
    request = {
      recipe_name: recipe_name.to_s,
      recipe_version: recipe_version.to_s,
      relative_path: relative_path.to_s,
      provider_family: provider_family.to_s,
      template_content: template_content.to_s,
      destination_content: destination_content.to_s,
      steps: fixture_deep_dup(steps)
    }
    request[:provider_backend] = provider_backend.to_s if provider_backend
    request[:runtime_context] = fixture_deep_dup(runtime_context) if runtime_context
    request[:metadata] = fixture_deep_dup(metadata) if metadata
    request
  end

  def content_recipe_execution_request_envelope(request)
    {
      kind: 'content_recipe_execution_request',
      version: described_class::STRUCTURED_EDIT_TRANSPORT_VERSION,
      request: fixture_deep_dup(request)
    }
  end

  def content_recipe_execution_report(request:, final_content:, changed:, step_reports:, diagnostics:, metadata: nil)
    report = {
      request: fixture_deep_dup(request),
      final_content: final_content.to_s,
      changed: changed ? true : false,
      step_reports: fixture_deep_dup(step_reports),
      diagnostics: fixture_deep_dup(diagnostics)
    }
    report[:metadata] = fixture_deep_dup(metadata) if metadata
    report
  end

  def content_recipe_execution_report_envelope(report)
    {
      kind: 'content_recipe_execution_report',
      version: described_class::STRUCTURED_EDIT_TRANSPORT_VERSION,
      report: fixture_deep_dup(report)
    }
  end

  def read_relative_file_tree(root)
    root = root.expand_path
    root.find.each_with_object({}) do |path, files|
      next if path.directory?

      rel = path.relative_path_from(root).to_s
      files[rel] = path.read
    end
  end

  def ruleset_fixture_paths
    fixtures_root.join('rulesets').find.select { |path| path.file? && path.extname == '.smrules' }
  end

  def repo_temp_dir
    root = Pathname(__dir__).join('..', '..', 'tmp').expand_path
    root.mkpath
    path = root.join("ast-merge-#{Process.pid}-#{Time.now.to_f.to_s.delete('.')}")
    path.mkpath
    path
  end

  def execution_key(ref)
    "#{ref[:family]}:#{ref[:role]}:#{ref[:case]}"
  end

  def execute_from(executions)
    lambda do |run|
      key = execution_key(run[:ref])
      executions[key.to_sym] || executions[key] || { outcome: 'failed', messages: ['missing execution'] }
    end
  end

  it 'conforms to the shared diagnostic vocabulary fixture' do
    fixture = diagnostics_fixture('diagnostic_vocabulary')

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

  it 'parses shared compact ruleset fixtures' do
    paths = ruleset_fixture_paths
    expect(paths).not_to be_empty

    paths.each do |path|
      result = described_class.parse_compact_ruleset(path.read)
      expect(result[:ok]).to be(true), "#{path}: #{result[:diagnostics].inspect}"
      expect(result.dig(:analysis, :directives)).not_to be_empty
    end
  end

  it 'rejects malformed compact ruleset edges' do
    cases = {
      'missing-required' => "format json\nowners line_bound_statements\nmatch stable_path\nread native_read_portable_write\n",
      'repeated-format' => "format json\nformat yaml\nowners line_bound_statements\nmatch stable_path\nread native_read_portable_write\nattach layout_only\n",
      'unknown-read' => "format json\nowners line_bound_statements\nmatch stable_path\nread imaginary\nattach layout_only\n",
      'unknown-directive' => "format json\nowners line_bound_statements\nmatch stable_path\nread native_read_portable_write\nattach layout_only\nmystery value\n"
    }

    cases.each do |name, source|
      result = described_class.parse_compact_ruleset(source)
      expect(result[:ok]).to be(false), name
      expect(result[:diagnostics]).not_to be_empty
    end
  end

  it 'derives the shared compact ruleset feature profile fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-781-compact-ruleset-profile', 'module-profile.json'))
    ruleset = described_class.parse_compact_ruleset(fixtures_root.join(*fixture[:ruleset_path]).read)

    expect(ruleset[:ok]).to be(true), ruleset[:diagnostics].inspect
    expect(described_class.compact_ruleset_feature_profile(ruleset.fetch(:analysis))).to eq(fixture.fetch(:profile))
  end

  it 'conforms to the shared policy vocabulary and reporting fixtures' do
    policy_fixture = diagnostics_fixture('policy_vocabulary')
    reporting_fixture = diagnostics_fixture('policy_reporting')

    policies = [
      { surface: 'fallback', name: 'trailing_comma_destination_fallback' },
      { surface: 'array', name: 'destination_wins_array' }
    ]

    expect(%w[fallback array]).to eq(policy_fixture[:surfaces])
    expect(json_ready(policies)).to eq(json_ready(policy_fixture[:policies]))
    expect(json_ready(policies.reverse)).to eq(json_ready(reporting_fixture[:merge_policies]))
  end

  it 'conforms to the slice-22 shared family feature profile fixture' do
    fixture = diagnostics_fixture('shared_family_feature_profile')

    feature_profile = {
      family: 'example',
      supported_dialects: %w[alpha beta],
      supported_policies: [{ surface: 'array', name: 'destination_wins_array' }]
    }

    expect(json_ready(feature_profile)).to eq(json_ready(fixture[:feature_profile]))
  end

  it 'conforms to the slice-908 language backend profile schema fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-908-language-backend-profile-schema',
                                           'language-backend-profile-schema.json'))
    profile = fixture[:profile]
    expected = fixture[:expected]

    contract = described_class::LanguageBackendProfile.new(
      profile_id: profile[:profile_id],
      family: profile[:family],
      version: profile[:version],
      parser_identity: described_class::ParserIdentity.new(**profile[:parser_identity]),
      extensions: profile[:extensions],
      aliases: profile[:aliases],
      git_attributes: described_class::GitAttributeProfile.new(**profile[:git_attributes]),
      supported_dialects: profile[:supported_dialects],
      backends: profile[:backends].map { |backend| described_class::BackendProfile.new(**backend) },
      rules: described_class::LanguageBackendProfileRules.new(
        node_roles: profile.dig(:rules, :node_roles),
        atomic_nodes: profile.dig(:rules, :atomic_nodes).map { |rule| described_class::AtomicNodeRule.new(**rule) },
        signatures: profile.dig(:rules, :signatures).map { |rule| described_class::SignatureDefinition.new(**rule) },
        commutative_parents: profile.dig(:rules, :commutative_parents).map do |rule|
          described_class::CommutativeParentDefinition.new(**rule)
        end,
        child_groups: profile.dig(:rules, :child_groups).map do |rule|
          described_class::ChildGroupDefinition.new(**rule)
        end,
        comment_attachment: profile.dig(:rules, :comment_attachment).map do |rule|
          described_class::CommentAttachmentRule.new(**rule)
        end
      )
    )

    expect(contract.profile_id).to eq(expected[:profile_id])
    expect(contract.family).to eq(expected[:family])
    expect(contract.backends.first.backend).to eq(expected[:default_backend])
    expect(contract.git_attributes.language_attributes.first).to eq(expected[:primary_language_attribute])
    expect(contract.rules.signatures.first.name).to eq(expected[:first_signature])
    expect(contract.rules.commutative_parents.first.selector).to eq(expected[:first_commutative_parent])
  end

  it 'conforms to the slice-909 profile validation fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-909-profile-validation', 'profile-validation.json'))
    expected = fixture[:expected]

    structural = described_class.validate_language_backend_profile(fixture[:structural_profile])
    expect(sorted_validation_messages(structural.errors)).to eq(expected[:structural_errors].sort)

    exhaustive = described_class.validate_language_backend_profile(fixture[:unknown_selector_profile],
                                                                   fixture[:backend_metadata])
    expect(sorted_validation_messages(exhaustive.errors)).to eq(expected[:exhaustive_backend_errors].sort)

    partial = described_class.validate_language_backend_profile(fixture[:unknown_selector_profile],
                                                                fixture[:partial_backend_metadata])
    expect(partial.errors).to be_empty
    expect(sorted_validation_messages(partial.warnings)).to eq(expected[:partial_backend_warnings].sort)
  end

  it 'conforms to the slice-910 active profile reporting fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-910-active-profile-reporting',
                                           'active-profile-reporting.json'))
    expected = fixture[:expected]
    active_profile = fixture[:active_profile]

    contract = active_profile_contract(active_profile)
    report = described_class::ProfileConformanceReport.new(
      **fixture[:conformance_report].merge(active_profile: contract)
    )
    debug_output = described_class::ProfileDebugOutput.new(
      mode: fixture.dig(:debug_output, :mode),
      active_profile: contract,
      diagnostics: fixture.dig(:debug_output, :diagnostics)
    )

    expect(contract.profile_id).to eq(expected[:profile_id])
    expect(contract.family).to eq(expected[:family])
    expect(contract.backend).to eq(expected[:backend])
    expect(contract.parser).to eq(expected[:parser])
    expect(contract.rule_counts.signatures).to eq(expected[:signature_count])
    expect(contract.validation.ok).to eq(expected[:validation_ok])
    expect(report.active_profile.profile_id).to eq(expected[:profile_id])
    expect(debug_output.mode).to eq(expected[:debug_mode])
    expect(debug_output.active_profile.profile_id).to eq(expected[:profile_id])
  end

  it 'conforms to the slice-911 profile promotion report fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-911-profile-promotion-report',
                                           'profile-promotion-report.json'))
    expected = fixture[:expected]
    report_fixture = fixture[:report]
    blocked_fixture = fixture[:blocked_report]

    report = promotion_report_contract(report_fixture)
    blocked = promotion_report_contract(blocked_fixture)

    expect(report.profile_id).to eq(expected[:profile_id])
    expect(report.status).to eq(expected[:recommended_status])
    expect(report.hard_gates.length).to eq(expected[:hard_gate_count])
    expect(report.metrics.required_fixture_count).to eq(expected[:required_fixture_count])
    expect(report.metrics.formatting_threshold).to eq(expected[:formatting_threshold])
    expect(report.active_profile.profile_id).to eq(expected[:profile_id])
    expect(blocked.status).to eq(expected[:blocked_status])
    expect(blocked.blocking_reasons.length).to eq(expected[:blocking_reason_count])
  end

  it 'conforms to the slice-912 profile promotion policy fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-912-profile-promotion-policy',
                                           'profile-promotion-policy.json'))
    expected = fixture[:expected]
    policy_fixture = fixture[:policy]
    policy = promotion_policy_contract(policy_fixture)

    recommended_eligible = policy.profiles.count { |entry| entry.eligible_statuses.include?('recommended') }
    default_eligible = policy.profiles.count { |entry| entry.eligible_statuses.include?('default') }
    source_subprofiles = policy.profiles.count { |entry| entry.scope == 'source_subprofile' }
    json_policy = policy.profiles.find do |entry|
      entry.profile_id == described_class::PROMOTION_PROFILE_JSON_KEYED_OBJECT
    end
    ruby_policy = policy.profiles.find do |entry|
      entry.profile_id == described_class::PROMOTION_PROFILE_RUBY_GEMSPEC_DEPENDENCY_DECLARATIONS
    end

    expect(policy.policy_id).to eq(expected[:policy_id])
    expect(policy.profiles.length).to eq(expected[:profile_count])
    expect(policy.global_hard_gates.length).to eq(expected[:global_hard_gate_count])
    expect(recommended_eligible).to eq(expected[:recommended_eligible_count])
    expect(default_eligible).to eq(expected[:default_eligible_count])
    expect(source_subprofiles).to eq(expected[:source_subprofile_count])
    expect(json_policy.recommendation_gate.requires_cross_implementation_parity).to eq(expected[:json_requires_cross_implementation_parity])
    expect(ruby_policy.recommendation_gate.requires_backend_parity).to eq(expected[:ruby_requires_backend_parity])
    expect(json_policy.recommendation_gate.formatting_threshold).to eq(expected[:formatting_threshold])
    expect(json_ready(described_class.initial_profile_promotion_policy)).to eq(json_ready(policy))
  end

  it 'conforms to the slice-913 profile promotion evaluation fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-913-profile-promotion-evaluation',
                                           'profile-promotion-evaluation.json'))
    expected = fixture[:expected]
    policy = promotion_policy_contract(fixture[:policy])
    recommended_report = promotion_report_contract(fixture[:recommended_report])
    blocked_report = promotion_report_contract(fixture[:blocked_report])

    recommended = described_class.evaluate_profile_promotion(policy, recommended_report)
    expect(recommended.status).to eq(expected[:recommended_status])
    expect(recommended.blocking_reasons.length).to eq(expected[:recommended_blocking_reason_count])

    blocked = described_class.evaluate_profile_promotion(policy, blocked_report)
    expect(blocked.status).to eq(expected[:blocked_status])
    expect(blocked.blocking_reasons.length).to eq(expected[:blocked_blocking_reason_count])
    expect(blocked.blocking_reasons.first).to eq(expected[:first_blocking_reason])

    unknown_report = promotion_report_contract(fixture[:recommended_report].merge(profile_id: 'unknown.profile'))
    unknown = described_class.evaluate_profile_promotion(policy, unknown_report)
    expect(unknown.status).to eq(expected[:unknown_profile_status])
  end

  it 'conforms to the slice-914 profile selection enforcement fixture' do
    fixture = read_json(fixtures_root.join('diagnostics', 'slice-914-profile-selection-enforcement',
                                           'profile-selection-enforcement.json'))
    expected = fixture[:expected]
    active_profile = active_profile_contract(fixture[:active_profile])
    available_evaluation = promotion_evaluation_contract(fixture[:available_evaluation])
    recommended_evaluation = promotion_evaluation_contract(fixture[:recommended_evaluation])
    advisory_requirement = profile_selection_requirement_contract(fixture[:advisory_requirement])
    required_requirement = profile_selection_requirement_contract(fixture[:required_requirement])
    satisfied_requirement = profile_selection_requirement_contract(fixture[:satisfied_requirement])

    advisory = described_class.evaluate_profile_selection_requirement(advisory_requirement, active_profile,
                                                                      available_evaluation)
    expect(advisory.allowed).to eq(expected[:advisory_allowed])
    expect(advisory.satisfied).to eq(expected[:advisory_satisfied])
    expect(advisory.enforced).to eq(expected[:advisory_enforced])
    expect(advisory.rejection_code).to eq(expected[:advisory_rejection_code])

    required = described_class.evaluate_profile_selection_requirement(required_requirement, active_profile,
                                                                      available_evaluation)
    expect(required.allowed).to eq(expected[:required_allowed])
    expect(required.satisfied).to eq(expected[:required_satisfied])
    expect(required.enforced).to eq(expected[:required_enforced])
    expect(required.rejection_code).to eq(expected[:required_rejection_code])
    expect(required.blocking_reasons.first).to eq(expected[:required_first_blocking_reason])

    satisfied = described_class.evaluate_profile_selection_requirement(satisfied_requirement, active_profile,
                                                                       recommended_evaluation)
    expect(satisfied.allowed).to eq(expected[:satisfied_allowed])
    expect(satisfied.satisfied).to eq(expected[:satisfied_satisfied])
    expect(satisfied.enforced).to eq(expected[:satisfied_enforced])
    expect(satisfied.rejection_code).to eq(expected[:satisfied_rejection_code])
    expect(satisfied.blocking_reasons).to be_empty
  end

  it 'conforms to the template source path mapping fixture' do
    fixture = diagnostics_fixture('template_source_path_mapping')

    fixture[:cases].each do |test_case|
      expect(described_class.normalize_template_source_path(test_case[:template_source_path])).to eq(
        test_case[:expected_destination_path]
      )
    end
  end

  it 'conforms to the template target classification fixture' do
    fixture = diagnostics_fixture('template_target_classification')

    fixture[:cases].each do |test_case|
      expect(json_ready(described_class.classify_template_target_path(test_case[:destination_path]))).to eq(
        json_ready(test_case[:expected])
      )
    end
  end

  it 'conforms to the template destination mapping fixture' do
    fixture = diagnostics_fixture('template_destination_mapping')

    fixture[:cases].each do |test_case|
      expect(
        described_class.resolve_template_destination_path(
          test_case[:logical_destination_path],
          test_case[:context]
        )
      ).to eq(test_case[:expected_destination_path])
    end
  end

  it 'conforms to the template strategy selection fixture' do
    fixture = diagnostics_fixture('template_strategy_selection')

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

  it 'conforms to the template token keys fixture' do
    fixture = diagnostics_fixture('template_token_keys')

    fixture[:cases].each do |test_case|
      expect(
        described_class.template_token_keys(
          test_case[:content],
          test_case[:config]
        )
      ).to eq(test_case[:expected_token_keys])
    end
  end

  it 'conforms to the template entry plan fixture' do
    fixture = diagnostics_fixture('template_entry_plan')

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

  it 'conforms to the template entry token state fixture' do
    fixture = diagnostics_fixture('template_entry_token_state')

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

  it 'conforms to the template entry prepared content fixture' do
    fixture = diagnostics_fixture('template_entry_prepared_content')

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

  it 'conforms to the template execution plan fixture' do
    fixture = diagnostics_fixture('template_execution_plan')

    expect(
      json_ready(
        described_class.plan_template_execution(
          fixture[:prepared_entries],
          fixture[:destination_contents]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it 'conforms to the mini template tree plan fixture' do
    fixture = diagnostics_fixture('mini_template_tree_plan')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics', 'mini_template_tree_plan')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

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

  it 'conforms to the mini template tree preview fixture' do
    plan_fixture = diagnostics_fixture('mini_template_tree_plan')
    preview_fixture = diagnostics_fixture('mini_template_tree_preview')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics', 'mini_template_tree_plan')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

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

  it 'conforms to the mini template tree apply fixture' do
    plan_fixture = diagnostics_fixture('mini_template_tree_plan')
    apply_fixture = diagnostics_fixture('mini_template_tree_apply')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics', 'mini_template_tree_plan')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

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
      destination_path = entry[:destination_path] || entry['destination_path']
      apply_fixture[:merge_results][destination_path] || apply_fixture[:merge_results][destination_path.to_sym]
    end

    expect(json_ready(apply_result)).to eq(json_ready(apply_fixture[:expected_result]))
  end

  it 'conforms to the mini template tree convergence fixture' do
    plan_fixture = diagnostics_fixture('mini_template_tree_plan')
    apply_fixture = diagnostics_fixture('mini_template_tree_apply')
    convergence_fixture = diagnostics_fixture('mini_template_tree_convergence')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics', 'mini_template_tree_plan')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

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
      destination_path = entry[:destination_path] || entry['destination_path']
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

  it 'conforms to the mini template tree run fixture' do
    plan_fixture = diagnostics_fixture('mini_template_tree_plan')
    run_fixture = diagnostics_fixture('mini_template_tree_run')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics', 'mini_template_tree_plan')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    ) do |entry|
      destination_path = entry[:destination_path] || entry['destination_path']
      run_fixture[:merge_results][destination_path] || run_fixture[:merge_results][destination_path.to_sym]
    end

    expect(json_ready(run_result)).to eq(json_ready(run_fixture[:expected]))
  end

  it 'conforms to the mini template tree run report fixture' do
    plan_fixture = diagnostics_fixture('mini_template_tree_plan')
    run_fixture = diagnostics_fixture('mini_template_tree_run')
    report_fixture = diagnostics_fixture('mini_template_tree_run_report')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics', 'mini_template_tree_plan')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      plan_fixture[:context],
      plan_fixture[:default_strategy],
      plan_fixture[:overrides],
      plan_fixture[:replacements]
    ) do |entry|
      destination_path = entry[:destination_path] || entry['destination_path']
      run_fixture[:merge_results][destination_path] || run_fixture[:merge_results][destination_path.to_sym]
    end

    expect(json_ready(described_class.report_template_tree_run(run_result))).to eq(json_ready(report_fixture[:expected]))
  end

  it 'conforms to the mini template tree family merge callback fixture' do
    fixture = diagnostics_fixture('mini_template_tree_family_merge_callback')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_family_merge_callback')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      family = entry.dig(:classification, :family) || entry.dig('classification', 'family')
      case family
      when 'markdown'
        Markdown::Merge.merge_markdown(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'markdown'
        )
      else
        {
          ok: false,
          diagnostics: [{ severity: 'error', category: 'configuration_error',
                          message: "missing family merge adapter for #{family}" }],
          policies: []
        }
      end
    end

    expect(json_ready(run_result)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the mini template tree multi-family merge callback fixture' do
    fixture = diagnostics_fixture('mini_template_tree_multi_family_merge_callback')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_multi_family_merge_callback')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      family = entry.dig(:classification, :family) || entry.dig('classification', 'family')
      case family
      when 'markdown'
        Markdown::Merge.merge_markdown(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'markdown'
        )
      when 'toml'
        Toml::Merge.merge_toml(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'toml'
        )
      when 'ruby'
        Ruby::Merge.merge_ruby(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'ruby'
        )
      else
        {
          ok: false,
          diagnostics: [{ severity: 'error', category: 'configuration_error',
                          message: "missing family merge adapter for #{family}" }],
          policies: []
        }
      end
    end

    expect(json_ready(run_result)).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the mini template tree multi-family run report fixture' do
    fixture = diagnostics_fixture('mini_template_tree_multi_family_merge_callback')
    report_fixture = diagnostics_fixture('mini_template_tree_multi_family_run_report')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_multi_family_merge_callback')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    template_contents = read_relative_file_tree(fixture_dir.join('template'))
    destination_contents = read_relative_file_tree(fixture_dir.join('destination'))

    run_result = described_class.run_template_tree_execution(
      template_contents.keys.sort,
      template_contents,
      destination_contents,
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      family = entry.dig(:classification, :family) || entry.dig('classification', 'family')
      case family
      when 'markdown'
        Markdown::Merge.merge_markdown(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'markdown'
        )
      when 'toml'
        Toml::Merge.merge_toml(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'toml'
        )
      when 'ruby'
        Ruby::Merge.merge_ruby(
          entry[:prepared_template_content] || entry['prepared_template_content'],
          entry[:destination_content] || entry['destination_content'],
          'ruby'
        )
      else
        {
          ok: false,
          diagnostics: [{ severity: 'error', category: 'configuration_error',
                          message: "missing family merge adapter for #{family}" }],
          policies: []
        }
      end
    end

    expect(json_ready(described_class.report_template_tree_run(run_result))).to eq(json_ready(report_fixture[:expected]))
  end

  it 'conforms to the mini template tree directory run report fixture' do
    fixture = diagnostics_fixture('mini_template_tree_directory_run_report')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_directory_run_report')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])

    run_result = described_class.run_template_tree_execution_from_directories(
      fixture_dir.join('template'),
      fixture_dir.join('destination'),
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    ) do |entry|
      case entry[:classification][:family]
      when 'markdown'
        Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
      when 'toml'
        Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
      when 'ruby'
        Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
      else
        {
          ok: false,
          diagnostics: [{ severity: 'error', category: 'configuration_error',
                          message: "missing family merge adapter for #{entry[:classification][:family]}" }]
        }
      end
    end

    expect(json_ready(described_class.report_template_tree_run(run_result))).to eq(json_ready(fixture[:expected]))
  end

  it 'conforms to the mini template tree directory apply convergence fixture' do
    fixture = diagnostics_fixture('mini_template_tree_directory_apply_convergence')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_directory_apply_convergence')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    temp_dir = repo_temp_dir
    destination_root = temp_dir.join('destination')

    begin
      described_class.write_relative_file_tree(destination_root,
                                               read_relative_file_tree(fixture_dir.join('destination')))

      first_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join('template'),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when 'markdown'
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
        when 'toml'
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
        when 'ruby'
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
        else
          {
            ok: false,
            diagnostics: [{ severity: 'error', category: 'configuration_error',
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
        fixture_dir.join('template'),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when 'markdown'
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
        when 'toml'
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
        when 'ruby'
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
        else
          {
            ok: false,
            diagnostics: [{ severity: 'error', category: 'configuration_error',
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

  it 'conforms to the mini template tree directory apply report fixture' do
    fixture = diagnostics_fixture('mini_template_tree_directory_apply_report')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_directory_apply_report')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])
    temp_dir = repo_temp_dir
    destination_root = temp_dir.join('destination')

    begin
      described_class.write_relative_file_tree(destination_root,
                                               read_relative_file_tree(fixture_dir.join('destination')))

      first_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join('template'),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when 'markdown'
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
        when 'toml'
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
        when 'ruby'
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
        else
          {
            ok: false,
            diagnostics: [{ severity: 'error', category: 'configuration_error',
                            message: "missing family merge adapter for #{entry[:classification][:family]}" }]
          }
        end
      end

      expect(json_ready(described_class.report_template_directory_apply(first_run))).to eq(
        json_ready(fixture[:expected_first_report])
      )

      second_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join('template'),
        destination_root,
        fixture[:context],
        fixture[:default_strategy],
        fixture[:overrides],
        fixture[:replacements]
      ) do |entry|
        case entry[:classification][:family]
        when 'markdown'
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
        when 'toml'
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
        when 'ruby'
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
        else
          {
            ok: false,
            diagnostics: [{ severity: 'error', category: 'configuration_error',
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

  it 'conforms to the mini template tree directory plan report fixture' do
    fixture = diagnostics_fixture('mini_template_tree_directory_plan_report')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_directory_plan_report')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])

    execution_plan = described_class.plan_template_tree_execution_from_directories(
      fixture_dir.join('template'),
      fixture_dir.join('destination'),
      fixture[:context],
      fixture[:default_strategy],
      fixture[:overrides],
      fixture[:replacements]
    )

    expect(json_ready(described_class.report_template_directory_plan(execution_plan))).to eq(
      json_ready(fixture[:expected])
    )
  end

  it 'conforms to the mini template tree directory runner report fixture' do
    fixture = diagnostics_fixture('mini_template_tree_directory_runner_report')
    fixture_path = described_class.conformance_fixture_path(manifest, 'diagnostics',
                                                            'mini_template_tree_directory_runner_report')
    fixture_dir = fixtures_root.join(*fixture_path[0...-1])

    dry_run_plan = described_class.plan_template_tree_execution_from_directories(
      fixture_dir.join('dry-run', 'template'),
      fixture_dir.join('dry-run', 'destination'),
      fixture.dig(:dry_run, :context),
      fixture.dig(:dry_run, :default_strategy),
      fixture.dig(:dry_run, :overrides),
      fixture.dig(:dry_run, :replacements)
    )
    expect(json_ready(described_class.report_template_directory_runner(dry_run_plan))).to eq(
      json_ready(fixture.dig(:dry_run, :expected))
    )

    temp_dir = repo_temp_dir
    destination_root = temp_dir.join('destination')
    begin
      described_class.write_relative_file_tree(
        destination_root,
        read_relative_file_tree(fixture_dir.join('apply-run', 'destination'))
      )

      apply_plan = described_class.plan_template_tree_execution_from_directories(
        fixture_dir.join('apply-run', 'template'),
        destination_root,
        fixture.dig(:apply_run, :context),
        fixture.dig(:apply_run, :default_strategy),
        fixture.dig(:apply_run, :overrides),
        fixture.dig(:apply_run, :replacements)
      )
      apply_run = described_class.apply_template_tree_execution_to_directory(
        fixture_dir.join('apply-run', 'template'),
        destination_root,
        fixture.dig(:apply_run, :context),
        fixture.dig(:apply_run, :default_strategy),
        fixture.dig(:apply_run, :overrides),
        fixture.dig(:apply_run, :replacements)
      ) do |entry|
        case entry[:classification][:family]
        when 'markdown'
          Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], 'markdown')
        when 'toml'
          Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], 'toml')
        when 'ruby'
          Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], 'ruby')
        else
          {
            ok: false,
            diagnostics: [{ severity: 'error', category: 'configuration_error',
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

  it 'conforms to the template entry plan state fixture' do
    fixture = diagnostics_fixture('template_entry_plan_state')

    expect(
      json_ready(
        described_class.enrich_template_plan_entries(
          fixture[:planned_entries],
          fixture[:existing_destination_paths]
        )
      )
    ).to eq(json_ready(fixture[:expected_entries]))
  end

  it 'resolves canonical manifest paths, including widened source-family entries' do
    expect(described_class.conformance_family_feature_profile_path(manifest, 'json')).to eq(
      %w[diagnostics slice-21-family-feature-profile json-feature-profile.json]
    )
    expect(described_class.conformance_fixture_path(manifest, 'text', 'analysis')).to eq(
      %w[text slice-03-analysis whitespace-and-blocks.json]
    )
    expect(described_class.conformance_family_feature_profile_path(manifest, 'typescript')).to eq(
      %w[diagnostics slice-101-typescript-family-feature-profile typescript-feature-profile.json]
    )
    expect(described_class.conformance_fixture_path(manifest, 'go', 'analysis')).to eq(
      %w[go slice-110-analysis module-owners.json]
    )
  end

  it 'conforms to the runner shape and summary fixtures' do
    runner_fixture = diagnostics_fixture('runner_shape')
    summary_fixture = diagnostics_fixture('runner_summary')

    case_ref = { family: 'json', role: 'tree_sitter_adapter', case: 'valid_strict_json' }
    result = { ref: case_ref, outcome: 'passed', messages: [] }

    expect(json_ready(case_ref)).to eq(json_ready(runner_fixture[:case_ref]))
    expect(json_ready(result)).to eq(json_ready(runner_fixture[:result]))

    summary = described_class.summarize_conformance_results(summary_fixture[:results])
    expect(json_ready(summary)).to eq(json_ready(summary_fixture[:summary]))
  end

  it 'conforms to the selection fixtures' do
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

  it 'conforms to the case and suite runner fixtures' do
    case_fixture = diagnostics_fixture('case_runner')
    suite_fixture = diagnostics_fixture('suite_runner')

    case_fixture[:cases].each do |test_case|
      result = described_class.run_conformance_case(test_case[:run], &->(_run) { test_case[:execution] })
      expect(json_ready(result)).to eq(json_ready(test_case[:expected]))
    end

    suite_results = described_class.run_conformance_suite(suite_fixture[:cases],
                                                          &execute_from(suite_fixture[:executions]))
    expect(json_ready(suite_results)).to eq(json_ready(suite_fixture[:expected_results]))
  end

  it 'conforms to the suite plan and report fixtures' do
    suite_plan_fixture = diagnostics_fixture('suite_plan')
    planned_runner_fixture = diagnostics_fixture('planned_suite_runner')
    planned_report_fixture = diagnostics_fixture('planned_suite_report')
    suite_report_fixture = diagnostics_fixture('suite_report')
    manifest_requirements_fixture = diagnostics_fixture('manifest_requirements')
    backend_requirements_fixture = diagnostics_fixture('manifest_backend_requirements')
    backend_report_fixture = diagnostics_fixture('manifest_backend_report')

    plan = described_class.plan_conformance_suite(
      manifest,
      suite_plan_fixture[:family],
      suite_plan_fixture[:roles],
      suite_plan_fixture[:family_profile],
      suite_plan_fixture[:feature_profile]
    )
    expect(json_ready(plan)).to eq(json_ready(suite_plan_fixture[:expected]))

    planned_results = described_class.run_planned_conformance_suite(planned_runner_fixture[:plan],
                                                                    &execute_from(planned_runner_fixture[:executions]))
    expect(json_ready(planned_results)).to eq(json_ready(planned_runner_fixture[:expected_results]))

    report = described_class.report_planned_conformance_suite(planned_report_fixture[:plan],
                                                              &execute_from(planned_report_fixture[:executions]))
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
      &->(_run) { { outcome: 'failed', messages: ['unexpected execution'] } }
    )
    expect(json_ready(backend_report)).to eq(json_ready(backend_report_fixture[:expected_report]))
  end

  it 'conforms to named suite planning and reporting fixtures' do
    suite_definitions_fixture = diagnostics_fixture('suite_definitions')
    named_suite_report_fixture = diagnostics_fixture('named_suite_report')
    named_suite_runner_fixture = diagnostics_fixture('named_suite_runner')
    suite_names_fixture = diagnostics_fixture('suite_names')
    named_suite_entry_fixture = diagnostics_fixture('named_suite_entry')
    named_suite_plan_entry_fixture = diagnostics_fixture('named_suite_plan_entry')
    family_plan_context_fixture = diagnostics_fixture('family_plan_context')
    named_suite_plans_fixture = diagnostics_fixture('named_suite_plans')
    named_suite_results_fixture = diagnostics_fixture('named_suite_results')
    named_suite_runner_entries_fixture = diagnostics_fixture('named_suite_runner_entries')
    named_suite_report_entries_fixture = diagnostics_fixture('named_suite_report_entries')
    named_suite_summary_fixture = diagnostics_fixture('named_suite_summary')
    named_suite_report_envelope_fixture = diagnostics_fixture('named_suite_report_envelope')
    named_suite_report_manifest_fixture = diagnostics_fixture('named_suite_report_manifest')

    expect(json_ready(described_class.conformance_suite_definition(manifest,
                                                                   suite_definitions_fixture[:suite_selector]))).to eq(
                                                                     json_ready(suite_definitions_fixture[:expected])
                                                                   )
    expect(json_ready(described_class.conformance_suite_selectors(manifest))).to eq(json_ready(suite_names_fixture[:suite_selectors]))
    expect(json_ready(named_suite_plan_entry_fixture[:context])).to eq(json_ready(family_plan_context_fixture[:context]))

    named_entry = described_class.report_named_conformance_suite_entry(
      manifest,
      named_suite_entry_fixture[:suite_selector],
      named_suite_entry_fixture[:family_profile],
      {
        backend: 'kreuzberg-language-pack',
        supports_dialects: false,
        supported_policies: [{ surface: 'array', name: 'destination_wins_array' }]
      },
      &execute_from(named_suite_entry_fixture[:executions])
    )
    expect(json_ready(named_entry)).to eq(json_ready(named_suite_entry_fixture[:expected_entry]))

    named_runner = described_class.run_named_conformance_suite(
      manifest,
      named_suite_runner_fixture[:suite_selector],
      named_suite_runner_fixture[:family_profile],
      {
        backend: 'kreuzberg-language-pack',
        supports_dialects: false,
        supported_policies: [{ surface: 'array', name: 'destination_wins_array' }]
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
        backend: 'kreuzberg-language-pack',
        supports_dialects: false,
        supported_policies: [{ surface: 'array', name: 'destination_wins_array' }]
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
        backend: 'kreuzberg-language-pack',
        supports_dialects: false,
        supported_policies: [{ surface: 'array', name: 'destination_wins_array' }]
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

  it 'conforms to manifest planning, defaulting, and review host fixtures' do
    default_context_fixture = diagnostics_fixture('default_family_context')
    explicit_mode_fixture = diagnostics_fixture('explicit_family_context_mode')
    missing_roles_fixture = diagnostics_fixture('missing_suite_roles')
    manifest_report_fixture = diagnostics_fixture('conformance_manifest_report')
    host_hints_fixture = diagnostics_fixture('review_host_hints')
    request_ids_fixture = diagnostics_fixture('review_request_ids')
    family_request_fixture = diagnostics_fixture('family_context_review_request')

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
    expect(described_class.conformance_manifest_review_request_ids(request_ids_fixture[:manifest],
                                                                   request_ids_fixture[:options])).to eq(request_ids_fixture[:expected_request_ids])

    _context, _diagnostics, requests, _decisions = described_class.review_conformance_family_context(
      family_request_fixture[:family],
      family_request_fixture[:options]
    )
    expect(json_ready(requests.first)).to eq(json_ready(family_request_fixture[:expected_request]))
  end

  it 'conforms to review-state, replay, and explicit-context fixtures' do
    review_state_fixture = diagnostics_fixture('conformance_manifest_review_state')
    reviewed_default_fixture = diagnostics_fixture('reviewed_default_context')
    replay_compatibility_fixture = diagnostics_fixture('review_replay_compatibility')
    replay_rejection_fixture = diagnostics_fixture('review_replay_rejection')
    stale_decision_fixture = diagnostics_fixture('stale_review_decision')
    replay_bundle_fixture = diagnostics_fixture('review_replay_bundle')
    replay_bundle_reviewed_nested_fixture = diagnostics_fixture('review_replay_bundle_reviewed_nested_executions')
    replay_bundle_application_fixture = diagnostics_fixture('review_replay_bundle_application')
    review_state_reviewed_nested_fixture = diagnostics_fixture('review_state_reviewed_nested_executions')
    review_state_roundtrip_fixture = diagnostics_fixture('review_state_json_roundtrip')
    replay_bundle_roundtrip_fixture = diagnostics_fixture('review_replay_bundle_json_roundtrip')
    review_state_envelope_fixture = diagnostics_fixture('review_state_envelope')
    replay_bundle_envelope_fixture = diagnostics_fixture('review_replay_bundle_envelope')
    review_state_envelope_rejection_fixture = diagnostics_fixture('review_state_envelope_rejection')
    replay_bundle_envelope_rejection_fixture = diagnostics_fixture('review_replay_bundle_envelope_rejection')
    reviewed_nested_execution_roundtrip_fixture = diagnostics_fixture('reviewed_nested_execution_json_roundtrip')
    reviewed_nested_execution_envelope_fixture = diagnostics_fixture('reviewed_nested_execution_envelope')
    reviewed_nested_execution_envelope_rejection_fixture = diagnostics_fixture('reviewed_nested_execution_envelope_rejection')
    reviewed_nested_execution_replay_application_fixture = diagnostics_fixture('review_replay_bundle_reviewed_nested_execution_application')
    reviewed_nested_execution_state_application_fixture = diagnostics_fixture('review_state_reviewed_nested_execution_application')
    review_proposal_fixture = diagnostics_fixture('family_context_review_proposal')
    explicit_decision_fixture = diagnostics_fixture('family_context_explicit_review_decision')
    explicit_bundle_fixture = diagnostics_fixture('explicit_review_replay_bundle_application')
    missing_context_fixture = diagnostics_fixture('explicit_review_decision_missing_context')
    family_mismatch_fixture = diagnostics_fixture('explicit_review_decision_family_mismatch')
    surface_fixture = diagnostics_fixture('surface_ownership')
    delegated_operation_fixture = diagnostics_fixture('delegated_child_operation')
    structured_edit_structure_profile_fixture = diagnostics_fixture('structured_edit_structure_profile')
    structured_edit_selection_profile_fixture = diagnostics_fixture('structured_edit_selection_profile')
    structured_edit_match_profile_fixture = diagnostics_fixture('structured_edit_match_profile')
    structured_edit_operation_profile_fixture = diagnostics_fixture('structured_edit_operation_profile')
    structured_edit_destination_profile_fixture = diagnostics_fixture('structured_edit_destination_profile')
    structured_edit_request_fixture = diagnostics_fixture('structured_edit_request')
    structured_edit_result_fixture = diagnostics_fixture('structured_edit_result')
    structured_edit_application_fixture = diagnostics_fixture('structured_edit_application')
    structured_edit_application_envelope_fixture = diagnostics_fixture('structured_edit_application_envelope')
    structured_edit_application_envelope_rejection_fixture = diagnostics_fixture('structured_edit_application_envelope_rejection')
    structured_edit_application_envelope_application_fixture = diagnostics_fixture('structured_edit_application_envelope_application')
    structured_edit_request_envelope_fixture = diagnostics_fixture('structured_edit_request_envelope')
    structured_edit_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_request_envelope_rejection')
    structured_edit_request_envelope_application_fixture = diagnostics_fixture('structured_edit_request_envelope_application')
    structured_edit_profile_promotion_envelope_fixture = read_json(fixtures_root.join('diagnostics',
                                                                                      'slice-915-structured-edit-profile-promotion-envelope', 'structured-edit-profile-promotion-envelope.json'))
    structured_edit_execution_report_fixture = diagnostics_fixture('structured_edit_execution_report')
    structured_edit_crispr_overmatch_fail_closed_fixture = diagnostics_fixture('structured_edit_crispr_overmatch_fail_closed')
    structured_edit_crispr_acceptance_scenario_fixture = diagnostics_fixture('structured_edit_crispr_acceptance_scenario')
    structured_edit_crispr_append_fallback_insert_fixture = diagnostics_fixture('structured_edit_crispr_append_fallback_insert')
    structured_edit_crispr_ruby_comment_owned_rewrite_delete_parity_fixture = diagnostics_fixture('structured_edit_crispr_ruby_comment_owned_rewrite_delete_parity')
    structured_edit_crispr_ruby_callable_destination_move_parity_fixture = diagnostics_fixture('structured_edit_crispr_ruby_callable_destination_move_parity')
    structured_edit_crispr_markdown_heading_section_replace_parity_fixture = diagnostics_fixture('structured_edit_crispr_markdown_heading_section_replace_parity')
    structured_edit_crispr_example_parity_report_fixture = diagnostics_fixture('structured_edit_crispr_example_parity_report')
    structured_edit_crispr_parity_substrate_report_fixture = diagnostics_fixture('structured_edit_crispr_parity_substrate_report')
    structured_edit_kettle_jem_primitive_gap_report_fixture = diagnostics_fixture('structured_edit_kettle_jem_primitive_gap_report')
    content_recipe_execution_envelope_fixture = diagnostics_fixture('content_recipe_execution_envelope')
    single_file_readme_heading_section_acceptance_fixture = diagnostics_fixture('single_file_readme_heading_section_acceptance')
    native_structured_edit_recipe_steps_fixture = diagnostics_fixture('native_structured_edit_recipe_steps')
    ruby_gemfile_signature_merge_acceptance_fixture = diagnostics_fixture('ruby_gemfile_signature_merge_acceptance')
    ruby_gemspec_native_boundary_report_fixture = diagnostics_fixture('ruby_gemspec_native_boundary_report')
    ruby_gemspec_signature_merge_acceptance_fixture = diagnostics_fixture('ruby_gemspec_signature_merge_acceptance')
    ruby_gemspec_field_policy_acceptance_fixture = diagnostics_fixture('ruby_gemspec_field_policy_acceptance')
    ruby_gemspec_dependency_section_policy_acceptance_fixture = diagnostics_fixture('ruby_gemspec_dependency_section_policy_acceptance')
    ruby_gemspec_files_policy_acceptance_fixture = diagnostics_fixture('ruby_gemspec_files_policy_acceptance')
    ruby_gemspec_version_loader_policy_acceptance_fixture = diagnostics_fixture('ruby_gemspec_version_loader_policy_acceptance')
    runtime_facts_context_fixture = diagnostics_fixture('runtime_facts_context')
    ruby_gemspec_self_dependency_policy_acceptance_fixture = diagnostics_fixture('ruby_gemspec_self_dependency_policy_acceptance')
    ruby_gemfile_self_dependency_policy_acceptance_fixture = diagnostics_fixture('ruby_gemfile_self_dependency_policy_acceptance')
    ruby_appraisals_self_dependency_policy_acceptance_fixture = diagnostics_fixture('ruby_appraisals_self_dependency_policy_acceptance')
    ruby_appraisals_min_ruby_prune_policy_acceptance_fixture = diagnostics_fixture('ruby_appraisals_min_ruby_prune_policy_acceptance')
    changelog_unreleased_normalization_acceptance_fixture = diagnostics_fixture('changelog_unreleased_normalization_acceptance')
    readme_supplied_metadata_synchronization_acceptance_fixture = diagnostics_fixture('readme_supplied_metadata_synchronization_acceptance')
    supplied_markdown_pruning_acceptance_fixture = diagnostics_fixture('supplied_markdown_pruning_acceptance')
    supplied_source_selector_deletion_acceptance_fixture = diagnostics_fixture('supplied_source_selector_deletion_acceptance')
    supplied_yaml_snippet_synchronization_acceptance_fixture = diagnostics_fixture('supplied_yaml_snippet_synchronization_acceptance')
    supplied_managed_text_block_replacement_acceptance_fixture = diagnostics_fixture('supplied_managed_text_block_replacement_acceptance')
    supplied_yaml_placeholder_scalar_backfill_acceptance_fixture = diagnostics_fixture('supplied_yaml_placeholder_scalar_backfill_acceptance')
    structured_edit_callable_destination_request_fixture = diagnostics_fixture('structured_edit_callable_destination_request')
    structured_edit_parity_selection_semantics_fixture = diagnostics_fixture('structured_edit_parity_selection_semantics')
    structured_edit_parity_match_semantics_fixture = diagnostics_fixture('structured_edit_parity_match_semantics')
    structured_edit_operation_triad_parity_fixture = diagnostics_fixture('structured_edit_operation_triad_parity')
    structured_edit_provider_execution_request_fixture = diagnostics_fixture('structured_edit_provider_execution_request')
    structured_edit_provider_execution_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_request_envelope')
    structured_edit_provider_execution_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_request_envelope_rejection')
    structured_edit_provider_execution_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_request_envelope_application')
    structured_edit_provider_execution_application_fixture = diagnostics_fixture('structured_edit_provider_execution_application')
    structured_edit_provider_execution_dispatch_fixture = diagnostics_fixture('structured_edit_provider_execution_dispatch')
    structured_edit_provider_execution_dispatch_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_dispatch_envelope')
    structured_edit_provider_execution_dispatch_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_dispatch_envelope_rejection')
    structured_edit_provider_execution_dispatch_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_dispatch_envelope_application')
    structured_edit_provider_execution_outcome_fixture = diagnostics_fixture('structured_edit_provider_execution_outcome')
    structured_edit_provider_execution_outcome_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_outcome_envelope')
    structured_edit_provider_execution_outcome_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_outcome_envelope_rejection')
    structured_edit_provider_execution_outcome_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_outcome_envelope_application')
    structured_edit_provider_batch_execution_outcome_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_outcome')
    structured_edit_provider_batch_execution_outcome_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_outcome_envelope')
    structured_edit_provider_batch_execution_outcome_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_outcome_envelope_rejection')
    structured_edit_provider_batch_execution_outcome_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_outcome_envelope_application')
    structured_edit_provider_execution_provenance_fixture = diagnostics_fixture('structured_edit_provider_execution_provenance')
    structured_edit_provider_execution_provenance_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_provenance_envelope')
    structured_edit_provider_execution_provenance_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_provenance_envelope_rejection')
    structured_edit_provider_execution_provenance_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_provenance_envelope_application')
    structured_edit_provider_batch_execution_provenance_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_provenance')
    structured_edit_provider_batch_execution_provenance_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_provenance_envelope')
    structured_edit_provider_batch_execution_provenance_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_provenance_envelope_rejection')
    structured_edit_provider_batch_execution_provenance_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_provenance_envelope_application')
    structured_edit_provider_execution_replay_bundle_fixture = diagnostics_fixture('structured_edit_provider_execution_replay_bundle')
    structured_edit_provider_execution_replay_bundle_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_replay_bundle_envelope')
    structured_edit_provider_execution_replay_bundle_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_replay_bundle_envelope_rejection')
    structured_edit_provider_execution_replay_bundle_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_replay_bundle_envelope_application')
    structured_edit_provider_batch_execution_replay_bundle_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_replay_bundle')
    structured_edit_provider_batch_execution_replay_bundle_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_replay_bundle_envelope')
    structured_edit_provider_batch_execution_replay_bundle_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_replay_bundle_envelope_rejection')
    structured_edit_provider_batch_execution_replay_bundle_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_replay_bundle_envelope_application')
    structured_edit_provider_executor_profile_fixture = diagnostics_fixture('structured_edit_provider_executor_profile')
    structured_edit_provider_executor_operation_triad_profile_fixture = diagnostics_fixture('structured_edit_provider_executor_operation_triad_profile')
    structured_edit_provider_executor_profile_envelope_fixture = diagnostics_fixture('structured_edit_provider_executor_profile_envelope')
    structured_edit_provider_executor_profile_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_executor_profile_envelope_rejection')
    structured_edit_provider_executor_profile_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_executor_profile_envelope_application')
    structured_edit_provider_executor_registry_fixture = diagnostics_fixture('structured_edit_provider_executor_registry')
    structured_edit_provider_executor_registry_envelope_fixture = diagnostics_fixture('structured_edit_provider_executor_registry_envelope')
    structured_edit_provider_executor_registry_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_executor_registry_envelope_rejection')
    structured_edit_provider_executor_registry_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_executor_registry_envelope_application')
    structured_edit_provider_executor_selection_policy_fixture = diagnostics_fixture('structured_edit_provider_executor_selection_policy')
    structured_edit_provider_executor_selection_policy_envelope_fixture = diagnostics_fixture('structured_edit_provider_executor_selection_policy_envelope')
    structured_edit_provider_executor_selection_policy_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_executor_selection_policy_envelope_rejection')
    structured_edit_provider_executor_selection_policy_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_executor_selection_policy_envelope_application')
    structured_edit_provider_executor_resolution_fixture = diagnostics_fixture('structured_edit_provider_executor_resolution')
    structured_edit_provider_executor_resolution_envelope_fixture = diagnostics_fixture('structured_edit_provider_executor_resolution_envelope')
    structured_edit_provider_executor_resolution_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_executor_resolution_envelope_rejection')
    structured_edit_provider_executor_resolution_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_executor_resolution_envelope_application')
    structured_edit_provider_execution_plan_fixture = diagnostics_fixture('structured_edit_provider_execution_plan')
    structured_edit_provider_execution_handoff_fixture = diagnostics_fixture('structured_edit_provider_execution_handoff')
    structured_edit_provider_execution_handoff_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_handoff_envelope')
    structured_edit_provider_execution_handoff_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_handoff_envelope_rejection')
    structured_edit_provider_execution_handoff_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_handoff_envelope_application')
    structured_edit_provider_execution_invocation_fixture = diagnostics_fixture('structured_edit_provider_execution_invocation')
    structured_edit_provider_execution_invocation_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_invocation_envelope')
    structured_edit_provider_execution_invocation_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_invocation_envelope_rejection')
    structured_edit_provider_execution_invocation_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_invocation_envelope_application')
    structured_edit_provider_batch_execution_invocation_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_invocation')
    structured_edit_provider_batch_execution_invocation_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_invocation_envelope')
    structured_edit_provider_batch_execution_invocation_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_invocation_envelope_rejection')
    structured_edit_provider_batch_execution_invocation_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_invocation_envelope_application')
    structured_edit_provider_execution_run_result_fixture = diagnostics_fixture('structured_edit_provider_execution_run_result')
    structured_edit_provider_execution_run_result_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_run_result_envelope')
    structured_edit_provider_execution_run_result_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_run_result_envelope_rejection')
    structured_edit_provider_execution_run_result_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_run_result_envelope_application')
    structured_edit_provider_batch_execution_run_result_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_run_result')
    structured_edit_provider_batch_execution_run_result_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_run_result_envelope')
    structured_edit_provider_batch_execution_run_result_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_run_result_envelope_rejection')
    structured_edit_provider_batch_execution_run_result_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_run_result_envelope_application')
    structured_edit_provider_execution_receipt_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt')
    structured_edit_provider_execution_receipt_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_envelope')
    structured_edit_provider_execution_receipt_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_envelope_rejection')
    structured_edit_provider_execution_receipt_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_envelope_application')
    structured_edit_provider_batch_execution_receipt_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt')
    structured_edit_provider_batch_execution_receipt_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_envelope')
    structured_edit_provider_batch_execution_receipt_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_envelope_application')
    structured_edit_provider_execution_receipt_replay_request_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_request')
    structured_edit_provider_execution_receipt_replay_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_request_envelope')
    structured_edit_provider_execution_receipt_replay_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_request_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_request_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_request_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_request')
    structured_edit_provider_batch_execution_receipt_replay_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_request_envelope')
    structured_edit_provider_batch_execution_receipt_replay_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_request_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_request_envelope_application')
    structured_edit_provider_execution_receipt_replay_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_application')
    structured_edit_provider_execution_receipt_replay_application_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_application_envelope')
    structured_edit_provider_execution_receipt_replay_application_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_application_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_application_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_application_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_application')
    structured_edit_provider_batch_execution_receipt_replay_application_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_application_envelope')
    structured_edit_provider_batch_execution_receipt_replay_application_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_application_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_application_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_application_envelope_application')
    structured_edit_provider_execution_receipt_replay_session_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_session')
    structured_edit_provider_execution_receipt_replay_session_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_session_envelope')
    structured_edit_provider_execution_receipt_replay_session_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_session_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_session_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_session_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_session_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_session')
    structured_edit_provider_batch_execution_receipt_replay_session_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_session_envelope')
    structured_edit_provider_batch_execution_receipt_replay_session_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_session_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_session_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_session_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow')
    structured_edit_provider_execution_receipt_replay_workflow_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow')
    structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_result_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_result')
    structured_edit_provider_execution_receipt_replay_workflow_result_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_result_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_result_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_result_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_result_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_result_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_review_request_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_review_request')
    structured_edit_provider_execution_receipt_replay_workflow_apply_request_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_request')
    structured_edit_provider_execution_receipt_replay_workflow_apply_session_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_session')
    structured_edit_provider_execution_receipt_replay_workflow_apply_result_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_result')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_audit_record_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_audit_record')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application')
    structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope')
    structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_rejection')
    structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_review_request')
    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_application')
    structured_edit_provider_batch_execution_receipt_replay_workflow_result_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_result')
    structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope')
    structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_rejection')
    structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_application')
    structured_edit_provider_batch_execution_handoff_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_handoff')
    structured_edit_provider_batch_execution_handoff_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_handoff_envelope')
    structured_edit_provider_batch_execution_handoff_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_handoff_envelope_rejection')
    structured_edit_provider_batch_execution_handoff_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_handoff_envelope_application')
    structured_edit_provider_execution_plan_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_plan_envelope')
    structured_edit_provider_execution_plan_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_plan_envelope_rejection')
    structured_edit_provider_execution_plan_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_plan_envelope_application')
    structured_edit_provider_batch_execution_plan_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_plan')
    structured_edit_provider_batch_execution_plan_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_plan_envelope')
    structured_edit_provider_batch_execution_plan_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_plan_envelope_rejection')
    structured_edit_provider_batch_execution_plan_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_plan_envelope_application')
    structured_edit_provider_execution_application_envelope_fixture = diagnostics_fixture('structured_edit_provider_execution_application_envelope')
    structured_edit_provider_execution_application_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_execution_application_envelope_rejection')
    structured_edit_provider_execution_application_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_execution_application_envelope_application')
    structured_edit_execution_report_envelope_fixture = diagnostics_fixture('structured_edit_execution_report_envelope')
    structured_edit_execution_report_envelope_rejection_fixture = diagnostics_fixture('structured_edit_execution_report_envelope_rejection')
    structured_edit_execution_report_envelope_application_fixture = diagnostics_fixture('structured_edit_execution_report_envelope_application')
    structured_edit_batch_request_fixture = diagnostics_fixture('structured_edit_batch_request')
    structured_edit_provider_batch_execution_request_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_request')
    structured_edit_provider_batch_execution_request_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_request_envelope')
    structured_edit_provider_batch_execution_request_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_request_envelope_rejection')
    structured_edit_provider_batch_execution_request_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_request_envelope_application')
    structured_edit_provider_batch_execution_dispatch_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_dispatch')
    structured_edit_provider_batch_execution_dispatch_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_dispatch_envelope')
    structured_edit_provider_batch_execution_dispatch_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_dispatch_envelope_rejection')
    structured_edit_provider_batch_execution_dispatch_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_dispatch_envelope_application')
    structured_edit_provider_batch_execution_report_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_report')
    structured_edit_provider_batch_execution_report_envelope_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_report_envelope')
    structured_edit_provider_batch_execution_report_envelope_rejection_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_report_envelope_rejection')
    structured_edit_provider_batch_execution_report_envelope_application_fixture = diagnostics_fixture('structured_edit_provider_batch_execution_report_envelope_application')
    structured_edit_batch_report_fixture = diagnostics_fixture('structured_edit_batch_report')
    structured_edit_batch_report_envelope_fixture = diagnostics_fixture('structured_edit_batch_report_envelope')
    structured_edit_batch_report_envelope_rejection_fixture = diagnostics_fixture('structured_edit_batch_report_envelope_rejection')
    structured_edit_batch_report_envelope_application_fixture = diagnostics_fixture('structured_edit_batch_report_envelope_application')
    projected_cases_fixture = diagnostics_fixture('projected_child_review_cases')

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
              if execution[:family] == 'markdown'
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: 'delegate_child_surface',
                  language_chain: %w[markdown typescript],
                  surface: {
                    surface_kind: 'fenced_code_block',
                    effective_language: 'typescript',
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: 'owned_region', address: '/code_fence/0' },
                    reconstruction_strategy: 'portable_write',
                    metadata: { family: 'typescript' }
                  }
                }
              else
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: 'delegate_child_surface',
                  language_chain: %w[ruby ruby],
                  surface: {
                    surface_kind: 'yard_example',
                    effective_language: 'ruby',
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: 'owned_region', address: '/yard_example/1' },
                    reconstruction_strategy: 'portable_write',
                    metadata: { family: 'ruby' }
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
    expect(json_ready(replay_nested_runs.map do |run|
      { execution_family: run[:execution][:family], result: run[:result] }
    end)).to eq(
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
              if execution[:family] == 'markdown'
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: 'delegate_child_surface',
                  language_chain: %w[markdown typescript],
                  surface: {
                    surface_kind: 'fenced_code_block',
                    effective_language: 'typescript',
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: 'owned_region', address: '/code_fence/0' },
                    reconstruction_strategy: 'portable_write',
                    metadata: { family: 'typescript' }
                  }
                }
              else
                {
                  operation_id: group[:child_operation_id],
                  parent_operation_id: group[:parent_operation_id],
                  requested_strategy: 'delegate_child_surface',
                  language_chain: %w[ruby ruby],
                  surface: {
                    surface_kind: 'yard_example',
                    effective_language: 'ruby',
                    address: group[:delegated_runtime_surface_path],
                    owner: { kind: 'owned_region', address: '/yard_example/1' },
                    reconstruction_strategy: 'portable_write',
                    metadata: { family: 'ruby' }
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
    expect(json_ready(review_state_nested_runs.map do |run|
      { execution_family: run[:execution][:family], result: run[:result] }
    end)).to eq(
      json_ready(reviewed_nested_execution_state_application_fixture[:expected_results])
    )

    replay_bundle_envelope_reviewed_nested_fixture = diagnostics_fixture('review_replay_bundle_envelope_reviewed_nested_execution_application')
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
    expect(json_ready(replay_bundle_envelope_nested_application[:results].map do |run|
      { execution_family: run[:execution][:family], result: run[:result] }
    end)).to eq(
      json_ready(replay_bundle_envelope_reviewed_nested_fixture[:expected_application][:results])
    )

    review_state_envelope_reviewed_nested_fixture = diagnostics_fixture('review_state_envelope_reviewed_nested_execution_application')
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
    expect(json_ready(review_state_envelope_nested_application[:results].map do |run|
      { execution_family: run[:execution][:family], result: run[:result] }
    end)).to eq(
      json_ready(review_state_envelope_reviewed_nested_fixture[:expected_application][:results])
    )

    replay_bundle_envelope_reviewed_nested_rejection_fixture = diagnostics_fixture('review_replay_bundle_envelope_reviewed_nested_execution_rejection')
    replay_bundle_envelope_reviewed_nested_rejection_fixture[:cases].each do |test_case|
      rejected_application = described_class.execute_review_replay_bundle_envelope_reviewed_nested_executions(
        test_case[:replay_bundle_envelope]
      ) do
        raise 'callbacks should not run for rejected replay bundle envelopes'
      end
      expect(json_ready(rejected_application)).to eq(json_ready(test_case[:expected_application]))
    end

    review_state_envelope_reviewed_nested_rejection_fixture = diagnostics_fixture('review_state_envelope_reviewed_nested_execution_rejection')
    review_state_envelope_reviewed_nested_rejection_fixture[:cases].each do |test_case|
      rejected_application = described_class.execute_review_state_envelope_reviewed_nested_executions(
        test_case[:review_state_envelope]
      ) do
        raise 'callbacks should not run for rejected review state envelopes'
      end
      expect(json_ready(rejected_application)).to eq(json_ready(test_case[:expected_application]))
    end

    reviewed_nested_manifest_application_fixture = diagnostics_fixture('review_replay_bundle_envelope_reviewed_nested_manifest_application')
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
    expect(json_ready(reviewed_nested_manifest_application[:results].map do |run|
      { execution_family: run[:execution][:family], result: run[:result] }
    end)).to eq(
      json_ready(reviewed_nested_manifest_application_fixture[:expected_application][:results])
    )

    reviewed_nested_manifest_rejection_fixture = diagnostics_fixture('review_replay_bundle_envelope_reviewed_nested_manifest_rejection')
    reviewed_nested_manifest_rejection_fixture[:cases].each do |test_case|
      rejected_application = described_class.review_and_execute_conformance_manifest_with_replay_bundle_envelope(
        reviewed_nested_manifest_rejection_fixture[:manifest],
        reviewed_nested_manifest_rejection_fixture[:options],
        test_case[:review_replay_bundle_envelope],
        execute: execute_from(reviewed_nested_manifest_rejection_fixture[:executions]),
        reviewed_nested_execution: lambda do
          raise 'callbacks should not run for rejected replay bundle envelopes'
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

    replay_bundle_envelope_application_fixture = diagnostics_fixture('review_replay_bundle_envelope_application')
    replay_bundle_envelope_applied = described_class.review_conformance_manifest_with_replay_bundle_envelope(
      replay_bundle_envelope_application_fixture[:manifest],
      replay_bundle_envelope_application_fixture[:options],
      replay_bundle_envelope_application_fixture[:review_replay_bundle_envelope],
      &execute_from(replay_bundle_envelope_application_fixture[:executions])
    )
    expect(json_ready(replay_bundle_envelope_applied)).to eq(
      json_ready(replay_bundle_envelope_application_fixture[:expected_state])
    )

    explicit_bundle_envelope_fixture = diagnostics_fixture('explicit_review_replay_bundle_envelope_application')
    explicit_envelope_applied = described_class.review_conformance_manifest_with_replay_bundle_envelope(
      explicit_bundle_envelope_fixture[:manifest],
      explicit_bundle_envelope_fixture[:options],
      explicit_bundle_envelope_fixture[:review_replay_bundle_envelope],
      &execute_from(explicit_bundle_envelope_fixture[:executions])
    )
    expect(json_ready(explicit_envelope_applied)).to eq(json_ready(explicit_bundle_envelope_fixture[:expected_state]))

    replay_bundle_envelope_rejection_fixture = diagnostics_fixture('review_replay_bundle_envelope_review_rejection')
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
        callable_destination: entry.dig(:request, :callable_destination),
        target_selection: entry.dig(:request, :target_selection),
        target_match: entry.dig(:request, :target_match),
        metadata: entry.dig(:request, :metadata)
      )
      expect(json_ready(request)).to eq(json_ready(entry[:request]))
    end

    structured_edit_callable_destination_request_fixture[:cases].each do |entry|
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
        callable_destination: entry.dig(:request, :callable_destination),
        target_selection: entry.dig(:request, :target_selection),
        target_match: entry.dig(:request, :target_match),
        metadata: entry.dig(:request, :metadata)
      )
      expect(json_ready(request)).to eq(json_ready(entry[:request]))
    end

    structured_edit_parity_selection_semantics_fixture[:cases].each do |entry|
      target_selection = described_class.structured_edit_target_selection(
        selector_kind: entry.dig(:request, :target_selection, :selector_kind),
        selection_intent: entry.dig(:request, :target_selection, :selection_intent),
        selection_intent_family: entry.dig(:request, :target_selection, :selection_intent_family),
        known_selection_intent: entry.dig(:request, :target_selection, :known_selection_intent),
        comment_region: entry.dig(:request, :target_selection, :comment_region),
        include_trailing_gap: entry.dig(:request, :target_selection, :include_trailing_gap),
        comment_anchored: entry.dig(:request, :target_selection, :comment_anchored),
        metadata: entry.dig(:request, :target_selection, :metadata)
      )
      request = described_class.structured_edit_request(
        operation_kind: entry.dig(:request, :operation_kind),
        content: entry.dig(:request, :content),
        source_label: entry.dig(:request, :source_label),
        target_selector: entry.dig(:request, :target_selector),
        target_selector_family: entry.dig(:request, :target_selector_family),
        target_selection: target_selection,
        payload_text: entry.dig(:request, :payload_text),
        metadata: entry.dig(:request, :metadata)
      )
      expect(json_ready(request)).to eq(json_ready(entry[:request]))
    end

    structured_edit_parity_match_semantics_fixture[:cases].each do |entry|
      target_match = described_class.structured_edit_target_match(
        start_boundary: entry.dig(:request, :target_match, :start_boundary),
        start_boundary_family: entry.dig(:request, :target_match, :start_boundary_family),
        known_start_boundary: entry.dig(:request, :target_match, :known_start_boundary),
        end_boundary: entry.dig(:request, :target_match, :end_boundary),
        end_boundary_family: entry.dig(:request, :target_match, :end_boundary_family),
        known_end_boundary: entry.dig(:request, :target_match, :known_end_boundary),
        payload_kind: entry.dig(:request, :target_match, :payload_kind),
        payload_family: entry.dig(:request, :target_match, :payload_family),
        known_payload_kind: entry.dig(:request, :target_match, :known_payload_kind),
        comment_anchored: entry.dig(:request, :target_match, :comment_anchored),
        trailing_gap_extended: entry.dig(:request, :target_match, :trailing_gap_extended),
        metadata: entry.dig(:request, :target_match, :metadata)
      )
      request = described_class.structured_edit_request(
        operation_kind: entry.dig(:request, :operation_kind),
        content: entry.dig(:request, :content),
        source_label: entry.dig(:request, :source_label),
        target_selector: entry.dig(:request, :target_selector),
        target_selector_family: entry.dig(:request, :target_selector_family),
        target_match: target_match,
        payload_text: entry.dig(:request, :payload_text),
        metadata: entry.dig(:request, :metadata)
      )
      expect(json_ready(request)).to eq(json_ready(entry[:request]))
    end

    expect(structured_edit_operation_triad_parity_fixture.dig(:metadata, :canonical_operation_kinds)).to eq(
      %w[insert replace delete]
    )
    expect(structured_edit_operation_triad_parity_fixture.dig(:metadata, :remove_alias_encoded)).to be(false)
    structured_edit_operation_triad_parity_fixture[:cases].each do |entry|
      request = described_class.structured_edit_request(
        operation_kind: entry.dig(:application, :request, :operation_kind),
        content: entry.dig(:application, :request, :content),
        source_label: entry.dig(:application, :request, :source_label),
        target_selector: entry.dig(:application, :request, :target_selector),
        target_selector_family: entry.dig(:application, :request, :target_selector_family),
        destination_selector: entry.dig(:application, :request, :destination_selector),
        destination_selector_family: entry.dig(:application, :request, :destination_selector_family),
        payload_text: entry.dig(:application, :request, :payload_text),
        if_missing: entry.dig(:application, :request, :if_missing),
        target_selection: entry.dig(:application, :request, :target_selection),
        target_match: entry.dig(:application, :request, :target_match),
        metadata: entry.dig(:application, :request, :metadata)
      )
      result = described_class.structured_edit_result(
        operation_kind: entry.dig(:application, :result, :operation_kind),
        updated_content: entry.dig(:application, :result, :updated_content),
        changed: entry.dig(:application, :result, :changed),
        captured_text: entry.dig(:application, :result, :captured_text),
        match_count: entry.dig(:application, :result, :match_count),
        operation_profile: entry.dig(:application, :result, :operation_profile),
        destination_profile: entry.dig(:application, :result, :destination_profile),
        metadata: entry.dig(:application, :result, :metadata)
      )
      application = described_class.structured_edit_application(
        request: request,
        result: result,
        metadata: entry.dig(:application, :metadata)
      )
      expect(json_ready(application)).to eq(json_ready(entry[:application]))
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

    structured_edit_request_envelope = described_class.structured_edit_request_envelope(
      structured_edit_request_envelope_fixture[:structured_edit_request]
    )
    expect(json_ready(structured_edit_request_envelope)).to eq(
      json_ready(structured_edit_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_request, structured_edit_request_error =
      described_class.import_structured_edit_request_envelope(
        structured_edit_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_request_error).to be_nil
    expect(json_ready(imported_structured_edit_request)).to eq(
      json_ready(structured_edit_request_envelope_fixture[:structured_edit_request])
    )

    structured_edit_request_envelope_rejection_fixture[:cases].each do |test_case|
      _request, import_error = described_class.import_structured_edit_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_request, applied_structured_edit_request_error =
      described_class.import_structured_edit_request_envelope(
        structured_edit_request_envelope_application_fixture[:structured_edit_request_envelope]
      )
    expect(applied_structured_edit_request_error).to be_nil
    expect(json_ready(applied_structured_edit_request)).to eq(
      json_ready(structured_edit_request_envelope_application_fixture[:expected_request])
    )

    structured_edit_request_envelope_application_fixture[:cases].each do |test_case|
      _request, request_rejection_error =
        described_class.import_structured_edit_request_envelope(test_case[:envelope])
      expect(json_ready(request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    profile_promotion_request_envelope = described_class.structured_edit_request_envelope(
      structured_edit_profile_promotion_envelope_fixture[:structured_edit_request],
      profile_id: structured_edit_profile_promotion_envelope_fixture.dig(:expected, :profile_id),
      minimum_profile_status: structured_edit_profile_promotion_envelope_fixture.dig(:expected,
                                                                                     :minimum_profile_status),
      promotion_policy_id: structured_edit_profile_promotion_envelope_fixture.dig(:expected, :promotion_policy_id)
    )
    expect(json_ready(profile_promotion_request_envelope)).to eq(
      json_ready(structured_edit_profile_promotion_envelope_fixture[:expected_request_envelope])
    )
    expect(json_ready(described_class.profile_selection_requirement_from_request_envelope(profile_promotion_request_envelope).to_h)).to eq(
      json_ready(structured_edit_profile_promotion_envelope_fixture[:profile_selection_requirement])
    )

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

    structured_edit_crispr_overmatch_fail_closed_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    expect(structured_edit_crispr_acceptance_scenario_fixture.dig(:metadata, :canonical_operation_kinds)).to eq(
      %w[insert replace delete]
    )
    expect(structured_edit_crispr_acceptance_scenario_fixture.dig(:metadata, :remove_alias_encoded)).to be(false)
    structured_edit_crispr_acceptance_scenario_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    structured_edit_crispr_append_fallback_insert_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    structured_edit_crispr_ruby_comment_owned_rewrite_delete_parity_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    structured_edit_crispr_ruby_callable_destination_move_parity_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    structured_edit_crispr_markdown_heading_section_replace_parity_fixture[:cases].each do |entry|
      report = described_class.structured_edit_execution_report(
        application: entry.dig(:report, :application),
        provider_family: entry.dig(:report, :provider_family),
        provider_backend: entry.dig(:report, :provider_backend),
        diagnostics: entry.dig(:report, :diagnostics),
        metadata: entry.dig(:report, :metadata)
      )
      expect(json_ready(report)).to eq(json_ready(entry[:report]))
    end

    crispr_example_parity_report = described_class.structured_edit_crispr_example_parity_report(
      scenarios: structured_edit_crispr_example_parity_report_fixture.dig(:report, :scenarios),
      remaining_gaps: structured_edit_crispr_example_parity_report_fixture.dig(:report, :remaining_gaps),
      metadata: structured_edit_crispr_example_parity_report_fixture.dig(:report, :metadata)
    )
    expect(json_ready(crispr_example_parity_report)).to eq(
      json_ready(structured_edit_crispr_example_parity_report_fixture[:report])
    )

    crispr_parity_substrate_report = described_class.structured_edit_crispr_example_parity_report(
      scenarios: structured_edit_crispr_parity_substrate_report_fixture.dig(:report, :scenarios),
      remaining_gaps: structured_edit_crispr_parity_substrate_report_fixture.dig(:report, :remaining_gaps),
      metadata: structured_edit_crispr_parity_substrate_report_fixture.dig(:report, :metadata)
    )
    expect(json_ready(crispr_parity_substrate_report)).to eq(
      json_ready(structured_edit_crispr_parity_substrate_report_fixture[:report])
    )

    kettle_jem_primitive_gap_report = described_class.structured_edit_kettle_jem_primitive_gap_report(
      reference_project: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :reference_project),
      scope: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :scope),
      product_target: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :product_target),
      current_substrate: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :current_substrate),
      required_primitives: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :required_primitives),
      script_classifications: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report,
                                                                                          :script_classifications),
      non_goals: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :non_goals),
      next_slices: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :next_slices),
      metadata: structured_edit_kettle_jem_primitive_gap_report_fixture.dig(:report, :metadata)
    )
    expect(json_ready(kettle_jem_primitive_gap_report)).to eq(
      json_ready(structured_edit_kettle_jem_primitive_gap_report_fixture[:report])
    )

    content_recipe_execution_envelope_fixture[:cases].each do |entry|
      request = content_recipe_execution_request(
        recipe_name: entry.dig(:request_envelope, :request, :recipe_name),
        recipe_version: entry.dig(:request_envelope, :request, :recipe_version),
        relative_path: entry.dig(:request_envelope, :request, :relative_path),
        provider_family: entry.dig(:request_envelope, :request, :provider_family),
        provider_backend: entry.dig(:request_envelope, :request, :provider_backend),
        template_content: entry.dig(:request_envelope, :request, :template_content),
        destination_content: entry.dig(:request_envelope, :request, :destination_content),
        steps: entry.dig(:request_envelope, :request, :steps),
        runtime_context: entry.dig(:request_envelope, :request, :runtime_context),
        metadata: entry.dig(:request_envelope, :request, :metadata)
      )
      expect(json_ready(content_recipe_execution_request_envelope(request))).to eq(
        json_ready(entry[:request_envelope])
      )

      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    single_file_readme_heading_section_acceptance_fixture[:cases].each do |entry|
      request = content_recipe_execution_request(
        recipe_name: entry.dig(:request_envelope, :request, :recipe_name),
        recipe_version: entry.dig(:request_envelope, :request, :recipe_version),
        relative_path: entry.dig(:request_envelope, :request, :relative_path),
        provider_family: entry.dig(:request_envelope, :request, :provider_family),
        provider_backend: entry.dig(:request_envelope, :request, :provider_backend),
        template_content: entry.dig(:request_envelope, :request, :template_content),
        destination_content: entry.dig(:request_envelope, :request, :destination_content),
        steps: entry.dig(:request_envelope, :request, :steps),
        runtime_context: entry.dig(:request_envelope, :request, :runtime_context),
        metadata: entry.dig(:request_envelope, :request, :metadata)
      )
      expect(json_ready(content_recipe_execution_request_envelope(request))).to eq(
        json_ready(entry[:request_envelope])
      )

      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    native_structured_edit_recipe_steps_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    ruby_gemfile_signature_merge_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    expect(ruby_gemspec_native_boundary_report_fixture[:kind]).to eq('ruby_gemspec_native_boundary_report')
    expect(ruby_gemspec_native_boundary_report_fixture.dig(:native_recipe_surface, :signature_profile)).to eq(
      'gemspec_declarations'
    )
    expect(ruby_gemspec_native_boundary_report_fixture[:wrapper_required_behaviors].map do |entry|
      entry[:name]
    end).to include(
      'dependency_ruby_floor_comment_alignment'
    )
    request = content_recipe_execution_request(
      recipe_name: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request, :recipe_name),
      recipe_version: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request,
                                                                      :recipe_version),
      relative_path: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request, :relative_path),
      provider_family: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request,
                                                                       :provider_family),
      provider_backend: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request,
                                                                        :provider_backend),
      template_content: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request,
                                                                        :template_content),
      destination_content: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request,
                                                                           :destination_content),
      steps: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request, :steps),
      runtime_context: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request,
                                                                       :runtime_context),
      metadata: ruby_gemspec_native_boundary_report_fixture.dig(:example_native_recipe, :request, :metadata)
    )
    expect(json_ready(content_recipe_execution_request_envelope(request))).to eq(
      json_ready(ruby_gemspec_native_boundary_report_fixture[:example_native_recipe])
    )

    ruby_gemspec_signature_merge_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    ruby_gemspec_field_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    ruby_gemspec_dependency_section_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    ruby_gemspec_files_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    ruby_gemspec_version_loader_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
    end

    runtime_facts_context_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
      expect(entry.dig(:report_envelope, :report, :request, :runtime_context, :facts, :schema)).to eq(
        'runtime_facts.v1'
      )
    end

    ruby_gemspec_self_dependency_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
      next unless entry[:label] == 'delete-active-self-dependencies-preserve-comments'

      expect(entry.dig(:report_envelope, :report,
                       :final_content)).not_to include('spec.add_dependency "demo", "~> 1.0"')
      expect(entry.dig(:report_envelope, :report, :final_content)).to include('# spec.add_dependency "demo", "~> 0"')
    end

    ruby_gemfile_self_dependency_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
      if entry[:label] == 'delete-gemfile-self-dependencies-across-nesting'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).not_to include('gem "demo", "~> 1.0"')
        expect(final_content).not_to include('path: "../dev/demo"')
        expect(final_content).to include('# gem "demo", "~> 0"')
        expect(final_content).to include('gem "fallback-gem"')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :operation)).to eq('delete')
      end
      if entry[:label] == 'missing-project-identity-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    ruby_appraisals_self_dependency_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
      if entry[:label] == 'delete-appraisals-self-dependencies'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).not_to include('gem "demo"')
        expect(final_content).to include('appraise("rails-6")')
        expect(final_content).to include('gem "rspec" # Testing')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :operation)).to eq('delete')
      end
      if entry[:label] == 'missing-project-identity-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    ruby_appraisals_min_ruby_prune_policy_acceptance_fixture[:cases].each do |entry|
      report = content_recipe_execution_report(
        request: entry.dig(:report_envelope, :report, :request),
        final_content: entry.dig(:report_envelope, :report, :final_content),
        changed: entry.dig(:report_envelope, :report, :changed),
        step_reports: entry.dig(:report_envelope, :report, :step_reports),
        diagnostics: entry.dig(:report_envelope, :report, :diagnostics),
        metadata: entry.dig(:report_envelope, :report, :metadata)
      )
      expect(json_ready(content_recipe_execution_report_envelope(report))).to eq(
        json_ready(entry[:report_envelope])
      )
      if entry[:label] == 'delete-ruby-appraisals-below-min-ruby'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).not_to include('ruby-2-3')
        expect(final_content).not_to include('ruby-2-7')
        expect(final_content).not_to include('ruby-3-0')
        expect(final_content).to include('ruby-3-2')
        expect(final_content).to include('appraise "style"')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :operation)).to eq('delete')
        expect(final_content).not_to include("\n\n\n")
      end
      if entry[:label] == 'missing-min-ruby-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    changelog_unreleased_normalization_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'create-unreleased-section-from-supplied-entries'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content.index('## Unreleased')).to be < final_content.index('## 1.2.0')
        expect(final_content).to include('- Added native Markdown recipe boundary.')
        expect(final_content).to include('- Existing release.')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata,
                         :operation)).to eq('insert_or_replace_section')
      end
      if entry[:label] == 'missing-entries-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    readme_supplied_metadata_synchronization_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'sync-readme-heading-and-summary-from-supplied-metadata'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).to start_with("# Demo Toolkit\n")
        expect(final_content).to include('A deterministic toolkit for structured merges.')
        expect(final_content).to include('Destination usage.')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata,
                         :consumed_context)).to eq('readme_metadata.title')
        expect(entry.dig(:report_envelope, :report, :step_reports, 1, :metadata,
                         :consumed_context)).to eq('readme_metadata.summary')
      end
      if entry[:label] == 'missing-readme-metadata-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    supplied_markdown_pruning_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'prune-supplied-table-rows-and-reference-definitions'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).not_to include('Works with JRuby')
        expect(final_content).not_to include('[jruby-9.4]:')
        expect(final_content).not_to include('[jruby-head]:')
        expect(final_content).to include('Works with MRI Ruby')
        expect(final_content).to include('[ruby-3.2]:')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :deleted_rows)).to eq(1)
        expect(entry.dig(:report_envelope, :report, :step_reports, 1, :metadata,
                         :deleted_reference_definitions)).to eq(2)
      end
      if entry[:label] == 'missing-prune-selectors-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    supplied_source_selector_deletion_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'delete-supplied-structural-owner-ranges'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).not_to include('kettle/scaffold')
        expect(final_content).not_to include('task :scaffold')
        expect(final_content).to include('require "bundler/gem_tasks"')
        expect(final_content).to include('task :spec')
        expect(final_content).not_to include("\n\n\n")
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :deleted_ranges)).to eq(2)
      end
      if entry[:label] == 'missing-delete-selectors-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    supplied_yaml_snippet_synchronization_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'apply-supplied-sections-and-scalar-pins'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).to include('concurrency:')
        expect(final_content).to include('permissions:')
        expect(final_content).to include('actions/checkout@1111111111111111111111111111111111111111')
        expect(final_content).to include('ruby/setup-ruby@2222222222222222222222222222222222222222')
        expect(final_content).not_to include('actions/checkout@v3')
        expect(final_content).not_to include('ruby/setup-ruby@v1')
        expect(final_content).to include('gemfiles/current.gemfile')
        expect(final_content).to include('ruby-version: ${{ matrix.ruby }}')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :updated_sections)).to eq(2)
        expect(entry.dig(:report_envelope, :report, :step_reports, 1, :metadata, :updated_scalars)).to eq(2)
      end
      if entry[:label] == 'missing-yaml-updates-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    supplied_managed_text_block_replacement_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'replace-existing-managed-text-block'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).to include('gem "debug", "~> 1.9"')
        expect(final_content).to include('gem "irb", "~> 1.15"')
        expect(final_content).not_to include('old-debug')
        expect(final_content).to include('gem "rake"')
        expect(final_content).to include('gem "rspec"')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :replaced_blocks)).to eq(1)
      end
      if entry[:label] == 'append-missing-managed-text-block'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).to include('# <<kettle-jem:generated>>')
        expect(final_content).to include('# (no shunted dependencies)')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :appended_blocks)).to eq(1)
      end
      if entry[:label] == 'missing-managed-block-updates-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
    end

    supplied_yaml_placeholder_scalar_backfill_acceptance_fixture[:cases].each do |entry|
      if entry[:label] == 'backfill-placeholder-and-blank-scalars'
        final_content = entry.dig(:report_envelope, :report, :final_content)
        expect(final_content).to include('name: "demo-toolkit"')
        expect(final_content).to include("namespace: 'Demo::Toolkit'")
        expect(final_content).to include('homepage: "https://example.invalid/existing"')
        expect(final_content).to include('# ENV: KJ_GEM_NAME')
        expect(final_content).to include('# keep concrete value')
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :updated_scalars)).to eq(2)
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :metadata, :preserved_scalars)).to eq(1)
      end
      if entry[:label] == 'missing-yaml-scalar-backfills-fails-closed'
        expect(entry.dig(:report_envelope, :report, :step_reports, 0, :status)).to eq('failed')
      end
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

    expect(structured_edit_provider_executor_operation_triad_profile_fixture.dig(:metadata,
                                                                                 :canonical_operation_kinds)).to eq(
                                                                                   %w[insert replace delete]
                                                                                 )
    expect(structured_edit_provider_executor_operation_triad_profile_fixture.dig(:metadata,
                                                                                 :remove_alias_encoded)).to be(false)
    structured_edit_provider_executor_operation_triad_profile_fixture[:cases].each do |entry|
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

    structured_edit_provider_execution_receipt_replay_application_fixture[:cases].each do |entry|
      receipt_replay_application = described_class.structured_edit_provider_execution_receipt_replay_application(
        receipt_replay_request: entry.dig(:receipt_replay_application, :receipt_replay_request),
        run_result: entry.dig(:receipt_replay_application, :run_result),
        metadata: entry.dig(:receipt_replay_application, :metadata)
      )
      expect(json_ready(receipt_replay_application)).to eq(json_ready(entry[:receipt_replay_application]))
    end

    structured_edit_provider_execution_receipt_replay_application_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_application_envelope(
        structured_edit_provider_execution_receipt_replay_application_envelope_fixture[:structured_edit_provider_execution_receipt_replay_application]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_application_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_application_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_application, structured_edit_provider_execution_receipt_replay_application_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_application_envelope(
        structured_edit_provider_execution_receipt_replay_application_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_application_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_application)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_application_envelope_fixture[:structured_edit_provider_execution_receipt_replay_application])
    )

    structured_edit_provider_execution_receipt_replay_application_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_application, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_application_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_application, applied_structured_edit_provider_execution_receipt_replay_application_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_application_envelope(
        structured_edit_provider_execution_receipt_replay_application_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_application_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_application_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_application)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_application_envelope_application_fixture[:expected_receipt_replay_application])
    )

    structured_edit_provider_execution_receipt_replay_application_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_application, receipt_replay_application_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_application_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_application_fixture[:cases].each do |entry|
      batch_receipt_replay_application = described_class.structured_edit_provider_batch_execution_receipt_replay_application(
        applications: entry.dig(:batch_receipt_replay_application, :applications),
        metadata: entry.dig(:batch_receipt_replay_application, :metadata)
      )
      expect(json_ready(batch_receipt_replay_application)).to eq(json_ready(entry[:batch_receipt_replay_application]))
    end

    structured_edit_provider_batch_execution_receipt_replay_application_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_application_envelope(
        structured_edit_provider_batch_execution_receipt_replay_application_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_application]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_application_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_application_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_application, structured_edit_provider_batch_execution_receipt_replay_application_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_application_envelope(
        structured_edit_provider_batch_execution_receipt_replay_application_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_application_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_application)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_application_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_application])
    )

    structured_edit_provider_batch_execution_receipt_replay_application_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_application, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_application_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_application, applied_structured_edit_provider_batch_execution_receipt_replay_application_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_application_envelope(
        structured_edit_provider_batch_execution_receipt_replay_application_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_application_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_application_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_application)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_application_envelope_application_fixture[:expected_batch_receipt_replay_application])
    )

    structured_edit_provider_batch_execution_receipt_replay_application_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_application, batch_receipt_replay_application_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_application_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_session_fixture[:cases].each do |entry|
      receipt_replay_session = described_class.structured_edit_provider_execution_receipt_replay_session(
        receipt_replay_application: entry.dig(:receipt_replay_session, :receipt_replay_application),
        execution_receipt: entry.dig(:receipt_replay_session, :execution_receipt),
        metadata: entry.dig(:receipt_replay_session, :metadata)
      )
      expect(json_ready(receipt_replay_session)).to eq(json_ready(entry[:receipt_replay_session]))
    end

    structured_edit_provider_execution_receipt_replay_session_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_session_envelope(
        structured_edit_provider_execution_receipt_replay_session_envelope_fixture[:structured_edit_provider_execution_receipt_replay_session]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_session_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_session_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_session, structured_edit_provider_execution_receipt_replay_session_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_session_envelope(
        structured_edit_provider_execution_receipt_replay_session_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_session_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_session)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_session_envelope_fixture[:structured_edit_provider_execution_receipt_replay_session])
    )

    structured_edit_provider_execution_receipt_replay_session_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_session, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_session_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_session, applied_structured_edit_provider_execution_receipt_replay_session_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_session_envelope(
        structured_edit_provider_execution_receipt_replay_session_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_session_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_session_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_session)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_session_envelope_application_fixture[:expected_receipt_replay_session])
    )

    structured_edit_provider_execution_receipt_replay_session_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_session, receipt_replay_session_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_session_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_session_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_session_fixture[:cases].each do |entry|
      batch_receipt_replay_session = described_class.structured_edit_provider_batch_execution_receipt_replay_session(
        sessions: entry.dig(:batch_receipt_replay_session, :sessions),
        metadata: entry.dig(:batch_receipt_replay_session, :metadata)
      )
      expect(json_ready(batch_receipt_replay_session)).to eq(json_ready(entry[:batch_receipt_replay_session]))
    end

    structured_edit_provider_batch_execution_receipt_replay_session_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_session_envelope(
        structured_edit_provider_batch_execution_receipt_replay_session_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_session]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_session_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_session_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_session, structured_edit_provider_batch_execution_receipt_replay_session_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_session_envelope(
        structured_edit_provider_batch_execution_receipt_replay_session_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_session_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_session)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_session_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_session])
    )

    structured_edit_provider_batch_execution_receipt_replay_session_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_session, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_session_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_session, applied_structured_edit_provider_batch_execution_receipt_replay_session_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_session_envelope(
        structured_edit_provider_batch_execution_receipt_replay_session_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_session_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_session_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_session)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_session_envelope_application_fixture[:expected_batch_receipt_replay_session])
    )

    structured_edit_provider_batch_execution_receipt_replay_session_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_session, batch_receipt_replay_session_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_session_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_session_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_fixture[:cases].each do |entry|
      receipt_replay_workflow = described_class.structured_edit_provider_execution_receipt_replay_workflow(
        receipt_replay_session: entry.dig(:receipt_replay_workflow, :receipt_replay_session),
        metadata: entry.dig(:receipt_replay_workflow, :metadata)
      )
      expect(json_ready(receipt_replay_workflow)).to eq(json_ready(entry[:receipt_replay_workflow]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow, structured_edit_provider_execution_receipt_replay_workflow_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow])
    )

    structured_edit_provider_execution_receipt_replay_workflow_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_workflow, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow, applied_structured_edit_provider_execution_receipt_replay_workflow_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_envelope_application_fixture[:expected_receipt_replay_workflow])
    )

    structured_edit_provider_execution_receipt_replay_workflow_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_workflow, receipt_replay_workflow_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_workflow_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow = described_class.structured_edit_provider_batch_execution_receipt_replay_workflow(
        workflows: entry.dig(:batch_receipt_replay_workflow, :workflows),
        metadata: entry.dig(:batch_receipt_replay_workflow, :metadata)
      )
      expect(json_ready(batch_receipt_replay_workflow)).to eq(json_ready(entry[:batch_receipt_replay_workflow]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow, structured_edit_provider_batch_execution_receipt_replay_workflow_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_application_fixture[:expected_batch_receipt_replay_workflow])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow, batch_receipt_replay_workflow_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_workflow_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_result_fixture[:cases].each do |entry|
      receipt_replay_workflow_result =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_result(
          receipt_replay_workflow: entry.dig(:receipt_replay_workflow_result, :receipt_replay_workflow),
          receipt_replay_application: entry.dig(:receipt_replay_workflow_result, :receipt_replay_application),
          metadata: entry.dig(:receipt_replay_workflow_result, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_result)).to eq(json_ready(entry[:receipt_replay_workflow_result]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_result_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_result_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_result_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_result]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_result_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_result_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_result, structured_edit_provider_execution_receipt_replay_workflow_result_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_result_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_result_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_result_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_result)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_result_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_result])
    )

    structured_edit_provider_execution_receipt_replay_workflow_result_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_result, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_result, applied_structured_edit_provider_execution_receipt_replay_workflow_result_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_result_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_result_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_result_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_result_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_result)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_result_envelope_application_fixture[:expected_receipt_replay_workflow_result])
    )

    structured_edit_provider_execution_receipt_replay_workflow_result_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_result, receipt_replay_workflow_result_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_result_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_workflow_result_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_review_request_fixture[:cases].each do |entry|
      receipt_replay_workflow_review_request =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_review_request(
          receipt_replay_workflow_result: entry.dig(:receipt_replay_workflow_review_request,
                                                    :receipt_replay_workflow_result),
          metadata: entry.dig(:receipt_replay_workflow_review_request, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_review_request)).to eq(
        json_ready(entry[:receipt_replay_workflow_review_request])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_request_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_request =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_request(
          receipt_replay_workflow_review_request: entry.dig(:receipt_replay_workflow_apply_request,
                                                            :receipt_replay_workflow_review_request),
          metadata: entry.dig(:receipt_replay_workflow_apply_request, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_request)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_request])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_session_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_session =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_session(
          receipt_replay_workflow_apply_request: entry.dig(:receipt_replay_workflow_apply_session,
                                                           :receipt_replay_workflow_apply_request),
          receipt_replay_session: entry.dig(:receipt_replay_workflow_apply_session, :receipt_replay_session),
          metadata: entry.dig(:receipt_replay_workflow_apply_session, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_session)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_session])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_result_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_result =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_result(
          receipt_replay_workflow_apply_session: entry.dig(:receipt_replay_workflow_apply_result,
                                                           :receipt_replay_workflow_apply_session),
          receipt_replay_workflow_result: entry.dig(:receipt_replay_workflow_apply_result,
                                                    :receipt_replay_workflow_result),
          metadata: entry.dig(:receipt_replay_workflow_apply_result, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_result)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_result])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_decision =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision(
          receipt_replay_workflow_apply_result: entry.dig(:receipt_replay_workflow_apply_decision,
                                                          :receipt_replay_workflow_apply_result),
          decision: entry.dig(:receipt_replay_workflow_apply_decision, :decision),
          metadata: entry.dig(:receipt_replay_workflow_apply_decision, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_decision)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_decision])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_decision_outcome =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome(
          receipt_replay_workflow_apply_decision: entry.dig(:receipt_replay_workflow_apply_decision_outcome,
                                                            :receipt_replay_workflow_apply_decision),
          outcome: entry.dig(:receipt_replay_workflow_apply_decision_outcome, :outcome),
          metadata: entry.dig(:receipt_replay_workflow_apply_decision_outcome, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_decision_outcome)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_decision_outcome])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_decision_settlement =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement(
          receipt_replay_workflow_apply_decision_outcome: entry.dig(:receipt_replay_workflow_apply_decision_settlement,
                                                                    :receipt_replay_workflow_apply_decision_outcome),
          settlement: entry.dig(:receipt_replay_workflow_apply_decision_settlement, :settlement),
          metadata: entry.dig(:receipt_replay_workflow_apply_decision_settlement, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_decision_settlement)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_decision_settlement])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_decision_confirmation =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation(
          receipt_replay_workflow_apply_decision_settlement: entry.dig(
            :receipt_replay_workflow_apply_decision_confirmation, :receipt_replay_workflow_apply_decision_settlement
          ),
          confirmation: entry.dig(:receipt_replay_workflow_apply_decision_confirmation, :confirmation),
          metadata: entry.dig(:receipt_replay_workflow_apply_decision_confirmation, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_decision_confirmation)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_decision_confirmation])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_decision_closure_report =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report(
          receipt_replay_workflow_apply_decision_confirmation: entry.dig(
            :receipt_replay_workflow_apply_decision_closure_report, :receipt_replay_workflow_apply_decision_confirmation
          ),
          closure_report: entry.dig(:receipt_replay_workflow_apply_decision_closure_report, :closure_report),
          metadata: entry.dig(:receipt_replay_workflow_apply_decision_closure_report, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_decision_closure_report)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_decision_closure_report])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_audit_record_fixture[:cases].each do |entry|
      receipt_replay_workflow_apply_decision_audit_record =
        described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_audit_record(
          receipt_replay_workflow_apply_decision_closure_report: entry.dig(
            :receipt_replay_workflow_apply_decision_audit_record, :receipt_replay_workflow_apply_decision_closure_report
          ),
          audit_record: entry.dig(:receipt_replay_workflow_apply_decision_audit_record, :audit_record),
          metadata: entry.dig(:receipt_replay_workflow_apply_decision_audit_record, :metadata)
        )
      expect(json_ready(receipt_replay_workflow_apply_decision_audit_record)).to eq(
        json_ready(entry[:receipt_replay_workflow_apply_decision_audit_record])
      )
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation, structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_rejection_fixture[:cases].each do |test_case|
      _apply_decision_confirmation, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture[:expected_receipt_replay_workflow_apply_decision_confirmation])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture[:cases].each do |test_case|
      _apply_decision_confirmation, application_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report, structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_rejection_fixture[:cases].each do |test_case|
      _apply_decision_closure_report, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture[:expected_receipt_replay_workflow_apply_decision_closure_report])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture[:cases].each do |test_case|
      _apply_decision_closure_report, application_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement, structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_rejection_fixture[:cases].each do |test_case|
      _apply_decision_settlement, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture[:expected_receipt_replay_workflow_apply_decision_settlement])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture[:cases].each do |test_case|
      _apply_decision_settlement, application_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_settlement_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome, structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_rejection_fixture[:cases].each do |test_case|
      _apply_decision_outcome, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture[:expected_receipt_replay_workflow_apply_decision_outcome])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture[:cases].each do |test_case|
      _apply_decision_outcome, application_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_outcome_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision, structured_edit_provider_execution_receipt_replay_workflow_apply_decision_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_decision)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_rejection_fixture[:cases].each do |test_case|
      _apply_decision, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_decision)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture[:expected_receipt_replay_workflow_apply_decision])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture[:cases].each do |test_case|
      _apply_decision, application_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_decision_envelope(test_case[:envelope])
      expect(json_ready(application_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_result]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_result, structured_edit_provider_execution_receipt_replay_workflow_apply_result_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_result_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_result)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_result])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_apply_result, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_result, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_result_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_result_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_result)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_application_fixture[:expected_receipt_replay_workflow_apply_result])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_apply_result, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_session]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_session, structured_edit_provider_execution_receipt_replay_workflow_apply_session_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_session_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_session)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_session])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_apply_session, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_session, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_session_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_session_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_session)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_application_fixture[:expected_receipt_replay_workflow_apply_session])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_apply_session, receipt_replay_workflow_apply_session_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_session_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_workflow_apply_session_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_request]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_apply_request, structured_edit_provider_execution_receipt_replay_workflow_apply_request_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_apply_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_apply_request)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_request])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_apply_request, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_apply_request, applied_structured_edit_provider_execution_receipt_replay_workflow_apply_request_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_apply_request)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_application_fixture[:expected_receipt_replay_workflow_apply_request])
    )

    structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_apply_request, receipt_replay_workflow_apply_request_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_apply_request_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_workflow_apply_request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_request =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request(
          apply_requests: entry.dig(:batch_receipt_replay_workflow_apply_request, :apply_requests),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_request, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_request)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_request])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_session =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session(
          apply_sessions: entry.dig(:batch_receipt_replay_workflow_apply_session, :apply_sessions),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_session, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_session)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_session])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_result =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result(
          apply_results: entry.dig(:batch_receipt_replay_workflow_apply_result, :apply_results),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_result, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_result)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_result])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_decision =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision(
          apply_decisions: entry.dig(:batch_receipt_replay_workflow_apply_decision, :apply_decisions),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_decision, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_decision)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_decision])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_decision_outcome =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome(
          apply_decision_outcomes: entry.dig(:batch_receipt_replay_workflow_apply_decision_outcome,
                                             :apply_decision_outcomes),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_decision_outcome, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_decision_outcome)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_decision_outcome])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_request, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_request])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_request, batch_receipt_replay_workflow_apply_request_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_request_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_workflow_apply_request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_session, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_session])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_session, batch_receipt_replay_workflow_apply_session_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_session_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_workflow_apply_session_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_result, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_result])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_result, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_decision])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_outcome, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_decision_outcome])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_outcome, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_outcome_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_decision_settlement =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement(
          apply_decision_settlements: entry.dig(:batch_receipt_replay_workflow_apply_decision_settlement,
                                                :apply_decision_settlements),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_decision_settlement, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_decision_settlement)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_decision_settlement])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_settlement, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_decision_settlement])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_settlement, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_settlement_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_decision_confirmation =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation(
          apply_decision_confirmations: entry.dig(:batch_receipt_replay_workflow_apply_decision_confirmation,
                                                  :apply_decision_confirmations),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_decision_confirmation, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_decision_confirmation)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_decision_confirmation])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_apply_decision_closure_report =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report(
          closure_reports: entry.dig(:batch_receipt_replay_workflow_apply_decision_closure_report, :closure_reports),
          metadata: entry.dig(:batch_receipt_replay_workflow_apply_decision_closure_report, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_apply_decision_closure_report)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_apply_decision_closure_report])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:batch_receipt_replay_workflow_apply_decision_confirmation]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_fixture[:batch_receipt_replay_workflow_apply_decision_confirmation])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_confirmation, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture[:batch_receipt_replay_workflow_apply_decision_confirmation_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_decision_confirmation])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_confirmation, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_confirmation_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:batch_receipt_replay_workflow_apply_decision_closure_report]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report, structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_fixture[:batch_receipt_replay_workflow_apply_decision_closure_report])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_closure_report, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture[:batch_receipt_replay_workflow_apply_decision_closure_report_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture[:expected_batch_receipt_replay_workflow_apply_decision_closure_report])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_apply_decision_closure_report, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_apply_decision_closure_report_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope =
      described_class.structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_review_request]
      )
    expect(json_ready(structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_execution_receipt_replay_workflow_review_request, structured_edit_provider_execution_receipt_replay_workflow_review_request_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_execution_receipt_replay_workflow_review_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_execution_receipt_replay_workflow_review_request)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_fixture[:structured_edit_provider_execution_receipt_replay_workflow_review_request])
    )

    structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_rejection_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_review_request, import_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_execution_receipt_replay_workflow_review_request, applied_structured_edit_provider_execution_receipt_replay_workflow_review_request_error =
      described_class.import_structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(
        structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_application_fixture[:structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope]
      )
    expect(applied_structured_edit_provider_execution_receipt_replay_workflow_review_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_execution_receipt_replay_workflow_review_request)).to eq(
      json_ready(structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_application_fixture[:expected_receipt_replay_workflow_review_request])
    )

    structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope_application_fixture[:cases].each do |test_case|
      _receipt_replay_workflow_review_request, receipt_replay_workflow_review_request_rejection_error =
        described_class.import_structured_edit_provider_execution_receipt_replay_workflow_review_request_envelope(test_case[:envelope])
      expect(json_ready(receipt_replay_workflow_review_request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_review_request =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_review_request(
          review_requests: entry.dig(:batch_receipt_replay_workflow_review_request, :review_requests),
          metadata: entry.dig(:batch_receipt_replay_workflow_review_request, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_review_request)).to eq(
        json_ready(entry[:batch_receipt_replay_workflow_review_request])
      )
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_review_request]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request, structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_review_request])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_review_request, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_application_fixture[:expected_batch_receipt_replay_workflow_review_request])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_review_request, batch_receipt_replay_workflow_review_request_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_review_request_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_workflow_review_request_rejection_error)).to eq(json_ready(test_case[:expected_error]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_result_fixture[:cases].each do |entry|
      batch_receipt_replay_workflow_result =
        described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_result(
          receipt_replay_workflow_results: entry.dig(:batch_receipt_replay_workflow_result,
                                                     :receipt_replay_workflow_results),
          metadata: entry.dig(:batch_receipt_replay_workflow_result, :metadata)
        )
      expect(json_ready(batch_receipt_replay_workflow_result)).to eq(json_ready(entry[:batch_receipt_replay_workflow_result]))
    end

    structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope =
      described_class.structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_result]
      )
    expect(json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_fixture[:expected_envelope])
    )

    imported_structured_edit_provider_batch_execution_receipt_replay_workflow_result, structured_edit_provider_batch_execution_receipt_replay_workflow_result_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_fixture[:expected_envelope]
      )
    expect(structured_edit_provider_batch_execution_receipt_replay_workflow_result_error).to be_nil
    expect(json_ready(imported_structured_edit_provider_batch_execution_receipt_replay_workflow_result)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_result])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_rejection_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_result, import_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(test_case[:envelope])
      expect(json_ready(import_error)).to eq(json_ready(test_case[:expected_error]))
    end

    applied_structured_edit_provider_batch_execution_receipt_replay_workflow_result, applied_structured_edit_provider_batch_execution_receipt_replay_workflow_result_error =
      described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(
        structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_application_fixture[:structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope]
      )
    expect(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_result_error).to be_nil
    expect(json_ready(applied_structured_edit_provider_batch_execution_receipt_replay_workflow_result)).to eq(
      json_ready(structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_application_fixture[:expected_batch_receipt_replay_workflow_result])
    )

    structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope_application_fixture[:cases].each do |test_case|
      _batch_receipt_replay_workflow_result, batch_receipt_replay_workflow_result_rejection_error =
        described_class.import_structured_edit_provider_batch_execution_receipt_replay_workflow_result_envelope(test_case[:envelope])
      expect(json_ready(batch_receipt_replay_workflow_result_rejection_error)).to eq(json_ready(test_case[:expected_error]))
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

    profile_promotion_report_envelope = described_class.structured_edit_execution_report_envelope(
      structured_edit_profile_promotion_envelope_fixture[:structured_edit_execution_report]
    )
    expect(json_ready(profile_promotion_report_envelope)).to eq(
      json_ready(structured_edit_profile_promotion_envelope_fixture[:expected_execution_report_envelope])
    )
    expect(structured_edit_profile_promotion_envelope_fixture.dig(:structured_edit_execution_report,
                                                                  :profile_selection_decision, :rejection_code)).to eq(
                                                                    structured_edit_profile_promotion_envelope_fixture.dig(
                                                                      :expected, :rejection_code
                                                                    )
                                                                  )
    expect(structured_edit_profile_promotion_envelope_fixture.dig(:structured_edit_execution_report,
                                                                  :profile_blocking_reasons).length).to eq(
                                                                    structured_edit_profile_promotion_envelope_fixture.dig(
                                                                      :expected, :profile_blocking_reason_count
                                                                    )
                                                                  )

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

  it 'conforms to the slice-227 projected child-review groups fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-227-projected-child-review-groups',
        'projected-child-review-groups.json'
      )
    )

    grouped = described_class.group_projected_child_review_cases(fixture[:cases])
    expect(json_ready(grouped)).to eq(json_ready(fixture[:expected_groups]))
  end

  it 'conforms to the slice-230 projected child-review group progress fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-230-projected-child-review-group-progress',
        'projected-child-review-group-progress.json'
      )
    )

    progress = described_class.summarize_projected_child_review_group_progress(
      fixture[:groups],
      fixture[:resolved_case_ids]
    )
    expect(json_ready(progress)).to eq(json_ready(fixture[:expected_progress]))
  end

  it 'conforms to the slice-233 projected child-review groups ready-for-apply fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-233-projected-child-review-groups-ready-for-apply',
        'projected-child-review-groups-ready-for-apply.json'
      )
    )

    ready_groups = described_class.select_projected_child_review_groups_ready_for_apply(
      fixture[:groups],
      fixture[:resolved_case_ids]
    )
    expect(json_ready(ready_groups)).to eq(json_ready(fixture[:expected_ready_groups]))
  end

  it 'conforms to the slice-236 delegated child group review request fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-236-delegated-child-group-review-request',
        'delegated-child-group-review-request.json'
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

  it 'conforms to the slice-237 delegated child groups accepted-for-apply fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-237-delegated-child-group-accepted-for-apply',
        'delegated-child-groups-accepted-for-apply.json'
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

  it 'conforms to the slice-240 delegated child group review-state fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-240-delegated-child-group-review-state',
        'delegated-child-group-review-state.json'
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

  it 'conforms to the slice-243 delegated child apply-plan fixture' do
    fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-243-delegated-child-apply-plan',
        'delegated-child-apply-plan.json'
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

  it 'conforms to the slice-292 delegated child nested-output resolution fixture' do
    fixture = diagnostics_fixture('delegated_child_nested_output_resolution')

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

  it 'conforms to the slice-293 delegated child nested-output rejection fixture' do
    fixture = diagnostics_fixture('delegated_child_nested_output_rejection')

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

  it 'conforms to the slice-303 reviewed nested execution payload fixture' do
    fixture = diagnostics_fixture('reviewed_nested_execution_payload')

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

  it 'executes nested merge through merge, discovery, resolution, and apply' do
    nested_outputs = [
      {
        surface_address: 'document[0] > fenced_code_block[/code_fence/0]',
        output: "export const feature = true;\n"
      }
    ]
    calls = []

    result = described_class.execute_nested_merge(
      nested_outputs,
      default_family: 'markdown',
      request_id_prefix: 'nested_markdown_child',
      merge_parent: lambda {
        calls << 'merge'
        { ok: true, diagnostics: [], output: 'merged-parent', policies: [] }
      },
      discover_operations: lambda { |merged_output|
        calls << "discover:#{merged_output}"
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{nested_outputs.first[:surface_address]}",
              parent_operation_id: 'parent:merge',
              requested_strategy: 'delegate_child_surface',
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: 'fenced_code_block',
                effective_language: 'typescript',
                address: nested_outputs.first[:surface_address],
                owner: { kind: 'owned_region', address: '/code_fence/0' },
                reconstruction_strategy: 'portable_write',
                metadata: { family: 'typescript' }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, applied_children|
        calls << "apply:#{merged_output}"
        expect(operations.first[:operation_id]).to eq("operation:#{nested_outputs.first[:surface_address]}")
        expect(apply_plan.dig(:entries, 0, :family)).to eq('typescript')
        expect(applied_children.first[:operation_id]).to eq("operation:#{nested_outputs.first[:surface_address]}")
        { ok: true, diagnostics: [], output: 'final-parent', policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: 'final-parent', policies: []))
    expect(calls).to eq(['merge', 'discover:merged-parent', 'apply:merged-parent'])
  end

  it 'returns nested parent-merge failure unchanged and skips later stages' do
    called = false

    result = described_class.execute_nested_merge(
      [],
      default_family: 'markdown',
      request_id_prefix: 'nested',
      merge_parent: lambda {
        {
          ok: false,
          diagnostics: [{ severity: 'error', category: 'parse_error', message: 'parent failed' }],
          policies: []
        }
      },
      discover_operations: lambda { |_merged_output|
        called = true
        { ok: true, diagnostics: [], operations: [] }
      },
      apply_resolved_outputs: lambda {
        called = true
        { ok: true, diagnostics: [], output: 'unused', policies: [] }
      }
    )

    expect(result[:ok]).to eq(false)
    expect(called).to eq(false)
  end

  it 'executes delegated child apply plan through merge, discovery, and apply' do
    address = 'document[0] > fenced_code_block[/code_fence/0]'

    result = described_class.execute_delegated_child_apply_plan(
      {
        entries: [
          {
            request_id: 'projected_child_group:markdown:fence:typescript',
            family: 'markdown',
            delegated_group: {
              delegated_apply_group: 'markdown:fence:typescript',
              parent_operation_id: 'parent:merge',
              child_operation_id: "operation:#{address}",
              delegated_runtime_surface_path: address,
              case_ids: [],
              delegated_case_ids: []
            },
            decision: {
              request_id: 'projected_child_group:markdown:fence:typescript',
              action: 'apply_delegated_child_group'
            }
          }
        ]
      },
      [{ operation_id: "operation:#{address}", output: "child-output\n" }],
      merge_parent: lambda {
        { ok: true, diagnostics: [], output: 'merged-parent', policies: [] }
      },
      discover_operations: lambda { |_merged_output|
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{address}",
              parent_operation_id: 'parent:merge',
              requested_strategy: 'delegate_child_surface',
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: 'fenced_code_block',
                effective_language: 'typescript',
                address: address,
                owner: { kind: 'owned_region', address: '/code_fence/0' },
                reconstruction_strategy: 'portable_write',
                metadata: { family: 'typescript' }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |_merged_output, _operations, apply_plan, applied_children|
        expect(apply_plan[:entries].length).to eq(1)
        expect(applied_children).to eq([{ operation_id: "operation:#{address}", output: "child-output\n" }])
        { ok: true, diagnostics: [], output: 'final-parent', policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: 'final-parent', policies: []))
  end

  it 'executes reviewed nested merge from accepted review state' do
    address = 'document[0] > fenced_code_block[/code_fence/0]'

    result = described_class.execute_reviewed_nested_merge(
      {
        requests: [],
        accepted_groups: [
          {
            delegated_apply_group: 'markdown:fence:typescript',
            parent_operation_id: 'parent:merge',
            child_operation_id: "operation:#{address}",
            delegated_runtime_surface_path: address,
            case_ids: [],
            delegated_case_ids: []
          }
        ],
        applied_decisions: [
          {
            request_id: 'projected_child_group:markdown:fence:typescript',
            action: 'apply_delegated_child_group'
          }
        ],
        diagnostics: []
      },
      'markdown',
      [{ operation_id: "operation:#{address}", output: "child-output\n" }],
      merge_parent: lambda {
        { ok: true, diagnostics: [], output: 'merged-parent', policies: [] }
      },
      discover_operations: lambda { |_merged_output|
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{address}",
              parent_operation_id: 'parent:merge',
              requested_strategy: 'delegate_child_surface',
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: 'fenced_code_block',
                effective_language: 'typescript',
                address: address,
                owner: { kind: 'owned_region', address: '/code_fence/0' },
                reconstruction_strategy: 'portable_write',
                metadata: { family: 'typescript' }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |_merged_output, _operations, apply_plan, _applied_children|
        expect(apply_plan.dig(:entries, 0, :request_id)).to eq('projected_child_group:markdown:fence:typescript')
        { ok: true, diagnostics: [], output: 'final-parent', policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: 'final-parent', policies: []))
  end

  it 'executes reviewed nested execution payload directly' do
    address = 'document[0] > fenced_code_block[/code_fence/0]'

    result = described_class.execute_reviewed_nested_execution(
      described_class.reviewed_nested_execution(
        'markdown',
        {
          requests: [],
          accepted_groups: [
            {
              delegated_apply_group: 'markdown:fence:typescript',
              parent_operation_id: 'parent:merge',
              child_operation_id: "operation:#{address}",
              delegated_runtime_surface_path: address,
              case_ids: [],
              delegated_case_ids: []
            }
          ],
          applied_decisions: [
            {
              request_id: 'projected_child_group:markdown:fence:typescript',
              action: 'apply_delegated_child_group'
            }
          ],
          diagnostics: []
        },
        [{ operation_id: "operation:#{address}", output: "child-output\n" }]
      ),
      merge_parent: lambda {
        { ok: true, diagnostics: [], output: 'merged-parent', policies: [] }
      },
      discover_operations: lambda { |_merged_output|
        {
          ok: true,
          diagnostics: [],
          operations: [
            {
              operation_id: "operation:#{address}",
              parent_operation_id: 'parent:merge',
              requested_strategy: 'delegate_child_surface',
              language_chain: %w[markdown typescript],
              surface: {
                surface_kind: 'fenced_code_block',
                effective_language: 'typescript',
                address: address,
                owner: { kind: 'owned_region', address: '/code_fence/0' },
                reconstruction_strategy: 'portable_write',
                metadata: { family: 'typescript' }
              }
            }
          ]
        }
      },
      apply_resolved_outputs: lambda { |_merged_output, _operations, apply_plan, applied_children|
        expect(apply_plan.dig(:entries, 0, :request_id)).to eq('projected_child_group:markdown:fence:typescript')
        expect(applied_children).to eq([{ operation_id: "operation:#{address}", output: "child-output\n" }])
        { ok: true, diagnostics: [], output: 'final-parent', policies: [] }
      }
    )

    expect(json_ready(result)).to eq(json_ready(ok: true, diagnostics: [], output: 'final-parent', policies: []))
  end

  it 'conforms to the widened source-family manifest and report fixtures' do
    source_manifest = read_json(fixtures_root.join('conformance', 'slice-124-source-family-manifest',
                                                   'source-family-manifest.json'))
    source_report_fixture = diagnostics_fixture('manifest_backend_report')
    mixed_source_report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-128-source-family-manifest-report', 'source-manifest-report.json')
    )

    expect(described_class.conformance_family_feature_profile_path(source_manifest, 'typescript')).to eq(
      %w[diagnostics slice-101-typescript-family-feature-profile typescript-feature-profile.json]
    )
    expect(described_class.conformance_fixture_path(source_manifest, 'rust', 'merge')).to eq(
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

  it 'conforms to the source-family suite-definition and named-suite plan fixtures' do
    suite_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-125-source-family-suite-definitions', 'source-suite-definitions.json')
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
      fixtures_root.join('diagnostics', 'slice-126-source-family-named-suite-plans', 'source-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    native_plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-127-source-family-native-suite-plans',
                         'source-native-named-suite-plans.json')
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

  it 'conforms to the source-family backend-restricted plan and report fixtures' do
    plans_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-129-source-family-backend-restricted-plans',
        'source-backend-restricted-plans.json'
      )
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-130-source-family-backend-restricted-report',
        'source-backend-restricted-report.json'
      )
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the TOML family suite-definition, named-suite plan, and manifest report fixtures' do
    suite_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-138-toml-family-suite-definitions', 'toml-suite-definitions.json')
    )
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(json_ready(suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest],
                                                        suite_fixture[:suite_selectors].first)).to eq(
                                                          suite_fixture[:suite_definitions].first
                                                        )

    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-139-toml-family-named-suite-plans', 'ruby-toml-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-140-toml-family-manifest-report', 'ruby-toml-manifest-report.json')
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the YAML family suite-definition, named-suite plan, and manifest report fixtures' do
    suite_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-144-yaml-family-suite-definitions', 'yaml-suite-definitions.json')
    )
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(json_ready(suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest],
                                                        suite_fixture[:suite_selectors].first)).to eq(
                                                          suite_fixture[:suite_definitions].first
                                                        )

    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-145-yaml-family-named-suite-plans', 'ruby-yaml-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-146-yaml-family-manifest-report', 'ruby-yaml-manifest-report.json')
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the Markdown family suite-definition, named-suite plan, and manifest report fixtures' do
    suite_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-200-markdown-family-suite-definitions',
                         'markdown-suite-definitions.json')
    )
    expect(json_ready(described_class.conformance_suite_selectors(suite_fixture[:manifest]))).to eq(json_ready(suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(suite_fixture[:manifest],
                                                        suite_fixture[:suite_selectors].first)).to eq(
                                                          suite_fixture[:suite_definitions].first
                                                        )

    plans_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-201-markdown-family-named-suite-plans',
        'ruby-markdown-named-suite-plans.json'
      )
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-202-markdown-family-manifest-report',
        'ruby-markdown-manifest-report.json'
      )
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the backend-aware YAML family named-suite plan and manifest report fixtures' do
    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-173-yaml-family-backend-named-suite-plans',
                         'ruby-yaml-backend-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-174-yaml-family-backend-manifest-report',
                         'ruby-yaml-backend-manifest-report.json')
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the slice-246 through slice-251 nested Markdown and Ruby suite fixtures' do
    markdown_suite_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-246-markdown-nested-suite-definitions',
                         'markdown-nested-suite-definitions.json')
    )
    expect(json_ready(described_class.conformance_suite_selectors(markdown_suite_fixture[:manifest]))).to eq(json_ready(markdown_suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(markdown_suite_fixture[:manifest],
                                                        markdown_suite_fixture[:suite_selectors].first)).to eq(
                                                          markdown_suite_fixture[:suite_definitions].first
                                                        )

    markdown_plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-247-markdown-nested-named-suite-plans',
                         'markdown-nested-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(markdown_plans_fixture[:manifest],
                                                               markdown_plans_fixture[:contexts]))
    ).to eq(json_ready(markdown_plans_fixture[:expected_entries]))

    markdown_report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-248-markdown-nested-manifest-report',
                         'markdown-nested-manifest-report.json')
    )
    markdown_report = described_class.report_conformance_manifest(
      markdown_report_fixture[:manifest],
      markdown_report_fixture[:options],
      &execute_from(markdown_report_fixture[:executions])
    )
    expect(json_ready(markdown_report)).to eq(json_ready(markdown_report_fixture[:expected_report]))

    ruby_suite_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-249-ruby-nested-suite-definitions', 'ruby-nested-suite-definitions.json')
    )
    expect(json_ready(described_class.conformance_suite_selectors(ruby_suite_fixture[:manifest]))).to eq(json_ready(ruby_suite_fixture[:suite_selectors]))
    expect(described_class.conformance_suite_definition(ruby_suite_fixture[:manifest],
                                                        ruby_suite_fixture[:suite_selectors].first)).to eq(
                                                          ruby_suite_fixture[:suite_definitions].first
                                                        )

    ruby_plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-250-ruby-nested-named-suite-plans', 'ruby-nested-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(ruby_plans_fixture[:manifest],
                                                               ruby_plans_fixture[:contexts]))
    ).to eq(json_ready(ruby_plans_fixture[:expected_entries]))

    ruby_report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-251-ruby-nested-manifest-report', 'ruby-nested-manifest-report.json')
    )
    ruby_report = described_class.report_conformance_manifest(
      ruby_report_fixture[:manifest],
      ruby_report_fixture[:options],
      &execute_from(ruby_report_fixture[:executions])
    )
    expect(json_ready(ruby_report)).to eq(json_ready(ruby_report_fixture[:expected_report]))
  end

  it 'conforms to the polyglot YAML family named-suite plan and manifest report fixtures' do
    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-185-yaml-family-polyglot-backend-named-suite-plans',
                         'ruby-yaml-polyglot-named-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-186-yaml-family-polyglot-backend-manifest-report',
                         'ruby-yaml-polyglot-manifest-report.json')
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the aggregate config-family manifest, plan, and report fixtures' do
    manifest_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-148-config-family-aggregate-manifest', 'config-family-aggregate.json')
    )
    expect(json_ready(described_class.conformance_suite_selectors(manifest_fixture[:manifest]))).to eq(json_ready(manifest_fixture[:suite_selectors]))

    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-149-config-family-aggregate-suite-plans',
                         'config-family-aggregate-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-150-config-family-aggregate-manifest-report',
        'config-family-aggregate-manifest-report.json'
      )
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))
  end

  it 'conforms to the aggregate config-family review-state fixtures' do
    %w[
      slice-151-config-family-aggregate-review-state/config-family-aggregate-review-state.json
      slice-152-config-family-aggregate-reviewed-default/config-family-aggregate-reviewed-default.json
      slice-153-config-family-aggregate-replay-application/config-family-aggregate-replay-application.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join('diagnostics', relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it 'conforms to the canonical stable-suite planning and review fixtures' do
    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-155-canonical-stable-suite-plans', 'canonical-stable-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-156-canonical-stable-suite-report', 'canonical-stable-suite-report.json')
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

    review_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-157-canonical-stable-suite-review-state',
                         'canonical-stable-suite-review-state.json')
    )
    state = described_class.review_conformance_manifest(
      review_fixture[:manifest],
      review_fixture[:options],
      &execute_from(review_fixture[:executions])
    )
    expect(json_ready(state)).to eq(json_ready(review_fixture[:expected_state]))
  end

  it 'conforms to the canonical stable-suite backend fixtures' do
    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-175-canonical-stable-suite-backend-plans',
                         'ruby-canonical-stable-suite-backend-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-176-canonical-stable-suite-backend-report',
                         'ruby-canonical-stable-suite-backend-report.json')
    )
    report = described_class.report_conformance_manifest(
      report_fixture[:manifest],
      report_fixture[:options],
      &execute_from(report_fixture[:executions])
    )
    expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

    review_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-177-canonical-stable-suite-backend-review-state',
                         'ruby-canonical-stable-suite-backend-review-state.json')
    )
    state = described_class.review_conformance_manifest(
      review_fixture[:manifest],
      review_fixture[:options],
      &execute_from(review_fixture[:executions])
    )
    expect(json_ready(state)).to eq(json_ready(review_fixture[:expected_state]))
  end

  it 'conforms to the source-family review-state fixtures' do
    %w[
      slice-158-source-family-review-state/source-family-review-state.json
      slice-159-source-family-reviewed-default/source-family-reviewed-default.json
      slice-160-source-family-replay-application/source-family-replay-application.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join('diagnostics', relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it 'conforms to the canonical widened-suite fixtures' do
    plans_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-162-canonical-widened-suite-plans', 'canonical-widened-suite-plans.json')
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    report_fixture = read_json(
      fixtures_root.join('diagnostics', 'slice-163-canonical-widened-suite-report',
                         'canonical-widened-suite-report.json')
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
      fixture = read_json(fixtures_root.join('diagnostics', relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end

  it 'conforms to the canonical widened-suite backend fixtures' do
    [
      [
        'slice-178-canonical-widened-suite-backend-plans',
        'ruby-canonical-widened-suite-backend-plans.json',
        'slice-179-canonical-widened-suite-backend-report',
        'ruby-canonical-widened-suite-backend-report.json',
        %w[
          slice-180-canonical-widened-suite-backend-review-state/ruby-canonical-widened-suite-backend-review-state.json
          slice-181-canonical-widened-suite-backend-reviewed-default/ruby-canonical-widened-suite-backend-reviewed-default.json
          slice-182-canonical-widened-suite-backend-replay-application/ruby-canonical-widened-suite-backend-replay-application.json
        ]
      ],
      [
        'slice-187-canonical-widened-suite-polyglot-backend-plans',
        'ruby-canonical-widened-suite-polyglot-backend-plans.json',
        'slice-188-canonical-widened-suite-polyglot-backend-report',
        'ruby-canonical-widened-suite-polyglot-backend-report.json',
        %w[
          slice-189-canonical-widened-suite-polyglot-backend-review-state/ruby-canonical-widened-suite-polyglot-backend-review-state.json
          slice-190-canonical-widened-suite-polyglot-backend-reviewed-default/ruby-canonical-widened-suite-polyglot-backend-reviewed-default.json
          slice-191-canonical-widened-suite-polyglot-backend-replay-application/ruby-canonical-widened-suite-polyglot-backend-replay-application.json
        ]
      ]
    ].each do |plans_slice, plans_file, report_slice, report_file, review_paths|
      plans_fixture = read_json(fixtures_root.join('diagnostics', plans_slice, plans_file))
      expect(
        json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
      ).to eq(json_ready(plans_fixture[:expected_entries]))

      report_fixture = read_json(fixtures_root.join('diagnostics', report_slice, report_file))
      report = described_class.report_conformance_manifest(
        report_fixture[:manifest],
        report_fixture[:options],
        &execute_from(report_fixture[:executions])
      )
      expect(json_ready(report)).to eq(json_ready(report_fixture[:expected_report]))

      review_paths.each do |relative_path|
        fixture = read_json(fixtures_root.join('diagnostics', relative_path))
        state = described_class.review_conformance_manifest(
          fixture[:manifest],
          fixture[:options],
          &execute_from(fixture[:executions])
        )
        expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
      end
    end
  end

  it 'conforms to the backend-sensitive aggregate fixtures' do
    plans_fixture = read_json(
      fixtures_root.join(
        'diagnostics',
        'slice-167-backend-sensitive-aggregate-suite-plans',
        'backend-sensitive-aggregate-suite-plans.json'
      )
    )
    expect(
      json_ready(described_class.plan_named_conformance_suites(plans_fixture[:manifest], plans_fixture[:contexts]))
    ).to eq(json_ready(plans_fixture[:expected_entries]))

    %w[
      slice-168-backend-sensitive-aggregate-tree-sitter-report/backend-sensitive-aggregate-tree-sitter-report.json
      slice-169-backend-sensitive-aggregate-native-report/backend-sensitive-aggregate-native-report.json
    ].each do |relative_path|
      fixture = read_json(fixtures_root.join('diagnostics', relative_path))
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
      fixture = read_json(fixtures_root.join('diagnostics', relative_path))
      state = described_class.review_conformance_manifest(
        fixture[:manifest],
        fixture[:options],
        &execute_from(fixture[:executions])
      )
      expect(json_ready(state)).to eq(json_ready(fixture[:expected_state]))
    end
  end
end
