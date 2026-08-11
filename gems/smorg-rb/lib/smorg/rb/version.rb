# frozen_string_literal: true

module Smorg
  module RB
    # Version namespace for this gem.
    module Version
      # Current gem version.
      VERSION = '7.1.3'
    end
    # Current gem version exposed at the traditional constant location.
    VERSION = Version::VERSION # Traditional Constant Location
  end
end
