# frozen_string_literal: true

module Ast
  module Merge
    # Namespace for compact merge-ruleset parsing and validation.
    module Ruleset
      autoload :Config, 'ast/merge/ruleset/config'
      autoload :DelegationPolicy, 'ast/merge/ruleset/delegation_policy'
      autoload :FeatureProfile, 'ast/merge/ruleset/feature_profile'
      autoload :LogicalOwnerPolicy, 'ast/merge/ruleset/logical_owner_policy'
      autoload :Parser, 'ast/merge/ruleset/parser'
      autoload :ProfileVocabulary, 'ast/merge/ruleset/profile_vocabulary'
      autoload :RepairPolicy, 'ast/merge/ruleset/repair_policy'
      autoload :RuntimeDeclaration, 'ast/merge/ruleset/runtime_declaration'
      autoload :RuntimeTranslator, 'ast/merge/ruleset/runtime_translator'
      autoload :SurfaceDeclaration, 'ast/merge/ruleset/surface_declaration'
      autoload :SupportStyleResolver, 'ast/merge/ruleset/support_style_resolver'
    end
  end
end
