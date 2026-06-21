# frozen_string_literal: true

module Prism
  module Merge
    # Detects block directive pairs (freeze and coverage) in source lines and
    # promotes them to synthetic BlockDirective tree nodes in the statements array.
    #
    # A block directive is an open/close comment pair that wraps content:
    # - Freeze: `# token:freeze` ... `# token:unfreeze`
    # - Coverage: `# simplecov:disable` ... `# simplecov:enable`
    # - Legacy coverage: `# :nocov:` ... `# :nocov:` (same marker toggles)
    #
    # The detector runs AFTER Prism's `attach_comments!` to avoid being fooled by
    # Prism's leading-comment attachment, which hoists all preceding comment lines
    # onto the first code node as leading comments.
    #
    # Rules enforced:
    # - Directives must form a clean tree (proper nesting, no offset overlap)
    # - Directives must open and close at the same syntactic level
    # - Violations emit a warning and fall back to plain comment emission
    class BlockDirectiveDetector
      # Represents a detected span before tree promotion
      Span = Struct.new(:kind, :start_line, :end_line, :open_marker, :close_marker, keyword_init: true)

      # Default legacy nocov token (older SimpleCov convention)
      NOCOV_TOKEN = ":nocov:"
      SIMPLECOV_DISABLE_RE = /\A\s*#\s*simplecov\s*:\s*disable\b/i
      SIMPLECOV_ENABLE_RE = /\A\s*#\s*simplecov\s*:\s*enable\b/i

      # @param lines [Array<String>] Raw source lines (1-indexed via [line_num - 1])
      # @param freeze_token [String, nil] Freeze token (e.g. "kettle-jem"). nil disables freeze detection.
      # @param nocov_token [String] Nocov token (default ":nocov:")
      # @param source_label [String, nil] Optional file path or label included in warning messages.
      def initialize(lines, freeze_token: nil, nocov_token: NOCOV_TOKEN, source_label: nil)
        @lines = lines
        @freeze_token = freeze_token
        @nocov_token = nocov_token
        @source_label = source_label
      end

      # Detect all directive spans in the source lines.
      # Returns a flat array of Span structs sorted by start_line.
      # Crossing/invalid spans are excluded with a warning.
      #
      # @return [Array<Span>]
      def detect_spans
        raw_spans = []
        raw_spans.concat(detect_freeze_spans) if @freeze_token
        raw_spans.concat(detect_nocov_spans)

        sorted = raw_spans.sort_by(&:start_line)
        validate_no_crossing(sorted)
      end

      # Post-process a statements array: replace content covered by each span
      # with a synthetic BlockDirective node. Spans must be pre-validated (no crossing).
      #
      # Spans that fall entirely INSIDE a top-level statement are skipped — those
      # are nested directives handled by recursive body merging, not top-level promotions.
      #
      # @param statements [Array] Prism statements (may include FrozenWrapper etc.)
      # @param spans [Array<Span>] Validated spans from detect_spans
      # @param analysis [FileAnalysis] The owning FileAnalysis (passed to node constructors)
      # @return [Array] Modified statements array
      def promote_spans_to_nodes(statements, spans, analysis:)
        return statements if spans.empty?

        validate_same_syntactic_level!(spans, statements)

        top_level = top_level_spans_only(spans).reject do |span|
          # Skip spans that are wholly inside a top-level code node.
          # Those are handled during recursive body merging.
          statements.any? do |stmt|
            sl = stmt_start_line(stmt)
            el = stmt_end_line(stmt)
            sl && el && sl <= span.start_line && el >= span.end_line
          end
        end

        return statements if top_level.empty?

        result = []
        used_indices = Set.new

        top_level.each do |span|
          inner_stmts = statements.each_with_index.select do |stmt, idx|
            next false if used_indices.include?(idx)

            sl = stmt_start_line(stmt)
            el = stmt_end_line(stmt)
            sl && el && sl >= span.start_line && el <= span.end_line
          end.map { |stmt, idx| [idx, stmt] }

          inner_indices = inner_stmts.map(&:first)
          inner_nodes = inner_stmts.map(&:last)

          nested = spans.select { |s| s != span && s.start_line >= span.start_line && s.end_line <= span.end_line }

          unless nested.empty?
            inner_nodes = promote_spans_to_nodes(inner_nodes, nested, analysis: analysis)
          end

          directive_node = build_directive_node(span, inner_nodes, analysis)
          # Determine insertion position:
          # - If inner nodes exist: insert at the first covered index (replacing them)
          # - If no inner nodes (span covers only comment lines): insert at the position
          #   of the first statement whose start_line is AFTER the span's start_line,
          #   or append at the end if no such statement exists.
          insert_at = if inner_indices.any?
            inner_indices.min
          else
            idx_after = statements.each_with_index.find { |stmt, _| stmt_start_line(stmt).to_i > span.start_line }
            idx_after ? idx_after.last : statements.length
          end
          result << [insert_at, directive_node, inner_indices]
          used_indices.merge(inner_indices)
        end

        rebuild_statements(statements, result, used_indices)
      end

      private

      def warn_prefix
        @source_label ? "[prism-merge] BlockDirectiveDetector (#{@source_label}):" : "[prism-merge] BlockDirectiveDetector:"
      end

      # Report an unbalanced or invalid block directive.
      # Raises Prism::Merge::Error for top-level file analysis (source_label present)
      # to prevent file corruption. Falls back to warn for sub-body fragments
      # (no source_label) where partial markers are expected.
      def report_unbalanced(message)
        if @source_label
          raise Prism::Merge::Error, "#{warn_prefix} #{message}"
        else
          warn("#{warn_prefix} #{message} — ignoring")
        end
      end

      # @return [Array<Span>]
      def detect_freeze_spans
        return [] unless @freeze_token

        freeze_pat = /\A\s*#\s?#{Regexp.escape(@freeze_token)}:freeze\b/i
        unfreeze_pat = /\A\s*#\s?#{Regexp.escape(@freeze_token)}:unfreeze\b/i

        spans = []
        stack = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          stripped = line.to_s.chomp
          if stripped.match?(freeze_pat)
            stack.push({start_line: line_num, open_marker: stripped})
          elsif stripped.match?(unfreeze_pat)
            if (open = stack.pop)
              spans << Span.new(
                kind: :freeze,
                start_line: open[:start_line],
                end_line: line_num,
                open_marker: open[:open_marker],
                close_marker: stripped,
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

      # @return [Array<Span>]
      def detect_nocov_spans
        return [] unless @nocov_token

        nocov_pat = /\A\s*#\s?#{Regexp.escape(@nocov_token)}\s*\z/i

        spans = []
        stack = []

        @lines.each_with_index do |line, idx|
          line_num = idx + 1
          stripped = line.to_s.chomp
          if stripped.match?(SIMPLECOV_DISABLE_RE)
            stack.push({start_line: line_num, open_marker: stripped})
          elsif stripped.match?(SIMPLECOV_ENABLE_RE)
            if (open = stack.pop)
              spans << Span.new(
                kind: :nocov,
                start_line: open[:start_line],
                end_line: line_num,
                open_marker: open[:open_marker],
                close_marker: stripped,
              )
            else
              report_unbalanced("unmatched simplecov:enable at line #{line_num}")
            end
          elsif stripped.match?(nocov_pat)
            if stack.empty?
              stack.push({start_line: line_num, open_marker: stripped})
            else
              open = stack.pop
              spans << Span.new(
                kind: :nocov,
                start_line: open[:start_line],
                end_line: line_num,
                open_marker: open[:open_marker],
                close_marker: stripped,
              )
            end
          end
        end

        stack.each do |open|
          report_unbalanced("unclosed coverage directive at line #{open[:start_line]}")
        end

        spans
      end

      # Validate spans form a clean tree (no offset/crossing overlap).
      # @param spans [Array<Span>] Sorted by start_line
      # @return [Array<Span>] Valid spans only
      def validate_no_crossing(spans)
        valid = []
        invalid_indices = Set.new

        spans.each_with_index do |a, i|
          next if invalid_indices.include?(i)

          crossing = false
          spans.each_with_index do |b, j|
            next if i == j || invalid_indices.include?(j)

            if (a.start_line < b.start_line && a.end_line > b.start_line && a.end_line < b.end_line) ||
                (b.start_line < a.start_line && b.end_line > a.start_line && b.end_line < a.end_line)
              report_unbalanced("offset-overlapping #{a.kind} block " \
                "(lines #{a.start_line}..#{a.end_line}) and #{b.kind} block " \
                "(lines #{b.start_line}..#{b.end_line}) — both treated as plain comments")
              invalid_indices.add(i)
              invalid_indices.add(j)
              crossing = true
              break
            end
          end

          valid << a unless crossing
        end

        valid
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

      def stmt_start_line(stmt)
        if stmt.respond_to?(:start_line)
          stmt.start_line
        elsif stmt.respond_to?(:location)
          stmt.location&.start_line
        end
      end

      def stmt_end_line(stmt)
        if stmt.respond_to?(:end_line)
          stmt.end_line
        elsif stmt.respond_to?(:location)
          stmt.location&.end_line
        end
      end

      def validate_same_syntactic_level!(spans, statements)
        spans.each do |span|
          start_owner = owner_for_line(statements, span.start_line)
          end_owner = owner_for_line(statements, span.end_line)
          next if start_owner.nil? && end_owner.nil?
          next if start_owner && end_owner && start_owner.equal?(end_owner)

          report_unbalanced(
            "#{span.kind} block opens at line #{span.start_line} and closes at line #{span.end_line}, " \
              "but the markers do not live at the same syntactic level",
          )
        end
      end

      def owner_for_line(statements, line_num)
        statements.find do |stmt|
          sl = stmt_start_line(stmt)
          el = stmt_end_line(stmt)
          sl && el && sl <= line_num && line_num <= el
        end
      end

      def build_directive_node(span, inner_nodes, analysis)
        case span.kind
        when :freeze
          Prism::Merge::FreezeNode.new(
            start_line: span.start_line,
            end_line: span.end_line,
            analysis: analysis,
            nodes: inner_nodes,
            overlapping_nodes: inner_nodes,
            start_marker: span.open_marker,
            end_marker: span.close_marker,
          )
        when :nocov
          Prism::Merge::NocovNode.new(
            start_line: span.start_line,
            end_line: span.end_line,
            analysis: analysis,
            nodes: inner_nodes,
            start_marker: span.open_marker,
            close_marker: span.close_marker,
          )
        else
          raise ArgumentError, "Unknown BlockDirective kind: #{span.kind}"
        end
      end

      def rebuild_statements(statements, replacements, used_indices)
        # Multiple directives can share the same insert position (e.g. a freeze span
        # with no inner nodes and a nocov span whose inner node is the same statement).
        # Use an array per position, sorted by span start_line so earlier directives
        # come first in the output.
        replacement_map = Hash.new { |h, k| h[k] = [] }
        replacements.each do |insert_at, node, _covered|
          replacement_map[insert_at] << node
        end
        replacement_map.each_value { |nodes| nodes.sort_by! { |n| n.start_line || 0 } }

        result = []
        statements.each_with_index do |stmt, idx|
          # Insert all replacements queued at this position (in start_line order)
          if (nodes = replacement_map.delete(idx))
            nodes.each { |n| result << n }
          end

          next if used_indices.include?(idx)

          result << stmt
        end

        # Append any replacements whose insert position is past the end
        replacement_map.each_value { |nodes| nodes.each { |n| result << n } }

        result
      end
    end
  end
end
