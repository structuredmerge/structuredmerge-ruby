# frozen_string_literal: true

module Ruby
  module Merge
    # Detects Ruby comment block directive pairs in source lines.
    #
    # This is Ruby-specific substrate behavior shared by Ruby parser providers.
    # Parser-specific gems may consume the spans and project them into their own
    # node types, but directive token semantics should live here.
    # Directive scanning intentionally keeps the paired-stack validation in one
    # class so every caller receives identical malformed-input diagnostics.
    # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/ClassLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    class BlockDirectiveDetector
      Span = Struct.new(:kind, :start_line, :end_line, :open_marker, :close_marker, keyword_init: true)

      NOCOV_TOKEN = ':nocov:'
      SIMPLECOV_DISABLE_RE = /\A\s*#\s*simplecov\s*:\s*disable\b/i
      SIMPLECOV_ENABLE_RE = /\A\s*#\s*simplecov\s*:\s*enable\b/i
      DIRECTIVE_CONTENT_RE = /\A(?::nocov:|[\w-]+:(?:freeze|unfreeze))\z/i

      class << self
        def coverage_directive_line?(line, nocov_token: NOCOV_TOKEN)
          stripped = line.to_s.chomp
          stripped.match?(simplecov_disable_re) ||
            stripped.match?(simplecov_enable_re) ||
            stripped.match?(nocov_re(nocov_token))
        end

        def directive_content?(content)
          DIRECTIVE_CONTENT_RE.match?(content.to_s.strip) ||
            coverage_directive_line?("# #{content}")
        end

        def simplecov_disable_re
          SIMPLECOV_DISABLE_RE
        end

        def simplecov_enable_re
          SIMPLECOV_ENABLE_RE
        end

        def nocov_re(nocov_token = NOCOV_TOKEN)
          /\A\s*#\s?#{Regexp.escape(nocov_token)}\s*\z/i
        end
      end

      def initialize(lines, freeze_token: nil, nocov_token: NOCOV_TOKEN, source_label: nil)
        @lines = lines
        @freeze_token = freeze_token
        @nocov_token = nocov_token
        @source_label = source_label
      end

      def detect_spans
        raw_spans = []
        raw_spans.concat(detect_freeze_spans) if @freeze_token
        raw_spans.concat(detect_nocov_spans)

        validate_no_crossing(raw_spans.sort_by(&:start_line))
      end

      private

      def detector_name
        'ruby-merge'
      end

      def directive_error_class
        Ast::Merge::Error
      end

      def warn_prefix
        if @source_label
          "[#{detector_name}] BlockDirectiveDetector (#{@source_label}):"
        else
          "[#{detector_name}] BlockDirectiveDetector:"
        end
      end

      def report_unbalanced(message)
        raise directive_error_class, "#{warn_prefix} #{message}" if @source_label

        warn("#{warn_prefix} #{message} - ignoring")
      end

      def detect_freeze_spans
        freeze_pat = /\A\s*#\s?#{Regexp.escape(@freeze_token)}:freeze\b/i
        unfreeze_pat = /\A\s*#\s?#{Regexp.escape(@freeze_token)}:unfreeze\b/i

        spans = []
        stack = []

        @lines.each_with_index do |line, index|
          line_num = index + 1
          stripped = line.to_s.chomp
          if stripped.match?(freeze_pat)
            stack.push({ start_line: line_num, open_marker: stripped })
          elsif stripped.match?(unfreeze_pat)
            if (open = stack.pop)
              spans << Span.new(
                kind: :freeze,
                start_line: open[:start_line],
                end_line: line_num,
                open_marker: open[:open_marker],
                close_marker: stripped
              )
            else
              report_unbalanced("unmatched #{@freeze_token}:unfreeze at line #{line_num}")
            end
          end
        end

        stack.each do |open|
          report_unbalanced("unclosed #{@freeze_token}:freeze at line #{open[:start_line]}")
        end

        spans
      end

      def detect_nocov_spans
        return [] unless @nocov_token

        nocov_pat = self.class.nocov_re(@nocov_token)

        spans = []
        stack = []

        @lines.each_with_index do |line, index|
          line_num = index + 1
          stripped = line.to_s.chomp
          if stripped.match?(self.class.simplecov_disable_re)
            stack.push({ start_line: line_num, open_marker: stripped })
          elsif stripped.match?(self.class.simplecov_enable_re)
            if (open = stack.pop)
              spans << Span.new(
                kind: :nocov,
                start_line: open[:start_line],
                end_line: line_num,
                open_marker: open[:open_marker],
                close_marker: stripped
              )
            else
              report_unbalanced("unmatched simplecov:enable at line #{line_num}")
            end
          elsif stripped.match?(nocov_pat)
            if stack.empty?
              stack.push({ start_line: line_num, open_marker: stripped })
            else
              open = stack.pop
              spans << Span.new(
                kind: :nocov,
                start_line: open[:start_line],
                end_line: line_num,
                open_marker: open[:open_marker],
                close_marker: stripped
              )
            end
          end
        end

        stack.each do |open|
          report_unbalanced("unclosed coverage directive at line #{open[:start_line]}")
        end

        spans
      end

      def validate_no_crossing(spans)
        valid = []
        invalid_indices = Set.new

        spans.each_with_index do |first, first_index|
          next if invalid_indices.include?(first_index)

          crossing = false
          spans.each_with_index do |second, second_index|
            next if first_index == second_index || invalid_indices.include?(second_index)
            next unless crossing_spans?(first, second)

            report_unbalanced(
              "offset-overlapping #{first.kind} block (lines #{first.start_line}..#{first.end_line}) and " \
              "#{second.kind} block (lines #{second.start_line}..#{second.end_line}) - both treated as plain comments"
            )
            invalid_indices.add(first_index)
            invalid_indices.add(second_index)
            crossing = true
            break
          end

          valid << first unless crossing
        end

        valid
      end

      def crossing_spans?(first, second)
        first_crosses_second = first.start_line < second.start_line &&
                               first.end_line > second.start_line &&
                               first.end_line < second.end_line
        second_crosses_first = second.start_line < first.start_line &&
                               second.end_line > first.start_line &&
                               second.end_line < first.end_line
        first_crosses_second || second_crosses_first
      end

      def top_level_spans_only(spans)
        spans.reject do |span|
          spans.any? do |other|
            other != span &&
              other.start_line <= span.start_line &&
              other.end_line >= span.end_line
          end
        end
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/ClassLength
  end
end
