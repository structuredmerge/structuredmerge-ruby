# frozen_string_literal: true

module Ast
  module Merge
    # Base class for merging a partial template into a specific key path of a
    # structured destination document.
    #
    # Unlike the navigable section-based PartialTemplateMergerBase, this base:
    # 1. Navigates a nested key path in a structured document
    # 2. Merges only the value located at that path
    # 3. Leaves the rest of the destination unchanged
    #
    # Ownership boundary:
    # - this base owns the shared control flow for key-path navigation,
    #   missing-path insertion, and full-document wrapper construction
    # - concrete subclasses own parser-specific analysis, child traversal,
    #   serialization, and SmartMerger integration
    #
    # Expected duck-type surface from analyses and entries:
    # - analysis responds to #valid?, #errors, and #statements
    # - entries respond to #key_name, #mapping?, #sequence?, and #scalar?
    class KeyPathPartialTemplateMergerBase
      # Result of a key-path partial template merge
      class Result
        attr_reader :content, :has_key_path, :changed, :stats, :message

        def initialize(content:, has_key_path:, changed:, stats: {}, message: nil)
          @content = content
          @has_key_path = has_key_path
          @changed = changed
          @stats = stats
          @message = message
        end

        def key_path_found?
          has_key_path
        end
      end

      attr_reader :template, :destination, :key_path, :preference, :add_missing, :remove_missing, :when_missing,
                  :recursive

      def initialize(
        template:,
        destination:,
        key_path:,
        preference: :destination,
        add_missing: true,
        remove_missing: false,
        when_missing: :skip,
        recursive: true
      )
        @template = template
        @destination = destination
        @key_path = Array(key_path)
        @preference = preference
        @add_missing = add_missing
        @remove_missing = remove_missing
        @when_missing = when_missing
        @recursive = recursive

        validate_key_path!
      end

      # Merge template content into the configured key path.
      #
      # @return [Result]
      def merge
        analysis = create_analysis(destination)

        unless analysis.valid?
          return Result.new(
            content: destination,
            has_key_path: false,
            changed: false,
            message: "Failed to parse destination: #{Array(analysis.errors).join(', ')}"
          )
        end

        target_entry = find_key_path(analysis)
        return handle_missing_key_path if target_entry.nil?

        perform_merge_at_path(target_entry)
      end

      protected

      def create_analysis(content)
        raise NotImplementedError, "#{self.class} must implement #create_analysis"
      end

      def child_entries_for(entry, analysis)
        raise NotImplementedError, "#{self.class} must implement #child_entries_for"
      end

      def create_smart_merger(template_content, destination_content)
        raise NotImplementedError, "#{self.class} must implement #create_smart_merger"
      end

      def parse_content_value(content)
        raise NotImplementedError, "#{self.class} must implement #parse_content_value"
      end

      def dump_content_value(value)
        raise NotImplementedError, "#{self.class} must implement #dump_content_value"
      end

      def deep_merge_content_value(base, overlay)
        raise NotImplementedError, "#{self.class} must implement #deep_merge_content_value"
      end

      private

      def validate_key_path!
        raise ArgumentError, 'key_path cannot be empty' if key_path.empty?
      end

      def find_key_path(analysis)
        current_entries = Array(analysis.statements)
        target_entry = nil

        key_path.each_with_index do |key, depth|
          entry = current_entries.find do |candidate|
            candidate.respond_to?(:key_name) && candidate.key_name == key
          end
          return nil unless entry

          if depth == key_path.length - 1
            target_entry = entry
          elsif entry.respond_to?(:mapping?) && entry.mapping?
            current_entries = Array(child_entries_for(entry, analysis))
          else
            return nil
          end
        end

        target_entry
      end

      def handle_missing_key_path
        case when_missing
        when :add
          new_content = add_key_path_with_content
          Result.new(
            content: new_content,
            has_key_path: false,
            changed: true,
            message: 'Key path not found, added with template content'
          )
        else
          Result.new(
            content: destination,
            has_key_path: false,
            changed: false,
            message: 'Key path not found, skipping'
          )
        end
      end

      def add_key_path_with_content
        template_value = load_content_value(template) { template }
        nested_value = wrap_value_at_key_path(template_value)
        destination_value = load_content_value(destination) { {} }
        merged_value = deep_merge_content_value(destination_value, nested_value)
        dump_content_value(merged_value)
      end

      def perform_merge_at_path(target_entry)
        if target_entry.respond_to?(:scalar?) && target_entry.scalar? && preference != :template
          return Result.new(
            content: destination,
            has_key_path: true,
            changed: false,
            stats: { mode: :keep_destination },
            message: 'No changes needed'
          )
        end

        merger = create_smart_merger(build_template_at_path, destination)
        merged_content = extract_merger_content(merger)
        changed = merged_content != destination

        Result.new(
          content: merged_content,
          has_key_path: true,
          changed: changed,
          stats: extract_merger_stats(merger),
          message: changed ? 'Merged at key path' : 'No changes needed'
        )
      end

      def build_template_at_path
        wrap_and_dump_value(load_content_value(template) { template })
      end

      def wrap_and_dump_value(value)
        dump_content_value(wrap_value_at_key_path(value))
      end

      def wrap_value_at_key_path(value)
        key_path.reverse_each.reduce(value) do |memo, key|
          { key => memo }
        end
      end

      def load_content_value(content)
        parse_content_value(content)
      rescue StandardError
        yield
      end

      def extract_merger_content(merger)
        result = merger.merge
        return result if result.is_a?(String)
        return result.content if result.respond_to?(:content)

        result.to_s
      end

      def extract_merger_stats(merger)
        if merger.respond_to?(:merge_result)
          merge_result = merger.merge_result
          return merge_result.stats if merge_result.respond_to?(:stats)
        end

        {}
      end
    end
  end
end
