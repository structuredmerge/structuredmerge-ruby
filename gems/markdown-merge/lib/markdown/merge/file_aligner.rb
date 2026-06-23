# frozen_string_literal: true

module Markdown
  module Merge
    # Aligns Markdown block elements between template and destination files.
    #
    # Uses structural signatures to match headings, paragraphs, lists, code blocks,
    # and other block elements. The alignment is then used by SmartMerger to
    # determine how to combine the files.
    #
    # @example Basic usage
    #   aligner = FileAligner.new(template_analysis, dest_analysis)
    #   alignment = aligner.align
    #   alignment.each do |entry|
    #     case entry[:type]
    #     when :match
    #       # Both files have this element
    #     when :template_only
    #       # Only in template
    #     when :dest_only
    #       # Only in destination
    #     end
    #   end
    #
    # @see FileAnalysisBase
    # @see SmartMergerBase
    class FileAligner < ::Ast::Merge::FileAlignerBase
      # @return [FileAnalysisBase] Template file analysis
      attr_reader :template_analysis

      # @return [FileAnalysisBase] Destination file analysis
      attr_reader :dest_analysis

      # @return [#call, nil] Optional match refiner for fuzzy matching
      attr_reader :match_refiner

      # Initialize a file aligner
      #
      # @param template_analysis [FileAnalysisBase] Analysis of the template file
      # @param dest_analysis [FileAnalysisBase] Analysis of the destination file
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      def initialize(template_analysis, dest_analysis, match_refiner: nil, **options)
        super(template_analysis, dest_analysis, match_refiner: match_refiner, **options)
      end

      private

      def signature_for(analysis, index)
        signature = analysis.signature_at(index)
        return signature if signature.nil?

        signature = contextual_list_signature(analysis, index, signature) if list_signature?(signature)

        contextualize_signature_with_heading_owner_path(analysis, index, signature)
      end

      def apply_match_refiner!(alignment, template_statements:, dest_statements:, matched_template:, matched_dest:)
        return unless match_refiner

        unmatched_template = template_statements.each_with_index.reject do |_, i|
          matched_template.include?(i)
        end.map(&:first)
        unmatched_dest = dest_statements.each_with_index.reject { |_, i| matched_dest.include?(i) }.map(&:first)
        return if unmatched_template.empty? || unmatched_dest.empty?

        refined_matches = match_refiner.call(
          unmatched_template,
          unmatched_dest,
          {
            template_analysis: template_analysis,
            dest_analysis: dest_analysis
          }
        )

        Array(refined_matches).each do |match|
          template_statement = refined_match_template_statement(match)
          dest_statement = refined_match_dest_statement(match)
          template_index = template_statements.index(template_statement)
          dest_index = dest_statements.index(dest_statement)

          next unless template_index && dest_index
          next if matched_template.include?(template_index) || matched_dest.include?(dest_index)
          next unless refined_match_heading_owner_compatible?(template_index, dest_index)

          entry = build_match_entry(
            signature: refined_match_signature(match),
            template_index: template_index,
            dest_index: dest_index,
            template_statement: template_statement,
            dest_statement: dest_statement
          )
          repair_dest_index = adjacent_section_hijack_repair_sort_dest_index(template_index, dest_index)
          entry[:repair_dest_index] = repair_dest_index if repair_dest_index
          alignment << entry

          matched_template << template_index
          matched_dest << dest_index
        end
      end

      def contextualize_signature_with_heading_owner_path(analysis, index, signature)
        return signature unless section_owned_signature?(signature)
        return signature if synthetic_section_label_paragraph?(analysis, index)
        return signature if gap_line_after_synthetic_section_label?(analysis, index)

        owner_path = heading_owner_path_for(analysis, index)
        return signature if owner_path.empty?

        [signature.first, owner_path, *signature.drop(1)]
      end

      def section_owned_signature?(signature)
        signature.is_a?(Array) && %i[
          paragraph
          code_block
          blockquote
          block_quote
          table
          custom_block
          hrule
          thematic_break
          gap_line_after
        ].include?(signature.first)
      end

      def heading_owner_path_for(analysis, index)
        heading_owner_paths_for(analysis).fetch(index, EMPTY_HEADING_OWNER_PATH)
      end

      def heading_owner_paths_for(analysis)
        @heading_owner_paths ||= {}
        @heading_owner_paths.fetch(analysis.object_id) do
          @heading_owner_paths[analysis.object_id] = build_heading_owner_paths(analysis)
        end
      end

      EMPTY_HEADING_OWNER_PATH = [].freeze

      def build_heading_owner_paths(analysis)
        statements = statements_for(analysis)
        stack = []

        statements.each_with_index.each_with_object([]) do |(_statement, index), paths|
          signature = analysis.signature_at(index)
          if heading_signature?(signature)
            level = signature[1]
            stack.pop while stack.any? && stack.last[:level] >= level
            paths << stack.map { |entry| entry[:signature] }.freeze
            stack << { level: level, signature: signature }
          else
            paths << stack.map { |entry| entry[:signature] }.freeze
          end
        end.freeze
      end

      def refined_match_heading_owner_compatible?(template_index, dest_index)
        template_owner_path = heading_owner_path_for(template_analysis, template_index)
        dest_owner_path = heading_owner_path_for(dest_analysis, dest_index)
        return true if template_owner_path == dest_owner_path

        refined_list_repair_compatible?(template_index, dest_index) ||
          adjacent_section_hijack_repair_compatible?(template_index, dest_index)
      end

      def refined_list_repair_compatible?(template_index, dest_index)
        template_signature = template_analysis.signature_at(template_index)
        dest_signature = dest_analysis.signature_at(dest_index)
        return false unless list_signature?(template_signature) && list_signature?(dest_signature)
        return true if synthetic_label_scoped_list?(template_analysis, template_index)

        template_count = template_signature[2].to_i
        dest_count = dest_signature[2].to_i
        [template_count, dest_count].max >= [template_count, dest_count].min + 2
      end

      def adjacent_section_hijack_repair_compatible?(template_index, dest_index)
        template_signature = template_analysis.signature_at(template_index)
        dest_signature = dest_analysis.signature_at(dest_index)
        return false unless repairable_hijacked_section_signature?(template_signature, dest_signature)
        return false unless exact_statement_text_match?(template_analysis, template_index, dest_analysis, dest_index)

        template_owner = section_owner_for(template_analysis, template_index)
        dest_owner = section_owner_for(dest_analysis, dest_index)
        return false unless template_owner && dest_owner
        return false if template_owner[:signature] == dest_owner[:signature]
        return false unless section_empty_for_heading_signature?(dest_analysis, template_owner[:signature])

        neighboring_section_signatures?(template_analysis, template_owner[:signature], dest_owner[:signature]) &&
          neighboring_section_signatures?(dest_analysis, template_owner[:signature], dest_owner[:signature])
      end

      def template_only_entry_context(template_index:, matched_entries_by_template_position:, **)
        next_match = next_match_for_template_only_entry(
          template_index,
          matched_entries_by_template_position
        )

        {
          anchor_dest_index: anchor_dest_index_for_entry(next_match),
          anchor_position: next_match ? :before : :append
        }
      end

      def next_match_for_template_only_entry(template_index, matched_entries_by_template_position)
        same_owner_match = next_same_owner_match_for_template_only_entry(
          template_index,
          matched_entries_by_template_position
        )
        return same_owner_match if same_owner_match

        section_boundary_match = next_section_boundary_match_for_template_only_entry(
          template_index,
          matched_entries_by_template_position
        )
        return section_boundary_match if section_boundary_match

        _previous_match, next_match = surrounding_matched_entries(matched_entries_by_template_position, template_index)
        next_match
      end

      def next_same_owner_match_for_template_only_entry(template_index, matched_entries_by_template_position)
        owner = section_owner_for(template_analysis, template_index)
        return unless owner

        matched_entries_by_template_position.find do |entry|
          candidate_index = entry[:template_index]
          next false unless candidate_index && candidate_index > template_index

          candidate_signature = template_analysis.signature_at(candidate_index)
          next false if candidate_signature.is_a?(Array) && candidate_signature.first == :gap_line_after

          candidate_owner = section_owner_for(template_analysis, candidate_index)
          candidate_owner && candidate_owner[:signature] == owner[:signature]
        end
      end

      def next_section_boundary_match_for_template_only_entry(template_index, matched_entries_by_template_position)
        owner = section_owner_for(template_analysis, template_index)
        return unless owner

        matched_entries_by_template_position.find do |entry|
          candidate_index = entry[:template_index]
          next false unless candidate_index && candidate_index > owner[:heading_index]

          candidate_signature = template_analysis.signature_at(candidate_index)
          heading_signature?(candidate_signature) && candidate_signature[1] <= owner[:level]
        end
      end

      def section_owner_for(analysis, index)
        statements = statements_for(analysis)
        statement = statements[index]
        signature = analysis.signature_at(index)
        return unless statement && signature

        if heading_signature?(signature)
          { heading_index: index, level: signature[1], owner_path: heading_owner_path_for(analysis, index),
            signature: signature }
        else
          owner_path = heading_owner_path_for(analysis, index)
          return if owner_path.empty?

          owner_signature = owner_path.last
          owner_index = nearest_owner_heading_index_for(analysis, index, owner_signature)
          return unless owner_index

          { heading_index: owner_index, level: owner_signature[1], owner_path: owner_path, signature: owner_signature }
        end
      end

      def nearest_owner_heading_index_for(analysis, index, owner_signature)
        index.downto(0) do |current_index|
          signature = analysis.signature_at(current_index)
          next unless heading_signature?(signature)
          return current_index if signature == owner_signature
        end

        nil
      end

      def log_alignment(alignment)
        DebugLogger.debug('Alignment complete', {
                            total: alignment.size,
                            matches: alignment.count { |e| e[:type] == :match },
                            template_only: alignment.count { |e| e[:type] == :template_only },
                            dest_only: alignment.count { |e| e[:type] == :dest_only }
                          })
      end

      def match_sort_key(entry)
        [0, anchor_dest_index_for_entry(entry), 0, entry[:template_index] || 0]
      end

      def template_only_sort_key(entry, _dest_size)
        anchor_dest_index = entry[:anchor_dest_index]

        case entry[:anchor_position]
        when :before
          [0, anchor_dest_index, -1, entry[:template_index]]
        else
          [1, entry[:template_index], 0, 0]
        end
      end

      def list_signature?(signature)
        signature.is_a?(Array) && signature.first == :list
      end

      def contextual_list_signature(analysis, index, signature)
        statement = statements_for(analysis)[index]
        list_type = signature[1]
        preceding_context_index = nearest_list_context_index(analysis, index)
        preceding_context = preceding_context_index ? analysis.signature_at(preceding_context_index) : nil
        owner_path = if preceding_context_index && synthetic_section_label_paragraph?(analysis, preceding_context_index)
                       EMPTY_HEADING_OWNER_PATH
                     else
                       heading_owner_path_for(analysis, index)
                     end
        first_anchor = first_list_item_anchor(statement, analysis)
        [:list, owner_path, list_type, preceding_context, first_anchor]
      end

      def heading_signature?(signature)
        signature.is_a?(Array) && signature.first == :heading
      end

      def nearest_list_context_index(analysis, index)
        (index - 1).downto(0) do |current_index|
          candidate = analysis.signature_at(current_index)
          next unless contextual_predecessor_signature?(candidate)

          return current_index
        end

        nil
      end

      def contextual_predecessor_signature?(signature)
        signature.is_a?(Array) && %i[heading paragraph code_block].include?(signature.first)
      end

      def synthetic_section_label_paragraph?(analysis, index)
        signature = analysis.signature_at(index)
        return false unless signature.is_a?(Array) && signature.first == :paragraph

        statement = statements_for(analysis)[index]
        return false unless statement&.respond_to?(:text)

        text = statement.text.to_s.strip
        return false if text.empty? || text.length > 120
        return false if text.include?("\n")
        return false if text.match?(/[.!?:]\z/)

        text.split(/\s+/).length <= 12
      end

      def synthetic_label_scoped_list?(analysis, index)
        return false unless list_signature?(analysis.signature_at(index))

        context_index = nearest_list_context_index(analysis, index)
        context_index && synthetic_section_label_paragraph?(analysis, context_index)
      end

      def gap_line_after_synthetic_section_label?(analysis, index)
        signature = analysis.signature_at(index)
        return false unless signature.is_a?(Array) && signature.first == :gap_line_after
        return false unless index.positive?

        synthetic_section_label_paragraph?(analysis, index - 1)
      end

      def repairable_hijacked_section_signature?(template_signature, dest_signature)
        return false unless template_signature == dest_signature

        paragraph_signature?(template_signature) || list_signature?(template_signature)
      end

      def paragraph_signature?(signature)
        signature.is_a?(Array) && signature.first == :paragraph
      end

      def exact_statement_text_match?(template_analysis, template_index, dest_analysis, dest_index)
        template_statement = statements_for(template_analysis)[template_index]
        dest_statement = statements_for(dest_analysis)[dest_index]
        return false unless template_statement&.respond_to?(:text) && dest_statement&.respond_to?(:text)

        template_statement.text.to_s == dest_statement.text.to_s
      end

      def adjacent_section_hijack_repair_sort_dest_index(template_index, dest_index)
        return unless adjacent_section_hijack_repair_compatible?(template_index, dest_index)

        template_owner = section_owner_for(template_analysis, template_index)
        return unless template_owner

        heading_index = heading_index_for_signature(dest_analysis, template_owner[:signature])
        return unless heading_index

        boundary_index = next_section_boundary_heading_index(dest_analysis, heading_index)
        return heading_index + 0.5 unless boundary_index

        boundary_index - 0.5
      end

      def anchor_dest_index_for_entry(entry)
        entry&.fetch(:repair_dest_index, entry[:dest_index])
      end

      def section_empty_for_heading_signature?(analysis, heading_signature)
        heading_index = heading_index_for_signature(analysis, heading_signature)
        return false unless heading_index

        next_heading_index = next_section_boundary_heading_index(analysis, heading_index)
        last_index = next_heading_index ? next_heading_index - 1 : statements_for(analysis).length - 1
        ((heading_index + 1)..last_index).none? do |index|
          signature = analysis.signature_at(index)
          signature && signature.first != :gap_line_after && !heading_signature?(signature)
        end
      end

      def neighboring_section_signatures?(analysis, first_signature, second_signature)
        first_index = heading_index_for_signature(analysis, first_signature)
        second_index = heading_index_for_signature(analysis, second_signature)
        return false unless first_index && second_index

        neighboring_heading_signatures(analysis, first_index).include?(second_signature)
      end

      def neighboring_heading_signatures(analysis, heading_index)
        signature = analysis.signature_at(heading_index)
        return [] unless heading_signature?(signature)

        level = signature[1]
        parent_path = heading_owner_path_for(analysis, heading_index)
        headings = statements_for(analysis).each_index.filter_map do |index|
          candidate = analysis.signature_at(index)
          next unless heading_signature?(candidate)
          next unless candidate[1] == level
          next unless heading_owner_path_for(analysis, index) == parent_path

          candidate
        end
        current_position = headings.index(signature)
        return [] unless current_position

        [headings[current_position - 1], headings[current_position + 1]].compact
      end

      def heading_index_for_signature(analysis, heading_signature)
        statements_for(analysis).each_index.find do |index|
          analysis.signature_at(index) == heading_signature
        end
      end

      def next_section_boundary_heading_index(analysis, heading_index)
        signature = analysis.signature_at(heading_index)
        return unless heading_signature?(signature)

        level = signature[1]
        ((heading_index + 1)...statements_for(analysis).length).find do |index|
          candidate = analysis.signature_at(index)
          heading_signature?(candidate) && candidate[1] <= level
        end
      end

      def first_list_item_anchor(statement, analysis)
        raw = Ast::Merge::NodeTyping.unwrap(statement)
        first_item = nil

        raw.each do |child|
          next unless child.respond_to?(:type) && %w[list_item item].include?(child.type.to_s)

          first_item = child
          break
        end

        return '' unless first_item

        text = if analysis && first_item.respond_to?(:source_position) && first_item.source_position
                 pos = first_item.source_position
                 analysis.source_range(pos[:start_line], pos[:end_line]).to_s
               else
                 first_item.respond_to?(:text) ? first_item.text.to_s : ''
               end

        text
          .strip
          .sub(/\A(?:[-*+]|\d+\.)\s+/, '')
          .gsub(/[^\p{L}\p{N}]+/u, ' ')
          .gsub(/\s+/, ' ')
          .downcase
          .strip
      end
    end
  end
end
