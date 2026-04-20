# frozen_string_literal: true

require "markdown-merge"

module Kramdown
  module Merge
    extend self

    PACKAGE_NAME = "kramdown-merge"
    BACKEND = "kramdown"

    def markdown_feature_profile
      Markdown::Merge.markdown_feature_profile
    end

    def available_markdown_backends
      [TreeHaver::BackendReference.new(id: BACKEND, family: "native")]
    end

    def markdown_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND

      markdown_feature_profile.merge(backend: BACKEND)
    end

    def markdown_plan_context(backend: nil)
      profile = markdown_backend_feature_profile(backend: backend)
      return profile if profile[:ok] == false

      {
        family_profile: markdown_feature_profile,
        feature_profile: {
          backend: profile[:backend],
          supports_dialects: true,
          supported_policies: []
        }
      }
    end

    def parse_markdown(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND

      Markdown::Merge.parse_markdown(source, dialect, backend: BACKEND)
    end

    def match_markdown_owners(template, destination)
      Markdown::Merge.match_markdown_owners(template, destination)
    end

    def unsupported_feature_result(message)
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "unsupported_feature", message: message }],
        policies: []
      }
    end

    module_function(
      :markdown_feature_profile,
      :available_markdown_backends,
      :markdown_backend_feature_profile,
      :markdown_plan_context,
      :parse_markdown,
      :match_markdown_owners,
      :unsupported_feature_result
    )
  end
end
