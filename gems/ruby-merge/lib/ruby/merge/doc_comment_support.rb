# frozen_string_literal: true

module Ruby
  module Merge
    # Ruby-specific doc-comment semantics shared by Ruby parser providers.
    module DocCommentSupport
      TAG_PREFIX = /\A@[a-z_]+\b/
      EXAMPLE_TAG = /\A@example\b(?<rest>.*)\z/
      MAGIC_COMMENT_PREFIXES = %w[
        coding
        encoding
        frozen_string_literal
        shareable_constant_value
        typed
        warn_indent
      ].freeze

      module_function

      def normalize_comment_content(raw)
        raw.to_s.sub(/\A\s*#\s?/, '').strip
      end

      def comment_prefix_for(raw)
        raw.to_s[/\A\s*#\s*/] || '# '
      end

      def doc_comment_content?(raw, magic_comment: false)
        content = normalize_comment_content(raw)
        return false if content.empty?
        return false if BlockDirectiveDetector.directive_content?(content)
        return false if magic_comment || magic_comment_content?(content)

        true
      end

      def magic_comment_content?(content)
        MAGIC_COMMENT_PREFIXES.any? { |prefix| content.to_s.start_with?("#{prefix}:") }
      end

      def declared_example_language(rest)
        match = rest.to_s.strip.match(/\A\[(?<language>[^\]]+)\]/)
        normalize_language(match && match[:language])
      end

      def declared_example_language_for_tag(content)
        match = EXAMPLE_TAG.match(content.to_s)
        return unless match

        declared_example_language(match[:rest])
      end

      def normalize_language(language)
        return if language.nil?

        normalized = language.to_s.strip.downcase.tr('-', '_')
        return if normalized.empty?

        normalized
      end

      def next_tag_index(normalized_lines, start_index)
        normalized_lines.each_with_index do |content, index|
          next if index < start_index

          return index if TAG_PREFIX.match?(content)
        end
        nil
      end

      # Example extraction deliberately combines tag scanning and body slicing
      # so the returned indexes remain tied to the original comment entries.
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      def example_blocks(entries)
        normalized = entries.map { |entry| normalize_comment_content(entry[:raw]) }
        normalized.each_with_index.filter_map do |content, tag_index|
          match = EXAMPLE_TAG.match(content)
          next unless match

          body_start_index = tag_index + 1
          body_end_index = next_tag_index(normalized, body_start_index) || normalized.length
          next if body_start_index >= body_end_index

          body_entries = entries[body_start_index...body_end_index]
          next if body_entries.nil? || body_entries.empty?

          {
            tag_index: tag_index,
            tag_line: entries[tag_index][:line],
            tag_text: normalized[tag_index],
            body_start_index: body_start_index,
            body_end_index: body_end_index,
            body_entries: body_entries,
            declared_language: declared_example_language(match[:rest])
          }
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    end
  end
end
