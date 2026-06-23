# frozen_string_literal: true

module Ast
  module Merge
    module Text
      # Merge result for text-based AST merging.
      # Tracks merged lines and decisions made during the merge process.
      class MergeResult < MergeResultBase
        # Add a line to the result
        #
        # @param line [String] Line content to add
        # @return [void]
        def add_line(line)
          @lines << line
        end

        # Add multiple lines to the result
        #
        # @param lines [Array<String>] Lines to add
        # @return [void]
        def add_lines(lines)
          @lines.concat(lines)
        end

        # Record a merge decision
        #
        # @param decision [Symbol] Decision constant
        # @param template_node [Object, nil] Template node involved
        # @param dest_node [Object, nil] Destination node involved
        # @return [void]
        def record_decision(decision, template_node, dest_node)
          @decisions << {
            decision: decision,
            template_node: template_node,
            dest_node: dest_node,
            line: @lines.length
          }
        end
      end
    end
  end
end
