# frozen_string_literal: true

require "markdown-merge"
require "commonmarker"

module Commonmarker
  module Merge
    extend self

    PACKAGE_NAME = "commonmarker-merge"
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: "commonmarker", family: "native").freeze
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

      markdown_feature_profile.merge(backend: BACKEND_REFERENCE.id, backend_ref: BACKEND_REFERENCE.to_h)
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

      ::Commonmarker.parse(source)
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

    def merge_markdown(template_source, destination_source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown(template_source, destination_source, dialect, backend: "kreuzberg-language-pack")
    end

    def merge_markdown_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state, applied_children, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        review_state,
        applied_children,
        backend: "kreuzberg-language-pack"
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect, replay_bundle, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle,
        backend: "kreuzberg-language-pack"
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(
        template_source,
        destination_source,
        dialect,
        envelope,
        backend: "kreuzberg-language-pack"
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect, review_state, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state,
        backend: "kreuzberg-language-pack"
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope(
        template_source,
        destination_source,
        dialect,
        envelope,
        backend: "kreuzberg-language-pack"
      )
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
      :merge_markdown,
      :merge_markdown_with_reviewed_nested_outputs,
      :merge_markdown_with_reviewed_nested_outputs_from_replay_bundle,
      :merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope,
      :merge_markdown_with_reviewed_nested_outputs_from_review_state,
      :merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope,
      :markdown_embedded_families,
      :unsupported_feature_result
    )
  end
end
