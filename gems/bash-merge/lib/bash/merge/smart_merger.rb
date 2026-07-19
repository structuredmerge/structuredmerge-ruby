# frozen_string_literal: true

module Bash
  module Merge
    # Main entry point for intelligent Bash script merging.
    # SmartMerger orchestrates the merge process using FileAnalysis
    # and MergeResult to merge two Bash scripts intelligently.
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_bash, dest_bash)
    #   result = merger.merge
    #   File.write("output.sh", result)
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_bash,
    #     dest_bash,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example With custom signature generator
    #   sig_gen = ->(node) {
    #     if node.is_a?(NodeWrapper) && node.function_definition? && node.function_name == "main"
    #       [:special_main]
    #     else
    #       node # Fall through to default
    #     end
    #   }
    #   merger = SmartMerger.new(template, dest, signature_generator: sig_gen)
    #
    # @example With node_typing for per-node-type preferences
    #   merger = SmartMerger.new(template, dest,
    #     node_typing: { "function_definition" => ->(n) { NodeTyping.with_merge_type(n, :func) } },
    #     preference: { default: :destination, func: :template })
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      include ::Ast::Merge::TrailingGroups::DestIterate
      include ::Ast::Merge::Runtime::RootSessionSupport
      include ::Ast::Merge::StructuredEmitterProvenanceSupport
      include ::Ast::Merge::CommentLayoutEmissionSupport

      # Creates a new SmartMerger for intelligent Bash script merging.
      #
      # @param template_content [String] Template Bash source code
      # @param dest_content [String] Destination Bash source code
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :destination, :template, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template
      # @param freeze_token [String] Token for freeze block markers
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #
      # @note To specify a custom parser path, use the TREE_SITTER_BASH_PATH environment
      #   variable. This is handled by tree_haver's GrammarFinder.
      # @param options [Hash] Additional options for forward compatibility
      #
      # @raise [TemplateParseError] If template has syntax errors
      # @raise [DestinationParseError] If destination has syntax errors
      def initialize(
        template_content,
        dest_content,
        signature_generator: nil,
        preference: :destination,
        add_template_only_nodes: false,
        remove_template_missing_nodes: false,
        corruption_handling: :heal,
        freeze_token: nil,
        match_refiner: nil,
        regions: nil,
        region_placeholder: nil,
        node_typing: nil,
        **options
      )
        @remove_template_missing_nodes = remove_template_missing_nodes
        @corruption_handling = ::Ast::Merge::Healer.normalize_mode(corruption_handling)

        super(
          template_content,
          dest_content,
          signature_generator: signature_generator,
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
        )
      end

      attr_reader :runtime_session, :corruption_handling, :remove_template_missing_nodes

      # Perform the merge and return the result as a Bash string.
      #
      # @return [String] Merged Bash content
      def merge
        merge_result.to_bash
      end

      # Perform the merge operation and return the full MergeResult object.
      #
      # @return [MergeResult] The merge result containing merged Bash content and metadata
      def merge_result
        return @merge_result if @merge_result

        root_operation = start_runtime_session!
        @merge_result = super
        complete_runtime_session!(root_operation, @merge_result)
        @merge_result
      rescue StandardError => e
        fail_runtime_session!(root_operation, e)
        raise
      end

      # Perform the merge and return detailed results including debug info.
      #
      # @return [Hash] Hash containing :content, :statistics, :decisions
      def merge_with_debug
        result_obj = merge_result
        template_analysis_debug = {
          valid: @template_analysis.valid?,
          nodes: @template_analysis.nodes.size,
          freeze_blocks: @template_analysis.freeze_blocks.size
        }
        dest_analysis_debug = {
          valid: @dest_analysis.valid?,
          nodes: @dest_analysis.nodes.size,
          freeze_blocks: @dest_analysis.freeze_blocks.size
        }

        {
          content: result_obj.to_bash,
          debug: {
            template_nodes: template_analysis_debug[:nodes],
            dest_nodes: dest_analysis_debug[:nodes],
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            resolution_mode: @resolution_mode,
            corruption_handling: @corruption_handling,
            freeze_token: @freeze_token,
            runtime_operation_count: runtime_session&.operations&.size || 0,
            runtime_diagnostic_count: runtime_session&.diagnostics&.size || 0
          },
          runtime: runtime_session&.to_h,
          statistics: result_obj.statistics,
          decisions: result_obj.decision_summary,
          template_analysis: template_analysis_debug,
          dest_analysis: dest_analysis_debug
        }
      end

      # Check if both files were parsed successfully.
      #
      # @return [Boolean]
      def valid?
        @template_analysis.valid? && @dest_analysis.valid?
      end

      # Get any parse errors from template or destination.
      #
      # @return [Array] Array of errors
      def errors
        errors = []
        errors.concat(@template_analysis.errors.map { |e| { source: :template, error: e } })
        errors.concat(@dest_analysis.errors.map { |e| { source: :destination, error: e } })
        errors
      end

      protected

      # @return [Class] The analysis class for Bash files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token
      def default_freeze_token
        'bash-merge'
      end

      # No separate resolver — SmartMerger handles merge logic directly
      # (following prism-merge's paradigm of section-based inline merging)
      # @return [Class, nil]
      def resolver_class
        nil
      end

      # @return [Class] The result class for Bash files
      def result_class
        MergeResult
      end

      # @return [Class] The template parse error class for Bash
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for Bash
      def destination_parse_error_class
        DestinationParseError
      end

      # Perform section-based merge directly (no ConflictResolver delegation).
      #
      # This follows prism-merge's paradigm: the SmartMerger itself owns the
      # merge algorithm. Signature maps store ALL occurrences of each signature,
      # and nodes are matched positionally (1:1 in order) when duplicates exist.
      #
      # Algorithm:
      #   1. Build signature → [node_info, ...] maps for both files
      #   2. Walk dest nodes in order; for each, find the next unconsumed
      #      template node with the same signature (sequential matching)
      #   3. Emit the preferred version (or dest-only if no match)
      #   4. Walk remaining unconsumed template nodes; emit as template-only
      #      if add_template_only_nodes is set
      #
      # @return [MergeResult] The merge result
      def perform_merge
        template_nodes = @template_analysis.nodes
        dest_nodes = @dest_analysis.nodes

        emitter = Emitter.new
        @emitted_preserved_line_numbers = Hash.new { |hash, key| hash[key] = [] }

        emit_root_boundary_to(emitter, :preamble)

        # Build signature maps: sig → [{node:, index:}, ...]
        template_by_sig = build_indexed_signature_map(template_nodes, @template_analysis)

        # Track which individual template node indices have been consumed.
        consumed_template_indices = ::Set.new

        # Per-signature cursor so duplicate signatures match 1:1 in order.
        sig_cursor = Hash.new(0)

        # Pre-compute position-aware trailing groups for template-only nodes.
        dest_sigs = ::Set.new
        dest_nodes.each do |n|
          sig = @dest_analysis.generate_signature(n)
          dest_sigs << sig if sig
        end

        trailing_groups, all_matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: template_nodes,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { @template_analysis.generate_signature(node) },
          add_template_only_nodes: @add_template_only_nodes
        )

        # Emit prefix template-only nodes (before first matched template node)
        emit_prefix_trailing_group(trailing_groups, consumed_template_indices) do |info|
          emit_node_to(emitter, info[:node], @template_analysis)
        end

        # Phase 1 — Walk destination nodes in order, preserving their positions.
        dest_nodes.each do |dest_node|
          dest_sig = @dest_analysis.generate_signature(dest_node)

          # Freeze blocks from destination are always preserved verbatim.
          if dest_node.is_a?(FreezeNode) || (dest_node.respond_to?(:is_a?) && dest_node.is_a?(Ast::Merge::Freezable))
            emitter.emit_raw_lines(dest_node.respond_to?(:lines) ? dest_node.lines : [])
            next
          end

          if dest_sig && template_by_sig.key?(dest_sig)
            # Find the next unconsumed template node with this signature.
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
              consumed_template_indices << template_info[:index]
              sig_cursor[dest_sig] = cursor + 1

              # Emit based on preference
              emit_preferred(emitter, template_node, dest_node)
            else
              # All template copies of this signature consumed — keep dest copy
              handle_destination_only_node(emitter, dest_node)
            end
          else
            # Destination-only node — always keep
            handle_destination_only_node(emitter, dest_node)
          end

          # Flush interior trailing groups that are ready
          flush_ready_trailing_groups(
            trailing_groups: trailing_groups,
            matched_indices: all_matched_indices,
            consumed_indices: consumed_template_indices
          ) { |info| emit_node_to(emitter, info[:node], @template_analysis) }
        end

        # Emit remaining trailing groups (tail + safety net)
        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_template_indices
        ) { |info| emit_node_to(emitter, info[:node], @template_analysis) }

        emit_root_boundary_to(emitter, :postlude)

        # Transfer emitter output to result
        @emitter = emitter
        collapse_cross_source_preamble_prefixes!(emitter)
        transfer_emitter_output(@result)

        @result
      end

      # Build the result (no-arg constructor for Bash)
      def build_result
        MergeResult.new
      end

      private

      def start_runtime_session!
        start_runtime_root_session!(
          surface_kind: :bash_document,
          declared_language: :bash,
          effective_language: :bash,
          operation_id: 'bash-document-root',
          delegate_name: 'bash-shell',
          policy_context: {
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          },
          metadata: { merger: self.class.name },
          options: {
            preference: @preference,
            add_template_only_nodes: @add_template_only_nodes,
            remove_template_missing_nodes: @remove_template_missing_nodes,
            resolution_mode: @resolution_mode,
            unresolved_policy: @unresolved_policy.to_h
          },
          language_chain: [:bash],
          delegate_metadata: { merger: self.class.name }
        )
      end

      def complete_runtime_session!(root_operation, merge_result)
        complete_runtime_root_session!(
          root_operation: root_operation,
          replacement_text: merge_result.to_bash,
          unresolved_cases: merge_result.unresolved_cases,
          metadata: {
            stats: merge_result.statistics,
            decisions: merge_result.decision_summary
          }
        )
      end

      def fail_runtime_session!(root_operation, error)
        fail_runtime_root_session!(
          root_operation: root_operation,
          error: error,
          kind: :merge_failed
        )
      end

      # Build a signature map that preserves ALL occurrences per signature,
      # keyed by index for sequential consumption.
      #
      # @param nodes [Array<NodeWrapper>] Parsed nodes
      # @param analysis [FileAnalysis] Analysis for signature generation
      # @return [Hash{Array => Array<Hash>}] sig → [{node:, index:}, ...]
      def build_indexed_signature_map(nodes, analysis)
        map = Hash.new { |h, k| h[k] = [] }
        nodes.each_with_index do |node, idx|
          sig = analysis.generate_signature(node)
          map[sig] << { node: node, index: idx } if sig
        end
        map
      end

      # Override hook: freeze nodes are treated as matched for trailing group purposes.
      def trailing_group_node_matched?(node, _signature)
        node.is_a?(FreezeNode) || (node.respond_to?(:is_a?) && node.is_a?(Ast::Merge::Freezable))
      end

      def emit_root_boundary_to(emitter, kind)
        root_boundary_analysis_candidates.find do |analysis|
          lines = root_boundary_lines_for(kind, analysis)
          next if lines.empty?
          next if skip_root_boundary_lines?(kind, analysis, lines)

          start_line = kind == :preamble ? 1 : (analysis.lines.length - lines.length + 1)
          emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, start_line))
          true
        end
      end

      STANDALONE_BASH_COMMENT_LINE_RE = /\A\s*#(?!!).*\z/
      private_constant :STANDALONE_BASH_COMMENT_LINE_RE

      def collapse_cross_source_preamble_prefixes!(emitter)
        template_comments, = leading_standalone_comment_run(@template_analysis.source.to_s)
        return emitter if template_comments.empty?

        leading_entries, remainder_entries = leading_standalone_comment_entries(emitter)
        merged_comments = leading_entries.map { |entry| entry[:line] }
        return emitter if merged_comments.empty?

        destination_specific_comments = merged_comments.reject { |line| template_comments.include?(line) }
        return emitter if destination_specific_comments.empty?

        should_heal = ::Ast::Merge::Healer.handle(
          mode: @corruption_handling,
          kind: :duplicate_template_preamble_prefix,
          message: 'merged Bash preamble begins with duplicated template-owned comment lines',
          prefix: '[bash-merge]',
          error_class: Bash::Merge::CorruptionDetectedError,
          warner: lambda { |formatted|
            DebugLogger.debug_warning(formatted, {
                                        template_comment_lines: template_comments.length,
                                        merged_comment_lines: merged_comments.length,
                                        destination_specific_comment_lines: destination_specific_comments.length
                                      })
          }
        )
        return emitter unless should_heal

        destination_specific_entries = leading_entries.reject { |entry| template_comments.include?(entry[:line]) }
        trimmed_remainder_entries = remainder_entries.drop_while { |entry| entry[:line].strip.empty? }
        rebuilt_entries = destination_specific_entries.dup
        rebuilt_entries << { line: '', metadata: {} } if rebuilt_entries.any? && trimmed_remainder_entries.any?
        rebuilt_entries.concat(trimmed_remainder_entries)

        emitter.lines.replace(rebuilt_entries.map { |entry| entry[:line] })
        emitter.line_metadata.replace(rebuilt_entries.map { |entry| entry[:metadata] })
        emitter
      end

      def leading_standalone_comment_run(text)
        lines = text.to_s.split("\n", -1)
        comment_lines = []
        index = 0

        while index < lines.length
          line = lines[index]
          if line.strip.empty?
            comment_lines << line if comment_lines.any?
            index += 1
            next
          end

          break unless STANDALONE_BASH_COMMENT_LINE_RE.match?(line)

          comment_lines << line
          index += 1
        end

        [comment_lines, lines.drop(index).join("\n")]
      end

      def leading_standalone_comment_entries(emitter)
        entries = emitter.lines.each_with_index.map do |line, idx|
          { line: line.to_s, metadata: emitter.line_metadata[idx].to_h }
        end

        leading_entries = []
        index = 0
        while index < entries.length
          line = entries[index][:line]
          if line.strip.empty?
            leading_entries << entries[index] if leading_entries.any?
            index += 1
            next
          end

          break unless STANDALONE_BASH_COMMENT_LINE_RE.match?(line)

          leading_entries << entries[index]
          index += 1
        end

        [leading_entries, entries.drop(index)]
      end

      def handle_destination_only_node(emitter, dest_node)
        if remove_template_missing_nodes
          lines = removed_destination_node_lines_for(dest_node, @dest_analysis)
          if lines.any?
            start_line = emission_start_line_for(dest_node, @dest_analysis)
            emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(@dest_analysis, start_line))
            mark_removed_destination_preserved_lines(dest_node, @dest_analysis)
          end
        else
          emit_node_to(emitter, dest_node, @dest_analysis)
        end
      end

      def preferred_root_boundary_analysis
        pref = @preference.is_a?(Hash) ? (@preference[:default] || :destination) : @preference
        pref == :template ? @template_analysis : @dest_analysis
      end

      def root_boundary_analysis_candidates
        preferred = preferred_root_boundary_analysis
        fallback = preferred.equal?(@template_analysis) ? @dest_analysis : @template_analysis

        analyses = [preferred]
        analyses << fallback if @add_template_only_nodes && !first_statement_has_leading_comments?(preferred)
        analyses.compact.uniq
      end

      def root_boundary_lines_for(kind, analysis)
        super(kind, analysis, owners: analysis.nodes, fallback_to_owner_bounds: true)
      end

      def emission_start_line_for(node, analysis)
        region_start = region_start_line(leading_region_for(node, analysis))
        comment_start = analysis.comment_tracker.leading_comments_before(node.start_line).first&.fetch(:line, nil)
        preceding_blank_line_start(region_start || comment_start || node.start_line, analysis)
      end

      def root_boundary_owner_start_line_for(node, analysis)
        return node.start_line unless region_present?(leading_region_for(node, analysis))

        emission_start_line_for(node, analysis)
      end

      # Emit the preferred version of a matched node pair.
      def emit_preferred(emitter, template_node, dest_node)
        pref = preference_for_pair(template_node, dest_node)
        record_unresolved_choice(template_node: template_node, dest_node: dest_node, provisional_winner: pref)
        if pref == :destination
          emit_retained_leading_gap_to(emitter, dest_node, @dest_analysis)
          emit_node_to(emitter, dest_node, @dest_analysis)
        else
          comment_source_node, comment_source_analysis = preferred_comment_source_for(template_node, dest_node)
          inline_comment = preferred_inline_comment_for(template_node, dest_node)
          emit_retained_leading_gap_to(emitter, dest_node, @dest_analysis)
          emit_node_to(
            emitter,
            template_node,
            @template_analysis,
            comment_source_node: comment_source_node,
            comment_source_analysis: comment_source_analysis,
            inline_comment: inline_comment
          )
        end
      end

      def preferred_comment_source_for(template_node, dest_node)
        return [template_node, @template_analysis] if node_has_leading_comments?(template_node, @template_analysis)
        return [dest_node, @dest_analysis] if node_has_leading_comments?(dest_node, @dest_analysis)

        [template_node, @template_analysis]
      end

      def first_statement_has_leading_comments?(analysis)
        first_statement = Array(analysis&.nodes).first
        return false unless first_statement

        node_has_leading_comments?(first_statement, analysis)
      end

      def node_has_leading_comments?(node, analysis)
        attachment = analysis.comment_attachment_for(node)
        leading_region = attachment&.leading_region
        return false unless leading_region&.respond_to?(:nodes)

        leading_region.nodes.any? do |comment_node|
          comment_node.respond_to?(:comment?) ? comment_node.comment? : true
        end
      end

      def leading_comment_lines_for(node, analysis)
        return [] unless node.respond_to?(:start_line) && node.start_line

        start_line = emission_start_line_for(node, analysis)
        return [] unless start_line && start_line < node.start_line

        lines = (start_line...node.start_line).filter_map { |line_number| analysis.line_at(line_number) }
        comments, = leading_standalone_comment_run(lines.join)
        comments
      end

      def skip_root_boundary_lines?(kind, analysis, lines)
        return false unless kind == :preamble
        return false unless analysis.equal?(@template_analysis)
        return false unless preferred_root_boundary_analysis.equal?(@template_analysis)

        template_comments, = leading_standalone_comment_run(lines.join)
        return false if template_comments.empty?

        destination_first_statement = Array(@dest_analysis&.nodes).first
        return false unless destination_first_statement

        template_comments == leading_comment_lines_for(destination_first_statement, @dest_analysis)
      end

      def preferred_inline_comment_for(template_node, dest_node)
        return unless safe_inline_comment_transfer?(template_node, dest_node)

        template_inline_comment = inline_comment_for(template_node, @template_analysis)
        return if template_inline_comment

        inline_comment_for(dest_node, @dest_analysis)
      end

      def inline_comment_for(node, analysis)
        return unless node.respond_to?(:end_line) && node.end_line

        analysis.comment_tracker.inline_comment_at(node.end_line)
      end

      def safe_inline_comment_transfer?(template_node, dest_node)
        single_line_node?(template_node) &&
          single_line_node?(dest_node) &&
          safe_inline_comment_node?(template_node) &&
          safe_inline_comment_node?(dest_node)
      end

      def single_line_node?(node)
        node.respond_to?(:start_line) &&
          node.respond_to?(:end_line) &&
          node.start_line &&
          node.end_line &&
          node.start_line == node.end_line
      end

      def safe_inline_comment_node?(node)
        (node.respond_to?(:command?) && node.command?) ||
          (node.respond_to?(:variable_assignment?) && node.variable_assignment?)
      end

      def promoted_inline_comment_lines_for(node, analysis)
        inline_comment = inline_comment_for(node, analysis)
        return [] unless inline_comment && single_line_node?(node) && safe_inline_comment_node?(node)

        line = promoted_inline_comment_line_for(node, analysis, inline_comment)
        line ? [line] : []
      end

      def promoted_inline_comment_line_for(node, analysis, inline_comment)
        raw_line = analysis.line_at(node.start_line)
        return unless raw_line

        "#{raw_line[/\A\s*/]}#{inline_comment[:raw].sub(/\A\s+/, '')}"
      end

      def removed_destination_node_lines_for(node, analysis)
        removed_owner_preserved_lines_for(
          node,
          analysis,
          owners: analysis.nodes,
          inline_lines: promoted_inline_comment_lines_for(node, analysis)
        )
      end

      def mark_removed_destination_preserved_lines(node, analysis)
        @emitted_preserved_line_numbers[analysis.object_id].concat(
          removed_owner_preserved_line_numbers_for(node, analysis, owners: analysis.nodes)
        )
      end

      # Determine preference for a matched pair, respecting per-type overrides.
      def preference_for_pair(template_node, dest_node)
        return @preference unless @preference.is_a?(Hash)

        typed_template = @node_typing ? ::Ast::Merge::NodeTyping.process(template_node, @node_typing) : template_node
        typed_dest = @node_typing ? ::Ast::Merge::NodeTyping.process(dest_node, @node_typing) : dest_node

        if ::Ast::Merge::NodeTyping.typed_node?(typed_template)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_template)
          return @preference.fetch(merge_type) { @preference.fetch(:default, :destination) } if merge_type
        end

        if ::Ast::Merge::NodeTyping.typed_node?(typed_dest)
          merge_type = ::Ast::Merge::NodeTyping.merge_type_for(typed_dest)
          return @preference.fetch(merge_type) { @preference.fetch(:default, :destination) } if merge_type
        end

        @preference.fetch(:default, :destination)
      end

      def record_unresolved_choice(template_node:, dest_node:, provisional_winner:)
        return unless unresolved_mode?
        return unless template_node && dest_node

        template_text = template_node.text
        dest_text = dest_node.text

        identifier = resolution_identifier(template_node, dest_node)
        surface_path = resolution_surface_path(template_node, dest_node)
        record_unresolved_node_choice(
          result: @result,
          template_node: template_node,
          destination_node: dest_node,
          template_text: template_text,
          destination_text: dest_text,
          provisional_winner: provisional_winner,
          case_prefix: 'bash',
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
        unresolved_identifier_for_nodes(
          dest_node,
          template_node,
          methods: %i[function_name variable_name command_name]
        )
      end

      def resolution_surface_path(template_node, dest_node)
        identifier = resolution_identifier(template_node, dest_node)
        unresolved_surface_path_for(
          unresolved_typed_path_segment(dest_node.type, identifier: identifier, node: dest_node, fallback: nil)
        )
      end

      # Emit a single node (with its leading comments) to an emitter.
      def emit_node_to(emitter, node, analysis, comment_source_node: node, comment_source_analysis: analysis,
                       inline_comment: nil)
        # Emit the node content
        return unless node.start_line && node.end_line

        emit_leading_segment_to(emitter, comment_source_node, comment_source_analysis)
        lines = (node.start_line..node.end_line).filter_map { |ln| analysis.line_at(ln) }
        emitter.emit_raw_lines(
          apply_inline_comment(lines, inline_comment),
          metadata: emitter_block_metadata(analysis, node.start_line)
        )
      end

      def apply_inline_comment(lines, inline_comment)
        return lines if inline_comment.nil? || lines.empty?

        updated_lines = lines.dup
        updated_lines[-1] = "#{updated_lines[-1].rstrip} #{inline_comment[:raw].sub(/\A\s+/, '')}"
        updated_lines
      end

      def emit_leading_segment_to(emitter, node, analysis)
        line_numbers = leading_segment_line_numbers_for(node, analysis, owners: analysis.nodes)
        emitted_line_numbers = @emitted_preserved_line_numbers[analysis.object_id]
        line_numbers = line_numbers.reject { |line_number| emitted_line_numbers.include?(line_number) }
        return if line_numbers.empty?

        lines = line_numbers.filter_map { |line_number| analysis.line_at(line_number) }
        start_line = line_numbers.first
        emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, start_line))
      end

      def emit_retained_leading_gap_to(emitter, node, analysis)
        lines = retained_owner_leading_gap_lines_for(node, analysis, owners: analysis.nodes)
        return if lines.empty?

        gap = retained_owner_leading_gap_for(node, analysis)
        emitter.emit_raw_lines(lines, metadata: emitter_block_metadata(analysis, gap.start_line))
      end
    end
  end
end
