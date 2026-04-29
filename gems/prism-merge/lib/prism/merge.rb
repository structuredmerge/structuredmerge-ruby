# frozen_string_literal: true

require "prism"
require "ruby-merge"

module Prism
  module Merge
    extend self

    PACKAGE_NAME = "prism-merge"
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: "prism", family: "native").freeze
    TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)

    def ruby_feature_profile
      Ruby::Merge.ruby_feature_profile
    end

    def available_ruby_backends
      [BACKEND_REFERENCE]
    end

    def ruby_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      ruby_feature_profile.merge(backend: BACKEND_REFERENCE.id, backend_ref: BACKEND_REFERENCE.to_h)
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

    def ruby_structured_edit_provider_profile
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_profile: {
          family: "ruby",
          structure_profile: Ast::Merge.structured_edit_structure_profile(
            owner_scope: "shared_default",
            owner_selector: "line_bound_statements",
            owner_selector_family: "line_oriented",
            known_owner_selector: true,
            supported_comment_regions: ["leading"],
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          selection_profile: Ast::Merge.structured_edit_selection_profile(
            owner_scope: "shared_default",
            owner_selector: "line_bound_statements",
            owner_selector_family: "line_oriented",
            selector_kind: "comment_region_owned_owner",
            selection_intent: "comment_anchored_owner",
            selection_intent_family: "comment_anchor",
            known_selection_intent: true,
            comment_region: "leading",
            include_trailing_gap: true,
            comment_anchored: true,
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          ),
          match_profile: Ast::Merge.structured_edit_match_profile(
            start_boundary: "comment_region_start",
            start_boundary_family: "comment_anchor",
            known_start_boundary: true,
            end_boundary: "owner_end_plus_trailing_gap",
            end_boundary_family: "gap_extension",
            known_end_boundary: true,
            payload_kind: "comment_owned_body",
            payload_family: "comment_owned",
            known_payload_kind: true,
            comment_anchored: true,
            trailing_gap_extended: true,
            metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
          )
        }
      }
    end

    def ruby_structured_edit_request_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_request: Ast::Merge.structured_edit_request(
          operation_kind: "replace",
          content: "class App\n  # managed snippet\n  old_call\nend\n",
          source_label: "source",
          target_selector: "managed_snippet",
          target_selector_family: "comment_anchor",
          payload_text: "new_call\n",
          metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_result_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_result: Ast::Merge.structured_edit_result(
          operation_kind: "replace",
          updated_content: "class App\n  # managed snippet\n  new_call\nend\n",
          changed: true,
          captured_text: "old_call\n",
          match_count: 1,
          operation_profile: Ast::Merge.structured_edit_operation_profile(
            operation_kind: "replace",
            operation_family: "rewrite",
            known_operation_kind: true,
            source_requirement: "required",
            destination_requirement: "none",
            replacement_source: "explicit_text",
            captures_source_text: true,
            supports_if_missing: false,
            metadata: { source: "legacy_crispr_reference" }
          ),
          metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_application_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_application: Ast::Merge.structured_edit_application(
          request: ruby_structured_edit_request_projection[:structured_edit_request],
          result: ruby_structured_edit_result_projection[:structured_edit_result],
          metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_execution_report_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_execution_report: Ast::Merge.structured_edit_execution_report(
          application: ruby_structured_edit_application_projection[:structured_edit_application],
          provider_family: "ruby",
          provider_backend: BACKEND_REFERENCE.id,
          diagnostics: [
            {
              severity: "warning",
              category: "assumed_default",
              message: "using managed snippet fallback selection."
            }
          ],
          metadata: { source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_batch_request_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_batch_request: Ast::Merge.structured_edit_batch_request(
          requests: [
            Ast::Merge.structured_edit_request(
              operation_kind: "replace",
              content: "class App\n  # managed snippet\n  old_call\n\n  # managed setup\n  setup_call\nend\n",
              source_label: "source",
              target_selector: "managed_snippet",
              target_selector_family: "comment_anchor",
              payload_text: "new_call\n",
              metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
            ),
            Ast::Merge.structured_edit_request(
              operation_kind: "replace",
              content: "class App\n  # managed snippet\n  old_call\n\n  # managed setup\n  setup_call\nend\n",
              source_label: "source",
              target_selector: "managed_setup",
              target_selector_family: "comment_anchor",
              payload_text: "configured_call\n",
              metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
            )
          ],
          metadata: { batch_label: "ruby_prism_pair", source: "legacy_crispr_reference" }
        )
      }
    end

    def ruby_structured_edit_batch_report_projection
      {
        package: PACKAGE_NAME,
        backend: BACKEND_REFERENCE.id,
        structured_edit_batch_report: Ast::Merge.structured_edit_batch_report(
          reports: [
            ruby_structured_edit_execution_report_projection[:structured_edit_execution_report],
            Ast::Merge.structured_edit_execution_report(
              application: Ast::Merge.structured_edit_application(
                request: Ast::Merge.structured_edit_request(
                  operation_kind: "replace",
                  content: "class App\n  # managed setup\n  setup_call\nend\n",
                  source_label: "source",
                  target_selector: "managed_setup",
                  target_selector_family: "comment_anchor",
                  payload_text: "configured_call\n",
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                result: Ast::Merge.structured_edit_result(
                  operation_kind: "replace",
                  updated_content: "class App\n  # managed setup\n  configured_call\nend\n",
                  changed: true,
                  captured_text: "setup_call\n",
                  match_count: 1,
                  operation_profile: Ast::Merge.structured_edit_operation_profile(
                    operation_kind: "replace",
                    operation_family: "rewrite",
                    known_operation_kind: true,
                    source_requirement: "required",
                    destination_requirement: "none",
                    replacement_source: "explicit_text",
                    captures_source_text: true,
                    supports_if_missing: false,
                    metadata: { source: "legacy_crispr_reference" }
                  ),
                  metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
                ),
                metadata: { family: "ruby", provider: BACKEND_REFERENCE.id, source: "legacy_crispr_reference" }
              ),
              provider_family: "ruby",
              provider_backend: BACKEND_REFERENCE.id,
              diagnostics: [],
              metadata: { source: "legacy_crispr_reference" }
            )
          ],
          diagnostics: [
            {
              severity: "info",
              category: "assumed_default",
              message: "ruby batch preserved request ordering."
            }
          ],
          metadata: { batch_label: "ruby_prism_pair", source: "legacy_crispr_reference" }
        )
      }
    end

    def parse_ruby(source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby dialect #{dialect}.") unless dialect == "ruby"
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

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

    def merge_ruby(template_source, destination_source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby(template_source, destination_source, dialect)
    end

    def merge_ruby_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state, applied_children, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        review_state,
        applied_children
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect, replay_bundle, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect, review_state, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state
      )
    end

    def merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source, dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      return unsupported_feature_result("Unsupported Ruby backend #{requested}.") unless requested == BACKEND_REFERENCE.id

      Ruby::Merge.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
      )
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
      :ruby_structured_edit_provider_profile,
      :ruby_structured_edit_request_projection,
      :ruby_structured_edit_result_projection,
      :ruby_structured_edit_application_projection,
      :ruby_structured_edit_execution_report_projection,
      :ruby_structured_edit_batch_request_projection,
      :ruby_structured_edit_batch_report_projection,
      :parse_ruby,
      :match_ruby_owners,
      :merge_ruby,
      :merge_ruby_with_reviewed_nested_outputs,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle,
      :merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state,
      :merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope,
      :ruby_discovered_surfaces,
      :ruby_delegated_child_operations,
      :unsupported_feature_result
    )
  end
end
