# frozen_string_literal: true

require 'toml/merge/source_preserving_provider'

module Parslet
  module Toml
    # Parslet-backed TOML structural merge provider integration.
    module Merge
      # Conservative source-preserving provider configured for the Parslet backend.
      class Provider < ::Toml::Merge::SourcePreservingProvider
        PROVIDER_ID = 'ruby.toml.parslet'
        BACKEND = Merge::BACKEND
        PACKAGE_NAME = Merge::PACKAGE_NAME
        PACKAGE_VERSION = Version::VERSION
      end

      class << self
        def merge_provider
          @merge_provider ||= Provider.new
        end

        def register_provider!(replace: false)
          Ast::Merge.register_provider(merge_provider, replace: replace)
        end
      end
    end
  end
end
