# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Conflict resolver for text-based AST merging.
      #
      # Uses content-based matching with destination-order preservation:
      # 1. Lines are matched by normalized content (whitespace-trimmed)
      # 2. Destination order is preserved (destination is source of truth for structure)
      # 3. Template-only lines are optionally inserted in template order relative
      #    to their matched anchors
      # 4. Freeze blocks are always preserved from destination
      #
      # @example
      #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
      #   result = MergeResult.new
      #   resolver.resolve(result)
      class ConflictResolver < ConflictResolverBase
        include Ast::Merge::TrailingGroups::DestIterate

        # Initialize the conflict resolver
        #
        # @param template_analysis [FileAnalysis] Analysis of template
        # @param dest_analysis [FileAnalysis] Analysis of destination
        # @param preference [Symbol] :destination or :template
        # @param add_template_only_nodes [Boolean] Whether to add template-only lines
        def initialize(
          template_analysis,
          dest_analysis,
          preference: :destination,
          add_template_only_nodes: false,
          resolution_mode: :eager,
          unresolved_policy: nil
        )
          super(
            strategy: :batch,
            preference: preference,
            template_analysis: template_analysis,
            dest_analysis: dest_analysis,
            add_template_only_nodes: add_template_only_nodes
          )
          @resolution_mode = resolution_mode
          @unresolved_policy = Ast::Merge::UnresolvedPolicy.coerce(unresolved_policy)
        end

        protected

        # Resolve using content-based matching with destination order preservation
        #
        # @param result [MergeResult] Result object to populate
        # @return [void]
        def resolve_batch(result)
          template_statements = @template_analysis.statements
          dest_statements = @dest_analysis.statements

          # Build index for matching (uses signatures when custom generator present)
          template_index = build_match_index(template_statements)
          dest_sigs = destination_signature_set(dest_statements)
          trailing_groups, matched_indices = build_dest_iterate_trailing_groups(
            template_nodes: template_statements,
            dest_sigs: dest_sigs,
            signature_for: ->(node) { freeze_node?(node) ? nil : signature_key_for(node) },
            add_template_only_nodes: @add_template_only_nodes
          )

          # Track matched template indices
          matched_template_indices = Set.new
          consumed_indices = Set.new

          emit_prefix_trailing_group(trailing_groups, consumed_indices) do |info|
            add_template_only_line(result, info[:node])
          end

          # Process destination in order - destination structure is preserved
          dest_statements.each do |dest_node|
            if freeze_node?(dest_node)
              # Freeze blocks are always preserved from destination
              add_freeze_block(result, dest_node)
              next
            end

            # Find matching template line by signature or normalized content
            match_key = signature_key_for(dest_node)
            template_match = find_unmatched(template_index[match_key], matched_template_indices)

            if template_match
              matched_template_indices << template_match[:index]
              resolve_matched_pair(result, template_match[:node], dest_node)
              consumed_indices << template_match[:index]
              flush_ready_trailing_groups(
                trailing_groups: trailing_groups,
                matched_indices: matched_indices,
                consumed_indices: consumed_indices
              ) do |info|
                add_template_only_line(result, info[:node])
              end
            else
              # Destination-only content - always preserve
              result.add_line(dest_node.content)
              result.record_decision(DECISION_APPENDED, nil, dest_node)
            end
          end

          emit_remaining_trailing_groups(
            trailing_groups: trailing_groups,
            consumed_indices: consumed_indices
          ) do |info|
            add_template_only_line(result, info[:node])
          end
        end

        private

        # Whether a custom signature generator is in use
        # @return [Boolean]
        def custom_signatures?
          @template_analysis.respond_to?(:signature_generator) &&
            !@template_analysis.signature_generator.nil?
        end

        # Compute the match key for a node.
        # Uses generate_signature when a custom generator is present;
        # falls back to normalized_content for default text matching.
        # @param node [LineNode] the node
        # @return [Object] match key (String or Array)
        def signature_key_for(node)
          if custom_signatures?
            @template_analysis.generate_signature(node)
          else
            node.normalized_content
          end
        end

        # Build an index of statements by match key (signature or normalized content)
        #
        # @param statements [Array] Statements to index
        # @return [Hash] Map of match_key => [{node:, index:}, ...]
        def build_match_index(statements)
          index = Hash.new { |h, k| h[k] = [] }
          statements.each_with_index do |node, idx|
            next if freeze_node?(node)

            key = signature_key_for(node)
            index[key] << { node: node, index: idx }
          end
          index
        end

        def destination_signature_set(statements)
          statements.each_with_object(::Set.new) do |node, signatures|
            next if freeze_node?(node)

            signatures << signature_key_for(node)
          end
        end

        # Find first unmatched entry from a list
        #
        # @param entries [Array, nil] List of {node:, index:} hashes
        # @param matched_indices [Set] Already matched indices
        # @return [Hash, nil] First unmatched entry or nil
        def find_unmatched(entries, matched_indices)
          return unless entries

          entries.find { |e| !matched_indices.include?(e[:index]) }
        end

        # Add a freeze block to the result
        #
        # @param result [MergeResult] Result to populate
        # @param freeze_node [FreezeNodeBase] Freeze block node
        def add_freeze_block(result, freeze_node)
          freeze_node.content.split("\n").each do |line|
            result.add_line(line)
          end
          result.record_decision(DECISION_FROZEN, nil, freeze_node)
        end

        def add_template_only_line(result, template_node)
          return if freeze_node?(template_node)

          result.add_line(template_node.content)
          result.record_decision(DECISION_ADDED, template_node, nil)
        end

        def trailing_group_node_matched?(node, _signature)
          freeze_node?(node)
        end

        # Resolve a matched pair of nodes
        #
        # @param result [MergeResult] Result to populate
        # @param template_node [LineNode] Template node
        # @param dest_node [LineNode] Destination node
        def resolve_matched_pair(result, template_node, dest_node)
          if template_node.content == dest_node.content
            # Identical content
            result.add_line(dest_node.content)
            result.record_decision(DECISION_IDENTICAL, template_node, dest_node)
          elsif unresolved_mode? && @unresolved_policy.unresolved_for?(:matched_line)
            provisional_winner = @unresolved_policy.provisional_winner_for(
              :matched_line,
              fallback: (@preference == :template ? :template : :destination)
            )
            chosen_content = provisional_winner == :template ? template_node.content : dest_node.content
            result.add_line(chosen_content)
            result.record_decision(Ast::Merge::MergeResultBase::DECISION_UNRESOLVED, template_node, dest_node)
            record_unresolved_node_choice(
              result: result,
              template_node: template_node,
              destination_node: dest_node,
              template_text: template_node.content,
              destination_text: dest_node.content,
              provisional_winner: provisional_winner,
              case_prefix: 'text',
              case_parts: [:matched_line],
              case_id: "text-line-#{result.line_count}",
              surface_path: nil,
              metadata: {
                match_kind: :matched_line,
                line: result.line_count,
                match_key: signature_key_for(dest_node),
                review_identity: review_identity_for_unresolved_choice(
                  template_text: template_node.content,
                  destination_text: dest_node.content,
                  provisional_winner: provisional_winner,
                  match_kind: :matched_line,
                  line: result.line_count,
                  match_key: signature_key_for(dest_node)
                )
              },
              conflict_fields: {
                line: result.line_count
              }
            )
          elsif @preference == :template
            # Template wins - use template content
            result.add_line(template_node.content)
            result.record_decision(DECISION_KEPT_TEMPLATE, template_node, dest_node)
          else
            # Destination wins (default) - use destination content
            result.add_line(dest_node.content)
            result.record_decision(DECISION_KEPT_DEST, template_node, dest_node)
          end
        end
      end
    end
  end
end
