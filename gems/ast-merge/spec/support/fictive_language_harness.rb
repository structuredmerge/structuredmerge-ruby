# frozen_string_literal: true

require "parslet"

module SpecSupport
  module FictiveLanguageHarness
    Statement = Struct.new(
      :name,
      :value,
      :indent,
      :start_line,
      :end_line,
      :raw_line,
      :structural_content,
      keyword_init: true,
    ) do
      def content
        structural_content
      end

      def normalized_content
        structural_content.to_s.strip
      end

      def freeze_node?
        false
      end

      def to_s
        raw_line
      end
    end

    class FlatStatementParser < Parslet::Parser
      root :statement

      rule(:statement) do
        key.as(:name) >> spacing >> str("=") >> spacing >> value.as(:value)
      end

      rule(:key) { match("[A-Za-z_]") >> match("[A-Za-z0-9_]").repeat }
      rule(:value) { any.repeat(1) }
      rule(:spacing) { match('\s').repeat }
    end

    class IndentedStatementParser < Parslet::Parser
      root :statement

      rule(:statement) do
        indent.as(:indent) >> key.as(:name) >> spacing >> str("=") >> spacing >> value.as(:value)
      end

      rule(:indent) { str(" ").repeat }
      rule(:key) { match("[A-Za-z_]") >> match("[A-Za-z0-9_]").repeat }
      rule(:value) { any.repeat(1) }
      rule(:spacing) { match('\s').repeat }
    end

    class StatementTransform < Parslet::Transform
      rule(name: simple(:name), value: simple(:value)) do
        {
          name: name.to_s,
          value: value.to_s.strip,
          indent: 0,
        }
      end

      rule(indent: simple(:indent), name: simple(:name), value: simple(:value)) do
        {
          name: name.to_s,
          value: value.to_s.strip,
          indent: Array(indent).join.length,
        }
      end
    end

    class CommentTracker < Ast::Merge::Comment::HashTrackerBase
      def initialize(lines)
        @line_comment_parser = Ast::Merge::Comment::QuotedHashLineParser.new
        super(lines)
      end

      private

      def extract_comments
        @lines.each_with_index.filter_map do |line, idx|
          line_num = idx + 1
          if (match = line.match(self.class.superclass::FULL_LINE_COMMENT_REGEX))
            {
              line: line_num,
              indent: match[:indent].length,
              text: match[:text].to_s.rstrip,
              full_line: true,
              raw: line,
            }
          else
            comment = @line_comment_parser.parse(line)
            next unless comment&.inline?

            {
              line: line_num,
              indent: comment.column,
              text: comment.text,
              full_line: false,
              raw: comment.raw,
            }
          end
        end
      end
    end

    class Analysis
      include Ast::Merge::FileAnalyzable

      attr_reader :statements, :language_name

      def initialize(source, parser_class:, language_name:, freeze_token: "fictive-merge", signature_generator: nil, **_options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @parser_class = parser_class
        @language_name = language_name
        @line_comment_parser = Ast::Merge::Comment::QuotedHashLineParser.new
        @transform = StatementTransform.new
        @statements = parse_statements
        @comment_tracker = CommentTracker.new(@lines)
      end

      def compute_node_signature(node)
        [:fictive_statement, language_name, node.indent, node.name]
      end

      def valid?
        true
      end

      def comment_capability
        Ast::Merge::Comment::Capability.source_augmented(
          source: :fictive_language_harness,
          language: language_name,
          style: :hash_comment,
          comment_nodes: true,
        )
      end

      def comment_support_style
        Ast::Merge::Comment::SupportStyle.source_augmented_portable_write(
          source: :fictive_language_harness,
          language: language_name,
        )
      end

      def comment_nodes
        @comment_tracker.comment_nodes
      end

      def comment_node_at(line_num)
        @comment_tracker.comment_node_at(line_num)
      end

      def comment_region_for_range(range, kind:, **options)
        @comment_tracker.comment_region_for_range(range, kind: kind, **options)
      end

      def comment_attachment_for(owner, **options)
        attachment = comment_augmenter(owners: statements, **options).attachment_for(owner)
        merge_comment_attachment_with_layout(owner, attachment, **options)
      end

      def comment_augmenter(owners: nil, **options)
        @comment_tracker.augment(owners: owners || statements, **options)
      end

      def standalone_comment_line(text, indent: "")
        "#{indent}# #{text}"
      end

      private

      def parse_statements
        parser = @parser_class.new

        @lines.each_with_index.filter_map do |line, idx|
          next if line.strip.empty?

          parsed_comment = @line_comment_parser.parse(line)
          next if parsed_comment&.full_line?

          structural_line = strip_inline_comment(line, parsed_comment)
          next if structural_line.strip.empty?

          begin
            tree = parser.parse(structural_line)
          rescue Parslet::ParseFailed => e
            raise ArgumentError, "Could not parse #{language_name} line #{idx + 1}: #{line.inspect} (#{e.message})"
          end

          statement = @transform.apply(tree)
          indent = statement[:indent].is_a?(Integer) ? statement[:indent] : structural_line[/\A */].to_s.length
          Statement.new(
            name: statement.fetch(:name),
            value: statement.fetch(:value),
            indent: indent,
            start_line: idx + 1,
            end_line: idx + 1,
            raw_line: line,
            structural_content: structural_line,
          )
        end
      end

      def strip_inline_comment(line, parsed_comment)
        return line unless parsed_comment&.inline?

        line[0...parsed_comment.column].rstrip
      end
    end

    class FlatAnalysis < Analysis
      def initialize(source, **options)
        super(source, parser_class: FlatStatementParser, language_name: :flat, **options)
      end
    end

    class IndentedAnalysis < Analysis
      def initialize(source, **options)
        super(source, parser_class: IndentedStatementParser, language_name: :indented, **options)
      end
    end

    class MergeResolver < Ast::Merge::ConflictResolverBase
      include Ast::Merge::TrailingGroups::DestIterate

      def initialize(
        template_analysis:,
        dest_analysis:,
        preference: :destination,
        add_template_only_nodes: false,
        remove_template_missing_nodes: false,
        match_refiner: nil
      )
        super(
          strategy: :batch,
          preference: preference,
          template_analysis: template_analysis,
          dest_analysis: dest_analysis,
          add_template_only_nodes: add_template_only_nodes,
          remove_template_missing_nodes: remove_template_missing_nodes,
          match_refiner: match_refiner,
        )
      end

      protected

      def resolve_batch(result)
        template_statements = @template_analysis.statements
        dest_statements = @dest_analysis.statements
        template_index = build_match_index(template_statements)
        dest_sigs = destination_signature_set(dest_statements)
        trailing_groups, matched_indices = build_dest_iterate_trailing_groups(
          template_nodes: template_statements,
          dest_sigs: dest_sigs,
          signature_for: ->(node) { signature_key_for(node) },
          add_template_only_nodes: @add_template_only_nodes,
        )

        matched_template_indices = Set.new
        consumed_indices = Set.new
        @emitted_comment_blocks = Set.new

        emit_prefix_trailing_group(trailing_groups, consumed_indices) do |info|
          add_template_only_statement(result, info[:node])
        end

        dest_statements.each do |dest_node|
          match_key = signature_key_for(dest_node)
          template_match = find_unmatched(template_index[match_key], matched_template_indices)

          if template_match
            matched_template_indices << template_match[:index]
            consumed_indices << template_match[:index]
            resolve_matched_pair(result, template_match[:node], dest_node)
            flush_ready_trailing_groups(
              trailing_groups: trailing_groups,
              matched_indices: matched_indices,
              consumed_indices: consumed_indices,
            ) do |info|
              add_template_only_statement(result, info[:node])
            end
          elsif !@remove_template_missing_nodes
            add_destination_only_statement(result, dest_node)
          else
            preserve_removed_destination_comments(result, dest_node)
          end
        end

        emit_remaining_trailing_groups(
          trailing_groups: trailing_groups,
          consumed_indices: consumed_indices,
        ) do |info|
          add_template_only_statement(result, info[:node])
        end
      end

      private

      def signature_key_for(node)
        @template_analysis.generate_signature(node)
      end

      def build_match_index(statements)
        statements.each_with_index.with_object(Hash.new { |h, k| h[k] = [] }) do |(node, idx), index|
          key = signature_key_for(node)
          index[key] << {node: node, index: idx}
        end
      end

      def destination_signature_set(statements)
        statements.each_with_object(Set.new) do |node, signatures|
          signatures << signature_key_for(node)
        end
      end

      def find_unmatched(entries, matched_indices)
        return unless entries

        entries.find { |entry| !matched_indices.include?(entry[:index]) }
      end

      def add_template_only_statement(result, template_node)
        emit_statement(result, template_node, @template_analysis)
        result.record_decision(DECISION_ADDED, template_node, nil)
      end

      def add_destination_only_statement(result, dest_node)
        emit_statement(result, dest_node, @dest_analysis)
        result.record_decision(DECISION_APPENDED, nil, dest_node)
      end

      def resolve_matched_pair(result, template_node, dest_node)
        preferred_node = if preference_for_node(template_node) == :template
          template_node
        else
          dest_node
        end
        preferred_analysis = preferred_node.equal?(template_node) ? @template_analysis : @dest_analysis

        emit_statement(result, preferred_node, preferred_analysis)
        result.record_decision(
          if template_node.raw_line == dest_node.raw_line
            DECISION_IDENTICAL
          elsif preferred_node.equal?(template_node)
            DECISION_KEPT_TEMPLATE
          else
            DECISION_KEPT_DEST
          end,
          template_node,
          dest_node,
        )
      end

      def preserve_removed_destination_comments(result, dest_node)
        attachment = @dest_analysis.comment_attachment_for(dest_node)
        leading_region = attachment.leading_region || removable_preamble_region_for(dest_node)

        if emit_region_lines(result, leading_region)
          emit_layout_gap(result, attachment.leading_gap)
        else
          Ast::Merge::Layout.prune_emitted_leading_gap_for_removed_owner(
            result: result,
            attachment: attachment,
          )
        end

        if attachment.inline_region
          result.add_line(
            @dest_analysis.standalone_comment_line(
              attachment.inline_region.normalized_content,
              indent: (" " * dest_node.indent),
            ),
          )
        end

        emit_region_lines(result, attachment.trailing_region)
      end

      def emit_region_lines(result, region)
        return false unless region
        return false if duplicate_comment_region?(region)

        remember_comment_region(region)

        region.text.split("\n").each do |line|
          result.add_line(line)
        end

        true
      end

      def emit_layout_gap(result, gap)
        return unless gap

        gap.lines.each do |line|
          result.add_line(line)
        end
      end

      def removable_preamble_region_for(dest_node)
        return unless @dest_analysis.statements.first.equal?(dest_node)

        @dest_analysis.comment_augmenter.preamble_region
      end

      def addable_preamble_region_for(template_node)
        return unless @template_analysis.statements.first.equal?(template_node)

        @template_analysis.comment_augmenter.preamble_region
      end

      def emit_statement(result, node, analysis)
        attachment = analysis.comment_attachment_for(node)
        leading_region = canonical_leading_region_for(node, analysis, attachment)

        emit_region_lines(result, leading_region)
        emit_layout_gap(result, attachment.leading_gap)
        result.add_line(node.raw_line)
        emit_region_lines(result, attachment.trailing_region)
        emit_layout_gap(result, attachment.trailing_gap)
        emit_postlude_region_for_last_node(result, node, analysis, attachment)
      end

      def canonical_leading_region_for(node, analysis, attachment)
        region = attachment.leading_region
        return collapse_template_preamble_prefix_region(region) if first_statement?(node, analysis) && region

        return region if region
        return unless first_statement?(node, analysis)

        collapse_template_preamble_prefix_region(analysis.comment_augmenter.preamble_region)
      end

      def emit_postlude_region_for_last_node(result, node, analysis, attachment)
        return unless last_statement?(node, analysis)

        postlude_region = analysis.comment_augmenter.postlude_region
        return unless postlude_region
        return if attachment.trailing_region && attachment.trailing_region.normalized_content == postlude_region.normalized_content

        emit_region_lines(result, postlude_region)
      end

      def first_statement?(node, analysis)
        analysis.statements.first.equal?(node)
      end

      def last_statement?(node, analysis)
        analysis.statements.last.equal?(node)
      end

      def collapse_template_preamble_prefix_region(region)
        return region unless region

        template_preamble = @template_analysis.comment_augmenter.preamble_region
        return region unless template_preamble

        region_nodes = Array(region.nodes)
        template_nodes = Array(template_preamble.nodes)
        return region if region_nodes.empty? || template_nodes.empty?
        return region if region.normalized_content == template_preamble.normalized_content
        return region if region_nodes.length < template_nodes.length

        repeat_count = 0
        while prefix_matches_region_nodes?(region_nodes.drop(repeat_count * template_nodes.length), template_nodes)
          repeat_count += 1
        end
        return region if repeat_count.zero?

        remainder_nodes = region_nodes.drop(repeat_count * template_nodes.length)
        return region if remainder_nodes.empty?

        Ast::Merge::Comment::Region.new(
          kind: region.kind,
          nodes: remainder_nodes,
          metadata: region.metadata,
        )
      end

      def prefix_matches_region_nodes?(candidate_nodes, prefix_nodes)
        candidate = candidate_nodes.first(prefix_nodes.length)
        return false unless candidate.length == prefix_nodes.length

        candidate.zip(prefix_nodes).all? do |left, right|
          left.respond_to?(:normalized_content) &&
            right.respond_to?(:normalized_content) &&
            left.normalized_content == right.normalized_content
        end
      end

      def duplicate_comment_region?(region)
        normalized = region.normalized_content
        return false if normalized.nil? || normalized.empty?

        @emitted_comment_blocks.include?(normalized)
      end

      def remember_comment_region(region)
        normalized = region.normalized_content
        return if normalized.nil? || normalized.empty?

        @emitted_comment_blocks.add(normalized)
      end
    end

    class SmartMergerBase < Ast::Merge::SmartMergerBase
      DEFAULT_FREEZE_TOKEN = "fictive-merge"

      def initialize(
        template_content,
        dest_content,
        preference: :destination,
        add_template_only_nodes: false,
        remove_template_missing_nodes: false
      )
        @remove_template_missing_nodes = remove_template_missing_nodes
        super(
          template_content,
          dest_content,
          signature_generator: ->(node) { node },
          preference: preference,
          add_template_only_nodes: add_template_only_nodes,
          freeze_token: DEFAULT_FREEZE_TOKEN,
        )
      end

      protected

      def default_freeze_token
        DEFAULT_FREEZE_TOKEN
      end

      def resolver_class
        MergeResolver
      end

      def result_class
        Ast::Merge::Text::MergeResult
      end

      def build_resolver_options
        {
          remove_template_missing_nodes: @remove_template_missing_nodes,
        }
      end

      def perform_merge
        @resolver.resolve(@result)
        @result
      end
    end

    class FlatSmartMerger < SmartMergerBase
      protected

      def analysis_class
        FlatAnalysis
      end
    end

    class IndentedSmartMerger < SmartMergerBase
      protected

      def analysis_class
        IndentedAnalysis
      end
    end
  end
end
