# frozen_string_literal: true

module Ast
  module Merge
    # Shared signature-based alignment pipeline for format-specific file aligners.
    #
    # Concrete aligners typically customize only:
    # - entry payload keys (`template_node` / `dest_node`, `template_decl` / `dest_decl`, ...)
    # - extra signature aliases for special wrapper nodes
    # - template-only positioning metadata
    # - optional fuzzy match refinement
    # - sort-key overrides via `TrailingGroups::AlignmentSort`
    class FileAlignerBase
      include TrailingGroups::AlignmentSort

      attr_reader :template_analysis, :dest_analysis, :match_refiner

      def initialize(template_analysis, dest_analysis, match_refiner: nil, **_options)
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @match_refiner = match_refiner
      end

      # Align template and destination statements into match/template-only/dest-only entries.
      #
      # @return [Array<Hash>] ordered alignment entries consumed by conflict resolvers
      def align
        template_statements = statements_for(template_analysis)
        dest_statements = statements_for(dest_analysis)

        template_by_sig = build_signature_map(template_statements, template_analysis)
        dest_by_sig = build_signature_map(dest_statements, dest_analysis)

        matched_template = Set.new
        matched_dest = Set.new
        alignment = []

        template_by_sig.each do |sig, template_indices|
          next unless dest_by_sig.key?(sig)

          dest_indices = dest_by_sig[sig]

          template_indices.zip(dest_indices).each do |t_idx, d_idx|
            next unless t_idx && d_idx
            next if matched_template.include?(t_idx) || matched_dest.include?(d_idx)

            alignment << build_match_entry(
              signature: sig,
              template_index: t_idx,
              dest_index: d_idx,
              template_statement: template_statements[t_idx],
              dest_statement: dest_statements[d_idx]
            )

            matched_template << t_idx
            matched_dest << d_idx
          end
        end

        apply_match_refiner!(
          alignment,
          template_statements: template_statements,
          dest_statements: dest_statements,
          matched_template: matched_template,
          matched_dest: matched_dest
        )

        matched_entries_by_template_position = alignment
                                               .select { |entry| entry[:type] == :match }
                                               .sort_by do |entry|
          [
            entry[:template_index], entry[:dest_index]
          ]
        end

        template_statements.each_with_index do |statement, idx|
          next if matched_template.include?(idx)

          alignment << build_template_only_entry(
            template_index: idx,
            template_statement: statement,
            matched_entries_by_template_position: matched_entries_by_template_position
          )
        end

        dest_statements.each_with_index do |statement, idx|
          next if matched_dest.include?(idx)

          alignment << build_dest_only_entry(
            dest_index: idx,
            dest_statement: statement
          )
        end

        sort_alignment(alignment)
        log_alignment(alignment)
        alignment
      end

      private

      def statements_for(analysis)
        analysis.statements
      end

      def template_entry_key
        :template_node
      end

      def dest_entry_key
        :dest_node
      end

      def signature_for(analysis, index)
        analysis.signature_at(index)
      end

      def add_signature_aliases(_map, _statement, _index, _analysis); end

      def sort_alignment(alignment)
        sort_alignment_with_template_position(alignment, alignment.count { |entry| entry[:type] != :template_only })
      end

      def log_alignment(_alignment); end

      def build_signature_map(statements, analysis)
        map = Hash.new { |h, k| h[k] = [] }

        statements.each_with_index do |statement, idx|
          signature = signature_for(analysis, idx)
          map[signature] << idx if signature
          content_signature = content_identity_signature(statement)
          map[content_signature] << idx if content_signature && content_signature != signature
          add_signature_aliases(map, statement, idx, analysis)
        end

        map
      end

      def content_identity_signature(statement)
        content = statement_value(statement, :normalized_content) || statement_value(statement, 'normalized_content')
        content = content.to_s
        return if content.empty?

        [:content_identity, content]
      end

      def statement_value(statement, key)
        if statement.respond_to?(key)
          statement.public_send(key)
        elsif statement.respond_to?(:[])
          statement[key]
        end
      end

      def build_match_entry(signature:, template_index:, dest_index:, template_statement:, dest_statement:)
        {
          :type => :match,
          :template_index => template_index,
          :dest_index => dest_index,
          :signature => signature,
          template_entry_key => template_statement,
          dest_entry_key => dest_statement
        }
      end

      def build_template_only_entry(template_index:, template_statement:, matched_entries_by_template_position:)
        {
          :type => :template_only,
          :template_index => template_index,
          :dest_index => nil,
          :signature => signature_for(template_analysis, template_index),
          template_entry_key => template_statement,
          dest_entry_key => nil
        }.merge(
          template_only_entry_context(
            template_index: template_index,
            template_statement: template_statement,
            matched_entries_by_template_position: matched_entries_by_template_position
          )
        )
      end

      def build_dest_only_entry(dest_index:, dest_statement:)
        {
          :type => :dest_only,
          :template_index => nil,
          :dest_index => dest_index,
          :signature => signature_for(dest_analysis, dest_index),
          template_entry_key => nil,
          dest_entry_key => dest_statement
        }
      end

      def template_only_entry_context(**_options)
        {}
      end

      def surrounding_matched_entries(matched_entries, template_index)
        previous_match = nil
        next_match = nil

        matched_entries.each do |entry|
          if entry[:template_index] < template_index
            previous_match = entry
            next
          end

          if entry[:template_index] > template_index
            next_match = entry
            break
          end
        end

        [previous_match, next_match]
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

          alignment << build_match_entry(
            signature: refined_match_signature(match),
            template_index: template_index,
            dest_index: dest_index,
            template_statement: template_statement,
            dest_statement: dest_statement
          )

          matched_template << template_index
          matched_dest << dest_index
        end
      end

      def refined_match_template_statement(match)
        match.template_node
      end

      def refined_match_dest_statement(match)
        match.dest_node
      end

      def refined_match_signature(match)
        [:refined_match, match.score]
      end
    end
  end
end
