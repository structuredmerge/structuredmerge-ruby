# frozen_string_literal: true

require 'ast/merge'

module Go
  module Merge
    class RustHostProvider < Ast::Merge::RustHostProvider
      def self.available?
        super(%i[parse_go_analysis merge_go_two_way merge_go_three_way])
      end

      def initialize
        super(
          provider_id: 'rust.go',
          family: 'go',
          dialect: :go,
          package: 'go-merge',
          package_version: Go::Merge::Version::VERSION,
          host_methods: {
            analyze: :parse_go_analysis,
            merge2: :merge_go_two_way,
            merge3: :merge_go_three_way
          }
        )
      end
    end
  end
end
