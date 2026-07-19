# frozen_string_literal: true

require 'version_gem'

require 'ast/merge'
require_relative 'git/version'

module Ast
  module Merge
    module Git
      PACKAGE_NAME = 'ast-merge-git'
      MERGE_CONFLICT_CATEGORY = 'merge_conflict'

      module_function

      def merge3(request)
        normalized = normalize_request(request)
        case normalize_language(normalized)
        when 'json'
          merge3_json(normalized)
        else
          response(
            ok: false,
            request: normalized,
            diagnostics: [{
              severity: 'error',
              category: 'unsupported_feature',
              message: 'ast-merge-git currently supports only json merge3.'
            }]
          )
        end
      end

      def merge3_json(request)
        response(
          ok: false,
          request: request,
          diagnostics: [{
            severity: 'error',
            category: 'unsupported_feature',
            message: 'JSON merge3 must be rebuilt on top of Json::Merge and TreeHaver before ast-merge-git can use it.'
          }]
        )
      end

      def normalize_request(request)
        request.transform_keys(&:to_sym)
      end

      def merge_comment_delta(base_comment:, ours_comment:, theirs_comment:, owner_path: '/')
        conflicts = []
        merged_comment =
          if ours_comment == theirs_comment
            ours_comment
          elsif base_comment == ours_comment
            theirs_comment
          elsif base_comment == theirs_comment
            ours_comment
          elsif ours_comment.nil?
            conflicts << comment_conflict('delete_edit', owner_path, 'ours deleted a comment that theirs edited')
            theirs_comment
          elsif theirs_comment.nil?
            conflicts << comment_conflict('delete_edit', owner_path, 'theirs deleted a comment that ours edited')
            ours_comment
          else
            conflicts << comment_conflict('edit_edit', owner_path, 'comment changed differently in ours and theirs')
            ours_comment
          end

        {
          ok: conflicts.empty?,
          merged_comment: conflicts.empty? ? merged_comment : nil,
          conflicts: conflicts
        }
      end

      def response(ok:, request:, merged_source: nil, conflicted_source: nil, conflicts: [],
                   change_classifications: [], diagnostics: [], fallbacks: [], owned_regions: [], reparse_after_render: nil, formatting_preservation: {}, secondary_formatting_metrics: nil, render_strategy: nil)
        {
          ok: ok,
          merged_source: merged_source,
          conflicted_source: conflicted_source,
          conflicts: conflicts,
          change_classifications: change_classifications,
          diagnostics: diagnostics,
          fallbacks: fallbacks,
          owned_regions: owned_regions,
          profile: {
            profile_id: request[:profile_id].to_s,
            language: normalize_language(request),
            dialect: request[:dialect].to_s
          },
          render_report: {
            strategy: render_strategy || (request[:render_policy].to_s.empty? ? 'canonical' : request[:render_policy].to_s),
            **render_identity(request)
          },
          formatting_preservation: {
            line_diff_score: 0.0,
            character_diff_score: 0.0
          }.merge(formatting_preservation),
          secondary_formatting_metrics: secondary_formatting_metrics || secondary_formatting_metrics_for(ok && merged_source),
          default_driver_evaluation: default_driver_evaluation(
            formatting_preservation: {
              line_diff_score: 0.0,
              character_diff_score: 0.0
            }.merge(formatting_preservation),
            reparse_after_render: reparse_after_render,
            render_strategy: render_strategy || (request[:render_policy].to_s.empty? ? 'canonical' : request[:render_policy].to_s)
          ),
          reparse_after_render: reparse_after_render
        }
      end

      def default_driver_evaluation(formatting_preservation:, reparse_after_render:, render_strategy:)
        threshold = 0.95
        score = (formatting_preservation.fetch(:line_diff_score) + formatting_preservation.fetch(:character_diff_score)) / 2.0
        reparse_passed = reparse_after_render == true
        no_full_file_rewrite = render_strategy != 'full_file_conflict_markers'
        coherent_conflict_markers = render_strategy != 'full_file_conflict_markers'
        blocking_reasons = []
        blocking_reasons << 'rendered output did not reparse' unless reparse_passed
        blocking_reasons << 'formatting score is below threshold' if score < threshold
        blocking_reasons << 'full-file rewrite or conflict markers were used' unless no_full_file_rewrite
        blocking_reasons << 'conflict marker placement is not syntactically coherent' unless coherent_conflict_markers

        {
          status: blocking_reasons.empty? ? 'recommended' : 'not_recommended',
          formatting_threshold: threshold,
          formatting_score: score,
          hard_gates: [
            { name: 'reparse_after_render', passed: reparse_passed, weighted: false },
            { name: 'no_full_file_rewrite', passed: no_full_file_rewrite, weighted: false },
            { name: 'coherent_conflict_marker_placement', passed: coherent_conflict_markers, weighted: false }
          ],
          blocking_reasons: blocking_reasons,
          diagnostics: ['default-driver evaluation is advisory unless explicitly required']
        }
      end

      def secondary_formatting_metrics_for(merged)
        if merged
          {
            unchanged_line_churn: 0,
            output_diff_size: 0,
            source_fragment_retention: 1.0,
            weighted: false,
            diagnostics: ['canonical JSON has no trivia-preserving source fragments yet']
          }
        else
          {
            unchanged_line_churn: 0,
            output_diff_size: 0,
            source_fragment_retention: 0.0,
            weighted: false,
            diagnostics: ['unresolved conflict did not produce a merged source-fragment retention measurement']
          }
        end
      end

      def render_identity(request)
        case normalize_language(request)
        when 'json'
          { backend_id: 'tree-haver-required', parser_identity: 'json-merge-unavailable' }
        else
          {}
        end
      end

      def render_conflict_source(request, conflicts)
        marker_size = request[:conflict_marker_size].to_i
        marker_size = 7 unless marker_size.positive?
        header = "/* smorg structured conflicts: #{conflicts.length} unresolved */"
        [
          header,
          "#{'<' * marker_size} ours",
          request.fetch(:ours_source),
          "#{'|' * marker_size} base",
          request.fetch(:base_source),
          '=' * marker_size,
          request.fetch(:theirs_source),
          "#{'>' * marker_size} theirs",
          ''
        ].join("\n")
      end

      def comment_conflict(category, path, message)
        {
          conflict_id: 'comment-conflict-1',
          category: category,
          path: path.to_s.empty? ? '/' : path,
          message: message
        }
      end

      def normalize_language(request)
        language = request[:language].to_s.strip.downcase
        return 'json' if language == 'json'
        return 'json' if request[:path_name].to_s.downcase.end_with?('.json')

        language
      end
    end
  end
end

Ast::Merge::Git::Version.class_eval do
  extend VersionGem::Basic
end
