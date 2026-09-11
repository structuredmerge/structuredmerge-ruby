# frozen_string_literal: true

require 'ast/merge'

module Rust
  module Merge
    class RustHostProvider < Ast::Merge::RustHostProvider
      def self.available?
        super(%i[parse_rust_analysis merge_rust_two_way merge_rust_three_way])
      end

      def initialize
        super(
          provider_id: 'rust.rust',
          family: 'rust',
          dialect: :rust,
          package: 'rust-merge',
          package_version: Rust::Merge::Version::VERSION,
          host_methods: {
            analyze: :parse_rust_analysis,
            merge2: :merge_rust_two_way,
            merge3: :merge_rust_three_way
          }
        )
      end
    end
  end
end
