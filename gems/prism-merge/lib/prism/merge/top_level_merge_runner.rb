# frozen_string_literal: true

module Prism
  module Merge
    # Orchestrates the top-level merge of two Ruby files parsed by Prism.
    #
    # Uses a **three-phase matching** strategy to pair template nodes with
    # destination nodes before emitting the merged result:
    #
    # 1. **Phase 1 — Exact signature match.**
    #    Pairs nodes whose structural signatures (method name + params,
    #    call name + args, etc.) are identical. This is the fastest phase
    #    and handles the vast majority of nodes.
    #
    # 2. **Phase 2 — Similarity match at the same depth.**
    #    For nodes left unmatched after Phase 1, computes body-text Jaccard
    #    similarity ({Ast::Merge::JaccardSimilarity}) to pair probable
    #    renames or minor refactors. Only operates on the residual
    #    unmatched sets, keeping cost proportional to orphan count.
    #
    # 3. **Phase 3 — Cross-depth match.**
    #    For nodes still unmatched after Phase 2, searches recursively into
    #    destination subtrees (conditionals, begin/rescue, call blocks) to
    #    detect "moved" nodes — e.g. a template top-level +eval_gemfile+
    #    that the destination wrapped inside an +if+ block. Only runs on
    #    the tiny residual set surviving both previous phases.
    #
    # The phase ordering is critical: exact matches are locked in first so
    # that fuzzy Phase 2 scoring cannot accidentally consume a node that
    # belongs to a later exact match at a different position.
    #
    # @example Basic usage (internal — called by SmartMerger)
    #   runner = TopLevelMergeRunner.new(merger: smart_merger)
    #   result = runner.merge   # => MergeResult
    #
    # @see Ast::Merge::JaccardSimilarity   Jaccard token-set similarity
    # @see Ast::Merge::TrailingGroups::DestIterate  Template-only node positioning
    class TopLevelMergeRunner
      include ::Ast::Merge::TrailingGroups::DestIterate
      include ::Ast::Merge::JaccardSimilarity

      # Minimum Jaccard score for Phase 2 body-text matching.
      # Below this threshold, two nodes are too dissimilar to pair.
      #
      # @return [Float]
      SIMILARITY_THRESHOLD = 0.6

      # Minimum token count for meaningful Jaccard comparison.
      # Nodes with fewer body tokens than this are skipped in Phase 2
      # to avoid spurious matches on trivially short bodies.
      #
      # @return [Integer]
      MIN_BODY_TOKENS = 3

      # @return [SmartMerger] The merger instance driving this run
      attr_reader :merger

      # @param merger [SmartMerger] The merger to run
      def initialize(merger:)
        @merger = merger
      end

      # Execute the three-phase merge and return the result.
      #
      # @return [MergeResult] The merged output
      def merge
        root_operation = start_runtime_session!

        merge_result = if comment_only_merge?
                         merger.send(:comment_only_file_merger).merge
                       else
                         template_by_signature = merger.send(:build_signature_map, merger.template_analysis)
                         dest_by_signature = merger.send(:build_signature_map, merger.dest_analysis)
                         prepare_comment_augmenters!(template_by_signature: template_by_signature,
                                                     dest_by_signature: dest_by_signature)
                         consumed_template_indices = Set.new
                         sig_cursor = Hash.new(0)
                         output_dest_line_ranges = []
                         last_output_dest_line = merger.send(:emit_dest_prefix_lines, merger.result,
                                                             merger.dest_analysis)

                         # Phase 1: exact signature match (existing behavior).
                         dest_sigs = ::Set.new(dest_by_signature.keys)

                         # Phase 2: compute similarity-matched pairs from residual orphans.
                         @similarity_pairs = compute_similarity_pairs(template_by_signature, dest_by_signature)

                         # Phase 3: cross-depth search, but only for orphans surviving Phases 1+2.
                         @deep_dest_sigs = compute_deep_sigs_for_orphans(
                           template_by_signature, dest_sigs
                         )

                         trailing_groups, _matched_indices = build_dest_iterate_trailing_groups(
                           template_nodes: merger.template_analysis.statements,
                           dest_sigs: dest_sigs,
                           signature_for: ->(node) { merger.template_analysis.generate_signature(node) },
                           add_template_only_nodes: merger.add_template_only_nodes
                         )
                         destination_template_indices = destination_template_index_sequence(
                           template_by_signature: template_by_signature
                         )
                         destination_signatures = merger.dest_analysis.statements.map do |dest_node|
                           merger.dest_analysis.generate_signature(dest_node)
                         end

                         unless destination_tail_template_only_placement?
                           emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
                             emit_template_only_node(info, consumed_template_indices)
                           end
                         end

                         merger.dest_analysis.statements.each_with_index do |dest_node, dest_position|
                           last_output_dest_line = process_dest_node(
                             dest_node: dest_node,
                             template_by_signature: template_by_signature,
                             consumed_template_indices: consumed_template_indices,
                             sig_cursor: sig_cursor,
                             output_dest_line_ranges: output_dest_line_ranges,
                             last_output_dest_line: last_output_dest_line,
                             dest_position: dest_position,
                             destination_signatures: destination_signatures,
                             destination_template_indices: destination_template_indices
                           )
                           next if destination_tail_template_only_placement?

                           emit_available_trailing_groups(
                             trailing_groups: trailing_groups,
                             consumed_indices: consumed_template_indices,
                             dest_position: dest_position,
                             destination_template_indices: destination_template_indices
                           )
                         end

                         # Safety net: emit any trailing groups whose anchor was never consumed
                         unless destination_tail_template_only_placement?
                           emit_remaining_trailing_groups(
                             trailing_groups: trailing_groups,
                             consumed_indices: consumed_template_indices
                           ) do |info|
                             emit_template_only_node(info, consumed_template_indices)
                           end
                         end
                         if destination_tail_template_only_placement?
                           emit_tail_template_only_nodes(consumed_template_indices)
                         end

                         emit_dest_postlude_lines(last_output_dest_line)
                         normalize_layout_blank_runs(merger.result)

                         merger.result
                       end

        complete_runtime_session!(root_operation, merge_result)
        merge_result
      rescue StandardError => e
        fail_runtime_session!(root_operation, e)
        raise
      end

      private

      def start_runtime_session!
        session = Ast::Merge::Runtime::Session.new(
          policy_context: {
            preference: merger.preference,
            add_template_only_nodes: merger.add_template_only_nodes,
            remove_template_missing_nodes: merger.remove_template_missing_nodes,
            corruption_handling: merger.corruption_handling,
            resolution_mode: merger.resolution_mode,
            unresolved_policy: merger.unresolved_policy.to_h
          },
          metadata: {
            merger: merger.class.name,
            render_family: merger.dest_analysis.feature_profile.render_family
          },
          delegation_registry: runtime_delegation_registry
        )
        @runtime_session = session

        root_surface = runtime_document_surface
        root_delegate = session.resolve_delegate_for(root_surface, capability: :merge)
        root_operation = Ast::Merge::Runtime::Operation.new(
          operation_id: 'ruby-document-0',
          surface: root_surface,
          template_fragment: merger.template_content,
          destination_fragment: merger.dest_content,
          requested_strategy: :top_level_merge,
          options: {
            feature_profile: merger.dest_analysis.feature_profile.to_h,
            resolution_mode: merger.resolution_mode,
            unresolved_policy: merger.unresolved_policy.to_h
          }
        ).running!

        session.register(
          root_operation,
          frame: Ast::Merge::Runtime::Frame.new(
            operation_id: root_operation.operation_id,
            depth: 0,
            surface_path: root_surface.address,
            language_chain: [root_surface.effective_language]
          ),
          delegate: root_delegate
        )
        add_missing_delegate_diagnostic!(session, root_operation, capability: :merge) unless root_delegate

        register_discovered_surface_operations!(session, root_operation)
        merger.send(:record_runtime_session, session)
        root_operation
      end

      def complete_runtime_session!(root_operation, merge_result)
        return unless @runtime_session && root_operation

        delegated_child_merge_complete = root_operation.children.all?(&:completed?)
        child_result = Ast::Merge::Runtime::ChildResult.new(
          replacement_text: merge_result.to_s,
          diagnostics: @runtime_session.diagnostics,
          capabilities_used: if delegated_child_merge_complete
                               %i[top_level_merge nested_surface_discovery
                                  delegated_child_merge]
                             else
                               %i[top_level_merge
                                  nested_surface_discovery]
                             end,
          capabilities_missing: delegated_child_merge_complete ? [] : %i[delegated_child_merge],
          unresolved_cases: merge_result.unresolved_cases,
          metadata: {
            decision_summary: merge_result.respond_to?(:decision_summary) ? merge_result.decision_summary : merge_result.statistics
          }
        )

        root_operation.add_diagnostic(
          Ast::Merge::Runtime::Diagnostic.new(
            severity: :info,
            kind: :merge_completed,
            operation_id: root_operation.operation_id,
            surface_path: root_operation.surface.address,
            message: 'Completed top-level Prism merge',
            metadata: {
              child_operation_count: root_operation.children.size
            }
          )
        )

        if child_result.unresolved?
          root_operation.unresolved!(result: child_result)
        else
          root_operation.complete!(result: child_result)
        end
        merger.send(:record_runtime_session, @runtime_session)
      end

      def fail_runtime_session!(root_operation, error)
        return unless @runtime_session && root_operation

        root_operation.fail!(
          diagnostic: Ast::Merge::Runtime::Diagnostic.new(
            severity: :error,
            kind: :merge_failed,
            operation_id: root_operation.operation_id,
            surface_path: root_operation.surface.address,
            message: error.message,
            metadata: {
              error_class: error.class.name
            }
          )
        )
        merger.send(:record_runtime_session, @runtime_session)
      end

      def runtime_document_surface
        max_lines = [merger.template_analysis.lines.length, merger.dest_analysis.lines.length].max

        Ast::Merge::Runtime::Surface.new(
          surface_kind: :ruby_document,
          effective_language: :ruby,
          address: 'document[0]',
          span: max_lines.zero? ? nil : (1..max_lines),
          reconstruction_strategy: :replace_inner_span,
          metadata: {
            template_line_count: merger.template_analysis.lines.length,
            destination_line_count: merger.dest_analysis.lines.length
          }
        )
      end

      def register_discovered_surface_operations!(session, root_operation)
        paired = paired_doc_surfaces
        return if paired.empty?

        combined_surface_index = paired.each_with_object({}) do |pair, index|
          surface = pair[:destination_surface] || pair[:template_surface]
          index[surface.address] = surface if surface
        end

        paired.each_with_index do |pair, index|
          surface = pair[:destination_surface] || pair[:template_surface]
          next unless surface

          operation_id = "ruby-surface-#{index}"
          child_operation = Ast::Merge::Runtime::Operation.new(
            operation_id: operation_id,
            surface: surface,
            template_fragment: fragment_for(pair[:template_surface], merger.template_analysis),
            destination_fragment: fragment_for(pair[:destination_surface], merger.dest_analysis),
            requested_strategy: :delegate_child_surface,
            options: {
              template_present: !pair[:template_surface].nil?,
              destination_present: !pair[:destination_surface].nil?,
              template_surface: pair[:template_surface],
              destination_surface: pair[:destination_surface]
            }
          )
          child_operation.add_diagnostic(
            Ast::Merge::Runtime::Diagnostic.new(
              severity: :info,
              kind: :surface_discovered,
              operation_id: operation_id,
              surface_path: surface.address,
              message: 'Discovered nested Ruby documentation surface pending delegated merge',
              metadata: {
                surface_kind: surface.surface_kind,
                template_present: !pair[:template_surface].nil?,
                destination_present: !pair[:destination_surface].nil?
              }
            )
          )
          child_delegate = session.resolve_delegate_for(surface, capability: :merge)
          add_missing_delegate_diagnostic!(session, child_operation, capability: :merge) unless child_delegate

          root_operation.add_child(child_operation)
          session.register(
            child_operation,
            frame: Ast::Merge::Runtime::Frame.new(
              parent_operation_id: root_operation.operation_id,
              operation_id: operation_id,
              depth: surface.address.split(' > ').length - 1,
              surface_path: surface.address,
              language_chain: runtime_language_chain_for(surface, combined_surface_index)
            ),
            delegate: session.resolve_delegate_for(surface)
          )
        end

        execute_child_operations!(session, root_operation)

        root_operation.add_diagnostic(
          Ast::Merge::Runtime::Diagnostic.new(
            severity: :info,
            kind: :embedded_surfaces_discovered,
            operation_id: root_operation.operation_id,
            surface_path: root_operation.surface.address,
            message: "Discovered #{root_operation.children.size} nested Ruby documentation surfaces",
            metadata: {
              child_operation_ids: root_operation.children.map(&:operation_id)
            }
          )
        )
      end

      def paired_doc_surfaces
        template_surfaces = discovered_surfaces_for(merger.template_analysis)
        destination_surfaces = discovered_surfaces_for(merger.dest_analysis)
        addresses = (template_surfaces.keys + destination_surfaces.keys).uniq.sort

        addresses.map do |address|
          {
            template_surface: template_surfaces[address],
            destination_surface: destination_surfaces[address]
          }
        end
      end

      def discovered_surfaces_for(analysis)
        analyzer = analysis.ruby_doc_surface_analyzer
        analyzer.discover_surfaces.each_with_object({}) do |surface, surfaces|
          surfaces[surface.address] = surface
        end
      end

      def fragment_for(surface, analysis)
        return '' unless surface && analysis

        line_numbers = surface.metadata[:line_numbers] || surface.span&.to_a
        return '' unless line_numbers

        Array(line_numbers).map { |line_number| analysis.line_at(line_number).to_s }.join
      end

      def runtime_language_chain_for(surface, combined_surface_index)
        return [:ruby] if surface.address == 'document[0]'

        parent = combined_surface_index[surface.parent_address]
        chain = parent ? runtime_language_chain_for(parent, combined_surface_index) : [:ruby]
        surface.effective_language ? chain + [surface.effective_language] : chain
      end

      def execute_child_operations!(session, root_operation)
        root_operation.children
                      .sort_by do |child_operation|
          [-session.frame_for(child_operation.operation_id).depth,
           child_operation.surface.address]
        end
                      .each do |child_operation|
          delegate = session.resolve_delegate_for(child_operation.surface, capability: :merge)
          next unless delegate

          child_operation.running!
          child_result = delegate.merge(operation: child_operation, session: session)
          child_operation.add_diagnostic(
            Ast::Merge::Runtime::Diagnostic.new(
              severity: :info,
              kind: :child_merge_completed,
              operation_id: child_operation.operation_id,
              surface_path: child_operation.surface.address,
              message: "Completed delegated child merge for #{child_operation.surface.surface_kind}",
              metadata: child_result.metadata.merge(delegate_name: delegate.name)
            )
          )
          child_operation.complete!(result: child_result)
        rescue StandardError => e
          child_operation.fail!(
            diagnostic: Ast::Merge::Runtime::Diagnostic.new(
              severity: :error,
              kind: :delegation_failed,
              operation_id: child_operation.operation_id,
              surface_path: child_operation.surface.address,
              message: e.message,
              metadata: {
                error_class: e.class.name,
                delegate_name: delegate&.name
              }
            )
          )
        end
      end

      def runtime_delegation_registry
        Ast::Merge::Runtime::DelegationRegistry.new(
          delegates: [runtime_prism_delegate],
          metadata: {
            source: :prism_merge
          }
        )
      end

      def runtime_prism_delegate
        Ast::Merge::Runtime::Delegate.new(
          name: 'prism-ruby',
          priority: 100,
          surface_kinds: %i[ruby_document ruby_doc_comment yard_example_block],
          languages: %i[ruby yard],
          feature_profile: merger.dest_analysis.feature_profile,
          capabilities: {
            merge: %i[ruby_document ruby_doc_comment yard_example_block],
            discover_child_surfaces: %i[ruby_document ruby_doc_comment]
          },
          merge: method(:merge_runtime_surface),
          metadata: {
            merger: merger.class.name
          }
        )
      end

      def merge_runtime_surface(operation:, session:)
        if operation.surface.surface_kind == :ruby_doc_comment
          return merge_runtime_doc_comment_surface(operation: operation,
                                                   session: session)
        end

        selected_source = runtime_fragment_source_for(operation)
        replacement_text =
          case selected_source
          when :template
            operation.template_fragment
          when :destination
            operation.destination_fragment
          else
            ''
          end

        Ast::Merge::Runtime::ChildResult.new(
          replacement_text: replacement_text,
          preserved_boundaries: runtime_preserved_boundaries_for(operation.surface),
          diagnostics: operation.diagnostics,
          capabilities_used: %i[delegated_child_merge fragment_selection],
          capabilities_missing: [],
          metadata: {
            selected_source: selected_source,
            surface_kind: operation.surface.surface_kind,
            template_present: operation.options[:template_present],
            destination_present: operation.options[:destination_present],
            delegate_name: operation.delegate_name,
            session_policy: session.policy_context
          }
        )
      end

      def merge_runtime_doc_comment_surface(operation:, session:)
        selected_source = runtime_fragment_source_for(operation)
        base_text =
          case selected_source
          when :template
            operation.template_fragment
          when :destination
            operation.destination_fragment
          else
            ''
          end

        replacement_text = apply_runtime_doc_children(base_text, operation, session)

        Ast::Merge::Runtime::ChildResult.new(
          replacement_text: replacement_text,
          preserved_boundaries: runtime_preserved_boundaries_for(operation.surface),
          diagnostics: operation.diagnostics,
          capabilities_used: %i[delegated_child_merge fragment_selection child_result_reintegration],
          capabilities_missing: [],
          metadata: {
            selected_source: selected_source,
            surface_kind: operation.surface.surface_kind,
            template_present: operation.options[:template_present],
            destination_present: operation.options[:destination_present],
            delegate_name: operation.delegate_name,
            child_operation_ids: session.operations.select do |candidate|
              candidate.surface.parent_address == operation.surface.address
            end.map(&:operation_id),
            session_policy: session.policy_context
          }
        )
      end

      def apply_runtime_doc_children(base_text, operation, session)
        lines = base_text.lines(chomp: true)

        session.operations
               .select do |candidate|
                 candidate.surface.parent_address == operation.surface.address &&
                   candidate.result.is_a?(Ast::Merge::Runtime::ChildResult) &&
                   candidate.surface.surface_kind == :yard_example_block
               end
               .sort_by do |candidate|
          -candidate.surface.metadata.fetch(:tag_relative_line,
                                            candidate.surface.metadata[:body_relative_span].begin - 1)
        end
               .each do |child_operation|
                 lines = apply_runtime_example_child(lines, child_operation)
               end

        join_runtime_lines(lines)
      end

      def apply_runtime_example_child(lines, child_operation)
        tag_relative_line = child_operation.surface.metadata.fetch(:tag_relative_line,
                                                                   child_operation.surface.metadata[:body_relative_span].begin - 1)
        body_relative_span = child_operation.surface.metadata[:body_relative_span]
        start_index = [tag_relative_line - 1, 0].max
        remove_count = body_relative_span ? (body_relative_span.end - tag_relative_line + 1) : 0
        selected_source = child_operation.result.metadata[:selected_source]

        if selected_source == :none
          return lines if start_index >= lines.length

          lines.dup.tap { |updated| updated.slice!(start_index, remove_count) }
        end

        block_lines = [
          child_operation.result.preserved_boundaries[:tag_header].to_s.sub(/\r?\n\z/, ''),
          *child_operation.result.replacement_text.lines(chomp: true)
        ]
        updated = lines.dup

        if start_index >= updated.length
          if start_index > updated.length
            padding_line = runtime_blank_comment_line_for(child_operation.surface)
            updated.insert(updated.length, *Array.new(start_index - updated.length, padding_line))
          end
          updated.insert(updated.length, *block_lines)
        else
          updated[start_index, remove_count] = block_lines
        end

        updated
      end

      def runtime_blank_comment_line_for(surface)
        prefix = surface.metadata[:comment_prefix].to_s
        stripped_prefix = prefix.rstrip
        stripped_prefix.empty? ? '#' : stripped_prefix
      end

      def join_runtime_lines(lines)
        return '' if lines.empty?

        "#{lines.join("\n")}\n"
      end

      def runtime_fragment_source_for(operation)
        template_present = operation.options[:template_present]
        destination_present = operation.options[:destination_present]

        if template_present && destination_present
          merger.send(:default_preference)
        elsif template_present
          merger.add_template_only_nodes ? :template : :none
        elsif destination_present
          merger.remove_template_missing_nodes ? :none : :destination
        else
          :none
        end
      end

      def runtime_preserved_boundaries_for(surface)
        boundaries = surface.metadata[:preserved_boundaries]
        return boundaries if boundaries

        {
          comment_prefix: surface.metadata[:comment_prefix]
        }.compact
      end

      def add_missing_delegate_diagnostic!(session, operation, capability:)
        return if session.resolve_delegate_for(operation.surface, capability: capability)

        operation.add_diagnostic(
          Ast::Merge::Runtime::Diagnostic.new(
            severity: :warn,
            kind: :unsupported_capability,
            operation_id: operation.operation_id,
            surface_path: operation.surface.address,
            message: "No runtime delegate resolved capability #{capability} for #{operation.surface.surface_kind}",
            metadata: {
              capability: capability,
              delegate_name: operation.delegate_name,
              surface_kind: operation.surface.surface_kind
            }
          )
        )
      end

      # Override the ast-merge hook to incorporate Phase 2 (similarity) and
      # Phase 3 (cross-depth) matches when deciding whether a template node
      # should be treated as "matched" vs "template-only".
      #
      # Called by {Ast::Merge::TrailingGroups::DestIterate} during trailing
      # group construction for each template node not matched by Phase 1.
      #
      # @param _node [Prism::Node] The template node under consideration
      # @param signature [Array, nil] The node's computed signature
      # @return [Boolean] true if the node should be treated as matched
      def trailing_group_node_matched?(_node, signature)
        return false unless signature

        # Phase 2: matched by body-text similarity?
        return true if @similarity_pairs&.key?(signature)

        # Phase 3: exists at a deeper depth in destination?
        return true if @deep_dest_sigs&.include?(signature)

        false
      end

      # ------------------------------------------------------------------
      # Phase 2: Body-text Jaccard similarity matching
      # ------------------------------------------------------------------

      # Compute similarity-based pairings for unmatched template nodes.
      #
      # After Phase 1 exact matching, some template and destination nodes
      # remain unpaired. This method extracts the body text of each
      # unmatched node, tokenizes it with {JaccardSimilarity#extract_tokens},
      # and uses greedy highest-score-first matching to pair probable
      # renames or minor refactors.
      #
      # Only nodes with meaningful body text (≥ {MIN_BODY_TOKENS} tokens)
      # are considered. The result is a Hash mapping template signature
      # to its similarity-paired destination signature.
      #
      # @param template_by_signature [Hash] Phase 1 template signature map
      # @param dest_by_signature [Hash] Phase 1 destination signature map
      # @return [Hash{Array => Array}] Template sig → dest sig pairs
      def compute_similarity_pairs(template_by_signature, dest_by_signature)
        pairs = {}
        template_sigs = ::Set.new(template_by_signature.keys)
        dest_sigs = ::Set.new(dest_by_signature.keys)
        matched_sigs = template_sigs & dest_sigs

        # Residual: unmatched signatures after Phase 1
        unmatched_t_sigs = template_sigs - matched_sigs
        unmatched_d_sigs = dest_sigs - matched_sigs

        return pairs if unmatched_t_sigs.empty? || unmatched_d_sigs.empty?

        # Build candidate lists: [{sig:, node:, tokens:}, ...]
        t_candidates = build_token_candidates(unmatched_t_sigs, template_by_signature, merger.template_analysis)
        d_candidates = build_token_candidates(unmatched_d_sigs, dest_by_signature, merger.dest_analysis)

        return pairs if t_candidates.empty? || d_candidates.empty?

        # Score all pairs, greedily assign best matches
        scored = []
        t_candidates.each do |tc|
          d_candidates.each do |dc|
            score = jaccard(tc[:tokens], dc[:tokens])
            scored << { t_sig: tc[:sig], d_sig: dc[:sig], score: score } if score > SIMILARITY_THRESHOLD
          end
        end

        scored.sort_by! { |s| -s[:score] }

        used_t = ::Set.new
        used_d = ::Set.new
        scored.each do |s|
          next if used_t.include?(s[:t_sig]) || used_d.include?(s[:d_sig])

          pairs[s[:t_sig]] = s[:d_sig]
          used_t << s[:t_sig]
          used_d << s[:d_sig]
        end

        pairs
      end

      # Build tokenized candidates from unmatched signatures.
      #
      # For each unmatched signature, extracts the body text of the
      # corresponding node, tokenizes it, and filters out nodes with
      # too few tokens for meaningful comparison.
      #
      # @param sigs [Set<Array>] Unmatched signatures
      # @param sig_map [Hash] Signature → [{node:, index:}, ...] map
      # @param analysis [FileAnalysis] Source analysis for text extraction
      # @return [Array<Hash>] Candidates with :sig, :node, :tokens keys
      def build_token_candidates(sigs, sig_map, analysis)
        candidates = []
        sigs.each do |sig|
          entries = sig_map[sig]
          next unless entries&.first

          node = entries.first[:node]
          body_text = extract_node_body_text(node, analysis)
          next if body_text.empty?

          tokens = extract_tokens(body_text, stopwords: ::Set.new, min_length: 2)
          next if tokens.size < MIN_BODY_TOKENS

          candidates << { sig: sig, node: node, tokens: tokens }
        end
        candidates
      end

      # Extract the body text of a node for Jaccard comparison.
      #
      # Only extracts body text from compound nodes that have meaningful
      # nested content (methods, classes, modules). Simple call nodes,
      # assignments, and other leaf-level nodes return empty strings
      # because their short source text leads to spurious matches.
      #
      # @param node [Prism::Node] The node to extract text from
      # @param analysis [FileAnalysis] Source analysis for line access
      # @return [String] Body text suitable for tokenization
      def extract_node_body_text(node, _analysis)
        actual = unwrap_node(node)
        case NodeTypeNormalizer.canonical_type(actual.type.to_s, :prism)
        when :def
          return '' unless actual.body

          actual.body.slice.to_s
        when :class, :module
          return '' unless actual.body

          actual.body.slice.to_s
        else
          # Leaf-level nodes (calls, assignments, etc.) are not eligible
          # for body-text similarity matching — their source text is too
          # short and leads to false positives.
          ''
        end
      end

      # ------------------------------------------------------------------
      # Phase 3: Cross-depth signature search
      # ------------------------------------------------------------------

      # Collect deep signatures only for template orphans surviving
      # Phase 1 and Phase 2.
      #
      # This narrows the expensive recursive AST walk to only the
      # signatures that are actually needed, rather than walking the
      # entire destination tree unconditionally.
      #
      # @param template_by_signature [Hash] Phase 1 template signature map
      # @param dest_sigs [Set<Array>] Phase 1 destination signatures
      # @return [Set<Array>] Signatures found at depth > 0 in the dest AST
      def compute_deep_sigs_for_orphans(template_by_signature, dest_sigs)
        template_sigs = ::Set.new(template_by_signature.keys)

        # Remove Phase 1 exact matches
        orphan_sigs = template_sigs - dest_sigs

        # Remove Phase 2 similarity matches
        orphan_sigs -= @similarity_pairs.keys if @similarity_pairs

        return ::Set.new if orphan_sigs.empty?

        # Only walk the destination AST for remaining orphans
        collect_deep_signatures(merger.dest_analysis, target_sigs: orphan_sigs)
      end

      # Recursively collect signatures from nested destination AST nodes.
      #
      # Walks into compound nodes (conditionals, begin/rescue, call blocks)
      # looking for signatures that match any of the +target_sigs+. Stops
      # early once all targets are found.
      #
      # @param analysis [FileAnalysis] Destination file analysis
      # @param target_sigs [Set<Array>, nil] If provided, only collect these
      #   signatures (early termination). If nil, collect all nested sigs.
      # @return [Set<Array>] Signatures found at depth > 0
      def collect_deep_signatures(analysis, target_sigs: nil)
        sigs = ::Set.new
        analysis.statements.each do |node|
          collect_nested_signatures(node, analysis, sigs, depth: 0, target_sigs: target_sigs)
          break if target_sigs && (target_sigs - sigs).empty?
        end
        sigs
      end

      # Walk a single node's subtree collecting signatures.
      #
      # Limits recursion to compound statement nodes where a "moved"
      # statement is semantically plausible (conditionals, begin/rescue,
      # call blocks). Does not descend into method or class definitions
      # where the same call name would have different semantics.
      #
      # @param node [Prism::Node] Current node to examine
      # @param analysis [FileAnalysis] Source analysis for signature generation
      # @param sigs [Set<Array>] Accumulator for found signatures
      # @param depth [Integer] Current recursion depth (0 = top-level)
      # @param target_sigs [Set<Array>, nil] Optional early-termination target
      # @return [void]
      def collect_nested_signatures(node, analysis, sigs, depth:, target_sigs: nil)
        actual = unwrap_node(node)
        if depth > 0
          sig = analysis.generate_signature(actual)
          if sig
            sigs << sig if target_sigs.nil? || target_sigs.include?(sig)
            return if target_sigs && (target_sigs - sigs).empty?
          end
        end

        children = nested_statement_children(actual)
        children.each do |child|
          collect_nested_signatures(child, analysis, sigs, depth: depth + 1, target_sigs: target_sigs)
          break if target_sigs && (target_sigs - sigs).empty?
        end
      end

      # Extract the immediate statement children of compound nodes.
      #
      # These are the node types where a statement might have been "moved"
      # from top-level into a nested block. The traversal is intentionally
      # limited — we do NOT descend into DefNode or ClassNode bodies, as
      # those represent distinct semantic scopes.
      #
      # @param node [Prism::Node] The compound node to inspect
      # @return [Array<Prism::Node>] Immediate statement children
      def nested_statement_children(node)
        children = []
        case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
        when :if, :unless
          children.concat(extract_body(node.statements))
          subsequent = node.respond_to?(:subsequent) ? node.subsequent : node.consequent
          children.concat(extract_body(subsequent.statements)) if subsequent.respond_to?(:statements)
          children.concat(nested_statement_children(subsequent)) if subsequent && %w[if_node
                                                                                     else_node].include?(subsequent.type.to_s)
        when :else
          children.concat(extract_body(node.statements))
        when :begin
          children.concat(extract_body(node.statements))
          children.concat(extract_body(node.rescue_clause.statements)) if node.rescue_clause&.respond_to?(:statements)
          children.concat(extract_body(node.else_clause.statements)) if node.else_clause&.respond_to?(:statements)
          children.concat(extract_body(node.ensure_clause.statements)) if node.ensure_clause&.respond_to?(:statements)
        when :call
          children.concat(extract_body(node.block.body)) if node.block && node.block.type.to_s == 'block_node'
        end
        children
      end

      # ------------------------------------------------------------------
      # Shared helpers
      # ------------------------------------------------------------------

      def comment_only_merge?
        merger.comment_only_file?(merger.template_analysis) && merger.comment_only_file?(merger.dest_analysis)
      end

      def prepare_comment_augmenters!(template_by_signature:, dest_by_signature:)
        retained = retained_owner_plan(template_by_signature: template_by_signature,
                                       dest_by_signature: dest_by_signature)

        merger.instance_variable_set(:@template_retained_owners, retained[:template])
        merger.instance_variable_set(:@dest_retained_owners, retained[:destination])
        merger.instance_variable_set(
          :@template_comment_augmenter,
          merger.template_analysis.comment_augmenter(owners: retained[:template])
        )
        merger.instance_variable_set(
          :@dest_comment_augmenter,
          merger.dest_analysis.comment_augmenter(owners: retained[:destination])
        )
      end

      def destination_tail_template_only_placement?
        merger.template_only_placement == :destination_tail
      end

      def emit_tail_template_only_nodes(consumed_template_indices)
        return unless merger.add_template_only_nodes

        merger.template_analysis.statements.each_with_index do |node, index|
          next if consumed_template_indices.include?(index)

          add_tail_template_separator if template_only_node_allowed?(node)

          emit_template_only_node({ node: node, index: index }, consumed_template_indices)
        end
      end

      def add_tail_template_separator
        return if merger.result.lines.empty?
        return if merger.result.lines.last.to_s.empty?

        merger.result.add_line(
          '',
          decision: Prism::Merge::MergeResult::DECISION_APPENDED,
          comment: 'separator before tail template-only Ruby node'
        )
      end

      def emit_template_only_node(info, consumed_template_indices)
        consumed_template_indices << info[:index]
        return unless template_only_node_allowed?(info[:node])

        merger.send(:add_node_to_result, merger.result, info[:node], merger.template_analysis, :template)
      end

      def template_only_node_allowed?(node)
        return true if merger.merge_template_requires

        !ruby_require_call?(node)
      end

      def ruby_require_call?(node)
        node.is_a?(::Prism::CallNode) && %i[require require_relative].include?(node.name)
      end

      def destination_template_index_sequence(template_by_signature:)
        sig_cursor = Hash.new(0)
        merger.dest_analysis.statements.map do |dest_node|
          signature = merger.dest_analysis.generate_signature(dest_node)
          next unless signature

          candidates = template_by_signature[signature]
          next unless candidates

          candidate = candidates[sig_cursor[signature]]
          sig_cursor[signature] += 1 if candidate
          candidate&.fetch(:index)
        end
      end

      def emit_available_trailing_groups(trailing_groups:, consumed_indices:, dest_position:,
                                         destination_template_indices:)
        trailing_groups.each do |anchor_index, group|
          next if anchor_index == :prefix
          next unless consumed_indices.include?(anchor_index)
          next unless trailing_group_safe_to_emit?(group, consumed_indices, dest_position, destination_template_indices)

          group.each do |info|
            next if consumed_indices.include?(info[:index])

            emit_template_only_node(info, consumed_indices)
          end
        end
      end

      def trailing_group_safe_to_emit?(group, consumed_indices, dest_position, destination_template_indices)
        pending_group_indices = group.filter_map do |info|
          index = info.fetch(:index)
          index unless consumed_indices.include?(index)
        end
        return false if pending_group_indices.empty?

        first_group_index = pending_group_indices.min
        future_indices = destination_template_indices[(dest_position + 1)..] || []
        future_indices.compact.none? do |future_index|
          future_index < first_group_index && !consumed_indices.include?(future_index)
        end
      end

      def retained_owner_plan(template_by_signature:, dest_by_signature:)
        matched_template_indices = Set.new
        retained_dest_indices = Set.new
        sig_cursor = Hash.new(0)

        merger.dest_analysis.statements.each_with_index do |dest_node, dest_index|
          dest_signature = merger.dest_analysis.generate_signature(dest_node)
          next unless dest_signature && template_by_signature.key?(dest_signature)

          template_info, cursor = next_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor
          )
          next unless template_info

          matched_template_indices << template_info[:index]
          retained_dest_indices << dest_index
          sig_cursor[dest_signature] = cursor + 1
        end

        merger.dest_analysis.statements.each_with_index do |_dest_node, dest_index|
          next if retained_dest_indices.include?(dest_index)
          next if merger.remove_template_missing_nodes

          retained_dest_indices << dest_index
        end

        template_retained = merger.template_analysis.statements.each_with_index.filter_map do |template_node, template_index|
          next template_node if matched_template_indices.include?(template_index)
          next template_node if merger.add_template_only_nodes

          nil
        end

        destination_retained = merger.dest_analysis.statements.each_with_index.filter_map do |dest_node, dest_index|
          dest_node if retained_dest_indices.include?(dest_index)
        end

        {
          template: template_retained,
          destination: destination_retained
        }
      end

      def process_dest_node(
        dest_node:,
        template_by_signature:,
        consumed_template_indices:,
        sig_cursor:,
        output_dest_line_ranges:,
        last_output_dest_line:,
        dest_position:,
        destination_signatures:,
        destination_template_indices:
      )
        node_range = node_offset_range(dest_node)
        return last_output_dest_line if already_output?(node_range, output_dest_line_ranges)

        dest_signature = merger.dest_analysis.generate_signature(dest_node)
        if dest_signature && template_by_signature.key?(dest_signature)
          template_info, = peek_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor
          )
          if defer_duplicate_destination_node?(
            dest_signature: dest_signature,
            template_info: template_info,
            dest_position: dest_position,
            destination_signatures: destination_signatures,
            destination_template_indices: destination_template_indices,
            consumed_template_indices: consumed_template_indices
          )
            prune_removed_owner_leading_gap(dest_node)
            output_dest_line_ranges << node_range
            return dest_node.location.end_line
          end
        end

        last_output_dest_line = merger.send(:emit_dest_gap_lines, merger.result, merger.dest_analysis,
                                            last_output_dest_line, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis
        advance_dest_output = true

        if dest_signature && template_by_signature.key?(dest_signature)
          template_info, cursor = next_template_match(
            candidates: template_by_signature[dest_signature],
            signature: dest_signature,
            sig_cursor: sig_cursor
          )

          if template_info
            emission = process_matched_node(
              dest_node: dest_node,
              dest_signature: dest_signature,
              template_info: template_info,
              cursor: cursor,
              consumed_template_indices: consumed_template_indices,
              sig_cursor: sig_cursor,
              output_dest_line_ranges: output_dest_line_ranges,
              node_range: node_range,
              last_output_dest_line: last_output_dest_line
            )
            last_output_dest_line = emission[:last_output_dest_line]
            output_node = emission[:output_node]
            output_analysis = emission[:output_analysis]

          else
            if merger.remove_template_missing_nodes
              emission = merger.send(:emit_removed_destination_node_comments, merger.result, dest_node,
                                     merger.dest_analysis)
              last_output_dest_line = emission_last_output(last_output_dest_line, emission)
              advance_dest_output = advance_dest_output?(emission)
            else
              emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
              last_output_dest_line = emission_last_output(last_output_dest_line, emission)
            end
            output_dest_line_ranges << node_range
          end
        else
          if merger.remove_template_missing_nodes
            emission = merger.send(:emit_removed_destination_node_comments, merger.result, dest_node,
                                   merger.dest_analysis)
            last_output_dest_line = emission_last_output(last_output_dest_line, emission)
            advance_dest_output = advance_dest_output?(emission)
          else
            emission = merger.send(:add_node_to_result, merger.result, dest_node, merger.dest_analysis, :destination)
            last_output_dest_line = emission_last_output(last_output_dest_line, emission)
          end
          output_dest_line_ranges << node_range
        end

        advance_last_output_dest_line(
          last_output_dest_line: last_output_dest_line,
          dest_node: dest_node,
          output_node: output_node,
          output_analysis: output_analysis,
          advance_dest_output: advance_dest_output,
          preserve_trailing_blank_line_progress: emission&.fetch(:preserve_trailing_blank_line_progress, false)
        )
      end

      def already_output?(node_range, output_dest_line_ranges)
        output_dest_line_ranges.any? do |range|
          range[:start_offset] <= node_range[:start_offset] && node_range[:end_offset] <= range[:end_offset]
        end
      end

      def node_offset_range(node)
        location = node.location
        start_offset = if location.respond_to?(:start_offset)
                         location.start_offset
                       elsif node.respond_to?(:start_byte)
                         node.start_byte
                       else
                         location.start_line
                       end

        end_offset = if location.respond_to?(:end_offset)
                       location.end_offset
                     elsif node.respond_to?(:end_byte)
                       node.end_byte
                     else
                       location.end_line
                     end

        {
          start_offset: start_offset,
          end_offset: end_offset
        }
      end

      def next_template_match(candidates:, signature:, sig_cursor:)
        cursor = sig_cursor[signature]

        candidate = candidates[cursor]
        return [candidate, cursor] if candidate

        [nil, cursor]
      end

      def peek_template_match(candidates:, signature:, sig_cursor:)
        cursor = sig_cursor[signature]
        [candidates[cursor], cursor]
      end

      def defer_duplicate_destination_node?(
        dest_signature:,
        template_info:,
        dest_position:,
        destination_signatures:,
        destination_template_indices:,
        consumed_template_indices:
      )
        return false unless template_info
        return false unless destination_signatures[(dest_position + 1)..]&.include?(dest_signature)

        template_index = template_info.fetch(:index)
        future_indices = destination_template_indices[(dest_position + 1)..] || []
        future_indices.compact.any? do |future_index|
          future_index < template_index && !consumed_template_indices.include?(future_index)
        end
      end

      def prune_removed_owner_leading_gap(dest_node)
        return unless merger.dest_analysis.respond_to?(:layout_attachment_for)

        Ast::Merge::Layout.prune_emitted_leading_gap_for_removed_owner(
          result: merger.result,
          attachment: merger.dest_analysis.layout_attachment_for(dest_node)
        )
      end

      def normalize_layout_blank_runs(result)
        result.normalize_blank_line_runs!(max: 1) if result.respond_to?(:normalize_blank_line_runs!)
      end

      def process_matched_node(dest_node:, dest_signature:, template_info:, cursor:, consumed_template_indices:,
                               sig_cursor:, output_dest_line_ranges:, node_range:, last_output_dest_line:)
        template_node = template_info[:node]
        consumed_template_indices << template_info[:index]
        sig_cursor[dest_signature] = cursor + 1
        output_dest_line_ranges << node_range

        if merger.send(:should_merge_recursively?, template_node, dest_node)
          process_recursive_match(
            template_node: template_node,
            dest_node: dest_node,
            last_output_dest_line: last_output_dest_line
          )
        else
          process_non_recursive_match(
            template_node: template_node,
            dest_node: dest_node,
            last_output_dest_line: last_output_dest_line
          )
        end
      end

      def process_recursive_match(template_node:, dest_node:, last_output_dest_line:)
        recursive_emission = merger.send(:merge_node_body_recursively, template_node, dest_node)
        output_node = dest_node
        output_analysis = merger.dest_analysis

        if merger.send(:preference_for_node, template_node, dest_node) == :template
          output_node = unwrap_node(template_node)
          output_analysis = merger.template_analysis
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, recursive_emission),
          output_node: output_node,
          output_analysis: output_analysis,
          preserve_trailing_blank_line_progress: true
        }
      end

      def process_non_recursive_match(template_node:, dest_node:, last_output_dest_line:)
        output_node = dest_node
        output_analysis = merger.dest_analysis
        emission = nil

        if reviewable_unresolved_match?(template_node, dest_node)
          emission = process_unresolved_non_recursive_match(template_node: template_node, dest_node: dest_node)
          if emission[:provisional_winner] == :template
            output_node = template_node
            output_analysis = merger.template_analysis
          end
        elsif merger.send(:preference_for_node, template_node, dest_node) == :template
          emission = merger.send(:add_matched_template_node_to_result, merger.result, template_node, dest_node)
          output_node = template_node
          output_analysis = merger.template_analysis
        else
          emission = merger.send(
            :add_node_to_result,
            merger.result,
            dest_node,
            merger.dest_analysis,
            :destination,
            matched_template_node: template_node
          )
        end

        {
          last_output_dest_line: emission_last_output(last_output_dest_line, emission),
          output_node: output_node,
          output_analysis: output_analysis,
          preserve_trailing_blank_line_progress: emission&.fetch(:preserve_trailing_blank_line_progress, false)
        }
      end

      def process_unresolved_non_recursive_match(template_node:, dest_node:)
        provisional_winner = merger.unresolved_policy.provisional_winner_for(
          :matched_node,
          fallback: merger.send(:preference_for_node, template_node, dest_node)
        )

        emission =
          if provisional_winner == :template
            merger.send(:add_matched_template_node_to_result, merger.result, template_node, dest_node)
          else
            merger.send(
              :add_node_to_result,
              merger.result,
              dest_node,
              merger.dest_analysis,
              :destination,
              matched_template_node: template_node
            )
          end

        result_line_span = emission[:result_line_span]
        mark_emitted_lines_unresolved!(result_line_span)
        record_unresolved_match_case!(
          template_node: template_node,
          dest_node: dest_node,
          provisional_winner: provisional_winner,
          result_line_span: result_line_span
        )

        emission.merge(provisional_winner: provisional_winner)
      end

      def reviewable_unresolved_match?(template_node, dest_node)
        return false unless merger.send(:unresolved_mode?)
        return false unless merger.unresolved_policy.unresolved_for?(:matched_node)

        template_candidate = unresolved_match_candidate_text(template_node, merger.template_analysis)
        destination_candidate = unresolved_match_candidate_text(dest_node, merger.dest_analysis)
        template_candidate != destination_candidate
      end

      def record_unresolved_match_case!(template_node:, dest_node:, provisional_winner:, result_line_span:)
        result_start_line, result_end_line = Array(result_line_span)
        node_type = unresolved_match_node_type(dest_node || template_node)
        surface_path = unresolved_match_surface_path(dest_node, template_node)
        merger.send(
          :record_unresolved_node_choice,
          result: merger.result,
          template_node: template_node,
          destination_node: dest_node,
          template_text: unresolved_match_candidate_text(template_node, merger.template_analysis),
          destination_text: unresolved_match_candidate_text(dest_node, merger.dest_analysis),
          provisional_winner: provisional_winner,
          case_prefix: 'prism',
          case_parts: [:matched_node],
          case_id: unresolved_match_case_id(dest_node, template_node),
          surface_path: surface_path,
          metadata: {
            match_kind: :matched_node,
            node_type: node_type,
            line: result_start_line == result_end_line ? result_start_line : nil,
            result_lines: result_line_span,
            template_lines: unresolved_match_line_span(template_node),
            destination_lines: unresolved_match_line_span(dest_node),
            review_identity: merger.send(
              :review_identity_for_unresolved_choice,
              template_text: unresolved_match_candidate_text(template_node, merger.template_analysis),
              destination_text: unresolved_match_candidate_text(dest_node, merger.dest_analysis),
              provisional_winner: provisional_winner,
              surface_path: surface_path,
              match_kind: :matched_node,
              node_type: node_type,
              result_lines: result_line_span
            )
          },
          conflict_fields: {
            line: dest_node.location.start_line
          }
        )
      end

      def mark_emitted_lines_unresolved!(result_line_span)
        start_line, end_line = Array(result_line_span)
        return unless start_line && end_line
        return if end_line < start_line

        ((start_line - 1)...end_line).each do |index|
          metadata = merger.result.line_metadata[index]
          next unless metadata

          metadata[:decision] = Ast::Merge::MergeResultBase::DECISION_UNRESOLVED
        end
      end

      def unresolved_match_candidate_text(node, analysis)
        merger.send(:node_emission_support).send(:node_source_lines, node, analysis).join("\n")
      end

      def unresolved_match_case_id(dest_node, template_node)
        line = (dest_node || template_node).location.start_line
        "prism-matched_node-#{line}"
      end

      def unresolved_match_surface_path(dest_node, template_node)
        line = (dest_node || template_node).location.start_line
        merger.send(:unresolved_surface_path, "matched_node[line=#{line}]")
      end

      def unresolved_match_node_type(node)
        node.class.name.split('::').last
      end

      def unresolved_match_line_span(node)
        [
          node.location.start_line,
          merger.send(:node_emission_support).send(:effective_end_line, node)
        ]
      end

      def emission_last_output(last_output_dest_line, emission)
        emitted_dest_line = emission&.dig(:last_emitted_dest_line)
        return last_output_dest_line unless emitted_dest_line

        [last_output_dest_line, emitted_dest_line].max
      end

      def advance_last_output_dest_line(last_output_dest_line:, dest_node:, output_node:, output_analysis:,
                                        advance_dest_output: true, preserve_trailing_blank_line_progress: false)
        return last_output_dest_line unless advance_dest_output

        updated_last_output_dest_line = [last_output_dest_line, dest_node.location.end_line].max

        return updated_last_output_dest_line unless preserve_trailing_blank_line_progress

        actual_output_end = unwrap_node(output_node).location.end_line
        trailing_line_num = actual_output_end + 1
        trailing_content = output_analysis.line_at(trailing_line_num)
        return updated_last_output_dest_line unless trailing_content && trailing_content.strip.empty?

        trailing_dest_line = dest_node.location.end_line + 1
        dest_trailing = merger.dest_analysis.line_at(trailing_dest_line)
        return updated_last_output_dest_line unless dest_trailing && dest_trailing.strip.empty?

        [updated_last_output_dest_line, trailing_dest_line].max
      end

      def advance_dest_output?(emission)
        !emission&.fetch(:emitted_removed_owner_comments, false)
      end

      def emit_dest_postlude_lines(last_output_dest_line)
        postlude_gap = merger.dest_analysis.layout_augmenter.postlude_gap
        if postlude_gap
          emit_dest_blank_lines(([postlude_gap.start_line, last_output_dest_line + 1].max)..postlude_gap.end_line)
          return
        end

        remaining_line_range = (last_output_dest_line + 1)..merger.dest_analysis.lines.length
        emit_dest_blank_lines(remaining_line_range)
      end

      def emit_dest_blank_lines(line_range)
        return if line_range.begin > line_range.end

        line_range.each do |line_num|
          line = merger.dest_analysis.line_at(line_num).to_s.chomp
          next unless line.strip.empty?

          merger.result.add_line(
            line,
            decision: MergeResult::DECISION_KEPT_DEST,
            dest_line: line_num
          )
        end
      end

      def unwrap_node(node)
        node.respond_to?(:unwrap) ? node.unwrap : node
      end

      # Extract body statements from a StatementsNode or similar container.
      #
      # @param statements_node [Prism::StatementsNode, #body, nil]
      # @return [Array<Prism::Node>]
      def extract_body(statements_node)
        return [] unless statements_node

        if statements_node.type.to_s == 'statements_node'
          statements_node.body.compact
        elsif statements_node.respond_to?(:body)
          Array(statements_node.body).compact
        else
          []
        end
      end
    end
  end
end
