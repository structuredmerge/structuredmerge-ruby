# frozen_string_literal: true

require "ast/merge"
require_relative "template/version"

module Ast
  module Template
    MODES = %w[plan apply reapply].freeze

    class << self
      def merge_prepared_content_from_registry(registry, entry)
        family = entry.dig(:classification, :family) || entry.dig("classification", "family")
        adapter = registry[family.to_s]
        unless adapter
          return {
            ok: false,
            diagnostics: [{
              severity: "error",
              category: "configuration_error",
              message: "missing family adapter for #{family}"
            }],
            policies: []
          }
        end

        adapter.call(deep_dup(entry))
      end

      def registered_adapter_families(registry)
        registry.keys.map(&:to_s).sort
      end

      def report_template_directory_registry_session(mode, entries, registry, result = nil)
        normalized_mode = mode.to_s
        raise ArgumentError, "unsupported template session mode: #{mode}" unless MODES.include?(normalized_mode)

        {
          mode: normalized_mode,
          adapter_families: registered_adapter_families(registry),
          diagnostics: Array(result&.dig(:apply_result, :diagnostics) || result&.dig("apply_result", "diagnostics")),
          runner_report: Ast::Merge.report_template_directory_runner(entries, result)
        }
      end

      def default_family_merge_adapter_registry(allowed_families = nil)
        allowed = Array(allowed_families).map(&:to_s)
        include_family = lambda do |family|
          allowed.empty? || allowed.include?(family)
        end

        registry = {}
        if include_family.call("markdown")
          begin
            require "markdown-merge"
            registry["markdown"] = lambda do |entry|
              Markdown::Merge.merge_markdown(entry[:prepared_template_content], entry[:destination_content], "markdown")
            end
          rescue LoadError
          end
        end
        if include_family.call("toml")
          begin
            require "toml-merge"
            registry["toml"] = lambda do |entry|
              Toml::Merge.merge_toml(entry[:prepared_template_content], entry[:destination_content], "toml")
            end
          rescue LoadError
          end
        end
        if include_family.call("ruby")
          begin
            require "ruby-merge"
            registry["ruby"] = lambda do |entry|
              Ruby::Merge.merge_ruby(entry[:prepared_template_content], entry[:destination_content], "ruby")
            end
          rescue LoadError
          end
        end

        registry
      end

      def report_template_directory_session(mode, entries, result = nil)
        normalized_mode = mode.to_s
        raise ArgumentError, "unsupported template session mode: #{mode}" unless MODES.include?(normalized_mode)

        {
          mode: normalized_mode,
          runner_report: Ast::Merge.report_template_directory_runner(entries, result)
        }
      end

      def plan_template_directory_session_from_directories(template_root, destination_root,
        context, default_strategy, overrides, replacements, config = nil)
        entries = Ast::Merge.plan_template_tree_execution_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        )
        report_template_directory_session(:plan, entries)
      end

      def apply_template_directory_session_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, config = nil, &merge_callback)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config,
          &merge_callback
        )
        report_template_directory_session(:apply, result[:execution_plan], result)
      end

      def reapply_template_directory_session_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, config = nil, &merge_callback)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config,
          &merge_callback
        )
        report_template_directory_session(:reapply, result[:execution_plan], result)
      end

      def apply_template_directory_session_with_registry_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, registry, config = nil)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        report_template_directory_registry_session(:apply, result[:execution_plan], registry, result)
      end

      def apply_template_directory_session_with_default_registry_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        apply_template_directory_session_with_registry_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          registry,
          config
        )
      end

      def required_families(entries)
        Array(entries).filter_map do |entry|
          next unless (entry[:execution_action] || entry["execution_action"]).to_s == "merge_prepared_content"

          entry.dig(:classification, :family) || entry.dig("classification", "family")
        end.uniq.sort
      end

      def report_adapter_capabilities(entries, registry)
        available = registered_adapter_families(registry)
        required = required_families(entries)
        missing = required - available
        {
          required_families: required,
          adapter_families: available,
          missing_families: missing,
          ready: missing.empty?
        }
      end

      def report_adapter_capabilities_from_directories(template_root, destination_root,
        context, default_strategy, overrides, replacements, registry, config = nil)
        entries = Ast::Merge.plan_template_tree_execution_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        )
        report_adapter_capabilities(entries, registry)
      end

      def report_default_adapter_capabilities_from_directories(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_adapter_capabilities_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          default_family_merge_adapter_registry(allowed_families),
          config
        )
      end

      def report_template_directory_session_envelope(session_report, adapter_capabilities)
        {
          session_report: session_report,
          adapter_capabilities: adapter_capabilities
        }
      end

      def plan_template_directory_session_envelope_from_directories(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_template_directory_session_envelope(
          plan_template_directory_session_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            config
          ),
          report_default_adapter_capabilities_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        )
      end

      def apply_template_directory_session_envelope_with_default_registry_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_template_directory_session_envelope(
          apply_template_directory_session_with_default_registry_to_directory(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          ),
          report_default_adapter_capabilities_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        )
      end

      def report_template_directory_session_status(envelope)
        session_report = envelope[:session_report] || envelope["session_report"] || {}
        adapter_capabilities = envelope[:adapter_capabilities] || envelope["adapter_capabilities"] || {}
        runner_report = session_report[:runner_report] || session_report["runner_report"] || {}
        plan_report = runner_report[:plan_report] || runner_report["plan_report"] || {}
        entries = Array(plan_report[:entries] || plan_report["entries"])
        plan_summary = plan_report[:summary] || plan_report["summary"] || {}
        apply_report = runner_report[:apply_report] || runner_report["apply_report"] || {}
        apply_entries = Array(apply_report[:entries] || apply_report["entries"])
        apply_summary = apply_report[:summary] || apply_report["summary"] || {}
        blocked_paths = (entries + apply_entries).filter_map do |entry|
          status = entry[:status] || entry["status"]
          destination_path = entry[:destination_path] || entry["destination_path"]
          destination_path if status.to_s == "blocked" && destination_path
        end.uniq.sort
        missing_families = Array(
          adapter_capabilities[:missing_families] || adapter_capabilities["missing_families"]
        ).map(&:to_s).sort

        {
          mode: (session_report[:mode] || session_report["mode"]).to_s,
          ready: !!(adapter_capabilities[:ready] || adapter_capabilities["ready"]) && blocked_paths.empty?,
          missing_families: missing_families,
          blocked_paths: blocked_paths,
          planned_write_count: plan_summary.fetch(:create, plan_summary.fetch("create", 0)) +
            plan_summary.fetch(:update, plan_summary.fetch("update", 0)),
          written_count: apply_summary.fetch(:written, apply_summary.fetch("written", 0))
        }
      end

      def report_template_directory_session_diagnostics(mode, entries, adapter_capabilities, result = nil)
        missing_families = Array(
          adapter_capabilities[:missing_families] || adapter_capabilities["missing_families"]
        ).map(&:to_s)
        blocked_apply_paths = Array(
          result&.dig(:apply_report, :entries) || result&.dig("apply_report", "entries")
        ).filter_map do |entry|
          destination_path = entry[:destination_path] || entry["destination_path"]
          status = entry[:status] || entry["status"]
          destination_path if status.to_s == "blocked" && destination_path
        end

        diagnostics = Array(entries).flat_map do |entry|
          path = entry[:destination_path] || entry["destination_path"] ||
            entry[:logical_destination_path] || entry["logical_destination_path"]
          family = entry.dig(:classification, :family) || entry.dig("classification", "family")
          result_entries = []
          block_reason = entry[:block_reason] || entry["block_reason"]
          if (entry[:blocked] || entry["blocked"]) && block_reason.to_s == "unresolved_tokens"
            result_entries << {
              severity: "error",
              category: "configuration_error",
              reason: "unresolved_tokens",
              path: path,
              message: "unresolved template tokens block #{path}"
            }
          end
          if (entry[:execution_action] || entry["execution_action"]).to_s == "merge_prepared_content" &&
              missing_families.include?(family.to_s) &&
              (result.nil? || blocked_apply_paths.empty? || blocked_apply_paths.include?(path))
            result_entries << {
              severity: "error",
              category: "configuration_error",
              reason: "missing_family_adapter",
              path: path,
              family: family.to_s,
              message: "missing family adapter for #{family} blocks #{path}"
            }
          end
          result_entries
        end.sort_by { |entry| [entry[:path].to_s, entry[:reason].to_s, entry[:family].to_s] }

        {
          mode: mode.to_s,
          ready: diagnostics.empty?,
          diagnostics: diagnostics
        }
      end

      def plan_template_directory_session_diagnostics_from_directories(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        entries = Ast::Merge.plan_template_tree_execution_from_directories(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        )
        report_template_directory_session_diagnostics(
          :plan,
          entries,
          report_adapter_capabilities(entries, default_family_merge_adapter_registry(allowed_families))
        )
      end

      def apply_template_directory_session_diagnostics_with_default_registry_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        report_template_directory_session_diagnostics(
          :apply,
          result[:execution_plan],
          report_adapter_capabilities(result[:execution_plan], registry),
          result
        )
      end

      def report_template_directory_session_outcome(session_report, status, diagnostics)
        {
          session_report: session_report,
          status: status,
          diagnostics: diagnostics
        }
      end

      def plan_template_directory_session_outcome_from_directories(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        report_template_directory_session_outcome(
          plan_template_directory_session_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            config
          ),
          report_template_directory_session_status(
            plan_template_directory_session_envelope_from_directories(
              template_root,
              destination_root,
              context,
              default_strategy,
              overrides,
              replacements,
              allowed_families,
              config
            )
          ),
          plan_template_directory_session_diagnostics_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        )
      end

      def apply_template_directory_session_outcome_with_default_registry_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        session_report = report_template_directory_registry_session(:apply, result[:execution_plan], registry, result)
        capabilities = report_adapter_capabilities(result[:execution_plan], registry)
        report_template_directory_session_outcome(
          session_report,
          report_template_directory_session_status(
            report_template_directory_session_envelope(session_report, capabilities)
          ),
          report_template_directory_session_diagnostics(
            :apply,
            result[:execution_plan],
            capabilities,
            result
          )
        )
      end

      def reapply_template_directory_session_outcome_with_default_registry_to_directory(template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        registry = default_family_merge_adapter_registry(allowed_families)
        result = Ast::Merge.apply_template_tree_execution_to_directory(
          template_root,
          destination_root,
          context,
          default_strategy,
          overrides,
          replacements,
          config
        ) do |entry|
          merge_prepared_content_from_registry(registry, entry)
        end
        session_report = report_template_directory_registry_session(:reapply, result[:execution_plan], registry, result)
        capabilities = report_adapter_capabilities(result[:execution_plan], registry)
        report_template_directory_session_outcome(
          session_report,
          report_template_directory_session_status(
            report_template_directory_session_envelope(session_report, capabilities)
          ),
          report_template_directory_session_diagnostics(
            :reapply,
            result[:execution_plan],
            capabilities,
            result
          )
        )
      end

      def run_template_directory_session_with_default_registry_to_directory(mode, template_root, destination_root,
        context, default_strategy, overrides, replacements, allowed_families = nil, config = nil)
        case mode.to_s
        when "plan"
          plan_template_directory_session_outcome_from_directories(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        when "apply"
          apply_template_directory_session_outcome_with_default_registry_to_directory(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        when "reapply"
          reapply_template_directory_session_outcome_with_default_registry_to_directory(
            template_root,
            destination_root,
            context,
            default_strategy,
            overrides,
            replacements,
            allowed_families,
            config
          )
        else
          raise ArgumentError, "unsupported template session mode: #{mode}"
        end
      end

      def run_template_directory_session_with_options(options)
        normalized = deep_dup(options)
        run_template_directory_session_with_default_registry_to_directory(
          normalized[:mode] || normalized["mode"],
          normalized[:template_root] || normalized["template_root"],
          normalized[:destination_root] || normalized["destination_root"],
          normalized[:context] || normalized["context"] || {},
          normalized[:default_strategy] || normalized["default_strategy"],
          normalized[:overrides] || normalized["overrides"] || [],
          normalized[:replacements] || normalized["replacements"] || {},
          normalized[:allowed_families] || normalized["allowed_families"],
          normalized[:config] || normalized["config"]
        )
      end

      def resolve_template_directory_session_options(profiles, profile_name, overrides)
        profile = profiles[profile_name.to_s] || profiles[profile_name.to_sym]
        return nil unless profile

        normalized_profile = deep_dup(profile)
        normalized_overrides = deep_dup(overrides)
        {
          mode: normalized_overrides[:mode] || normalized_overrides["mode"] ||
            normalized_profile[:mode] || normalized_profile["mode"],
          template_root: normalized_overrides[:template_root] || normalized_overrides["template_root"],
          destination_root: normalized_overrides[:destination_root] || normalized_overrides["destination_root"],
          context: normalized_overrides[:context] || normalized_overrides["context"] ||
            normalized_profile[:context] || normalized_profile["context"] || {},
          default_strategy: normalized_overrides[:default_strategy] || normalized_overrides["default_strategy"] ||
            normalized_profile[:default_strategy] || normalized_profile["default_strategy"],
          overrides: normalized_overrides[:overrides] || normalized_overrides["overrides"] ||
            normalized_profile[:overrides] || normalized_profile["overrides"] || [],
          replacements: normalized_overrides[:replacements] || normalized_overrides["replacements"] ||
            normalized_profile[:replacements] || normalized_profile["replacements"] || {},
          allowed_families: normalized_overrides[:allowed_families] || normalized_overrides["allowed_families"] ||
            normalized_profile[:allowed_families] || normalized_profile["allowed_families"],
          config: normalized_overrides[:config] || normalized_overrides["config"] ||
            normalized_profile[:config] || normalized_profile["config"]
        }
      end

      def run_template_directory_session_with_profile(profiles, profile_name, overrides)
        options = resolve_template_directory_session_options(profiles, profile_name, overrides)
        return nil unless options

        run_template_directory_session_with_options(options)
      end

      private

      def deep_dup(value)
        Ast::Merge.deep_dup(value)
      end
    end
  end
end
