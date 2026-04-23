# frozen_string_literal: true

require "ast/merge"
require_relative "template/version"

module Ast
  module Template
    MODES = %w[plan apply reapply].freeze

    class << self
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
    end
  end
end
