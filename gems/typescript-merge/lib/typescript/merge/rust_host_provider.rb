# frozen_string_literal: true

require 'ast/merge'
require 'ast/merge/typed_core_provider'

module TypeScript
  module Merge
    # Opt-in typed TypeScript/TSX declaration profile. Compatibility name, not a prototype dependency.
    class RustHostProvider < Ast::Merge::TypedCoreProvider
      PROVIDER_ID = 'rust.typescript'
      FAMILY = 'typescript'
      DIALECTS = %i[typescript tsx].freeze
      OPERATIONS = %i[analyze diff2 merge2 merge3].freeze
      CORE_PROVIDER = 'kernel.typescript'
      CORE_PROFILE = 'kernel.typescript.owners.v1'
      PACKAGE = 'typescript-merge'

      def capabilities
        super.merge(ast_ownership: :top_level_declarations).freeze
      end

      private

      def package_version = TypeScript::Merge::Version::VERSION
      def parser_language(dialect) = dialect
      def owner_path(owner) = owner.fetch('id')

      def additional_fields = %i[path_name labels conflict_marker_size]

      def policy(operation, request)
        # Git supplies neutral framing even to non-rendering providers. A path
        # is context, never a language selector. This profile emits no markers:
        # accept only empty labels and the default width, not custom requests.
        labels = request.fetch(:labels, {})
        width = request[:conflict_marker_size]
        width = Integer(width, 10) if width.is_a?(String)
        unless labels == {} && (width.nil? || (width.is_a?(Integer) && width == 7))
          raise ArgumentError, 'Typed TypeScript does not support custom conflict markers or labels'
        end

        super
      end
    end
  end
end
