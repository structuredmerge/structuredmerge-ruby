# frozen_string_literal: true

module Dotenv
  module Merge
    # Result container for dotenv file merge operations.
    # Inherits from Ast::Merge::MergeResultBase for shared functionality.
    #
    # Tracks merged content, decisions made during merge, and provides
    # methods to reconstruct the final merged dotenv file.
    #
    # @example Basic usage
    #   result = MergeResult.new(template_analysis, dest_analysis)
    #   result.add_from_template(0)
    #   result.add_from_destination(1)
    #   merged_content = result.to_s
    #
    # @see Ast::Merge::MergeResultBase
    class MergeResult < Ast::Merge::MergeResultBase
      # Decision indicating content was preserved from a freeze block
      # @return [Symbol]
      DECISION_FREEZE_BLOCK = :freeze_block

      # Decision indicating content came from the template
      # @return [Symbol]
      DECISION_TEMPLATE = :template

      # Decision indicating content came from the destination (customization preserved)
      # @return [Symbol]
      DECISION_DESTINATION = :destination

      # Decision indicating content was added from template (new in template)
      # @return [Symbol]
      DECISION_ADDED = :added

      # Initialize a new merge result
      # @param template_analysis [FileAnalysis] Analysis of the template file
      # @param dest_analysis [FileAnalysis] Analysis of the destination file
      # @param options [Hash] Additional options for forward compatibility
      def initialize(template_analysis, dest_analysis, **options)
        super(template_analysis: template_analysis, dest_analysis: dest_analysis, **options)
      end

      # Add content from the template at the given statement index
      # @param index [Integer] Statement index in template
      # @param decision [Symbol] Decision type (default: DECISION_TEMPLATE)
      # @return [void]
      def add_from_template(index, decision: DECISION_TEMPLATE)
        statement = @template_analysis.statements[index]
        return unless statement

        lines = extract_lines(statement)
        @lines.concat(lines)
        @decisions << { decision: decision, source: :template, index: index, lines: lines.length }
      end

      # Add content from the destination at the given statement index
      # @param index [Integer] Statement index in destination
      # @param decision [Symbol] Decision type (default: DECISION_DESTINATION)
      # @return [void]
      def add_from_destination(index, decision: DECISION_DESTINATION)
        statement = @dest_analysis.statements[index]
        return unless statement

        lines = extract_lines(statement)
        @lines.concat(lines)
        @decisions << { decision: decision, source: :destination, index: index, lines: lines.length }
      end

      # Add content from a freeze block
      # @param freeze_node [FreezeNode] The freeze block to add
      # @return [void]
      def add_freeze_block(freeze_node)
        lines = freeze_node.lines.map(&:raw)
        @lines.concat(lines)
        @decisions << {
          decision: DECISION_FREEZE_BLOCK,
          source: :destination,
          start_line: freeze_node.start_line,
          end_line: freeze_node.end_line,
          lines: lines.length
        }
      end

      # Add raw content lines
      # @param lines [Array<String>] Lines to add
      # @param decision [Symbol] Decision type
      # @return [void]
      def add_raw(lines, decision:)
        @lines.concat(lines)
        @decisions << { decision: decision, source: :raw, lines: lines.length }
      end

      # Convert the merged result to a string
      # @return [String] The merged dotenv content
      def to_s
        return '' if @lines.empty?

        # Join with newlines and ensure file ends with newline
        result = @lines.join("\n")
        result += "\n" unless result.end_with?("\n")
        result
      end

      # Check if any content has been added
      # @return [Boolean]
      def empty?
        @lines.empty?
      end

      # Get summary of merge decisions
      # @return [Hash] Summary with counts by decision type
      def summary
        counts = @decisions.group_by { |d| d[:decision] }.transform_values(&:count)
        {
          total_decisions: @decisions.length,
          total_lines: @lines.length,
          by_decision: counts
        }
      end

      private

      # Extract lines from a statement
      # @param statement [EnvLine, FreezeNode] The statement
      # @return [Array<String>]
      def extract_lines(statement)
        case statement
        when FreezeNode
          statement.lines.map(&:raw)
        when EnvLine
          [statement.raw]
        else
          []
        end
      end
    end
  end
end
