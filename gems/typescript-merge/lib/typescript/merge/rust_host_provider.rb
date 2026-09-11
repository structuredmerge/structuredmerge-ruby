# frozen_string_literal: true

require 'ast/merge'

module TypeScript
  module Merge
    class RustHostProvider < Ast::Merge::RustHostProvider
      def self.available?
        super(%i[parse_typescript_analysis merge_typescript_two_way merge_typescript_three_way])
      end

      def initialize
        super(
          provider_id: 'rust.typescript',
          family: 'typescript',
          dialect: :typescript,
          package: 'typescript-merge',
          package_version: TypeScript::Merge::Version::VERSION,
          host_methods: {
            analyze: :parse_typescript_analysis,
            merge2: :merge_typescript_two_way,
            merge3: :merge_typescript_three_way
          }
        )
      end
    end
  end
end
