# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # One merge attempt over one owned surface.
      class Operation
        attr_reader :operation_id,
                    :surface,
                    :template_fragment,
                    :destination_fragment,
                    :requested_strategy,
                    :options,
                    :result,
                    :diagnostics,
                    :children,
                    :delegate_name,
                    :status

        def initialize(
          operation_id:,
          surface:,
          template_fragment:,
          destination_fragment:,
          requested_strategy: nil,
          options: {},
          result: nil,
          diagnostics: [],
          children: [],
          status: :pending
        )
          @operation_id = operation_id
          @surface = surface
          @template_fragment = template_fragment.to_s
          @destination_fragment = destination_fragment.to_s
          @requested_strategy = requested_strategy&.to_sym
          @options = options.dup.freeze
          @result = result
          @diagnostics = Array(diagnostics).dup
          @children = Array(children).dup
          @delegate_name = nil
          @status = status.to_sym
        end

        def add_child(child_operation)
          @children << child_operation
          child_operation
        end

        def add_diagnostic(diagnostic)
          @diagnostics << diagnostic
          diagnostic
        end

        def running!
          @status = :running
          self
        end

        def assign_delegate!(delegate)
          @delegate_name = delegate&.name&.to_s
          self
        end

        def complete!(result:)
          @result = result
          @status = :completed
          self
        end

        def unresolved!(result:, diagnostic: nil)
          @result = result
          add_diagnostic(diagnostic) if diagnostic
          @status = :unresolved
          self
        end

        def fail!(diagnostic: nil)
          add_diagnostic(diagnostic) if diagnostic
          @status = :failed
          self
        end

        def completed?
          status == :completed
        end

        def failed?
          status == :failed
        end

        def unresolved?
          status == :unresolved
        end

        def delegate_assigned?
          !delegate_name.nil?
        end

        def to_h
          {
            operation_id: operation_id,
            surface: surface.respond_to?(:to_h) ? surface.to_h : surface,
            requested_strategy: requested_strategy,
            options: options,
            result: result.respond_to?(:to_h) ? result.to_h : result,
            diagnostics: diagnostics.map { |diagnostic| diagnostic.respond_to?(:to_h) ? diagnostic.to_h : diagnostic },
            children: children.map { |child| child.respond_to?(:operation_id) ? child.operation_id : child },
            delegate_name: delegate_name,
            status: status
          }.compact
        end
      end
    end
  end
end
