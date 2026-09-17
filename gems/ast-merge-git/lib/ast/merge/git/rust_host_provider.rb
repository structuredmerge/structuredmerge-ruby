# frozen_string_literal: true

require 'ast/merge'
require 'ast/merge/typed_core_provider'

module Ast
  module Merge
    module Git
      # Compatibility name only: Rust owns merge decisions and marker rendering.
      class RustHostProvider < Ast::Merge::TypedCoreProvider
        PROVIDER_ID = 'rust.git.json'
        FAMILY = 'json'
        OPERATIONS = [:merge3].freeze
        CORE_PROVIDER = 'kernel.git.json'
        CORE_PROFILE = 'kernel.git.json.v1'
        PACKAGE = 'ast-merge-git'

        private

        def package_version = Ast::Merge::Git::Version::VERSION

        # path_name is context, never a substitute for the explicit dialect.
        def additional_fields = %i[path_name labels conflict_marker_size]

        def policy(_operation, request)
          labels = request.fetch(:labels, {})
          raise ArgumentError, 'Git labels must be a Hash of text values' unless labels.is_a?(Hash) && labels.values.all? { |label| label.is_a?(String) }

          width = request[:conflict_marker_size]
          width = Integer(width, 10) if width.is_a?(String) # Git argv is textual.
          raise ArgumentError, 'Git marker width must be an Integer' unless width.nil? || width.is_a?(Integer)

          core::OperationPolicy.from_merge3(core::ThreeWayMergePolicy.new(
            render_policy: 'source-preserving', fallback_policy: 'none',
            labels: labels.transform_keys(&:to_s), conflict_marker_size: width, extra: {}))
        end
      end
    end
  end
end

Ast::Merge::Git.register_rust_host_provider! if Ast::Merge::Git::RustHostProvider.available?
