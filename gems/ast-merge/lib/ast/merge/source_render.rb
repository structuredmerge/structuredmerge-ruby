# frozen_string_literal: true

module Ast
  module Merge
    # Language-neutral assembly of provider-selected source fragments.
    module SourceRender
      REVISION_ROLES = %i[base ours theirs].freeze
      FRAGMENT_KINDS = %i[source synthesized conflict].freeze

      class Error < Ast::Merge::Error; end
      class InvalidPlanError < Error; end

      autoload :ConflictFragment, 'ast/merge/source_render/fragment'
      autoload :SourceFragment, 'ast/merge/source_render/fragment'
      autoload :SynthesizedFragment, 'ast/merge/source_render/fragment'
      autoload :Plan, 'ast/merge/source_render/plan'
      autoload :Renderer, 'ast/merge/source_render/renderer'
      autoload :Result, 'ast/merge/source_render/result'
    end
  end
end
