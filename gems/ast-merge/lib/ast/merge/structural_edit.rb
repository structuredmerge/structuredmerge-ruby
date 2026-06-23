# frozen_string_literal: true

module Ast
  module Merge
    # Shared structural editing primitives for replace/remove/rehome workflows.
    #
    # `Ast::Merge::StructuralEdit` is intentionally passive: it models edit
    # boundaries and splice plans without taking ownership of parser-specific
    # traversal or post-processing behavior.
    module StructuralEdit
      autoload :BoundarySupport, 'ast/merge/structural_edit/boundary_support'
      autoload :Boundary, 'ast/merge/structural_edit/boundary'
      autoload :PlanSet, 'ast/merge/structural_edit/plan_set'
      autoload :RemovePlanSupport, 'ast/merge/structural_edit/remove_plan_support'
      autoload :RehomePlan, 'ast/merge/structural_edit/rehome_plan'
      autoload :RemovePlan, 'ast/merge/structural_edit/remove_plan'
      autoload :SplicePlan, 'ast/merge/structural_edit/splice_plan'
    end
  end
end
