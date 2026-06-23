# frozen_string_literal: true

module Prism
  module Merge
    class CommentOnlyFileMerger
      attr_reader :merger, :comment_only_prefix_lines

      def initialize(merger:)
        @merger = merger
        @comment_only_prefix_lines = {
          template: Set.new,
          destination: Set.new
        }
      end

      def comment_only_file?(analysis)
        statements = analysis.statements
        return false if statements.nil? || statements.empty?

        statements.all? do |statement|
          statement.is_a?(Ast::Merge::Comment::Empty) ||
            statement.is_a?(Ast::Merge::Comment::Block) ||
            statement.is_a?(Ast::Merge::Comment::Line)
        end
      end

      def merge
        @comment_only_prefix_lines = {
          template: Set.new,
          destination: Set.new
        }

        template_lines = merger.template_content.lines.map(&:chomp)
        dest_lines = merger.dest_content.lines.map(&:chomp)

        emit_comment_only_prefix_lines(template_lines, dest_lines)

        template_nodes = Comment::Parser.parse(template_lines)
        dest_nodes = Comment::Parser.parse(dest_lines)
        template_context = build_comment_only_merge_context(nodes: template_nodes, lines: template_lines,
                                                            source: :template)
        dest_context = build_comment_only_merge_context(nodes: dest_nodes, lines: dest_lines, source: :destination)
        output_plan = build_output_plan(template_context: template_context, dest_context: dest_context)
        retained_owners_by_source = output_plan.group_by { |entry| entry[:source] }
                                               .transform_values do |entries|
          entries.map do |entry|
            entry[:node]
          end
        end
        emitted_gap_keys = {
          template: Set.new,
          destination: Set.new
        }

        output_plan.each do |entry|
          context = entry[:source] == :template ? template_context : dest_context
          emit_comment_node_with_layout(
            node: entry[:node],
            source: entry[:source],
            context: context,
            retained_owners: retained_owners_by_source.fetch(entry[:source], []),
            emitted_gap_keys: emitted_gap_keys
          )
        end

        merger.result
      end

      private

      def build_comment_indices_map(nodes)
        nodes.each_with_index.with_object(Hash.new { |hash, key| hash[key] = [] }) do |(node, index), map|
          signature = node.respond_to?(:signature) ? node.signature : nil
          map[signature] << index if signature
        end
      end

      def build_comment_only_merge_context(nodes:, lines:, source:)
        mergeable_nodes = Array(nodes).reject do |node|
          ignored_comment_only_node?(node, source)
        end

        {
          source: source,
          lines: lines,
          nodes: mergeable_nodes,
          layout_augmenter: Ast::Merge::Layout::Augmenter.new(
            lines: lines,
            owners: mergeable_nodes,
            start_line_for: method(:node_start_line),
            end_line_for: method(:node_end_line),
            metadata: {
              source: :comment_only_file_merger,
              comment_source: source
            }
          )
        }
      end

      def build_output_plan(template_context:, dest_context:)
        dest_indices_by_signature = build_comment_indices_map(dest_context[:nodes])
        output_template_signatures = Set.new
        matched_dest_indices = Set.new
        plan = []

        template_context[:nodes].each do |template_node|
          template_signature = template_node.respond_to?(:signature) ? template_node.signature : nil
          next if template_signature && output_template_signatures.include?(template_signature)

          dest_index = find_first_unmatched_index(dest_indices_by_signature, template_signature, matched_dest_indices)

          if dest_index
            dest_node = dest_context[:nodes][dest_index]
            matched_dest_indices << dest_index
            output_template_signatures << template_signature if template_signature

            plan << if merger.send(:default_preference) == :template
                      { node: template_node, source: :template }
                    else
                      { node: dest_node, source: :destination }
                    end
          elsif merger.add_template_only_nodes ||
                (merger.send(:default_preference) == :template && template_node.respond_to?(:magic_comment?) && template_node.magic_comment?)
            plan << { node: template_node, source: :template }
            output_template_signatures << template_signature if template_signature
          end
        end

        if merger.send(:default_preference) == :destination && !merger.remove_template_missing_nodes
          dest_context[:nodes].each_with_index do |dest_node, index|
            next if matched_dest_indices.include?(index)

            plan << { node: dest_node, source: :destination }
          end
        end

        plan
      end

      def find_first_unmatched_index(indices_map, signature, matched_indices)
        return unless signature

        indices = indices_map[signature]
        return unless indices

        indices.find { |index| !matched_indices.include?(index) }
      end

      def add_comment_node_to_result(node, source)
        decision = source == :template ? MergeResult::DECISION_KEPT_TEMPLATE : MergeResult::DECISION_KEPT_DEST
        suppressed_lines = comment_only_prefix_lines.fetch(source, Set.new)

        content = if node.respond_to?(:text)
                    node.text
                  elsif node.respond_to?(:content)
                    node.content
                  else
                    node.to_s
                  end

        if node.respond_to?(:children) && node.children.any?
          node.children.each do |child|
            child_content = child.respond_to?(:text) ? child.text : child.to_s
            line_num = child.respond_to?(:line_number) ? child.line_number : nil
            next if line_num && suppressed_lines.include?(line_num)

            if source == :template
              merger.result.add_line(child_content, decision: decision, template_line: line_num)
            else
              merger.result.add_line(child_content, decision: decision, dest_line: line_num)
            end
          end
        else
          line_num = node.respond_to?(:line_number) ? node.line_number : nil
          return if line_num && suppressed_lines.include?(line_num)

          if source == :template
            merger.result.add_line(content, decision: decision, template_line: line_num)
          else
            merger.result.add_line(content, decision: decision, dest_line: line_num)
          end
        end
      end

      def emit_comment_node_with_layout(node:, source:, context:, retained_owners:, emitted_gap_keys:)
        layout_attachment = context[:layout_augmenter].attachment_for(node)

        emit_layout_gap_to_result(
          gap: layout_attachment&.leading_gap,
          owner: node,
          source: source,
          retained_owners: retained_owners,
          emitted_gap_keys: emitted_gap_keys
        )
        add_comment_node_to_result(node, source)
        emit_layout_gap_to_result(
          gap: layout_attachment&.trailing_gap,
          owner: node,
          source: source,
          retained_owners: retained_owners,
          emitted_gap_keys: emitted_gap_keys
        )
      end

      def emit_layout_gap_to_result(gap:, owner:, source:, retained_owners:, emitted_gap_keys:)
        return unless gap
        return if skip_interstitial_gap?(gap, retained_owners)
        return unless gap.controls_output_for?(owner, retained_owners: retained_owners)

        gap_key = [gap.start_line, gap.end_line]
        return if emitted_gap_keys.fetch(source).include?(gap_key)

        decision = source == :template ? MergeResult::DECISION_KEPT_TEMPLATE : MergeResult::DECISION_KEPT_DEST
        suppressed_lines = comment_only_prefix_lines.fetch(source, Set.new)

        gap.lines.each_with_index do |line, index|
          line_num = gap.start_line + index
          next if suppressed_lines.include?(line_num)

          if source == :template
            merger.result.add_line(line.to_s, decision: decision, template_line: line_num)
          else
            merger.result.add_line(line.to_s, decision: decision, dest_line: line_num)
          end
        end

        emitted_gap_keys.fetch(source) << gap_key
      end

      def emit_comment_only_prefix_lines(template_lines, dest_lines)
        dest_prefix = comment_only_prefix_lines_for(dest_lines)
        return if dest_prefix[:entries].empty?

        dest_prefix[:entries].each do |entry|
          merger.result.add_line(entry[:text], decision: MergeResult::DECISION_KEPT_DEST, dest_line: entry[:line_num])
        end
        dest_prefix[:suppressed_line_nums].each { |line_num| comment_only_prefix_lines[:destination] << line_num }

        template_prefix = comment_only_prefix_lines_for(template_lines)
        template_prefix[:suppressed_line_nums].each { |line_num| comment_only_prefix_lines[:template] << line_num }
      end

      def comment_only_prefix_lines_for(lines)
        prefix_info = Prism::Merge::MagicCommentSupport.comment_only_prefix_info(lines)
        duplicate_magic_line_nums = prefix_info[:duplicate_magic_line_nums]

        if duplicate_magic_line_nums.any?
          should_heal = merger.send(
            :handle_suspected_corruption,
            kind: :duplicate_magic_comment_prefix,
            message: 'comment-only file header repeats an already-declared magic comment type'
          )

          entries = if should_heal
                      prefix_info[:entries].reject { |entry| duplicate_magic_line_nums.include?(entry[:line_num]) }
                    else
                      prefix_info[:entries]
                    end

          return {
            entries: entries,
            suppressed_line_nums: prefix_info[:suppressed_line_nums]
          }
        end

        prefix_info.slice(:entries, :suppressed_line_nums)
      end

      def ruby_magic_comment_line_type(line)
        Prism::Merge::MagicCommentSupport.magic_comment_type_for_text(line)
      end

      def ignored_comment_only_node?(node, source)
        node.is_a?(Ast::Merge::Comment::Empty) || fully_suppressed_comment_only_node?(node, source)
      end

      def fully_suppressed_comment_only_node?(node, source)
        line_numbers = node_line_numbers(node)
        line_numbers.any? && line_numbers.all? do |line_num|
          comment_only_prefix_lines.fetch(source, Set.new).include?(line_num)
        end
      end

      def node_line_numbers(node)
        if node.respond_to?(:children) && node.children.any?
          node.children.flat_map { |child| node_line_numbers(child) }
        elsif node.respond_to?(:line_number)
          [node.line_number]
        elsif node.respond_to?(:location) && node.location
          (node.location.start_line..node.location.end_line).to_a
        else
          []
        end
      end

      def node_start_line(node)
        return node.location.start_line if node.respond_to?(:location) && node.location
        return node.line_number if node.respond_to?(:line_number)

        nil
      end

      def node_end_line(node)
        return node.location.end_line if node.respond_to?(:location) && node.location
        return node.line_number if node.respond_to?(:line_number)

        nil
      end

      def skip_interstitial_gap?(gap, retained_owners)
        return false unless gap.interstitial?

        retained_before = retained_owners.any? { |candidate| candidate.equal?(gap.before_owner) }
        retained_after = retained_owners.any? { |candidate| candidate.equal?(gap.after_owner) }
        !(retained_before && retained_after)
      end
    end
  end
end
