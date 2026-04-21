# frozen_string_literal: true

require "toml-merge"
require "toml-rb"

module Citrus
  module Toml
    module Merge
      extend self

      PACKAGE_NAME = "citrus-toml-merge"
      BACKEND = TreeHaver::CITRUS_BACKEND

      def toml_feature_profile
        ::Toml::Merge.toml_feature_profile
      end

      def available_toml_backends
        [BACKEND]
      end

      def toml_backend_feature_profile(backend: nil)
        requested = backend.to_s.empty? ? BACKEND.id : backend.to_s
        return unsupported_feature_result("Unsupported TOML backend #{requested}.") unless requested == BACKEND.id

        toml_feature_profile.merge(
          backend: BACKEND.id,
          backend_ref: BACKEND.to_h
        )
      end

      def toml_plan_context(backend: nil)
        profile = toml_backend_feature_profile(backend: backend)
        return profile if profile[:ok] == false

        {
          family_profile: toml_feature_profile,
          feature_profile: {
            backend: profile[:backend],
            supports_dialects: false,
            supported_policies: profile[:supported_policies]
          }
        }
      end

      def parse_toml(source, dialect, backend: nil)
        requested = backend.to_s.empty? ? BACKEND.id : backend.to_s
        return unsupported_feature_result("Unsupported TOML backend #{requested}.") unless requested == BACKEND.id
        return unsupported_feature_result("Unsupported TOML dialect #{dialect}.") unless dialect == "toml"

        syntax_result = TreeHaver.parse_with_citrus(source, grammar_module: TomlRB::Document)
        return { ok: false, diagnostics: syntax_result[:diagnostics], policies: [] } unless syntax_result[:ok]

        ::Toml::Merge.analyze_toml_source(source, dialect)
      end

      def match_toml_owners(template, destination)
        ::Toml::Merge.match_toml_owners(template, destination)
      end

      def merge_toml(template_source, destination_source, dialect, backend: nil)
        requested = backend.to_s.empty? ? BACKEND.id : backend.to_s
        return unsupported_feature_result("Unsupported TOML backend #{requested}.") unless requested == BACKEND.id

        ::Toml::Merge.merge_toml_with_parser(template_source, destination_source, dialect) do |source, parse_dialect|
          parse_toml(source, parse_dialect, backend: BACKEND.id)
        end
      end

      def unsupported_feature_result(message)
        {
          ok: false,
          diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }],
          policies: []
        }
      end

      module_function(
        :toml_feature_profile,
        :available_toml_backends,
        :toml_backend_feature_profile,
        :toml_plan_context,
        :parse_toml,
        :match_toml_owners,
        :merge_toml,
        :unsupported_feature_result
      )
    end
  end
end
