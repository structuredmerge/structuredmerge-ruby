# frozen_string_literal: true

module Psych
  module Merge
    # Resolves conflicts between template and destination YAML content
    # using structural signatures and configurable preferences.
    #
    # Inherits from Ast::Merge::ConflictResolverBase using the :batch strategy,
    # which resolves all conflicts at once using signature maps.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    #
    # @example With recursive merge for nested structures
    #   resolver = ConflictResolver.new(
    #     template_analysis,
    #     dest_analysis,
    #     recursive: true,
    #     add_template_only_nodes: true
    #   )
    #
    # @see Ast::Merge::ConflictResolverBase
    class ConflictResolver < Ast::Merge::ConflictResolverBase
      include ::Ast::Merge::StructuredEmitterProvenanceSupport
      include ::Ast::Merge::TrailingGroups::DestIterate

      attr_reader :corruption_handling

      # Creates a new ConflictResolver
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      # @param preference [Symbol, Hash] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination nodes not in template
      # @param recursive [Boolean, Integer] Whether to merge nested structures recursively
      #   - true: unlimited depth (default)
      #   - false: disabled
      #   - Integer > 0: max depth
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type preferences
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false,
                     add_template_only_sequence_items: nil, remove_template_missing_nodes: false, resolution_mode: :eager, corruption_handling: :heal, recursive: true, match_refiner: nil, node_typing: nil, comment_merge_policy: :preserve_destination, **options)
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
          recursive: recursive,
          match_refiner: match_refiner,
          **options
        )
        @resolution_mode = resolution_mode
        @corruption_handling = ::Ast::Merge::Healer.normalize_mode(corruption_handling)
        @add_template_only_sequence_items = add_template_only_sequence_items.nil? ? add_template_only_nodes : add_template_only_sequence_items
        @node_typing = node_typing
        @comment_merge_policy = normalize_comment_merge_policy(comment_merge_policy)
        @emitter = Emitter.new
        @last_document_node_recursively_merged = false
      end

      protected

      # Resolve conflicts and populate the result
      #
      # @param result [MergeResult] Result object to populate
      def resolve_batch(result)
        DebugLogger.time('ConflictResolver#resolve') do
          @result = result
          template_nodes = @template_analysis.statements
          dest_nodes = @dest_analysis.statements

          # Clear emitter for fresh merge
          @emitter.clear
          @last_document_node_recursively_merged = false

          # Build signature maps
          template_by_sig = build_signature_map(template_nodes, @template_analysis)
          dest_by_sig = build_signature_map(dest_nodes, @dest_analysis)

          # Build refined matches for nodes that don't match by signature
          @refined_matches = build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)

          # Process nodes via emitter
          merge_nodes_to_emitter(
            template_nodes,
            dest_nodes,
            template_by_sig,
            emit_destination_postlude: true
          )

          # Transfer emitter output to result
          transfer_emitter_output(result)

          DebugLogger.debug('Conflict resolution complete', {
                              template_nodes: template_nodes.size,
                              dest_nodes: dest_nodes.size,
                              result_lines: result.line_count
                            })
        end
      end

      private

      # Build a map of refined matches from template node to destination node.
      # Uses the match_refiner to find additional pairings for nodes that didn't match by signature.
      #
      # @param template_nodes [Array] Template nodes
      # @param dest_nodes [Array] Destination nodes
      # @param template_by_sig [Hash] Template signature map
      # @param dest_by_sig [Hash] Destination signature map
      # @return [Hash] Map of template node to destination node
      def build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        return {} unless @match_refiner

        # Find unmatched nodes
        matched_template_sigs = template_by_sig.keys & dest_by_sig.keys
        unmatched_t_nodes = template_nodes.reject do |n|
          sig = @template_analysis.generate_signature(n)
          sig && matched_template_sigs.include?(sig)
        end
        unmatched_d_nodes = dest_nodes.reject do |n|
          sig = @dest_analysis.generate_signature(n)
          sig && matched_template_sigs.include?(sig)
        end

        return {} if unmatched_t_nodes.empty? || unmatched_d_nodes.empty?

        # Call the refiner
        matches = @match_refiner.call(unmatched_t_nodes, unmatched_d_nodes, {
                                        template_analysis: @template_analysis,
                                        dest_analysis: @dest_analysis
                                      })

        # Build result map: template node -> dest node
        matches.each_with_object({}) do |match, h|
          h[match.template_node] = match.dest_node
        end
      end

      def merge_nodes_to_emitter(template_nodes, dest_nodes, template_by_sig, depth: 0,
                                 emit_destination_postlude: false, template_fallback_next_node: nil, dest_fallback_next_node: nil)
        # Build reverse lookup from dest_node to template_node for refined matches
        refined_dest_to_template = @refined_matches.invert
        next_template_by_id = build_next_node_lookup(template_nodes, fallback_next_node: template_fallback_next_node)
        next_dest_by_id = build_next_node_lookup(dest_nodes, fallback_next_node: dest_fallback_next_node)

        if emit_destination_postlude
          document_analysis, document_nodes = preferred_document_context(template_nodes, dest_nodes)
          emit_document_prelude(
            preferred_document_prelude_analysis(template_nodes, dest_nodes, document_analysis, document_nodes),
            nodes: preferred_document_prelude_nodes(template_nodes, dest_nodes, document_analysis, document_nodes)
          )
        end

        # Track consumed individual node indices (not just signatures) so that
        # multiple nodes sharing the same signature are matched 1:1 in order
        # rather than collapsed into a single match.
        consumed_template_indices = ::Set.new
        sig_cursor = Hash.new(0)

        # Pre-compute position-aware trailing groups for template-only nodes.
        dest_sigs = ::Set.new
        dest_nodes.each do |n|
          sig = @dest_analysis.generate_signature(n)
          dest_sigs << sig if sig
        end
        refined_template_ids = ::Set.new(@refined_matches.keys.map(&:object_id))

        trailing_groups, all_matched_template_indices = build_dest_iterate_trailing_groups(
          template_nodes: template_nodes,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { @template_analysis.generate_signature(node) },
          refined_template_ids: refined_template_ids,
          add_template_only_nodes: @add_template_only_nodes
        )

        # Emit template-only nodes that precede the first matched template node
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          next if freeze_node?(info[:node])

          emit_node(
            info[:node],
            @template_analysis,
            next_node: next_template_by_id[info[:node].object_id]
          )
        end

        # Track previous node end_line to preserve inter-node blank lines.
        # Blank lines between top-level YAML sections (e.g., between `name:` and `on:`)
        # are not part of any node or comment — they are purely visual separators.
        # We preserve them from the destination to maintain readability.
        prev_end_line = nil

        # First pass: Process destination nodes and find matches
        dest_nodes.each do |dest_node|
          next_dest_node = next_dest_by_id[dest_node.object_id]
          dest_sig = @dest_analysis.generate_signature(dest_node)
          effective_dest_end_line = effective_end_line(dest_node, @dest_analysis, next_node: next_dest_node)
          removed_boundary = nil

          # Preserve inter-node blank lines from destination
          if prev_end_line && dest_node.respond_to?(:start_line) && dest_node.start_line
            effective_start = effective_start_line(dest_node, @dest_analysis)

            # Emit blank lines that existed between the previous node and this one
            gap_start = prev_end_line + 1
            if gap_start < effective_start
              (gap_start...effective_start).each do |line_num|
                if @dest_analysis.respond_to?(:comment_tracker) &&
                   @dest_analysis.comment_tracker.blank_line?(line_num)
                  @emitter.emit_blank_line
                end
              end
            end
          end

          # Freeze blocks from destination are always preserved
          if freeze_node?(dest_node)
            emit_freeze_block(dest_node)
            prev_end_line = preferred_emitted_end_line(dest_node, effective_dest_end_line)
            next
          end

          matched_template_index = nil
          emitted_dest_node = true
          recursively_merged = false

          # Check for signature match first
          if dest_sig && template_by_sig[dest_sig]
            # Find the next unconsumed template node with this signature
            candidates = template_by_sig[dest_sig]
            cursor = sig_cursor[dest_sig]
            template_info = nil

            while cursor < candidates.size
              candidate = candidates[cursor]
              unless consumed_template_indices.include?(candidate[:index])
                template_info = candidate
                break
              end
              cursor += 1
            end

            if template_info
              template_node = template_info[:node]

              # Check if we should recursively merge nested structures
              if should_recurse?(depth) && can_merge_recursively?(template_node, dest_node)
                recursively_merged = true
                emit_recursive_merge(
                  template_node,
                  dest_node,
                  depth: depth,
                  next_template_node: next_template_by_id[template_node.object_id],
                  next_dest_node: next_dest_node
                )
              else
                emit_preferred_node(
                  template_node,
                  dest_node,
                  next_template_node: next_template_by_id[template_node.object_id],
                  next_dest_node: next_dest_node
                )
              end

              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1
              matched_template_index = template_info[:index]
            elsif @remove_template_missing_nodes
              # All template copies consumed — destination-only duplicate
              removed_boundary = emit_removed_destination_node_comments(dest_node, @dest_analysis,
                                                                        next_node: next_dest_node)
              emitted_dest_node = false
            elsif redundant_destination_duplicate?(dest_node, candidates)
              if handle_suspected_corruption(
                kind: :duplicate_destination_mapping_entry,
                message: 'destination mapping entry duplicates semantic content already present in the preferred template mapping',
                context: duplicate_destination_context(dest_node, @dest_analysis)
              )
                emitted_dest_node = false
              else
                emit_node(dest_node, @dest_analysis, next_node: next_dest_node)
              end
            else
              emit_node(dest_node, @dest_analysis, next_node: next_dest_node)
            end
          elsif refined_dest_to_template.key?(dest_node)
            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = @template_analysis.generate_signature(template_node)

            # Find and consume the matching template index
            if template_sig && template_by_sig[template_sig]
              template_by_sig[template_sig].each do |info|
                next if consumed_template_indices.include?(info[:index])

                consumed_template_indices << info[:index]
                matched_template_index = info[:index]
                break
              end
            end

            # If we couldn't find the index via sig map, find it by identity
            if matched_template_index.nil?
              template_nodes.each_with_index do |tn, idx|
                next unless tn.equal?(template_node) && !consumed_template_indices.include?(idx)

                consumed_template_indices << idx
                matched_template_index = idx
                break
              end
            end

            # Check if we should recursively merge nested structures
            if should_recurse?(depth) && can_merge_recursively?(template_node, dest_node)
              recursively_merged = true
              emit_recursive_merge(
                template_node,
                dest_node,
                depth: depth,
                next_template_node: next_template_by_id[template_node.object_id],
                next_dest_node: next_dest_node
              )
            else
              emit_preferred_node(
                template_node,
                dest_node,
                next_template_node: next_template_by_id[template_node.object_id],
                next_dest_node: next_dest_node
              )
            end
          elsif @remove_template_missing_nodes
            # Destination-only node
            # If remove_template_missing_nodes is enabled, skip this node (remove it)
            removed_boundary = emit_removed_destination_node_comments(dest_node, @dest_analysis,
                                                                      next_node: next_dest_node)
            emitted_dest_node = false
          else
            emit_node(dest_node, @dest_analysis, next_node: next_dest_node)
          end

          prev_end_line = if emitted_dest_node
                            preferred_emitted_end_line(dest_node, effective_dest_end_line)
                          else
                            removed_boundary || skipped_destination_node_boundary(next_dest_node, @dest_analysis)
                          end

          # Track whether the last document-level node was recursively merged.
          # Only relevant at the document root (emit_destination_postlude context).
          # The final iteration's value determines emit_document_postlude behavior.
          @last_document_node_recursively_merged = recursively_merged if emit_destination_postlude

          # After each dest node, flush any trailing groups that are now ready.
          # A group anchored at index K is ready when ALL matched template indices
          # with values 0..K have been consumed.  This prevents premature emission
          # when the dest reorders matched items relative to the template.
          flush_ready_trailing_groups(
            trailing_groups: trailing_groups,
            matched_indices: all_matched_template_indices,
            consumed_indices: consumed_template_indices
          ) do |info|
            next if freeze_node?(info[:node])

            emit_node(
              info[:node],
              @template_analysis,
              next_node: next_template_by_id[info[:node].object_id]
            )
          end
        end

        # Safety net: emit any remaining trailing groups whose anchor was never consumed
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices
        ) do |info|
          next if freeze_node?(info[:node])

          emit_node(
            info[:node],
            @template_analysis,
            next_node: next_template_by_id[info[:node].object_id]
          )
        end

        return unless emit_destination_postlude

        document_analysis, document_nodes = preferred_document_context(template_nodes, dest_nodes)
        emit_document_postlude(
          document_analysis,
          fallback_node: document_nodes.last
        )
        emit_supplemental_document_postlude(
          template_nodes: template_nodes,
          dest_nodes: dest_nodes,
          preferred_analysis: document_analysis
        )
      end

      # Override hook: freeze nodes are treated as matched for trailing group purposes.
      def trailing_group_node_matched?(node, _signature)
        freeze_node?(node)
      end

      def preferred_document_context(template_nodes, dest_nodes)
        return [@template_analysis, template_nodes] if default_preference == :template

        [@dest_analysis, dest_nodes]
      end

      def nonpreferred_document_context(template_nodes, dest_nodes)
        return [@dest_analysis, dest_nodes] if default_preference == :template

        [@template_analysis, template_nodes]
      end

      def preferred_document_prelude_analysis(template_nodes, dest_nodes, document_analysis, document_nodes)
        analysis, = preferred_document_prelude_context(template_nodes, dest_nodes, document_analysis, document_nodes)
        analysis
      end

      def preferred_document_prelude_nodes(template_nodes, dest_nodes, document_analysis, document_nodes)
        _, nodes = preferred_document_prelude_context(template_nodes, dest_nodes, document_analysis, document_nodes)
        nodes
      end

      def preferred_document_prelude_context(template_nodes, dest_nodes, document_analysis, document_nodes)
        return [document_analysis, document_nodes] unless @add_template_only_nodes
        return [document_analysis, document_nodes] unless document_leading_regions_for(
          document_comment_augmenter_for(document_analysis), document_nodes, document_analysis
        ).empty?
        return [document_analysis, document_nodes] if first_node_leading_comment_region(document_nodes,
                                                                                        document_analysis)

        supplemental_analysis, supplemental_nodes = nonpreferred_document_context(template_nodes, dest_nodes)
        supplemental_regions = document_leading_regions_for(
          document_comment_augmenter_for(supplemental_analysis),
          supplemental_nodes,
          supplemental_analysis
        )
        return [document_analysis, document_nodes] if supplemental_regions.empty?

        [supplemental_analysis, supplemental_nodes]
      end

      def emit_supplemental_document_postlude(template_nodes:, dest_nodes:, preferred_analysis:)
        return unless emit_nonpreferred_document_postlude?

        supplemental_analysis, supplemental_nodes = nonpreferred_document_context(template_nodes, dest_nodes)
        return unless supplemental_analysis && supplemental_nodes.any?

        preferred_nodes = preferred_analysis.equal?(@template_analysis) ? template_nodes : dest_nodes
        preferred_regions = document_trailing_regions_for(
          document_comment_augmenter_for(preferred_analysis),
          preferred_analysis,
          preferred_nodes.last
        )
        supplemental_regions = document_trailing_regions_for(
          document_comment_augmenter_for(supplemental_analysis),
          supplemental_analysis,
          supplemental_nodes.last
        )

        # For deduplication, also consider all orphan regions from the preferred
        # analysis — not just those past last_content_line. When the last
        # preferred YAML node's end_line encompasses trailing comments (e.g. a
        # multi-value mapping), those orphans are classified inside the node's
        # range and are excluded from preferred_regions by the start_line filter
        # in document_trailing_regions_for. Without this, an identical trailing
        # comment block present in both sources escapes deduplication and is
        # emitted twice.
        preferred_augmenter = document_comment_augmenter_for(preferred_analysis)
        all_preferred_regions = preferred_regions | Array(preferred_augmenter&.orphan_regions).compact

        unique_regions = unique_document_regions(supplemental_regions, excluding: all_preferred_regions)
        return if unique_regions.empty?

        emit_nonpreferred_document_postlude_regions(
          unique_regions,
          analysis: supplemental_analysis,
          fallback_node: supplemental_nodes.last,
          emitted_preferred_regions: preferred_regions.any?
        )
      end

      def emit_nonpreferred_document_postlude?
        return !@remove_template_missing_nodes if default_preference == :template

        @add_template_only_nodes
      end

      def emit_nonpreferred_document_postlude_regions(regions, analysis:, fallback_node:, emitted_preferred_regions:)
        if emitted_preferred_regions
          @emitter.emit_blank_line
        else
          last_content_line = effective_end_line(fallback_node, analysis)
          first_region = regions.first
          if last_content_line && first_region.respond_to?(:start_line) && first_region.start_line
            emit_interstitial_blank_lines(last_content_line + 1, first_region.start_line - 1, analysis)
          end
        end

        previous_end_line = nil
        regions.each do |region|
          if previous_end_line && region.respond_to?(:start_line) && region.start_line
            emit_interstitial_blank_lines(previous_end_line + 1, region.start_line - 1, analysis)
          end

          @emitter.emit_comment_region(region, source_lines: analysis.lines)
          previous_end_line = region.end_line if region.respond_to?(:end_line)
        end
      end

      def unique_document_regions(regions, excluding: [])
        seen = {}
        Array(excluding).each do |region|
          key = document_region_key(region)
          seen[key] = true if key
        end

        Array(regions).each_with_object([]) do |region, unique|
          key = document_region_key(region)
          next if key && seen[key]

          seen[key] = true if key
          unique << region
        end
      end

      def document_region_key(region)
        return unless region

        # Use only normalized_content for the deduplication key.
        # Excluding :kind is intentional: the same trailing comment block can be
        # classified as :postlude in one source and :orphan in the other depending
        # on whether the last YAML node's reported end_line covers the comment
        # lines (e.g. a multi-line mapping vs a compact one-liner). Including
        # :kind in the key would cause identical content to be emitted twice.
        region.normalized_content.to_s
      end

      def emit_preferred_node(template_node, dest_node, next_template_node: nil, next_dest_node: nil)
        provisional_winner = preference_for_pair(template_node, dest_node)
        record_unresolved_choice(template_node: template_node, dest_node: dest_node,
                                 provisional_winner: provisional_winner)
        if provisional_winner == :destination
          emit_node(
            dest_node,
            @dest_analysis,
            next_node: next_dest_node,
            comment_source_node: template_comment_fallback_source(template_node),
            comment_analysis: @template_analysis,
            comment_source_fallback: template_comment_fallback?
          )
        else
          trim_overpreserved_destination_gap_for(
            template_node,
            dest_node,
            comment_source_node: dest_node,
            comment_analysis: @dest_analysis
          )
          emit_node(
            template_node,
            @template_analysis,
            next_node: next_template_node,
            comment_source_node: dest_node,
            comment_analysis: @dest_analysis
          )
        end
      end

      def trim_overpreserved_destination_gap_for(template_node, dest_node, comment_source_node: nil,
                                                 comment_analysis: @template_analysis)
        preferred_gap_line_count = if preserve_destination_leading_gap_for?(comment_source_node, comment_analysis)
                                     preferred_leading_gap_line_count_for(
                                       template_node,
                                       comment_source_node,
                                       analysis: @template_analysis,
                                       comment_analysis: comment_analysis
                                     )
                                   else
                                     leading_gap_line_count_for(template_node, @template_analysis)
                                   end
        excess_blank_lines = leading_gap_line_count_for(dest_node, @dest_analysis) - preferred_gap_line_count
        return unless excess_blank_lines.positive?

        while excess_blank_lines.positive? && @emitter.lines.last == ''
          @emitter.lines.pop
          excess_blank_lines -= 1
        end
      end

      def preferred_leading_gap_line_count_for(node, comment_source_node = nil, analysis:, comment_analysis:)
        leading_region = preferred_leading_comment_region(
          node,
          comment_source_node,
          analysis: analysis,
          comment_analysis: comment_analysis
        )

        if leading_region && !leading_region.empty? && leading_region.respond_to?(:start_line) && leading_region.start_line
          source_analysis = resolved_comment_analysis(analysis, comment_source_node, comment_analysis, leading_region)
          source_node = resolved_comment_node(node, comment_source_node, leading_region)
          leading_region = canonical_leading_comment_region(leading_region, source_analysis: source_analysis,
                                                                            source_node: source_node)
          return fallback_blank_line_count_for(node, analysis) unless leading_region && !leading_region.empty?

          return blank_line_count_before(leading_region.start_line, source_analysis)
        end

        blank_line_count_before(node_content_start_line(node), analysis)
      end

      def preserve_destination_leading_gap_for?(comment_source_node, comment_analysis)
        return false unless comment_source_node && comment_analysis&.respond_to?(:comment_attachment_for)

        attachment = comment_analysis.comment_attachment_for(comment_source_node)
        attachment&.respond_to?(:orphan_regions) && attachment.orphan_regions.any?
      end

      def preference_for_pair(template_node, dest_node)
        return @preference unless @preference.is_a?(Hash)

        typed_template = apply_node_typing(template_node)
        typed_dest = apply_node_typing(dest_node)

        if Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        if Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { default_preference } if merge_type
        end

        default_preference
      end

      def apply_node_typing(node)
        return node unless @node_typing
        return node unless node

        Ast::Merge::NodeTyping.process(node, @node_typing)
      end

      def record_unresolved_choice(template_node:, dest_node:, provisional_winner:)
        return unless unresolved_mode?
        return unless template_node && dest_node

        template_text = resolution_text_for(template_node)
        dest_text = resolution_text_for(dest_node)

        identifier = resolution_identifier(template_node, dest_node)
        node_type = resolution_node_type(dest_node)
        surface_path = resolution_surface_path(node_type, identifier, dest_node)
        record_unresolved_node_choice(
          result: @result,
          template_node: template_node,
          destination_node: dest_node,
          template_text: template_text,
          destination_text: dest_text,
          provisional_winner: provisional_winner,
          case_prefix: 'yaml',
          case_parts: [node_type, identifier],
          surface_path: surface_path,
          metadata: {
            node_type: node_type,
            identifier: identifier,
            review_identity: review_identity_for_unresolved_choice(
              template_text: template_text,
              destination_text: dest_text,
              provisional_winner: provisional_winner,
              surface_path: surface_path,
              node_type: node_type,
              identifier: identifier
            )
          },
          conflict_fields: {
            node_type: node_type,
            identifier: identifier
          }
        )
      end

      def resolution_text_for(node)
        return node.content if node.respond_to?(:content)
        return node.text if node.respond_to?(:text)

        node.to_s
      end

      def resolution_identifier(template_node, dest_node)
        unresolved_identifier_for_nodes(dest_node, template_node, methods: [:key_name])
      end

      def resolution_node_type(node)
        return node.class.name.split('::').last if node.respond_to?(:key_name)
        return node.type if node.respond_to?(:type)

        node.class.name.split('::').last
      end

      def resolution_surface_path(node_type, identifier, node)
        segment = resolution_path_segment_for(node_type, identifier, node)
        unresolved_surface_path_for(segment)
      end

      # Check if two nodes can be merged recursively (both are mappings or sequences)
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node
      # @param dest_node [MappingEntry, NodeWrapper] Destination node
      # @return [Boolean] Whether recursive merge is possible
      def can_merge_recursively?(template_node, dest_node)
        # Both must have nested mapping or sequence values
        return false unless template_node.respond_to?(:mapping?) && dest_node.respond_to?(:mapping?)

        if template_node.mapping? && dest_node.mapping?
          return false if sequence_item_mapping_reorder_requires_whole_item?(template_node, dest_node)
          return false if bare_dash_sequence_item_mapping?(template_node, @template_analysis)
          return false if bare_dash_sequence_item_mapping?(dest_node, @dest_analysis)

          # Empty flow mappings (e.g. `files: {}`) are safe to recurse into:
          # the inline `{}` carries no content to preserve, and template-only
          # child nodes can be added as block entries after the key line.
          !flow_mapping?(template_node) && (!flow_mapping?(dest_node) || empty_flow_mapping?(dest_node))
        elsif template_node.sequence? && dest_node.sequence?
          # Flow sequences (e.g., `key: [val1, val2]`) occupy the same physical
          # line as their key.  Recursing into them would emit the key line via
          # emit_recursive_merge AND then re-emit it via emit_sequence_item,
          # producing a duplicate.  Only recurse when the value spans additional
          # lines beyond the key (block sequence).
          !flow_sequence?(template_node) && !flow_sequence?(dest_node)
        else
          false
        end
      end

      # Detect flow sequences where the value occupies the same line(s) as the key.
      # A flow sequence like `github: [pboling]` has key and value on the same
      # start_line, so emitting the key line separately would duplicate content.
      #
      # @param node [MappingEntry, NodeWrapper] Node to check
      # @return [Boolean] true when the sequence value starts on the same line as the key
      def flow_sequence?(node)
        return false unless node.respond_to?(:key) && node.respond_to?(:value)
        return false unless node.key && node.value

        key_start_line = node.key&.start_line
        value_start_line = node.value&.start_line
        return false unless key_start_line && value_start_line

        key_start_line == value_start_line
      end

      def flow_mapping?(node)
        return false unless node.respond_to?(:key) && node.respond_to?(:value)
        return false unless node.key && node.value
        return false unless node.value.respond_to?(:mapping?) && node.value.mapping?

        key_start_line = node.key&.start_line
        value_start_line = node.value&.start_line
        return false unless key_start_line && value_start_line

        key_start_line == value_start_line
      end

      # True when node is a flow mapping whose value contains no entries (e.g. `key: {}`).
      # Such nodes can be safely converted to block style by recursing into them.
      def empty_flow_mapping?(node)
        return false unless flow_mapping?(node)
        return false unless node.respond_to?(:value) && node.value

        node.value.mapping_entries.empty?
      rescue StandardError
        false
      end

      def sequence_item_mapping_reorder_requires_whole_item?(template_node, dest_node)
        return false unless sequence_item_mapping_node?(template_node)
        return false unless sequence_item_mapping_node?(dest_node)

        template_first_key = first_mapping_key_name(template_node)
        dest_first_key = first_mapping_key_name(dest_node)

        template_first_key && dest_first_key && template_first_key != dest_first_key
      end

      def sequence_item_mapping_node?(node)
        node.respond_to?(:mapping?) && node.mapping? && (!node.respond_to?(:key) || node.key.nil?)
      end

      def bare_dash_sequence_item_mapping?(node, analysis)
        return false unless sequence_item_mapping_node?(node)
        return false unless node.respond_to?(:start_line) && node.start_line
        return false unless analysis.respond_to?(:line_at)

        previous_line_num = node.start_line - 1
        return false if previous_line_num < 1

        previous_line = analysis.line_at(previous_line_num).to_s
        item_line = analysis.line_at(node.start_line).to_s
        return false unless previous_line.match?(/\A\s*-\s*(?:#.*)?\z/)

        previous_indent = previous_line[/\A\s*/].to_s.length
        item_indent = item_line[/\A\s*/].to_s.length
        previous_indent < item_indent
      end

      def first_mapping_key_name(node)
        key_wrapper, = node.mapping_entries.first
        key_wrapper&.value
      end

      # Emit a recursively merged node
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with nested structure
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with nested structure
      # @param depth [Integer] Current recursion depth
      def emit_recursive_merge(template_node, dest_node, depth:, next_template_node: nil, next_dest_node: nil)
        with_resolution_path_segment(dest_node, template_node) do
          # Preserve the destination prelude (leading comments / blank lines) for
          # recursively merged mapping entries, then emit the key line.
          if dest_node.respond_to?(:key) && dest_node.key
            # For empty flow mappings (e.g. `files: {}`), the dest key line includes
            # the inline `{}`.  Emitting it as-is and then adding block children
            # would produce invalid YAML.  Fall through to the template key line
            # so children are emitted as proper block entries.
            if preference_for_pair(template_node, dest_node) == :destination && !empty_flow_mapping?(dest_node)
              emit_mapping_entry_prelude(
                dest_node,
                @dest_analysis,
                comment_source_node: template_comment_fallback_source(template_node),
                comment_analysis: @template_analysis,
                comment_source_fallback: template_comment_fallback?
              )
              emit_mapping_entry_key_line(
                dest_node,
                @dest_analysis,
                comment_source_node: template_comment_fallback_source(template_node),
                comment_analysis: @template_analysis
              )
            else
              emit_mapping_entry_prelude(
                template_node,
                @template_analysis,
                comment_source_node: dest_node,
                comment_analysis: @dest_analysis
              )
              emit_mapping_entry_key_line(
                template_node,
                @template_analysis,
                comment_source_node: dest_node,
                comment_analysis: @dest_analysis
              )
            end
          end

          if template_node.mapping? && dest_node.mapping?
            emit_recursive_mapping_merge(
              template_node,
              dest_node,
              depth: depth,
              next_template_node: next_template_node,
              next_dest_node: next_dest_node
            )
          elsif template_node.sequence? && dest_node.sequence?
            emit_recursive_sequence_merge(
              template_node,
              dest_node,
              depth: depth,
              next_template_node: next_template_node,
              next_dest_node: next_dest_node
            )
          end
        end
      end

      def resolution_path_segment_for(node_type, identifier, node)
        unresolved_typed_path_segment(node_type, identifier: identifier, node: node, fallback: node_type)
      end

      def with_resolution_path_segment(*nodes, &block)
        with_first_unresolved_path_segment(
          *nodes,
          segment_builder: lambda { |node|
            resolution_path_segment_for(resolution_node_type(node), resolution_identifier(node, node), node)
          }, &block
        )
      end

      # Recursively merge two mapping values
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with mapping value
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with mapping value
      # @param depth [Integer] Current recursion depth
      def emit_recursive_mapping_merge(template_node, dest_node, depth:, next_template_node: nil, next_dest_node: nil)
        # Get the mapping node:
        # - MappingEntry has .value which is a NodeWrapper wrapping the mapping
        # - NodeWrapper that IS a mapping should be used directly
        template_value = if template_node.respond_to?(:value) && template_node.value&.mapping?
                           template_node.value
                         elsif template_node.mapping?
                           template_node
                         end

        return unless template_value

        dest_value = if dest_node.respond_to?(:value) && dest_node.value&.mapping?
                       dest_node.value
                     elsif dest_node.mapping?
                       dest_node
                     end

        return unless dest_value

        # Get nested entries from both
        template_entries = template_value.mapping_entries(comment_tracker: @template_analysis.comment_tracker)
        dest_entries = dest_value.mapping_entries(comment_tracker: @dest_analysis.comment_tracker)

        # Convert to MappingEntry objects for consistent handling
        template_nested = template_entries.map do |key_wrapper, value_wrapper|
          MappingEntry.new(
            key: key_wrapper,
            value: value_wrapper,
            lines: @template_analysis.lines,
            comment_tracker: @template_analysis.comment_tracker
          )
        end

        dest_nested = dest_entries.map do |key_wrapper, value_wrapper|
          MappingEntry.new(
            key: key_wrapper,
            value: value_wrapper,
            lines: @dest_analysis.lines,
            comment_tracker: @dest_analysis.comment_tracker
          )
        end

        # Build signature maps for nested entries
        nested_template_by_sig = {}
        template_nested.each_with_index do |entry, idx|
          sig = [:mapping_entry, entry.key_name]
          nested_template_by_sig[sig] ||= []
          nested_template_by_sig[sig] << { node: entry, index: idx }
        end

        # Recursively merge nested entries
        merge_nodes_to_emitter(
          template_nested,
          dest_nested,
          nested_template_by_sig,
          depth: depth + 1,
          template_fallback_next_node: next_template_node,
          dest_fallback_next_node: next_dest_node
        )
      end

      # Recursively merge two sequence values (arrays)
      # Uses union semantics: keeps all destination items, adds template-only items
      #
      # @param template_node [MappingEntry, NodeWrapper] Template node with sequence value
      # @param dest_node [MappingEntry, NodeWrapper] Destination node with sequence value
      # @param depth [Integer] Current recursion depth
      def emit_recursive_sequence_merge(template_node, dest_node, depth:, next_template_node: nil, next_dest_node: nil)
        # Get the sequence node:
        # - MappingEntry has .value which is a NodeWrapper wrapping the sequence
        # - NodeWrapper that IS a sequence should be used directly
        template_value = if template_node.respond_to?(:value) && template_node.value&.sequence?
                           template_node.value
                         elsif template_node.sequence?
                           template_node
                         end

        dest_value = if dest_node.respond_to?(:value) && dest_node.value&.sequence?
                       dest_node.value
                     elsif dest_node.sequence?
                       dest_node
                     end

        return unless template_value && dest_value

        template_items = template_value.sequence_items(comment_tracker: @template_analysis.comment_tracker)
        dest_items = dest_value.sequence_items(comment_tracker: @dest_analysis.comment_tracker)
        template_items_by_key = build_sequence_item_match_map(template_items, @template_analysis)
        next_template_by_id = build_next_node_lookup(template_items, fallback_next_node: next_template_node)
        next_dest_by_id = build_next_node_lookup(dest_items, fallback_next_node: next_dest_node)

        sequence_matches = build_sequence_item_matches(template_items, dest_items)
        consumed_template_indices = ::Set.new
        prev_dest_end_line = nil

        # Pre-compute position-aware trailing groups for template-only sequence items.
        # Controlled by @add_template_only_sequence_items, which defaults to
        # @add_template_only_nodes but can be set independently to false to prevent
        # template items from being appended to user-controlled dest sequences.
        if @add_template_only_sequence_items
          matched_template_indices_from_seq = ::Set.new(sequence_matches.values.map { |info| info[:index] })
          seq_trailing_groups, seq_all_matched_indices = build_trailing_groups(
            template_nodes: template_items,
            matched_predicate: ->(_item, idx) { matched_template_indices_from_seq.include?(idx) },
            entry_builder: ->(item, idx) { { item: item, node: item, index: idx } }
          )
        else
          seq_trailing_groups = {}
          seq_all_matched_indices = ::Set.new
        end

        # Emit template-only items that precede the first matched template item
        emit_prefix_trailing_group(seq_trailing_groups, consumed_template_indices) do |info|
          emit_sequence_item(info[:item], @template_analysis, next_node: next_template_by_id[info[:item].object_id])
        end

        dest_items.each_with_index do |item, dest_idx|
          removing_destination_only_item = @remove_template_missing_nodes && !sequence_matches.key?(dest_idx)
          skipped_redundant_duplicate = false

          if prev_dest_end_line && !removing_destination_only_item
            effective_start = effective_start_line(item, @dest_analysis)
            if effective_start
              emit_interstitial_blank_lines(prev_dest_end_line + 1, effective_start - 1,
                                            @dest_analysis)
            end
          end

          template_info = sequence_matches[dest_idx]
          next_dest_node = next_dest_by_id[item.object_id]
          emitted_recursively = false

          if template_info
            template_item = template_info[:item]

            if should_recurse?(depth) && can_merge_recursively?(template_item, item)
              emitted_recursively = true
              emit_recursive_merge(
                template_item,
                item,
                depth: depth,
                next_template_node: next_template_by_id[template_item.object_id],
                next_dest_node: next_dest_node
              )
            elsif preference_for_pair(template_item, item) == :destination
              emit_sequence_item(
                item,
                @dest_analysis,
                next_node: next_dest_node,
                comment_source_node: template_comment_fallback_source(template_item),
                comment_analysis: @template_analysis,
                comment_source_fallback: template_comment_fallback?
              )
            else
              emit_sequence_item(
                template_item,
                @template_analysis,
                next_node: next_template_by_id[template_item.object_id],
                comment_source_node: item,
                comment_analysis: @dest_analysis
              )
            end

            consumed_template_indices << template_info[:index]
          elsif @remove_template_missing_nodes
            emitted_recursively = should_recurse?(depth) && (item.mapping? || item.sequence?)
            emit_removed_sequence_item_comments(item, @dest_analysis, depth: depth)
          elsif redundant_destination_sequence_duplicate?(item, template_items_by_key)
            if handle_suspected_corruption(
              kind: :duplicate_destination_sequence_item,
              message: 'destination sequence item duplicates semantic content already present in the preferred template sequence',
              context: duplicate_destination_context(item, @dest_analysis)
            )
              skipped_redundant_duplicate = true
            else
              emit_sequence_item(item, @dest_analysis, next_node: next_dest_node)
            end
          else
            emit_sequence_item(item, @dest_analysis, next_node: next_dest_node)
          end

          prev_dest_end_line = if removing_destination_only_item || skipped_redundant_duplicate
                                 skipped_destination_node_boundary(next_dest_node, @dest_analysis)
                               elsif emitted_recursively
                                 effective_end_line(item, @dest_analysis, next_node: next_dest_node)
                               else
                                 sequence_item_end_line(item, @dest_analysis, next_node: next_dest_node)
                               end

          # After each dest item, flush any ready trailing groups (deferred approach)
          flush_ready_trailing_groups(
            trailing_groups: seq_trailing_groups,
            matched_indices: seq_all_matched_indices,
            consumed_indices: consumed_template_indices
          ) do |info|
            emit_sequence_item(info[:item], @template_analysis, next_node: next_template_by_id[info[:item].object_id])
          end
        end

        # Safety net: emit any remaining trailing groups
        emit_remaining_trailing_groups(
          trailing_groups: seq_trailing_groups,
          consumed_indices: consumed_template_indices
        ) do |info|
          emit_sequence_item(info[:item], @template_analysis, next_node: next_template_by_id[info[:item].object_id])
        end
      end

      def build_sequence_item_matches(template_items, dest_items)
        matches = {}
        consumed_template_indices = ::Set.new
        consumed_dest_indices = ::Set.new

        # Phase 1: exact semantic matches. This is schema-agnostic and lets us
        # pair items that are logically identical even when formatting differs
        # (for example, scalar quoting/style differences).
        template_items_by_key = build_sequence_item_match_map(template_items, @template_analysis)
        key_cursor = Hash.new(0)

        dest_items.each_with_index do |item, dest_idx|
          match_key = sequence_item_match_key(item, @dest_analysis)
          template_info = next_sequence_item_match(template_items_by_key, match_key, key_cursor,
                                                   consumed_template_indices)
          next unless template_info

          matches[dest_idx] = template_info
          consumed_template_indices << template_info[:index]
          consumed_dest_indices << dest_idx
        end

        refined_matches = build_refined_sequence_observation_matches(
          template_items,
          dest_items,
          consumed_template_indices,
          consumed_dest_indices
        )
        matches.merge!(refined_matches)
      end

      def build_refined_sequence_observation_matches(template_items, dest_items, consumed_template_indices,
                                                     consumed_dest_indices)
        # Phase 2: for composite items that are not semantically identical, infer
        # correspondence from the data actually present in the sibling sequence.
        # We look for the smallest shared set of scalar observations that is
        # unique on both sides, instead of assuming any key name is globally
        # special across all YAML documents.
        template_infos = template_items.each_with_index.filter_map do |item, idx|
          next if consumed_template_indices.include?(idx)

          observations = sequence_item_observations(item, @template_analysis)
          next if observations.empty?

          { item: item, index: idx, observations: observations }
        end
        dest_infos = dest_items.each_with_index.filter_map do |item, idx|
          next if consumed_dest_indices.include?(idx)

          observations = sequence_item_observations(item, @dest_analysis)
          next if observations.empty?

          { item: item, index: idx, observations: observations }
        end

        return {} if template_infos.empty? || dest_infos.empty?

        candidates = dest_infos.filter_map do |dest_info|
          template_infos.filter_map do |template_info|
            shared_observations = template_info[:observations] & dest_info[:observations]
            next if shared_observations.empty?

            discriminator = unique_shared_observation_subset(
              shared_observations,
              template_info,
              template_infos,
              dest_info,
              dest_infos
            )
            next unless discriminator

            {
              dest_index: dest_info[:index],
              template_index: template_info[:index],
              item: template_info[:item],
              shared_count: shared_observations.length,
              discriminator_size: discriminator.length
            }
          end
        end.flatten

        return {} if candidates.empty?

        consumed_template_candidate_indices = ::Set.new
        consumed_dest_candidate_indices = ::Set.new

        candidates.sort_by do |candidate|
          [
            -candidate[:shared_count],
            candidate[:discriminator_size],
            (candidate[:dest_index] - candidate[:template_index]).abs,
            candidate[:dest_index],
            candidate[:template_index]
          ]
        end.each_with_object({}) do |candidate, matches|
          next if consumed_dest_candidate_indices.include?(candidate[:dest_index])
          next if consumed_template_candidate_indices.include?(candidate[:template_index])

          matches[candidate[:dest_index]] = {
            item: candidate[:item],
            index: candidate[:template_index]
          }
          consumed_dest_candidate_indices << candidate[:dest_index]
          consumed_template_candidate_indices << candidate[:template_index]
        end
      end

      def unique_shared_observation_subset(shared_observations, template_info, template_infos, dest_info, dest_infos)
        ranked_observations = rank_sequence_mapping_observations(shared_observations, template_infos, dest_infos)

        (1..ranked_observations.length).each do |subset_size|
          ranked_observations.combination(subset_size) do |subset|
            next unless uniquely_identified_by_observations?(subset, template_info, template_infos)
            next unless uniquely_identified_by_observations?(subset, dest_info, dest_infos)

            return subset
          end
        end

        nil
      end

      def uniquely_identified_by_observations?(subset, target_info, infos)
        matches = infos.select do |info|
          subset.all? { |observation| info[:observations].include?(observation) }
        end

        matches.one? && matches.first[:index] == target_info[:index]
      end

      def rank_sequence_mapping_observations(shared_observations, template_infos, dest_infos)
        occurrence_counts = Hash.new(0)

        (template_infos + dest_infos).each do |info|
          info[:observations].each { |observation| occurrence_counts[observation] += 1 }
        end

        shared_observations.sort_by do |path, value|
          [occurrence_counts[[path, value]], path.length, path.join('.'), value.to_s]
        end
      end

      # Emit a single sequence item
      #
      # @param item [NodeWrapper] Sequence item to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_sequence_item(item, analysis, next_node: nil, comment_source_node: nil, comment_analysis: analysis,
                             comment_source_fallback: false)
        return unless item.start_line && item.end_line

        emit_node_prelude(
          item,
          analysis,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
          comment_source_fallback: comment_source_fallback
        )

        lines = trimmed_sequence_item_lines(item, analysis, next_node: next_node)
        return if lines.empty?

        emit_node_first_line(lines.shift, item, analysis, comment_source_node: comment_source_node,
                                                          comment_analysis: comment_analysis)
        @emitter.emit_raw_lines(lines) if lines.any?
        emit_node_trailing_comments(item, analysis, next_node: next_node)
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper, MappingEntry] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis, next_node: nil, comment_source_node: nil, comment_analysis: analysis,
                    comment_source_fallback: false)
        return if freeze_node?(node)

        if node.is_a?(MappingEntry)
          emit_mapping_entry(
            node,
            analysis,
            next_node: next_node,
            comment_source_node: comment_source_node,
            comment_analysis: comment_analysis,
            comment_source_fallback: comment_source_fallback
          )
          return
        end

        emit_node_prelude(
          node,
          analysis,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
          comment_source_fallback: comment_source_fallback
        )

        # Emit the node content
        return unless node.respond_to?(:start_line) && node.respond_to?(:end_line)
        # Regular node - emit its lines
        return unless node.start_line && node.end_line

        end_line = effective_end_line(node, analysis, next_node: next_node)
        lines = []
        (node.start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line
        end
        return if lines.empty?

        emit_node_first_line(lines.shift, node, analysis, comment_source_node: comment_source_node,
                                                          comment_analysis: comment_analysis)
        @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, node.start_line + 1)) if lines.any?
        emit_node_trailing_comments(node, analysis, next_node: next_node)
      end

      # Emit a mapping entry
      # @param entry [MappingEntry] The mapping entry
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_mapping_entry(entry, analysis, next_node: nil, comment_source_node: nil, comment_analysis: analysis,
                             comment_source_fallback: false)
        return unless entry.respond_to?(:start_line) && entry.respond_to?(:end_line)

        emit_mapping_entry_prelude(
          entry,
          analysis,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis,
          comment_source_fallback: comment_source_fallback
        )

        content_start_line = mapping_entry_content_start_line(entry)
        end_line = effective_end_line(entry, analysis, next_node: next_node)
        return unless content_start_line && end_line
        return if end_line < content_start_line

        if entry.respond_to?(:key) && entry.key&.start_line == content_start_line
          emit_mapping_entry_key_line(entry, analysis, comment_source_node: comment_source_node,
                                                       comment_analysis: comment_analysis)
          content_start_line += 1
        end

        if content_start_line > end_line
          emit_node_trailing_comments(entry, analysis, next_node: next_node)
          return
        end

        lines = []
        (content_start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line
        end
        @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, content_start_line)) if lines.any?
        emit_node_trailing_comments(entry, analysis, next_node: next_node)
      end

      # Emit a freeze block
      # @param freeze_node [FreezeNode] Freeze block to emit
      def emit_freeze_block(freeze_node)
        @emitter.emit_raw_lines(freeze_node.lines,
                                metadata: emitter_block_metadata(@dest_analysis, freeze_node.start_line))
      end

      def emit_mapping_entry_prelude(entry, analysis, comment_source_node: nil, comment_analysis: analysis,
                                     comment_source_fallback: false)
        content_start_line = mapping_entry_content_start_line(entry)
        return unless content_start_line

        leading_region = preferred_leading_comment_region(
          entry,
          comment_source_node,
          analysis: analysis,
          comment_analysis: comment_analysis,
          source_fallback: comment_source_fallback
        )
        if leading_region && !leading_region.empty?
          source_analysis = resolved_comment_analysis(analysis, comment_source_node, comment_analysis, leading_region)
          source_node = resolved_comment_node(entry, comment_source_node, leading_region)
          leading_region = canonical_leading_comment_region(leading_region, source_analysis: source_analysis,
                                                                            source_node: source_node)
          return if leading_region.nil? || leading_region.empty?

          source_content_start_line = node_content_start_line(source_node)

          remember_emitted_leading_comment_region(leading_region)
          @emitter.emit_comment_region(leading_region, source_lines: source_analysis&.lines)
          if source_analysis && source_content_start_line
            emit_interstitial_blank_lines(
              (leading_region.end_line || source_content_start_line) + 1,
              source_content_start_line - 1,
              source_analysis
            )
          end
          return
        end

        return unless entry.respond_to?(:start_line) && entry.start_line
        return if entry.start_line >= content_start_line

        lines = []
        (entry.start_line...content_start_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line
        end
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def emit_node_prelude(node, analysis, comment_source_node: nil, comment_analysis: analysis,
                            comment_source_fallback: false)
        content_start_line = node_content_start_line(node)
        return unless content_start_line

        leading_region = preferred_leading_comment_region(
          node,
          comment_source_node,
          analysis: analysis,
          comment_analysis: comment_analysis,
          source_fallback: comment_source_fallback
        )
        return unless leading_region && !leading_region.empty?

        source_analysis = resolved_comment_analysis(analysis, comment_source_node, comment_analysis, leading_region)
        source_node = resolved_comment_node(node, comment_source_node, leading_region)
        leading_region = canonical_leading_comment_region(leading_region, source_analysis: source_analysis,
                                                                          source_node: source_node)
        return if leading_region.nil? || leading_region.empty?

        source_content_start_line = node_content_start_line(source_node)

        remember_emitted_leading_comment_region(leading_region)
        @emitter.emit_comment_region(leading_region, source_lines: source_analysis&.lines)
        if source_analysis && source_content_start_line
          emit_interstitial_blank_lines(
            (leading_region.end_line || source_content_start_line) + 1,
            source_content_start_line - 1,
            source_analysis
          )
        end
        nil
      end

      def emit_mapping_entry_key_line(entry, analysis, comment_source_node: nil, comment_analysis: analysis)
        return unless entry.respond_to?(:key) && entry.key&.start_line

        key_line = analysis.line_at(entry.key.start_line)
        return unless key_line

        emit_node_first_line(key_line, entry, analysis, comment_source_node: comment_source_node,
                                                        comment_analysis: comment_analysis)
      end

      def emit_node_first_line(line, node, analysis, comment_source_node: nil, comment_analysis: analysis)
        inline_region = preferred_inline_comment_region(
          node,
          comment_source_node,
          analysis: analysis,
          comment_analysis: comment_analysis
        )
        unless inline_region && !inline_region.empty?
          @emitter.emit_raw_lines([line],
                                  metadata: emitter_line_metadata(analysis, line_number: node_content_start_line(node)))
          return
        end

        existing_inline_region = node_inline_comment_region(node, analysis)
        if existing_inline_region && !existing_inline_region.empty?
          line = strip_inline_comment_from_line(line,
                                                existing_inline_region)
        end

        @emitter.emit_raw_lines([line],
                                metadata: emitter_line_metadata(analysis, line_number: node_content_start_line(node)))
        @emitter.emit_comment_region(
          inline_region,
          inline: true,
          source_lines: resolved_comment_analysis(analysis, comment_source_node, comment_analysis,
                                                  inline_region)&.lines
        )
      end

      def emit_removed_destination_node_comments(node, analysis, next_node: nil)
        before_count = @emitter.lines.length
        leading_region = node_leading_comment_region(node, analysis)
        content_start_line = node_content_start_line(node)
        if leading_region && !leading_region.empty?
          @emitter.emit_comment_region(leading_region, source_lines: analysis.lines)
          if content_start_line
            emit_interstitial_blank_lines((leading_region.end_line || content_start_line) + 1, content_start_line - 1,
                                          analysis)
          end
        end

        emit_removed_destination_node_inline_comments(node, analysis)
        return if @emitter.lines.length <= before_count

        effective_end_line(node, analysis, next_node: next_node) || content_start_line
      end

      def emit_removed_destination_node_inline_comments(node, analysis)
        inline_region = node_inline_comment_region(node, analysis)
        return unless inline_region && !inline_region.empty?

        @emitter.emit_raw_lines(
          promoted_inline_comment_lines(inline_region, node, analysis),
          metadata: emitter_block_metadata(analysis, node_content_start_line(node))
        )
      end

      def emit_removed_sequence_item_comments(item, analysis, depth:)
        if should_recurse?(depth) && item.mapping?
          emit_removed_sequence_mapping_item_comments(item, analysis, depth: depth)
        elsif should_recurse?(depth) && item.sequence?
          emit_removed_nested_sequence_item_comments(item, analysis, depth: depth)
        else
          emit_removed_destination_node_comments(item, analysis)
        end
      end

      def emit_removed_sequence_mapping_item_comments(item, analysis, depth:)
        nested_entries = item.mapping_entries(comment_tracker: analysis.comment_tracker).map do |key_wrapper, value_wrapper|
          MappingEntry.new(
            key: key_wrapper,
            value: value_wrapper,
            lines: analysis.lines,
            comment_tracker: analysis.comment_tracker
          )
        end

        merge_nodes_to_emitter([], nested_entries, {}, depth: depth + 1)
      end

      def build_sequence_item_match_map(items, analysis)
        items.each_with_index.with_object({}) do |(item, idx), map|
          match_key = sequence_item_match_key(item, analysis)
          map[match_key] ||= []
          map[match_key] << { item: item, index: idx }
        end
      end

      def next_sequence_item_match(items_by_key, match_key, key_cursor, consumed_template_indices)
        candidates = items_by_key[match_key]
        return unless candidates

        cursor = key_cursor[match_key]
        template_info = nil

        while cursor < candidates.size
          candidate = candidates[cursor]
          unless consumed_template_indices.include?(candidate[:index])
            template_info = candidate
            break
          end
          cursor += 1
        end

        key_cursor[match_key] = cursor + 1 if template_info
        template_info
      end

      def redundant_destination_sequence_duplicate?(item, template_items_by_key)
        match_key = sequence_item_match_key(item, @dest_analysis)
        candidates = template_items_by_key[match_key]
        return false unless candidates&.any?

        true
      end

      def sequence_item_match_key(item, analysis)
        return [:scalar, item.value] if item.scalar?
        return [:alias, item.alias_anchor] if item.alias?

        semantic_identity = sequence_item_semantic_identity(item, analysis)
        return semantic_identity if semantic_identity

        [:fingerprint, sequence_item_fingerprint(item, analysis)]
      end

      def sequence_item_semantic_identity(item, analysis)
        canonical = canonical_sequence_item_value(item, analysis)
        canonical ? [:semantic, canonical] : nil
      end

      def canonical_sequence_item_value(item, analysis)
        # Canonicalize sequence items structurally so equality is based on YAML
        # content, not source formatting. Mapping entry order is normalized here
        # because YAML mappings are semantic key/value collections even when the
        # source file preserves a presentation order.
        return [:scalar, item.node.tag, item.value] if item.scalar?
        return [:alias, item.alias_anchor] if item.alias?

        if item.mapping?
          entries = item.mapping_entries(comment_tracker: analysis.comment_tracker).map do |key_wrapper, value_wrapper|
            [key_wrapper&.value, canonical_sequence_item_value(value_wrapper, analysis)]
          end

          return [:mapping, entries.sort_by { |key, value| [key.to_s, value.inspect] }]
        end

        if item.sequence?
          items = item.sequence_items(comment_tracker: analysis.comment_tracker).map do |child|
            canonical_sequence_item_value(child, analysis)
          end

          return [:sequence, items]
        end

        nil
      end

      def sequence_item_observations(item, analysis, path = [])
        return ::Set[[path, item.value]] if item.scalar?
        return ::Set[[path, item.alias_anchor]] if item.alias?

        if item.mapping?
          return item.mapping_entries(comment_tracker: analysis.comment_tracker).each_with_object(::Set.new) do |(key_wrapper, value_wrapper), observations|
            next unless key_wrapper&.value

            child_path = path + [key_wrapper.value]
            observations.merge(sequence_item_observations(value_wrapper, analysis, child_path)) if value_wrapper
          end
        end

        if item.sequence?
          return item.sequence_items(comment_tracker: analysis.comment_tracker).each_with_object(::Set.new).with_index do |(child, observations), idx|
            observations.merge(sequence_item_observations(child, analysis, path + [idx]))
          end
        end

        ::Set.new
      end

      def emit_removed_nested_sequence_item_comments(item, analysis, depth:)
        nested_items = item.sequence_items(comment_tracker: analysis.comment_tracker)
        merge_nodes_to_emitter([], nested_items, {}, depth: depth + 1)
      end

      def sequence_item_fingerprint(item, analysis)
        return [:scalar, item.value] if item.scalar?
        return [:fallback, item.content] unless item.respond_to?(:start_line) && item.respond_to?(:end_line)
        return [:fallback, item.content] unless item.start_line && item.end_line

        [:raw_lines, trimmed_sequence_item_lines(item, analysis)]
      end

      def trimmed_sequence_item_lines(item, analysis, next_node: nil)
        end_line = sequence_item_end_line(item, analysis, next_node: next_node)
        start_line = sequence_item_start_line(item, analysis)
        lines = (start_line..end_line).map { |line_num| analysis.line_at(line_num) }.compact
        return lines if lines.empty?

        first_content_line = lines.find { |line| !line.strip.empty? }
        return lines unless first_content_line

        base_indent = first_content_line[/\A\s*/].to_s.length
        cutoff_index = lines.index do |line|
          next false if line.strip.empty?

          indent = line[/\A\s*/].to_s.length
          indent < base_indent
        end

        trimmed_lines = cutoff_index ? lines.take(cutoff_index) : lines
        trimmed_lines.pop while next_node.nil? && trimmed_lines.any? && trimmed_lines.last.strip.empty?
        trimmed_lines
      end

      def sequence_item_start_line(item, analysis)
        return item.start_line unless item.respond_to?(:start_line) && item.start_line
        return item.start_line unless analysis.respond_to?(:line_at)

        previous_line_num = item.start_line - 1
        return item.start_line if previous_line_num < 1

        previous_line = analysis.line_at(previous_line_num).to_s
        item_line = analysis.line_at(item.start_line).to_s
        return item.start_line unless previous_line.match?(/\A\s*-\s*(?:#.*)?\z/)

        previous_indent = previous_line[/\A\s*/].to_s.length
        item_indent = item_line[/\A\s*/].to_s.length
        previous_indent < item_indent ? previous_line_num : item.start_line
      end

      def sequence_item_end_line(item, analysis, next_node: nil)
        return item.end_line unless next_node

        next_start_line = effective_start_line(next_node, analysis)
        return item.end_line unless next_start_line

        boundary = next_start_line - 1
        if analysis.respond_to?(:comment_tracker)
          boundary -= 1 while boundary >= 1 && analysis.comment_tracker.blank_line?(boundary)
        end

        item.end_line.clamp(..[boundary, item.start_line].max)
      end

      def build_next_node_lookup(nodes, fallback_next_node: nil)
        lookup = {}

        nodes.each_with_index do |node, idx|
          lookup[node.object_id] = nodes[idx + 1] || fallback_next_node
        end

        lookup
      end

      def effective_end_line(node, analysis, next_node: nil)
        return unless node.respond_to?(:end_line) && node.end_line

        end_line = node.end_line
        return end_line unless next_node&.respond_to?(:start_line) && next_node.start_line

        next_effective_start = effective_start_line(next_node, analysis)
        boundary = (next_effective_start || next_node.start_line) - 1
        if analysis.respond_to?(:comment_tracker)
          boundary -= 1 while boundary >= 1 && analysis.comment_tracker.blank_line?(boundary)
        end

        [boundary, node_content_start_line(node)].max.clamp(..end_line)
      end

      def preferred_emitted_end_line(node, effective_end_line)
        return effective_end_line if effective_end_line
        return node.end_line if node.respond_to?(:end_line) && node.end_line

        nil
      end

      def skipped_destination_node_boundary(next_node, analysis)
        next_effective_start = effective_start_line(next_node, analysis)
        next_effective_start ? next_effective_start - 1 : nil
      end

      def emit_trailing_lines_after_last_node(node, analysis)
        return unless node

        after_line = effective_end_line(node, analysis)
        return unless after_line && analysis.respond_to?(:lines)
        return if after_line >= analysis.lines.length

        lines = ((after_line + 1)..analysis.lines.length).map { |line_num| analysis.line_at(line_num) }.compact
        @emitter.emit_raw_lines(lines) if lines.any?
      end

      # Check whether a comment region's content already appears in the
      # emitter's output. Used to prevent duplication when a raw-block
      # emission (with Psych's inflated end_line) already included the
      # trailing comment lines.
      #
      # @param region [Comment::Region] Region to check
      # @param analysis [FileAnalysis] Source analysis for line content
      # @return [Boolean] true when the region's text already appears in emitter output
      def region_already_emitted?(region, _analysis)
        return false unless region.respond_to?(:nodes) && region.nodes&.any?

        # Build the expected lines from the region's source
        region_lines = region.nodes.filter_map do |node|
          if node.respond_to?(:slice)
            node.slice.to_s.chomp
          elsif node.respond_to?(:text)
            node.text.to_s.chomp
          end
        end
        return false if region_lines.empty?

        emitted = @emitter.lines
        return false if emitted.size < region_lines.size

        # Check if the region lines appear as a contiguous block anywhere
        # in the tail portion of the emitter output. We check the last
        # (region_lines.size * 3) lines to account for interstitial blanks.
        search_window = [region_lines.size * 3, emitted.size].min
        tail = emitted.last(search_window)

        # Look for the first region line in the tail, then verify the rest follow
        region_lines.size.times do |offset|
          start_idx = tail.size - region_lines.size - offset
          next if start_idx.negative?

          match = true
          region_lines.each_with_index do |expected, i|
            unless tail[start_idx + i] == expected
              match = false
              break
            end
          end
          return true if match
        end

        false
      end

      def emit_document_postlude(analysis, fallback_node: nil)
        augmenter = document_comment_augmenter_for(analysis)
        return if fallback_node.nil?

        regions = document_trailing_regions_for(augmenter, analysis, fallback_node)
        had_document_trailing_regions = regions.any?
        last_node_leading_region = node_leading_comment_region(fallback_node, analysis)
        last_node_trailing_region = node_trailing_comment_region(fallback_node, analysis)
        regions = regions.reject { |region| same_comment_content?(region, last_node_leading_region) }
        regions = regions.reject { |region| same_comment_content?(region, last_node_trailing_region) }
        regions = regions.reject { |region| emitted_leading_comment_region?(region) }

        if regions.empty?
          unless had_document_trailing_regions || last_node_trailing_region
            emit_trailing_lines_after_last_node(fallback_node,
                                                analysis)
          end
          return
        end

        last_content_line = effective_end_line(fallback_node, analysis)
        # Use the deflated line so interstitial blank-line emission covers
        # the gap between the last YAML content and the first trailing
        # comment region (Psych inflates end_line to EOF).
        previous_end_line = deflated_content_end_line(last_content_line, analysis)

        # Even when the last document node was recursively merged, nested raw-line
        # emission can still already include trailing orphan regions. Always
        # filter against the current emitter tail before appending document
        # trailing regions.
        emittable_regions = regions.reject { |region| region_already_emitted?(region, analysis) }

        return if emittable_regions.empty?

        emittable_regions.each do |region|
          if previous_end_line && region.respond_to?(:start_line) && region.start_line
            emit_interstitial_blank_lines(previous_end_line + 1, region.start_line - 1, analysis)
          end

          @emitter.emit_comment_region(region, source_lines: analysis.lines)
          previous_end_line = region.end_line if region.respond_to?(:end_line)
        end
      end

      def emit_document_prelude(analysis, nodes: [])
        augmenter = document_comment_augmenter_for(analysis)
        return unless augmenter

        normalized_nodes = Array(nodes)
        regions = document_leading_regions_for(augmenter, normalized_nodes, analysis)

        previous_end_line = nil
        regions.each do |region|
          if previous_end_line && region.respond_to?(:start_line) && region.start_line
            emit_interstitial_blank_lines(previous_end_line + 1, region.start_line - 1, analysis)
          end

          remember_emitted_leading_comment_region(region)
          @emitter.emit_comment_region(region, source_lines: analysis.lines)
          previous_end_line = region.end_line if region.respond_to?(:end_line)
        end

        return if regions.empty?

        last_region_end = regions.last.end_line
        if normalized_nodes.any?
          first_node_start = effective_start_line(normalized_nodes.first, analysis)
          if last_region_end && first_node_start
            emit_interstitial_blank_lines(last_region_end + 1, first_node_start - 1,
                                          analysis)
          end
        elsif last_region_end
          emit_interstitial_blank_lines(last_region_end + 1, analysis.lines.length, analysis)
        end
      end

      def remember_emitted_leading_comment_region(region)
        normalized = region.normalized_content
        return if normalized.nil? || normalized.empty?

        (@emitted_leading_comment_texts ||= ::Set.new).add(normalized)
      end

      def emitted_leading_comment_region?(region)
        normalized = region&.normalized_content
        return false if normalized.nil? || normalized.empty?

        (@emitted_leading_comment_texts ||= ::Set.new).include?(normalized)
      end

      def document_comment_augmenter_for(analysis)
        @document_comment_augmenters ||= {}
        @document_comment_augmenters[analysis.object_id] ||= analysis.comment_augmenter
      end

      def document_leading_regions_for(augmenter, nodes, analysis)
        regions = []
        preamble = canonical_document_preamble_region(augmenter&.preamble_region, analysis)
        regions << preamble if preamble && !preamble.empty?

        first_node_start = (effective_start_line(nodes.first, analysis) if nodes.any?)

        Array(augmenter&.orphan_regions).each do |region|
          next unless region && !region.empty?
          if first_node_start && region.respond_to?(:end_line) && region.end_line && region.end_line >= first_node_start
            next
          end

          regions << region
        end

        regions.sort_by { |region| region.start_line || 0 }
      end

      def canonical_document_preamble_region(region, analysis)
        return region unless region && !region.empty?
        return region unless analysis.equal?(@dest_analysis)

        template_region = document_comment_augmenter_for(@template_analysis)&.preamble_region
        return region unless template_region && !template_region.empty?

        collapse_template_preamble_prefix_region(region, template_region)
      end

      def canonical_leading_comment_region(region, source_analysis:, source_node:)
        return region unless region && !region.empty?
        return region unless source_analysis.equal?(@dest_analysis)
        return region unless source_node
        unless source_analysis.respond_to?(:statements) && Array(source_analysis.statements).first.equal?(source_node)
          return region
        end

        template_region = document_comment_augmenter_for(@template_analysis)&.preamble_region
        return region unless template_region && !template_region.empty?

        collapse_template_preamble_prefix_region(region, template_region)
      end

      def collapse_template_preamble_prefix_region(region, template_region)
        template_nodes = Array(template_region.nodes)
        region_nodes = Array(region.nodes)
        return region if template_nodes.empty? || region_nodes.length < template_nodes.length

        repeat_count = leading_repeat_count(region_nodes, template_nodes) do |left, right|
          left.respond_to?(:normalized_content) && right.respond_to?(:normalized_content) &&
            left.normalized_content == right.normalized_content
        end
        remainder_nodes = region_nodes.drop(repeat_count * template_nodes.length)
        if @preference == :template && repeat_count == 1 && remainder_nodes.empty?
          return empty_comment_region_like(region)
        end
        return region if repeat_count < 2
        return region if remainder_nodes.empty?

        should_heal = handle_suspected_corruption(
          kind: :duplicate_template_preamble_prefix,
          message: 'document preamble begins with duplicated template-owned YAML preamble comments',
          context: {
            repeated_nodes: repeat_count * template_nodes.length,
            remaining_nodes: remainder_nodes.length
          }
        )
        return region unless should_heal

        ::Ast::Merge::Comment::Region.new(
          kind: region.kind,
          nodes: remainder_nodes,
          metadata: region.metadata
        )
      end

      def duplicated_template_preamble_prefix_in_first_node_leading_region?(analysis, nodes)
        return false unless analysis.equal?(@dest_analysis)

        region = first_node_leading_comment_region(nodes, analysis)
        return false unless region && !region.empty?

        template_region = document_comment_augmenter_for(@template_analysis)&.preamble_region
        return false unless template_region && !template_region.empty?

        template_nodes = Array(template_region.nodes)
        region_nodes = Array(region.nodes)
        return false if template_nodes.empty? || region_nodes.length < template_nodes.length * 2

        repeat_count = leading_repeat_count(region_nodes, template_nodes) do |left, right|
          left.respond_to?(:normalized_content) && right.respond_to?(:normalized_content) &&
            left.normalized_content == right.normalized_content
        end

        repeat_count >= 2 && region_nodes.drop(repeat_count * template_nodes.length).any?
      end

      def first_node_leading_comment_region(nodes, analysis)
        first_node = Array(nodes).first
        return unless first_node

        region = node_leading_comment_region(first_node, analysis)
        return unless region && !region.empty?

        region
      end

      def leading_repeat_count(lines, prefix, &comparator)
        return 0 if prefix.empty? || lines.length < prefix.length

        comparator ||= ->(left, right) { left == right }

        count = 0
        count += 1 while prefix_match?(lines.drop(count * prefix.length).first(prefix.length), prefix, comparator)
        count
      end

      def prefix_match?(candidate, prefix, comparator)
        return false unless candidate && candidate.length == prefix.length

        candidate.zip(prefix).all? { |left, right| comparator.call(left, right) }
      end

      def empty_comment_region_like(region)
        ::Ast::Merge::Comment::Region.new(
          kind: region.kind,
          nodes: [],
          metadata: region.metadata
        )
      end

      def document_trailing_regions_for(augmenter, analysis, fallback_node)
        last_content_line = effective_end_line(fallback_node, analysis)
        # Psych reports the last node's end_line as the end of the document,
        # which can include trailing comment lines. Scan backward to find the
        # actual last YAML-content line so orphan comment regions inside the
        # inflated range are not filtered out.
        last_yaml_line = deflated_content_end_line(last_content_line, analysis)
        regions = Array(augmenter&.orphan_regions).select do |region|
          next false unless region && !region.empty?
          next true unless last_yaml_line

          region.respond_to?(:start_line) && region.start_line && region.start_line > last_yaml_line
        end

        postlude = augmenter&.postlude_region
        regions << postlude if postlude && !postlude.empty?
        regions.sort_by { |region| region.start_line || 0 }
      end

      # Walk backward from +end_line+ to find the last line that contains
      # actual YAML content (not a full-line comment or blank line).
      # Returns the original +end_line+ when no comment tracker is available
      # or when no deflation is needed.
      def deflated_content_end_line(end_line, analysis)
        return end_line unless end_line
        return end_line unless analysis.respond_to?(:comment_tracker)

        tracker = analysis.comment_tracker
        return end_line unless tracker

        line = end_line
        while line >= 1
          break unless tracker.blank_line?(line) || tracker.full_line_comment?(line)

          line -= 1
        end

        line >= 1 ? line : end_line
      end

      def node_content_start_line(node)
        if node.respond_to?(:key) && node.key&.start_line
          node.key.start_line
        elsif node.respond_to?(:start_line) && node.start_line
          node.start_line
        else
          1
        end
      end

      def effective_start_line(node, analysis)
        return unless node

        leading_region = node_leading_comment_region(node, analysis)
        return leading_region&.start_line if leading_region&.start_line

        node.start_line if node.respond_to?(:start_line) && node.start_line
      end

      def leading_gap_line_count_for(node, analysis)
        return 0 unless node && analysis

        anchor_line = if (leading_region = node_leading_comment_region(node,
                                                                       analysis)) && leading_region.respond_to?(:start_line) && leading_region.start_line
                        leading_region.start_line
                      elsif node.respond_to?(:start_line) && node.start_line
                        node.start_line
                      end
        return 0 unless anchor_line

        blank_line_count_before(anchor_line, analysis)
      end

      def blank_line_count_before(line_num, analysis)
        count = 0
        current = line_num - 1

        while current >= 1
          line = analysis.line_at(current)
          break unless line && line.strip.empty?

          count += 1
          current -= 1
        end

        count
      end

      def mapping_entry_content_start_line(entry)
        return entry.key.start_line if entry.respond_to?(:key) && entry.key&.start_line
        return entry.start_line if entry.respond_to?(:start_line)

        nil
      end

      def redundant_destination_duplicate?(dest_node, template_candidates)
        return false unless template_candidates&.any?

        dest_identity = node_semantic_identity(dest_node, @dest_analysis)
        return false unless dest_identity

        template_candidates.any? do |candidate|
          node_semantic_identity(candidate[:node], @template_analysis) == dest_identity
        end
      end

      def duplicate_destination_context(node, analysis)
        {
          file: analysis.respond_to?(:path) ? analysis.path : nil,
          owner_type: node&.respond_to?(:type) ? node.type : node.class.name.split('::').last,
          semantic_identity: node_semantic_identity(node, analysis),
          line_range: [node&.start_line, node&.end_line].compact
        }.compact
      end

      def handle_suspected_corruption(kind:, message:, context:)
        ::Ast::Merge::Healer.handle(
          mode: corruption_handling,
          kind: kind,
          message: message,
          prefix: '[psych-merge]',
          error_class: Psych::Merge::CorruptionDetectedError,
          warner: ->(formatted) { DebugLogger.debug_warning(formatted, context) }
        )
      end

      def node_semantic_identity(node, analysis)
        if node.is_a?(MappingEntry)
          return [:mapping_entry, node.key_name, canonical_sequence_item_value(node.value, analysis)]
        end

        canonical_sequence_item_value(node, analysis) if node.is_a?(NodeWrapper)
      end

      def resolved_comment_attachment(node, analysis = nil)
        return unless node

        return node.comment_attachment if node.respond_to?(:comment_attachment)
        return unless analysis&.respond_to?(:comment_attachment_for)

        analysis.comment_attachment_for(node, line_num: node_content_start_line(node))
      end

      def node_leading_comment_region(node, analysis = nil)
        attachment = resolved_comment_attachment(node, analysis)
        return attachment.leading_region if attachment&.respond_to?(:leading_region)
        return unless node.respond_to?(:leading_comment_region)

        node.leading_comment_region
      end

      def node_inline_comment_region(node, analysis = nil)
        attachment = resolved_comment_attachment(node, analysis)
        return attachment.inline_region if attachment&.respond_to?(:inline_region)
        return unless node.respond_to?(:inline_comment_region)

        node.inline_comment_region
      end

      def node_trailing_comment_region(node, analysis = nil)
        attachment = resolved_comment_attachment(node, analysis)
        return attachment.trailing_region if attachment&.respond_to?(:trailing_region)

        nil
      end

      def preferred_leading_comment_region(node, comment_source_node = nil, analysis: nil, comment_analysis: analysis,
                                           source_fallback: false)
        if source_fallback
          node_region = node_leading_comment_region(node, analysis)
          return node_region if node_region && !node_region.empty?

          source_region = node_leading_comment_region(comment_source_node, comment_analysis) if comment_source_node
          return source_region if source_region && !source_region.empty?

          return node_region
        end

        source_region = node_leading_comment_region(comment_source_node, comment_analysis) if comment_source_node
        return source_region if source_region && !source_region.empty?

        node_leading_comment_region(node, analysis)
      end

      def template_comment_fallback?
        @comment_merge_policy == :template_fallback_when_missing
      end

      def template_comment_fallback_source(node)
        template_comment_fallback? ? node : nil
      end

      def normalize_comment_merge_policy(policy)
        normalized = policy.to_s.strip.downcase.tr('-', '_').to_sym
        case normalized
        when :preserve_destination, :destination, :git_merge
          :preserve_destination
        when :template_fallback, :template_fallback_when_missing, :template_documentation
          :template_fallback_when_missing
        else
          raise ArgumentError, "unknown YAML comment_merge_policy: #{policy}"
        end
      end

      def preferred_inline_comment_region(node, comment_source_node = nil, analysis: nil, comment_analysis: analysis)
        node_region = node_inline_comment_region(node, analysis)
        return node_region if node_region && !node_region.empty?

        source_region = node_inline_comment_region(comment_source_node, comment_analysis) if comment_source_node
        return source_region if source_region && !source_region.empty?

        node_region
      end

      def resolved_comment_analysis(default_analysis, comment_source_node, comment_analysis, region)
        return default_analysis unless comment_source_node && comment_analysis

        source_leading = node_leading_comment_region(comment_source_node, comment_analysis)
        source_inline = node_inline_comment_region(comment_source_node, comment_analysis)
        source_trailing = node_trailing_comment_region(comment_source_node, comment_analysis)
        if source_leading.equal?(region) || source_inline.equal?(region) || source_trailing.equal?(region)
          return comment_analysis
        end

        default_analysis
      end

      def resolved_comment_node(default_node, comment_source_node, region)
        return default_node unless comment_source_node

        source_leading = node_leading_comment_region(comment_source_node)
        source_inline = node_inline_comment_region(comment_source_node)
        source_trailing = node_trailing_comment_region(comment_source_node)
        if source_leading.equal?(region) || source_inline.equal?(region) || source_trailing.equal?(region)
          return comment_source_node
        end

        default_node
      end

      def emit_node_trailing_comments(node, analysis, next_node: nil)
        trailing_region = node_trailing_comment_region(node, analysis)
        return unless trailing_region && !trailing_region.empty?
        return if duplicated_by_next_leading_region?(trailing_region, next_node, analysis)
        return if region_already_emitted?(trailing_region, analysis)

        @emitter.emit_comment_region(trailing_region, source_lines: analysis.lines)
      end

      def duplicated_by_next_leading_region?(trailing_region, next_node, analysis)
        return false unless next_node

        next_leading_region = node_leading_comment_region(next_node, analysis)
        return false unless next_leading_region && !next_leading_region.empty?

        same_comment_region?(trailing_region, next_leading_region)
      end

      def same_comment_region?(left, right)
        comment_region_key(left) == comment_region_key(right)
      end

      def same_comment_content?(left, right)
        return false unless left && right

        left.normalized_content.to_s == right.normalized_content.to_s
      end

      def comment_region_key(region)
        return unless region

        [
          (region.start_line if region.respond_to?(:start_line)),
          (region.end_line if region.respond_to?(:end_line)),
          region.normalized_content.to_s
        ]
      end

      def emit_interstitial_blank_lines(start_line, end_line, analysis)
        return unless analysis
        return unless start_line && end_line && start_line <= end_line

        lines = []
        (start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line && line.strip.empty?
        end
        @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, start_line)) if lines.any?
      end

      def promoted_inline_comment_lines(inline_region, node, analysis)
        base_indent = analysis.line_at(node_content_start_line(node)).to_s[/\A\s*/].to_s

        inline_region.nodes.map do |comment_node|
          content = if comment_node.respond_to?(:normalized_content)
                      comment_node.normalized_content.to_s
                    else
                      comment_node.to_s.sub(/\A\s*#\s?/, '')
                    end

          line = +base_indent
          line << '#'
          line << " #{content}" unless content.empty?
          line
        end
      end

      def strip_inline_comment_from_line(line, inline_region)
        tracked_hash = inline_region.metadata[:tracked_hashes]&.first
        indent = tracked_hash && (tracked_hash[:indent] || tracked_hash['indent'])

        stripped = if indent
                     line[0...indent].to_s.rstrip
                   else
                     line.sub(/\s+#.*\z/, '')
                   end

        stripped.empty? ? line : stripped
      end
    end
  end
end
