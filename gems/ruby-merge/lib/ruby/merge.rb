# frozen_string_literal: true

require 'digest'
require 'tree_haver'
require 'ast/merge'
require_relative 'merge/version'
require_relative 'merge/block_directive_detector'
require_relative 'merge/block_binding_support'
require_relative 'merge/doc_comment_support'
require_relative 'merge/gemspec_support'
require_relative 'merge/magic_comment_support'
require_relative 'merge/method_similarity'
require_relative 'merge/nocov_node_base'
require_relative 'merge/nocov_wrapper_base'
require_relative 'merge/rescue_semantics'
require_relative 'merge/scaffold_chunk_support'
require_relative 'merge/signature_support'

module Ruby
  # Public Ruby parser-family substrate for Structured Merge.
  #
  # The adapter deliberately keeps parser capability reporting, ownership
  # discovery, merge planning, and source reconstruction together. Splitting
  # those phases to satisfy generic size metrics would obscure the contract
  # they implement and make provider behavior harder to audit.
  # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/BlockNesting
  # rubocop:disable Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength
  # rubocop:disable Metrics/ModuleLength, Metrics/PerceivedComplexity
  # rubocop:disable Style/MultilineBlockChain
  module Merge
    extend self
    include Ast::Merge::SourceRegionReportSupport

    PACKAGE_NAME = 'ruby-merge'
    TREE_SITTER_BACKEND = TreeHaver::KREUZBERG_LANGUAGE_PACK_BACKEND
    DESTINATION_WINS_ARRAY_POLICY = { surface: 'array', name: 'destination_wins_array' }.freeze
    DEFAULT_METHOD_MOVE_POLICY = 'destination_order'
    BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)
    TslpSpan = Struct.new(:start_row, :start_col, :end_row, :end_col, keyword_init: true)
    TslpStructureItem = Struct.new(:kind, :name, :span, keyword_init: true)
    TslpImportItem = Struct.new(:source, :span, keyword_init: true)
    TslpProcessAnalysis = Struct.new(:structure, :imports, keyword_init: true)
    PERCENT_ARRAY_DELIMITER_PAIRS = {
      '[' => ']',
      '(' => ')',
      '{' => '}',
      '<' => '>'
    }.freeze
    REQUIRE_PATTERN = /^\s*require(?:_relative)?\s+["']([^"']+)["']/
    CLASS_PATTERN = /^\s*class\s+([A-Z]\w*(?:::\w+)*)/
    MODULE_PATTERN = /^\s*module\s+([A-Z]\w*(?:::\w+)*)/
    DEF_PATTERN = %r{
      ^\s*def\s+
      ((?:self\.)?)
      ([a-zA-Z_]\w*[!?=]?|\[\]=?|\+@|-@|\*\*|<<|>>|<=>|===|==|=~|!~|!=|[+\-*/%&|^<>]=?|[!~`])
    }x
    CONSTANT_ASSIGNMENT_PATTERN = /^(\s*)([A-Z]\w*)\s*=/
    CONSTANT_HASH_ASSIGNMENT_PATTERN = /^(\s*)([A-Z]\w*)\s*=\s*\{/

    def register_backend!
      BACKEND_REGISTRY.mutex.synchronize do
        return if BACKEND_REGISTRY.registered

        TreeHaver::BackendRegistry.register(TREE_SITTER_BACKEND)

        grammar_finder = TreeHaver::GrammarFinder.new(:ruby)
        grammar_finder.register! if grammar_finder.available?

        BACKEND_REGISTRY.registered = true
      end
    end

    def ruby_feature_profile
      {
        family: 'ruby',
        supported_dialects: ['ruby'],
        supported_policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def available_ruby_backends
      ruby_backend_available_for_analysis?(TREE_SITTER_BACKEND.id) ? [TREE_SITTER_BACKEND] : []
    end

    def ruby_tslp_capability_profile
      {
        import_records: TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_import_records),
        top_level_call_records: TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_top_level_call_records)
      }
    end

    def ruby_backend_feature_profile(backend: nil)
      requested = requested_tree_sitter_backend_id(backend)
      unless ruby_backend_available_for_analysis?(requested)
        return unsupported_feature_result("Unsupported Ruby backend #{requested}.")
      end

      ruby_feature_profile.merge(
        backend: requested,
        backend_ref: TREE_SITTER_BACKEND.to_h,
        supports_dialects: true
      )
    end

    def ruby_plan_context(backend: nil)
      profile = ruby_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: ruby_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def ruby_backend_available_for_analysis?(backend_id)
      register_backend!

      if backend_id.to_s.empty?
        TreeHaver.parser_for(:ruby, backend_type: :tree_sitter)
      else
        TreeHaver.with_backend(backend_id) { TreeHaver.parser_for(:ruby, backend_type: :tree_sitter) }
      end
      true
    rescue TreeHaver::Error, ArgumentError
      false
    end

    def parse_ruby(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? nil : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == 'ruby'

      unless ruby_backend_available_for_analysis?(requested)
        diagnostic_backend = requested || TreeHaver.current_backend_id || 'tree-sitter'
        return unsupported_feature_result("Unsupported Ruby backend #{diagnostic_backend}.")
      end

      tree = parse_tree_sitter_source(:ruby, source, backend: requested)
      collect_parse_errors(tree.root_node)

      process_analysis = ruby_process_analysis_from_tree(source, tree.root_node)
      {
        ok: true,
        diagnostics: [],
        analysis: analyze_ruby_document(source, process_analysis: process_analysis),
        policies: []
      }
    rescue TreeHaver::Error, StandardError => e
      parse_failure_result(e)
    end

    def parse_tree_sitter_source(language, source, backend: nil)
      if backend
        TreeHaver.with_backend(backend) { TreeHaver.parser_for(language, backend_type: :tree_sitter).parse(source) }
      else
        TreeHaver.parser_for(language, backend_type: :tree_sitter).parse(source)
      end
    end
    private_class_method :parse_tree_sitter_source

    def requested_tree_sitter_backend_id(backend)
      return backend.to_s unless backend.to_s.empty?

      contextual = TreeHaver.current_backend_id || ENV['TREE_HAVER_BACKEND']
      contextual.to_s.empty? || contextual.to_s == 'auto' ? TREE_SITTER_BACKEND.id : contextual.to_s
    end
    private_class_method :requested_tree_sitter_backend_id

    def match_ruby_owners(template, destination)
      Ast::Merge::OwnerSelection.match_by_path(template, destination)
    end

    def ruby_method_move_detection(template_source, destination_source, dialect)
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == 'ruby'

      template_methods = ruby_method_projection(template_source, revision: 'template')
      destination_methods = ruby_method_projection(destination_source, revision: 'destination')
      destination_by_signature = destination_methods.to_h { |entry| [entry[:signature], entry] }
      template_signatures = template_methods
                            .map { |entry| entry[:signature] }
                            .to_h { |signature| [signature, true] }

      matches = template_methods.filter_map do |template_entry|
        destination_entry = destination_by_signature[template_entry[:signature]]
        next unless destination_entry

        moved = template_entry[:index] != destination_entry[:index] ||
                template_entry[:parent_path] != destination_entry[:parent_path]
        Ast::Merge::MoveDetectionMatch.new(
          from_path: template_entry[:path],
          to_path: destination_entry[:path],
          from_node_id: template_entry[:node_id],
          to_node_id: destination_entry[:node_id],
          signature: template_entry[:signature],
          moved: moved,
          from_parent_path: template_entry[:parent_path],
          to_parent_path: destination_entry[:parent_path],
          from_index: template_entry[:index],
          to_index: destination_entry[:index],
          confidence: moved ? 0.98 : 0.9,
          diagnostics: [
            if moved
              'same Ruby method signature observed at a different sibling position'
            else
              'same Ruby method signature observed at the same sibling position'
            end
          ]
        )
      end

      matched_template_signatures = matches.map(&:signature).to_h { |signature| [signature, true] }
      Ast::Merge::MoveDetectionMatchingReport.new(
        matching_id: 'ruby-method-move-detection',
        strategy: 'move_detection',
        from_revision: 'template',
        to_revision: 'destination',
        capability: Ast::Merge::MoveDetectionCapability.new(
          name: 'move_detection',
          enabled: true,
          default_enabled: false,
          requires_stable_node_identity: true
        ),
        matches: matches,
        unmatched_from: template_methods.reject do |entry|
          matched_template_signatures[entry[:signature]]
        end.map { |entry| entry[:path] },
        unmatched_to: destination_methods.reject do |entry|
          template_signatures[entry[:signature]]
        end.map { |entry| entry[:path] },
        diagnostics: [
          'Ruby method move detection uses generic move-detection matching over receiver-aware method projections'
        ]
      ).to_h
    end

    def merge_ruby(template_source, destination_source, dialect, merge_template_requires: false,
                   method_move_policy: DEFAULT_METHOD_MOVE_POLICY)
      template = parse_ruby(template_source, dialect)
      return template unless template[:ok]

      method_move_policy = normalize_method_move_policy(method_move_policy)

      destination = parse_ruby(destination_source, dialect)
      unless destination[:ok]
        return {
          ok: false,
          diagnostics: destination[:diagnostics].map do |diagnostic|
            diagnostic[:category] == 'parse_error' ? diagnostic.merge(category: 'destination_parse_error') : diagnostic
          end,
          policies: []
        }
      end

      destination_context = ruby_tslp_merge_context(destination.fetch(:analysis), role: 'destination')
      return destination_context unless destination_context[:ok]

      template_context = ruby_tslp_merge_context(template.fetch(:analysis), role: 'template')
      return template_context unless template_context[:ok]

      destination_requires = destination_context.fetch(:requires)
      template_requires = template_context.fetch(:requires)
      destination_declarations = destination_context.fetch(:declarations)
      template_declarations = template_context.fetch(:declarations)
      template_declarations_by_key = template_declarations.to_h { |entry| [entry[:merge_key], entry] }
      intra_owner_merges = ruby_intra_owner_merge_plan(template_declarations, destination_declarations)
      namespace_conflicts = ruby_namespace_form_conflicts(template_declarations, destination_declarations)
      namespace_equivalence_available = TreeHaver::BackendRegistry.tag_available?(
        :tslp_ruby_namespace_form_equivalence
      )
      unless namespace_conflicts.empty? || namespace_equivalence_available
        conflicts = namespace_conflicts.join(', ')
        return unsupported_feature_result(
          'ruby-merge cannot reconcile equivalent Ruby namespace declaration forms with the active TSLP records: ' \
          "#{conflicts}. Use a native Ruby provider for native Ruby merging, or report missing Ruby namespace " \
          'ownership records to tree-sitter-language-pack.'
        )
      end
      if !namespace_conflicts.empty? && TreeHaver::BackendRegistry.tag_available?(:tslp_ruby_namespace_form_equivalence)
        template_declarations += qualified_nested_declaration_entries(template_declarations)
        template_declarations_by_key = template_declarations.to_h { |entry| [entry[:merge_key], entry] }
      end
      destination_paths = destination_declarations.to_h { |entry| [entry[:merge_key], true] }
      sections = []
      preamble = destination_context.fetch(:preamble)
      sections << { text: preamble } unless preamble.empty?
      requires = if merge_template_requires
                   merge_ruby_requires(destination_requires,
                                       template_requires)
                 else
                   destination_requires
                 end
      require_block = requires.map { |entry| entry[:text] }.join("\n").strip
      sections << ruby_top_level_section(require_block, requires) unless require_block.empty?
      sections.concat(
        destination_declarations.map do |entry|
          ruby_top_level_section(
            merge_ruby_declaration_entry(template_declarations_by_key[entry[:merge_key]], entry)[:text],
            [entry]
          )
        end
      )
      sections.concat(
        template_declarations.reject do |entry|
          destination_paths[entry[:merge_key]] ||
            namespace_wrapper_matched?(entry, template_declarations, destination_paths)
        end.map { |entry| { text: entry[:text] } }
      )
      destination_footer = destination_context.fetch(:footer)
      sections << { text: destination_footer } unless destination_footer.empty?

      output = emit_ruby_top_level_sections(destination_source, sections)
      matching_reports = [ruby_method_move_detection(template_source, destination_source, dialect)]
      moved_method_count = matching_reports.sum do |report|
        Array(report[:matches]).count { |entry| entry[:moved] }
      end

      {
        ok: true,
        diagnostics: [],
        output: output,
        policies: [DESTINATION_WINS_ARRAY_POLICY],
        matching_reports: matching_reports,
        merge_planning: {
          method_move_policy: method_move_policy,
          method_move_detection: {
            matching_id: 'ruby-tslp-method-move-detection',
            moved_method_count: moved_method_count,
            preserves_destination_order: method_move_policy == DEFAULT_METHOD_MOVE_POLICY,
            suppresses_duplicate_moved_methods: method_move_policy == DEFAULT_METHOD_MOVE_POLICY,
            override_scope: 'per_file_recipe'
          },
          intra_owner_merges: {
            strategy: 'destination_wins_scoped_owner_body',
            merge_count: intra_owner_merges.length,
            merges: intra_owner_merges
          }
        }
      }
    end

    def ruby_discovered_surfaces(analysis)
      analysis[:discovered_surfaces] || []
    end

    def ruby_delegated_child_operations(analysis, parent_operation_id: 'ruby-document-0')
      surfaces = ruby_discovered_surfaces(analysis)
      doc_operation_ids = {}
      operations = []

      surfaces.each_with_index do |surface, index|
        next unless surface[:surface_kind] == 'ruby_doc_comment'

        operation_id = "ruby-doc-comment-#{index}"
        doc_operation_ids[surface[:address]] = operation_id
        operations << Ast::Merge.delegated_child_operation(
          operation_id: operation_id,
          parent_operation_id: parent_operation_id,
          requested_strategy: 'delegate_child_surface',
          language_chain: ['ruby', surface[:effective_language]],
          surface: surface
        )
      end

      example_index = 0
      surfaces.each do |surface|
        next unless surface[:surface_kind] == 'yard_example_block'

        operations << Ast::Merge.delegated_child_operation(
          operation_id: "yard-example-#{example_index}",
          parent_operation_id: doc_operation_ids.fetch(surface[:parent_address], parent_operation_id),
          requested_strategy: 'delegate_child_surface',
          language_chain: ['ruby', 'yard', surface[:effective_language]],
          surface: surface
        )
        example_index += 1
      end

      operations
    end

    def ruby_source_regions(source)
      lines = normalize_source(source).lines(chomp: true)
      owners = top_level_source_region_owners(lines)

      {
        regions: source_interleaved_regions_for_report(lines: lines, owners: owners),
        trailing_newline: normalize_source(source).end_with?("\n")
      }
    end

    def ruby_source_owner_identity_profile(source)
      identities = collect_ruby_declaration_entries(source).flat_map do |entry|
        declaration_identity = source_owner_identity_entry(
          kind: entry[:kind],
          name: entry[:name],
          parent_scope: '/',
          address: entry[:path],
          content: entry[:text]
        )
        method_identities = direct_body_method_entries(entry[:text]).map do |method_entry|
          source_owner_identity_entry(
            kind: 'method',
            name: method_entry[:signature],
            parent_scope: entry[:path],
            address: "#{entry[:path]}/methods/#{method_entry[:signature]}",
            content: method_entry[:body_text]
          )
        end
        [declaration_identity, *method_identities]
      end
      add_source_owner_occurrence_indexes(identities)
    end

    def ruby_source_owner_identity_matches(template_source, destination_source)
      template_identities = ruby_source_owner_identity_profile(template_source)
      destination_identities = ruby_source_owner_identity_profile(destination_source)
      destination_groups = destination_identities.group_by { |identity| identity[:structural_identity] }
      template_identities.group_by { |identity| identity[:structural_identity] }
      matched_destination_addresses = {}

      matches = template_identities.filter_map do |template_identity|
        destination_identity = destination_groups.fetch(template_identity[:structural_identity], []).find do |candidate|
          candidate[:occurrence_index] == template_identity[:occurrence_index]
        end
        next unless destination_identity

        matched_destination_addresses[destination_identity[:address]] = true
        {
          template_address: template_identity[:address],
          destination_address: destination_identity[:address],
          structural_identity: template_identity[:structural_identity],
          occurrence_index: template_identity[:occurrence_index],
          confidence: 'structural_ordered'
        }
      end

      matched_template_addresses = matches.to_h { |match| [match[:template_address], true] }
      {
        confidence_profile: ruby_source_owner_match_confidence_profile,
        matches: matches,
        unmatched_template: template_identities.reject do |identity|
          matched_template_addresses[identity[:address]]
        end.map { |identity| identity[:address] },
        unmatched_destination: destination_identities.reject do |identity|
          matched_destination_addresses[identity[:address]]
        end.map { |identity| identity[:address] },
        diagnostics: [
          {
            severity: 'info',
            category: 'source_owner_identity_matching',
            message: 'Ruby source-owner matching reports confidence per match and uses ordered structural pairing ' \
                     'for duplicate identities.'
          }
        ]
      }
    end

    def ruby_ambiguous_source_owner_identity_report(source)
      identities = ruby_source_owner_identity_profile(source)
      ambiguities = identities
                    .group_by { |identity| identity[:structural_identity] }
                    .filter_map do |structural_identity, entries|
                      next if entries.length < 2

                      {
                        structural_identity: structural_identity,
                        occurrence_count: entries.length,
                        addresses: entries.map { |entry| entry[:address] },
                        ambiguity_kind: 'duplicate_structural_identity',
                        resolution_model: 'ordered_cursor',
                        confidence: 'structural_ordered'
                      }
                    end

      {
        ambiguities: ambiguities,
        diagnostics: if ambiguities.empty?
                       []
                     else
                       [
                         {
                           severity: 'warning',
                           category: 'ambiguous_source_owner_identity',
                           message: 'Repeated Ruby source-owner identities require ordered cursor matching.'
                         }
                       ]
                     end
      }
    end

    def ruby_source_owner_match_confidence_profile
      {
        levels: [
          {
            name: 'exact',
            meaning: 'same structural identity, occurrence index, and content identity'
          },
          {
            name: 'structural_ordered',
            meaning: 'same structural identity and occurrence index'
          },
          {
            name: 'content_hash',
            meaning: 'same content-derived identity when structural identity is ambiguous'
          },
          {
            name: 'token_similar',
            meaning: 'similar token content below exact content identity'
          },
          {
            name: 'unresolved',
            meaning: 'identity is ambiguous and must not be auto-matched'
          }
        ]
      }
    end

    def ruby_fallback_policy_profile
      {
        policy_id: 'ruby-source-fallback-policy',
        baseline_provider: {
          provider_id: 'host_baseline_merge',
          integration_point: true
        },
        scopes: %w[node subtree owned_region whole_file],
        triggers: [
          { reason: 'binary_input', scope: 'whole_file' },
          { reason: 'unsupported_structural_merge_capability', scope: 'whole_file' },
          { reason: 'no_structural_owners', scope: 'whole_file' },
          { reason: 'both_branches_create_file', scope: 'whole_file' },
          { reason: 'excessive_duplicate_identities', scope: 'owned_region' },
          { reason: 'timeout_or_resource_budget', scope: 'whole_file' },
          { reason: 'backend_diagnostic_threshold', scope: 'owned_region' }
        ],
        reporting_fields: %w[activated reason scope selected_baseline structured_result_discarded]
      }
    end

    def ruby_fallback_activation_report(reason:, scope:, selected_baseline: 'host_baseline_merge',
                                        structured_result_discarded: true)
      {
        activated: true,
        reason: reason,
        scope: scope,
        selected_baseline: selected_baseline,
        structured_result_discarded: structured_result_discarded,
        policy_id: ruby_fallback_policy_profile.fetch(:policy_id),
        diagnostics: [
          {
            severity: 'warning',
            category: 'fallback_applied',
            message: "Ruby source fallback activated for #{reason} at #{scope} scope."
          }
        ]
      }
    end

    def ruby_never_worse_fallback_mode
      {
        mode_id: 'never_worse_than_baseline',
        enabled: true,
        baseline_provider: ruby_fallback_policy_profile.dig(:baseline_provider, :provider_id),
        comparison: {
          conflict_count: 'structured_must_not_exceed_baseline',
          conflict_scope: 'structured_must_not_be_broader_than_baseline',
          data_loss: 'structured_must_not_drop_clean_branch_content'
        },
        fallback_action: 'discard_structured_result_and_use_baseline',
        diagnostics: [
          {
            severity: 'info',
            category: 'never_worse_fallback_mode',
            message: 'Ruby fallback comparison mode treats the host baseline merge as the safety floor.'
          }
        ]
      }
    end

    def ruby_post_merge_validation_profile
      {
        profile_id: 'ruby-post-merge-validation',
        phase: 'post_merge_validation',
        separate_from: %w[merge_planning rendering],
        checks: %w[
          reparse_merged_output
          resolved_owners_present
          owner_count_not_unexpectedly_lower
          unchanged_significant_lines_preserved
          branch_added_significant_lines_preserved
          output_length_within_policy_bounds
          conflict_marker_shape_compatible
        ],
        failure_outcomes: %w[fallback_to_baseline scoped_conflict hard_diagnostic_failure],
        hooks: {
          ci: 'strict',
          exploratory: 'permissive_when_explicit'
        }
      }
    end

    def ruby_conflict_diagnostics_profile
      {
        profile_id: 'ruby-source-conflict-diagnostics',
        conflict_kinds: %w[
          both_modified
          both_added
          modify_delete
          rename_rename
          rename_modify
          order_sensitive_sibling_additions
          interstitial_conflict
          validation_failure
        ],
        risk_levels: %w[text_only syntax_level semantic_risk unknown],
        marker_compatibility: {
          standard_markers: true,
          enhanced_metadata: 'sidecar_or_review_state'
        },
        audit_fields: %w[
          owner_identity
          owner_kind
          strategy_chosen
          match_confidence
          fallback_reason
          validation_warnings
          conflict_kind
          conflict_scope
        ],
        stable_for_review_replay: true
      }
    end

    def ruby_formatter_policy_profile
      {
        profile_id: 'ruby-source-formatter-policy',
        adapter_phase: 'optional_post_merge_adapter',
        semantic_validation: 'not_proven_by_formatter',
        policies: %w[
          no_formatter
          validate_only
          format_after_clean_merge
          format_after_fallback
          formatter_failure_is_warning
          formatter_failure_is_hard_error
        ],
        portable_fixture_default: 'no_formatter',
        formatter_execution_in_portable_expectations: 'only_when_fixture_opts_in',
        invariants: %w[owner_identity conflict_scope validation_semantics]
      }
    end

    def ruby_formatter_adapter_report(pre_format_output:, formatted_output:, policy: 'validate_only',
                                      conflict_scope: 'none')
      pre_format_owners = ruby_source_owner_identity_profile(pre_format_output)
      formatted_owners = ruby_source_owner_identity_profile(formatted_output)
      formatted_owner_signatures = stable_owner_signatures(formatted_owners)
      owners_preserved = stable_owner_signatures(pre_format_owners) == formatted_owner_signatures
      whitespace_repaired = pre_format_output != formatted_output

      {
        policy: policy,
        formatter_profile: ruby_formatter_policy_profile.fetch(:profile_id),
        adapter_phase: 'optional_post_merge_adapter',
        semantic_validation: 'not_proven_by_formatter',
        whitespace_repaired: whitespace_repaired,
        owners_preserved: owners_preserved,
        conflict_scope_preserved: true,
        validation_semantics_preserved: true,
        conflict_scope: conflict_scope,
        portable_expectation: 'formatter_not_executed_unless_fixture_opts_in',
        owner_signatures: formatted_owner_signatures,
        diagnostics: [
          {
            severity: owners_preserved ? 'info' : 'error',
            category: owners_preserved ? 'formatter_adapter_accepted' : 'formatter_adapter_rejected',
            message: if owners_preserved
                       'Ruby formatter adapter preserved owner identity, conflict scope, and validation semantics.'
                     else
                       'Ruby formatter adapter changed owner identity and cannot be accepted as a semantic merge.'
                     end
          }
        ]
      }
    end

    def ruby_ast_node_merge_strategy_profile
      {
        profile_id: 'ruby-optional-ast-node-merge',
        merge_surfaces: %w[owner ast_node line hybrid],
        optional_fine_grained_profiles: %w[expression argument_list hash_literal_pair],
        child_ordering_strategies: %w[destination_order successor_constraints pcs_like_triples],
        public_contract_level: 'ruleset_and_fixture',
        default_surface: 'owner',
        backend_strategy_choices: %w[entity_level ast_level line_level hybrid],
        reconstruction_policy: {
          preserve_original_text_unless_backend_declares_renderer: true,
          conflict_marker_placement_requires_text_boundary: true,
          risky_reconstruction_outcome: 'fallback_or_scoped_conflict'
        }
      }
    end

    def ruby_ast_node_merge_candidate_report(surface:, base:, template:, destination:, reconstruction_risk: false)
      {
        surface: surface,
        strategy_profile: ruby_ast_node_merge_strategy_profile.fetch(:profile_id),
        candidate_strategy: reconstruction_risk ? 'fallback_or_scoped_conflict' : 'hybrid_ast_node_merge',
        owner_level_fallback_too_blunt: !reconstruction_risk,
        successor_ordering_available: true,
        pcs_like_strategy_available: true,
        public_contract_level: 'ruleset_and_fixture',
        backend_strategy_choices: ruby_ast_node_merge_strategy_profile.fetch(:backend_strategy_choices),
        inputs: {
          base: base,
          template: template,
          destination: destination
        },
        reconstruction: {
          risky: reconstruction_risk,
          outcome: reconstruction_risk ? 'fallback_or_scoped_conflict' : 'preserve_original_text_boundaries'
        },
        diagnostics: [
          {
            severity: reconstruction_risk ? 'warning' : 'info',
            category: reconstruction_risk ? 'ast_node_reconstruction_risk' : 'ast_node_merge_candidate',
            message: if reconstruction_risk
                       'Ruby AST-node merge candidate has ambiguous whitespace, comment, or marker ' \
                       'reconstruction boundaries.'
                     else
                       'Ruby AST-node merge candidate can be considered when owner-level fallback would be too blunt.'
                     end
          }
        ]
      }
    end

    def ruby_vcs_tool_integration_profile
      {
        profile_id: 'ruby-vcs-tool-integration',
        hosts: {
          git_merge_driver: {
            contract: 'git_merge_driver',
            placeholders: %w[%O %A %B %P],
            output_target: '%A',
            standard_marker_modes: %w[diff3 zdiff3 merge],
            marker_size: 'host_provided'
          },
          jujutsu_merge_tool: {
            contract: 'jj_merge_tool',
            roles: %w[base left right output path],
            output_target: 'output',
            standard_marker_modes: %w[diff3 merge],
            marker_size: 'host_provided'
          }
        },
        enhanced_markers: {
          optional: true,
          requires_host_tolerance: true,
          default: 'standard_markers'
        },
        audit_artifact: {
          enabled: true,
          formats: %w[json],
          fields: %w[host operation path fallback_reason validation_warnings conflict_kind timeout_ms]
        },
        resource_budget: {
          timeout_ms: 5000,
          timeout_outcome: 'fallback_or_driver_error',
          cannot_hang_vcs_operation: true
        },
        diagnostics: %w[
          structured_merge_skipped
          fallback_activated
          driver_invocation_error
          tool_invocation_error
          timeout_or_resource_budget
        ]
      }
    end

    def ruby_vcs_tool_invocation_report(host:, event:, path:, timeout_ms: 5000)
      severity = event.to_s.end_with?('error') ? 'error' : 'warning'

      {
        host: host,
        event: event,
        path: path,
        integration_profile: ruby_vcs_tool_integration_profile.fetch(:profile_id),
        marker_mode: 'standard_markers',
        marker_size: 'host_provided',
        audit_artifact: {
          format: 'json',
          required: true
        },
        timeout_ms: timeout_ms,
        resource_budget_enforced: true,
        diagnostics: [
          {
            severity: severity,
            category: event,
            message: "Ruby #{host} integration reported #{event} for #{path}."
          }
        ]
      }
    end

    def ruby_silent_data_loss_validation_report(template_source:, destination_source:, output:)
      significant_inputs = {
        template: significant_source_lines(template_source),
        destination: significant_source_lines(destination_source)
      }
      output_lines = significant_source_lines(output).to_h { |line| [line, true] }
      missing = significant_inputs.flat_map do |side, lines|
        lines.reject { |line| output_lines[line] }.map do |line|
          {
            side: side.to_s,
            line: line,
            check: 'branch_added_significant_lines_preserved'
          }
        end
      end

      {
        ok: missing.empty?,
        validation_profile: ruby_post_merge_validation_profile.fetch(:profile_id),
        failures: missing,
        outcome: missing.empty? ? 'accepted' : 'hard_diagnostic_failure',
        diagnostics: if missing.empty?
                       []
                     else
                       [
                         {
                           severity: 'error',
                           category: 'silent_data_loss_prevention',
                           message: 'Ruby post-merge validation detected significant input lines missing from output.'
                         }
                       ]
                     end
      }
    end

    def ruby_fallback_scope_guard_report(requested_scope:, declared_scope:)
      widened = ruby_fallback_scope_rank(requested_scope) > ruby_fallback_scope_rank(declared_scope)
      {
        requested_scope: requested_scope,
        declared_scope: declared_scope,
        widened: widened,
        activated: !widened,
        diagnostics: [
          {
            severity: widened ? 'error' : 'info',
            category: widened ? 'fallback_scope_widening_rejected' : 'fallback_scope_accepted',
            message: if widened
                       "Ruby fallback cannot widen from #{declared_scope} to #{requested_scope} without an " \
                       'explicit policy.'
                     else
                       'Ruby fallback scope is within the declared policy.'
                     end
          }
        ]
      }
    end

    def ruby_interstitial_merge_policy_profile
      {
        policy_id: 'ruby-source-interstitial-merge',
        separates_owner_merge: true,
        region_kinds: %w[file_header file_footer container_header container_footer between],
        owner_adjacency_fields: %w[previous_owner next_owner],
        rules: [
          {
            region_kind: 'require',
            ordering: 'destination_order_then_template_additions',
            duplicate_key: 'require_path'
          },
          {
            region_kind: 'blank_line',
            ownership: 'preserve_declared_region_owner'
          },
          {
            region_kind: 'comment',
            attachment: 'nearest_declared_owner_or_standalone'
          }
        ]
      }
    end

    def ruby_child_group_profile
      {
        profile_id: 'ruby-source-child-groups',
        groups: [
          {
            owner_kind: 'class',
            child_group: 'methods',
            ordering: 'policy_ordered',
            ordering_policy: DEFAULT_METHOD_MOVE_POLICY,
            commutative: false,
            visibility_sections: %w[public protected private]
          },
          {
            owner_kind: 'class',
            child_group: 'constants',
            ordering: 'destination_order_then_template_additions',
            commutative: false
          },
          {
            owner_kind: 'module',
            child_group: 'declarations',
            ordering: 'destination_order_then_template_additions',
            commutative: false
          }
        ],
        diagnostics: [
          {
            severity: 'info',
            category: 'ruby_child_group_profile',
            message: 'Ruby child groups preserve destination order unless an explicit policy says otherwise.'
          }
        ]
      }
    end

    def ruby_interstitial_comment_attachment_report(source)
      lines = normalize_source(source).lines(chomp: true)
      owners = top_level_source_region_owners(lines)
      source_comment_block_attachment_report(
        lines: lines,
        owners: owners,
        comment_line: method(:comment_line?)
      )
    end

    def ruby_blank_line_ownership_report(source)
      regions = ruby_source_regions(source)[:regions]
      {
        blank_line_regions: source_blank_line_ownership_regions(regions: regions)
      }
    end

    def ruby_rename_detection_policy_profile
      {
        policy_id: 'ruby-source-rename-detection',
        capability: {
          name: 'rename_detection',
          enabled: true,
          default_enabled: false,
          explicit: true
        },
        signals: %w[body_hash_with_owner_name_normalization structural_hash token_similarity parent_scope_similarity
                    backend_native_move_metadata],
        clean_rename_confidence: 'content_hash',
        conflict_policy: 'report_rename_plus_edit'
      }
    end

    def ruby_rename_detection(template_source, destination_source)
      template_methods = ruby_method_identity_entries(template_source)
      destination_methods = ruby_method_identity_entries(destination_source)
      destination_by_parent_and_body = destination_methods.group_by do |entry|
        [entry[:parent_scope], entry[:normalized_body_identity]]
      end
      destination_signature_keys = destination_methods.to_h do |entry|
        [[entry[:parent_scope], entry[:signature]], true]
      end
      matched_destination_addresses = {}

      renames = template_methods.filter_map do |template_entry|
        next if destination_signature_keys[[template_entry[:parent_scope], template_entry[:signature]]]

        destination_entry = destination_by_parent_and_body.fetch(
          [template_entry[:parent_scope], template_entry[:normalized_body_identity]],
          []
        ).find { |entry| entry[:signature] != template_entry[:signature] }
        next unless destination_entry

        matched_destination_addresses[destination_entry[:address]] = true
        {
          from_address: template_entry[:address],
          to_address: destination_entry[:address],
          from_name: template_entry[:signature],
          to_name: destination_entry[:signature],
          parent_scope: template_entry[:parent_scope],
          confidence: 'content_hash',
          signals: %w[body_hash_with_owner_name_normalization parent_scope_similarity],
          clean_rename: true
        }
      end

      {
        policy: ruby_rename_detection_policy_profile,
        renames: renames,
        diagnostics: if renames.empty?
                       []
                     else
                       [
                         {
                           severity: 'info',
                           category: 'ruby_rename_detection',
                           message: 'Ruby rename detection is explicit and reports clean same-parent method renames ' \
                                    'by normalized body hash.'
                         }
                       ]
                     end,
        unmatched_destination: destination_methods.reject do |entry|
          matched_destination_addresses[entry[:address]]
        end.map { |entry| entry[:address] }
      }
    end

    def ruby_rename_plus_edit_conflicts(base_source, template_source, destination_source)
      base_methods = ruby_method_identity_entries(base_source)
      template_methods = ruby_method_identity_entries(template_source)
      destination_methods = ruby_method_identity_entries(destination_source)
      template_by_parent = template_methods.group_by { |entry| entry[:parent_scope] }
      destination_by_parent = destination_methods.group_by { |entry| entry[:parent_scope] }

      conflicts = base_methods.filter_map do |base_entry|
        template_candidates = template_by_parent.fetch(base_entry[:parent_scope], []).reject do |entry|
          entry[:signature] == base_entry[:signature]
        end
        destination_candidates = destination_by_parent.fetch(base_entry[:parent_scope], []).reject do |entry|
          entry[:signature] == base_entry[:signature]
        end
        next if template_candidates.empty? || destination_candidates.empty?

        template_candidate = template_candidates.first
        destination_candidate = destination_candidates.first
        next if template_candidate[:signature] == destination_candidate[:signature]

        {
          base_address: base_entry[:address],
          template_address: template_candidate[:address],
          destination_address: destination_candidate[:address],
          parent_scope: base_entry[:parent_scope],
          conflict_kind: 'rename_plus_edit',
          fallback_scope: 'owned_region',
          confidence: 'unresolved',
          diagnostics: [
            'both branches renamed the same Ruby owner differently',
            'method body identity changed on at least one side'
          ]
        }
      end

      {
        policy: ruby_rename_detection_policy_profile,
        conflicts: conflicts,
        diagnostics: if conflicts.empty?
                       []
                     else
                       [
                         {
                           severity: 'warning',
                           category: 'ruby_rename_plus_edit_conflict',
                           message: 'Ruby rename detection found incompatible rename-plus-edit changes.'
                         }
                       ]
                     end
      }
    end

    def ruby_cross_container_method_move_detection(template_source, destination_source)
      template_methods = ruby_method_identity_entries(template_source)
      destination_methods = ruby_method_identity_entries(destination_source)
      destination_by_signature_and_body = destination_methods.group_by do |entry|
        [entry[:signature], entry[:normalized_body_identity]]
      end

      moves = template_methods.filter_map do |template_entry|
        destination_entry = destination_by_signature_and_body.fetch(
          [template_entry[:signature], template_entry[:normalized_body_identity]],
          []
        ).find { |entry| entry[:parent_scope] != template_entry[:parent_scope] }
        next unless destination_entry

        {
          from_address: template_entry[:address],
          to_address: destination_entry[:address],
          from_parent_scope: template_entry[:parent_scope],
          to_parent_scope: destination_entry[:parent_scope],
          signature: template_entry[:signature],
          moved: true,
          move_kind: 'cross_container',
          ordering_policy: DEFAULT_METHOD_MOVE_POLICY,
          preserves_destination_order: true,
          confidence: 'content_hash'
        }
      end

      {
        capability: {
          name: 'move_detection',
          enabled: true,
          default_enabled: false,
          requires_stable_node_identity: true
        },
        moves: moves,
        diagnostics: if moves.empty?
                       []
                     else
                       [
                         {
                           severity: 'info',
                           category: 'ruby_cross_container_method_move',
                           message: 'Ruby detected same-signature method movement across containers while preserving ' \
                                    'destination order.'
                         }
                       ]
                     end
      }
    end

    def apply_ruby_delegated_child_outputs(source, delegated_operations, apply_plan, applied_children)
      lines = normalize_source(source).split("\n")
      operations_by_id = delegated_operations.to_h { |operation| [operation[:operation_id], operation] }
      outputs_by_id = applied_children.to_h { |entry| [entry[:operation_id], entry[:output]] }

      replacements = apply_plan[:entries].filter_map do |entry|
        operation = operations_by_id[entry.dig(:delegated_group, :child_operation_id)]
        output = outputs_by_id[entry.dig(:delegated_group, :child_operation_id)]
        span = operation&.dig(:surface, :span)
        next if operation.nil? || output.nil? || span.nil?

        { start: span[:start_line] - 1, finish: span[:end_line] - 1, output: output }
      end

      replacements.sort_by { |entry| -entry[:start] }.each do |entry|
        prefix = comment_prefix_for(lines[entry[:start]])
        replacement_lines = if entry[:output].empty?
                              []
                            else
                              entry[:output].sub(/\n\z/, '').split("\n").map do |line|
                                "#{prefix}#{line}"
                              end
                            end
        lines[entry[:start]..entry[:finish]] = replacement_lines
      end

      {
        ok: true,
        diagnostics: [],
        output: "#{lines.join("\n").sub(/\n+\z/, '')}\n",
        policies: [DESTINATION_WINS_ARRAY_POLICY]
      }
    end

    def merge_ruby_with_nested_outputs(template_source, destination_source, dialect, nested_outputs)
      Ast::Merge.execute_nested_merge(
        nested_outputs,
        default_family: 'ruby',
        request_id_prefix: 'nested_ruby_child',
        merge_parent: -> { merge_ruby(template_source, destination_source, dialect) },
        discover_operations: lambda { |merged_output|
          analysis = parse_ruby(merged_output, dialect)
          next { ok: false, diagnostics: analysis[:diagnostics] || [] } unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: ruby_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, applied_children|
          apply_ruby_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            applied_children
          )
        }
      )
    end

    def merge_ruby_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state,
                                                applied_children)
      Ast::Merge.execute_reviewed_nested_merge(
        review_state,
        'ruby',
        applied_children,
        merge_parent: -> { merge_ruby(template_source, destination_source, dialect) },
        discover_operations: lambda { |merged_output|
          analysis = parse_ruby(merged_output, dialect)
          next({ ok: false, diagnostics: analysis[:diagnostics] || [] }) unless analysis[:ok]

          {
            ok: true,
            diagnostics: [],
            operations: ruby_delegated_child_operations(analysis[:analysis])
          }
        },
        apply_resolved_outputs: lambda { |merged_output, operations, apply_plan, resolved_children|
          apply_ruby_delegated_child_outputs(
            merged_output,
            operations,
            apply_plan,
            resolved_children
          )
        }
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect,
                                                                   replay_bundle)
      execution = Array(replay_bundle[:reviewed_nested_executions]).find { |entry| entry[:family] == 'ruby' }
      unless execution
        return { ok: false,
                 diagnostics: [
                   {
                     severity: 'error',
                     category: 'configuration_error',
                     message: 'review replay bundle does not include a reviewed nested execution for ruby.'
                   }
                 ], policies: [] }
      end

      merge_ruby_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        execution[:review_state],
        execution[:applied_children]
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect,
                                                                  review_state)
      execution = Array(review_state[:reviewed_nested_executions]).find { |entry| entry[:family] == 'ruby' }
      unless execution
        return { ok: false,
                 diagnostics: [
                   {
                     severity: 'error',
                     category: 'configuration_error',
                     message: 'review state does not include a reviewed nested execution for ruby.'
                   }
                 ], policies: [] }
      end

      merge_ruby_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        execution[:review_state],
        execution[:applied_children]
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source,
                                                                            dialect, envelope)
      replay_bundle, import_error = Ast::Merge.import_review_replay_bundle_envelope(envelope)
      if import_error
        return { ok: false,
                 diagnostics: [
                   { severity: 'error', category: import_error[:category], message: import_error[:message] }
                 ], policies: [] }
      end

      merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source,
                                                                           dialect, envelope)
      review_state, import_error = Ast::Merge.import_conformance_manifest_review_state_envelope(envelope)
      if import_error
        return { ok: false,
                 diagnostics: [
                   { severity: 'error', category: import_error[:category], message: import_error[:message] }
                 ], policies: [] }
      end

      merge_ruby_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state
      )
    end

    def analyze_ruby_document(source, process_analysis: nil)
      lines = normalize_source(source).split("\n", -1)
      requires = ruby_analysis_require_owners(source, process_analysis)
      discovered_surfaces = []
      pending_comments = []

      lines.each_with_index do |line, index|
        line_number = index + 1
        stripped = line.strip

        if comment_line?(line)
          pending_comments << { line: line_number, raw: line }
          next
        end

        if stripped.empty?
          pending_comments = []
          next
        end

        if ruby_process_import_item_at_line(process_analysis,
                                            line_number) || legacy_require_line?(line, process_analysis)
          pending_comments = []
          next
        end

        declaration = ruby_process_structure_item_at_line(process_analysis, line_number)
        declaration ||= declaration_for_line(line) if Array(process_analysis&.structure).empty?
        if declaration
          surfaces = surfaces_for_owner(
            owner_name: declaration[:name],
            comment_entries: pending_comments
          )
          discovered_surfaces.concat(surfaces)
          pending_comments = []
          next
        end

        pending_comments = []
      end

      declaration_entries = ruby_process_owner_entries(process_analysis)
      declaration_entries = legacy_ruby_analysis_owner_entries(source) if declaration_entries.empty?
      declarations = declaration_entries.map do |entry|
        {
          path: entry[:path],
          owner_kind: 'declaration',
          match_key: entry[:name]
        }
      end

      {
        kind: 'ruby',
        dialect: 'ruby',
        root_kind: 'document',
        source: normalize_source(source),
        tree_haver_process_analysis: process_analysis,
        owners: (requires + declarations).sort_by { |owner| owner[:path] },
        discovered_surfaces: discovered_surfaces,
        method_shadowing: ruby_method_shadowing(source),
        diagnostics: ruby_method_shadowing_diagnostics(source)
      }
    end

    def collect_ruby_preamble(source)
      lines = normalize_source(source).split("\n")
      preamble = []
      lines.each do |line|
        break unless line.strip.empty? || comment_line?(line)

        preamble << line.rstrip
      end
      preamble.join("\n").strip
    end

    def ruby_file_footer_text(source)
      regions = ruby_source_regions(source).fetch(:regions)
      footer = regions.reverse.find do |region|
        region[:region_kind] == 'interstitial' && region[:position] == 'file_footer'
      end
      content = footer.to_h.fetch(:content, '').strip
      return '' if content.empty?

      content.lines.any? { |line| !line.strip.empty? && !comment_line?(line) } ? '' : content
    end

    def collect_parse_errors(node)
      raise TreeHaver::NotAvailable, 'Ruby parse returned no root node' unless node
      return unless node.respond_to?(:has_error?) && node.has_error?

      raise TreeHaver::NotAvailable,
            'Ruby parse contains syntax errors'
    end

    def parse_failure_result(error)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: error.message }],
        policies: []
      }
    end

    def ruby_process_analysis_from_tree(source, root_node)
      structure = []
      imports = []

      ruby_named_children(root_node).each do |node|
        case node.type
        when 'call'
          import = ruby_import_item_from_node(source, node)
          imports << import if import
        when 'if_modifier'
          import = ruby_import_item_from_modifier_node(source, node)
          imports << import if import
        when 'begin'
          import = ruby_import_item_from_begin_node(source, node)
          imports << import if import
        when 'class', 'module', 'method', 'singleton_method'
          item = ruby_structure_item_from_node(source, node)
          structure << item if item
        end
      end

      TslpProcessAnalysis.new(structure: structure, imports: imports)
    end

    def ruby_import_item_from_node(source, node)
      children = ruby_named_children(node)
      callee = children.first
      return unless callee && %w[identifier method_identifier].include?(callee.type)

      name = ruby_node_text(source, callee)
      return unless %w[require require_relative].include?(name)

      string_node = ruby_first_descendant(node) do |child|
        %w[string_content simple_symbol].include?(child.type)
      end
      return unless string_node

      TslpImportItem.new(source: ruby_node_text(source, string_node), span: ruby_import_span_for(source, node))
    end

    def ruby_import_item_from_modifier_node(source, node)
      call_node = ruby_named_children(node).first
      return unless call_node&.type == 'call'

      import = ruby_import_item_from_node(source, call_node)
      return unless import

      TslpImportItem.new(source: import.source, span: ruby_import_span_for(source, node))
    end

    def ruby_import_item_from_begin_node(source, node)
      children = ruby_named_children(node)
      call_imports = children.filter_map do |child|
        ruby_import_item_from_node(source, child) if child.type == 'call'
      end
      return if call_imports.empty?

      unsupported = children.any? do |child|
        child.type != 'call' && !ruby_load_error_rescue_node?(source, child)
      end
      return if unsupported

      TslpImportItem.new(source: call_imports.map(&:source).join(','), span: ruby_span_for(node))
    end

    def ruby_load_error_rescue_node?(source, node)
      return false unless node.type == 'rescue'
      return false unless ruby_named_children(node).all? { |child| child.type == 'exceptions' }

      ruby_node_text(source, node).match?(/\Arescue\s+LoadError\b/)
    end

    def ruby_structure_item_from_node(source, node)
      kind = case node.type
             when 'class'
               'class'
             when 'module'
               'module'
             when 'method', 'singleton_method'
               'method'
             end
      return unless kind

      name_node = ruby_declaration_name_node(node)
      return unless name_node

      TslpStructureItem.new(kind: kind, name: ruby_node_text(source, name_node), span: ruby_span_for(node))
    end

    def ruby_declaration_name_node(node)
      case node.type
      when 'class', 'module'
        ruby_named_children(node).find do |child|
          %w[constant scope_resolution].include?(child.type)
        end
      when 'method'
        ruby_named_children(node).find do |child|
          %w[identifier method_identifier operator].include?(child.type)
        end
      when 'singleton_method'
        children = ruby_named_children(node)
        children.reverse.find do |child|
          %w[identifier method_identifier operator].include?(child.type)
        end
      end
    end

    def ruby_first_descendant(node, &block)
      ruby_named_children(node).each do |child|
        return child if yield(child)

        descendant = ruby_first_descendant(child, &block)
        return descendant if descendant
      end
      nil
    end

    def ruby_named_children(node)
      node.children.select { |child| !child.respond_to?(:named?) || child.named? }
    end

    def ruby_span_for(node)
      start_point = node.start_point
      end_point = node.end_point
      TslpSpan.new(
        start_row: start_point.fetch(:row),
        start_col: start_point.fetch(:column),
        end_row: end_point.fetch(:row),
        end_col: end_point.fetch(:column)
      )
    end

    def ruby_import_span_for(source, node)
      span = ruby_span_for(node)
      lines = normalize_source(source).split("\n")
      start_row = span.start_row
      end_row = span.end_row

      start_row -= 1 while start_row.positive? && coverage_directive_comment_line?(lines[start_row - 1])
      end_row += 1 while end_row < lines.length - 1 && coverage_directive_comment_line?(lines[end_row + 1])

      TslpSpan.new(
        start_row: start_row,
        start_col: start_row == span.start_row ? span.start_col : 0,
        end_row: end_row,
        end_col: end_row == span.end_row ? span.end_col : lines[end_row].to_s.length
      )
    end

    def coverage_directive_comment_line?(line)
      BlockDirectiveDetector.coverage_directive_line?(line)
    end

    def ruby_node_text(source, node)
      source[node.start_byte...node.end_byte].to_s
    end

    def ruby_fallback_scope_rank(scope)
      ruby_fallback_policy_profile.fetch(:scopes).index(scope.to_s) || Float::INFINITY
    end

    def stable_owner_signatures(owner_identities)
      owner_identities.map do |identity|
        {
          owner_kind: identity.fetch(:owner_kind),
          owner_name: identity.fetch(:owner_name),
          parent_scope: identity.fetch(:parent_scope),
          structural_identity: identity.fetch(:structural_identity),
          occurrence_index: identity.fetch(:occurrence_index)
        }
      end
    end

    def significant_source_lines(source)
      normalize_source(source).lines.map(&:strip).reject do |line|
        line.empty? || line.start_with?('#') || line == 'end'
      end
    end

    def merge_ruby_requires(destination_requires, template_requires)
      destination_paths = destination_requires.to_h { |entry| [entry[:path], true] }
      destination_requires + template_requires.reject { |entry| destination_paths[entry[:path]] }
    end

    def ruby_tslp_merge_context(analysis, role:)
      source = analysis.fetch(:source)
      process_analysis = analysis[:tree_haver_process_analysis]
      unsupported_lines = ruby_tslp_unsupported_top_level_lines(source, process_analysis)
      unless unsupported_lines.empty?
        return unsupported_feature_result(
          "ruby-merge can only merge TSLP-record-backed top-level Ruby declarations and imports; #{role} has " \
          "unsupported top-level content on line(s) #{unsupported_lines.join(', ')}. Use a native Ruby provider " \
          'for native Ruby merging, or report missing Ruby process records to tree-sitter-language-pack.'
        )
      end

      {
        ok: true,
        source: source,
        preamble: ruby_tslp_file_preamble_text(source, process_analysis),
        requires: ruby_process_import_entries(source, process_analysis),
        declarations: collect_ruby_declaration_entries(source, process_analysis: process_analysis),
        footer: ruby_tslp_file_footer_text(source, process_analysis)
      }
    end

    def ruby_tslp_unsupported_top_level_lines(source, process_analysis)
      lines = normalize_source(source).split("\n", -1)
      claimed = ruby_tslp_claimed_line_indexes(lines, process_analysis)
      lines.each_index.filter_map do |index|
        next if claimed.include?(index)

        line = lines[index]
        next if line.strip.empty? || comment_line?(line)

        index + 1
      end
    end

    def ruby_tslp_claimed_line_indexes(lines, process_analysis)
      claimed = Set.new
      ruby_top_level_process_structure_items(process_analysis).each do |item|
        start_index = attached_comment_start_index(lines, item.span.start_row)
        (start_index..item.span.end_row).each { |line_index| claimed.add(line_index) }
      end
      Array(process_analysis&.imports).each do |item|
        (item.span.start_row..item.span.end_row).each { |line_index| claimed.add(line_index) }
      end
      claimed
    end

    def ruby_process_import_entries(source, process_analysis)
      lines = normalize_source(source).split("\n")
      Array(process_analysis&.imports).map do |item|
        text = lines[item.span.start_row..item.span.end_row].to_a.join("\n").rstrip
        {
          path: "/requires/#{item.source}",
          text: text,
          start_index: item.span.start_row,
          end_index: item.span.end_row
        }
      end
    end

    def ruby_analysis_require_owners(source, process_analysis)
      imports = Array(process_analysis&.imports)
      unless imports.empty?
        return imports.each_with_index.map do |item, index|
          {
            path: "/requires/#{index}",
            owner_kind: 'require',
            match_key: item.source.to_s
          }
        end
      end

      return [] if process_analysis

      legacy_ruby_require_owners(source)
    end

    def legacy_ruby_require_owners(source)
      requires = []
      normalize_source(source).split("\n").each do |line|
        match = REQUIRE_PATTERN.match(line)
        next unless match

        requires << {
          path: "/requires/#{requires.length}",
          owner_kind: 'require',
          match_key: match[1]
        }
      end
      requires
    end

    def ruby_process_import_item_at_line(process_analysis, line_number)
      index = line_number.to_i - 1
      Array(process_analysis&.imports).find do |item|
        item.span.start_row <= index && item.span.end_row >= index
      end
    end

    def legacy_require_line?(line, process_analysis)
      return false if process_analysis

      REQUIRE_PATTERN.match?(line)
    end

    def ruby_tslp_file_footer_text(source, process_analysis)
      lines = normalize_source(source).split("\n")
      claimed = ruby_tslp_claimed_line_indexes(lines, process_analysis)
      footer_indexes = []
      (lines.length - 1).downto(0) do |index|
        break if claimed.include?(index)
        break unless lines[index].strip.empty? || comment_line?(lines[index])

        footer_indexes.unshift(index)
      end
      lines.values_at(*footer_indexes).join("\n").strip
    end

    def ruby_tslp_file_preamble_text(source, process_analysis)
      lines = normalize_source(source).split("\n")
      claimed = ruby_tslp_claimed_line_indexes(lines, process_analysis)
      preamble_indexes = []
      lines.each_index do |index|
        break if claimed.include?(index)
        break unless lines[index].strip.empty? || comment_line?(lines[index])

        preamble_indexes << index
      end
      lines.values_at(*preamble_indexes).join("\n").strip
    end

    def collect_ruby_declaration_entries(source, process_analysis: nil)
      process_entries = ruby_process_declaration_entries(source, process_analysis: process_analysis)
      return process_entries unless process_entries.empty?

      legacy_collect_ruby_declaration_entries(source)
    end

    def legacy_collect_ruby_declaration_entries(source)
      # TSLP process records are the preferred substrate. This legacy scanner is
      # retained only for direct helper calls that do not have parser analysis.
      # Main merge paths must pass process_analysis and fail closed when TSLP
      # cannot provide readable structure records.
      lines = normalize_source(source).split("\n")
      entries = []
      pending_comments = []
      index = 0

      while index < lines.length
        line = lines[index]
        stripped = line.strip

        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        if REQUIRE_PATTERN.match?(line)
          pending_comments = []
          index += 1
          next
        end

        declaration = declaration_for_line(line)
        unless declaration
          pending_comments = []
          index += 1
          next
        end

        start_index = pending_comments.first || index
        depth = 1
        cursor = index + 1
        while cursor < lines.length
          candidate = lines[cursor].strip
          depth += 1 if declaration_for_line(candidate)
          if candidate == 'end'
            depth -= 1
            if depth.zero?
              cursor += 1
              break
            end
          end
          cursor += 1
        end

        entries << {
          path: "/declarations/#{declaration[:name]}",
          name: declaration[:name],
          kind: declaration[:kind],
          merge_key: "#{declaration[:kind]}:#{declaration[:name]}",
          text: lines[start_index...cursor].join("\n").strip
        }
        pending_comments = []
        index = cursor
      end

      entries
    end

    def legacy_ruby_analysis_owner_entries(source)
      normalize_source(source).split("\n").filter_map do |line|
        declaration = declaration_for_line(line)
        next unless declaration

        {
          path: "/declarations/#{declaration[:name]}",
          name: declaration[:name],
          kind: declaration[:kind],
          merge_key: "#{declaration[:kind]}:#{declaration[:name]}"
        }
      end
    end

    def ruby_process_owner_entries(process_analysis)
      Array(process_analysis&.structure).filter_map do |item|
        kind = ruby_process_owner_kind(item)
        name = item.name.to_s
        next if kind.to_s.empty? || name.empty?

        {
          path: "/declarations/#{name}",
          name: name,
          kind: kind,
          merge_key: "#{kind}:#{name}"
        }
      end
    end

    def ruby_process_declaration_entries(source, process_analysis: nil)
      items = ruby_top_level_process_structure_items(process_analysis)
      return [] if items.empty?

      lines = normalize_source(source).split("\n")
      items.map do |item|
        start_index = attached_comment_start_index(lines, item.span.start_row)
        finish_index = item.span.end_row
        kind = ruby_process_structure_kind(item)
        name = item.name.to_s
        {
          path: "/declarations/#{name}",
          name: name,
          kind: kind,
          merge_key: "#{kind}:#{name}",
          text: lines[start_index..finish_index].to_a.join("\n").strip,
          start_index: start_index,
          end_index: finish_index
        }
      end
    end

    def ruby_top_level_section(text, entries)
      positioned_entries = entries.select do |entry|
        entry[:start_index].is_a?(Integer) && entry[:end_index].is_a?(Integer)
      end
      return { text: text } if positioned_entries.empty?

      {
        text: text,
        start_index: positioned_entries.map { |entry| entry[:start_index] }.min,
        end_index: positioned_entries.map { |entry| entry[:end_index] }.max
      }
    end

    def emit_ruby_top_level_sections(destination_source, sections)
      lines = normalize_source(destination_source).split("\n", -1)
      emitted = sections.reject { |section| section[:text].to_s.strip.empty? }
      previous = nil
      output = +''

      emitted.each do |section|
        output << ruby_top_level_section_separator(lines, previous, section) if previous
        output << section.fetch(:text).strip
        previous = section
      end

      "#{output.strip}\n"
    end

    def ruby_top_level_section_separator(lines, previous, current)
      return "\n\n" unless previous[:end_index].is_a?(Integer) && current[:start_index].is_a?(Integer)
      return "\n\n" unless current[:start_index] > previous[:end_index]

      gap = lines[(previous[:end_index] + 1)...current[:start_index]].to_a
      return "\n\n" if gap.empty?

      "\n#{gap.join("\n")}\n"
    end

    def ruby_top_level_process_structure_items(process_analysis)
      items = Array(process_analysis&.structure).select do |item|
        ruby_process_structure_kind(item) && !item.name.to_s.empty?
      end
      items.reject do |item|
        items.any? do |candidate|
          next false if candidate.equal?(item)

          candidate.span.start_row <= item.span.start_row &&
            candidate.span.end_row >= item.span.end_row &&
            (candidate.span.start_row < item.span.start_row || candidate.span.end_row > item.span.end_row)
        end
      end.sort_by { |item| [item.span.start_row, item.span.start_col] }
    end

    def ruby_process_structure_item_at_line(process_analysis, line_number)
      Array(process_analysis&.structure).find do |item|
        ruby_process_owner_kind(item) &&
          item.span.start_row == line_number - 1
      end&.then do |item|
        { kind: ruby_process_owner_kind(item), name: item.name.to_s }
      end
    end

    def ruby_process_owner_kind(item)
      case item.kind.to_s
      when 'class'
        'class'
      when 'module'
        'module'
      when 'method', 'function'
        'def'
      end
    end

    def ruby_process_structure_kind(item)
      case item.kind.to_s
      when 'class'
        'class'
      when 'module'
        'module'
      when 'method', 'function'
        'def'
      end
    end

    def attached_comment_start_index(lines, declaration_index)
      index = declaration_index.to_i
      index -= 1 while index.positive? && comment_line?(lines[index - 1])
      index
    end

    def merge_ruby_declaration_entry(template_entry, destination_entry)
      return destination_entry unless template_entry

      merged_text = merge_declaration_hash_constants(template_entry[:text], destination_entry[:text])
      merged_text = merge_declaration_body_constants(template_entry[:text], merged_text)
      merged_text = merge_declaration_body_methods(template_entry[:text], merged_text)
      merged_text = merge_nested_body_declarations(template_entry[:text], merged_text)
      destination_entry.merge(
        text: merged_text
      )
    end

    def ruby_intra_owner_merge_plan(template_entries, destination_entries)
      template_by_key = template_entries.to_h { |entry| [entry[:merge_key], entry] }
      destination_entries.flat_map do |destination_entry|
        template_entry = template_by_key[destination_entry[:merge_key]]
        next [] unless template_entry
        next [] unless %w[class module].include?(destination_entry[:kind])

        template_methods = direct_body_method_entries(template_entry[:text]).to_h { |entry| [entry[:signature], entry] }
        direct_body_method_entries(destination_entry[:text]).filter_map do |destination_method|
          template_method = template_methods[destination_method[:signature]]
          next unless template_method
          next if template_method[:body_text] == destination_method[:body_text]

          {
            owner_path: destination_entry[:path],
            owner_kind: destination_entry[:kind],
            owner_name: destination_entry[:name],
            child_group: 'methods',
            child_signature: destination_method[:signature],
            child_path: "#{destination_entry[:path]}/methods/#{destination_method[:signature]}",
            decision: 'destination_wins',
            scope: 'owner_body'
          }
        end
      end
    end

    def ruby_namespace_form_conflicts(template_entries, destination_entries)
      destination_names = destination_entries.to_h do |entry|
        ["#{entry[:kind]}:#{entry[:name]}", true]
      end
      template_entries.flat_map do |entry|
        direct_body_declaration_entries(entry[:text]).filter_map do |nested_entry|
          compact_key = "#{nested_entry[:kind]}:#{entry[:name]}::#{nested_entry[:name]}"
          next unless destination_names[compact_key]

          "#{entry[:name]}::#{nested_entry[:name]}"
        end
      end.uniq
    end

    def source_owner_identity_entry(kind:, name:, parent_scope:, address:, content:)
      normalized_kind = kind.to_s
      normalized_name = name.to_s
      {
        owner_kind: normalized_kind,
        owner_name: normalized_name,
        parent_scope: parent_scope,
        address: address,
        structural_identity: "#{parent_scope}:#{normalized_kind}:#{normalized_name}",
        content_identity: "sha256:#{Digest::SHA256.hexdigest(content.to_s)}",
        identity_components: %w[owner_kind owner_name parent_scope content_identity]
      }
    end

    def add_source_owner_occurrence_indexes(identities)
      counters = Hash.new(0)
      identities.map do |identity|
        occurrence_index = counters[identity[:structural_identity]]
        counters[identity[:structural_identity]] += 1
        identity.merge(
          occurrence_index: occurrence_index,
          address: occurrence_index.zero? ? identity[:address] : "#{identity[:address]}[#{occurrence_index}]"
        )
      end
    end

    def ruby_method_identity_entries(source)
      collect_ruby_declaration_entries(source).flat_map do |declaration_entry|
        direct_body_method_entries(declaration_entry[:text]).map do |method_entry|
          {
            parent_scope: declaration_entry[:path],
            signature: method_entry[:signature],
            address: "#{declaration_entry[:path]}/methods/#{method_entry[:signature]}",
            normalized_body_identity: normalized_method_body_identity(method_entry[:body_text])
          }
        end
      end
    end

    def normalized_method_body_identity(body_text)
      normalized_lines = body_text.to_s.lines.map.with_index do |line, index|
        index.zero? && DEF_PATTERN.match?(line) ? "#{line[/\A\s*/]}def __owner_name__\n" : line
      end
      "sha256:#{Digest::SHA256.hexdigest(normalized_lines.join)}"
    end

    def ruby_method_shadowing(source)
      collect_ruby_declaration_entries(source).flat_map do |entry|
        direct_method_shadowing(entry)
      end
    end

    def ruby_method_shadowing_diagnostics(source)
      ruby_method_shadowing(source).map do |entry|
        {
          severity: 'warning',
          category: 'ruby_method_shadowing',
          path: "#{entry[:owner_path]}/methods/#{entry[:method_signature]}",
          message: "Ruby method #{entry[:method_signature]} is defined #{entry[:shadowed_count] + 1} times in " \
                   "#{entry[:owner_path]}; the last definition shadows earlier definitions."
        }
      end
    end

    def direct_method_shadowing(declaration_entry)
      grouped = direct_body_method_entries(declaration_entry[:text])
                .each_with_index
                .group_by do |(method_entry, _index)|
        method_entry[:signature]
      end

      grouped.filter_map do |signature, entries|
        next if entries.length < 2

        {
          owner_path: declaration_entry[:path],
          method_signature: signature,
          effective_index: entries.last[1],
          shadowed_indices: entries[0...-1].map { |_method_entry, index| index },
          shadowed_count: entries.length - 1
        }
      end
    end

    def ruby_method_projection(source, revision:)
      collect_ruby_declaration_entries(source).flat_map do |declaration_entry|
        direct_body_method_entries(declaration_entry[:text]).each_with_index.map do |method_entry, index|
          signature = "method:#{declaration_entry[:path]}:#{method_entry[:signature]}"
          {
            path: "#{declaration_entry[:path]}/methods/#{index}",
            parent_path: "#{declaration_entry[:path]}/methods",
            node_id: "#{revision}:#{signature}",
            signature: signature,
            index: index
          }
        end
      end
    end

    def qualified_nested_declaration_entries(entries)
      entries.flat_map do |entry|
        direct_body_declaration_entries(entry[:text]).map do |nested_entry|
          root_name = entry[:name]
          nested_name = nested_entry[:name]
          qualified_name = nested_name.include?('::') ? nested_name : "#{root_name}::#{nested_name}"
          nested_entry.merge(
            name: qualified_name,
            path: "/declarations/#{qualified_name}",
            merge_key: "#{nested_entry[:kind]}:#{qualified_name}",
            text: normalize_declaration_text_indent(nested_entry[:text]),
            namespace_root_merge_key: entry[:merge_key]
          )
        end
      end
    end

    def normalize_declaration_text_indent(text)
      lines = text.to_s.split("\n")
      base_indent = lines.first.to_s[/\A\s*/].to_s
      return text if base_indent.empty?

      lines.map do |line|
        line.start_with?(base_indent) ? line[base_indent.length..].to_s : line
      end.join("\n")
    end

    def namespace_wrapper_matched?(entry, candidates, matched)
      children = candidates.select { |candidate| candidate[:namespace_root_merge_key] == entry[:merge_key] }
      return false if children.empty?
      unless direct_body_method_entries(entry[:text]).empty? && direct_body_constant_entries(entry[:text]).empty?
        return false
      end

      children.all? { |child| matched[child[:merge_key]] }
    end

    def merge_declaration_hash_constants(template_text, destination_text)
      template_blocks = constant_hash_blocks(template_text).to_h { |block| [block[:constant], block] }
      destination_blocks = constant_hash_blocks(destination_text)
      return destination_text if template_blocks.empty? || destination_blocks.empty?

      output = destination_text.dup
      destination_blocks.reverse_each do |destination_block|
        template_block = template_blocks[destination_block[:constant]]
        next unless template_block

        template_hash = RubyHashLiteralProjector.new(template_block[:hash_source]).call
        destination_hash = RubyHashLiteralProjector.new(destination_block[:hash_source]).call
        merged_hash = merge_ruby_hash_literals(template_hash, destination_hash)
        rendered = "#{destination_block[:prefix]}#{render_ruby_hash_literal(merged_hash,
                                                                            destination_block[:base_indent])}"
        output[destination_block[:range]] = rendered
      rescue ArgumentError
        next
      end
      output
    end

    def merge_declaration_body_constants(template_text, destination_text)
      template_constants = direct_body_constant_entries(template_text)
      destination_constants = direct_body_constant_entries(destination_text)
      return destination_text if template_constants.empty?

      merged_text = merge_matched_array_constants(template_constants, destination_constants, destination_text)
      destination_names = destination_constants.map { |entry| entry[:name] }.to_h { |name| [name, true] }
      missing_constants = template_constants.reject { |entry| destination_names[entry[:name]] }
      return merged_text if missing_constants.empty?

      insert_declaration_body_blocks(merged_text, missing_constants.map do |entry|
        entry[:text]
      end, placement: :after_opening)
    end

    def merge_matched_array_constants(template_constants, destination_constants, destination_text)
      template_by_name = template_constants.to_h { |entry| [entry[:name], entry] }
      output = destination_text.dup
      destination_constants.reverse_each do |destination_entry|
        template_entry = template_by_name[destination_entry[:name]]
        next unless template_entry

        merged_text = merge_array_constant_text(template_entry[:text], destination_entry[:text])
        next unless merged_text

        output[destination_entry[:range]] = merged_text
      end
      output
    end

    def merge_array_constant_text(template_text, destination_text)
      template_match = template_text.match(/\A(\s*[A-Z]\w*\s*=\s*)\[(.*)\]\z/)
      destination_match = destination_text.match(/\A(\s*[A-Z]\w*\s*=\s*)\[(.*)\]\z/)
      unless template_match && destination_match
        return merge_percent_array_constant_text(template_text, destination_text) ||
               merge_multiline_array_constant_text(template_text, destination_text)
      end

      destination_elements = split_ruby_array_elements(destination_match[2])
      template_elements = split_ruby_array_elements(template_match[2])
      destination_keys = destination_elements.map do |element|
        normalize_array_element_key(element)
      end.to_h { |key| [key, true] }
      appended = template_elements.reject { |element| destination_keys[normalize_array_element_key(element)] }
      return destination_text if appended.empty?

      "#{destination_match[1]}[#{(destination_elements + appended).join(', ')}]"
    end

    def merge_percent_array_constant_text(template_text, destination_text)
      template_match = parse_percent_array_constant_text(template_text)
      destination_match = parse_percent_array_constant_text(destination_text)
      return unless template_match && destination_match

      destination_elements = destination_match[:body].split(/\s+/).reject(&:empty?)
      template_elements = template_match[:body].split(/\s+/).reject(&:empty?)
      destination_keys = destination_elements.to_h { |element| [element, true] }
      appended = template_elements.reject { |element| destination_keys[element] }
      return destination_text if appended.empty?

      "#{destination_match[:prefix]}#{(destination_elements + appended).join(' ')}#{destination_match[:closing]}"
    end

    def parse_percent_array_constant_text(text)
      match = text.match(/\A(?<head>\s*[A-Z]\w*\s*=\s*%[wWiI])(?<opening>[^\s[:alnum:]])(?<content>.*)\z/)
      return unless match

      closing = PERCENT_ARRAY_DELIMITER_PAIRS.fetch(match[:opening], match[:opening])
      content = match[:content]
      return unless content.end_with?(closing)

      {
        prefix: "#{match[:head]}#{match[:opening]}",
        body: content[0...-closing.length],
        closing: closing
      }
    end

    def merge_multiline_array_constant_text(template_text, destination_text)
      template_match = template_text.match(/\A(\s*[A-Z]\w*\s*=\s*\[\n)(.*)(\n\s*\])\z/m)
      destination_match = destination_text.match(/\A(\s*[A-Z]\w*\s*=\s*\[\n)(.*)(\n\s*\])\z/m)
      return unless template_match && destination_match

      destination_elements = multiline_array_elements(destination_match[2])
      template_elements = multiline_array_elements(template_match[2])
      destination_keys = destination_elements.map do |element|
        normalize_array_element_key(element[:value])
      end.to_h { |key| [key, true] }
      appended = template_elements.reject { |element| destination_keys[normalize_array_element_key(element[:value])] }
      return destination_text if appended.empty?

      insertion_prefix = destination_elements.last&.dig(:indent) || template_elements.first&.dig(:indent) || '  '
      body = append_multiline_array_elements(destination_match[2], appended, insertion_prefix)
      "#{destination_match[1]}#{body}#{destination_match[3]}"
    end

    def merge_declaration_body_methods(template_text, destination_text)
      template_methods = direct_body_method_entries(template_text)
      destination_methods = direct_body_method_entries(destination_text)
      return destination_text if template_methods.empty?

      destination_method_signatures = destination_methods.map do |entry|
        entry[:signature]
      end.to_h { |signature| [signature, true] }
      missing_methods = template_methods.reject { |entry| destination_method_signatures[entry[:signature]] }
      return destination_text if missing_methods.empty?

      public_methods, visibility_methods = missing_methods.partition { |entry| entry[:visibility] == 'public' }
      merged_text = destination_text
      unless public_methods.empty?
        merged_text = insert_declaration_body_blocks(
          merged_text,
          public_methods.map { |entry| entry[:body_text] },
          before_visibility: !direct_visibility_section_present?(merged_text, 'public')
        )
      end
      visibility_methods.group_by { |entry| entry[:visibility] }.each do |visibility, entries|
        blocks = if direct_visibility_section_present?(merged_text, visibility)
                   merged_text = insert_declaration_body_blocks(merged_text, entries.map do |entry|
                     entry[:body_text]
                   end, before_visibility: false)
                   next
                 else
                   entries.map { |entry| entry[:text] }
                 end
        merged_text = insert_declaration_body_blocks(merged_text, blocks)
      end
      merged_text
    end

    def merge_nested_body_declarations(template_text, destination_text)
      template_entries = direct_body_declaration_entries(template_text)
      destination_entries = direct_body_declaration_entries(destination_text)
      return destination_text if template_entries.empty? || destination_entries.empty?

      template_by_path = template_entries.to_h { |entry| [entry[:merge_key], entry] }
      output = destination_text.dup
      destination_entries.reverse_each do |destination_entry|
        template_entry = template_by_path[destination_entry[:merge_key]]
        next unless template_entry

        output[destination_entry[:range]] = merge_ruby_declaration_entry(template_entry, destination_entry)[:text]
      end

      destination_paths = destination_entries.map { |entry| entry[:merge_key] }.to_h { |path| [path, true] }
      missing_entries = template_entries.reject { |entry| destination_paths[entry[:merge_key]] }
      return output if missing_entries.empty?

      insert_declaration_body_blocks(output, missing_entries.map { |entry| entry[:text] })
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
        policies: []
      }
    end

    def normalize_method_move_policy(policy)
      normalized = policy.to_s.strip
      normalized = DEFAULT_METHOD_MOVE_POLICY if normalized.empty?
      return normalized if normalized == DEFAULT_METHOD_MOVE_POLICY

      raise ArgumentError, "Unsupported Ruby method move policy #{policy.inspect}"
    end

    private

    def top_level_source_region_owners(lines)
      owners = []
      pending_comments = []
      index = 0

      while index < lines.length
        line = lines[index]
        stripped = line.strip

        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        if (match = REQUIRE_PATTERN.match(line))
          require_path = match[1]
          owners << {
            region_id: "require:#{require_path}",
            region_kind: 'owner',
            owner_kind: 'require',
            address: "/requires/#{require_path}",
            match_key: require_path,
            start_index: index,
            end_index: index,
            span: source_report_line_span(index, index),
            content: source_report_region_content(lines, index, index)
          }
          pending_comments = []
          index += 1
          next
        end

        declaration = declaration_for_line(line)
        if declaration
          start_index = pending_comments.first || index
          finish_index = ruby_block_finish_index(lines, index)
          address = if declaration[:kind] == 'def'
                      "/methods/#{declaration[:name]}"
                    else
                      "/declarations/#{declaration[:name]}"
                    end
          owner = {
            region_id: "#{declaration[:kind] == 'def' ? 'method' : 'declaration'}:#{declaration[:name]}",
            region_kind: 'owner',
            owner_kind: declaration[:kind],
            address: address,
            match_key: declaration[:name],
            start_index: start_index,
            declaration_start_index: index,
            end_index: finish_index,
            span: source_report_line_span(start_index, finish_index),
            declaration_span: source_report_line_span(index, finish_index),
            content: source_report_region_content(lines, start_index, finish_index)
          }
          if %w[class module].include?(declaration[:kind])
            owner[:child_regions] = container_child_source_regions(lines, declaration, index, finish_index)
          end
          attached_comments = source_attached_comment_regions_for_report(
            lines: lines,
            start_index: start_index,
            declaration_index: index
          )
          owner[:attached_comments] = attached_comments unless attached_comments.empty?
          owners << owner
          pending_comments = []
          index = finish_index + 1
          next
        end

        pending_comments = []
        index += 1
      end

      owners
    end

    def container_child_source_regions(lines, declaration, declaration_index, finish_index)
      owners = []
      pending_comments = []
      index = declaration_index + 1

      while index < finish_index
        line = lines[index]
        stripped = line.strip

        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        nested_declaration = declaration_for_line(line)
        if nested_declaration && %w[class module].include?(nested_declaration[:kind])
          pending_comments = []
          index = ruby_block_finish_index(lines, index) + 1
          next
        end

        method = DEF_PATTERN.match(line)
        unless method
          pending_comments = []
          index += 1
          next
        end

        start_index = pending_comments.first || index
        method_finish_index = ruby_block_finish_index(lines, index)
        method_name = method[2]
        owner = {
          region_id: "method:#{declaration[:name]}##{method_name}",
          region_kind: 'owner',
          owner_kind: 'method',
          address: "/declarations/#{declaration[:name]}/methods/#{method_name}",
          match_key: method_name,
          start_index: start_index,
          end_index: method_finish_index,
          span: source_report_line_span(start_index, method_finish_index),
          content: source_report_region_content(lines, start_index, method_finish_index)
        }
        owner[:declaration_span] = source_report_line_span(index, method_finish_index) if start_index != index
        attached_comments = source_attached_comment_regions_for_report(
          lines: lines,
          start_index: start_index,
          declaration_index: index
        )
        owner[:attached_comments] = attached_comments unless attached_comments.empty?
        owners << owner
        pending_comments = []
        index = method_finish_index + 1
      end

      source_interleaved_regions_for_report(
        lines: lines,
        owners: owners,
        container_name: declaration[:name],
        container_start_index: declaration_index,
        container_end_index: finish_index
      )
    end

    def compact_region(region)
      region.reject { |_key, value| value.nil? }
    end

    RubyHashNode = Struct.new(:pairs, :inline, :trailing_comma, keyword_init: true)
    RubyHashPair = Struct.new(:key, :key_source, :delimiter, :value, keyword_init: true)
    RubyScalarNode = Struct.new(:source, keyword_init: true)

    # Projects Ruby hash literals into source-preserving merge nodes.
    class RubyHashLiteralProjector
      def initialize(source)
        @source = source.to_s
      end

      def call
        tree = TreeHaver.parser_for(:ruby, backend_type: :tree_sitter).parse(source)
        root = if tree.respond_to?(:parse_result)
                 tree.parse_result.value
               else
                 tree.root_node
               end
        hash_node = root_hash_node(root)
        raise ArgumentError, 'expected Ruby hash literal' unless hash_node?(hash_node)

        project_hash_node(hash_node)
      end

      private

      attr_reader :source

      def root_hash_node(root)
        return root if hash_node?(root)
        return root.statements&.body&.first if root.respond_to?(:statements)

        child_nodes(root).find { |child| hash_node?(child) }
      end

      def hash_node?(node)
        %w[hash hash_node].include?(node&.type.to_s)
      end

      def project_hash_node(node)
        pairs = hash_pair_nodes(node).map do |assoc|
          key_node, value_node = hash_pair_key_value_nodes(assoc)
          key = project_hash_key(key_node, hash_pair_operator(assoc))
          RubyHashPair.new(
            key: key.fetch(:key),
            key_source: key.fetch(:key_source),
            delimiter: key.fetch(:delimiter),
            value: project_hash_value(value_node)
          )
        end
        RubyHashNode.new(
          pairs: pairs,
          inline: !node_source(node).include?("\n"),
          trailing_comma: trailing_comma?(node)
        )
      end

      def project_hash_value(node)
        return project_hash_node(node) if hash_node?(node)

        RubyScalarNode.new(source: node_source(node).rstrip)
      end

      def project_hash_key(key_node, operator)
        delimiter = operator.to_s == '=>' ? '=>' : ':'
        if delimiter == ':'
          {
            key: hash_key_value(key_node),
            key_source: node_source(key_node).delete_suffix(':'),
            delimiter: delimiter
          }
        elsif %w[symbol_node simple_symbol].include?(key_node.type.to_s) && node_source(key_node).start_with?(':')
          {
            key: hash_key_value(key_node),
            key_source: node_source(key_node),
            delimiter: delimiter
          }
        elsif %w[string_node string].include?(key_node.type.to_s)
          {
            key: hash_key_value(key_node),
            key_source: node_source(key_node),
            delimiter: delimiter
          }
        else
          {
            key: hash_key_value(key_node),
            key_source: node_source(key_node),
            delimiter: delimiter
          }
        end
      end

      def hash_pair_nodes(node)
        return Array(node.elements) if node.respond_to?(:elements)

        child_nodes(node).select { |child| child.type.to_s == 'pair' }
      end

      def hash_pair_key_value_nodes(pair)
        return [pair.key, pair.value] if pair.respond_to?(:key) && pair.respond_to?(:value)

        named = child_nodes(pair).reject { |child| punctuation_node?(child) }
        [named.first, named.last]
      end

      def hash_pair_operator(pair)
        return pair.operator if pair.respond_to?(:operator)

        all_child_nodes(pair).find { |child| %w[: =>].include?(child.type.to_s) }&.type
      end

      def hash_key_value(node)
        return node.unescaped.to_s if node.respond_to?(:unescaped)

        text = node_source(node)
        return text.delete_prefix(':') if text.start_with?(':')
        return text[1...-1] if node.type.to_s == 'string' && text.match?(/\A(["']).*\1\z/m)

        text
      end

      def trailing_comma?(node)
        if node.respond_to?(:elements) && node.respond_to?(:closing_loc)
          return trailing_comma_between?(last_child_end: Array(node.elements).last.location.end_offset,
                                         closing_start: node.closing_loc.start_offset)
        end

        last_pair = hash_pair_nodes(node).last
        closing = all_child_nodes(node).reverse.find { |child| child.type.to_s == '}' }
        return false unless last_pair && closing

        trailing_comma_between?(last_child_end: node_end_offset(last_pair), closing_start: node_start_offset(closing))
      end

      def trailing_comma_between?(last_child_end:, closing_start:)
        source.byteslice(last_child_end...closing_start).to_s.include?(',')
      end

      def child_nodes(node)
        if node.respond_to?(:compact_child_nodes)
          node.compact_child_nodes
        elsif node.respond_to?(:named_children)
          node.named_children
        elsif node.respond_to?(:children)
          node.children
        else
          []
        end
      end

      def all_child_nodes(node)
        if node.respond_to?(:compact_child_nodes)
          node.compact_child_nodes
        elsif node.respond_to?(:children)
          node.children
        else
          child_nodes(node)
        end
      end

      def punctuation_node?(node)
        %w[{ } : => ,].include?(node.type.to_s)
      end

      def node_source(node)
        return node.slice.to_s if node.respond_to?(:slice)
        return node.text.to_s if node.respond_to?(:text)

        source.byteslice(node_start_offset(node)...node_end_offset(node)).to_s
      end

      def node_start_offset(node)
        return node.location.start_offset if node.respond_to?(:location)
        return node.start_byte if node.respond_to?(:start_byte)

        raise ArgumentError, 'Ruby hash node does not expose a start offset'
      end

      def node_end_offset(node)
        return node.location.end_offset if node.respond_to?(:location)
        return node.end_byte if node.respond_to?(:end_byte)

        raise ArgumentError, 'Ruby hash node does not expose an end offset'
      end
    end

    def constant_hash_blocks(text)
      lines = text.to_s.split("\n", -1)
      line_start_offsets = []
      offset = 0
      lines.each do |line|
        line_start_offsets << offset
        offset += line.length + 1
      end

      blocks = []
      index = 0
      while index < lines.length
        line = lines[index]
        match = CONSTANT_HASH_ASSIGNMENT_PATTERN.match(line)
        unless match
          index += 1
          next
        end

        start_line = index
        finish_line = hash_assignment_finish_line(lines, start_line)
        if finish_line
          block_source = lines[start_line..finish_line].join("\n")
          hash_offset = block_source.index('{')
          start_offset = line_start_offsets[start_line]
          finish_offset = line_start_offsets[finish_line] + lines[finish_line].length
          blocks << {
            constant: match[2],
            prefix: block_source[0...hash_offset],
            hash_source: block_source[hash_offset..],
            base_indent: match[1].length,
            range: (start_offset...finish_offset)
          }
          index = finish_line + 1
        else
          index += 1
        end
      end
      blocks
    end

    def hash_assignment_finish_line(lines, start_line)
      depth = 0
      in_string = nil
      escape = false
      start_line.upto(lines.length - 1) do |line_index|
        lines[line_index].each_char do |char|
          if in_string
            if escape
              escape = false
            elsif char == '\\'
              escape = true
            elsif char == in_string
              in_string = nil
            end
            next
          end

          if ['"', "'"].include?(char)
            in_string = char
          elsif char == '{'
            depth += 1
          elsif char == '}'
            depth -= 1
            return line_index if depth.zero?
          end
        end
      end
      nil
    end

    def direct_body_method_entries(text)
      lines = text.to_s.split("\n")
      return [] if lines.length < 3

      entries = []
      pending_comments = []
      current_visibility = 'public'
      visibility_start_index = nil
      visibility_consumed = false
      index = 1
      while index < lines.length - 1
        line = lines[index]
        stripped = line.strip
        if comment_line?(line)
          pending_comments << index
          index += 1
          next
        end

        if stripped.empty?
          pending_comments = []
          index += 1
          next
        end

        if %w[private protected public].include?(stripped)
          current_visibility = stripped
          visibility_start_index = index
          visibility_consumed = false
          pending_comments = []
          index += 1
          next
        end

        nested_declaration = declaration_for_line(line)
        if nested_declaration && %w[class module].include?(nested_declaration[:kind])
          pending_comments = []
          index = ruby_block_finish_index(lines, index) + 1
          next
        end

        match = DEF_PATTERN.match(line)
        unless match
          pending_comments = []
          index += 1
          next
        end

        start_index = pending_comments.first || visibility_section_start_index(visibility_start_index,
                                                                               visibility_consumed) || index
        finish_index = ruby_block_finish_index(lines, index)
        entries << {
          name: match[2],
          signature: SignatureSupport.textual_method_signature(match[1], match[2]),
          visibility: current_visibility,
          text: lines[start_index..finish_index].join("\n").rstrip,
          body_text: lines[(pending_comments.first || index)..finish_index].join("\n").rstrip
        }
        pending_comments = []
        visibility_consumed = true
        index = finish_index + 1
      end
      entries
    end

    def direct_body_constant_entries(text)
      lines = text.to_s.split("\n")
      return [] if lines.length < 3

      line_start_offsets = []
      offset = 0
      lines.each do |line|
        line_start_offsets << offset
        offset += line.length + 1
      end

      entries = []
      index = 1
      while index < lines.length - 1
        stripped = lines[index].strip
        if stripped.empty? || comment_line?(lines[index])
          index += 1
          next
        end

        nested_declaration = declaration_for_line(lines[index])
        if nested_declaration && %w[class module].include?(nested_declaration[:kind])
          index = ruby_block_finish_index(lines, index) + 1
          next
        end

        match = CONSTANT_ASSIGNMENT_PATTERN.match(lines[index])
        unless match
          index += 1
          next
        end

        finish_index = constant_assignment_finish_index(lines, index)
        entries << {
          name: match[2],
          text: lines[index..finish_index].join("\n").rstrip,
          range: (line_start_offsets[index]...(line_start_offsets[finish_index] + lines[finish_index].length))
        }
        index = finish_index + 1
      end
      entries
    end

    def split_ruby_array_elements(source)
      elements = []
      start_index = 0
      string_quote = nil
      escape = false
      source.each_char.with_index do |char, index|
        if string_quote
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == string_quote
            string_quote = nil
          end
          next
        end

        if ['"', "'"].include?(char)
          string_quote = char
        elsif char == ','
          elements << source[start_index...index].strip
          start_index = index + 1
        end
      end
      elements << source[start_index..].to_s.strip
      elements.reject(&:empty?)
    end

    def normalize_array_element_key(element)
      element.to_s.strip
    end

    def multiline_array_elements(source)
      source.to_s.lines.filter_map do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?('#')

        {
          indent: line[/\A\s*/],
          value: stripped.sub(/,\z/, '')
        }
      end
    end

    def append_multiline_array_elements(destination_body, appended, insertion_prefix)
      body_lines = destination_body.to_s.lines.map(&:chomp)
      element_indexes = body_lines.each_index.select do |index|
        stripped = body_lines[index].strip
        !stripped.empty? && !stripped.start_with?('#')
      end
      trailing_comma = element_indexes.empty? || body_lines[element_indexes.last].strip.end_with?(',')

      if trailing_comma
        insertion_lines = appended.map { |element| "#{insertion_prefix}#{element[:value]}," }
        return "#{destination_body.rstrip}\n#{insertion_lines.join("\n")}"
      end

      body_lines[element_indexes.last] = "#{body_lines[element_indexes.last]},"
      insertion_lines = appended.each_with_index.map do |element, index|
        suffix = index == appended.length - 1 ? '' : ','
        "#{insertion_prefix}#{element[:value]}#{suffix}"
      end
      "#{body_lines.join("\n").rstrip}\n#{insertion_lines.join("\n")}"
    end

    def constant_assignment_finish_index(lines, index)
      return hash_assignment_finish_line(lines, index) || index if lines[index].include?('{')
      return array_assignment_finish_line(lines, index) || index if lines[index].include?('[')

      index
    end

    def array_assignment_finish_line(lines, start_line)
      depth = 0
      in_string = nil
      escape = false
      start_line.upto(lines.length - 1) do |line_index|
        lines[line_index].each_char do |char|
          if in_string
            if escape
              escape = false
            elsif char == '\\'
              escape = true
            elsif char == in_string
              in_string = nil
            end
            next
          end

          if ['"', "'"].include?(char)
            in_string = char
          elsif char == '['
            depth += 1
          elsif char == ']'
            depth -= 1
            return line_index if depth.zero?
          end
        end
      end
      nil
    end

    def visibility_section_start_index(index, consumed)
      return if consumed

      index
    end

    def direct_body_declaration_entries(text)
      lines = text.to_s.split("\n")
      return [] if lines.length < 3

      line_start_offsets = []
      offset = 0
      lines.each do |line|
        line_start_offsets << offset
        offset += line.length + 1
      end

      entries = []
      index = 1
      while index < lines.length - 1
        declaration = declaration_for_line(lines[index].strip)
        unless declaration && %w[class module].include?(declaration[:kind])
          index += 1
          next
        end

        finish_index = ruby_block_finish_index(lines, index)
        start_offset = line_start_offsets[index]
        finish_offset = line_start_offsets[finish_index] + lines[finish_index].length
        entries << {
          path: "/declarations/#{declaration[:name]}",
          name: declaration[:name],
          kind: declaration[:kind],
          merge_key: "#{declaration[:kind]}:#{declaration[:name]}",
          text: lines[index..finish_index].join("\n").rstrip,
          range: (start_offset...finish_offset)
        }
        index = finish_index + 1
      end
      entries
    end

    def declaration_closing_end_index(lines)
      depth = 0
      lines.each_with_index do |line, index|
        stripped = line.strip
        depth += 1 if declaration_for_line(stripped)
        depth -= 1 if stripped == 'end'
        return index if depth.zero? && index.positive?
      end
      nil
    end

    def insert_declaration_body_blocks(destination_text, blocks, before_visibility: true, placement: :before_closing)
      lines = destination_text.to_s.split("\n")
      closing_index = declaration_closing_end_index(lines)
      return destination_text unless closing_index

      insertion_index = if placement == :after_opening
                          1
                        elsif before_visibility
                          direct_visibility_section_index(lines, closing_index) || closing_index
                        else
                          closing_index
                        end
      insertion = []
      insertion << '' unless insertion_index == 1 || lines[insertion_index - 1].to_s.strip.empty?
      insertion.concat(blocks.join("\n\n").split("\n"))
      insertion << '' if insertion_index != closing_index && !lines[insertion_index].to_s.strip.empty?
      lines.insert(insertion_index, *insertion)
      "#{lines.join("\n").sub(/\n+\z/, '')}\n".chomp
    end

    def direct_visibility_section_present?(text, visibility)
      lines = text.to_s.split("\n")
      closing_index = declaration_closing_end_index(lines)
      return false unless closing_index

      find_direct_visibility_section_index(lines, closing_index, visibility: visibility)
    end

    def direct_visibility_section_index(lines, closing_index)
      find_direct_visibility_section_index(lines, closing_index, visibility: nil)
    end

    def find_direct_visibility_section_index(lines, closing_index, visibility:)
      depth = 1
      1.upto(closing_index - 1) do |index|
        stripped = lines[index].strip
        visibility_match = visibility ? stripped == visibility : %w[private protected].include?(stripped)
        return index if depth == 1 && visibility_match

        depth += 1 if declaration_for_line(stripped)
        depth -= 1 if stripped == 'end'
      end
      nil
    end

    def merge_ruby_hash_literals(template, destination)
      destination_by_key = destination.pairs.to_h { |pair| [pair.key, pair] }
      merged_pairs = template.pairs.map do |template_pair|
        destination_pair = destination_by_key[template_pair.key]
        if destination_pair.nil?
          template_pair
        elsif template_pair.value.is_a?(RubyHashNode) && destination_pair.value.is_a?(RubyHashNode)
          RubyHashPair.new(
            key: template_pair.key,
            key_source: destination_pair.key_source,
            delimiter: destination_pair.delimiter,
            value: merge_ruby_hash_literals(template_pair.value, destination_pair.value)
          )
        else
          destination_pair
        end
      end
      template_keys = template.pairs.map(&:key).to_h { |key| [key, true] }
      merged_pairs.concat(destination.pairs.reject { |pair| template_keys[pair.key] })
      RubyHashNode.new(pairs: merged_pairs, inline: destination.inline, trailing_comma: destination.trailing_comma)
    end

    def render_ruby_hash_literal(node, base_indent)
      return node.source unless node.is_a?(RubyHashNode)
      return render_inline_ruby_hash_literal(node) if node.inline

      child_indent = base_indent + 2
      lines = node.pairs.each_with_index.map do |pair, index|
        suffix = index == node.pairs.length - 1 && !node.trailing_comma ? '' : ','
        "#{' ' * child_indent}#{render_ruby_hash_key(pair)} #{render_ruby_hash_literal(pair.value,
                                                                                       child_indent)}#{suffix}"
      end
      "{\n#{lines.join("\n")}\n#{' ' * base_indent}}"
    end

    def render_inline_ruby_hash_literal(node)
      inner = node.pairs.map do |pair|
        "#{render_ruby_hash_key(pair)} #{render_ruby_hash_literal(pair.value, 0)}"
      end.join(', ')
      inner = "#{inner}," if node.trailing_comma && !inner.empty?
      "{#{inner}}"
    end

    def render_ruby_hash_key(pair)
      delimiter = pair.delimiter == '=>' ? '=>' : ':'
      delimiter == '=>' ? "#{pair.key_source} =>" : "#{pair.key_source}:"
    end

    def comment_line?(line)
      line.lstrip.start_with?('#')
    end

    def declaration_for_line(line)
      if (match = CLASS_PATTERN.match(line))
        { kind: 'class', name: match[1] }
      elsif (match = MODULE_PATTERN.match(line))
        { kind: 'module', name: match[1] }
      elsif (match = DEF_PATTERN.match(line))
        { kind: 'def', name: match[2], signature: SignatureSupport.textual_method_signature(match[1], match[2]) }
      end
    end

    def ruby_block_finish_index(lines, start_index)
      depth = 0
      cursor = start_index
      while cursor < lines.length
        stripped = lines[cursor].strip
        depth += stripped.scan(/\bdo\b/).length
        depth += 1 if declaration_for_line(stripped) || stripped.match?(/\A(begin|if|unless|case|while|until|for)\b/)
        depth -= 1 if stripped == 'end'
        return cursor if depth <= 0 && cursor > start_index

        cursor += 1
      end
      lines.length - 1
    end

    def preceding_code_line_index(lines, start_index)
      start_index.downto(0) do |index|
        next if lines[index].strip.empty?

        return index
      end
      nil
    end

    def next_code_line_index(lines, start_index)
      start_index.upto(lines.length - 1) do |index|
        next if lines[index].strip.empty?

        return index
      end
      nil
    end

    def surfaces_for_owner(owner_name:, comment_entries:)
      filtered_entries = comment_entries.filter { |entry| doc_comment_content?(entry[:raw]) }
      return [] if filtered_entries.empty?

      start_line = filtered_entries.first[:line]
      end_line = filtered_entries.last[:line]
      doc_surface = Ast::Merge.discovered_surface(
        surface_kind: 'ruby_doc_comment',
        declared_language: 'yard',
        effective_language: 'yard',
        address: "document[0] > ruby_doc_comment[#{owner_name}]",
        parent_address: 'document[0]',
        owner: Ast::Merge.surface_owner_ref(kind: 'owned_region', address: "/declarations/#{owner_name}"),
        span: Ast::Merge.surface_span(start_line: start_line, end_line: end_line),
        reconstruction_strategy: 'rewrite_with_prefix_preservation',
        metadata: {
          owner_signature: owner_name,
          comment_prefix: comment_prefix_for(filtered_entries.first[:raw]),
          entries: filtered_entries.map { |entry| { line: entry[:line], raw: entry[:raw] } }
        }
      )

      [doc_surface] + example_surfaces_for(doc_surface)
    end

    def example_surfaces_for(surface)
      entries = Array(surface.dig(:metadata, :entries))
      DocCommentSupport.example_blocks(entries).map do |block|
        body_entries = block.fetch(:body_entries)
        declared_language = block.fetch(:declared_language) || 'ruby'
        Ast::Merge.discovered_surface(
          surface_kind: 'yard_example_block',
          declared_language: declared_language,
          effective_language: declared_language,
          address: "#{surface[:address]} > yard_example[#{block.fetch(:tag_index)}]",
          parent_address: surface[:address],
          owner: Ast::Merge.surface_owner_ref(kind: 'owned_region', address: surface[:address]),
          span: Ast::Merge.surface_span(start_line: body_entries.first[:line], end_line: body_entries.last[:line]),
          reconstruction_strategy: 'rewrite_with_prefix_preservation',
          metadata: {
            tag_kind: 'example',
            tag_index: block.fetch(:tag_index),
            tag_text: block.fetch(:tag_text),
            comment_prefix: surface.dig(:metadata, :comment_prefix)
          }
        )
      end
    end

    def next_tag_index(normalized_lines, start_index)
      DocCommentSupport.next_tag_index(normalized_lines, start_index)
    end

    def normalize_source(source)
      source.gsub(/\r\n?/, "\n")
    end

    def normalize_comment_content(raw)
      DocCommentSupport.normalize_comment_content(raw)
    end

    def doc_comment_content?(raw)
      DocCommentSupport.doc_comment_content?(raw)
    end

    def comment_prefix_for(raw)
      DocCommentSupport.comment_prefix_for(raw)
    end

    def declared_example_language(rest)
      DocCommentSupport.declared_example_language(rest)
    end

    module_function(
      :ruby_feature_profile,
      :available_ruby_backends,
      :ruby_tslp_capability_profile,
      :ruby_backend_feature_profile,
      :ruby_plan_context,
      :parse_ruby,
      :match_ruby_owners,
      :ruby_method_move_detection,
      :merge_ruby,
      :ruby_discovered_surfaces,
      :ruby_delegated_child_operations,
      :apply_ruby_delegated_child_outputs,
      :merge_ruby_with_reviewed_nested_outputs,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope,
      :merge_ruby_with_nested_outputs,
      :analyze_ruby_document,
      :collect_ruby_declaration_entries,
      :unsupported_feature_result
    )
    # rubocop:enable Style/MultilineBlockChain
    # rubocop:enable Metrics/ModuleLength, Metrics/PerceivedComplexity
    # rubocop:enable Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength
    # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/BlockNesting
  end
end

Ruby::Merge.register_backend!

TreeHaver::BackendRegistry.register_tag(
  :tslp_ruby_import_records,
  category: :capability,
  backend_name: :tslp_ruby_import_records
) do
  result = Ruby::Merge.parse_ruby("require \"json\"\n", 'ruby')
  result[:ok] && Array(result.dig(:analysis, :owners)).any? do |owner|
    owner[:owner_kind] == 'require' && owner[:match_key] == 'json'
  end
end

TreeHaver::BackendRegistry.register_tag(
  :tslp_ruby_top_level_call_records,
  category: :capability,
  backend_name: :tslp_ruby_top_level_call_records
) do
  template = <<~RUBY
    source "https://gem.coop"
    gemspec
    eval_gemfile "gemfiles/modular/style.gemfile"
    gem "rake"
  RUBY
  destination = <<~RUBY
    source "https://rubygems.org"
    gem "rspec"
    eval_gemfile "gemfiles/modular/style.gemfile"
  RUBY
  result = Ruby::Merge.merge_ruby(template, destination, 'ruby')
  result[:ok]
end

TreeHaver::BackendRegistry.register_tag(
  :tslp_ruby_namespace_form_equivalence,
  category: :capability,
  backend_name: :tslp_ruby_namespace_form_equivalence
) do
  template = Ruby::Merge.parse_ruby("module Admin\n  class User\n  end\nend\n", 'ruby')
  destination = Ruby::Merge.parse_ruby("class Admin::User\nend\n", 'ruby')
  template[:ok] && destination[:ok] && Ruby::Merge.ruby_namespace_form_conflicts(
    Ruby::Merge.send(:ruby_tslp_merge_context, template.fetch(:analysis), role: 'template').fetch(:declarations),
    Ruby::Merge.send(:ruby_tslp_merge_context, destination.fetch(:analysis), role: 'destination').fetch(:declarations)
  ).empty?
end
