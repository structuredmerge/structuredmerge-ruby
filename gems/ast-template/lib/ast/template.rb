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

      private

      def deep_dup(value)
        Ast::Merge.deep_dup(value)
      end
    end
  end
end
