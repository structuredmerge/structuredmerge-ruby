# frozen_string_literal: true

module Prism
  module Merge
    # Prism-specific projection for Ruby block directive spans.
    #
    # Ruby directive token detection lives in Ruby::Merge::BlockDirectiveDetector.
    # This class only promotes detected spans into Prism merge nodes.
    class BlockDirectiveDetector < Ruby::Merge::BlockDirectiveDetector
      def promote_spans_to_nodes(statements, spans, analysis:)
        return statements if spans.empty?

        validate_same_syntactic_level!(spans, statements)

        top_level = top_level_spans_only(spans).reject do |span|
          statements.any? do |stmt|
            start_line = stmt_start_line(stmt)
            end_line = stmt_end_line(stmt)
            start_line && end_line && start_line <= span.start_line && end_line >= span.end_line
          end
        end

        return statements if top_level.empty?

        result = []
        used_indices = Set.new

        top_level.each do |span|
          inner_stmts = statements.each_with_index.select do |stmt, index|
            next false if used_indices.include?(index)

            start_line = stmt_start_line(stmt)
            end_line = stmt_end_line(stmt)
            start_line && end_line && start_line >= span.start_line && end_line <= span.end_line
          end.map { |stmt, index| [index, stmt] }

          inner_indices = inner_stmts.map(&:first)
          inner_nodes = inner_stmts.map(&:last)
          nested = spans.select { |candidate| candidate != span && candidate.start_line >= span.start_line && candidate.end_line <= span.end_line }
          inner_nodes = promote_spans_to_nodes(inner_nodes, nested, analysis: analysis) unless nested.empty?

          insert_at = if inner_indices.any?
                        inner_indices.min
                      else
                        after_span = statements.each_with_index.find do |stmt, _|
                          stmt_start_line(stmt).to_i > span.start_line
                        end
                        after_span ? after_span.last : statements.length
                      end

          result << [insert_at, build_directive_node(span, inner_nodes, analysis), inner_indices]
          used_indices.merge(inner_indices)
        end

        rebuild_statements(statements, result, used_indices)
      end

      private

      def detector_name
        'prism-merge'
      end

      def directive_error_class
        Prism::Merge::Error
      end

      def stmt_start_line(stmt)
        if stmt.respond_to?(:start_line)
          stmt.start_line
        elsif stmt.respond_to?(:location)
          stmt.location&.start_line
        end
      end

      def stmt_end_line(stmt)
        if stmt.respond_to?(:end_line)
          stmt.end_line
        elsif stmt.respond_to?(:location)
          stmt.location&.end_line
        end
      end

      def validate_same_syntactic_level!(spans, statements)
        spans.each do |span|
          start_owner = owner_for_line(statements, span.start_line)
          end_owner = owner_for_line(statements, span.end_line)
          next if start_owner.nil? && end_owner.nil?
          next if start_owner && end_owner && start_owner.equal?(end_owner)

          report_unbalanced(
            "#{span.kind} block opens at line #{span.start_line} and closes at line #{span.end_line}, " \
              'but the markers do not live at the same syntactic level'
          )
        end
      end

      def owner_for_line(statements, line_num)
        statements.find do |stmt|
          start_line = stmt_start_line(stmt)
          end_line = stmt_end_line(stmt)
          start_line && end_line && start_line <= line_num && line_num <= end_line
        end
      end

      def build_directive_node(span, inner_nodes, analysis)
        case span.kind
        when :freeze
          Prism::Merge::FreezeNode.new(
            start_line: span.start_line,
            end_line: span.end_line,
            analysis: analysis,
            nodes: inner_nodes,
            overlapping_nodes: inner_nodes,
            start_marker: span.open_marker,
            end_marker: span.close_marker
          )
        when :nocov
          Prism::Merge::NocovNode.new(
            start_line: span.start_line,
            end_line: span.end_line,
            analysis: analysis,
            nodes: inner_nodes,
            start_marker: span.open_marker,
            close_marker: span.close_marker
          )
        else
          raise ArgumentError, "Unknown BlockDirective kind: #{span.kind}"
        end
      end

      def rebuild_statements(statements, replacements, used_indices)
        replacement_map = Hash.new { |hash, key| hash[key] = [] }
        replacements.each do |insert_at, node, _covered|
          replacement_map[insert_at] << node
        end
        replacement_map.each_value { |nodes| nodes.sort_by! { |node| node.start_line || 0 } }

        result = []
        statements.each_with_index do |stmt, index|
          if (nodes = replacement_map.delete(index))
            nodes.each { |node| result << node }
          end

          next if used_indices.include?(index)

          result << stmt
        end

        replacement_map.each_value { |nodes| nodes.each { |node| result << node } }

        result
      end
    end
  end
end
