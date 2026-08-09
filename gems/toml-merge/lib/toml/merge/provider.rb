# frozen_string_literal: true

module Toml
  # Portable TOML workflow integration.
  module Merge
    # Source-preserving TOML workflow configured for kreuzberg-language-pack.
    class Provider < SourcePreservingProvider
      PROVIDER_ID = 'ruby.toml'
      BACKEND = TREE_SITTER_BACKEND_REFERENCE
      PACKAGE_NAME = Merge::PACKAGE_NAME
      PACKAGE_VERSION = Version::VERSION
      ROLE = :workflow
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
