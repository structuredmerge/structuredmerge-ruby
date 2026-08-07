# frozen_string_literal: true

require 'toml-rb'
require 'toml-merge'

module Citrus
  module Toml
    module Merge
      module_function

      PACKAGE_NAME = 'citrus-toml-merge'
      BACKEND = TreeHaver::CITRUS_BACKEND
      BACKEND_REGISTRY = Struct.new(:registered, :mutex).new(false, Mutex.new)

      def register_backend!
        BACKEND_REGISTRY.mutex.synchronize do
          return if BACKEND_REGISTRY.registered

          TreeHaver.register_language(
            :toml,
            grammar_module: TomlRB::Document,
            gem_name: 'toml-rb'
          )

          BACKEND_REGISTRY.registered = true
        end
      end

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
        return unsupported_feature_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        TreeHaver.with_backend(BACKEND.id) { ::Toml::Merge.analyze_toml_source(source, dialect) }
      end

      def match_toml_owners(template, destination)
        ::Toml::Merge.match_toml_owners(template, destination)
      end

      def merge_toml(template_source, destination_source, dialect, backend: nil)
        requested = backend.to_s.empty? ? BACKEND.id : backend.to_s
        return unsupported_feature_result("Unsupported TOML backend #{requested}.") unless requested == BACKEND.id

        return unsupported_feature_result("Unsupported TOML dialect #{dialect}.") unless dialect == 'toml'

        template_parse = parse_toml(template_source, dialect, backend: BACKEND.id)
        return provider_parse_failure(:template_parse_error, template_parse) unless template_parse[:ok]

        destination_parse = parse_toml(destination_source, dialect, backend: BACKEND.id)
        return provider_parse_failure(:destination_parse_error, destination_parse) unless destination_parse[:ok]

        output = SmartMerger.new(
          template_source,
          destination_source,
          preference: :destination,
          add_template_only_nodes: true
        ).merge_result.to_toml

        {
          ok: true,
          diagnostics: [],
          output: output,
          policies: [::Toml::Merge::DESTINATION_WINS_ARRAY_POLICY]
        }
      rescue ::Toml::Merge::TemplateParseError => e
        { ok: false, diagnostics: [{ severity: 'error', category: 'template_parse_error', message: e.message }],
          policies: [] }
      rescue ::Toml::Merge::DestinationParseError => e
        { ok: false, diagnostics: [{ severity: 'error', category: 'destination_parse_error', message: e.message }],
          policies: [] }
      rescue StandardError => e
        { ok: false, diagnostics: [{ severity: 'error', category: 'merge_error', message: e.message }], policies: [] }
      end

      def unsupported_feature_result(message)
        {
          ok: false,
          diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
          policies: []
        }
      end

      def provider_parse_failure(category, parse_result)
        diagnostics = Array(parse_result[:diagnostics])
        message = diagnostics.map { |diagnostic| diagnostic[:message] || diagnostic['message'] }.compact.join('; ')
        message = 'provider parse failed' if message.empty?
        { ok: false, diagnostics: [{ severity: 'error', category: category.to_s, message: message }], policies: [] }
      end

      module_function(
        :toml_feature_profile,
        :register_backend!,
        :available_toml_backends,
        :toml_backend_feature_profile,
        :toml_plan_context,
        :parse_toml,
        :match_toml_owners,
        :merge_toml,
        :unsupported_feature_result,
        :provider_parse_failure
      )

      class SmartMerger < ::Toml::Merge::SmartMerger
        def initialize(...)
          TreeHaver.with_backend(::Citrus::Toml::Merge::BACKEND.id) { super }
        end

        def merge_result
          TreeHaver.with_backend(::Citrus::Toml::Merge::BACKEND.id) { super }
        end
      end
    end
  end
end

Citrus::Toml::Merge.register_backend!
