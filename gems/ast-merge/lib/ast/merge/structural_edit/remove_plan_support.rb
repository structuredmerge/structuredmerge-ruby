# frozen_string_literal: true

module Ast
  module Merge
    module StructuralEdit
      # Shared helpers for parser-agnostic RemovePlan assembly from one contiguous
      # statement run plus explicit neighboring boundary owners.
      module RemovePlanSupport
        module_function

        # Build a {RemovePlan} for a contiguous run of removed statements.
        #
        # @param analysis [Object] analysis exposing source and attachment hooks
        # @param statements [Array<Object>] removed statements
        # @param leading_statement [Object, nil] surviving statement before the run
        # @param trailing_statement [Object, nil] surviving statement after the run
        # @param source [Symbol, String, nil] optional metadata source tag
        # @return [RemovePlan, nil]
        def build_remove_plan(analysis:, statements:, leading_statement: nil, trailing_statement: nil, source: nil)
          return unless analysis.respond_to?(:source)

          statement_list = Array(statements)
          first_statement = statement_list.first
          last_statement = statement_list.last
          return unless first_statement && last_statement

          remove_start_line = BoundarySupport.statement_start_line(first_statement)
          remove_end_line = BoundarySupport.statement_end_line(last_statement)
          return if remove_start_line.nil? || remove_end_line.nil?

          RemovePlan.new(
            source: analysis.source,
            remove_start_line: remove_start_line,
            remove_end_line: remove_end_line,
            leading_boundary: BoundarySupport.build_splice_boundary(
              analysis,
              leading_statement,
              edge: :leading,
              source: source
            ),
            trailing_boundary: BoundarySupport.build_splice_boundary(
              analysis,
              trailing_statement,
              edge: :trailing,
              source: source
            ),
            removed_attachments: BoundarySupport.removed_statement_attachments_for(
              analysis,
              statement_list
            ),
            metadata: source ? { source: source } : {}
          )
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
