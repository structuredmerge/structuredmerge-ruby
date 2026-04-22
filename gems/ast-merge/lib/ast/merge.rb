# frozen_string_literal: true

require "json"
require_relative "merge/version"

module Ast
  module Merge
    PACKAGE_NAME = "ast-merge"
    REVIEW_TRANSPORT_VERSION = 1

    module_function

    def conformance_family_entries(manifest, family)
      families = manifest.fetch(:families, {})
      (families[family.to_sym] || families[family.to_s] || []).map { |entry| deep_dup(entry) }
    end

    def conformance_fixture_path(manifest, family, role)
      entry = conformance_family_entries(manifest, family).find { |candidate| candidate[:role] == role }
      entry && deep_dup(entry[:path])
    end

    def conformance_family_feature_profile_path(manifest, family)
      entry = manifest.fetch(:family_feature_profiles, []).find { |candidate| candidate[:family] == family.to_s }
      entry && deep_dup(entry[:path])
    end

    def conformance_suite_definition(manifest, selector)
      manifest.fetch(:suite_descriptors, []).find do |definition|
        conformance_suite_selectors_equal?(
          { kind: definition[:kind], subject: deep_dup(definition[:subject]) },
          selector
        )
      end&.then { |definition| deep_dup(definition) }
    end

    def conformance_suite_selectors(manifest)
      manifest.fetch(:suite_descriptors, []).map do |definition|
        {
          kind: definition[:kind],
          subject: deep_dup(definition[:subject])
        }
      end.sort_by do |selector|
        [
          selector[:kind].to_s,
          selector.dig(:subject, :grammar).to_s,
          selector.dig(:subject, :variant).to_s
        ]
      end
    end

    def conformance_suite_descriptor_string(definition)
      JSON.generate(json_ready(definition))
    end

    def default_conformance_family_context(family_profile)
      { family_profile: deep_dup(family_profile) }
    end

    def review_request_id_for_family_context(family)
      "family_context:#{family}"
    end

    def conformance_review_host_hints(options)
      {
        interactive: options.fetch(:interactive, false),
        require_explicit_contexts: options.fetch(:require_explicit_contexts, false)
      }
    end

    def surface_owner_ref(kind:, address:)
      {
        kind: kind.to_s,
        address: address
      }
    end

    def surface_span(start_line:, end_line:)
      {
        start_line: start_line,
        end_line: end_line
      }
    end

    def discovered_surface(surface_kind:, effective_language:, address:, owner:, declared_language: nil,
      parent_address: nil, span: nil, reconstruction_strategy:, metadata: nil)
      surface = {
        surface_kind: surface_kind.to_s,
        effective_language: effective_language.to_s,
        address: address,
        owner: deep_dup(owner),
        reconstruction_strategy: reconstruction_strategy.to_s
      }
      surface[:declared_language] = declared_language.to_s if declared_language
      surface[:parent_address] = parent_address if parent_address
      surface[:span] = deep_dup(span) if span
      surface[:metadata] = deep_dup(metadata) if metadata
      surface
    end

    def delegated_child_operation(operation_id:, parent_operation_id:, requested_strategy:, language_chain:, surface:)
      {
        operation_id: operation_id,
        parent_operation_id: parent_operation_id,
        requested_strategy: requested_strategy.to_s,
        language_chain: deep_dup(language_chain),
        surface: deep_dup(surface)
      }
    end

    def projected_child_review_case(case_id:, parent_operation_id:, child_operation_id:, surface_path:,
      delegated_case_id:, delegated_apply_group:, delegated_runtime_surface_path:)
      {
        case_id: case_id,
        parent_operation_id: parent_operation_id,
        child_operation_id: child_operation_id,
        surface_path: surface_path,
        delegated_case_id: delegated_case_id,
        delegated_apply_group: delegated_apply_group,
        delegated_runtime_surface_path: delegated_runtime_surface_path
      }
    end

    def group_projected_child_review_cases(cases)
      groups = []

      cases.each do |entry|
        existing = groups.find { |group| group[:delegated_apply_group] == entry[:delegated_apply_group] }
        if existing
          existing[:case_ids] << entry[:case_id]
          existing[:delegated_case_ids] << entry[:delegated_case_id]
          next
        end

        groups << {
          delegated_apply_group: entry[:delegated_apply_group],
          parent_operation_id: entry[:parent_operation_id],
          child_operation_id: entry[:child_operation_id],
          delegated_runtime_surface_path: entry[:delegated_runtime_surface_path],
          case_ids: [entry[:case_id]],
          delegated_case_ids: [entry[:delegated_case_id]]
        }
      end

      groups
    end

    def summarize_projected_child_review_group_progress(groups, resolved_case_ids)
      groups.map do |group|
        resolved = group[:case_ids].select { |case_id| resolved_case_ids.include?(case_id) }
        pending = group[:case_ids].reject { |case_id| resolved_case_ids.include?(case_id) }

        {
          delegated_apply_group: group[:delegated_apply_group],
          parent_operation_id: group[:parent_operation_id],
          child_operation_id: group[:child_operation_id],
          delegated_runtime_surface_path: group[:delegated_runtime_surface_path],
          resolved_case_ids: resolved,
          pending_case_ids: pending,
          complete: pending.empty?
        }
      end
    end

    def select_projected_child_review_groups_ready_for_apply(groups, resolved_case_ids)
      groups.select do |group|
        group[:case_ids].all? { |case_id| resolved_case_ids.include?(case_id) }
      end
    end

    def review_request_id_for_projected_child_group(group)
      "projected_child_group:#{group[:delegated_apply_group]}"
    end

    def projected_child_group_review_request(group, family)
      {
        id: review_request_id_for_projected_child_group(group),
        kind: "delegated_child_group",
        family: family,
        message: "delegated child group #{group[:delegated_apply_group]} is ready to apply for #{family}.",
        blocking: true,
        delegated_group: deep_dup(group),
        action_offers: [
          { action: "apply_delegated_child_group", requires_context: false }
        ],
        default_action: "apply_delegated_child_group"
      }
    end

    def select_projected_child_review_groups_accepted_for_apply(groups, _family, decisions)
      accepted_request_ids = decisions
        .select { |decision| decision[:action] == "apply_delegated_child_group" }
        .map { |decision| decision[:request_id] }

      groups.select do |group|
        accepted_request_ids.include?(review_request_id_for_projected_child_group(group))
      end
    end

    def review_projected_child_groups(groups, family, decisions)
      request_ids = groups.map { |group| review_request_id_for_projected_child_group(group) }
      applied_decisions = []
      diagnostics = []

      decisions.each do |decision|
        next unless decision[:action] == "apply_delegated_child_group"

        if request_ids.include?(decision[:request_id])
          applied_decisions << deep_dup(decision)
        else
          diagnostics << diagnostic(
            "error",
            "replay_rejected",
            "review decision #{decision[:request_id]} does not match any current delegated child review request.",
            review: {
              request_id: decision[:request_id],
              action: decision[:action],
              reason: "request_not_found"
            }
          )
        end
      end

      accepted_groups = select_projected_child_review_groups_accepted_for_apply(
        groups,
        family,
        applied_decisions
      )
      accepted_request_ids = accepted_groups.map do |group|
        review_request_id_for_projected_child_group(group)
      end
      requests = groups.reject do |group|
        accepted_request_ids.include?(review_request_id_for_projected_child_group(group))
      end.map do |group|
        projected_child_group_review_request(group, family)
      end

      {
        requests: requests,
        accepted_groups: accepted_groups,
        applied_decisions: applied_decisions,
        diagnostics: diagnostics
      }
    end

    def delegated_child_apply_plan(state, family)
      entries = state.fetch(:accepted_groups, []).filter_map do |group|
        request_id = review_request_id_for_projected_child_group(group)
        decision = state.fetch(:applied_decisions, []).find do |candidate|
          candidate[:request_id] == request_id
        end
        next unless decision

        {
          request_id: request_id,
          family: family,
          delegated_group: deep_dup(group),
          decision: deep_dup(decision)
        }
      end

      { entries: entries }
    end

    def resolve_delegated_child_outputs(operations, nested_outputs, default_family:, request_id_prefix:)
      operations_by_surface_address = operations.each_with_object({}) do |operation, memo|
        memo[operation.dig(:surface, :address)] = operation
      end

      nested_outputs.each do |entry|
        next if operations_by_surface_address.key?(entry[:surface_address])

        return {
          ok: false,
          diagnostics: [
            diagnostic(
              "error",
              "configuration_error",
              "missing delegated child surface #{entry[:surface_address]}."
            )
          ]
        }
      end

      {
        ok: true,
        diagnostics: [],
        apply_plan: {
          entries: nested_outputs.each_with_index.map do |entry, index|
            operation = operations_by_surface_address.fetch(entry[:surface_address])
            request_id = "#{request_id_prefix}:#{index}"
            {
              request_id: request_id,
              family: operation.dig(:surface, :metadata, :family) || default_family,
              delegated_group: {
                delegated_apply_group: request_id,
                parent_operation_id: operation[:parent_operation_id],
                child_operation_id: operation[:operation_id],
                delegated_runtime_surface_path: entry[:surface_address],
                case_ids: [],
                delegated_case_ids: []
              },
              decision: {
                request_id: request_id,
                action: "apply_delegated_child_group"
              }
            }
          end
        },
        applied_children: nested_outputs.map do |entry|
          operation = operations_by_surface_address.fetch(entry[:surface_address])
          {
            operation_id: operation[:operation_id],
            output: entry[:output]
          }
        end
      }
    end

    def execute_nested_merge(nested_outputs, default_family:, request_id_prefix:, merge_parent:, discover_operations:, apply_resolved_outputs:)
      merged = merge_parent.call
      return merged unless merged[:ok] && merged.key?(:output)

      discovery = discover_operations.call(merged[:output])
      return { ok: false, diagnostics: discovery[:diagnostics] || [], policies: [] } unless discovery[:ok] && discovery[:operations]

      resolution = resolve_delegated_child_outputs(
        discovery[:operations],
        nested_outputs,
        default_family: default_family,
        request_id_prefix: request_id_prefix
      )
      return resolution.merge(policies: []) unless resolution[:ok]

      apply_resolved_outputs.call(
        merged[:output],
        discovery[:operations],
        resolution[:apply_plan],
        resolution[:applied_children]
      )
    end

    def execute_delegated_child_apply_plan(apply_plan, applied_children, merge_parent:, discover_operations:, apply_resolved_outputs:)
      merged = merge_parent.call
      return merged unless merged[:ok] && merged.key?(:output)

      discovery = discover_operations.call(merged[:output])
      return { ok: false, diagnostics: discovery[:diagnostics] || [], policies: [] } unless discovery[:ok] && discovery[:operations]

      apply_resolved_outputs.call(
        merged[:output],
        discovery[:operations],
        apply_plan,
        applied_children
      )
    end

    def execute_reviewed_nested_merge(review_state, family, applied_children, merge_parent:, discover_operations:, apply_resolved_outputs:)
      execute_delegated_child_apply_plan(
        delegated_child_apply_plan(review_state, family),
        applied_children,
        merge_parent: merge_parent,
        discover_operations: discover_operations,
        apply_resolved_outputs: apply_resolved_outputs
      )
    end

    def reviewed_nested_execution(family, review_state, applied_children)
      {
        family: family,
        review_state: deep_dup(review_state),
        applied_children: deep_dup(applied_children)
      }
    end

    def execute_reviewed_nested_execution(execution, merge_parent:, discover_operations:, apply_resolved_outputs:)
      execute_reviewed_nested_merge(
        execution[:review_state],
        execution[:family],
        execution[:applied_children],
        merge_parent: merge_parent,
        discover_operations: discover_operations,
        apply_resolved_outputs: apply_resolved_outputs
      )
    end

    def conformance_manifest_replay_context(manifest, options)
      seen = {}
      families = conformance_suite_selectors(manifest).filter_map do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)
        next if seen[family]

        seen[family] = true
        family
      end

      {
        surface: "conformance_manifest",
        families: families,
        require_explicit_contexts: options.fetch(:require_explicit_contexts, false)
      }
    end

    def review_replay_context_compatible(current, candidate)
      return false unless candidate

      current[:surface] == candidate[:surface] &&
        current[:require_explicit_contexts] == candidate[:require_explicit_contexts] &&
        current[:families] == candidate[:families]
    end

    def conformance_manifest_review_request_ids(manifest, options)
      return [] unless options.fetch(:require_explicit_contexts, false)

      seen = {}
      conformance_suite_selectors(manifest).filter_map do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)
        next if seen[family]

        seen[family] = true
        contexts = options.fetch(:contexts, {})
        family_profiles = options.fetch(:family_profiles, {})
        next if contexts.key?(family.to_sym) || contexts.key?(family)
        next unless family_profiles.key?(family.to_sym) || family_profiles.key?(family)

        review_request_id_for_family_context(family)
      end
    end

    def review_replay_bundle_inputs(options)
      if options[:review_replay_bundle]
        bundle = options[:review_replay_bundle]
        [bundle[:replay_context], bundle[:decisions] || []]
      else
        [options[:review_replay_context], options[:review_decisions] || []]
      end
    end

    def conformance_manifest_review_state_envelope(state)
      {
        kind: "conformance_manifest_review_state",
        version: REVIEW_TRANSPORT_VERSION,
        state: deep_dup(state)
      }
    end

    def review_replay_bundle_envelope(bundle)
      {
        kind: "review_replay_bundle",
        version: REVIEW_TRANSPORT_VERSION,
        replay_bundle: deep_dup(bundle)
      }
    end

    def reviewed_nested_execution_envelope(execution)
      {
        kind: "reviewed_nested_execution",
        version: REVIEW_TRANSPORT_VERSION,
        execution: deep_dup(execution)
      }
    end

    def import_conformance_manifest_review_state_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected conformance_manifest_review_state envelope kind." }] unless envelope[:kind] == "conformance_manifest_review_state"
      return [nil, { category: "unsupported_version", message: "unsupported conformance_manifest_review_state envelope version #{envelope[:version]}." }] unless envelope[:version] == REVIEW_TRANSPORT_VERSION

      [deep_dup(envelope[:state]), nil]
    end

    def import_review_replay_bundle_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected review_replay_bundle envelope kind." }] unless envelope[:kind] == "review_replay_bundle"
      return [nil, { category: "unsupported_version", message: "unsupported review_replay_bundle envelope version #{envelope[:version]}." }] unless envelope[:version] == REVIEW_TRANSPORT_VERSION

      [deep_dup(envelope[:replay_bundle]), nil]
    end

    def import_reviewed_nested_execution_envelope(envelope)
      return [nil, { category: "kind_mismatch", message: "expected reviewed_nested_execution envelope kind." }] unless envelope[:kind] == "reviewed_nested_execution"
      return [nil, { category: "unsupported_version", message: "unsupported reviewed_nested_execution envelope version #{envelope[:version]}." }] unless envelope[:version] == REVIEW_TRANSPORT_VERSION

      [deep_dup(envelope[:execution]), nil]
    end

    def resolve_conformance_family_context(family, options)
      contexts = options.fetch(:contexts, {})
      key = family.to_sym
      return [deep_dup(contexts[key] || contexts[family.to_s]), []] if contexts.key?(key) || contexts.key?(family.to_s)

      if options.fetch(:require_explicit_contexts, false)
        return [nil, [diagnostic("error", "configuration_error", "missing explicit family context for #{family}.")]]
      end

      family_profiles = options.fetch(:family_profiles, {})
      if family_profiles.key?(key) || family_profiles.key?(family.to_s)
        context = default_conformance_family_context(family_profiles[key] || family_profiles[family.to_s])
        diagnostics = [diagnostic("warning", "assumed_default", "using default family context for #{family}.")]
        return [context, diagnostics]
      end

      [nil, [diagnostic("error", "configuration_error", "missing family context for #{family} and no default family profile is available.")]]
    end

    def review_conformance_family_context(family, options)
      contexts = options.fetch(:contexts, {})
      key = family.to_sym
      return [deep_dup(contexts[key] || contexts[family.to_s]), [], [], []] if contexts.key?(key) || contexts.key?(family.to_s)

      unless options.fetch(:require_explicit_contexts, false)
        context, diagnostics = resolve_conformance_family_context(
          family,
          contexts: options.fetch(:contexts, {}),
          family_profiles: options.fetch(:family_profiles, {}),
          require_explicit_contexts: false
        )
        return [context, diagnostics, [], []]
      end

      family_profiles = options.fetch(:family_profiles, {})
      family_profile = family_profiles[key] || family_profiles[family.to_s]
      unless family_profile
        return [nil, [diagnostic("error", "configuration_error", "missing family context for #{family} and no default family profile is available.")], [], []]
      end

      context, applied_decision, assumed_default, decision_diagnostics = review_decision_for_family_context(family, options)
      if applied_decision
        diagnostics = assumed_default ? [diagnostic("warning", "assumed_default", "using default family context for #{family}.")] : []
        return [context, diagnostics, [], [applied_decision]]
      end

      request = family_context_review_request(family, family_profile)
      return [nil, decision_diagnostics, [request], []] unless decision_diagnostics.empty?

      [
        nil,
        [diagnostic("error", "configuration_error", "missing explicit family context for #{family}.")],
        [request],
        []
      ]
    end

    def summarize_conformance_results(results)
      results.each_with_object({ total: 0, passed: 0, failed: 0, skipped: 0 }) do |result, summary|
        summary[:total] += 1
        case result[:outcome]
        when "passed" then summary[:passed] += 1
        when "failed" then summary[:failed] += 1
        when "skipped" then summary[:skipped] += 1
        end
      end
    end

    def select_conformance_case(ref, requirements, family_profile, feature_profile = nil)
      messages = []

      if requirements[:backend]
        if feature_profile.nil?
          messages << "case requires backend #{requirements[:backend]} but no backend feature profile is available for family #{family_profile[:family]}."
        elsif feature_profile[:backend] != requirements[:backend]
          messages << "case requires backend #{requirements[:backend]} but backend #{feature_profile[:backend]} is active for family #{family_profile[:family]}."
        end
      end

      if requirements[:dialect]
        if !family_profile.fetch(:supported_dialects, []).include?(requirements[:dialect])
          messages << "family #{family_profile[:family]} does not support dialect #{requirements[:dialect]}."
        elsif feature_profile && !feature_profile[:supports_dialects] && !default_dialect?(family_profile, requirements[:dialect])
          messages << "backend #{feature_profile[:backend]} does not support dialect #{requirements[:dialect]} for family #{family_profile[:family]}."
        end
      end

      requirements.fetch(:policies, []).each do |policy|
        unless includes_policy?(family_profile.fetch(:supported_policies, []), policy)
          messages << "family #{family_profile[:family]} does not support policy #{policy[:name]}."
          next
        end

        if feature_profile && !includes_policy?(feature_profile.fetch(:supported_policies, []), policy)
          messages << "backend #{feature_profile[:backend]} does not support policy #{policy[:name]}."
        end
      end

      {
        ref: deep_dup(ref),
        status: messages.empty? ? "selected" : "skipped",
        messages: messages
      }
    end

    def run_conformance_case(run, &execute)
      selection = select_conformance_case(run[:ref], run[:requirements], run[:family_profile], run[:feature_profile])
      return { ref: deep_dup(run[:ref]), outcome: "skipped", messages: selection[:messages] } if selection[:status] == "skipped"

      execution = execute.call(run)
      {
        ref: deep_dup(run[:ref]),
        outcome: execution[:outcome],
        messages: deep_dup(execution[:messages] || [])
      }
    end

    def run_conformance_suite(runs, &execute)
      runs.map { |run| run_conformance_case(run, &execute) }
    end

    def run_planned_conformance_suite(plan, &execute)
      plan[:entries].map { |entry| run_conformance_case(entry[:run], &execute) }
    end

    def run_named_conformance_suite(manifest, selector, family_profile, feature_profile = nil, &execute)
      plan = plan_named_conformance_suite(manifest, selector, family_profile, feature_profile)
      plan && run_planned_conformance_suite(plan, &execute)
    end

    def run_named_conformance_suite_entry(manifest, selector, family_profile, feature_profile = nil, &execute)
      results = run_named_conformance_suite(manifest, selector, family_profile, feature_profile, &execute)
      definition = conformance_suite_definition(manifest, selector)
      results && definition && { suite: definition, results: results }
    end

    def run_planned_named_conformance_suites(entries, &execute)
      entries.map { |entry| { suite: entry[:suite], results: run_planned_conformance_suite(entry[:plan], &execute) } }
    end

    def report_planned_conformance_suite(plan, &execute)
      report_conformance_suite(run_planned_conformance_suite(plan, &execute))
    end

    def report_named_conformance_suite(manifest, selector, family_profile, feature_profile = nil, &execute)
      plan = plan_named_conformance_suite(manifest, selector, family_profile, feature_profile)
      plan && report_planned_conformance_suite(plan, &execute)
    end

    def report_named_conformance_suite_entry(manifest, selector, family_profile, feature_profile = nil, &execute)
      report = report_named_conformance_suite(manifest, selector, family_profile, feature_profile, &execute)
      definition = conformance_suite_definition(manifest, selector)
      report && definition && { suite: definition, report: report }
    end

    def report_planned_named_conformance_suites(entries, &execute)
      entries.map { |entry| { suite: entry[:suite], report: report_planned_conformance_suite(entry[:plan], &execute) } }
    end

    def summarize_named_conformance_suite_reports(entries)
      entries.each_with_object({ total: 0, passed: 0, failed: 0, skipped: 0 }) do |entry, summary|
        report_summary = entry.dig(:report, :summary) || {}
        summary[:total] += report_summary.fetch(:total, 0)
        summary[:passed] += report_summary.fetch(:passed, 0)
        summary[:failed] += report_summary.fetch(:failed, 0)
        summary[:skipped] += report_summary.fetch(:skipped, 0)
      end
    end

    def report_named_conformance_suite_envelope(entries)
      { entries: deep_dup(entries), summary: summarize_named_conformance_suite_reports(entries) }
    end

    def report_named_conformance_suite_manifest(manifest, contexts, &execute)
      report_named_conformance_suite_envelope(
        report_planned_named_conformance_suites(
          plan_named_conformance_suites(manifest, contexts),
          &execute
        )
      )
    end

    def report_conformance_manifest(manifest, options, &execute)
      planned = plan_named_conformance_suites_with_diagnostics(manifest, options)
      {
        report: report_named_conformance_suite_envelope(report_planned_named_conformance_suites(planned[:entries], &execute)),
        diagnostics: planned[:diagnostics]
      }
    end

    def review_conformance_manifest(manifest, options, &execute)
      replay_context = conformance_manifest_replay_context(manifest, options)
      entries = []
      diagnostics = []
      requests = []
      applied_decisions = []
      effective_options = deep_dup(options)
      replay_input_context, replay_input_decisions = review_replay_bundle_inputs(options)

      if replay_input_decisions.any?
        if replay_input_context.nil?
          diagnostics << diagnostic("error", "replay_rejected", "review decisions were provided without replay context.")
          effective_options[:review_replay_bundle] = nil
          effective_options[:review_replay_context] = nil
          effective_options[:review_decisions] = []
        elsif !review_replay_context_compatible(replay_context, replay_input_context)
          diagnostics << diagnostic("error", "replay_rejected", "review replay context does not match the current conformance manifest state.")
          effective_options[:review_replay_bundle] = nil
          effective_options[:review_replay_context] = nil
          effective_options[:review_decisions] = []
        else
          allowed_request_ids = conformance_manifest_review_request_ids(manifest, options).to_h { |request_id| [request_id, true] }
          accepted_decisions = []

          replay_input_decisions.each do |decision|
            if allowed_request_ids[decision[:request_id]]
              accepted_decisions << deep_dup(decision)
            else
              diagnostics << diagnostic(
                "error",
                "replay_rejected",
                "review decision #{decision[:request_id]} does not match any current review request.",
                review: {
                  request_id: decision[:request_id],
                  action: decision[:action],
                  reason: "request_not_found"
                }
              )
            end
          end

          effective_options[:review_replay_bundle] = nil
          effective_options[:review_replay_context] = deep_dup(replay_input_context)
          effective_options[:review_decisions] = accepted_decisions
        end
      end

      resolved_contexts = {}

      conformance_suite_selectors(manifest).each do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)

        context =
          if resolved_contexts.key?(family)
            resolved_contexts[family]
          else
            resolved_context, resolved_diagnostics, resolved_requests, resolved_applied_decisions = review_conformance_family_context(family, effective_options)
            diagnostics.concat(resolved_diagnostics)
            requests.concat(resolved_requests)
            applied_decisions.concat(resolved_applied_decisions)
            resolved_contexts[family] = resolved_context
            resolved_context
          end
        next unless context

        entry = plan_named_conformance_suite_entry(manifest, selector, context)
        next unless entry

        if entry[:plan][:missing_roles].any?
          diagnostics << diagnostic("error", "configuration_error", "suite #{conformance_suite_descriptor_string(entry[:suite])} declares missing roles: #{join_comma(entry[:plan][:missing_roles])}.")
          next
        end

        entries << entry
      end

      {
        report: report_named_conformance_suite_envelope(report_planned_named_conformance_suites(entries, &execute)),
        diagnostics: diagnostics,
        requests: requests,
        applied_decisions: applied_decisions,
        host_hints: conformance_review_host_hints(options),
        replay_context: replay_context
      }
    end

    def report_conformance_suite(results)
      { results: deep_dup(results), summary: summarize_conformance_results(results) }
    end

    def plan_conformance_suite(manifest, family, roles, family_profile, feature_profile = nil)
      entries = []
      missing_roles = []

      roles.each do |role|
        entry = conformance_family_entries(manifest, family).find { |candidate| candidate[:role] == role }
        unless entry
          missing_roles << role
          next
        end

        ref = { family: family, role: role, case: role }
        run = {
          ref: ref,
          requirements: deep_dup(entry[:requirements] || {}),
          family_profile: deep_dup(family_profile)
        }
        run[:feature_profile] = deep_dup(feature_profile) if feature_profile
        entries << {
          ref: ref,
          path: deep_dup(entry[:path]),
          run: run
        }
      end

      { family: family, entries: entries, missing_roles: missing_roles }
    end

    def plan_named_conformance_suite(manifest, selector, family_profile, feature_profile = nil)
      definition = conformance_suite_definition(manifest, selector)
      return nil unless definition

      plan_conformance_suite(manifest, definition.dig(:subject, :grammar), definition[:roles], family_profile, feature_profile)
    end

    def plan_named_conformance_suite_entry(manifest, selector, context)
      plan = plan_named_conformance_suite(manifest, selector, context[:family_profile], context[:feature_profile])
      definition = conformance_suite_definition(manifest, selector)
      plan && definition && { suite: definition, plan: plan }
    end

    def plan_named_conformance_suites(manifest, contexts)
      conformance_suite_selectors(manifest).filter_map do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)
        family_key = family.to_sym
        next unless contexts.key?(family_key) || contexts.key?(family)

        plan_named_conformance_suite_entry(manifest, selector, contexts[family_key] || contexts[family])
      end
    end

    def plan_named_conformance_suites_with_diagnostics(manifest, options)
      entries = []
      diagnostics = []
      resolved_contexts = {}

      conformance_suite_selectors(manifest).each do |selector|
        definition = conformance_suite_definition(manifest, selector)
        next unless definition
        family = definition.dig(:subject, :grammar)

        context =
          if resolved_contexts.key?(family)
            resolved_contexts[family]
          else
            resolved_context, resolved_diagnostics = resolve_conformance_family_context(family, options)
            diagnostics.concat(resolved_diagnostics)
            resolved_contexts[family] = resolved_context
            resolved_context
          end
        next unless context

        entry = plan_named_conformance_suite_entry(manifest, selector, context)
        next unless entry

        if entry[:plan][:missing_roles].any?
          diagnostics << diagnostic("error", "configuration_error", "suite #{conformance_suite_descriptor_string(entry[:suite])} declares missing roles: #{join_comma(entry[:plan][:missing_roles])}.")
          next
        end

        entries << entry
      end

      { entries: entries, diagnostics: diagnostics }
    end

    def normalize_value(value)
      deep_symbolize(value)
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end

    def deep_symbolize(value)
      case value
      when Array
        value.map { |item| deep_symbolize(item) }
      when Hash
        value.each_with_object({}) do |(key, item), memo|
          memo[key.to_sym] = deep_symbolize(item)
        end
      else
        value
      end
    end

    def json_ready(value)
      case value
      when Array
        value.map { |item| json_ready(item) }
      when Hash
        value.each_with_object({}) do |(key, item), memo|
          memo[key.to_s] = json_ready(item)
        end
      else
        value
      end
    end

    def includes_policy?(supported_policies, policy)
      supported_policies.any? { |candidate| candidate == policy }
    end
    private_class_method :includes_policy?

    def default_dialect?(family_profile, dialect)
      dialect == family_profile[:family]
    end
    private_class_method :default_dialect?

    def review_decision_for_family_context(family, options)
      request_id = review_request_id_for_family_context(family)
      family_profiles = options.fetch(:family_profiles, {})
      family_profile = family_profiles[family.to_sym] || family_profiles[family]

      (options[:review_decisions] || []).each do |decision|
        next unless decision[:request_id] == request_id

        if decision[:action] == "accept_default_context" && family_profile
          return [default_conformance_family_context(family_profile), deep_dup(decision), true, []]
        end

        if decision[:action] == "provide_explicit_context" && decision[:context].nil?
          diagnostics = [
            diagnostic(
              "error",
              "configuration_error",
              "review decision #{request_id} requires explicit context payload.",
              review: {
                request_id: request_id,
                action: "provide_explicit_context",
                reason: "missing_required_payload",
                payload_kind: "conformance_family_context"
              }
            )
          ]
          return [nil, nil, false, diagnostics]
        end

        if decision[:action] == "provide_explicit_context" && decision[:context]
          provided_family = decision.dig(:context, :family_profile, :family)
          if provided_family != family
            diagnostics = [
              diagnostic(
                "error",
                "configuration_error",
                "review decision #{request_id} provided context for #{provided_family}, expected #{family}.",
                review: {
                  request_id: request_id,
                  action: "provide_explicit_context",
                  reason: "family_mismatch",
                  expected_family: family,
                  provided_family: provided_family
                }
              )
            ]
            return [nil, nil, false, diagnostics]
          end

          return [deep_dup(decision[:context]), deep_dup(decision), false, []]
        end
      end

      [nil, nil, false, []]
    end
    private_class_method :review_decision_for_family_context

    def family_context_review_request(family, family_profile)
      {
        id: review_request_id_for_family_context(family),
        kind: "family_context",
        family: family,
        message: "explicit family context is required for #{family}; a synthesized default may be accepted by review.",
        blocking: true,
        proposed_context: { family_profile: deep_dup(family_profile) },
        action_offers: [
          { action: "accept_default_context", requires_context: false },
          { action: "provide_explicit_context", requires_context: true, payload_kind: "conformance_family_context" }
        ],
        default_action: "accept_default_context"
      }
    end
    private_class_method :family_context_review_request

    def diagnostic(severity, category, message, path: nil, review: nil)
      output = {
        severity: severity,
        category: category,
        message: message
      }
      output[:path] = path if path
      output[:review] = review if review
      output
    end
    private_class_method :diagnostic

    def join_comma(values)
      values.join(", ")
    end
    private_class_method :join_comma

    def conformance_suite_selectors_equal?(left, right)
      left[:kind] == right[:kind] &&
        left.dig(:subject, :grammar) == right.dig(:subject, :grammar) &&
        left.dig(:subject, :variant) == right.dig(:subject, :variant)
    end
    private_class_method :conformance_suite_selectors_equal?
  end
end
