# frozen_string_literal: true

module Prism
  module Merge
    class RecursiveNodeBodyMerger
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def merge(template_node:, dest_node:)
        actual_template = template_node.respond_to?(:unwrap) ? template_node.unwrap : template_node
        actual_dest = dest_node.respond_to?(:unwrap) ? dest_node.unwrap : dest_node
        template_layout = merger.send(:node_body_layout_for, actual_template, merger.template_analysis)
        dest_layout = merger.send(:node_body_layout_for, actual_dest, merger.dest_analysis)

        template_body = merger.send(:extract_node_body, actual_template, merger.template_analysis)
        dest_body = merger.send(:extract_node_body, actual_dest, merger.dest_analysis)

        # When the gemspec block uses different variable names (e.g. |gem| vs |spec|),
        # rewrite the destination body to match the template's variable name.
        # The template variable ALWAYS wins regardless of merge preference because the
        # downstream pipeline (DependencySectionPolicy regex, DevelopmentDependencySyncPolicy
        # line insertion, etc.) is built around a single canonical variable name.
        # Uses AST-directed byte-offset replacement — no regular expressions.
        template_var = merger.template_analysis.respond_to?(:gemspec_block_var) ? merger.template_analysis.gemspec_block_var : nil
        dest_var = merger.dest_analysis.respond_to?(:gemspec_block_var) ? merger.dest_analysis.gemspec_block_var : nil
        preferred_var = Ruby::Merge::GemspecSupport.preferred_block_var(template_var, dest_var)
        dest_body = GemspecVarRenamer.rename(dest_body, old_var: dest_var, new_var: preferred_var) if preferred_var

        body_merger = merger.class.new(
          template_body,
          dest_body,
          signature_generator: merger.instance_variable_get(:@raw_signature_generator),
          preference: merger.preference,
          resolution_mode: merger.resolution_mode,
          unresolved_policy: merger.unresolved_policy,
          add_template_only_nodes: merger.add_template_only_nodes,
          remove_template_missing_nodes: merger.remove_template_missing_nodes,
          corruption_handling: merger.corruption_handling,
          freeze_token: merger.freeze_token,
          max_recursion_depth: merger.max_recursion_depth,
          current_depth: merger.instance_variable_get(:@current_depth) + 1,
          node_typing: merger.node_typing,
          # Thread gemspec block-variable names so inner FileAnalysis objects can normalise
          # assignment signatures even when the Gem::Specification.new wrapper is absent
          # from the extracted body text (auto-detection cannot fire without the wrapper).
          # When renaming was applied above, both sides now use preferred_var.
          template_gemspec_block_var: Ruby::Merge::GemspecSupport.merged_block_var(template_var, preferred_var),
          dest_gemspec_block_var: Ruby::Merge::GemspecSupport.merged_block_var(dest_var, preferred_var)
        )
        body_result = if template_body.empty? && dest_body.empty?
                        nil
                      else
                        body_merger.merge_result
                      end

        node_preference = merger.send(:preference_for_node, template_node, dest_node)
        last_emitted_dest_line = nil

        template_comments = actual_template.location.respond_to?(:leading_comments) ? actual_template.location.leading_comments : []
        dest_comments = actual_dest.location.respond_to?(:leading_comments) ? actual_dest.location.leading_comments : []
        dest_prefix_comment_lines = merger.instance_variable_get(:@dest_prefix_comment_lines)
        template_prefix_line_numbers = Prism::Merge::MagicCommentSupport.prefix_comment_line_numbers_for_comments(template_comments)
        dest_claimed = merger.dest_analysis.respond_to?(:claimed_lines) ? merger.dest_analysis.claimed_lines : Set.new
        template_claimed = merger.template_analysis.respond_to?(:claimed_lines) ? merger.template_analysis.claimed_lines : Set.new
        dest_comments = dest_comments.reject do |comment|
          ln = comment.location.start_line
          dest_prefix_comment_lines&.include?(ln) || dest_claimed.include?(ln)
        end
        last_skipped_template_line = nil
        if dest_prefix_comment_lines&.any? || template_claimed.any?
          template_comments = template_comments.reject do |comment|
            ln = comment.location.start_line
            if template_prefix_line_numbers.include?(ln) || template_claimed.include?(ln)
              last_skipped_template_line = ln
              true
            end
          end
        end

        if node_preference == :template && template_comments.empty? && dest_comments.any?
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = merger.dest_analysis
        elsif node_preference == :template
          comment_source = :template
          leading_comments = template_comments
          comment_analysis = merger.template_analysis
        else
          comment_source = :destination
          leading_comments = dest_comments
          comment_analysis = merger.dest_analysis
        end

        source_analysis = node_preference == :template ? merger.template_analysis : merger.dest_analysis
        source_node = node_preference == :template ? actual_template : actual_dest
        source_layout = merger.send(:node_body_layout_for, source_node, source_analysis)
        decision = MergeResult::DECISION_REPLACED
        template_inline_by_line = merger.send(:wrapper_inline_comment_entries_by_line, merger.template_analysis,
                                              actual_template)
        dest_inline_by_line = merger.send(:wrapper_inline_comment_entries_by_line, merger.dest_analysis, actual_dest)
        merged_body_lines = body_result ? body_result.lines.dup : []
        merged_body_metadata = body_result&.line_metadata&.dup || []
        remapped_result_lines = {}

        # Recursive body merges emit comments through SmartMerger directly, so
        # apply the same ownership filters used by NodeEmissionSupport. Without
        # this, a floating comment can be emitted once as a matched node's
        # external template trailing comment and again as a nested leading
        # comment when both inputs already contain it.
        emission_support = merger.send(:node_emission_support)
        last_filtered_comment_line = nil
        if comment_source == :template
          leading_comments, trailing_filtered_line = emission_support.send(
            :filter_emitted_template_trailing_comments,
            leading_comments
          )
          leading_comments, leading_filtered_line = emission_support.send(
            :filter_already_emitted_leading_comments,
            leading_comments
          )
          last_filtered_comment_line = leading_filtered_line || trailing_filtered_line
          emission_support.send(:track_emitted_template_leading_comments, leading_comments)
        else
          leading_comments, trailing_filtered_line = emission_support.send(
            :filter_emitted_template_trailing_comments,
            leading_comments
          )
          leading_comments, template_leading_filtered_line = emission_support.send(
            :filter_emitted_template_leading_comments,
            leading_comments,
            last_filtered_line: trailing_filtered_line
          )
          last_filtered_comment_line = template_leading_filtered_line || trailing_filtered_line
          emission_support.send(:track_emitted_dest_leading_comments, leading_comments)
        end

        prev_comment_line = if comment_source == :template
                              [last_skipped_template_line, last_filtered_comment_line].compact.max
                            else
                              last_filtered_comment_line
                            end
        merger.send(
          :emit_leading_comments,
          merger.result,
          leading_comments,
          analysis: comment_analysis,
          source: comment_source,
          decision: decision,
          prev_comment_line: prev_comment_line
        )

        if comment_source == :destination && leading_comments.any?
          last_emitted_dest_line = leading_comments.last.location.start_line
        end

        if leading_comments.any?
          emitted_gap_line = merger.send(
            :emit_blank_lines_between,
            merger.result,
            last_comment_line: leading_comments.last.location.start_line,
            next_content_line: source_node.location.start_line,
            analysis: comment_analysis,
            source: comment_source,
            decision: decision
          )
          last_emitted_dest_line = emitted_gap_line if comment_source == :destination && emitted_gap_line
        end

        opening_line = source_layout.opening_line_text
        # When the opening line comes from dest but the template var is canonical,
        # rename the block parameter in the opening line (e.g. |gem| → |spec|).
        opening_line = Ruby::Merge::GemspecSupport.opening_line_with_preferred_block_var(
          opening_line,
          dest_var: dest_var,
          preferred_var: preferred_var,
          node_preference: node_preference
        )
        if node_preference == :template &&
           template_inline_by_line[actual_template.location.start_line].empty? &&
           !source_layout.body_starts_on_opening_line?
          dest_opening_inline = dest_inline_by_line[actual_dest.location.start_line]
          if dest_opening_inline.any?
            opening_line = merger.send(:append_inline_comment_entries, opening_line.to_s.chomp,
                                       dest_opening_inline)
          end
        end
        if source_layout.body_starts_on_opening_line? && merged_body_lines.any?
          opening_line = "#{opening_line}#{merged_body_lines.shift}"
          merged_body_metadata.shift
        end
        merger.result.add_line(
          opening_line.chomp,
          decision: decision,
          template_line: node_preference == :template ? source_node.location.start_line : nil,
          dest_line: node_preference == :destination ? source_node.location.start_line : nil
        )

        closing_body_line = nil
        if source_layout.body_ends_on_closing_line? && merged_body_lines.any?
          closing_body_line = merged_body_lines.pop
          merged_body_metadata.pop
        end

        merged_body_lines.each_with_index do |line, index|
          metadata = merged_body_metadata[index] || {}
          merger.result.add_line(
            line.chomp,
            decision: metadata[:decision] || decision,
            template_line: remap_body_line(metadata[:template_line], template_layout),
            dest_line: remap_body_line(metadata[:dest_line], dest_layout),
            comment: metadata[:comment]
          )
          remapped_result_lines[metadata[:result_line]] = merger.result.line_count if metadata[:result_line]
        end

        remap_inner_unresolved_review_state!(
          body_result: body_result,
          remapped_result_lines: remapped_result_lines,
          template_layout: template_layout,
          dest_layout: dest_layout,
          parent_node: actual_dest || actual_template
        )

        merger.send(:begin_node_plan_emitter).emit(
          template_node: actual_template,
          dest_node: actual_dest,
          node_preference: node_preference,
          decision: decision,
          template_inline_by_line: template_inline_by_line,
          dest_inline_by_line: dest_inline_by_line
        )

        end_line = source_layout.closing_line_text
        if node_preference == :template && template_inline_by_line[actual_template.location.end_line].empty?
          dest_end_inline = dest_inline_by_line[actual_dest.location.end_line]
          if dest_end_inline.any?
            end_line = merger.send(:append_inline_comment_entries, end_line.to_s.chomp,
                                   dest_end_inline)
          end
        end
        end_line = "#{closing_body_line}#{end_line}" if closing_body_line
        merger.result.add_line(
          end_line.chomp,
          decision: decision,
          template_line: node_preference == :template ? source_node.location.end_line : nil,
          dest_line: node_preference == :destination ? source_node.location.end_line : nil
        )

        template_trailing_comments = merger.send(:external_trailing_comments_for, actual_template,
                                                 analysis: merger.template_analysis)
        dest_trailing_comments = merger.send(:external_trailing_comments_for, actual_dest,
                                             analysis: merger.dest_analysis)

        if node_preference == :template
          trailing_comments = template_trailing_comments.any? ? template_trailing_comments : dest_trailing_comments
          trailing_analysis = template_trailing_comments.any? ? merger.template_analysis : merger.dest_analysis
        else
          trailing_comments = dest_trailing_comments
          trailing_analysis = merger.dest_analysis
        end

        if trailing_comments.any?
          emitted_dest_line = merger.send(
            :emit_external_trailing_comments,
            merger.result,
            trailing_comments,
            source_node: trailing_analysis.equal?(merger.template_analysis) ? actual_template : actual_dest,
            analysis: trailing_analysis,
            source: trailing_analysis.equal?(merger.template_analysis) ? :template : :destination,
            decision: decision
          )
          last_emitted_dest_line = emitted_dest_line if trailing_analysis.equal?(merger.dest_analysis)
          return { last_emitted_dest_line: last_emitted_dest_line }
        end

        trailing_line = source_node.location.end_line + 1
        trailing_content = source_analysis.line_at(trailing_line)
        emitted_trailing_gap_line = emit_trailing_layout_gap_lines(
          analysis: source_analysis,
          owner: source_node,
          source: node_preference == :template ? :template : :destination,
          decision: decision
        )

        if emitted_trailing_gap_line
          last_emitted_dest_line = emitted_trailing_gap_line if node_preference == :destination
        elsif trailing_content && trailing_content.strip.empty?
          if node_preference == :template
            merger.result.add_line('', decision: decision, template_line: trailing_line)
          else
            merger.result.add_line('', decision: decision, dest_line: trailing_line)
            last_emitted_dest_line = trailing_line
          end
        end

        { last_emitted_dest_line: last_emitted_dest_line }
      end

      private

      def remap_inner_unresolved_review_state!(body_result:, remapped_result_lines:, template_layout:, dest_layout:,
                                               parent_node:)
        return unless body_result&.review_required?

        remapped_cases = body_result.unresolved_cases.map do |resolution_case|
          remap_inner_unresolved_case(
            resolution_case: resolution_case,
            remapped_result_lines: remapped_result_lines,
            template_layout: template_layout,
            dest_layout: dest_layout,
            parent_node: parent_node
          )
        end
        remapped_conflicts_by_case_id = body_result.conflicts.each_with_object({}) do |conflict, hash|
          hash[conflict[:case_id].to_s] = conflict
        end

        remapped_cases.each do |resolution_case|
          merger.result.add_unresolved_case(resolution_case)
          conflict = remapped_conflicts_by_case_id[resolution_case.metadata[:source_case_id].to_s]
          if conflict
            merger.result.conflicts << remap_inner_unresolved_conflict(conflict: conflict,
                                                                       resolution_case: resolution_case)
          end
        end
      end

      def remap_inner_unresolved_case(resolution_case:, remapped_result_lines:, template_layout:, dest_layout:,
                                      parent_node:)
        metadata = resolution_case.metadata.dup
        metadata[:source_case_id] = resolution_case.case_id
        metadata[:result_lines] = remap_result_line_span(metadata[:result_lines], remapped_result_lines)
        metadata[:line] = single_line_result(metadata[:result_lines])
        metadata[:template_lines] = remap_source_line_span(metadata[:template_lines], template_layout)
        metadata[:destination_lines] = remap_source_line_span(metadata[:destination_lines], dest_layout)

        Ast::Merge::Runtime::ResolutionCase.new(
          case_id: remapped_case_id(resolution_case.case_id, parent_node),
          reason: resolution_case.reason,
          candidates: resolution_case.candidates,
          provisional_winner: resolution_case.provisional_winner,
          surface_path: remapped_surface_path(resolution_case, parent_node, metadata),
          operation_id: resolution_case.operation_id,
          metadata: metadata
        )
      end

      def remap_inner_unresolved_conflict(conflict:, resolution_case:)
        remapped = conflict.merge(case_id: resolution_case.case_id)
        remapped[:line] = resolution_case.metadata[:line] if resolution_case.metadata[:line]
        remapped
      end

      def remap_result_line_span(result_lines, remapped_result_lines)
        span = Array(result_lines)
        return unless span.length == 2

        start_line = remapped_result_lines[span[0]]
        end_line = remapped_result_lines[span[1]]
        return unless start_line && end_line

        [start_line, end_line]
      end

      def remap_source_line_span(source_lines, layout)
        span = Array(source_lines)
        return unless span.length == 2

        start_line = remap_body_line(span[0], layout)
        end_line = remap_body_line(span[1], layout)
        return unless start_line && end_line

        [start_line, end_line]
      end

      def single_line_result(result_lines)
        return unless result_lines && result_lines[0] == result_lines[1]

        result_lines[0]
      end

      def remapped_case_id(case_id, parent_node)
        "#{case_id}-within-#{parent_segment_token(parent_node)}"
      end

      def remapped_surface_path(resolution_case, parent_node, metadata)
        parent_segment = recursive_parent_surface_segment(parent_node)
        child_segment = recursive_child_surface_segment(resolution_case, metadata)
        return merger.send(:unresolved_surface_path, parent_segment) unless child_segment

        merger.send(:unresolved_surface_path, parent_segment, child_segment)
      end

      def recursive_parent_surface_segment(node)
        node_type = node.class.name.split('::').last
        merger.send(:unresolved_typed_path_segment, node_type, node: node, fallback: node_type)
      end

      def recursive_child_surface_segment(resolution_case, metadata)
        child_line = metadata.dig(:destination_lines, 0) || metadata.dig(:template_lines, 0)
        return unless child_line

        match_kind = metadata[:match_kind] || resolution_case.reason
        "#{match_kind}[line=#{child_line}]"
      end

      def parent_segment_token(node)
        "#{node.class.name.split('::').last.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase}-#{node.location.start_line}"
      end

      def emit_trailing_layout_gap_lines(analysis:, owner:, source:, decision:)
        return unless analysis.respond_to?(:layout_attachment_for)

        attachment = analysis.layout_attachment_for(owner)
        gap = attachment&.trailing_gap
        return unless gap
        return unless gap.controls_output_for?(owner)

        last_emitted_line = nil

        (gap.start_line..gap.end_line).each do |line_num|
          line = analysis.line_at(line_num).to_s.chomp
          next unless line.strip.empty?

          if source == :template
            merger.result.add_line(line, decision: decision, template_line: line_num)
          else
            merger.result.add_line(line, decision: decision, dest_line: line_num)
          end

          last_emitted_line = line_num
        end

        last_emitted_line
      end

      def remap_body_line(body_line, layout)
        layout.source_line_for_body_line(body_line)
      end
    end
  end
end
