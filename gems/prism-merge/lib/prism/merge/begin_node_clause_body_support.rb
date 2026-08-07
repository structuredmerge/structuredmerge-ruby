# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodeClauseBodySupport
      attr_reader :merger, :template_analysis, :dest_analysis, :freeze_token, :raw_signature_generator, :node_typing

      def initialize(merger:, template_analysis:, dest_analysis:, freeze_token:, raw_signature_generator:, node_typing:)
        @merger = merger
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @freeze_token = freeze_token
        @raw_signature_generator = raw_signature_generator
        @node_typing = node_typing
      end

      def clause_statements_node(node)
        ct = NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
        node.statements if %i[rescue else ensure].include?(ct)
      end

      def clause_header_end_line(node, region)
        return region[:start_line] unless node && region

        header_lines = []
        header_lines << node.keyword_loc.end_line if node.respond_to?(:keyword_loc) && node.keyword_loc

        if node.type.to_s == 'rescue_node'
          header_lines.concat(Array(node.exceptions).filter_map do |exception_node|
            exception_node.location.end_line if exception_node.respond_to?(:location) && exception_node.location
          end)
          operator_loc = node.operator_loc if node.respond_to?(:operator_loc)
          header_lines << operator_loc.end_line if operator_loc
          reference = node.reference if node.respond_to?(:reference)
          reference_location = reference.location if reference.respond_to?(:location)
          header_lines << reference_location.end_line if reference_location
        end

        header_lines.compact.max || region[:start_line]
      end

      def clause_body_start_line(node, region)
        clause_header_end_line(node, region) + 1
      end

      def extract_region_body(region, analysis, body_start_line: region[:start_line] + 1,
                              body_end_line: region[:end_line])
        return '' unless region
        return '' if body_end_line < body_start_line

        lines = []
        (body_start_line..body_end_line).each do |line_num|
          lines << analysis.line_at(line_num).chomp
        end
        "#{lines.join("\n")}\n"
      end

      def split_leading_comment_prefix(body_text)
        lines = body_text.lines
        prefix_lines = []
        index = 0

        while index < lines.length
          line = lines[index]
          stripped = line.strip
          break unless stripped.empty? || line.lstrip.start_with?('#')

          prefix_lines << line
          index += 1
        end

        [prefix_lines.join, lines[index..]&.join.to_s]
      end

      def body_contains_freeze_markers?(body_text)
        return false unless freeze_token && !freeze_token.empty?

        body_text.match?(/^\s*#\s*#{Regexp.escape(freeze_token)}:(?:freeze|unfreeze)\b/)
      end

      def clause_body_components(node, region, analysis)
        return { merge_body: '', trailing_suffix: '' } unless node && region

        statements_node = clause_statements_node(node)
        return { merge_body: '', trailing_suffix: '' } unless statements_node&.type.to_s == 'statements_node'

        body_statements = statements_node.body
        body_start_line = clause_body_start_line(node, region)
        if body_statements.empty?
          return {
            merge_body: '',
            trailing_suffix: extract_region_body(region, analysis, body_start_line: body_start_line)
          }
        end

        last_statement_end_line = body_statements.last.location.end_line

        # If the merge_body slice has an odd number of :nocov: markers (open without
        # a matching close), scan the trailing lines to include the close marker.
        # Trailing close markers are pure comments — not Prism AST nodes — so they
        # end up in trailing_suffix and cause false "unclosed :nocov:" warnings when
        # sub-body FileAnalysis is constructed on the body slice alone.
        effective_body_end = last_statement_end_line
        if region[:end_line] > last_statement_end_line
          nocov_count = (body_start_line..last_statement_end_line).count do |ln|
            Ruby::Merge::BlockDirectiveDetector.coverage_directive_line?(analysis.line_at(ln))
          end
          if nocov_count.odd?
            ((last_statement_end_line + 1)..region[:end_line]).each do |ln|
              if Ruby::Merge::BlockDirectiveDetector.coverage_directive_line?(analysis.line_at(ln))
                effective_body_end = ln
                break
              end
            end
          end
        end

        {
          merge_body: extract_region_body(region, analysis, body_start_line: body_start_line,
                                                            body_end_line: effective_body_end),
          trailing_suffix: if region[:end_line] > effective_body_end
                             lines = []
                             ((effective_body_end + 1)..region[:end_line]).each do |line_num|
                               lines << analysis.line_at(line_num).chomp
                             end
                             "#{lines.join("\n")}\n"
                           else
                             ''
                           end
        }
      end

      def statement_signatures_for_nodes(nodes, analysis)
        Set.new(
          Array(nodes).filter_map do |node|
            signature = analysis.generate_signature(node)
            signature if signature
          end
        )
      end

      def begin_node_statement_signatures(node, analysis)
        return Set.new unless node.type.to_s == 'begin_node'

        signatures = statement_signatures_for_nodes(node.statements&.body, analysis)
        BeginNodeStructure.new(node).clause_nodes_by_type.each_value do |clause_node|
          signatures.merge(statement_signatures_for_nodes(clause_statements_node(clause_node)&.body, analysis))
        end
        signatures
      end

      def clause_body_fully_duplicated_in_preferred_begin?(clause_node, clause_analysis, preferred_begin_node,
                                                           preferred_begin_analysis)
        clause_statements = Array(clause_statements_node(clause_node)&.body)
        return false if clause_statements.empty?

        clause_signatures = clause_statements.map { |statement| clause_analysis.generate_signature(statement) }
        return false if clause_signatures.any?(&:nil?)

        preferred_signatures = begin_node_statement_signatures(preferred_begin_node, preferred_begin_analysis)
        clause_signatures.all? { |signature| preferred_signatures.include?(signature) }
      end

      def clause_bodies_have_matching_statements?(template_body, dest_body)
        return false if template_body.strip.empty? || dest_body.strip.empty?

        effective_signature_generator = merger.send(:build_effective_signature_generator, raw_signature_generator,
                                                    node_typing)
        template_body_analysis = FileAnalysis.new(
          template_body,
          freeze_token: freeze_token,
          signature_generator: effective_signature_generator
        )
        dest_body_analysis = FileAnalysis.new(
          dest_body,
          freeze_token: freeze_token,
          signature_generator: effective_signature_generator
        )

        merger.send(:build_signature_map,
                    template_body_analysis).keys.intersect?(merger.send(:build_signature_map, dest_body_analysis).keys)
      end
    end
  end
end
