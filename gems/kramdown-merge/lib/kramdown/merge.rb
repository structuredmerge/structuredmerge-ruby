# frozen_string_literal: true

require "markdown-merge"
require "kramdown"

module Kramdown
  module Merge
    extend self

    PACKAGE_NAME = "kramdown-merge"
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: "kramdown", family: "native").freeze
    TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

    def markdown_feature_profile
      Markdown::Merge.markdown_feature_profile
    end

    def available_markdown_backends
      [BACKEND_REFERENCE]
    end

    def markdown_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      markdown_feature_profile.merge(backend: BACKEND_REFERENCE.id)
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
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      return unsupported_feature_result("Unsupported Markdown dialect #{dialect}.") unless dialect == "markdown"

      ::Kramdown::Document.new(source)
      normalized = Markdown::Merge.normalize_source(source)
      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: "markdown",
          dialect: dialect,
          normalized_source: normalized,
          root_kind: "document",
          owners: Markdown::Merge.collect_markdown_owners(normalized)
        },
        policies: []
      }
    rescue StandardError => e
      {
        ok: false,
        diagnostics: [{ severity: "error", category: "parse_error", message: e.message }],
        policies: []
      }
    end

    def match_markdown_owners(template, destination)
      Markdown::Merge.match_markdown_owners(template, destination)
    end

    def markdown_embedded_families(analysis)
      Markdown::Merge.markdown_embedded_families(analysis)
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
      :markdown_embedded_families,
      :unsupported_feature_result
    )
  end
end
