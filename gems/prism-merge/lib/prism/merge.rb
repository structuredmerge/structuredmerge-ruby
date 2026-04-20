# frozen_string_literal: true

require "prism"
require "ruby-merge"

module Prism
  module Merge
    extend self

    PACKAGE_NAME = "prism-merge"
    BACKEND = "prism"

    def ruby_feature_profile
      Ruby::Merge.ruby_feature_profile
    end

    def available_ruby_backends
      [TreeHaver::BackendReference.new(id: BACKEND, family: "native")]
    end

    def ruby_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND

      ruby_feature_profile.merge(backend: BACKEND)
    end

    def ruby_plan_context(backend: nil)
      profile = ruby_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: ruby_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: profile[:supported_policies]
        }
      }
    end

    def parse_ruby(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND

      result = ::Prism.parse(source)
      unless result.success?
        return {
          ok: false,
          diagnostics: result.errors.map do |error|
            { severity: "error", category: "parse_error", message: error.message }
          end,
          policies: []
        }
      end

      {
        ok: true,
        diagnostics: [],
        analysis: Ruby::Merge.analyze_ruby_document(source),
        policies: []
      }
    end

    def match_ruby_owners(template, destination)
      Ruby::Merge.match_ruby_owners(template, destination)
    end

    def ruby_discovered_surfaces(analysis)
      Ruby::Merge.ruby_discovered_surfaces(analysis)
    end

    def ruby_delegated_child_operations(analysis, parent_operation_id: "ruby-document-0")
      Ruby::Merge.ruby_delegated_child_operations(analysis, parent_operation_id: parent_operation_id)
    end

    def unsupported_feature_result(message)
      Ruby::Merge.unsupported_feature_result(message)
    end

    module_function(
      :ruby_feature_profile,
      :available_ruby_backends,
      :ruby_backend_feature_profile,
      :ruby_plan_context,
      :parse_ruby,
      :match_ruby_owners,
      :ruby_discovered_surfaces,
      :ruby_delegated_child_operations,
      :unsupported_feature_result
    )
  end
end
