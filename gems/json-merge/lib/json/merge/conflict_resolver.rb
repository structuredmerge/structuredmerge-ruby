# frozen_string_literal: true

module Json
  module Merge
    # Resolves conflicts between template and destination JSON content
    # using structural signatures and configurable preferences.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    class ConflictResolver < Ast::Merge::ConflictResolverBase
      include Ast::Merge::CommentLayoutEmissionSupport
      include Ast::Merge::StructuredEmitterProvenanceSupport

      class MissingSharedInlineRegionError < Json::Merge::Error; end

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
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type preferences
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false,
                     remove_template_missing_nodes: false, resolution_mode: :eager, corruption_handling: :heal, match_refiner: nil, node_typing: nil, merge_arrays: true, preserve_atomic_formatting: false, **options)
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
          match_refiner: match_refiner,
          **options
        )
        @resolution_mode = resolution_mode
        @corruption_handling = ::Ast::Merge::Healer.normalize_mode(corruption_handling)
        @node_typing = node_typing
        @merge_arrays = merge_arrays
        @preserve_atomic_formatting = preserve_atomic_formatting
        @emitter = Emitter.new
      end

      protected

      # Resolve conflicts and populate the result using tree-based merging
      #
      # @param result [MergeResult] Result object to populate
      def resolve_batch(result)
        DebugLogger.time('ConflictResolver#resolve') do
          @result = result
          template_statements = @template_analysis.statements
          dest_statements = @dest_analysis.statements

          # Clear emitter for fresh merge
          @emitter.clear
          @emitted_leading_comment_texts = ::Set.new

          emit_document_prelude(@dest_analysis, nodes: dest_statements)

          # Merge root-level statements via emitter
          merge_node_lists_to_emitter(
            template_statements,
            dest_statements,
            @template_analysis,
            @dest_analysis
          )

          emit_document_postlude(@dest_analysis, fallback_node: dest_statements.last)

          # Transfer emitter output to result
          transfer_emitter_output(result)

          DebugLogger.debug('Conflict resolution complete', {
                              template_statements: template_statements.size,
                              dest_statements: dest_statements.size,
                              result_lines: result.line_count
                            })
        end
      end

      public

      def freeze_node?(node)
        return false unless node
        return node.freeze_node? if node.respond_to?(:freeze_node?)

        node.is_a?(FreezeNode)
      end

      private

      # Recursively merge two lists of nodes, emitting to emitter
      # @param template_nodes [Array<NodeWrapper>] Template nodes
      # @param dest_nodes [Array<NodeWrapper>] Destination nodes
      # @param template_analysis [FileAnalysis] Template analysis for line access
      # @param dest_analysis [FileAnalysis] Destination analysis for line access
      def merge_node_lists_to_emitter(template_nodes, dest_nodes, template_analysis, dest_analysis)
        # Build signature maps for matching
        template_by_sig = build_signature_map(template_nodes, template_analysis)
        dest_by_sig = build_signature_map(dest_nodes, dest_analysis)

        # Build refined matches for nodes that don't match by signature
        refined_matches = build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        refined_dest_to_template = refined_matches.invert

        # Track consumed individual node indices (not just signatures) so that
        # multiple nodes sharing the same signature are matched 1:1 in order
        # rather than collapsed into a single match.
        consumed_template_indices = ::Set.new
        sig_cursor = Hash.new(0)

        # Pre-compute position-aware trailing groups for template-only nodes.
        dest_sigs = ::Set.new
        dest_nodes.each do |n|
          sig = dest_analysis.generate_signature(n)
          dest_sigs << sig if sig
        end
        refined_template_ids = ::Set.new(refined_matches.keys.map(&:object_id))

        trailing_groups, all_matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: template_nodes,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { template_analysis.generate_signature(node) },
          refined_template_ids: refined_template_ids,
          add_template_only_nodes: @add_template_only_nodes
        )

        # Emit template-only nodes that precede the first matched template node.
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          next if freeze_node?(info[:node])

          emit_atomic_node(info[:node], template_analysis)
        end

        # First pass: Process destination nodes
        dest_nodes.each do |dest_node|
          dest_sig = dest_analysis.generate_signature(dest_node)

          if freeze_node?(dest_node)
            emit_freeze_block(dest_node)
            next
          end

          # Check for signature match
          if dest_sig && template_by_sig[dest_sig]
            emit_retained_gap_before_destination_node(dest_node, dest_analysis, owners: dest_nodes)

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

              # Both have this node - merge them (recursively if containers)
              merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)

              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1
            else
              # All template copies consumed — keep dest copy
              emit_atomic_node(dest_node, dest_analysis)
            end
          elsif refined_dest_to_template.key?(dest_node)
            emit_retained_gap_before_destination_node(dest_node, dest_analysis, owners: dest_nodes)

            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = template_analysis.generate_signature(template_node)

            # Find and consume the matching template index
            if template_sig && template_by_sig[template_sig]
              template_by_sig[template_sig].each do |info|
                unless consumed_template_indices.include?(info[:index])
                  consumed_template_indices << info[:index]
                  break
                end
              end
            end

            # Merge matched nodes
            merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
          elsif @remove_template_missing_nodes
            emit_removed_destination_node_comments(dest_node, dest_analysis)
          else
            # Destination-only node - always keep
            emit_retained_gap_before_destination_node(dest_node, dest_analysis, owners: dest_nodes)
            emit_atomic_node(dest_node, dest_analysis)
          end

          # Flush interior trailing groups (between two matches) that are ready
          flush_ready_trailing_groups(
            trailing_groups: trailing_groups,
            matched_indices: all_matched_indices,
            consumed_indices: consumed_template_indices
          ) do |info|
            next if freeze_node?(info[:node])

            emit_atomic_node(info[:node], template_analysis)
          end
        end

        # Emit remaining trailing groups (tail groups after last match + safety net)
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices
        ) do |info|
          next if freeze_node?(info[:node])

          emit_atomic_node(info[:node], template_analysis)
        end
      end

      def trailing_group_node_matched?(node, _signature)
        freeze_node?(node)
      end

      # Merge two matched nodes - for containers, recursively merge children
      # Emits to emitter instead of result
      # @param template_node [NodeWrapper] Template node
      # @param dest_node [NodeWrapper] Destination node
      # @param template_analysis [FileAnalysis] Template analysis
      # @param dest_analysis [FileAnalysis] Destination analysis
      def merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
        if dest_node.container? && template_node.container?
          # Both are containers - recursively merge their children
          merge_container_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
        elsif dest_node.pair? && template_node.pair?
          # Both are pairs - check if their values are OBJECTS (not arrays) that need recursive merge
          template_value = template_node.value_node
          dest_value = dest_node.value_node

          # Only recursively merge if BOTH values are objects.
          # Arrays are file-owned atoms unless a caller explicitly changes the
          # preference; their element order and formatting must survive.
          if recursively_merge_pair_values?(template_value, dest_value)
            key_name = dest_node.key_name || template_node.key_name
            comment_source_node, comment_source_analysis = preferred_comment_source(
              dest_node,
              dest_analysis,
              fallback_node: template_node,
              fallback_analysis: template_analysis
            )
            comment_attachment = shared_line_comment_attachment_for(comment_source_node, comment_source_analysis)
            inline_source_node, inline_source_analysis, inline_attachment = preferred_available_inline_attachment(
              template_node,
              template_analysis,
              dest_node,
              dest_analysis
            )

            emit_preferred_leading_comments_for(comment_source_node, comment_source_analysis,
                                                shared_attachment: comment_attachment)
            trailing_source_node, trailing_source_analysis = preferred_container_comment_source(
              dest_value,
              dest_analysis,
              fallback_node: template_value,
              fallback_analysis: template_analysis
            )
            compact_source_node = trailing_source_node || dest_value || template_value

            with_resolution_path_segment(dest_node, template_node) do
              if compact_empty_container?(template_value, compact_source_node, trailing_source_analysis)
                emit_with_preferred_inline_comment(inline_source_node, inline_source_analysis,
                                                   shared_attachment: inline_attachment) do |inline_text|
                  @emitter.emit_pair(key_name, compact_container_literal_for(template_value),
                                     inline_comment: inline_text)
                end
              elsif template_value.object?
                emit_with_preferred_inline_comment(inline_source_node, inline_source_analysis,
                                                   shared_attachment: inline_attachment) do |inline_text|
                  @emitter.emit_nested_object_start(key_name, inline_comment: inline_text)
                end
              elsif template_value.array?
                emit_with_preferred_inline_comment(inline_source_node, inline_source_analysis,
                                                   shared_attachment: inline_attachment) do |inline_text|
                  @emitter.emit_array_start(key_name, inline_comment: inline_text)
                end
              end

              unless compact_empty_container?(template_value, compact_source_node, trailing_source_analysis)
                merge_node_lists_to_emitter(
                  template_value.mergeable_children,
                  dest_value.mergeable_children,
                  template_analysis,
                  dest_analysis
                )

                emit_container_trailing_lines(trailing_source_node, trailing_source_analysis)

                if template_value.object?
                  @emitter.emit_nested_object_end
                elsif template_value.array?
                  @emitter.emit_array_end
                end
              end
            end
          elsif preference_for_pair(template_node, dest_node) == :destination
            # Values are not both objects, or one/both are arrays - use preference and emit
            # Arrays are always replaced, not merged
            record_unresolved_choice(
              template_node: template_node,
              dest_node: dest_node,
              match_kind: :pair_value
            )
            emit_atomic_node(dest_node, dest_analysis)
          else
            record_unresolved_choice(
              template_node: template_node,
              dest_node: dest_node,
              match_kind: :pair_value
            )
            emit_atomic_node(
              template_node,
              template_analysis,
              comment_source_node: dest_node,
              comment_analysis: dest_analysis
            )
          end
        elsif preference_for_pair(template_node, dest_node) == :destination
          # Leaf nodes or mismatched types - use preference
          record_unresolved_choice(
            template_node: template_node,
            dest_node: dest_node,
            match_kind: :node_value
          )
          emit_atomic_node(dest_node, dest_analysis)
        else
          record_unresolved_choice(
            template_node: template_node,
            dest_node: dest_node,
            match_kind: :node_value
          )
          emit_atomic_node(
            template_node,
            template_analysis,
            comment_source_node: dest_node,
            comment_analysis: dest_analysis
          )
        end
      end

      def emit_retained_gap_before_destination_node(dest_node, dest_analysis, owners: nil)
        gap_lines = retained_owner_leading_gap_lines_for(dest_node, dest_analysis, owners: owners)
        return if gap_lines.empty?
        return if @emitter.blank_lines?(gap_lines) && @emitter.ends_with_blank_line?

        gap = retained_owner_leading_gap_for(dest_node, dest_analysis, owners: owners)
        @emitter.emit_raw_lines(gap_lines, metadata: emitter_block_metadata(dest_analysis, gap.start_line))
      end

      # Merge container nodes by emitting via emitter
      # @param template_node [NodeWrapper] Template container node
      # @param dest_node [NodeWrapper] Destination container node
      # @param template_analysis [FileAnalysis] Template analysis
      # @param dest_analysis [FileAnalysis] Destination analysis
      def merge_container_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
        if dest_node.object?
          @emitter.emit_object_start
        elsif dest_node.array?
          @emitter.emit_array_start
        end

        merge_node_lists_to_emitter(
          template_node.mergeable_children,
          dest_node.mergeable_children,
          template_analysis,
          dest_analysis
        )

        trailing_source_node, trailing_source_analysis = preferred_container_comment_source(
          dest_node,
          dest_analysis,
          fallback_node: template_node,
          fallback_analysis: template_analysis
        )
        emit_container_trailing_lines(trailing_source_node, trailing_source_analysis)

        if dest_node.object?
          @emitter.emit_object_end
        elsif dest_node.array?
          @emitter.emit_array_end
        end
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

      def record_unresolved_choice(template_node:, dest_node:, match_kind:)
        return unless unresolved_mode?
        return unless template_node && dest_node

        template_text = node_resolution_text(template_node)
        dest_text = node_resolution_text(dest_node)
        return if template_text == dest_text

        provisional_winner = preference_for_pair(template_node, dest_node) == :template ? :template : :destination
        key_name = resolution_key_name(template_node, dest_node)
        surface_path = resolution_surface_path(template_node, dest_node)
        metadata = {
          match_kind: match_kind,
          node_type: dest_node.respond_to?(:type) ? dest_node.type : nil,
          key_name: key_name,
          review_identity: review_identity_for_unresolved_choice(
            template_text: template_text,
            destination_text: dest_text,
            provisional_winner: provisional_winner,
            surface_path: surface_path,
            match_kind: match_kind,
            key_name: key_name
          )
        }.compact

        record_unresolved_node_choice(
          result: @result,
          template_node: template_node,
          destination_node: dest_node,
          template_text: template_text,
          destination_text: dest_text,
          provisional_winner: provisional_winner,
          case_prefix: 'json',
          case_parts: [match_kind, metadata[:key_name]],
          surface_path: surface_path,
          metadata: metadata,
          conflict_fields: {
            match_kind: match_kind,
            key_name: metadata[:key_name]
          }
        )
      end

      def node_resolution_text(node)
        return unless node.respond_to?(:text)

        node.text
      end

      def resolution_key_name(template_node, dest_node)
        unresolved_identifier_for_nodes(dest_node, template_node, methods: [:key_name])
      end

      def resolution_surface_path(template_node, dest_node)
        segment = resolution_path_segment_for(template_node, dest_node)
        line = dest_node.respond_to?(:start_line) ? dest_node.start_line : nil
        unresolved_surface_path_for(segment, fallback_segment: (line ? "line[#{line}]" : nil))
      end

      def resolution_path_segment_for(template_node, dest_node)
        key_name = resolution_key_name(template_node, dest_node)
        return "pair[#{key_name.inspect}]" if key_name

        nil
      end

      def with_resolution_path_segment(*nodes, &block)
        with_first_unresolved_path_segment(*nodes, segment_builder: lambda { |node|
          resolution_path_segment_for(node, node)
        }, &block)
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        return if freeze_node?(node)

        source_node = comment_source_node || node
        source_analysis = comment_source_node ? comment_analysis : analysis
        source_attachment = shared_line_comment_attachment_for(source_node, source_analysis)
        _inline_source_node, _inline_source_analysis, inline_attachment =
          preferred_available_inline_attachment(
            node,
            analysis,
            comment_source_node,
            source_analysis,
            preferred_node: node,
            preferred_analysis: analysis
          )

        emit_preferred_leading_comments_for(source_node, source_analysis, shared_attachment: source_attachment)

        if node.pair?
          # Emit as pair
          key = node.key_name
          value_node = node.value_node
          source_value_node = source_node.respond_to?(:value_node) ? source_node.value_node : nil

          if value_node
            # Check if value is an object (not array) and needs recursive emission
            if value_node.container?
              container_comment_source = source_value_node || value_node

              if compact_empty_container?(value_node, container_comment_source, source_analysis)
                emit_with_preferred_inline_comment(node, analysis,
                                                   shared_attachment: inline_attachment) do |inline_text|
                  if key
                    @emitter.emit_pair(
                      key,
                      compact_container_literal_for(value_node),
                      inline_comment: inline_text,
                      metadata: emitter_line_metadata(analysis, line_number: node.start_line)
                    )
                  end
                end
              elsif value_node.object?
                emit_with_preferred_inline_comment(node, analysis,
                                                   shared_attachment: inline_attachment) do |inline_text|
                  @emitter.emit_nested_object_start(
                    key,
                    inline_comment: inline_text,
                    metadata: emitter_line_metadata(analysis, line_number: node.start_line)
                  )
                end
              elsif value_node.array?
                emit_with_preferred_inline_comment(node, analysis,
                                                   shared_attachment: inline_attachment) do |inline_text|
                  @emitter.emit_array_start(
                    key,
                    inline_comment: inline_text,
                    metadata: emitter_line_metadata(analysis, line_number: node.start_line)
                  )
                end
              end

              unless compact_empty_container?(value_node, container_comment_source, source_analysis)
                value_node.mergeable_children.each do |child|
                  emit_node(child, analysis)
                end

                emit_container_trailing_lines(container_comment_source, source_analysis)

                if value_node.object?
                  @emitter.emit_nested_object_end(metadata: emitter_line_metadata(analysis, line_number: node.end_line))
                elsif value_node.array?
                  @emitter.emit_array_end(metadata: emitter_line_metadata(analysis, line_number: node.end_line))
                end
              end
            else
              emit_with_preferred_inline_comment(node, analysis, shared_attachment: inline_attachment) do |inline_text|
                if key
                  @emitter.emit_pair(
                    key,
                    value_node.text,
                    inline_comment: inline_text,
                    metadata: emitter_line_metadata(analysis, line_number: node.start_line)
                  )
                end
              end
            end
          end
        elsif node.container?
          if node.object?
            @emitter.emit_object_start(metadata: emitter_line_metadata(analysis, line_number: node.start_line))
          elsif node.array?
            @emitter.emit_array_start(metadata: emitter_line_metadata(analysis, line_number: node.start_line))
          end

          node.mergeable_children.each do |child|
            emit_node(child, analysis)
          end

          emit_container_trailing_lines(source_node, source_analysis)

          if node.object?
            @emitter.emit_object_end(metadata: emitter_line_metadata(analysis, line_number: node.end_line))
          elsif node.array?
            @emitter.emit_array_end(metadata: emitter_line_metadata(analysis, line_number: node.end_line))
          end
        elsif node.start_line && node.end_line
          if node.start_line == node.end_line
            emit_with_preferred_inline_comment(node, analysis, shared_attachment: inline_attachment) do |inline_text|
              @emitter.emit_array_element(
                node.text,
                inline_comment: inline_text,
                metadata: emitter_line_metadata(analysis, line_number: node.start_line)
              )
            end
          else
            lines = []
            (node.start_line..node.end_line).each do |ln|
              line = analysis.line_at(ln)
              lines << line if line
            end
            @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, node.start_line))
          end
        end
      end

      def emit_atomic_node(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        return if freeze_node?(node)
        unless @preserve_atomic_formatting
          return emit_node(node, analysis, comment_source_node: comment_source_node,
                                           comment_analysis: comment_analysis)
        end
        unless node.respond_to?(:text)
          return emit_node(node, analysis, comment_source_node: comment_source_node,
                                           comment_analysis: comment_analysis)
        end

        source_node = comment_source_node || node
        source_analysis = comment_source_node ? comment_analysis : analysis
        source_attachment = shared_line_comment_attachment_for(source_node, source_analysis)
        inline_attachment = shared_inline_comment_attachment_for(source_node, source_analysis)

        emit_preferred_leading_comments_for(source_node, source_analysis, shared_attachment: source_attachment)
        emit_with_preferred_inline_comment(node, analysis, shared_attachment: inline_attachment) do |inline_text|
          fragment = reindented_source_fragment(node, analysis)
          fragment = "#{fragment} // #{inline_text}" if inline_text && !inline_text.empty?
          @emitter.emit_raw_fragment(
            fragment,
            metadata: emitter_block_metadata(analysis, node.start_line)
          )
        end
      end

      def reindented_source_fragment(node, analysis)
        fragment = node.text.to_s
        source_line = node.respond_to?(:start_line) && node.start_line ? analysis.line_at(node.start_line).to_s : ''
        source_indent = leading_indent(source_line)
        return fragment if source_indent.empty?

        fragment.lines(chomp: true).map do |line|
          line.start_with?(source_indent) ? line.delete_prefix(source_indent) : line
        end.join("\n")
      end

      def leading_indent(line)
        indent = +''
        line.each_char do |char|
          break unless [' ', "\t"].include?(char)

          indent << char
        end
        indent
      end

      def recursively_merge_pair_values?(template_value, dest_value)
        return true if template_value&.object? && dest_value&.object?
        return true if @merge_arrays && template_value&.array? && dest_value&.array?

        false
      end

      def preferred_comment_source(node, analysis, fallback_node: nil, fallback_analysis: nil)
        return [node, analysis] if node_has_emittable_leading_comments?(node, analysis)
        return [fallback_node, fallback_analysis] if fallback_node && node_has_emittable_leading_comments?(
          fallback_node, fallback_analysis
        )

        [node, analysis]
      end

      def preferred_available_inline_attachment(template_node, template_analysis, dest_node, dest_analysis,
                                                preferred_node: nil, preferred_analysis: nil)
        if preferred_node && preferred_analysis
          primary_node = preferred_node
          primary_analysis = preferred_analysis
          fallback_node = preferred_node.equal?(template_node) && preferred_analysis.equal?(template_analysis) ? dest_node : template_node
          fallback_analysis = fallback_node.equal?(dest_node) ? dest_analysis : template_analysis
        elsif preference_for_pair(template_node, dest_node) == :destination
          primary_node = dest_node
          primary_analysis = dest_analysis
          fallback_node = template_node
          fallback_analysis = template_analysis
        else
          primary_node = template_node
          primary_analysis = template_analysis
          fallback_node = dest_node
          fallback_analysis = dest_analysis
        end

        primary_attachment = shared_inline_comment_attachment_for(primary_node, primary_analysis)
        if primary_attachment&.inline_region && !primary_attachment.inline_region.empty?
          return [primary_node, primary_analysis,
                  primary_attachment]
        end

        fallback_attachment = shared_inline_comment_attachment_for(fallback_node, fallback_analysis)
        if fallback_attachment&.inline_region && !fallback_attachment.inline_region.empty?
          return [fallback_node, fallback_analysis,
                  fallback_attachment]
        end

        [primary_node, primary_analysis, nil]
      end

      def preferred_container_comment_source(node, analysis, fallback_node: nil, fallback_analysis: nil)
        return [node, analysis] if container_has_trailing_comments?(node, analysis)
        return [fallback_node, fallback_analysis] if fallback_node && container_has_trailing_comments?(fallback_node,
                                                                                                       fallback_analysis)

        [node, analysis]
      end

      def node_has_emittable_leading_comments?(node, analysis)
        return false unless node.respond_to?(:start_line) && node.start_line

        analysis.comment_tracker.leading_comments_before(node.start_line).any?
      end

      def emit_preferred_leading_comments_for(node, analysis, shared_attachment: nil)
        attachment = shared_attachment || shared_line_comment_attachment_for(node, analysis)
        region = canonical_leading_comment_region(attachment&.leading_region, analysis: analysis, node: node)

        unless region && !region.empty?
          emit_leading_comments_for(node, analysis)
          return
        end

        # Bidirectional dedup: skip this region if an identical comment block
        # was already emitted by a preceding node (from either source).
        normalized = region.normalized_content
        if normalized && !normalized.empty? && @emitted_leading_comment_texts&.include?(normalized)
          should_heal = handle_suspected_corruption(
            kind: :comment_ownership_overlap,
            message: 'leading comment region overlaps previously emitted JSON comment ownership',
            context: dedup_warning_context(region: region, analysis: analysis, node: node)
          )
          if should_heal
            emit_blank_lines_in_range((region.end_line || node.start_line).to_i + 1, node.start_line.to_i - 1, analysis)
            return
          end
        end
        @emitted_leading_comment_texts&.add(normalized) if normalized && !normalized.empty?

        emit_blank_lines_before_leading_comments(region.start_line, analysis)
        if attachment&.leading_region.equal?(region)
          @emitter.emit_comment_attachment(attachment, leading: true, inline: false, source_lines: analysis.lines)
        else
          @emitter.emit_comment_region(region, source_lines: analysis.lines)
        end
        emit_blank_lines_in_range((region.end_line || node.start_line).to_i + 1, node.start_line.to_i - 1, analysis)
      end

      def emit_leading_comments_for(node, analysis)
        return unless node.respond_to?(:start_line) && node.start_line

        leading = analysis.comment_tracker.leading_comments_before(node.start_line)
        leading = canonical_tracked_leading_comments(leading, analysis: analysis, node: node)
        return if leading.empty?

        # Bidirectional dedup: build normalized text from tracked comments
        # and skip if already emitted by a preceding node.
        normalized = leading.map { |c| c[:text].to_s.strip }.join("\n")
        if @emitted_leading_comment_texts&.include?(normalized)
          should_heal = handle_suspected_corruption(
            kind: :comment_ownership_overlap,
            message: 'tracked leading comments overlap previously emitted JSON comment ownership',
            context: dedup_warning_context(
              region: nil,
              analysis: analysis,
              node: node,
              normalized_content: normalized,
              region_lines: [leading.first[:line], comment_end_line(leading.last)]
            )
          )
          if should_heal
            emit_blank_lines_in_range(comment_end_line(leading.last) + 1, node.start_line - 1, analysis)
            return
          end
        end
        @emitted_leading_comment_texts&.add(normalized)

        emit_blank_lines_before_leading_comments(leading.first[:line], analysis)
        emit_tracked_comments_with_internal_blank_lines(leading, analysis)

        emit_blank_lines_in_range(comment_end_line(leading.last) + 1, node.start_line - 1, analysis) if leading.any?
      end

      def canonical_leading_comment_region(region, analysis:, node:)
        return region unless region && !region.empty?
        return region unless analysis.equal?(@dest_analysis)
        return region unless first_statement?(node, analysis)

        template_region = first_leading_comment_region(@template_analysis)
        return region unless template_region && !template_region.empty?

        template_nodes = Array(template_region.nodes)
        region_nodes = Array(region.nodes)
        return region if template_nodes.empty? || region_nodes.length < template_nodes.length

        repeat_count = leading_repeat_count(region_nodes, template_nodes) do |left, right|
          normalized_comment_unit(left) == normalized_comment_unit(right)
        end
        return region if repeat_count < 2

        remaining_nodes = region_nodes.drop(repeat_count * template_nodes.length)
        return region if remaining_nodes.empty?

        should_heal = handle_suspected_corruption(
          kind: :duplicate_template_preamble_prefix,
          message: 'leading JSON comment region begins with duplicated template-owned preamble comments',
          context: {
            template_comment_lines: template_nodes.length,
            merged_comment_lines: region_nodes.length,
            destination_specific_comment_lines: remaining_nodes.length
          }
        )
        return region unless should_heal

        ::Ast::Merge::Comment::Region.new(
          kind: region.kind,
          nodes: remaining_nodes,
          metadata: region.metadata
        )
      end

      def canonical_tracked_leading_comments(leading, analysis:, node:)
        return leading unless analysis.equal?(@dest_analysis)
        return leading unless first_statement?(node, analysis)

        template_region = first_leading_comment_region(@template_analysis)
        template_units = Array(template_region&.nodes).map { |comment| normalized_comment_unit(comment) }
        return leading if template_units.empty? || leading.length < template_units.length

        leading_units = leading.map { |comment| normalized_comment_unit(comment) }
        repeat_count = leading_repeat_count(leading_units, template_units)
        return leading if repeat_count < 2

        remaining_comments = leading.drop(repeat_count * template_units.length)
        return leading if remaining_comments.empty?

        should_heal = handle_suspected_corruption(
          kind: :duplicate_template_preamble_prefix,
          message: 'tracked JSON leading comments begin with duplicated template-owned preamble comments',
          context: {
            template_comment_lines: template_units.length,
            merged_comment_lines: leading.length,
            destination_specific_comment_lines: remaining_comments.length
          }
        )
        return leading unless should_heal

        remaining_comments
      end

      def tracked_inline_comment_for(node, analysis)
        return unless node.respond_to?(:start_line) && node.start_line

        analysis.comment_tracker.inline_comment_at(inline_comment_line_for(node))
      end

      def dedup_warning_context(region:, analysis:, node:, normalized_content: nil, region_lines: nil)
        {
          file: analysis.respond_to?(:path) ? analysis.path : nil,
          owner_type: node.respond_to?(:type) ? node.type : node.class.name.split('::').last,
          region_lines: region_lines || [region.respond_to?(:start_line) ? region.start_line : nil,
                                         region.respond_to?(:end_line) ? region.end_line : nil],
          normalized_content: normalized_content || region&.normalized_content
        }.compact
      end

      def handle_suspected_corruption(kind:, message:, context:)
        ::Ast::Merge::Healer.handle(
          mode: corruption_handling,
          kind: kind,
          message: message,
          prefix: '[json-merge]',
          error_class: Json::Merge::CorruptionDetectedError,
          warner: ->(formatted) { DebugLogger.debug_warning(formatted, context) }
        )
      end

      def first_leading_comment_region(analysis)
        first_statement = first_owned_node(analysis)
        return unless first_statement

        shared_line_comment_attachment_for(first_statement, analysis)&.leading_region
      end

      def first_statement?(node, analysis)
        equivalent_owner?(first_owned_node(analysis), node)
      end

      def first_owned_node(analysis)
        first_statement = Array(analysis&.statements).first
        return unless first_statement

        if first_statement.respond_to?(:container?) && first_statement.container? &&
           first_statement.respond_to?(:mergeable_children)
          first_child = Array(first_statement.mergeable_children).first
          return first_child if first_child
        end

        first_statement
      end

      def equivalent_owner?(left, right)
        return false unless left && right
        return true if left.equal?(right)
        return false unless left.respond_to?(:type) && right.respond_to?(:type) && left.type == right.type
        unless left.respond_to?(:start_line) && right.respond_to?(:start_line) && left.start_line == right.start_line
          return false
        end
        unless left.respond_to?(:end_line) && right.respond_to?(:end_line) && left.end_line == right.end_line
          return false
        end

        if left.respond_to?(:key_name) && right.respond_to?(:key_name)
          left.key_name == right.key_name
        else
          true
        end
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

      def normalized_comment_unit(comment)
        return comment.normalized_content if comment.respond_to?(:normalized_content)
        return comment[:text].to_s.strip if comment.is_a?(Hash)

        comment.to_s.strip
      end

      def emit_with_preferred_inline_comment(node, analysis, shared_attachment: nil)
        tracked_inline_comment = tracked_inline_comment_for(node, analysis)
        attachment = shared_attachment || shared_line_comment_attachment_for(node, analysis)
        inline_region = attachment&.inline_region

        unless inline_region && !inline_region.empty?
          if tracked_inline_comment
            raise MissingSharedInlineRegionError,
                  "Expected shared inline region for tracked inline comment at line #{tracked_inline_comment[:line]}"
          end

          yield nil
          return
        end

        yield nil
        @emitter.emit_comment_attachment(attachment, leading: false, inline: true, source_lines: analysis.lines)
      end

      def shared_line_comment_attachment_for(node, analysis)
        return unless node && analysis
        return unless node.respond_to?(:start_line) && node.start_line

        tracker = analysis.comment_tracker
        leading_comments = tracker.leading_comments_before(node.start_line)
        return if leading_comments.any? { |comment| comment[:block] }

        inline_comment = tracker.inline_comment_at(inline_comment_line_for(node))
        return unless leading_comments.any? || inline_comment

        analysis.comment_attachment_for(
          node,
          line_num: node.start_line,
          leading_comments: leading_comments,
          inline_comment: inline_comment
        )
      end

      def shared_inline_comment_attachment_for(node, analysis)
        return unless node && analysis
        return unless node.respond_to?(:start_line) && node.start_line

        inline_comment = analysis.comment_tracker.inline_comment_at(inline_comment_line_for(node))
        return unless inline_comment

        analysis.comment_attachment_for(
          node,
          line_num: node.start_line,
          leading_comments: [],
          inline_comment: inline_comment
        )
      end

      def inline_comment_line_for(node)
        return unless node
        return node.start_line if node.respond_to?(:pair?) && node.pair?
        return node.start_line if node.respond_to?(:container?) && node.container?

        node.end_line || node.start_line
      end

      def emit_container_trailing_lines(container_node, analysis)
        range = trailing_container_line_range(container_node)
        return unless range

        region = shared_trailing_line_comment_region_for(range, analysis)
        unless region && !region.empty?
          emit_comment_and_blank_lines_in_range(range.begin, range.end, analysis)
          return
        end

        emit_blank_lines_in_range(range.begin, region.start_line - 1, analysis)
        @emitter.emit_comment_region(region, source_lines: analysis.lines)
        emit_blank_lines_in_range(region.end_line + 1, range.end, analysis)
      end

      def container_has_trailing_comments?(container_node, analysis)
        range = trailing_container_line_range(container_node)
        return false unless range

        range.any? do |line_num|
          stripped = analysis.line_at(line_num).to_s.strip
          comment_like_line?(stripped)
        end
      end

      def trailing_container_line_range(container_node)
        return unless container_node&.container?
        return unless container_node.respond_to?(:start_line) && container_node.respond_to?(:end_line)
        return unless container_node.start_line && container_node.end_line

        children = container_node.mergeable_children
        start_line = if children.any?
                       last_child = children.last
                       (last_child.end_line || last_child.start_line) + 1
                     else
                       container_node.start_line + 1
                     end
        end_line = container_node.end_line - 1
        return if end_line < start_line

        start_line..end_line
      end

      def emit_comment_and_blank_lines_in_range(start_line, end_line, analysis)
        return unless start_line && end_line
        return if end_line < start_line

        lines = []
        (start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          next unless line

          stripped = line.strip
          next unless stripped.empty? || comment_like_line?(stripped)

          lines << line
        end

        @emitter.emit_raw_lines(lines) if lines.any?
      end

      def shared_trailing_line_comment_region_for(range, analysis)
        return unless range && analysis
        return unless trailing_range_supports_shared_line_region?(range, analysis)

        region = analysis.comment_region_for_range(range, kind: :trailing, full_line_only: true)
        return unless region && !region.empty?

        region
      end

      def trailing_range_supports_shared_line_region?(range, analysis)
        range.each do |line_num|
          stripped = analysis.line_at(line_num).to_s.strip
          next if stripped.empty?
          return false unless stripped.start_with?('//')
          return false unless analysis.comment_tracker.full_line_comment?(line_num)
        end

        true
      end

      def comment_like_line?(stripped_line)
        stripped_line.start_with?('//', '/*', '*', '*/')
      end

      def emit_freeze_block(freeze_node)
        @emitter.emit_raw_lines(freeze_node.lines)
      end

      def emit_removed_destination_node_comments(node, analysis)
        return unless node.respond_to?(:start_line) && node.start_line

        leading_comments = analysis.comment_tracker.leading_comments_before(node.start_line)
        emit_preferred_leading_comments_for(node, analysis)

        inline_comment = removed_inline_comment_for(node, analysis)
        if inline_comment
          @emitter.emit_tracked_comment(normalize_comment_indent(
                                          inline_comment.merge(
                                            indent: current_emitter_indent,
                                            full_line: true,
                                            block: inline_comment[:block] || false
                                          )
                                        ))
        end

        emit_following_removed_node_blank_lines(node, analysis) if leading_comments.any? || inline_comment
      end

      def emit_following_removed_node_blank_lines(node, analysis)
        line_num = (node.end_line || node.start_line) + 1
        first_nonblank_line = line_num

        while first_nonblank_line <= analysis.lines.length && analysis.comment_tracker.blank_line?(first_nonblank_line)
          first_nonblank_line += 1
        end

        return if analysis.comment_tracker.full_line_comment?(first_nonblank_line)

        while line_num <= analysis.lines.length && analysis.comment_tracker.blank_line?(line_num)
          @emitter.emit_blank_line
          line_num += 1
        end
      end

      def removed_inline_comment_for(node, analysis)
        line_num = inline_comment_line_for(node)
        return unless line_num

        region = analysis.comment_tracker.inline_comment_region_at(line_num)
        tracked = Array(region&.metadata&.dig(:tracked_hashes)).first
        return tracked if tracked

        analysis.comment_tracker.inline_comment_at(line_num) || removed_inline_block_comment_at(line_num, analysis)
      end

      def removed_inline_block_comment_at(line_num, analysis)
        line = analysis.line_at(line_num).to_s
        return if line.empty?

        start_idx = line.index('/*')
        end_idx = start_idx && line.index('*/', start_idx + 2)
        return unless start_idx && end_idx

        before_comment = line[0...start_idx].to_s
        after_comment = line[(end_idx + 2)..].to_s
        return if before_comment.strip.empty?
        return unless after_comment.strip.empty?

        quote_count = before_comment.count('"') - before_comment.scan('\\"').count
        return unless quote_count.even?

        {
          line: line_num,
          indent: 0,
          text: line[(start_idx + 2)...end_idx].to_s.strip,
          full_line: false,
          block: true,
          raw: line[start_idx..(end_idx + 1)]
        }
      end

      def emit_tracked_comments_with_internal_blank_lines(comments, analysis)
        Array(comments).each_with_index do |comment, index|
          emit_tracked_comment_preserving_raw_layout(comment, analysis)

          next_comment = comments[index + 1]
          next unless next_comment

          emit_blank_lines_in_range(comment_end_line(comment) + 1, next_comment[:line] - 1, analysis)
        end
      end

      def emit_tracked_comment_preserving_raw_layout(comment, analysis)
        if multiline_block_comment?(comment)
          lines = (comment[:line]..comment_end_line(comment)).map { |line_num| analysis.line_at(line_num) }.compact
          @emitter.emit_raw_lines(lines) if lines.any?
          return
        end

        @emitter.emit_tracked_comment(normalize_comment_indent(comment))
      end

      def multiline_block_comment?(comment)
        comment && comment[:block] && comment_end_line(comment) > comment[:line]
      end

      def comment_end_line(comment)
        return unless comment

        comment[:end_line] || comment[:line]
      end

      def emit_document_prelude(analysis, nodes: [])
        augmenter = document_comment_augmenter_for(analysis)
        return unless augmenter

        normalized_nodes = Array(nodes)
        regions = []
        preamble = augmenter.preamble_region
        regions << preamble if preamble && !preamble.empty?

        if normalized_nodes.any?
          first_attachment = augmenter.attachment_for(normalized_nodes.first)
          first_leading = first_attachment&.leading_region
          if first_leading && !first_leading.empty?
            duplicate = regions.any? do |region|
              region.start_line == first_leading.start_line && region.end_line == first_leading.end_line
            end
            regions << first_leading unless duplicate
          end
        end

        if normalized_nodes.empty?
          augmenter.orphan_regions.each do |region|
            regions << region if region && !region.empty?
          end
        end

        regions.each do |region|
          @emitter.emit_comment_region(region, source_lines: analysis.lines)
        end

        return if regions.empty?

        last_region_end = regions.last.end_line
        if normalized_nodes.any?
          first_node_start = normalized_nodes.first.start_line
          if last_region_end && first_node_start
            emit_blank_lines_in_range(last_region_end + 1, first_node_start - 1,
                                      analysis)
          end
        elsif last_region_end
          emit_blank_lines_in_range(last_region_end + 1, analysis.lines.length, analysis)
        end
      end

      def emit_document_postlude(analysis, fallback_node: nil)
        augmenter = document_comment_augmenter_for(analysis)
        regions = []
        postlude = augmenter&.postlude_region
        regions << postlude if postlude && !postlude.empty?

        if fallback_node
          last_attachment = augmenter&.attachment_for(fallback_node)
          last_trailing = last_attachment&.trailing_region
          if last_trailing && !last_trailing.empty?
            duplicate = regions.any? do |region|
              region.start_line == last_trailing.start_line && region.end_line == last_trailing.end_line
            end
            regions << last_trailing unless duplicate
          end
        end

        return if regions.empty?

        first_region = regions.first
        if fallback_node && first_region.respond_to?(:start_line) && first_region.start_line && fallback_node.respond_to?(:end_line) && fallback_node.end_line && fallback_node.respond_to?(:end_line) && fallback_node.end_line
          emit_blank_lines_in_range(fallback_node.end_line + 1, first_region.start_line - 1,
                                    analysis)
        end

        regions.each do |region|
          @emitter.emit_comment_region(region, source_lines: analysis.lines)
        end
      end

      def document_comment_augmenter_for(analysis)
        @document_comment_augmenters ||= {}
        @document_comment_augmenters[analysis.object_id] ||= analysis.comment_augmenter
      end

      def emit_blank_lines_in_range(start_line, end_line, analysis)
        return unless start_line && end_line
        return if end_line < start_line

        (start_line..end_line).each do |line_num|
          @emitter.emit_blank_line if analysis.comment_tracker.blank_line?(line_num)
        end
      end

      def emit_blank_lines_before_leading_comments(first_comment_line, analysis)
        return unless first_comment_line

        blank_lines = []
        line_num = first_comment_line - 1
        while line_num >= 1 && analysis.comment_tracker.blank_line?(line_num)
          blank_lines << line_num
          line_num -= 1
        end

        blank_lines.reverse_each { @emitter.emit_blank_line }
      end

      def normalize_comment_indent(comment)
        return comment unless comment

        comment.merge(indent: current_emitter_indent)
      end

      def current_emitter_indent
        @emitter.indent_level * @emitter.indent_size
      end

      def compact_empty_container?(container_node, source_node, source_analysis)
        return false unless container_node&.container?
        return false unless container_node.mergeable_children.empty?

        !container_has_trailing_comments?(source_node || container_node, source_analysis)
      end

      def compact_container_literal_for(container_node)
        container_node.object? ? '{}' : '[]'
      end

      def build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        return {} unless @match_refiner

        matched_sigs = template_by_sig.keys & dest_by_sig.keys

        unmatched_template = template_nodes.reject do |node|
          sig = @template_analysis.generate_signature(node)
          sig && matched_sigs.include?(sig)
        end

        unmatched_dest = dest_nodes.reject do |node|
          sig = @dest_analysis.generate_signature(node)
          sig && matched_sigs.include?(sig)
        end

        return {} if unmatched_template.empty? || unmatched_dest.empty?

        matches = @match_refiner.call(unmatched_template, unmatched_dest, {
                                        template_analysis: @template_analysis,
                                        dest_analysis: @dest_analysis
                                      })

        matches.each_with_object({}) do |match, hash|
          hash[match.template_node] = match.dest_node
        end
      end
    end
  end
end
