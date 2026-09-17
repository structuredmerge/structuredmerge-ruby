# frozen_string_literal: true

require 'ast/merge/typed_core_provider'

module Json
  module Merge
    class TypedCoreProvider < Ast::Merge::TypedCoreProvider
      PROVIDER_ID = 'rust.json'
      FAMILY = 'json'
      OPERATIONS = %i[analyze diff2 merge2 merge3].freeze
      CORE_PROVIDER = 'kernel.json'
      CORE_PROFILE = 'kernel.json.nested.v1'
      PACKAGE = 'json-merge'

      private

      def package_version = Json::Merge::Version::VERSION
    end
  end
end
