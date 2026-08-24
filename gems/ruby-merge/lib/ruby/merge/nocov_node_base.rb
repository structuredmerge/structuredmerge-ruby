# frozen_string_literal: true

module Ruby
  module Merge
    # Shared Ruby synthetic node for a balanced coverage-exclusion block.
    #
    # Parser-specific merge gems subclass this when they need native AST location
    # or comment attachment behavior. The structural Ruby semantics live here:
    # nocov blocks follow file preference and match by their inner content.
    # Nocov nodes preserve source locations and marker text as one structural
    # unit; the initializer mirrors the node's complete serialized shape.
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
    class NocovNodeBase
      include Ast::Merge::BlockDirective

      InvalidStructureError = Class.new(StandardError)

      Location = Struct.new(:start_line, :end_line) do
        def cover?(line)
          (start_line..end_line).cover?(line)
        end
      end

      attr_reader :start_line, :end_line, :nodes, :analysis, :start_marker, :close_marker

      def initialize(start_line:, end_line:, analysis:, nodes: [], start_marker: nil, close_marker: nil)
        @start_line = start_line
        @end_line = end_line
        @analysis = analysis
        @nodes = nodes
        @start_marker = start_marker
        @close_marker = close_marker
      end

      def kind = :nocov

      def children = @nodes

      def merge_policy = nil

      def location
        @location ||= Location.new(@start_line, @end_line)
      end

      def slice
        return unless @analysis

        lines = @analysis.lines
        return unless lines

        lines[(@start_line - 1)..(@end_line - 1)]&.join
      end

      def signature
        return [:NocovNode, nil] if @nodes.empty? || @analysis.nil?

        if @nodes.length == 1
          @analysis.generate_signature(@nodes.first)
        else
          inner_lines = @analysis.lines && @analysis.lines[@start_line..(@end_line - 2)]
          [:nocov_multi, inner_lines&.map(&:strip)&.join("\n")]
        end
      end

      def merge_type = :nocov_block

      alias type merge_type

      def nocov_node? = true

      def inspect
        "#<#{self.class} lines=#{@start_line}..#{@end_line} nodes=#{@nodes.length}>"
      end

      alias to_s inspect
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
