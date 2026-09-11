# frozen_string_literal: true

require 'ast/merge'

module Bash
  module Merge
    # Opt-in Rust provider for the portable top-level function/assignment subset.
    # Test-harness titles and comment attachment remain Ruby-owned.
    class RustHostProvider < Ast::Merge::RustHostProvider
      def self.available?
        super(%i[parse_bash_analysis merge_bash_two_way merge_bash_three_way])
      end

      def initialize
        super(
          provider_id: 'rust.bash',
          family: 'bash',
          dialect: :bash,
          package: 'bash-merge',
          package_version: Bash::Merge::Version::VERSION,
          host_methods: {
            analyze: :parse_bash_analysis,
            merge2: :merge_bash_two_way,
            merge3: :merge_bash_three_way
          }
        )
      end

      def capabilities
        super.merge(ast_ownership: :top_level_functions_and_variable_assignments).freeze
      end
    end
  end
end
