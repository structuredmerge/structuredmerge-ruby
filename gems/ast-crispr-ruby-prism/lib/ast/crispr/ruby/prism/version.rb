# frozen_string_literal: true

module Ast
  module Crispr
    module Ruby
      module Prism
        # Version namespace for this gem.
        module Version
          # Current gem version.
          VERSION = '7.1.4'
        end
        # Current gem version exposed at the traditional constant location.
        VERSION = Version::VERSION # Traditional Constant Location
      end
    end
  end
end
