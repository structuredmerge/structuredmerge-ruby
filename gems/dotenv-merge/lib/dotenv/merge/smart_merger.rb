# frozen_string_literal: true

module Dotenv
  module Merge
    # Smart merger for dotenv files.
    # Intelligently combines template and destination dotenv files by matching
    # environment variable names and preserving customizations.
    #
    # @example Basic merge
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #   puts result.to_s
    #
    # @example With options
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true,
    #   )
    #   result = merger.merge
    #
    # @example With node_typing for per-node-type preferences
    #   merger = SmartMerger.new(template, dest,
    #     node_typing: { "EnvLine" => ->(n) { NodeTyping.with_merge_type(n, :secret) } },
    #     preference: { default: :destination, secret: :template })
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      include Ast::Merge::TrailingGroups::DestIterate
      include Ast::Merge::CommentLayoutEmissionSupport

      attr_reader :corruption_handling

      # Initialize a new SmartMerger
      #
      # @param template_content [String] Content of the template dotenv file
      # @param dest_content [String] Content of the destination dotenv file
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param preference [Symbol, Hash] :destination, :template, or per-type Hash
      # @param add_template_only_nodes [Boolean] Whether to add template-only env vars
      #   (default: false)
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination-only
      #   env vars that do not exist in the template (default: false)
      # @param corruption_handling [Symbol] How to handle detected historical
      #   duplicate-prefix corruption (:heal, :warn, :error, :skip)
      # @param freeze_token [String] Token for freeze block markers
      #   (default: "dotenv-merge")
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #   for per-node-type merge preferences
      # @param options [Hash] Additional options for forward compatibility
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
          remove_template_missing_nodes: remove_template_missing_nodes,
          freeze_token: freeze_token,
          match_refiner: match_refiner,
          regions: regions,
          region_placeholder: region_placeholder,
          node_typing: node_typing,
          **options
        )
      end

      protected

      # @return [Class] The analysis class for dotenv files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token
      def default_freeze_token
        'dotenv-merge'
      end

      # @return [Class, nil] No separate resolver class for dotenv
      def resolver_class
        nil
      end

      # @return [Class, nil] Result class (built with analysis args)
      def result_class
        nil
      end

      # Build the result with required analysis arguments
      def build_result
        MergeResult.new(@template_analysis, @dest_analysis)
      end

      # @return [Class] The template parse error class for dotenv
      def template_parse_error_class
        ParseError
      end

      # @return [Class] The destination parse error class for dotenv
      def destination_parse_error_class
        ParseError
      end

      # Perform the dotenv-specific merge with structural-owner alignment.
      #
      # @return [MergeResult] The merge result
      def perform_merge
        template_nodes = @template_analysis.structural_owners
        dest_nodes = @dest_analysis.structural_owners

        emit_root_boundary(:preamble)

        template_index = build_match_index(template_nodes, @template_analysis)
        dest_sigs = destination_signature_set(dest_nodes, @dest_analysis)
        trailing_groups, matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: template_nodes,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { freeze_node?(node) ? nil : @template_analysis.generate_signature(node) },
          add_template_only_nodes: @add_template_only_nodes
        )

        matched_template_indices = Set.new
        consumed_indices = Set.new

        emit_prefix_trailing_group(trailing_groups, consumed_indices) do |info|
          add_template_only_node(info[:node], template_nodes.index(info[:node]))
        end

        dest_nodes.each do |dest_node|
          if freeze_node?(dest_node)
            @result.add_freeze_block(dest_node)
            next
          end

          match_key = @dest_analysis.generate_signature(dest_node)
          template_match = find_unmatched(template_index[match_key], matched_template_indices)

          if template_match
            matched_template_indices << template_match[:index]
            consumed_indices << template_match[:index]
            process_match(template_match[:node], dest_node)
            flush_ready_trailing_groups(
              trailing_groups: trailing_groups,
              matched_indices: matched_indices,
              consumed_indices: consumed_indices
            ) do |info|
              add_template_only_node(info[:node], info[:index])
            end
          else
            process_dest_only(dest_node, dest_nodes.index(dest_node))
          end
        end

        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_indices
        ) do |info|
          add_template_only_node(info[:node], info[:index])
        end

        emit_root_boundary(:postlude)

        merged_content = @result.to_s
        healed_content = collapse_cross_source_preamble_prefixes(merged_content)
        update_result_content(@result, healed_content) if healed_content != merged_content

        @result
      end

      private

      def build_match_index(nodes, analysis)
        index = Hash.new { |h, k| h[k] = [] }
        nodes.each_with_index do |node, idx|
          next if freeze_node?(node)

          key = analysis.generate_signature(node)
          index[key] << { node: node, index: idx }
        end
        index
      end

      def destination_signature_set(nodes, analysis)
        nodes.each_with_object(Set.new) do |node, signatures|
          next if freeze_node?(node)

          signatures << analysis.generate_signature(node)
        end
      end

      def find_unmatched(entries, matched_indices)
        return unless entries

        entries.find { |entry| !matched_indices.include?(entry[:index]) }
      end

      def trailing_group_node_matched?(node, _signature)
        freeze_node?(node)
      end

      def process_match(template_stmt, dest_stmt)
        resolved_pref = resolve_preference(template_stmt, dest_stmt)

        case resolved_pref
        when :template
          emit_template_preferred_match(template_stmt, dest_stmt)
        else
          @result.add_raw(node_lines_for(dest_stmt, @dest_analysis), decision: MergeResult::DECISION_DESTINATION)
        end
      end

      # Resolve preference for a matched pair
      # @param template_stmt [Object] Template statement
      # @param dest_stmt [Object] Destination statement
      # @return [Symbol] :template or :destination
      def resolve_preference(template_stmt, dest_stmt)
        return @preference if @preference.is_a?(Symbol)

        # Hash preference - check for node_typing-based merge_types
        if @preference.is_a?(Hash)
          # Apply node_typing if configured
          typed_template = apply_node_typing(template_stmt)
          apply_node_typing(dest_stmt)

          # Check template merge_type first
          if Ast::Merge::NodeTyping.typed_node?(typed_template)
            merge_type = typed_template.merge_type
            return @preference[merge_type] if @preference.key?(merge_type)
          end

          # Fall back to default
          return @preference[:default] || :destination
        end

        :destination
      end

      # Apply node typing to a statement if node_typing is configured
      # @param stmt [Object] The statement
      # @return [Object] The statement, possibly wrapped with merge_type
      def apply_node_typing(stmt)
        return stmt unless @node_typing
        return stmt unless stmt

        # Check by class name
        type_key = stmt.class.name&.split('::')&.last
        callable = @node_typing[type_key] || @node_typing[type_key&.to_sym]
        return callable.call(stmt) if callable

        stmt
      end

      def add_template_only_node(stmt, _index)
        return unless @add_template_only_nodes
        return if freeze_node?(stmt)

        # Intentional product behavior: template-only dotenv additions do not
        # import surrounding template comment context. The matrix marks those
        # comment-bearing template-only cases as out of scope unless this policy
        # is changed deliberately.
        @result.add_raw(
          node_lines_for(
            stmt,
            @template_analysis,
            include_leading_segment: false,
            include_interstitial_trailing_segment: false
          ),
          decision: MergeResult::DECISION_ADDED
        )
      end

      def process_dest_only(dest_stmt, _dest_index)
        if remove_destination_only_assignment?(dest_stmt)
          lines = removed_destination_comment_lines_for(dest_stmt)
          @result.add_raw(lines, decision: MergeResult::DECISION_DESTINATION) if lines.any?
        else
          @result.add_raw(node_lines_for(dest_stmt, @dest_analysis), decision: MergeResult::DECISION_DESTINATION)
        end
      end

      def emit_template_preferred_match(template_stmt, dest_stmt)
        comment_source_node, comment_source_analysis = preferred_comment_source_for(template_stmt, dest_stmt)
        inline_comment = preferred_inline_comment_for(template_stmt, dest_stmt)
        @result.add_raw(
          node_lines_for(
            template_stmt,
            @template_analysis,
            comment_source_node: comment_source_node,
            comment_source_analysis: comment_source_analysis,
            inline_comment: inline_comment
          ),
          decision: MergeResult::DECISION_TEMPLATE
        )
      end

      def preferred_comment_source_for(template_stmt, dest_stmt)
        return [dest_stmt, @dest_analysis] if node_has_leading_comments?(dest_stmt, @dest_analysis)
        return [template_stmt, @template_analysis] if node_has_leading_comments?(template_stmt, @template_analysis)

        [template_stmt, @template_analysis]
      end

      def node_has_leading_comments?(node, analysis)
        leading_segment_lines_for(node, analysis).any? { |line| !line.to_s.strip.empty? }
      end

      def preferred_inline_comment_for(template_stmt, dest_stmt)
        return unless preserve_destination_inline_comment_for_template_match?(template_stmt, dest_stmt)

        destination_inline_comment_for(dest_stmt)
      end

      def preserve_destination_inline_comment_for_template_match?(template_stmt, dest_stmt)
        return false unless template_stmt.is_a?(EnvLine) && dest_stmt.is_a?(EnvLine)
        return false unless template_stmt.assignment? && dest_stmt.assignment?
        return false unless destination_inline_comment_for(dest_stmt)

        template_inline_comment_for(template_stmt).nil?
      end

      def remove_destination_only_assignment?(stmt)
        @remove_template_missing_nodes && stmt.is_a?(EnvLine) && stmt.assignment?
      end

      def destination_inline_comment_for(stmt)
        @dest_analysis.comment_tracker.inline_comment_at(stmt.line_number)
      end

      def template_inline_comment_for(stmt)
        @template_analysis.comment_tracker.inline_comment_at(stmt.line_number)
      end

      def freeze_node?(node)
        node.is_a?(FreezeNode) || (node.respond_to?(:is_a?) && node.is_a?(Ast::Merge::Freezable))
      end

      def emit_root_boundary(kind)
        lines = root_boundary_lines_for(kind, @dest_analysis)
        return if lines.empty?

        decision = MergeResult::DECISION_DESTINATION
        @result.add_raw(lines, decision: decision)
      end

      def root_boundary_lines_for(kind, analysis)
        super(kind, analysis, owners: analysis.structural_owners, fallback_to_owner_bounds: true)
      end

      def emission_start_line_for(node, analysis)
        region_start = region_start_line(leading_region_for(node, analysis))
        preamble_start = analysis.comment_augmenter.preamble_region&.start_line if first_structural_owner?(node, analysis)
        preceding_blank_line_start(region_start || preamble_start || node.start_line, analysis)
      end

      def root_boundary_owner_start_line_for(node, analysis)
        emission_start_line_for(node, analysis)
      end

      def first_structural_owner?(node, analysis)
        Array(analysis.structural_owners).first.equal?(node)
      end

      def node_lines_for(
        node,
        analysis,
        comment_source_node: node,
        comment_source_analysis: analysis,
        inline_comment: nil,
        include_leading_segment: true,
        include_interstitial_trailing_segment: true
      )
        return freeze_block_lines_for(node) if freeze_node?(node)

        leading_lines = if include_leading_segment
                          leading_segment_lines_for(comment_source_node,
                                                    comment_source_analysis)
                        else
                          []
                        end
        node_lines = (node.start_line..node.end_line).filter_map { |line_number| raw_line_at(analysis, line_number) }
        trailing_lines = if include_interstitial_trailing_segment
                           interstitial_trailing_segment_lines_for(node,
                                                                   analysis)
                         else
                           []
                         end
        leading_lines + apply_inline_comment(node_lines, inline_comment) + trailing_lines
      end

      def removed_destination_comment_lines_for(node)
        inline_lines = []

        if (inline_comment = destination_inline_comment_for(node))
          inline_lines << promoted_inline_comment_line_for(node, @dest_analysis, inline_comment)
        end

        removed_owner_preserved_lines_for(
          node,
          @dest_analysis,
          owners: @dest_analysis.structural_owners,
          inline_lines: inline_lines
        )
      end

      def interstitial_trailing_segment_lines_for(node, analysis)
        interstitial_trailing_region_lines_for(node, analysis, owners: analysis.structural_owners)
      end

      def next_structural_owner_for(node, analysis)
        owners = Array(analysis.structural_owners)
        index = owners.index(node)
        return unless index

        owners[index + 1]
      end

      def apply_inline_comment(lines, inline_comment)
        return lines if inline_comment.nil? || lines.empty?

        updated_lines = lines.dup
        updated_lines[-1] = "#{updated_lines[-1].rstrip} #{inline_comment[:raw].sub(/\A\s+/, '')}"
        updated_lines
      end

      def promoted_inline_comment_line_for(node, analysis, inline_comment)
        raw_line = raw_line_at(analysis, node.start_line)
        return unless raw_line

        "#{raw_line[/\A\s*/]}#{inline_comment[:raw].sub(/\A\s+/, '')}"
      end

      def freeze_block_lines_for(node)
        node.lines.map { |line| line.respond_to?(:raw) ? line.raw : line.to_s }
      end

      STANDALONE_DOTENV_COMMENT_LINE_RE = /\A\s*#.*\z/
      private_constant :STANDALONE_DOTENV_COMMENT_LINE_RE

      def collapse_cross_source_preamble_prefixes(content)
        template_comments, = leading_standalone_comment_run(@template_content.to_s)
        return content if template_comments.empty?

        merged_comments, remainder = leading_standalone_comment_run(content)
        return content if merged_comments.empty?

        template_tally = template_comments.tally
        merged_tally = merged_comments.tally
        duplicated_template_prefix = template_tally.any? do |line, count|
          merged_tally.fetch(line, 0) > count
        end
        return content unless duplicated_template_prefix

        destination_specific_comments = merged_comments.reject { |line| template_comments.include?(line) }
        return content if destination_specific_comments.empty?

        should_heal = ::Ast::Merge::Healer.handle(
          mode: @corruption_handling,
          kind: :duplicate_template_preamble_prefix,
          message: 'merged dotenv preamble begins with duplicated template-owned comment lines',
          prefix: '[dotenv-merge]',
          error_class: Dotenv::Merge::CorruptionDetectedError,
          warner: lambda { |formatted|
            DebugLogger.debug_warning(formatted, {
                                        template_comment_lines: template_comments.length,
                                        merged_comment_lines: merged_comments.length,
                                        destination_specific_comment_lines: destination_specific_comments.length
                                      })
          }
        )
        return content unless should_heal

        remainder = remainder.sub(/\A(?:\s*\n)+/, '')
        rebuilt = destination_specific_comments.join("\n")
        return rebuilt if remainder.empty?

        "#{rebuilt}\n\n#{remainder}"
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

          break unless STANDALONE_DOTENV_COMMENT_LINE_RE.match?(line)

          comment_lines << line
          index += 1
        end

        [comment_lines, lines.drop(index).join("\n")]
      end

      def raw_line_at(analysis, line_number)
        line = analysis.line_at(line_number)
        line.respond_to?(:raw) ? line.raw : line
      end

      def leading_segment_anchor_line_for(node, analysis, owners: nil, leading_region: nil)
        region_start = super(node, analysis, owners: owners || analysis.structural_owners, leading_region: leading_region)
        preamble_start = analysis.comment_augmenter.preamble_region&.start_line if first_structural_owner?(node, analysis)
        region_start || preamble_start
      end

      def source_line_at(analysis, line_number)
        raw_line_at(analysis, line_number)
      end
    end
  end
end
