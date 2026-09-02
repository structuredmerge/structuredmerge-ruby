# frozen_string_literal: true

module Prism
  module Merge
    class NodeEmissionSupport
      include Prism::Merge::SourceLineLookup

      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def emit_dest_prefix_lines(result:, analysis:)
        merger.instance_variable_set(:@dest_prefix_comment_lines, Set.new)
        return 0 if analysis.statements.empty?

        first_node = analysis.statements.first
        leading_comments = first_node.location.respond_to?(:leading_comments) ? first_node.location.leading_comments : []
        first_content_line = leading_comments.any? ? leading_comments.first.location.start_line : first_node.location.start_line
        last_emitted = 0
        prefix_line_numbers = Prism::Merge::MagicCommentSupport.prefix_comment_line_numbers_for_comments(leading_comments)

        if first_content_line > 1
          (1...first_content_line).each do |line_num|
            line = required_source_line(
              analysis,
              line_num,
              context: 'emitting destination prefix line'
            )
            result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
            dest_prefix_comment_lines << line_num
            last_emitted = line_num
          end
        end

        return last_emitted if prefix_line_numbers.empty?

        leading_comments.each do |comment|
          line_num = comment.location.start_line
          next unless prefix_line_numbers.include?(line_num)

          line = required_comment_line(
            analysis,
            comment,
            context: 'emitting destination prefix comment'
          )

          result.add_line(line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: line_num)
          dest_prefix_comment_lines << line_num
          last_emitted = line_num
        end

        next_content_line = if leading_comments.any? && prefix_line_numbers.any?
                              next_comment = leading_comments.find do |comment|
                                !prefix_line_numbers.include?(comment.location.start_line)
                              end
                              next_comment ? next_comment.location.start_line : first_node.location.start_line
                            else
                              first_node.location.start_line
                            end

        if next_content_line > last_emitted + 1
          ((last_emitted + 1)...next_content_line).each do |gap_num|
            gap_line = required_source_line(
              analysis,
              gap_num,
              context: 'emitting destination prefix gap line'
            )
            next unless gap_line.strip.empty?

            result.add_line(gap_line, decision: MergeResult::DECISION_KEPT_DEST, dest_line: gap_num)
            dest_prefix_comment_lines << gap_num
            last_emitted = gap_num
          end
        end

        last_emitted
      end

      def emit_removed_destination_node_comments(result:, node:, analysis:)
        decision = MergeResult::DECISION_KEPT_DEST
        last_emitted_dest_line = nil
        rehomed_orphan_lines = merger.send(:wrapper_comment_support).orphan_line_numbers_for(:destination).to_set
        leading = merger.send(:filtered_leading_comments_for, node, :destination)
        leading_comments = filter_rehomed_removed_owner_comments(
          leading[:comments],
          rehomed_orphan_lines: rehomed_orphan_lines,
          comment_role: :leading
        )

        merger.send(
          :emit_leading_comments,
          result,
          leading_comments,
          analysis: analysis,
          source: :destination,
          decision: decision
        )

        if leading_comments.any?
          last_emitted_dest_line = leading_comments.last.location.start_line
          emitted_gap_line = merger.send(
            :emit_blank_lines_between,
            result,
            last_comment_line: leading_comments.last.location.start_line,
            next_content_line: node.location.start_line,
            analysis: analysis,
            source: :destination,
            decision: decision
          )
          last_emitted_dest_line = emitted_gap_line if emitted_gap_line
        end

        inline_entries = analysis.send(:owner_inline_comment_entries, node)
        if inline_entries.any?
          indentation = line_indentation(analysis, node.location.end_line)

          inline_entries.each do |entry|
            result.add_line(
              "#{indentation}#{entry[:raw].strip}",
              decision: decision,
              dest_line: entry[:line]
            )
            last_emitted_dest_line = entry[:line]
          end
        end

        trailing_comments = filter_rehomed_removed_owner_comments(
          merger.send(:external_trailing_comments_for, node, analysis: analysis),
          rehomed_orphan_lines: rehomed_orphan_lines,
          comment_role: :external_trailing
        )
        if trailing_comments.any?
          emitted_dest_line = merger.send(
            :emit_external_trailing_comments,
            result,
            trailing_comments,
            source_node: node,
            analysis: analysis,
            source: :destination,
            decision: decision
          )
          last_emitted_dest_line = emitted_dest_line if emitted_dest_line
        end

        {
          last_emitted_dest_line: last_emitted_dest_line,
          emitted_removed_owner_comments: true
        }
      end

      def emit_dest_gap_lines(result:, analysis:, last_output_line:, next_node:)
        return last_output_line if last_output_line.zero?

        leading_comments = next_node.location.respond_to?(:leading_comments) ? next_node.location.leading_comments : []
        pending_leading_comments = leading_comments.select do |comment|
          comment.location.start_line > last_output_line
        end
        next_start_line = pending_leading_comments.any? ? pending_leading_comments.first.location.start_line : next_node.location.start_line
        gap_start = last_output_line + 1
        return last_output_line if gap_start >= next_start_line

        if pending_leading_comments.empty?
          emitted_gap_line = emit_layout_leading_gap_lines(
            result: result,
            analysis: analysis,
            owner: next_node,
            source: :destination,
            decision: MergeResult::DECISION_KEPT_DEST,
            last_output_line: last_output_line
          )
          return [last_output_line, emitted_gap_line].max if emitted_gap_line
        end

        emitted_gap_line = emit_scanned_blank_gap_lines(
          result: result,
          analysis: analysis,
          source: :destination,
          decision: MergeResult::DECISION_KEPT_DEST,
          line_numbers: gap_start...next_start_line
        )

        emitted_gap_line ? [last_output_line, emitted_gap_line].max : last_output_line
      end

      def emit_matched_template_node(result:, template_node:, dest_node:)
        decision = MergeResult::DECISION_KEPT_TEMPLATE
        last_emitted_dest_line = nil
        last_filtered_leading_line = nil
        result_line_span = nil

        template_analysis = merger.template_analysis
        dest_analysis = merger.dest_analysis
        template_leading = merger.send(:filtered_leading_comments_for, template_node, :template)
        dest_leading = merger.send(:filtered_leading_comments_for, dest_node, :destination)

        filtered_template_leading = filter_previous_destination_owned_template_leading_comments(
          template_node: template_node,
          dest_node: dest_node,
          template_comments: template_leading[:comments],
          dest_comments: dest_leading[:comments]
        )
        template_leading = template_leading.merge(comments: filtered_template_leading)

        leading_comments = template_leading[:comments]
        leading_analysis = template_analysis

        if leading_comments.empty? && dest_leading[:comments].any?
          leading_comments = dest_leading[:comments]
          leading_analysis = dest_analysis
        end

        # Bidirectional dedup: filter out leading comments whose text was
        # already emitted by a preceding dest-only or template-only node.
        if leading_comments.any?
          leading_comments, last_filtered_leading_line = filter_emitted_template_trailing_comments(leading_comments)
          if leading_analysis.equal?(dest_analysis)
            leading_comments, last_filtered_leading_line = filter_emitted_template_leading_comments(
              leading_comments,
              last_filtered_line: last_filtered_leading_line
            )
          end

          leading_comments, last_filtered_leading_line = filter_already_emitted_leading_comments(leading_comments)
        end

        if leading_analysis.equal?(template_analysis)
          emit_template_blank_lines_before_leading_comments(
            result: result,
            node: template_node,
            analysis: template_analysis,
            leading_comments: leading_comments,
            skipped_prefix_line: template_leading[:last_skipped_line],
            skip_for_destination_gap: destination_gap_already_precedes_template_leading_comments?(result, dest_node),
            decision: decision
          )
        end

        merger.send(
          :emit_leading_comments,
          result,
          leading_comments,
          analysis: leading_analysis,
          source: leading_analysis.equal?(template_analysis) ? :template : :destination,
          decision: decision,
          prev_comment_line: last_filtered_leading_line
        )

        # Track emitted leading comments for bidirectional dedup so that
        # subsequent unmatched or matched nodes can filter duplicates.
        if leading_comments.any?
          if leading_analysis.equal?(template_analysis)
            track_emitted_template_leading_comments(leading_comments)
          else
            track_emitted_dest_leading_comments(leading_comments)
          end
        end

        if leading_analysis.equal?(dest_analysis) && leading_comments.any?
          last_emitted_dest_line = leading_comments.last.location.start_line
        end

        if leading_comments.any?
          emitted_gap_line = merger.send(
            :emit_blank_lines_between,
            result,
            last_comment_line: leading_comments.last.location.start_line,
            next_content_line: leading_analysis.equal?(template_analysis) ? template_node.location.start_line : dest_node.location.start_line,
            analysis: leading_analysis,
            source: leading_analysis.equal?(template_analysis) ? :template : :destination,
            decision: decision
          )
          last_emitted_dest_line = emitted_gap_line if leading_analysis.equal?(dest_analysis) && emitted_gap_line
        end

        template_inline_entries = template_analysis.send(:owner_inline_comment_entries, template_node)
        dest_inline_entries = dest_analysis.send(:owner_inline_comment_entries, dest_node)
        inline_entries = template_inline_entries.any? ? template_inline_entries : dest_inline_entries

        template_source_lines = template_node_source_lines(template_node, template_analysis)
        node_result_start_line = result.line_count + 1
        template_source_lines.each_with_index do |line, index|
          line_num = template_node.location.start_line + index

          if index == template_source_lines.length - 1 &&
             template_inline_entries.empty? && inline_entries.any?
            line = merger.send(:append_inline_comment_entries, line, inline_entries)
          end

          result.add_line(line, decision: decision, template_line: line_num)
        end
        result_line_span = [node_result_start_line, result.line_count] if template_source_lines.any?

        template_claimed = template_analysis.respond_to?(:claimed_lines) ? template_analysis.claimed_lines : Set.new
        dest_claimed = dest_analysis.respond_to?(:claimed_lines) ? dest_analysis.claimed_lines : Set.new
        template_trailing_comments = merger.send(:wrapper_comment_support).external_trailing_comments_for(
          template_node, analysis: template_analysis, claimed_lines: template_claimed
        )
        dest_trailing_comments = merger.send(:wrapper_comment_support).external_trailing_comments_for(
          dest_node,
          analysis: dest_analysis,
          claimed_lines: dest_claimed
        )
        trailing_comments = template_trailing_comments.any? ? template_trailing_comments : dest_trailing_comments
        trailing_analysis = template_trailing_comments.any? ? template_analysis : dest_analysis
        trailing_source = trailing_analysis.equal?(template_analysis) ? :template : :destination
        trailing_node = trailing_analysis.equal?(template_analysis) ? template_node : dest_node

        if trailing_comments.any?
          emitted_dest_line = merger.send(
            :emit_external_trailing_comments,
            result,
            trailing_comments,
            source_node: trailing_node,
            analysis: trailing_analysis,
            source: trailing_source,
            decision: decision
          )
          last_emitted_dest_line = emitted_dest_line if trailing_analysis.equal?(dest_analysis) && emitted_dest_line
          track_emitted_template_trailing_comments(trailing_comments) if trailing_analysis.equal?(template_analysis)
        end

        orphan_regions, orphan_analysis = selected_orphan_regions_for(
          template_node: template_node,
          dest_node: dest_node,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis
        )
        if orphan_regions.any?
          orphan_previous_line = if trailing_comments.any?
                                   trailing_comments.last.location.start_line
                                 else
                                   orphan_analysis.equal?(template_analysis) ? template_node.location.end_line : dest_node.location.end_line
                                 end
          emitted_orphan_line = merger.send(:wrapper_comment_support).emit_orphan_regions(
            result,
            orphan_regions,
            analysis: orphan_analysis,
            source: orphan_analysis.equal?(template_analysis) ? :template : :destination,
            decision: decision,
            previous_line: orphan_previous_line
          )
          last_emitted_dest_line = emitted_orphan_line if orphan_analysis.equal?(dest_analysis) && emitted_orphan_line
        end

        if trailing_comments.any?
          return {
            last_emitted_dest_line: last_emitted_dest_line,
            preserve_trailing_blank_line_progress: true,
            result_line_span: result_line_span
          }
        end

        # Emit the template's trailing blank line when one exists immediately after the
        # matched template node. This restores blank lines that may have been dropped in
        # a prior merge (dest lost the blank, but template still has it). Mirrors the
        # same trailing-blank logic in `emit_node` so behaviour is consistent.
        # Only emit when this node controls the trailing gap per gap ownership rules.
        if orphan_regions.empty?
          trailing_line = effective_end_line(template_node) + 1
          trailing_content = template_analysis.line_at(trailing_line)
          if trailing_content && trailing_content.strip.empty? && template_node_controls_trailing_gap?(template_node,
                                                                                                       template_analysis, dest_node, dest_analysis)
            result.add_line('', decision: decision, template_line: trailing_line)
            # Advance last_emitted_dest_line to the corresponding dest position so that
            # emit_dest_gap_lines on the next iteration does not double-emit the blank.
            dest_trailing_line = dest_node.location.end_line + 1
            last_emitted_dest_line = [last_emitted_dest_line.to_i, dest_trailing_line].max
          end
        end

        { last_emitted_dest_line: last_emitted_dest_line, result_line_span: result_line_span }
      end

      def emit_node(result:, node:, analysis:, source:, matched_template_node: nil)
        decision = source == :template ? MergeResult::DECISION_KEPT_TEMPLATE : MergeResult::DECISION_KEPT_DEST
        last_emitted_dest_line = nil
        result_line_span = nil
        leading = merger.send(:filtered_leading_comments_for, node, source)
        leading_comments = leading[:comments]
        last_filtered_leading_line = nil

        if source == :destination
          leading_comments, = collapse_matched_template_leading_prefix(
            leading_comments,
            matched_template_node
          )
          leading_comments, last_filtered_leading_line = filter_emitted_template_trailing_comments(leading_comments)
          leading_comments, last_filtered_leading_line = filter_emitted_template_leading_comments(
            leading_comments,
            last_filtered_line: last_filtered_leading_line
          )
          track_emitted_dest_leading_comments(leading_comments)
        elsif source == :template
          leading_comments, trailing_filtered_line = filter_emitted_template_trailing_comments(leading_comments)
          leading_comments, emitted_leading_line = filter_already_emitted_leading_comments(leading_comments)
          last_filtered_leading_line = emitted_leading_line || trailing_filtered_line
          track_emitted_template_leading_comments(leading_comments)
        end

        inline_comment_entries = analysis.send(:owner_inline_comment_entries, node)

        if source == :template
          if leading_comments.empty?
            last_emitted_template_line = result.line_metadata.reverse_each.find do |metadata|
              metadata[:template_line]
            end&.fetch(:template_line, 0) || 0
            emit_layout_leading_gap_lines(
              result: result,
              analysis: analysis,
              owner: node,
              source: source,
              decision: decision,
              last_output_line: last_emitted_template_line
            )
          end
          emit_template_blank_lines_before_leading_comments(
            result: result,
            node: node,
            analysis: analysis,
            leading_comments: leading_comments,
            skipped_prefix_line: leading[:last_skipped_line],
            decision: decision
          )
        end

        merger.send(
          :emit_leading_comments,
          result,
          leading_comments,
          analysis: analysis,
          source: source,
          decision: decision,
          prev_comment_line: last_filtered_leading_line
        )

        if leading_comments.any?
          last_comment_line = leading_comments.last.location.start_line
          if node.location.start_line > last_comment_line + 1
            ((last_comment_line + 1)...node.location.start_line).each do |line_num|
              next if dest_prefix_comment_lines.include?(line_num)

              line = required_source_line(
                analysis,
                line_num,
                context: 'emitting blank line between leading comments and node'
              )
              if source == :template
                result.add_line(line, decision: decision, template_line: line_num)
              else
                result.add_line(line, decision: decision, dest_line: line_num)
                last_emitted_dest_line = line_num
              end
            end
          end
        end

        source_lines = node_source_lines(node, analysis)
        node_result_start_line = result.line_count + 1
        source_lines.each_with_index do |line, index|
          line_num = node.location.start_line + index

          if index == source_lines.length - 1 && partial_same_line_node?(node, analysis) && inline_comment_entries.any?
            line = append_owned_inline_entries(line, inline_comment_entries)
          end

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
            last_emitted_dest_line = line_num
          end
        end
        result_line_span = [node_result_start_line, result.line_count] if source_lines.any?

        claimed = analysis.respond_to?(:claimed_lines) ? analysis.claimed_lines : Set.new
        trailing_comments = merger.send(:wrapper_comment_support).external_trailing_comments_for(
          node,
          analysis: analysis,
          claimed_lines: claimed
        )
        trailing_analysis = analysis
        trailing_source = source
        trailing_node = node
        if source == :destination && matched_template_node
          template_claimed = if merger.template_analysis.respond_to?(:claimed_lines)
                               merger.template_analysis.claimed_lines
                             else
                               Set.new
                             end
          template_trailing_comments = merger.send(:wrapper_comment_support).external_trailing_comments_for(
            matched_template_node,
            analysis: merger.template_analysis,
            claimed_lines: template_claimed
          )
          if template_trailing_comments.any?
            trailing_comments = template_trailing_comments
            trailing_analysis = merger.template_analysis
            trailing_source = :template
            trailing_node = matched_template_node
          end
        end
        orphan_regions = orphan_regions_for(node, analysis: analysis, source: source)

        if trailing_comments.empty? && orphan_regions.empty?
          if analysis.respond_to?(:layout_attachment_for)
            trailing_gap = analysis.layout_attachment_for(node)&.trailing_gap
          end
          emitted_trailing_gap_line = emit_layout_trailing_gap_lines(
            result: result,
            analysis: analysis,
            owner: node,
            source: source,
            decision: decision
          )

          if emitted_trailing_gap_line.nil?
            # When layout ownership assigns the gap to a later sibling's leading gap,
            # do not emit a single synthetic blank separator here and truncate the run.
            gap_owned_by_later_destination_sibling =
              source == :destination && trailing_gap && !trailing_gap.controls_output_for?(node)

            unless gap_owned_by_later_destination_sibling
              trailing_line = effective_end_line(node) + 1
              trailing_content = analysis.line_at(trailing_line)
              if trailing_content && trailing_content.strip.empty?
                if source == :template
                  result.add_line('', decision: decision, template_line: trailing_line)
                else
                  result.add_line('', decision: decision, dest_line: trailing_line)
                  last_emitted_dest_line = trailing_line
                end
              end
            end
          elsif source == :destination
            last_emitted_dest_line = emitted_trailing_gap_line
          end
        end

        trailing_comments.each do |comment|
          line_num = comment.location.start_line

          line = required_comment_line(
            trailing_analysis,
            comment,
            context: 'emitting external trailing comment'
          )

          if trailing_source == :template
            result.add_line(line, decision: decision, template_line: line_num)
            track_emitted_template_trailing_comments([comment])
          else
            result.add_line(line, decision: decision, dest_line: line_num)
            last_emitted_dest_line = line_num
          end
        end

        if orphan_regions.any?
          orphan_previous_line = if trailing_comments.any?
                                   trailing_comments.last.location.start_line
                                 else
                                   effective_end_line(trailing_node)
                                 end
          emitted_orphan_line = merger.send(:wrapper_comment_support).emit_orphan_regions(
            result,
            orphan_regions,
            analysis: analysis,
            source: source,
            decision: decision,
            previous_line: orphan_previous_line
          )
          last_emitted_dest_line = emitted_orphan_line if source == :destination && emitted_orphan_line
        end

        { last_emitted_dest_line: last_emitted_dest_line, result_line_span: result_line_span }
      end

      private

      def filter_previous_destination_owned_template_leading_comments(template_node:, dest_node:, template_comments:,
                                                                      dest_comments:)
        return template_comments if template_comments.empty? || dest_comments.any?

        previous_dest_node = previous_destination_statement_for(dest_node)
        return template_comments unless previous_dest_node
        return template_comments unless adjacent_destination_statements?(previous_dest_node, dest_node)

        previous_dest_leading = merger.send(:filtered_leading_comments_for, previous_dest_node, :destination)[:comments]
        return template_comments if previous_dest_leading.empty?

        unless normalized_comment_block(previous_dest_leading) == normalized_comment_block(template_comments)
          return template_comments
        end

        should_heal = merger.send(
          :handle_suspected_corruption,
          kind: :comment_ownership_overlap,
          message: 'template-leading comment block overlaps previous adjacent destination leading comment ownership'
        )
        should_heal ? [] : template_comments
      end

      def previous_destination_statement_for(node)
        statements = merger.dest_analysis.statements
        index = statements.index { |statement| statement.equal?(node) }
        return unless index&.positive?

        statements[index - 1]
      end

      def previous_statement_for(node, analysis)
        statements = analysis.statements
        index = statements.index { |statement| statement.equal?(node) }
        return unless index&.positive?

        statements[index - 1]
      end

      def adjacent_destination_statements?(previous_node, current_node)
        previous_node.location.end_line + 1 == current_node.location.start_line
      end

      def normalized_comment_block(comments)
        comments.map { |comment| comment.slice.to_s.rstrip }
      end

      def template_node_source_lines(node, analysis)
        node_source_lines(node, analysis)
      end

      def emit_template_blank_lines_before_leading_comments(result:, node:, analysis:, leading_comments:,
                                                            skipped_prefix_line:, decision:, skip_for_destination_gap: false)
        return if skipped_prefix_line || skip_for_destination_gap
        return if leading_comments.empty?
        return if previous_template_gap_already_precedes_leading_comments?(result, node, analysis, leading_comments)

        previous_node = previous_statement_for(node, analysis)
        return unless previous_node

        first_comment_line = leading_comments.first.location.start_line
        gap_start_line = previous_node.location.end_line + 1
        return if gap_start_line >= first_comment_line

        emit_scanned_blank_gap_lines(
          result: result,
          analysis: analysis,
          source: :template,
          decision: decision,
          line_numbers: gap_start_line...first_comment_line
        )
      end

      def destination_gap_already_precedes_template_leading_comments?(_result, dest_node)
        previous_dest_node = previous_destination_statement_for(dest_node)
        return false unless previous_dest_node

        dest_leading = merger.send(:filtered_leading_comments_for, dest_node, :destination)[:comments]
        first_dest_content_line = dest_leading.any? ? dest_leading.first.location.start_line : dest_node.location.start_line

        # Structural check: does the dest have a blank-line gap before this node?
        # If so, the dest spacing is adequate and template gap emission should be
        # suppressed — regardless of whether the gap was emitted as a dest line or
        # a template line (which happens when preference: :template).
        blank_only_gap_between?(
          analysis: merger.dest_analysis,
          start_line: previous_dest_node.location.end_line + 1,
          end_line_exclusive: first_dest_content_line
        )
      end

      def previous_template_gap_already_precedes_leading_comments?(result, node, analysis, leading_comments)
        previous_node = previous_statement_for(node, analysis)
        return false unless previous_node
        return false unless analysis.respond_to?(:layout_attachment_for)

        trailing_gap = analysis.layout_attachment_for(previous_node)&.trailing_gap
        return false unless trailing_gap

        first_comment_line = leading_comments.first.location.start_line
        unless trailing_gap.start_line == previous_node.location.end_line + 1 && trailing_gap.end_line == first_comment_line - 1
          return false
        end

        last_emitted_template_line = result.line_metadata.reverse_each.find do |metadata|
          metadata[:template_line]
        end&.fetch(:template_line)
        last_emitted_template_line == trailing_gap.end_line
      end

      def gap_contains_blank_lines?(analysis:, start_line:, end_line_exclusive:)
        return false if start_line >= end_line_exclusive

        (start_line...end_line_exclusive).any? do |line_num|
          analysis.line_at(line_num).to_s.strip.empty?
        end
      end

      def blank_only_gap_between?(analysis:, start_line:, end_line_exclusive:)
        return false if start_line >= end_line_exclusive

        lines = (start_line...end_line_exclusive).map { |line_num| analysis.line_at(line_num).to_s }
        lines.any? && lines.all? { |line| line.strip.empty? }
      end

      # Returns true when the template node should emit a trailing blank line
      # according to the gap ownership system. Postlude gaps (trailing blank at
      # end of file) are suppressed when the matched dest node is NOT also at
      # the end of the dest file — the template's end-of-file whitespace should
      # not be injected mid-output when the node has been repositioned.
      # Interstitial gaps always pass (blank restoration from template is desired).
      def template_node_controls_trailing_gap?(template_node, template_analysis, dest_node = nil, dest_analysis = nil)
        attachment = template_analysis.layout_attachment_for(template_node)
        trailing_gap = attachment.trailing_gap
        return true unless trailing_gap
        return true unless trailing_gap.postlude?

        # Postlude gap: only emit if dest node is also at end of file
        return true unless dest_node && dest_analysis

        dest_attachment = dest_analysis.layout_attachment_for(dest_node)
        dest_trailing = dest_attachment.trailing_gap
        dest_trailing&.postlude? || false
      end

      def orphan_regions_for(node, analysis:, source:)
        merger.send(:wrapper_comment_support).orphan_regions_for(node, source: source, analysis: analysis)
      end

      def selected_orphan_regions_for(template_node:, dest_node:, template_analysis:, dest_analysis:)
        template_orphans = orphan_regions_for(template_node, analysis: template_analysis, source: :template)
        return [template_orphans, template_analysis] if template_orphans.any?

        [orphan_regions_for(dest_node, analysis: dest_analysis, source: :destination), dest_analysis]
      end

      def append_owned_inline_entries(line, entries)
        merger.send(:append_inline_comment_entries, line, entries)
      end

      def node_source_lines(node, analysis)
        if partial_same_line_node?(node, analysis)
          ["#{line_indentation(analysis, node.location.start_line)}#{node.slice}"]
        else
          (node.location.start_line..effective_end_line(node)).map do |line_num|
            required_source_line(
              analysis,
              line_num,
              context: 'emitting analyzed node source line'
            )
          end
        end
      end

      # Prism records heredoc nodes' location as just the opening token line (e.g. <<~MESSAGE),
      # while the body and terminator appear on subsequent lines tracked via closing_loc.
      # This method computes the true last line of a node, including any heredoc body/terminator.
      def effective_end_line(node)
        max_end = node.location.end_line
        return max_end unless node.respond_to?(:compact_child_nodes)

        node.compact_child_nodes.each do |child|
          max_end = [max_end, child.closing_loc.start_line].max if child.respond_to?(:closing_loc) && child.closing_loc
          max_end = [max_end, effective_end_line(child)].max
        end
        max_end
      end

      def partial_same_line_node?(node, analysis)
        return false unless node.location.start_line == node.location.end_line

        line_num = node.location.start_line
        line_start_offset = analysis.lines.take(line_num - 1).sum(&:bytesize)
        line_end_offset = line_start_offset + analysis.line_at(line_num).to_s.bytesize
        prefix = analysis.source.byteslice(line_start_offset...node_start_offset(node)).to_s
        suffix = analysis.source.byteslice(node_end_offset(node)...line_end_offset).to_s
        prefix_has_code = !prefix.strip.empty?
        suffix_content = suffix.sub(/\r?\n\z/, '').lstrip
        suffix_has_code = !suffix_content.empty? && !suffix_content.start_with?('#')

        prefix_has_code || suffix_has_code
      end

      def node_start_offset(node)
        if node.location.respond_to?(:start_offset)
          node.location.start_offset
        elsif node.respond_to?(:start_byte)
          node.start_byte
        else
          0
        end
      end

      def node_end_offset(node)
        if node.location.respond_to?(:end_offset)
          node.location.end_offset
        elsif node.respond_to?(:end_byte)
          node.end_byte
        else
          node_start_offset(node) + node.slice.to_s.bytesize
        end
      end

      def line_indentation(analysis, line_num)
        analysis.line_at(line_num).to_s[/\A\s*/].to_s
      end

      def prism_magic_comment?(comment)
        !!Prism::Merge::MagicCommentSupport.magic_comment_type_for_text(comment.slice)
      end

      def shebang_comment?(comment)
        comment.slice.start_with?('#!')
      end

      def dest_prefix_comment_lines
        merger.instance_variable_get(:@dest_prefix_comment_lines) || Set.new
      end

      def emit_layout_leading_gap_lines(result:, analysis:, owner:, source:, decision:, last_output_line:)
        return unless analysis.respond_to?(:layout_attachment_for)

        attachment = analysis.layout_attachment_for(owner)
        gap = attachment&.leading_gap
        return unless gap
        return unless gap.controls_output_for?(owner)

        emit_scanned_blank_gap_lines(
          result: result,
          analysis: analysis,
          source: source,
          decision: decision,
          line_numbers: [gap.start_line, last_output_line + 1].max..gap.end_line
        )
      end

      def emit_layout_trailing_gap_lines(result:, analysis:, owner:, source:, decision:)
        return unless analysis.respond_to?(:layout_attachment_for)

        attachment = analysis.layout_attachment_for(owner)
        gap = attachment&.trailing_gap
        return unless gap
        return unless gap.controls_output_for?(owner)

        emit_scanned_blank_gap_lines(
          result: result,
          analysis: analysis,
          source: source,
          decision: decision,
          line_numbers: gap.start_line..gap.end_line
        )
      end

      def track_emitted_template_trailing_comments(comments)
        set = merger.instance_variable_get(:@emitted_template_trailing_texts) || Set.new
        comments.each { |c| set << c.slice.strip }
        merger.instance_variable_set(:@emitted_template_trailing_texts, set)
      end

      def filter_emitted_template_trailing_comments(comments)
        template_trailing_texts = merger.instance_variable_get(:@emitted_template_trailing_texts)
        return [comments, nil] unless template_trailing_texts&.any?

        last_filtered_line = nil
        filtered = Ast::Merge::Healer.filter_items(
          comments,
          mode: merger.corruption_handling,
          prefix: '[prism-merge]',
          error_class: Prism::Merge::CorruptionDetectedError,
          kind: :comment_ownership_overlap,
          message: 'destination-leading comment block overlaps previously emitted template trailing comment ownership',
          on_filter: ->(comment) { last_filtered_line = comment.location.start_line }
        ) { |comment| template_trailing_texts.include?(comment.slice.strip) }
        [filtered, last_filtered_line]
      end

      # Track leading comments emitted for template-only nodes so that identical
      # comment blocks on subsequent destination-frozen nodes can be deduplicated.
      def track_emitted_template_leading_comments(comments)
        set = merger.instance_variable_get(:@emitted_template_leading_texts) || Set.new
        comments.each { |c| set << c.slice.strip }
        merger.instance_variable_set(:@emitted_template_leading_texts, set)
      end

      # Remove dest leading comments that were already emitted as leading comments
      # of a preceding template-only node.
      #
      # Filtered comment line numbers are also added to @dest_prefix_comment_lines so
      # that emit_leading_comments's gap-filler (which emits all lines between retained
      # comments) skips them instead of re-emitting the comment text.
      def filter_emitted_template_leading_comments(comments, last_filtered_line: nil)
        template_leading_texts = merger.instance_variable_get(:@emitted_template_leading_texts)
        return [comments, last_filtered_line] unless template_leading_texts&.any?

        prefix_lines = merger.instance_variable_get(:@dest_prefix_comment_lines) || Set.new

        filtered = Ast::Merge::Healer.filter_items(
          comments,
          mode: merger.corruption_handling,
          prefix: '[prism-merge]',
          error_class: Prism::Merge::CorruptionDetectedError,
          kind: :comment_ownership_overlap,
          message: 'destination-leading comment block overlaps previously emitted template leading comment ownership',
          on_filter: lambda do |comment|
            last_filtered_line = comment.location.start_line
            prefix_lines << last_filtered_line
          end
        ) { |comment| template_leading_texts.include?(comment.slice.strip) }

        merger.instance_variable_set(:@dest_prefix_comment_lines, prefix_lines)
        [filtered, last_filtered_line]
      end

      # Track leading comments emitted for destination nodes so that identical
      # comment blocks on subsequent template nodes can be deduplicated.
      # This is the dest→template direction of bidirectional dedup.
      def track_emitted_dest_leading_comments(comments)
        set = merger.instance_variable_get(:@emitted_dest_leading_texts) || Set.new
        comments.each { |c| set << c.slice.strip }
        merger.instance_variable_set(:@emitted_dest_leading_texts, set)
      end

      # Remove leading comments whose text was already emitted by an earlier
      # node from either source. Prism can attach the same gap-separated
      # (floating) comment block to different nodes in template and
      # destination, including when both sides already contain the comment.
      def filter_already_emitted_leading_comments(comments)
        emitted_texts = Set.new
        emitted_texts.merge(merger.instance_variable_get(:@emitted_dest_leading_texts).to_a)
        emitted_texts.merge(merger.instance_variable_get(:@emitted_template_leading_texts).to_a)
        return [comments, nil] if emitted_texts.empty?

        last_filtered_line = nil
        filtered = Ast::Merge::Healer.filter_items(
          comments,
          mode: merger.corruption_handling,
          prefix: '[prism-merge]',
          error_class: Prism::Merge::CorruptionDetectedError,
          kind: :comment_ownership_overlap,
          message: 'template-leading comment block overlaps previously emitted leading comment ownership',
          on_filter: ->(comment) { last_filtered_line = comment.location.start_line }
        ) { |comment| emitted_texts.include?(comment.slice.strip) }
        [filtered, last_filtered_line]
      end

      def collapse_matched_template_leading_prefix(dest_comments, matched_template_node)
        return [dest_comments, nil] unless matched_template_node
        return [dest_comments, nil] if dest_comments.empty?

        template_comments = merger.send(:filtered_leading_comments_for, matched_template_node, :template)[:comments]
        return [dest_comments, nil] if template_comments.empty?

        template_block = normalized_comment_block(template_comments)
        return [dest_comments, nil] if template_block.empty?
        return [dest_comments, nil] unless suspicious_duplicate_template_prefix?(dest_comments, template_block)
        return [dest_comments, nil] unless merger.send(
          :handle_suspected_corruption,
          kind: :duplicate_template_leading_prefix,
          message: 'matched destination node starts with duplicated template-owned leading comment block'
        )

        filtered = dest_comments
        last_filtered_line = nil

        while filtered.length > template_block.length &&
              normalized_comment_block(filtered.first(template_block.length)) == template_block
          removed = filtered.first(template_block.length)
          last_filtered_line = removed.last.location.start_line
          filtered = filtered.drop(template_block.length)
        end

        [filtered, last_filtered_line]
      end

      def suspicious_duplicate_template_prefix?(dest_comments, template_block)
        dest_comments.length > template_block.length &&
          normalized_comment_block(dest_comments.first(template_block.length)) == template_block
      end

      def filter_rehomed_removed_owner_comments(comments, rehomed_orphan_lines:, comment_role:)
        return comments if comments.empty? || rehomed_orphan_lines.empty?

        Ast::Merge::Healer.filter_items(
          comments,
          mode: merger.corruption_handling,
          prefix: '[prism-merge]',
          error_class: Prism::Merge::CorruptionDetectedError,
          kind: :removed_owner_comment_overlap,
          message: "removed destination-only node #{comment_role.to_s.tr('_',
                                                                         '-')} comments overlap orphan comment regions already rehomed onto a retained owner"
        ) { |comment| rehomed_orphan_lines.include?(comment.location.start_line) }
      end

      def emit_scanned_blank_gap_lines(result:, analysis:, source:, decision:, line_numbers:)
        last_emitted_line = nil

        line_numbers.each do |line_num|
          next if source == :destination && dest_prefix_comment_lines.include?(line_num)

          line = required_source_line(
            analysis,
            line_num,
            context: 'emitting scanned blank gap line'
          )
          next unless line.strip.empty?

          if source == :template
            result.add_line(line, decision: decision, template_line: line_num)
          else
            result.add_line(line, decision: decision, dest_line: line_num)
          end

          last_emitted_line = line_num
        end

        last_emitted_line
      end
    end
  end
end
