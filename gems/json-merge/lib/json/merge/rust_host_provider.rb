# frozen_string_literal: true

require 'ast/merge'

module Json
  module Merge
    # Opt-in JSON-family provider backed by the canonical Rust host.
    class RustHostProvider < Ast::Merge::RustHostProvider
      DIALECTS = %i[json jsonc json5].freeze

      def self.available?
        super(%i[parse_json_analysis merge_json_two_way merge_json_three_way])
      end

      def initialize
        super(
          provider_id: 'rust.json',
          family: 'json',
          dialect: :json,
          package: 'json-merge',
          package_version: Json::Merge::Version::VERSION,
          host_methods: {
            analyze: :parse_json_analysis,
            merge2: :merge_json_two_way,
            merge3: :merge_json_three_way
          }
        )
      end

      def capabilities
        super.merge(dialects: DIALECTS).freeze
      end
    end
  end
end
