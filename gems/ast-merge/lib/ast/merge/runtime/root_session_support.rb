# frozen_string_literal: true

module Ast
  module Merge
    module Runtime
      # Shared helper for mergers that only need a charter-owned root session.
      module RootSessionSupport
        private

        def start_runtime_root_session!(
          surface_kind:,
          operation_id:, delegate_name:, declared_language: nil,
          effective_language: nil,
          requested_strategy: :merge,
          surface_address: 'document[0]',
          surface_metadata: {},
          policy_context: {},
          metadata: {},
          options: {},
          language_chain: nil,
          delegate_priority: 10,
          delegate_metadata: {}
        )
          root_surface = Surface.new(
            surface_kind: surface_kind,
            declared_language: declared_language,
            effective_language: effective_language,
            address: surface_address,
            metadata: surface_metadata
          )
          delegate = Delegate.new(
            name: delegate_name,
            priority: delegate_priority,
            surface_kinds: [root_surface.surface_kind],
            languages: [root_surface.effective_language || root_surface.declared_language].compact,
            capabilities: { merge: true },
            metadata: delegate_metadata
          )
          session = Session.new(
            policy_context: policy_context,
            metadata: metadata,
            delegation_registry: DelegationRegistry.new(delegates: [delegate])
          )
          root_operation = Operation.new(
            operation_id: operation_id,
            surface: root_surface,
            template_fragment: template_content,
            destination_fragment: dest_content,
            requested_strategy: requested_strategy,
            options: options,
            status: :running
          )

          session.register(
            root_operation,
            frame: Frame.new(
              operation_id: root_operation.operation_id,
              depth: 0,
              surface_path: root_surface.address,
              language_chain: Array(language_chain || [root_surface.effective_language || root_surface.declared_language]).compact
            ),
            delegate: session.resolve_delegate_for(root_surface, capability: :merge)
          )
          @runtime_session = session
          root_operation
        end

        def complete_runtime_root_session!(
          root_operation:,
          replacement_text:,
          metadata: {},
          capabilities_used: [],
          capabilities_missing: [],
          unresolved_cases: []
        )
          return unless @runtime_session && root_operation

          child_result = ChildResult.new(
            replacement_text: replacement_text,
            capabilities_used: capabilities_used,
            capabilities_missing: capabilities_missing,
            unresolved_cases: unresolved_cases,
            metadata: metadata
          )
          if child_result.unresolved?
            root_operation.unresolved!(result: child_result)
          else
            root_operation.complete!(result: child_result)
          end
        end

        def fail_runtime_root_session!(root_operation:, error:, kind: :merge_failed, severity: :error, metadata: {})
          return unless @runtime_session && root_operation

          diagnostic = Diagnostic.new(
            severity: severity,
            kind: kind,
            operation_id: root_operation.operation_id,
            surface_path: root_operation.surface.address,
            message: error.message,
            metadata: { error_class: error.class.name }.merge(metadata)
          )
          root_operation.fail!(diagnostic: diagnostic)
        end
      end
    end
  end
end
