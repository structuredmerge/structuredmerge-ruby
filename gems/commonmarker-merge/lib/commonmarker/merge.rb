# frozen_string_literal: true

require 'version_gem'
require_relative 'merge/version'

require 'markdown-merge'
require 'commonmarker'

module Commonmarker
  module Merge
    extend self

    PACKAGE_NAME = 'commonmarker-merge'
    BACKEND_REFERENCE = TreeHaver::BackendReference.new(id: 'commonmarker', family: 'native').freeze
    TreeHaver::BackendRegistry.register(BACKEND_REFERENCE)
    Markdown::Merge::WrapperSupport.install!(
      wrapper_module: self,
      require_prefix: 'commonmarker/merge',
      default_freeze_token: 'commonmarker-merge',
      default_inner_merge_code_blocks: false,
      registry_tag: :commonmarker_merge,
      merger_class: 'Commonmarker::Merge::SmartMerger'
    )

    def markdown_feature_profile
      Markdown::Merge.markdown_feature_profile
    end

    def available_markdown_backends
      [BACKEND_REFERENCE]
    end

    def markdown_backend_feature_profile(backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

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
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

      ::Commonmarker.parse(source)
      normalized = Markdown::Merge.normalize_source(source)
      {
        ok: true,
        diagnostics: [],
        analysis: {
          kind: 'markdown',
          dialect: dialect,
          normalized_source: normalized,
          root_kind: 'document',
          owners: Markdown::Merge.collect_markdown_owners(normalized)
        },
        policies: []
      }
    rescue StandardError => e
      {
        ok: false,
        diagnostics: [{ severity: 'error', category: 'parse_error', message: e.message }],
        policies: []
      }
    end

    def match_markdown_owners(template, destination)
      Markdown::Merge.match_markdown_owners(template, destination)
    end

    def merge_markdown(template_source, destination_source, dialect, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

      template = parse_markdown(template_source, dialect, backend: backend)
      return template unless template[:ok]

      destination = parse_markdown(destination_source, dialect, backend: backend)
      return destination unless destination[:ok]

      destination_sections = Markdown::Merge.collect_markdown_sections(
        destination.dig(:analysis, :normalized_source),
        destination.dig(:analysis, :owners)
      )
      template_sections = Markdown::Merge.collect_markdown_sections(
        template.dig(:analysis, :normalized_source),
        template.dig(:analysis, :owners)
      )
      destination_paths = destination_sections.to_h { |section| [section[:path], true] }
      merged_sections = destination_sections.map { |section| section[:text] }.reject(&:empty?) +
                        template_sections
                        .reject { |section| destination_paths[section[:path]] || section[:text].empty? }
                        .map { |section| section[:text] }

      {
        ok: true,
        diagnostics: [],
        output: "#{merged_sections.join("\n\n").strip}\n",
        policies: []
      }
    end

    def merge_markdown_with_reviewed_nested_outputs(template_source, destination_source, dialect, review_state,
                                                    applied_children, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs(
        template_source,
        destination_source,
        dialect,
        review_state,
        applied_children
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(template_source, destination_source, dialect,
                                                                       replay_bundle, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_replay_bundle(
        template_source,
        destination_source,
        dialect,
        replay_bundle
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(template_source, destination_source,
                                                                                dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_replay_bundle_envelope(
        template_source,
        destination_source,
        dialect,
        envelope
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state(template_source, destination_source, dialect,
                                                                      review_state, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

      Markdown::Merge.merge_markdown_with_reviewed_nested_outputs_from_review_state(
        template_source,
        destination_source,
        dialect,
        review_state
      )
    end

    def merge_markdown_with_reviewed_nested_outputs_from_review_state_envelope(template_source, destination_source,
                                                                               dialect, envelope, backend: nil)
      requested = backend.to_s.empty? ? BACKEND_REFERENCE.id : backend.to_s
      unless requested == BACKEND_REFERENCE.id
        return unsupported_feature_result("Unsupported Markdown backend #{requested}.")
      end

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
        diagnostics: [{ severity: 'error', category: 'unsupported_feature', message: message }],
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

Commonmarker::Merge.ensure_backend_loaded!

Commonmarker::Merge::Version.class_eval do
  extend VersionGem::Basic
end
