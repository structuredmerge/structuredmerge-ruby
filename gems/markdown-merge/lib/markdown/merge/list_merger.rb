# frozen_string_literal: true

module Markdown
  module Merge
    # Merges two Markdown list nodes at the item level.
    #
    # When a template list and destination list are matched (e.g., via fuzzy matching
    # or a shared content fingerprint), this merger produces a result that is smarter
    # than simply picking one whole list as the winner:
    #
    #   - Items that appear in both lists are resolved by preference (template or dest).
    #   - Items that only appear in the destination are kept (project customisations).
    #   - Items that only appear in the template are added (new canonical steps).
    #
    # Item matching uses significant-token Jaccard overlap so minor wording differences
    # (e.g., "Commit changes" vs "Commit your changes") still produce a match.
    #
    # The merged list is emitted as plain Markdown text (ordered `1. …` lines) and
    # passed to the caller via `add_raw` on the OutputBuilder.
    #
    # @example Basic usage
    #   merger = ListMerger.new
    #   result = merger.merge_lists(template_node, dest_node,
    #                               preference: :template,
    #                               add_template_only_nodes: true,
    #                               template_analysis: t_analysis,
    #                               dest_analysis: d_analysis)
    #   if result[:merged]
    #     builder.add_raw(result[:content])
    #   end
    #
    # @see SmartMergerBase#try_inner_merge_list_to_builder
    class ListMerger
      include Ast::Merge::JaccardSimilarity

      # Minimum Jaccard token overlap to consider two list items as matching.
      ITEM_MATCH_THRESHOLD = 0.35

      # Merge two list nodes.
      #
      # @param template_node [Object] Template list node (tree_haver / Markly node)
      # @param dest_node [Object] Destination list node
      # @param preference [Symbol] :template or :destination — which wins for matched items
      # @param add_template_only_nodes [Boolean] Whether to append template-only items
      # @param template_analysis [FileAnalysisBase] Template file analysis (for source text)
      # @param dest_analysis [FileAnalysisBase] Destination file analysis (for source text)
      # @return [Hash] { merged: Boolean, content: String } or { merged: false, reason: String }
      def merge_lists(template_node, dest_node,
                      preference:,
                      add_template_only_nodes: true,
                      template_analysis: nil,
                      dest_analysis: nil,
                      resolution_mode: :eager,
                      unresolved_policy: nil)
        t_items = extract_items(template_node)
        d_items = extract_items(dest_node)

        return not_merged('empty list') if t_items.empty? && d_items.empty?

        alignment = align_items(t_items, d_items)
        lines, unresolved_cases = emit_lines(
          alignment,
          template_node: template_node,
          dest_node: dest_node,
          preference: preference,
          add_template_only: add_template_only_nodes,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          resolution_mode: resolution_mode,
          unresolved_policy: Ast::Merge::UnresolvedPolicy.coerce(unresolved_policy)
        )
        return not_merged('no lines emitted') if lines.empty?

        {
          merged: true,
          content: lines.join("\n") + "\n",
          stats: { decision: unresolved_cases.empty? ? :merged : :unresolved },
          unresolved_cases: unresolved_cases
        }
      end

      private

      # --- item extraction ---

      def extract_items(list_node)
        raw = Ast::Merge::NodeTyping.unwrap(list_node)
        children =
          if raw.respond_to?(:to_a)
            raw.to_a
          elsif raw.respond_to?(:children)
            raw.children
          elsif raw.respond_to?(:each)
            raw.each.to_a
          else
            []
          end

        children.select do |item|
          item.respond_to?(:type) && %w[list_item item].include?(item.type.to_s)
        end
      end

      # --- alignment ---

      # Produce an ordered array of alignment entries, each one of:
      #   { type: :match,         template_item: …, dest_item: … }
      #   { type: :dest_only,     dest_item: … }
      #   { type: :template_only, template_item: … }
      def align_items(t_items, d_items)
        t_tokens = t_items.map { |i| item_tokens(i) }
        d_tokens = d_items.map { |i| item_tokens(i) }

        matched_t = Set.new
        matched_d = Set.new
        candidates = []

        t_items.each_with_index do |_t_item, ti|
          d_items.each_with_index do |_d_item, di|
            score = jaccard(t_tokens[ti], d_tokens[di])
            next if score < ITEM_MATCH_THRESHOLD

            candidates << { score: score, ti: ti, di: di }
          end
        end

        # Greedy best-first matching
        matches = {}        # ti => di
        reverse = {}        # di => ti
        candidates.sort_by { |c| -c[:score] }.each do |c|
          next if matched_t.include?(c[:ti]) || matched_d.include?(c[:di])

          matches[c[:ti]] = c[:di]
          reverse[c[:di]] = c[:ti]
          matched_t << c[:ti]
          matched_d << c[:di]
        end

        # Walk destination order, interleaving template-only items before the
        # dest item they were adjacent to in the template.
        result = []
        inserted_t = Set.new

        d_items.each_with_index do |d_item, di|
          # Before this dest item, insert any template-only items whose nearest
          # matched template neighbour falls before this point.
          t_items.each_with_index do |t_item, ti|
            next if matched_t.include?(ti) || inserted_t.include?(ti)

            # Find the first matched dest index for template items after ti
            next_matched_di = (ti + 1..t_items.size - 1).find { |k| matches.key?(k) }&.then { |k| matches[k] }
            insert_before = next_matched_di.nil? ? d_items.size : next_matched_di
            next if insert_before > di

            result << { type: :template_only, template_item: t_item }
            inserted_t << ti
          end

          if reverse.key?(di)
            ti = reverse[di]
            result << { type: :match, template_item: t_items[ti], dest_item: d_item }
          else
            result << { type: :dest_only, dest_item: d_item }
          end
        end

        # Append remaining template-only items that come after the last dest item
        t_items.each_with_index do |t_item, ti|
          next if matched_t.include?(ti) || inserted_t.include?(ti)

          result << { type: :template_only, template_item: t_item }
        end

        result
      end

      # --- emission ---

      def emit_lines(alignment, template_node:, dest_node:, preference:, add_template_only:,
                     template_analysis:, dest_analysis:, resolution_mode:, unresolved_policy:)
        counter = 1
        lines = []
        unresolved_cases = []
        current_offset = 0

        alignment.each do |entry|
          case entry[:type]
          when :match
            template_text = item_bare_text(entry[:template_item], template_analysis)
            dest_text = item_bare_text(entry[:dest_item], dest_analysis)
            if unresolved_match?(template_text, dest_text, resolution_mode: resolution_mode,
                                                           unresolved_policy: unresolved_policy)
              provisional_winner = unresolved_policy.provisional_winner_for(:matched_list_item, fallback: preference)
              selected_text = provisional_winner == :template ? template_text : dest_text
              line = format_list_line(counter, selected_text)
              lines << line
              unresolved_cases << build_unresolved_case(
                template_node: template_node,
                dest_node: dest_node,
                template_item: entry[:template_item],
                dest_item: entry[:dest_item],
                template_text: format_list_line(counter, template_text),
                dest_text: format_list_line(counter, dest_text),
                provisional_winner: provisional_winner,
                output_range: [current_offset, current_offset + line.bytesize],
                list_index: counter
              )
            else
              node = preference == :template ? entry[:template_item] : entry[:dest_item]
              analysis = preference == :template ? template_analysis : dest_analysis
              text = item_bare_text(node, analysis)
              lines << format_list_line(counter, text)
            end
            counter += 1
            current_offset += lines.last.bytesize + 1
          when :dest_only
            text = item_bare_text(entry[:dest_item], dest_analysis)
            lines << format_list_line(counter, text)
            counter += 1
            current_offset += lines.last.bytesize + 1
          when :template_only
            next unless add_template_only

            text = item_bare_text(entry[:template_item], template_analysis)
            lines << format_list_line(counter, text)
            counter += 1
            current_offset += lines.last.bytesize + 1
          end
        end

        [lines, unresolved_cases]
      end

      # Return the bare inline text of a list_item node (without the leading `1. ` marker).
      def item_bare_text(item, analysis)
        # Prefer source extraction for fidelity (preserves links, code spans, etc.)
        if analysis && item.respond_to?(:source_position)
          pos = item.source_position
          if pos
            raw = analysis.source_range(pos[:start_line], pos[:end_line]).strip
            # Strip the ordered-list marker: `1. `, `2. `, `123. ` etc.
            return raw.sub(/\A\d+\.\s+/, '')
          end
        end

        # Fallback: use .text and strip marker
        item.text.to_s.strip.sub(/\A\d+\.\s+/, '')
      end

      # --- token helpers ---

      def item_tokens(item)
        text = item.respond_to?(:text) ? item.text.to_s : ''
        extract_tokens(text)
      end

      def unresolved_match?(template_text, dest_text, resolution_mode:, unresolved_policy:)
        resolution_mode.to_sym == :unresolved &&
          unresolved_policy.unresolved_for?(:matched_list_item) &&
          template_text != dest_text
      end

      def format_list_line(counter, text)
        "#{counter}. #{text}"
      end

      def build_unresolved_case(template_node:, dest_node:, template_item:, dest_item:, template_text:, dest_text:,
                                provisional_winner:, output_range:, list_index:)
        template_lines = source_span_for(template_item)
        dest_lines = source_span_for(dest_item)
        reference_line = template_lines&.first || dest_lines&.first || list_index
        case_id = "markdown-matched_list_item-#{reference_line}-#{list_index}"

        Ast::Merge::Runtime::ResolutionCase.new(
          case_id: case_id,
          reason: :conflict,
          candidates: {
            template: template_text,
            destination: dest_text
          },
          provisional_winner: provisional_winner,
          surface_path: "#{list_surface_path(template_node, dest_node)} > matched_list_item[index=#{list_index}]",
          metadata: {
            template_lines: template_lines,
            destination_lines: dest_lines,
            match_kind: :matched_list_item,
            list_index: list_index,
            relative_output_range: output_range
          }.compact
        )
      end

      def list_surface_path(template_node, dest_node)
        template_lines = source_span_for(template_node)
        dest_lines = source_span_for(dest_node)
        start_line, end_line = template_lines || dest_lines

        if start_line && end_line
          "document[0] > list[L#{start_line}-L#{end_line}]"
        else
          'document[0] > list'
        end
      end

      def source_span_for(node)
        raw = Ast::Merge::NodeTyping.unwrap(node)
        return unless raw.respond_to?(:source_position)

        position = raw.source_position
        start_line = position&.dig(:start_line)
        end_line = position&.dig(:end_line)
        return unless start_line && end_line

        [start_line, end_line]
      end

      def not_merged(reason)
        { merged: false, reason: reason }
      end
    end
  end
end
