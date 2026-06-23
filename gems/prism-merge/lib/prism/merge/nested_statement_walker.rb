# frozen_string_literal: true

module Prism
  module Merge
    # Shared recursive traversal helpers for nested Prism statement bodies.
    #
    # This stays in prism-merge rather than ast-merge because the reusable seam is
    # Prism node structure (`CallNode` blocks plus conditional branches), not a
    # parser-agnostic merge primitive.
    module NestedStatementWalker
      module_function

      def walk(body_node, &block)
        return enum_for(__method__, body_node) unless block

        extract_statements(body_node).each do |node|
          yield node
          nested_statement_children(node).each do |child|
            walk(child[:body], &block)
          end
        end
      end

      def walk_with_context(body_node, next_context:, context_stack: [], &block)
        return enum_for(__method__, body_node, context_stack: context_stack, next_context: next_context) unless block

        extract_statements(body_node).each do |node|
          yield node, context_stack

          nested_statement_children(node).each do |child|
            walk_with_context(
              child[:body],
              context_stack: next_context.call(
                node: node,
                child_kind: child[:kind],
                current_context: context_stack
              ),
              next_context: next_context,
              &block
            )
          end
        end
      end

      def nested_statement_children(node)
        case NodeTypeNormalizer.canonical_type(node.type.to_s, :prism)
        when :call
          node.block ? [{ kind: :call_block, body: node.block.body }] : []
        when :if
          conditional_children(node, :if_body, :if_subsequent)
        when :unless
          conditional_children(node, :unless_body, :unless_subsequent)
        when :else
          node.statements ? [{ kind: :else_body, body: node.statements }] : []
        else
          []
        end
      end

      def extract_statements(body_node)
        return [] unless body_node

        body = body_node.respond_to?(:body) ? body_node.body : nil
        return body if body.is_a?(Array)

        statements = body_node.respond_to?(:statements) ? body_node.statements : nil
        statement_body = statements.respond_to?(:body) ? statements.body : nil
        return statement_body if statement_body.is_a?(Array)

        []
      end

      def conditional_children(node, body_kind, subsequent_kind)
        children = []
        children << { kind: body_kind, body: node.statements } if node.statements
        children << { kind: subsequent_kind, body: node.subsequent } if node.respond_to?(:subsequent) && node.subsequent
        children
      end
      private_class_method :conditional_children
    end
  end
end
