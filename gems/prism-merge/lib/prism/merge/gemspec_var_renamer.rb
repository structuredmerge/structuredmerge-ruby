# frozen_string_literal: true

module Prism
  module Merge
    # Backward-compatible name for the former gemspec-only receiver renamer.
    #
    # The implementation is generic because a block-local receiver has the same
    # structural semantics in a gemspec, RSpec configuration, or another DSL.
    class GemspecVarRenamer
      class << self
        def rename(source, old_var:, new_var:)
          BlockVarRenamer.rename(source, old_var: old_var, new_var: new_var)
        end
      end
    end
  end
end
