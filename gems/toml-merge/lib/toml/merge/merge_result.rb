# frozen_string_literal: true

module Toml
  module Merge
    # Tracks the result of a merge operation, including the merged content,
    # decisions made, and statistics.
    #
    # Inherits decision constants and base functionality from Ast::Merge::MergeResultBase.
    #
    # @example Basic usage
    #   result = MergeResult.new
    #   result.add_line('key = "value"', decision: :kept_template, source: :template)
    #   result.to_toml # => 'key = "value"\n'
    class MergeResult < Ast::Merge::MergeResultBase
      include Ast::Merge::StructuredReviewApplySupport

      # Inherit decision constants from base class
      DECISION_KEPT_TEMPLATE = Ast::Merge::MergeResultBase::DECISION_KEPT_TEMPLATE
      DECISION_KEPT_DEST = Ast::Merge::MergeResultBase::DECISION_KEPT_DEST
      DECISION_MERGED = Ast::Merge::MergeResultBase::DECISION_MERGED
      DECISION_ADDED = Ast::Merge::MergeResultBase::DECISION_ADDED

      # @return [Hash] Statistics about the merge
      attr_reader :statistics

      # @return [Array<Hash>] Raw line data for post-processing (e.g., sorting)
      def lines_array
        @lines
      end

      # Initialize a new merge result
      # @param options [Hash] Additional options for forward compatibility
      def initialize(**options)
        super(**options)
        @statistics = {
          template_lines: 0,
          dest_lines: 0,
          merged_lines: 0,
          total_decisions: 0
        }
      end

      # Add a single line to the result
      #
      # @param line [String] Line content
      # @param decision [Symbol] Decision that led to this line
      # @param source [Symbol] Source of the line (:template, :destination, :merged)
      # @param original_line [Integer, nil] Original line number
      def add_line(line, decision:, source:, original_line: nil)
        @lines << {
          content: line,
          decision: decision,
          source: source,
          original_line: original_line
        }

        track_statistics(decision, source)
        track_decision(decision, source, line: original_line)
      end

      # Add multiple lines to the result
      #
      # @param lines [Array<String>] Lines to add
      # @param decision [Symbol] Decision for all lines
      # @param source [Symbol] Source of the lines
      # @param start_line [Integer, nil] Starting original line number
      def add_lines(lines, decision:, source:, start_line: nil)
        lines.each_with_index do |line, idx|
          original_line = start_line ? start_line + idx : nil
          add_line(line, decision: decision, source: source, original_line: original_line)
        end
      end

      # Add a blank line
      #
      # @param decision [Symbol] Decision for the blank line
      # @param source [Symbol] Source
      def add_blank_line(decision: DECISION_MERGED, source: :merged)
        add_line('', decision: decision, source: source)
      end

      # Add content from a node wrapper
      #
      # @param node [NodeWrapper] Node to add
      # @param decision [Symbol] Decision that led to keeping this node
      # @param source [Symbol] Source of the node
      # @param analysis [FileAnalysis] Analysis for accessing source lines
      def add_node(node, decision:, source:, analysis:)
        return unless node.start_line

        # Use effective_end_line for tables to include associated pairs on Citrus backend
        # (Citrus has flat structure where pairs are siblings, not children of tables)
        end_line = node.respond_to?(:effective_end_line) ? node.effective_end_line : node.end_line
        return unless end_line

        (node.start_line..end_line).each do |line_num|
          line = analysis.line_at(line_num)
          next unless line

          add_line(line.chomp, decision: decision, source: source, original_line: line_num)
        end
      end

      # Get the merged content as a TOML string
      #
      # @return [String]
      def to_toml
        content = @lines.map { |l| l[:content] }.join("\n")
        # Ensure trailing newline
        content += "\n" unless content.end_with?("\n") || content.empty?
        content
      end

      # Alias for to_toml
      # @return [String]
      def content
        to_toml
      end

      # Alias for to_toml (used by SmartMerger#merge)
      # @return [String]
      def to_s
        to_toml
      end

      # Get line count
      # @return [Integer]
      def line_count
        @lines.size
      end

      private

      def track_statistics(decision, _source)
        @statistics[:total_decisions] += 1

        case decision
        when DECISION_KEPT_TEMPLATE
          @statistics[:template_lines] += 1
        when DECISION_KEPT_DEST
          @statistics[:dest_lines] += 1
        else
          @statistics[:merged_lines] += 1
        end
      end
    end
  end
end
