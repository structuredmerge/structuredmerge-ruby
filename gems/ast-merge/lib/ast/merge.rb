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

    def conformance_suite_definition(manifest, suite_name)
      suites = manifest.fetch(:suites, {})
      definition = suites[suite_name.to_sym] || suites[suite_name.to_s]
      definition && deep_dup(definition)
    end

    def conformance_suite_names(manifest)
      manifest.fetch(:suites, {}).keys.map(&:to_s).sort
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

    def conformance_manifest_replay_context(manifest, options)
      seen = {}
      families = conformance_suite_names(manifest).filter_map do |suite_name|
        definition = conformance_suite_definition(manifest, suite_name)
        next unless definition
        family = definition[:family]
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
      conformance_suite_names(manifest).filter_map do |suite_name|
        definition = conformance_suite_definition(manifest, suite_name)
        next unless definition
        family = definition[:family]
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

    def run_named_conformance_suite(manifest, suite_name, family_profile, feature_profile = nil, &execute)
      plan = plan_named_conformance_suite(manifest, suite_name, family_profile, feature_profile)
      plan && run_planned_conformance_suite(plan, &execute)
    end

    def run_named_conformance_suite_entry(manifest, suite_name, family_profile, feature_profile = nil, &execute)
      results = run_named_conformance_suite(manifest, suite_name, family_profile, feature_profile, &execute)
      results && { suite: suite_name, results: results }
    end

    def run_planned_named_conformance_suites(entries, &execute)
      entries.map { |entry| { suite: entry[:suite], results: run_planned_conformance_suite(entry[:plan], &execute) } }
    end

    def report_planned_conformance_suite(plan, &execute)
      report_conformance_suite(run_planned_conformance_suite(plan, &execute))
    end

    def report_named_conformance_suite(manifest, suite_name, family_profile, feature_profile = nil, &execute)
      plan = plan_named_conformance_suite(manifest, suite_name, family_profile, feature_profile)
      plan && report_planned_conformance_suite(plan, &execute)
    end

    def report_named_conformance_suite_entry(manifest, suite_name, family_profile, feature_profile = nil, &execute)
      report = report_named_conformance_suite(manifest, suite_name, family_profile, feature_profile, &execute)
      report && { suite: suite_name, report: report }
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
      resolved_families = {}

      conformance_suite_names(manifest).each do |suite_name|
        definition = conformance_suite_definition(manifest, suite_name)
        next unless definition

        context =
          if resolved_families[definition[:family]]
            resolved_contexts[definition[:family]]
          else
            resolved_context, resolved_diagnostics, resolved_requests, resolved_applied_decisions = review_conformance_family_context(definition[:family], effective_options)
            diagnostics.concat(resolved_diagnostics)
            requests.concat(resolved_requests)
            applied_decisions.concat(resolved_applied_decisions)
            resolved_families[definition[:family]] = true
            resolved_contexts[definition[:family]] = resolved_context
            resolved_context
          end
        next unless context

        entry = plan_named_conformance_suite_entry(manifest, suite_name, context)
        next unless entry

        if entry[:plan][:missing_roles].any?
          diagnostics << diagnostic("error", "configuration_error", "suite #{suite_name} declares missing roles: #{join_comma(entry[:plan][:missing_roles])}.")
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

    def plan_named_conformance_suite(manifest, suite_name, family_profile, feature_profile = nil)
      definition = conformance_suite_definition(manifest, suite_name)
      return nil unless definition

      plan_conformance_suite(manifest, definition[:family], definition[:roles], family_profile, feature_profile)
    end

    def plan_named_conformance_suite_entry(manifest, suite_name, context)
      plan = plan_named_conformance_suite(manifest, suite_name, context[:family_profile], context[:feature_profile])
      plan && { suite: suite_name, plan: plan }
    end

    def plan_named_conformance_suites(manifest, contexts)
      conformance_suite_names(manifest).filter_map do |suite_name|
        definition = conformance_suite_definition(manifest, suite_name)
        next unless definition
        family_key = definition[:family].to_sym
        next unless contexts.key?(family_key) || contexts.key?(definition[:family])

        plan_named_conformance_suite_entry(manifest, suite_name, contexts[family_key] || contexts[definition[:family]])
      end
    end

    def plan_named_conformance_suites_with_diagnostics(manifest, options)
      entries = []
      diagnostics = []
      resolved_contexts = {}
      resolved_families = {}

      conformance_suite_names(manifest).each do |suite_name|
        definition = conformance_suite_definition(manifest, suite_name)
        next unless definition

        context =
          if resolved_families[definition[:family]]
            resolved_contexts[definition[:family]]
          else
            resolved_context, resolved_diagnostics = resolve_conformance_family_context(definition[:family], options)
            diagnostics.concat(resolved_diagnostics)
            resolved_families[definition[:family]] = true
            resolved_contexts[definition[:family]] = resolved_context
            resolved_context
          end
        next unless context

        entry = plan_named_conformance_suite_entry(manifest, suite_name, context)
        next unless entry

        if entry[:plan][:missing_roles].any?
          diagnostics << diagnostic("error", "configuration_error", "suite #{suite_name} declares missing roles: #{join_comma(entry[:plan][:missing_roles])}.")
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
  end
end
