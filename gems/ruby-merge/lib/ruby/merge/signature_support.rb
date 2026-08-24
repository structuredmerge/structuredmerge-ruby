# frozen_string_literal: true

module Ruby
  module Merge
    # Stable structural signatures used by Ruby owner and method matching.
    module SignatureSupport
      module_function

      def method_definition(name, params)
        [:def, name, Array(params)]
      end

      def class_definition(constant_path)
        [:class, constant_path]
      end

      def module_definition(constant_path)
        [:module, constant_path]
      end

      def singleton_class(expression)
        [:singleton_class, expression]
      end

      def constant(name)
        [:const, name]
      end

      def variable_assignment(kind, name)
        [kind, name]
      end

      def multi_write(targets)
        [:multi_write, Array(targets)]
      end

      def conditional(kind, predicate)
        [kind, predicate]
      end

      def case_statement(predicate)
        [:case, predicate || '']
      end

      def case_match_statement(predicate)
        [:case_match, predicate || '']
      end

      def loop_statement(kind, *parts)
        [kind, *parts]
      end

      def begin_block(first_statement_preview)
        [:begin, first_statement_preview || '']
      end

      def call(method_name, identifier, block: false)
        [block ? :call_with_block : :call, method_name, identifier]
      end

      def super_call(block:)
        [:super, block ? :with_block : :no_block]
      end

      def forwarding_super_call(block:)
        [:forwarding_super, block ? :with_block : :no_block]
      end

      def call_operator_write(write_name, receiver)
        [:call_op_write, write_name, receiver]
      end

      def lambda_literal(parameters_source)
        [:lambda, parameters_source || '']
      end

      def execution_block(kind, line_number)
        [kind, line_number]
      end

      def parenthesized(first_expression_preview)
        [:parens, first_expression_preview || '']
      end

      def embedded(statements_source)
        [:embedded, statements_source || '']
      end

      def other(class_name, line_number)
        [:other, class_name, line_number]
      end

      def textual_method_signature(receiver_prefix, method_name)
        "#{receiver_prefix}#{method_name}"
      end
    end
  end
end
