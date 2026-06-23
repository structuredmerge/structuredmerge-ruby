# frozen_string_literal: true

module Psych
  module Merge
    # Merges a partial YAML template into a specific key path of a destination document.
    #
    # Unlike the full SmartMerger which merges entire documents, PartialTemplateMerger:
    # 1. Finds a specific key path in the destination (e.g., ["AllCops", "Exclude"])
    # 2. Merges template content at that location
    # 3. Leaves the rest of the destination unchanged
    #
    # @example Basic usage - merge into existing key
    #   template = <<~YAML
    #     - examples/**/*
    #     - vendor/**/*
    #   YAML
    #
    #   destination = <<~YAML
    #     AllCops:
    #       Exclude:
    #         - tmp/**/*
    #       TargetRubyVersion: 3.2
    #   YAML
    #
    #   merger = PartialTemplateMerger.new(
    #     template: template,
    #     destination: destination,
    #     key_path: ["AllCops", "Exclude"]
    #   )
    #   result = merger.merge
    #
    # @example Adding a new nested key
    #   merger = PartialTemplateMerger.new(
    #     template: "enable",
    #     destination: "AllCops:\n  Exclude: []",
    #     key_path: ["AllCops", "NewCops"],
    #     when_missing: :add
    #   )
    #
    class PartialTemplateMerger < ::Ast::Merge::KeyPathPartialTemplateMergerBase
      # Initialize a PartialTemplateMerger.
      #
      # @param template [String] The template content to merge
      # @param destination [String] The destination content
      # @param key_path [Array<String, Integer>] Path to target key (e.g., ["AllCops", "Exclude"])
      # @param preference [Symbol] Which content wins on conflicts (:template or :destination)
      # @param add_missing [Boolean] Whether to add template items not in destination
      # @param remove_missing [Boolean] Whether to remove destination items not in template
      # @param when_missing [Symbol] Behavior when key path not found (:skip, :add)
      # @param recursive [Boolean] Whether to recursively merge nested structures

      private

      def create_analysis(content)
        FileAnalysis.new(content)
      end

      def child_entries_for(entry, analysis)
        entry.value.mapping_entries(comment_tracker: analysis.comment_tracker).map do |key, value|
          MappingEntry.new(key: key, value: value, lines: analysis.lines, comment_tracker: analysis.comment_tracker)
        end
      end

      def create_smart_merger(template_content, destination_content)
        SmartMerger.new(
          template_content,
          destination_content,
          preference: preference,
          add_template_only_nodes: add_missing,
          remove_template_missing_nodes: remove_missing,
          recursive: recursive
        )
      end

      def parse_content_value(content)
        ::Psych.safe_load(content)
      end

      def dump_content_value(value)
        ::Psych.dump(value).sub(/\A---\n?/, '')
      end

      def deep_merge_content_value(base, overlay)
        return overlay unless base.is_a?(Hash) && overlay.is_a?(Hash)

        result = base.dup
        overlay.each do |key, value|
          result[key] = if result.key?(key) && result[key].is_a?(Hash) && value.is_a?(Hash)
                          deep_merge_content_value(result[key], value)
                        else
                          value
                        end
        end
        result
      end
    end
  end
end
