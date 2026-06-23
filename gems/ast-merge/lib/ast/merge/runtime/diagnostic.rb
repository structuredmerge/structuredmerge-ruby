# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Structured runtime event emitted during merge orchestration.
      class Diagnostic
        attr_reader :severity, :kind, :operation_id, :surface_path, :message, :metadata

        def initialize(severity:, kind:, operation_id:, surface_path:, message:, metadata: {})
          @severity = severity.to_sym
          @kind = kind.to_sym
          @operation_id = operation_id
          @surface_path = surface_path.to_s
          @message = message.to_s
          @metadata = metadata.dup.freeze
        end

        def error?
          severity == :error
        end

        def warning?
          severity == :warn
        end

        def to_h
          {
            severity: severity,
            kind: kind,
            operation_id: operation_id,
            surface_path: surface_path,
            message: message,
            metadata: metadata
          }
        end
      end
    end
  end
end
