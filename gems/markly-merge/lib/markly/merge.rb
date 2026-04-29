# frozen_string_literal: true

require "markdown-merge"
require "markly"

module Markly
  module Merge
    extend self

    PACKAGE_NAME = "markly-merge"
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: "markly", family: "native").freeze
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

    def markdown_structured_edit_provider_profile
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_profile: {
          family: "markdown",
          structure_profile: Ast::Merge.structured_edit_structure_profile(
            owner_scope: "heading_sections",
            owner_selector: "heading_sections",
            owner_selector_family: "section_branch",
            known_owner_selector: true,
            supported_comment_regions: [],
            metadata: { family: "markdown", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          selection_profile: Ast::Merge.structured_edit_selection_profile(
            owner_scope: "heading_sections",
            owner_selector: "heading_sections",
            owner_selector_family: "section_branch",
            selector_kind: "heading_section",
            selection_intent: "section_branch",
            selection_intent_family: "section_branch",
            known_selection_intent: true,
            comment_region: nil,
            include_trailing_gap: false,
            comment_anchored: false,
            metadata: { family: "markdown", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          match_profile: Ast::Merge.structured_edit_match_profile(
            start_boundary: "owner_start",
            start_boundary_family: "structural_owner",
            known_start_boundary: true,
            end_boundary: "owner_end",
            end_boundary_family: "structural_owner",
            known_end_boundary: true,
            payload_kind: "section_branch",
            payload_family: "section_branch",
            known_payload_kind: true,
            comment_anchored: false,
            trailing_gap_extended: false,
            metadata: { family: "markdown", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          )
        }
      }
    end

    def markdown_structured_edit_request_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_request: Ast::Merge.structured_edit_request(
          operation_kind: "insert",
          content: "# Title\n\n## Usage\n\nExisting text.\n",
          source_label: "source",
          destination_selector: "/heading/usage",
          destination_selector_family: "section_branch",
          payload_text: "### Managed\n\nInserted text.\n",
          if_missing: "append",
          metadata: { family: "markdown", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def markdown_structured_edit_result_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_result: Ast::Merge.structured_edit_result(
          operation_kind: "insert",
          updated_content: "# Title\n\n## Usage\n\nExisting text.\n### Managed\n\nInserted text.\n",
          changed: true,
          operation_profile: Ast::Merge.structured_edit_operation_profile(
            operation_kind: "insert",
            operation_family: "insertion",
            known_operation_kind: true,
            source_requirement: "none",
            destination_requirement: "optional",
            replacement_source: "explicit_text",
            captures_source_text: false,
            supports_if_missing: true,
            metadata: { source: "legacy_crispr_reference" }
          ),
          destination_profile: Ast::Merge.structured_edit_destination_profile(
            resolution_kind: "append_fallback",
            resolution_source: "none",
            anchor_boundary: "none",
            resolution_family: "append",
            resolution_source_family: "implicit",
            anchor_boundary_family: "none",
            known_resolution_kind: true,
            known_resolution_source: true,
            known_anchor_boundary: true,
            used_if_missing: true,
            metadata: { family: "shared", source: "legacy_crispr_reference" }
          ),
          metadata: { family: "markdown", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def parse_markdown(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      ::Markly.parse(source, flags: ::Markly::DEFAULT, extensions: [:table])
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

      Markdown::Merge.merge_markdown(template_source, destination_source, dialect)
    end

    def merge_markdown_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state, applied_children, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        review_state,
        applied_children
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect, replay_bundle, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect, review_state, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Markdown backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
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
      :markdown_structured_edit_provider_profile,
      :markdown_structured_edit_request_projection,
      :markdown_structured_edit_result_projection,
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
