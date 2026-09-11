# frozen_string_literal: true

require 'ast/merge'

module Bash
  module Merge
    # Opt-in Rust provider for the portable top-level function/assignment and
    # literal-title test-harness subset. Comments remain Ruby-owned.
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
        super.merge(ast_ownership: :top_level_functions_assignments_and_literal_test_titles).freeze
      end
    end
  end
end
