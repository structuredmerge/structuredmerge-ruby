# frozen_string_literal: true

module Ast
  module Merge
    # Shared runtime-charter value objects for orchestrating nested merge sessions
    # across format-specific merge gems.
    module Runtime
      autoload :ChildResult, 'ast/merge/runtime/child_result'
      autoload :Delegate, 'ast/merge/runtime/delegate'
      autoload :DelegationRegistry, 'ast/merge/runtime/delegation_registry'
      autoload :Diagnostic, 'ast/merge/runtime/diagnostic'
      autoload :Frame, 'ast/merge/runtime/frame'
      autoload :Operation, 'ast/merge/runtime/operation'
      autoload :ResolutionCase, 'ast/merge/runtime/resolution_case'
      autoload :RootSessionSupport, 'ast/merge/runtime/root_session_support'
      autoload :Session, 'ast/merge/runtime/session'
      autoload :Surface, 'ast/merge/runtime/surface'
    end
  end
end
