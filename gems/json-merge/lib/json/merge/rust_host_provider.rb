# frozen_string_literal: true

require 'ast/merge'
require_relative 'typed_core_provider'

module Json
  module Merge
    # Compatibility name; no prototype dependency or host-owned merge logic.
    class RustHostProvider < TypedCoreProvider
    end
  end
end
