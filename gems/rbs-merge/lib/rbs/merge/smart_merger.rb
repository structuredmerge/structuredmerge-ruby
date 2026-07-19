# frozen_string_literal: true

module Rbs
  module Merge
    # Orchestrates the smart merge process for RBS type signature files.
    # Uses FileAnalysis, FileAligner, ConflictResolver, and MergeResult to
    # merge two RBS files intelligently.
    #
    # SmartMerger provides flexible configuration for different merge scenarios.
    # When matching class or module definitions are found in both files, the merger
    # can perform recursive merging of their members.
    #
    # @example Basic merge (destination customizations preserved)
    #   merger = SmartMerger.new(template_content, dest_content)
    #   result = merger.merge
    #
    # @example Template updates win
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #   result = merger.merge
    #
    # @example Custom signature matching
    #   sig_gen = ->(node) { [:decl, node.name.to_s] }
    #   merger = SmartMerger.new(
    #     template_content,
    #     dest_content,
    #     signature_generator: sig_gen
    #   )
    #
    # @example With node_typing for per-node-type preferences
    #   merger = SmartMerger.new(template, dest,
    #     node_typing: { "ClassDecl" => ->(n) { NodeTyping.with_merge_type(n, :model) } },
    #     preference: { default: :destination, model: :template })
    #
    # @see FileAnalysis
    # @see FileAligner
    # @see ConflictResolver
    # @see MergeResult
    class SmartMerger < ::Ast::Merge::SmartMergerBase
      attr_reader :corruption_handling

      # Creates a new SmartMerger for intelligent RBS file merging.
      #
      # @param template_content [String] Template RBS source code
      # @param dest_content [String] Destination RBS source code
      #
      # @param signature_generator [Proc, nil] Optional proc to generate custom node signatures.
      #   The proc receives an RBS declaration and should return one of:
      #   - An array representing the node's signature
      #   - `nil` to indicate the node should have no signature
      #   - The original node to fall through to default signature computation
      #
      # @param preference [Symbol, Hash] Controls which version to use when nodes
      #   have matching signatures but different content:
      #   - `:destination` (default) - Use destination version (preserves customizations)
      #   - `:template` - Use template version (applies updates)
      #   - Hash for per-type preferences
      #
      # @param add_template_only_nodes [Boolean] Controls whether to add nodes that only
      #   exist in template:
      #   - `false` (default) - Skip template-only nodes
      #   - `true` - Add template-only nodes to result
      # @param remove_template_missing_nodes [Boolean] Controls whether to remove
      #   destination-only declarations while promoting their leading comments
      # @param corruption_handling [Symbol] How to handle detected historical
      #   duplicate-prefix corruption (:heal, :warn, :error, :skip)
      #
      # @param freeze_token [String] Token to use for freeze block markers.
      #   Default: "rbs-merge" (looks for # rbs-merge:freeze / # rbs-merge:unfreeze)
      #
      # @param match_refiner [#call, nil] Match refiner for fuzzy matching
      # @param regions [Array<Hash>, nil] Region configurations for nested merging
      # @param region_placeholder [String, nil] Custom placeholder for regions
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #
      # @param max_recursion_depth [Integer, Float] Maximum depth for recursive body merging.
      #   Default: Float::INFINITY (no limit)
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
        max_recursion_depth: Float::INFINITY,
        **options
      )
        @max_recursion_depth = max_recursion_depth
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

      # @return [Class] The analysis class for RBS files
      def analysis_class
        FileAnalysis
      end

      # @return [String] The default freeze token
      def default_freeze_token
        'rbs-merge'
      end

      # @return [Class, nil] The resolver class for RBS files
      def resolver_class
        ConflictResolver
      end

      # @return [Class, nil] Result class (built with analysis args)
      def result_class
        nil
      end

      # @return [Class] The aligner class for RBS files
      def aligner_class
        FileAligner
      end

      # @return [Class] The template parse error class for RBS
      def template_parse_error_class
        TemplateParseError
      end

      # @return [Class] The destination parse error class for RBS
      def destination_parse_error_class
        DestinationParseError
      end

      # Build the result with required analysis arguments
      def build_result
        MergeResult.new(@template_analysis, @dest_analysis)
      end

      # Build the resolver with RBS-specific options
      def build_resolver
        ConflictResolver.new(
          preference: @preference,
          template_analysis: @template_analysis,
          dest_analysis: @dest_analysis,
          node_typing: @node_typing,
          remove_template_missing_nodes: @remove_template_missing_nodes
        )
      end

      # Build the aligner
      def build_aligner
        FileAligner.new(@template_analysis, @dest_analysis)
      end

      # Perform the RBS-specific merge with recursive body merging
      #
      # @return [MergeResult] The merge result
      def perform_merge
        alignment = @aligner.align

        DebugLogger.debug('Alignment complete', {
                            total_entries: alignment.size,
                            matches: alignment.count { |e| e[:type] == :match },
                            template_only: alignment.count { |e| e[:type] == :template_only },
                            dest_only: alignment.count { |e| e[:type] == :dest_only }
                          })

        emit_root_boundary(:preamble)
        process_alignment(alignment)
        emit_root_boundary(:postlude)

        merged_content = @result.to_s
        healed_content = collapse_cross_source_preamble_prefixes(merged_content)
        update_result_content(@result, healed_content) if healed_content != merged_content

        @result
      end

      private

      # Process alignment entries and build result
      # @param alignment [Array<Hash>] Alignment entries
      # @return [void]
      def process_alignment(alignment)
        prefix_template_only_entries = prefix_template_only_entries_for(alignment)

        prefix_template_only_entries.each do |entry|
          process_template_only(entry)
        end

        alignment.each do |entry|
          next if prefix_template_only_entries.include?(entry)

          case entry[:type]
          when :match
            process_match(entry)
          when :template_only
            process_template_only(entry)
          when :dest_only
            process_dest_only(entry)
          end
        end
      end

      def prefix_template_only_entries_for(alignment)
        first_match_template_index = alignment
                                     .select { |entry| entry[:type] == :match }
                                     .filter_map { |entry| entry[:template_index] }
                                     .min

        return [] unless first_match_template_index

        alignment.select do |entry|
          entry[:type] == :template_only &&
            entry[:template_index] &&
            entry[:template_index] < first_match_template_index
        end
      end

      def emit_root_boundary(kind)
        analysis, lines = preferred_root_boundary_lines(kind)
        return unless analysis
        return if lines.empty?
        return if skip_root_boundary_lines?(kind, analysis, lines)

        decision = analysis == @template_analysis ? MergeResult::DECISION_TEMPLATE : MergeResult::DECISION_DESTINATION
        @result.add_raw(lines, decision: decision)
      end

      def preferred_root_boundary_lines(kind)
        analyses = [preferred_root_boundary_analysis]
        fallback_analysis = analyses.first == @template_analysis ? @dest_analysis : @template_analysis
        if @add_template_only_nodes && !first_statement_has_leading_comments?(analyses.first)
          analyses << fallback_analysis
        end

        analyses.each do |analysis|
          lines = root_boundary_lines_for(kind, analysis)
          return [analysis, lines] if lines.any?
        end

        [nil, []]
      end

      def preferred_root_boundary_analysis
        pref = @preference.is_a?(Hash) ? (@preference[:default] || :destination) : @preference
        pref == :template ? @template_analysis : @dest_analysis
      end

      def skip_root_boundary_lines?(kind, analysis, lines)
        return false unless kind == :preamble
        return false unless analysis.equal?(@template_analysis)
        return false unless preferred_root_boundary_analysis.equal?(@template_analysis)

        template_comments, = leading_standalone_comment_run(lines.join("\n"))
        return false if template_comments.empty?

        destination_first_statement = first_statement_for(@dest_analysis)
        return false unless destination_first_statement

        destination_leading_comments = leading_comment_lines_for(destination_first_statement, @dest_analysis)
        return false if destination_leading_comments.empty?

        true
      end

      def root_boundary_lines_for(kind, analysis)
        return [] unless analysis&.respond_to?(:comment_augmenter)

        comment_only_lines = comment_only_boundary_lines_for(kind, analysis)
        return comment_only_lines if comment_only_lines.any?

        region = root_boundary_region(kind, analysis)
        return [] unless region_present?(region)

        start_line, end_line = root_boundary_range(kind, analysis, region)
        return [] unless start_line && end_line
        return [] if start_line > end_line

        (start_line..end_line).filter_map { |line_number| analysis.line_at(line_number) }
      end

      def comment_only_boundary_lines_for(kind, analysis)
        return [] unless kind == :preamble
        return [] unless Array(analysis.statements).empty?
        return [] unless analysis.respond_to?(:comment_nodes) && analysis.comment_nodes.any?

        analysis.lines.dup
      end

      def root_boundary_region(kind, analysis)
        augmenter = root_comment_augmenter_for(analysis)
        return unless augmenter

        kind == :preamble ? augmenter.preamble_region : augmenter.postlude_region
      end

      def root_comment_augmenter_for(analysis)
        @root_comment_augmenters ||= {}
        @root_comment_augmenters[analysis.object_id] ||= analysis.comment_augmenter(owners: analysis.statements)
      end

      def root_boundary_range(kind, analysis, region)
        statements = Array(analysis.statements).select do |statement|
          statement.respond_to?(:start_line) && statement.respond_to?(:end_line)
        end

        case kind
        when :preamble
          end_line = if statements.any?
                       statements.map(&:start_line).compact.min.to_i - 1
                     else
                       analysis.lines.length
                     end
          [1, end_line]
        when :postlude
          start_line = if statements.any?
                         statements.map(&:end_line).compact.max.to_i + 1
                       else
                         region.start_line || 1
                       end
          [start_line, analysis.lines.length]
        end
      end

      def first_statement_for(analysis)
        Array(analysis&.statements)
          .select { |statement| statement.respond_to?(:start_line) && statement.start_line }
          .min_by(&:start_line)
      end

      def first_statement_has_leading_comments?(analysis)
        first_statement = first_statement_for(analysis)
        return false unless first_statement

        leading_comment_lines_for(first_statement, analysis).any?
      end

      # Process a matched declaration pair
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_match(entry)
        resolution = @resolver.resolve(
          entry[:template_decl],
          entry[:dest_decl],
          template_index: entry[:template_index],
          dest_index: entry[:dest_index]
        )

        case resolution[:source]
        when :template
          if entry[:template_decl].is_a?(FreezeNode)
            @result.add_freeze_block(entry[:template_decl])
          else
            @result.add_from_template(
              entry[:template_index],
              decision: resolution[:decision],
              comment_source_statement: entry[:dest_decl],
              comment_source_analysis: @dest_analysis
            )
          end
        when :destination
          if entry[:dest_decl].is_a?(FreezeNode)
            @result.add_freeze_block(entry[:dest_decl])
          else
            @result.add_from_destination(entry[:dest_index], decision: resolution[:decision])
          end
        when :recursive
          process_recursive_merge(entry, resolution)
        end
      end

      # Process a template-only declaration
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_template_only(entry)
        return unless @add_template_only_nodes

        # FreezeNodes from template should always be added
        if entry[:template_decl].is_a?(FreezeNode)
          @result.add_freeze_block(entry[:template_decl])
        else
          @result.add_from_template(entry[:template_index], decision: MergeResult::DECISION_ADDED)
        end
      end

      # Process a destination-only declaration
      # @param entry [Hash] Alignment entry
      # @return [void]
      def process_dest_only(entry)
        if entry[:dest_decl].is_a?(FreezeNode)
          @result.add_freeze_block(entry[:dest_decl])
        elsif @remove_template_missing_nodes
          emit_removed_destination_declaration_comments(entry[:dest_decl])
        else
          @result.add_from_destination(entry[:dest_index], decision: MergeResult::DECISION_DESTINATION)
        end
      end

      def emit_removed_destination_declaration_comments(decl)
        lines = removed_declaration_comment_lines(decl, @dest_analysis)
        @result.add_raw(lines, decision: MergeResult::DECISION_DESTINATION) if lines.any?
      end

      def removed_declaration_comment_lines(decl, analysis)
        attachment = analysis.comment_attachment_for(decl)
        leading_region = leading_region_for(decl, analysis)
        start_line = get_start_line(decl)
        trailing_lines = if (trailing_region = attachment&.trailing_region)
                           trailing_region.nodes.filter_map do |node|
                             if node.respond_to?(:slice)
                               node.slice.to_s
                             elsif node.respond_to?(:text)
                               node.text.to_s
                             else
                               node.to_s
                             end
                           end
                         else
                           []
                         end

        if region_present?(leading_region)
          region_start = region_start_line(leading_region)
          if region_start && start_line && region_start < start_line
            leading_start = preceding_blank_line_start(region_start, analysis)
            lines = (leading_start...start_line).filter_map { |ln| analysis.line_at(ln) }
            lines.concat(trailing_lines)
            trailing_gap = attachment&.trailing_gap
            if trailing_gap&.effective_controller_side(removed_owners: [decl]) == :after
              lines.concat(trailing_gap.lines)
            end
            return lines
          end
        elsif decl.respond_to?(:comment) && decl.comment
          comment_start = decl.comment.location&.start_line
          if comment_start && start_line && comment_start < start_line
            return (comment_start...start_line).filter_map do |ln|
              analysis.line_at(ln)
            end
          end
        end

        return trailing_lines if trailing_lines.any?

        []
      end

      # Process recursive merge for container declarations
      # @param entry [Hash] Alignment entry
      # @param resolution [Hash] Resolution info
      # @return [void]
      def process_recursive_merge(entry, resolution)
        template_decl = resolution[:template_declaration]
        dest_decl = resolution[:dest_declaration]

        # For now, just use the destination version for complex recursive merges
        # A full recursive implementation would merge members individually
        merged_content = reconstruct_declaration_with_merged_members(
          template_decl,
          dest_decl,
          entry[:template_index],
          entry[:dest_index]
        )

        @result.add_recursive_merge(
          merged_content,
          template_index: entry[:template_index],
          dest_index: entry[:dest_index]
        )
      end

      # Reconstruct a declaration with merged members
      # @param template_decl [Object] Template declaration
      # @param dest_decl [Object] Destination declaration
      # @param template_index [Integer] Template index
      # @param dest_index [Integer] Destination index
      # @return [String] Merged declaration source
      def reconstruct_declaration_with_merged_members(template_decl, dest_decl, _template_index, _dest_index)
        # Choose which declaration to use based on preference
        pref = @preference.is_a?(Hash) ? (@preference[:default] || :destination) : @preference
        decl = pref == :template ? template_decl : dest_decl
        analysis = pref == :template ? @template_analysis : @dest_analysis
        comment_source_decl = pref == :template ? dest_decl : nil
        comment_source_analysis = pref == :template ? @dest_analysis : nil

        # Support both NodeWrapper (has start_line/end_line) and RBS gem nodes (has location)
        start_line = get_start_line(decl)
        end_line = get_end_line(decl)

        leading_region, leading_analysis, leading_decl = preferred_leading_region(
          decl,
          analysis,
          comment_source_decl: comment_source_decl,
          comment_source_analysis: comment_source_analysis
        )

        if leading_region && leading_decl
          region_start = region_start_line(leading_region)
          leading_end = get_start_line(leading_decl)

          if region_start && leading_end && region_start < leading_end
            leading_start = leading_segment_start_for_output(
              output_decl: decl,
              output_analysis: analysis,
              source_region_start: region_start,
              source_region: leading_region,
              source_analysis: leading_analysis
            )
            leading_lines = (leading_start...leading_end).filter_map { |ln| leading_analysis.line_at(ln) }
            body_lines = recursive_body_lines_for_declaration(
              template_decl,
              dest_decl,
              decl,
              analysis
            )
            return (leading_lines + body_lines).join("\n") + "\n"
          end
        end

        # Only fall back to native declaration comments when shared attachment
        # support is unavailable. Once comment attachments exist they define the
        # authoritative ownership boundary.
        if native_comment_fallback_applicable?(decl, analysis)
          comment_loc = decl.comment.respond_to?(:location) ? decl.comment.location : nil
          if comment_loc
            comment_start = comment_loc.start_line
            start_line = comment_start if comment_start < start_line
          end
        end

        body_lines = recursive_body_lines_for_declaration(
          template_decl,
          dest_decl,
          decl,
          analysis,
          start_line: start_line,
          end_line: end_line
        )
        body_lines.join("\n") + "\n"
      end

      def recursive_body_lines_for_declaration(template_decl, dest_decl, selected_decl, selected_analysis,
                                               start_line: nil, end_line: nil)
        template_members = template_decl.respond_to?(:members) ? template_decl.members : []
        dest_members = dest_decl.respond_to?(:members) ? dest_decl.members : []
        selected_members = selected_decl.respond_to?(:members) ? selected_decl.members : []

        start_line ||= get_start_line(selected_decl)
        end_line ||= get_end_line(selected_decl)

        if template_members.empty? && dest_members.empty?
          return (start_line..end_line).map do |ln|
            selected_analysis.line_at(ln)
          end
        end

        if selected_members.empty?
          return empty_container_header_lines(selected_analysis, start_line: start_line, end_line: end_line) +
                 merge_member_lines(template_members, dest_members, template_owners: template_members,
                                                                  dest_owners: dest_members) +
                 empty_container_footer_lines(selected_analysis, start_line: start_line, end_line: end_line)
        end

        container_header_lines(selected_decl, selected_analysis) +
          merge_member_lines(template_members, dest_members, template_owners: template_members,
                                                              dest_owners: dest_members) +
          container_footer_lines(selected_decl, selected_analysis)
      end

      def merge_member_lines(template_members, dest_members, template_owners: nil, dest_owners: nil)
        align_member_lists(template_members, dest_members).each_with_object([]) do |entry, lines|
          case entry[:type]
          when :match
            resolution = @resolver.resolve(
              entry[:template_decl],
              entry[:dest_decl],
              template_index: entry[:template_index],
              dest_index: entry[:dest_index]
            )

            case resolution[:source]
            when :template
              lines.concat(
                extract_statement_lines_with_leading_comments(
                  entry[:template_decl],
                  @template_analysis,
                  comment_source_statement: entry[:dest_decl],
                  comment_source_analysis: @dest_analysis,
                  owners: template_owners,
                  comment_source_owners: dest_owners
                )
              )
            when :destination
              lines.concat(
                extract_statement_lines_with_leading_comments(
                  entry[:dest_decl],
                  @dest_analysis,
                  owners: dest_owners
                )
              )
            when :recursive
              lines.concat(
                reconstruct_declaration_with_merged_members(
                  resolution[:template_declaration],
                  resolution[:dest_declaration],
                  entry[:template_index],
                  entry[:dest_index]
                ).split("\n", -1).tap { |parts| parts.pop if parts.last == '' }
              )
            end
          when :template_only
            next unless @add_template_only_nodes

            lines.concat(
              extract_statement_lines_with_leading_comments(
                entry[:template_decl],
                @template_analysis,
                owners: template_owners
              )
            )
          when :dest_only
            if @remove_template_missing_nodes
              lines.concat(removed_declaration_comment_lines(entry[:dest_decl], @dest_analysis))
            else
              lines.concat(
                extract_statement_lines_with_leading_comments(
                  entry[:dest_decl],
                  @dest_analysis,
                  owners: dest_owners
                )
              )
            end
          end
        end
      end

      def align_member_lists(template_members, dest_members)
        template_by_sig = build_member_signature_map(template_members, @template_analysis)
        dest_by_sig = build_member_signature_map(dest_members, @dest_analysis)
        matched_template = Set.new
        matched_dest = Set.new
        alignment = []

        template_by_sig.each do |sig, template_indices|
          next unless dest_by_sig.key?(sig)

          template_indices.zip(dest_by_sig[sig]).each do |t_idx, d_idx|
            next unless t_idx && d_idx

            alignment << {
              type: :match,
              template_index: t_idx,
              dest_index: d_idx,
              template_decl: template_members[t_idx],
              dest_decl: dest_members[d_idx]
            }
            matched_template << t_idx
            matched_dest << d_idx
          end
        end

        template_members.each_with_index do |stmt, idx|
          next if matched_template.include?(idx)

          alignment << {
            type: :template_only,
            template_index: idx,
            dest_index: nil,
            template_decl: stmt,
            dest_decl: nil
          }
        end

        dest_members.each_with_index do |stmt, idx|
          next if matched_dest.include?(idx)

          alignment << {
            type: :dest_only,
            template_index: nil,
            dest_index: idx,
            template_decl: nil,
            dest_decl: stmt
          }
        end

        alignment.sort_by do |entry|
          if entry[:dest_index]
            [0, entry[:dest_index], entry[:template_index] || Float::INFINITY]
          elsif entry[:template_index]
            [1, entry[:template_index], 0]
          else
            [2, 0, 0]
          end
        end
      end

      def build_member_signature_map(members, analysis)
        members.each_with_index.with_object(Hash.new { |hash, key| hash[key] = [] }) do |(member, idx), map|
          signature = member_alignment_signature(member, analysis)
          map[signature] << idx if signature
        end
      end

      def member_alignment_signature(member, analysis)
        signature = analysis.generate_signature(member)
        return signature unless method_member_signature?(member, signature)

        overload_key = method_overload_alignment_key(member, analysis)
        return signature unless overload_key

        signature + [overload_key]
      end

      def method_member_signature?(member, signature)
        return false unless signature.is_a?(Array) && signature.first == :method
        return member.method? if member.respond_to?(:method?)

        true
      end

      def method_overload_alignment_key(member, analysis)
        text = if member.respond_to?(:text) && member.text
                 member.text
               else
                 extract_raw_statement_lines(member, analysis).join("\n")
               end

        callable_shape = extract_callable_shape(text)
        callable_shape unless callable_shape.nil? || callable_shape.empty?
      end

      def extract_callable_shape(text)
        stripped = text.to_s.strip
        return if stripped.empty?

        colon_index = stripped.index(':')
        return unless colon_index

        type_text = stripped[(colon_index + 1)..].to_s.strip
        callable_portion, = split_top_level_return_type(type_text)
        normalize_signature_whitespace(callable_portion)
      end

      def split_top_level_return_type(type_text)
        depth = 0
        index = 0

        while index < (type_text.length - 1)
          char = type_text[index]
          next_char = type_text[index + 1]

          case char
          when '(', '[', '{', '<'
            depth += 1
          when ')', ']', '}', '>'
            depth -= 1 if depth.positive?
          end

          if depth.zero? && char == '-' && next_char == '>'
            return [type_text[0...index].strip, type_text[(index + 2)..].to_s.strip]
          end

          index += 1
        end

        [type_text.strip, nil]
      end

      def normalize_signature_whitespace(text)
        text.to_s.gsub(/\s+/, ' ').strip
      end

      def extract_raw_statement_lines(statement, analysis)
        start_line = get_start_line(statement)
        end_line = get_end_line(statement)
        return [] unless start_line && end_line

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def extract_statement_lines_with_leading_comments(statement, analysis, comment_source_statement: nil,
                                                        comment_source_analysis: nil, owners: nil,
                                                        comment_source_owners: nil)
        start_line = get_start_line(statement)
        return [] unless start_line

        leading_region, leading_analysis, leading_statement = preferred_leading_region(
          statement,
          analysis,
          comment_source_decl: comment_source_statement,
          comment_source_analysis: comment_source_analysis,
          owners: owners,
          comment_source_owners: comment_source_owners
        )

        leading_lines = if leading_region && leading_statement
                          region_start = region_start_line(leading_region)
                          leading_end = get_start_line(leading_statement)

                          if region_start && leading_end && region_start < leading_end
                            leading_start = leading_segment_start_for_output(
                              output_decl: statement,
                              output_analysis: analysis,
                              source_region_start: region_start,
                              source_region: leading_region,
                              source_analysis: leading_analysis
                            )
                            (leading_start...leading_end).filter_map do |line_number|
                              leading_analysis.line_at(line_number)
                            end
                          else
                            []
                          end
                        else
                          []
                        end

        leading_gap_lines = leading_lines.empty? ? layout_gap_lines_for(statement, analysis, side: :leading, owners: owners) : []

        leading_gap_lines + leading_lines + extract_raw_statement_lines(statement, analysis)
      end

      def layout_gap_lines_for(statement, analysis, side:, owners: nil)
        return [] unless statement && analysis&.respond_to?(:comment_attachment_for)

        attachment = analysis.comment_attachment_for(statement, owners: owners)
        gap = side == :leading ? attachment.leading_gap : attachment.trailing_gap
        return [] unless gap&.controls_output_for?(statement)

        gap.lines
      end

      def empty_container_header_lines(analysis, start_line:, end_line:)
        return [] unless start_line && end_line
        return [] if start_line >= end_line

        (start_line...end_line).map { |line_number| analysis.line_at(line_number) }
      end

      def empty_container_footer_lines(analysis, start_line:, end_line:)
        return [] unless start_line && end_line

        [analysis.line_at(end_line)]
      end

      def container_header_lines(decl, analysis)
        members = decl.respond_to?(:members) ? decl.members : []
        first_member = members.first
        return [] unless first_member

        start_line = get_start_line(decl)
        end_line = get_start_line(first_member) - 1
        return [] unless start_line && end_line && start_line <= end_line

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def container_footer_lines(decl, analysis)
        members = decl.respond_to?(:members) ? decl.members : []
        last_member = members.last
        return [] unless last_member

        start_line = get_end_line(last_member) + 1
        end_line = get_end_line(decl)
        return [] unless start_line && end_line && start_line <= end_line

        (start_line..end_line).map { |ln| analysis.line_at(ln) }
      end

      def preferred_leading_region(decl, analysis, comment_source_decl: nil, comment_source_analysis: nil,
                                   owners: nil, comment_source_owners: nil)
        primary_region = leading_region_for(decl, analysis, owners: owners)
        return [primary_region, analysis, decl] if region_present?(primary_region)

        if comment_source_decl && comment_source_analysis
          source_region = leading_region_for(comment_source_decl, comment_source_analysis, owners: comment_source_owners)
          return [source_region, comment_source_analysis, comment_source_decl] if region_present?(source_region)
        end

        [nil, analysis, decl]
      end

      def native_comment_fallback_applicable?(decl, analysis)
        return false if analysis&.respond_to?(:comment_attachment_for)

        decl.respond_to?(:comment) && decl.comment
      end

      def leading_comment_lines_for(statement, analysis)
        leading_region = leading_region_for(statement, analysis)
        return [] unless region_present?(leading_region)

        region_start = region_start_line(leading_region)
        statement_start = get_start_line(statement)
        return [] unless region_start && statement_start && region_start < statement_start

        leading_start = leading_segment_start_for_output(
          output_decl: statement,
          output_analysis: analysis,
          source_region_start: region_start,
          source_region: leading_region,
          source_analysis: analysis
        )
        lines = (leading_start...statement_start).filter_map { |line_number| analysis.line_at(line_number) }
        comments, = leading_standalone_comment_run(lines.join("\n"))
        comments
      end

      def leading_region_for(decl, analysis, owners: nil)
        return unless decl && analysis&.respond_to?(:comment_attachment_for)

        attachment = analysis.comment_attachment_for(decl, owners: owners)
        attachment.leading_region if attachment.respond_to?(:leading_region)
      end

      def region_present?(region)
        return false unless region
        return !region.empty? if region.respond_to?(:empty?)
        return region.nodes.any? if region.respond_to?(:nodes)

        true
      end

      def region_start_line(region)
        return region.start_line if region.respond_to?(:start_line) && region.start_line
        return unless region.respond_to?(:nodes)

        region.nodes.filter_map { |node| node.respond_to?(:line_number) ? node.line_number : nil }.min
      end

      def preceding_blank_line_start(region_start, analysis)
        line_num = region_start
        while line_num > 1
          previous_line = analysis.line_at(line_num - 1)
          break unless previous_line && previous_line.strip.empty?

          line_num -= 1
        end

        line_num
      end

      def leading_segment_start_for_output(output_decl:, output_analysis:, source_region_start:, source_analysis:,
                                           source_region: nil)
        source_region_start - desired_blank_line_count_before_leading_region(
          output_decl: output_decl,
          output_analysis: output_analysis,
          source_region_start: source_region_start,
          source_region: source_region,
          source_analysis: source_analysis
        )
      end

      def desired_blank_line_count_before_leading_region(output_decl:, output_analysis:, source_region_start:,
                                                         source_analysis:, source_region: nil)
        target_region = leading_region_for(output_decl, output_analysis)
        target_region_start = region_start_line(target_region)
        output_start_line = get_start_line(output_decl)

        if target_region_start && output_start_line && target_region_start < output_start_line
          blank_line_count_before(target_region_start, output_analysis)
        elsif source_region && previous_statement_trailing_region_matches?(output_decl, output_analysis, source_region)
          0
        else
          blank_line_count_before(source_region_start, source_analysis)
        end
      end

      def blank_line_count_before(line_num, analysis)
        count = 0
        current = line_num - 1

        while current >= 1
          previous_line = analysis.line_at(current)
          break unless previous_line && previous_line.strip.empty?

          count += 1
          current -= 1
        end

        count
      end

      def previous_statement_trailing_region_matches?(decl, analysis, source_region)
        previous_decl = previous_statement_for(decl, analysis)
        return false unless previous_decl

        previous_trailing_region = analysis.comment_attachment_for(previous_decl)&.trailing_region
        regions_equivalent?(previous_trailing_region, source_region)
      end

      def previous_statement_for(decl, analysis)
        statements = Array(analysis&.statements).select do |statement|
          statement.respond_to?(:start_line) && statement.start_line
        end
        index = statements.index(decl)
        return unless index && index.positive?

        statements[index - 1]
      end

      def regions_equivalent?(left, right)
        return false unless left && right

        left.respond_to?(:normalized_content) &&
          right.respond_to?(:normalized_content) &&
          left.normalized_content == right.normalized_content
      end

      STANDALONE_RBS_COMMENT_LINE_RE = /\A\s*#.*\z/
      private_constant :STANDALONE_RBS_COMMENT_LINE_RE

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
          message: 'merged RBS preamble begins with duplicated template-owned comment lines',
          prefix: '[rbs-merge]',
          error_class: Rbs::Merge::CorruptionDetectedError,
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

          break unless STANDALONE_RBS_COMMENT_LINE_RE.match?(line)

          comment_lines << line
          index += 1
        end

        [comment_lines, lines.drop(index).join("\n")]
      end

      # Get start line for a declaration (works with both backends)
      # @param decl [Object] Declaration (NodeWrapper or RBS::AST::*)
      # @return [Integer]
      def get_start_line(decl)
        if decl.respond_to?(:start_line)
          decl.start_line
        elsif decl.respond_to?(:location) && decl.location
          decl.location.start_line
        else
          1
        end
      end

      # Get end line for a declaration (works with both backends)
      # @param decl [Object] Declaration (NodeWrapper or RBS::AST::*)
      # @return [Integer]
      def get_end_line(decl)
        if decl.respond_to?(:end_line)
          decl.end_line
        elsif decl.respond_to?(:location) && decl.location
          decl.location.end_line
        else
          1
        end
      end
    end
  end
end
