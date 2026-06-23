# frozen_string_literal: true

module Toml
  module Merge
    # Resolves conflicts between template and destination TOML content
    # using structural signatures and configurable preferences.
    #
    # @example Basic usage
    #   resolver = ConflictResolver.new(template_analysis, dest_analysis)
    #   resolver.resolve(result)
    class ConflictResolver < Ast::Merge::ConflictResolverBase
      class MissingSharedInlineRegionError < Toml::Merge::Error; end

      include ::Ast::Merge::TrailingGroups::DestIterate
      include ::Ast::Merge::StructuredEmitterProvenanceSupport

      attr_reader :corruption_handling

      # Creates a new ConflictResolver
      #
      # @param template_analysis [FileAnalysis] Analyzed template file
      # @param dest_analysis [FileAnalysis] Analyzed destination file
      # @param preference [Symbol] Which version to prefer when
      #   nodes have matching signatures:
      #   - :destination (default) - Keep destination version (customizations)
      #   - :template - Use template version (updates)
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      def initialize(template_analysis, dest_analysis, preference: :destination, add_template_only_nodes: false,
                     remove_template_missing_nodes: false, resolution_mode: :eager, corruption_handling: :heal, match_refiner: nil, **options)
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

          if template_statements.empty? && dest_statements.empty?
            emit_comment_only_document(preferred_comment_only_analysis(@template_analysis, @dest_analysis))
            return transfer_emitter_output(result)
          end

          emit_root_boundary_region(preferred_boundary_analysis(@template_analysis, @dest_analysis), :preamble)

          # Merge root-level statements via emitter
          merge_node_lists_to_emitter(
            template_statements,
            dest_statements,
            @template_analysis,
            @dest_analysis
          )

          emit_root_boundary_region(preferred_boundary_analysis(@template_analysis, @dest_analysis), :postlude)
          if @emitter.to_s.empty?
            emit_comment_only_document(preferred_comment_only_analysis(@template_analysis,
                                                                       @dest_analysis))
          end

          # Transfer emitter output to result
          transfer_emitter_output(result)

          DebugLogger.debug('Conflict resolution complete', {
                              template_statements: template_statements.size,
                              dest_statements: dest_statements.size,
                              result_lines: result.line_count
                            })
        end
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
        # This is especially important for TOML [[array_of_tables]] which can
        # legitimately repeat headers.
        consumed_template_indices = ::Set.new
        sig_cursor = Hash.new(0)
        emitted_destination_signatures = ::Set.new
        prev_emitted_end_line = nil
        prev_emitted_analysis = nil

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

        # Emit template-only nodes that precede the first matched template node
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          emit_gap_before_node(info[:node], template_analysis, prev_emitted_end_line, prev_emitted_analysis)
          emit_node(info[:node], template_analysis)
          prev_emitted_end_line = emitted_end_line_for(info[:node])
          prev_emitted_analysis = template_analysis
        end

        # First pass: Process destination nodes
        dest_nodes.each do |dest_node|
          dest_sig = dest_analysis.generate_signature(dest_node)

          # Check for signature match
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
              selected_node, selected_analysis = preferred_node_with_analysis(
                template_node,
                dest_node,
                template_analysis,
                dest_analysis
              )

              emit_gap_before_node(
                selected_node,
                selected_analysis,
                prev_emitted_end_line,
                prev_emitted_analysis,
                skip_for_borrowed_leading_region: @preference == :template && leading_region_present?(dest_node,
                                                                                                      dest_analysis)
              )

              # Both have this node - merge them
              merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
              prev_emitted_end_line = emitted_end_line_for(selected_node)
              prev_emitted_analysis = selected_analysis
              emitted_destination_signatures << dest_sig if dest_sig

              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1
            elsif @remove_template_missing_nodes
              # All template copies consumed — treat the extra destination copy as destination-only.
              if emit_removed_destination_node_comments(dest_node, dest_analysis)
                prev_emitted_end_line = emitted_end_line_for(dest_node)
                prev_emitted_analysis = dest_analysis
              end
            elsif redundant_destination_pair_duplicate?(dest_node, dest_sig, emitted_destination_signatures)
              next
            else
              emit_gap_before_node(dest_node, dest_analysis, prev_emitted_end_line, prev_emitted_analysis)
              emit_node(dest_node, dest_analysis)
              prev_emitted_end_line = emitted_end_line_for(dest_node)
              prev_emitted_analysis = dest_analysis
              emitted_destination_signatures << dest_sig if dest_sig
            end
          elsif refined_dest_to_template.key?(dest_node)
            # Found refined match
            template_node = refined_dest_to_template[dest_node]
            template_sig = template_analysis.generate_signature(template_node)
            selected_node, selected_analysis = preferred_node_with_analysis(
              template_node,
              dest_node,
              template_analysis,
              dest_analysis
            )

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
            emit_gap_before_node(
              selected_node,
              selected_analysis,
              prev_emitted_end_line,
              prev_emitted_analysis,
              skip_for_borrowed_leading_region: @preference == :template && leading_region_present?(dest_node,
                                                                                                    dest_analysis)
            )
            merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
            prev_emitted_end_line = emitted_end_line_for(selected_node)
            prev_emitted_analysis = selected_analysis
            emitted_destination_signatures << dest_sig if dest_sig
          elsif @remove_template_missing_nodes
            # Destination-only node
            if emit_removed_destination_node_comments(dest_node, dest_analysis)
              prev_emitted_end_line = emitted_end_line_for(dest_node)
              prev_emitted_analysis = dest_analysis
            end
          elsif redundant_destination_pair_duplicate?(dest_node, dest_sig, emitted_destination_signatures)
            next
          else
            emit_gap_before_node(dest_node, dest_analysis, prev_emitted_end_line, prev_emitted_analysis)
            emit_node(dest_node, dest_analysis)
            prev_emitted_end_line = emitted_end_line_for(dest_node)
            prev_emitted_analysis = dest_analysis
            emitted_destination_signatures << dest_sig if dest_sig
          end

          # Flush interior trailing groups
          flush_ready_trailing_groups(
            trailing_groups: trailing_groups,
            matched_indices: all_matched_indices,
            consumed_indices: consumed_template_indices
          ) do |info|
            emit_gap_before_node(info[:node], template_analysis, prev_emitted_end_line, prev_emitted_analysis)
            emit_node(info[:node], template_analysis)
            prev_emitted_end_line = emitted_end_line_for(info[:node])
            prev_emitted_analysis = template_analysis
          end
        end

        # Emit remaining trailing groups (tail + safety net)
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices
        ) do |info|
          emit_gap_before_node(info[:node], template_analysis, prev_emitted_end_line, prev_emitted_analysis)
          emit_node(info[:node], template_analysis)
          prev_emitted_end_line = emitted_end_line_for(info[:node])
          prev_emitted_analysis = template_analysis
        end
      end

      # Merge two matched nodes
      # @param template_node [NodeWrapper] Template node
      # @param dest_node [NodeWrapper] Destination node
      # @param template_analysis [FileAnalysis] Template analysis
      # @param dest_analysis [FileAnalysis] Destination analysis
      def merge_matched_nodes_to_emitter(template_node, dest_node, template_analysis, dest_analysis)
        # For TOML, tables can be merged recursively
        if dest_node.table? && template_node.table?
          with_resolution_path_segment(dest_node, template_node) do
            selected_node, selected_analysis = preferred_node_with_analysis(
              template_node,
              dest_node,
              template_analysis,
              dest_analysis
            )

            comment_source_node, comment_source_analysis = if @preference == :template
                                                             [dest_node, dest_analysis]
                                                           else
                                                             [nil, selected_analysis]
                                                           end

            emit_leading_region(
              selected_node,
              selected_analysis,
              comment_source_node: comment_source_node,
              comment_analysis: comment_source_analysis
            )

            # Emit table header and merge children
            @emitter.emit_table_header(
              selected_node.table_name || dest_node.table_name || template_node.table_name,
              inline_comment: preferred_inline_comment_text(
                selected_node,
                selected_analysis,
                comment_source_node: comment_source_node,
                comment_analysis: comment_source_analysis
              )
            )

            template_children = template_node.mergeable_children
            dest_children = dest_node.mergeable_children

            merge_node_lists_to_emitter(
              template_children,
              dest_children,
              template_analysis,
              dest_analysis
            )
          end
        elsif @preference == :destination
          # Leaf nodes or mismatched types - use preference
          record_unresolved_choice(template_node: template_node, dest_node: dest_node, provisional_winner: :destination)
          emit_node(dest_node, dest_analysis)
        else
          record_unresolved_choice(template_node: template_node, dest_node: dest_node, provisional_winner: :template)
          emit_node(
            template_node,
            template_analysis,
            comment_source_node: dest_node,
            comment_analysis: dest_analysis
          )
        end
      end

      def redundant_destination_pair_duplicate?(node, signature, emitted_signatures)
        signature && node.respond_to?(:pair?) && node.pair? && emitted_signatures.include?(signature)
      end

      # Emit a single node to the emitter
      # @param node [NodeWrapper] Node to emit
      # @param analysis [FileAnalysis] Analysis for accessing source
      def emit_node(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        emit_leading_region(
          node,
          analysis,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis
        )

        # Emit the node content
        start_line = node.start_line
        end_line = emitted_end_line_for(node)

        return unless start_line && end_line

        lines = []
        (start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          lines << line if line
        end
        emit_node_lines(
          lines,
          node,
          analysis,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis
        )
      end

      # Build a map of refined matches
      # @param template_nodes [Array<NodeWrapper>] Template nodes
      # @param dest_nodes [Array<NodeWrapper>] Destination nodes
      # @param template_by_sig [Hash] Template signature map
      # @param dest_by_sig [Hash] Destination signature map
      # @return [Hash] Map of template_node => dest_node
      def build_refined_matches(template_nodes, dest_nodes, template_by_sig, dest_by_sig)
        return {} unless @match_refiner

        # Find unmatched nodes
        matched_sigs = template_by_sig.keys & dest_by_sig.keys
        unmatched_t_nodes = template_nodes.reject do |n|
          sig = @template_analysis.generate_signature(n)
          sig && matched_sigs.include?(sig)
        end
        unmatched_d_nodes = dest_nodes.reject do |n|
          sig = @dest_analysis.generate_signature(n)
          sig && matched_sigs.include?(sig)
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

      def emit_removed_destination_node_comments(node, analysis)
        emitted_line_count = @emitter.lines.length
        emit_leading_region(node, analysis)
        emit_removed_destination_node_inline_comments(node, analysis)
        if table_like_node?(node)
          node.mergeable_children.each do |child|
            emit_removed_destination_node_comments(child, analysis)
          end
        end
        @emitter.lines.length > emitted_line_count
      end

      def emit_removed_destination_node_inline_comments(node, analysis)
        inline_region = attachment_region(node, analysis, :inline_region)
        return unless inline_region && !inline_region.empty?

        indent = analysis.line_at(node.start_line).to_s[/\A\s*/].to_s.length
        tracked_hashes = Array(inline_region.metadata[:tracked_hashes])

        if tracked_hashes.any?
          tracked_hashes.each do |comment|
            @emitter.emit_tracked_comment(comment.merge(indent: indent, full_line: true))
          end
        else
          @emitter.emit_comment(inline_region.text.to_s.sub(/\A\s*#\s?/, ''))
        end
      end

      def preferred_boundary_analysis(template_analysis, dest_analysis)
        @preference == :template ? template_analysis : dest_analysis
      end

      def preferred_comment_only_analysis(template_analysis, dest_analysis)
        preferred = preferred_boundary_analysis(template_analysis, dest_analysis)
        alternate = preferred.equal?(template_analysis) ? dest_analysis : template_analysis

        [preferred, alternate].find do |analysis|
          analysis.statements.empty? && analysis.comment_nodes.any?
        end
      end

      def emit_comment_only_document(analysis)
        return unless analysis

        @emitter.emit_raw_lines(analysis.lines)
      end

      def emit_root_boundary_region(analysis, kind)
        boundary_analysis_candidates(analysis, kind).find do |candidate|
          next unless candidate

          augmenter = candidate.comment_augmenter(owners: candidate.statements)
          region = kind == :preamble ? augmenter.preamble_region : augmenter.postlude_region
          boundary_lines = canonical_root_boundary_lines_for(region, candidate, kind)
          boundary_lines = fallback_root_boundary_lines_for(candidate, kind) if boundary_lines.empty?
          next if boundary_lines.empty?

          remember_emitted_root_boundary_region(boundary_lines, kind) if region
          @emitter.emit_raw_lines(boundary_lines)
          true
        end
      end

      def boundary_analysis_candidates(preferred_analysis, kind)
        return [] unless preferred_analysis

        fallback_analysis = preferred_analysis.equal?(@template_analysis) ? @dest_analysis : @template_analysis
        analyses = [preferred_analysis]
        return analyses if kind == :preamble && first_statement_leading_region_present?(preferred_analysis)

        analyses << fallback_analysis if @add_template_only_nodes
        analyses.compact.uniq
      end

      def canonical_root_boundary_lines_for(region, analysis, kind)
        return [] unless region

        boundary_lines = root_boundary_lines_for(region, analysis, kind)
        return boundary_lines unless kind == :preamble

        boundary_lines = collapse_template_preamble_prefix(boundary_lines, preferred_analysis: analysis)
        prefer_attached_first_statement_preamble_lines(boundary_lines, region, preferred_analysis: analysis)
      end

      def collapse_template_preamble_prefix(boundary_lines, preferred_analysis:)
        return boundary_lines unless preferred_analysis.equal?(@dest_analysis)
        return boundary_lines if boundary_lines.empty?

        template_lines = alternate_template_preamble_lines_for(preferred_analysis)
        return boundary_lines if template_lines.empty?

        repeat_count = leading_repeat_count(boundary_lines, template_lines)
        return boundary_lines if repeat_count.zero?

        remainder = boundary_lines.drop(repeat_count * template_lines.length)
        return template_lines if remainder.empty?

        should_heal = handle_suspected_corruption(
          kind: :duplicate_template_preamble_prefix,
          message: 'document preamble begins with duplicated template-owned TOML preamble lines',
          context: {
            repeated_lines: repeat_count * template_lines.length,
            remaining_lines: remainder.length
          }
        )
        should_heal ? remainder : boundary_lines
      end

      def alternate_template_preamble_lines_for(preferred_analysis)
        alternate_analysis = preferred_analysis.equal?(@template_analysis) ? @dest_analysis : @template_analysis
        return [] unless alternate_analysis

        alternate_augmenter = alternate_analysis.comment_augmenter(owners: alternate_analysis.statements)
        alternate_region = alternate_augmenter.preamble_region
        return [] unless alternate_region

        root_boundary_lines_for(alternate_region, alternate_analysis, :preamble)
      end

      def prefer_attached_first_statement_preamble_lines(boundary_lines, region, preferred_analysis:)
        return boundary_lines if boundary_lines.empty?
        return boundary_lines unless region

        alternate_analysis = preferred_analysis.equal?(@template_analysis) ? @dest_analysis : @template_analysis
        alternate_region = first_statement_leading_region_for(alternate_analysis)
        return boundary_lines unless alternate_region
        return boundary_lines unless region.normalized_content == alternate_region.normalized_content

        region_lines_for(alternate_region, alternate_analysis)
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

      def remember_emitted_root_boundary_region(boundary_lines, kind)
        return unless kind == :preamble

        dedup_keys_for_lines(boundary_lines).each do |key|
          (@emitted_leading_comment_texts ||= ::Set.new).add(key)
        end
      end

      def first_statement_leading_region_present?(analysis)
        region = first_statement_leading_region_for(analysis)
        region && (!region.respond_to?(:empty?) || !region.empty?)
      end

      def first_statement_leading_region_for(analysis)
        return unless analysis

        first_statement = Array(analysis.statements).first
        return unless first_statement

        attachment_region(first_statement, analysis, :leading_region)
      end

      def emit_leading_region(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        region, source_analysis, source_node = preferred_region_with_source(
          node,
          analysis,
          :leading_region,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis
        )
        return unless region

        region = canonical_leading_region_for(
          region,
          source_analysis: source_analysis,
          source_node: source_node
        )

        # Bidirectional dedup: skip this region if an identical comment block
        # was already emitted by a preceding node (from either source).
        dedup_keys = dedup_keys_for_region(region)
        if dedup_keys.any? { |key| @emitted_leading_comment_texts.include?(key) }
          should_heal = handle_suspected_corruption(
            kind: :comment_ownership_overlap,
            message: 'leading comment region overlaps previously emitted TOML comment ownership',
            context: dedup_warning_context(region: region, analysis: source_analysis, node: node,
                                           source_node: source_node)
          )
          if should_heal
            emit_interstitial_blank_lines((region.end_line || source_node&.start_line).to_i + 1,
                                          source_node&.start_line.to_i - 1, source_analysis)
            return
          end
        end
        dedup_keys.each { |key| @emitted_leading_comment_texts.add(key) }

        emit_preceding_blank_lines(region, source_analysis)
        @emitter.emit_comment_region(region, source_lines: source_analysis&.lines)
        emit_interstitial_blank_lines((region.end_line || source_node&.start_line).to_i + 1,
                                      source_node&.start_line.to_i - 1, source_analysis)
      end

      def dedup_keys_for_region(region)
        normalized = normalize_comment_text(region.normalized_content.to_s)
        return [] if normalized.empty?

        keys = [normalized]
        semantic_key = shared_dev_preamble_dedup_key(normalized)
        keys << semantic_key if semantic_key
        keys.uniq
      end

      def dedup_keys_for_lines(lines)
        normalized = Array(lines).map { |line| normalize_comment_line(line) }.join("\n")
        normalized = normalized.sub(/\n+\z/, '')
        return [] if normalized.empty?

        keys = [normalized]
        semantic_key = shared_dev_preamble_dedup_key(normalized)
        keys << semantic_key if semantic_key
        keys.uniq
      end

      SHARED_DEV_PREAMBLE_FIRST_LINE = /\AShared development environment for .+\.\z/
      SHARED_DEV_PREAMBLE_SECOND_LINE = 'Local overrides belong in .env.local (loaded via dotenvy through mise).'
      private_constant :SHARED_DEV_PREAMBLE_FIRST_LINE, :SHARED_DEV_PREAMBLE_SECOND_LINE

      def shared_dev_preamble_dedup_key(normalized)
        lines = normalized.lines.map(&:chomp).reject(&:empty?)
        return unless lines.length >= 2
        return unless lines.first.match?(SHARED_DEV_PREAMBLE_FIRST_LINE)
        return unless lines[1] == SHARED_DEV_PREAMBLE_SECOND_LINE

        canonicalized = lines.dup
        canonicalized[0] = 'Shared development environment for __MATCHED_GEM__.'
        canonicalized.join("\n")
      end

      def normalize_comment_text(text)
        text.to_s.lines.map { |line| normalize_comment_line(line) }.join("\n").sub(/\n+\z/, '')
      end

      def normalize_comment_line(line)
        line.to_s.sub(/\A\s*#\s?/, '').rstrip
      end

      def canonical_leading_region_for(region, source_analysis:, source_node:)
        return region unless source_analysis.equal?(@dest_analysis)
        return region unless source_node
        return region unless source_analysis.statements.first.equal?(source_node)
        return region unless region.respond_to?(:start_line) && region.start_line == 1

        template_region = template_preamble_region
        return region unless template_region

        collapse_template_preamble_prefix_region(region, template_region)
      end

      def template_preamble_region
        augmenter = @template_analysis.comment_augmenter(owners: @template_analysis.statements)
        augmenter.preamble_region
      end

      def collapse_template_preamble_prefix_region(region, template_region)
        template_nodes = Array(template_region.nodes)
        region_nodes = Array(region.nodes)
        return region if template_nodes.empty? || region_nodes.length < template_nodes.length

        repeat_count = leading_repeat_count(region_nodes, template_nodes) do |left, right|
          left.respond_to?(:normalized_content) && right.respond_to?(:normalized_content) &&
            left.normalized_content == right.normalized_content
        end
        return region if repeat_count.zero?

        remainder_nodes = region_nodes.drop(repeat_count * template_nodes.length)
        return region if remainder_nodes.empty?

        should_heal = handle_suspected_corruption(
          kind: :duplicate_template_preamble_prefix,
          message: 'first-node leading region begins with duplicated template-owned TOML preamble comments',
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

      def root_boundary_lines_for(region, analysis, kind)
        return [] unless region.respond_to?(:nodes)
        return [] if region.nodes.empty?

        case kind
        when :preamble
          end_line = first_structural_root_line_for(analysis) - 1
          return [] if end_line < 1

          (1..end_line).filter_map { |line_num| analysis.line_at(line_num) }
        when :postlude
          start_line = last_structural_root_line_for(analysis) + 1
          return [] if start_line > analysis.lines.length

          (start_line..analysis.lines.length).filter_map { |line_num| analysis.line_at(line_num) }
        else
          []
        end
      end

      def region_lines_for(region, analysis)
        return [] unless region && analysis
        return [] unless region.respond_to?(:start_line) && region.respond_to?(:end_line)
        return [] unless region.start_line && region.end_line

        (region.start_line..region.end_line).filter_map { |line_num| analysis.line_at(line_num) }
      end

      def fallback_root_boundary_lines_for(analysis, kind)
        return [] unless kind == :postlude

        start_line = last_structural_root_line_for(analysis) + 1
        return [] if start_line > analysis.lines.length

        (start_line..analysis.lines.length).filter_map { |line_num| analysis.line_at(line_num) }
      end

      def dedup_warning_context(region:, analysis:, node:, source_node:)
        {
          file: analysis.respond_to?(:path) ? analysis.path : nil,
          owner_type: node&.respond_to?(:type) ? node.type : node.class.name.split('::').last,
          source_owner_type: source_node&.respond_to?(:type) ? source_node.type : source_node&.class&.name&.split('::')&.last,
          region_lines: [region.respond_to?(:start_line) ? region.start_line : nil,
                         region.respond_to?(:end_line) ? region.end_line : nil],
          normalized_content: region.normalized_content
        }.compact
      end

      def handle_suspected_corruption(kind:, message:, context:)
        ::Ast::Merge::Healer.handle(
          mode: corruption_handling,
          kind: kind,
          message: message,
          prefix: '[toml-merge]',
          error_class: Toml::Merge::CorruptionDetectedError,
          warner: ->(formatted) { DebugLogger.debug_warning(formatted, context) }
        )
      end

      def preferred_node_with_analysis(template_node, dest_node, template_analysis, dest_analysis)
        if @preference == :template
          [template_node, template_analysis]
        else
          [dest_node, dest_analysis]
        end
      end

      def record_unresolved_choice(template_node:, dest_node:, provisional_winner:)
        return unless unresolved_mode?
        return unless template_node && dest_node
        return if template_node.table? && dest_node.table?

        template_text = template_node.text
        dest_text = dest_node.text

        identifier = resolution_identifier(template_node, dest_node)
        surface_path = resolution_surface_path(dest_node, identifier)
        record_unresolved_node_choice(
          result: @result,
          template_node: template_node,
          destination_node: dest_node,
          template_text: template_text,
          destination_text: dest_text,
          provisional_winner: provisional_winner,
          case_prefix: 'toml',
          case_parts: [dest_node.type, identifier],
          surface_path: surface_path,
          metadata: {
            node_type: dest_node.type,
            identifier: identifier,
            review_identity: review_identity_for_unresolved_choice(
              template_text: template_text,
              destination_text: dest_text,
              provisional_winner: provisional_winner,
              surface_path: surface_path,
              node_type: dest_node.type,
              identifier: identifier
            )
          },
          conflict_fields: {
            node_type: dest_node.type,
            identifier: identifier
          }
        )
      end

      def resolution_identifier(template_node, dest_node)
        unresolved_identifier_for_nodes(dest_node, template_node, methods: %i[key_name table_name])
      end

      def resolution_surface_path(node, identifier)
        segment = resolution_path_segment_for(node, identifier)
        unresolved_surface_path_for(segment)
      end

      def resolution_path_segment_for(node, identifier)
        unresolved_typed_path_segment(node.type, identifier: identifier, node: node, fallback: node.type)
      end

      def with_resolution_path_segment(*nodes, &block)
        with_first_unresolved_path_segment(
          *nodes,
          segment_builder: ->(node) { resolution_path_segment_for(node, resolution_identifier(node, node)) }, &block
        )
      end

      def inline_comment_text_for(node)
        inline_comment = node.respond_to?(:inline_comment) ? node.inline_comment : nil
        return unless inline_comment

        inline_comment[:text]
      end

      def preferred_inline_comment_text(node, analysis, comment_source_node: nil, comment_analysis: analysis)
        region, = preferred_region_with_source(
          node,
          analysis,
          :inline_region,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis
        )
        unless region && !region.empty?
          inline_comment =
            inline_comment_text_for(node) ||
            inline_comment_text_for(comment_source_node)

          if inline_comment
            raise MissingSharedInlineRegionError,
                  'Expected shared inline region for owner with inline comment'
          end

          return
        end

        tracked = Array(region.metadata[:tracked_hashes]).first
        return tracked[:text] if tracked && tracked[:text]

        raise MissingSharedInlineRegionError,
              'Expected tracked inline comment metadata for shared inline region'
      end

      def emit_node_lines(lines, node, analysis, comment_source_node: nil, comment_analysis: analysis)
        return if lines.empty?

        metadata = emitter_block_metadata(analysis, node.start_line)

        inline_region, inline_source_analysis, = preferred_region_with_source(
          node,
          analysis,
          :inline_region,
          comment_source_node: comment_source_node,
          comment_analysis: comment_analysis
        )

        unless inline_region && !inline_region.empty?
          @emitter.emit_raw_lines(lines, metadata: metadata)
          return
        end

        existing_inline_region = attachment_region(node, analysis, :inline_region)
        first_line = strip_inline_region_from_line(lines.first, existing_inline_region)
        first_line = attach_inline_region_to_line(first_line, inline_region,
                                                  source_lines: inline_source_analysis&.lines)

        @emitter.emit_raw_lines([first_line], metadata: emitter_line_metadata(analysis, line_number: node.start_line))
        return unless lines.length > 1

        @emitter.emit_raw_lines(lines.drop(1),
                                metadata: emitter_block_metadata(analysis, node.start_line + 1))
      end

      def preferred_region_with_source(node, analysis, region_kind, comment_source_node: nil,
                                       comment_analysis: analysis)
        primary_region = attachment_region(node, analysis, region_kind)
        return [primary_region, analysis, node] if primary_region && !primary_region.empty?

        if comment_source_node && comment_analysis
          source_region = attachment_region(comment_source_node, comment_analysis, region_kind)
          return [source_region, comment_analysis, comment_source_node] if source_region && !source_region.empty?
        end

        [primary_region, analysis, node]
      end

      def attachment_region(node, analysis, region_kind)
        return unless node && analysis

        attachment = analysis.comment_attachment_for(node)
        attachment.public_send(region_kind) if attachment.respond_to?(region_kind)
      end

      def strip_inline_region_from_line(line, inline_region)
        return line unless line
        return line unless inline_region && !inline_region.empty?

        tracked = Array(inline_region.metadata[:tracked_hashes]).first
        column = tracked && tracked[:column]
        return line unless column

        line.byteslice(0...column).to_s.rstrip
      end

      def attach_inline_region_to_line(line, inline_region, source_lines: nil)
        return line unless line
        return line unless inline_region && !inline_region.empty?

        raw_inline = inline_region.text.to_s
        return line if raw_inline.empty?

        base_line = line.to_s
        separator = inline_region_separator(inline_region, source_lines: source_lines, base_line: base_line,
                                                           raw_inline: raw_inline)

        base_line + separator + raw_inline
      end

      def inline_region_separator(inline_region, source_lines:, base_line:, raw_inline:)
        tracked = Array(inline_region.metadata[:tracked_hashes]).first
        if tracked && source_lines
          line_number = tracked[:line]
          column = tracked[:column]
          if line_number && column
            source_line = source_lines[line_number - 1].to_s
            source_prefix = source_line.byteslice(0...column).to_s
            return source_prefix[/[ \t]*\z/].to_s
          end
        end

        return '' if base_line.empty? || base_line.end_with?(' ', "\t") || !raw_inline.lstrip.start_with?('#')

        ' '
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

      def emit_gap_before_node(node, analysis, prev_end_line, prev_analysis, skip_for_borrowed_leading_region: false)
        return unless node && analysis && prev_end_line
        return unless prev_analysis&.equal?(analysis)
        return unless node.respond_to?(:start_line) && node.start_line
        return if skip_for_borrowed_leading_region

        leading_region = attachment_region(node, analysis, :leading_region)
        return if leading_region && (!leading_region.respond_to?(:empty?) || !leading_region.empty?)

        emit_interstitial_blank_lines(prev_end_line + 1, node.start_line - 1, analysis)
      end

      def leading_region_present?(node, analysis)
        region = attachment_region(node, analysis, :leading_region)
        region && (!region.respond_to?(:empty?) || !region.empty?)
      end

      def emit_preceding_blank_lines(region, analysis)
        return unless analysis
        return unless region.respond_to?(:start_line) && region.start_line

        line_num = region.start_line - 1
        lines = []

        while line_num >= 1
          line = analysis.line_at(line_num)
          break unless line && line.strip.empty?

          lines.unshift(line)
          line_num -= 1
        end

        @emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, line_num + 1)) if lines.any?
      end

      def emitted_end_line_for(node)
        return node.start_line if table_like_without_children?(node)

        if table_like_node?(node)
          child_end_line = node.mergeable_children.map(&:end_line).compact.max
          return child_end_line if child_end_line
        end

        node.end_line
      end

      def last_structural_root_line_for(analysis)
        analysis.statements.map { |node| emitted_end_line_for(node) }.compact.max || 0
      end

      def first_structural_root_line_for(analysis)
        analysis.statements.map(&:start_line).compact.min || 1
      end

      def table_like_without_children?(node)
        table_like_node?(node) && node.mergeable_children.empty?
      end

      def table_like_node?(node)
        node.table? || (node.respond_to?(:array_of_tables?) && node.array_of_tables?)
      end
    end
  end
end
