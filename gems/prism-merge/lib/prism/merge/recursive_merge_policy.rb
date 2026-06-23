# frozen_string_literal: true

module Prism
  module Merge
    class RecursiveMergePolicy
      attr_reader :merger

      def initialize(merger:)
        @merger = merger
      end

      def should_merge?(template_node:, dest_node:)
        return false unless template_node && dest_node
        return false if merger.instance_variable_get(:@current_depth) >= merger.max_recursion_depth

        actual_template = unwrap_node(template_node)
        actual_dest = unwrap_node(dest_node)
        return false unless canonical_type_of(actual_template) == canonical_type_of(actual_dest)
        return false unless multiline_wrapper?(actual_template) && multiline_wrapper?(actual_dest)

        case canonical_type_of(actual_template)
        when :class, :module, :singleton_class
          true
        when :call
          return false unless actual_template.block && actual_dest.block

          template_body = actual_template.block.body
          dest_body = actual_dest.block.body

          body_has_mergeable_statements?(template_body) && body_has_mergeable_statements?(dest_body)
        when :begin
          !!(merger.send(:begin_node_has_clause_or_body?,
                         actual_template) && merger.send(:begin_node_has_clause_or_body?, actual_dest))
        else
          false
        end
      end

      def body_has_mergeable_statements?(body)
        return false unless body.type.to_s == 'statements_node'
        return false if body.body.empty?

        body.body.any? { |statement| mergeable_statement?(statement) }
      end

      def mergeable_statement?(node)
        ct = NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
        %i[
          call
          def
          class
          module
          singleton_class
          const
          local_var
          ivar
          cvar
          gvar
          multi_write
          if
          unless
          case
          begin
        ].include?(ct)
      end

      private

      def unwrap_node(node)
        n = node.respond_to?(:unwrap) ? node.unwrap : node
        n.respond_to?(:node) ? n.node : n
      end

      def canonical_type_of(node)
        NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
      end

      def multiline_wrapper?(node)
        node.location.start_line < node.location.end_line
      end
    end
  end
end
