# frozen_string_literal: true

module Prism
  module Merge
    class BeginNodeStructure
      class << self
        def rescue_signature(rescue_node)
          exceptions = Array(rescue_node.exceptions).map do |exception_node|
            exception_node.respond_to?(:slice) ? exception_node.slice : exception_node.to_s
          end
          normalized_exceptions = exceptions.map { |exception| exception.to_s.sub(/\A::/, '') }
          if normalized_exceptions.empty? || normalized_exceptions == ['StandardError']
            [:standard_error]
          else
            normalized_exceptions.sort
          end
        end
      end

      attr_reader :node

      def initialize(node)
        @node = node
      end

      def boundary_lines
        return [node.location.start_line, node.location.end_line].uniq unless begin_node?

        [
          node.location.start_line,
          node.rescue_clause&.location&.start_line,
          node.else_clause&.location&.start_line,
          node.ensure_clause&.location&.start_line,
          node.location.end_line
        ].compact.uniq
      end

      def clause_start_line
        return unless begin_node?

        [
          node.rescue_clause&.location&.start_line,
          node.else_clause&.location&.start_line,
          node.ensure_clause&.location&.start_line
        ].compact.min
      end

      def rescue_nodes
        return [] unless begin_node?

        nodes = []
        current = node.rescue_clause
        while current.is_a?(Prism::RescueNode)
          nodes << current
          current = if current.respond_to?(:subsequent)
                      current.subsequent
                    else
                      current.consequent
                    end
        end
        nodes
      end

      def clause_regions
        return [] unless begin_node?

        rescue_occurrences = Hash.new(0)
        region_defs = rescue_nodes.map do |rescue_node|
          signature = self.class.rescue_signature(rescue_node)
          occurrence = rescue_occurrences[signature]
          rescue_occurrences[signature] += 1
          { type: [:rescue_clause, signature, occurrence], start_line: rescue_node.location.start_line }
        end
        if node.else_clause&.location
          region_defs << { type: :else_clause, start_line: node.else_clause.location.start_line }
        end
        if node.ensure_clause&.location
          region_defs << { type: :ensure_clause, start_line: node.ensure_clause.location.start_line }
        end

        region_defs.each_with_index.map do |region_def, index|
          next_start_line = region_defs[index + 1]&.dig(:start_line)
          {
            type: region_def[:type],
            start_line: region_def[:start_line],
            end_line: (next_start_line ? next_start_line - 1 : node.location.end_line - 1)
          }
        end
      end

      def clause_nodes_by_type
        return {} unless begin_node?

        rescue_occurrences = Hash.new(0)
        nodes_by_type = {}
        rescue_nodes.each do |rescue_node|
          signature = self.class.rescue_signature(rescue_node)
          occurrence = rescue_occurrences[signature]
          rescue_occurrences[signature] += 1
          nodes_by_type[[:rescue_clause, signature, occurrence]] = rescue_node
        end
        nodes_by_type[:else_clause] = node.else_clause if node.else_clause
        nodes_by_type[:ensure_clause] = node.ensure_clause if node.ensure_clause
        nodes_by_type
      end

      def has_clause_or_body?
        !!(begin_node? && (node.statements || node.rescue_clause || node.else_clause || node.ensure_clause))
      end

      def line_map_for(other_structure)
        return {} unless begin_node? && other_structure.begin_node?

        regions = clause_regions.each_with_object({}) { |region, by_type| by_type[region[:type]] = region }
        other_regions = other_structure.clause_regions.each_with_object({}) do |region, by_type|
          by_type[region[:type]] = region
        end

        regions.each_with_object({}) do |(type, region), mapping|
          other_region = other_regions[type]
          next unless other_region

          mapping[region[:start_line]] = other_region[:start_line]
        end
      end

      protected

      def begin_node?
        node.is_a?(Prism::BeginNode)
      end
    end
  end
end
