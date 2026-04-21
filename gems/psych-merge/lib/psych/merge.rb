# frozen_string_literal: true

require "yaml"
require "tree_haver"
require "yaml/merge"

module Psych
  module Merge
    PACKAGE_NAME = "psych-merge"
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: "psych", family: "native").freeze
    TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

    module_function

    def yaml_feature_profile
      Yaml::Merge.yaml_feature_profile
    end

    def available_yaml_backends
      [BACKEND_REFERENCE]
    end

    def yaml_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported YAML backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      yaml_feature_profile.merge(
        backend: BACKEND_REFERENCE.id,
        backend_ref: BACKEND_REFERENCE.to_h
      )
    end

    def yaml_plan_context(backend: nil)
      profile = yaml_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: yaml_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_yaml(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_parse_result("Unsupported YAML backend #{requested}.") unless requested == BACKEND_REFERENCE.id
      return unsupported_feature_parse_result("Unsupported YAML dialect #{dialect}.") unless dialect == "yaml"

      parsed = YAML.safe_load(source, permitted_classes: [], aliases: false)
      Yaml::Merge.analyze_yaml_document(parsed, dialect)
    rescue StandardError => e
      parse_error_result(e.message)
    end

    def match_yaml_owners(template, destination)
      Yaml::Merge.match_yaml_owners(template, destination)
    end

    def merge_yaml(template_source, destination_source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_merge_result("Unsupported YAML backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Yaml::Merge.merge_yaml_with_parser(template_source, destination_source, dialect) do |source, parse_dialect|
        parse_yaml(source, parse_dialect, backend: requested)
      end
    end

    def parse_error_result(message)
      { ok: false, diagnostics: [{ severity: "error", category: "parse_error", message: message }], policies: [] }
    end
    private_class_method :parse_error_result

    def unsupported_feature_parse_result(message)
      { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }], policies: [] }
    end
    private_class_method :unsupported_feature_parse_result

    def unsupported_feature_merge_result(message)
      { ok: false, diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }], policies: [] }
    end
    private_class_method :unsupported_feature_merge_result

    def unsupported_feature_result(message)
      { ok: false, diagnostic: { severity: "error", category: "unsupported_feature", message: message } }
    end
    private_class_method :unsupported_feature_result
  end
end
