# frozen_string_literal: true

require 'psych/merge'

module Psych
  module Merge
    module RSpec
      # Native Psych AST attributes retained by the workflow provider.
      module ProviderSnapshotExtension
        module_function

        def call(**arguments)
          ProviderExtension.call(**arguments)
        end
      end
    end
  end
end
