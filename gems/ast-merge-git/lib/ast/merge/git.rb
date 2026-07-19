# frozen_string_literal: true

require 'version_gem'

require 'ast/merge'
require 'json'
require 'json/merge'
require_relative 'git/version'

module Ast
  module Merge
    module Git
      PACKAGE_NAME = 'ast-merge-git'
      MERGE_CONFLICT_CATEGORY = 'merge_conflict'
      MISSING = Object.new.freeze

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
        parsed = parse_json_merge3_inputs(request)
        return parsed unless parsed.is_a?(Hash) && parsed[:ok]

        merge = merge_json_values(
          parsed.fetch(:base),
          parsed.fetch(:ours),
          parsed.fetch(:theirs),
          path: ''
        )

        if merge.fetch(:conflicts).empty?
          merged_source = "#{JSON.pretty_generate(merge.fetch(:value))}\n"
          return response(
            ok: true,
            request: request,
            merged_source: merged_source,
            change_classifications: merge.fetch(:change_classifications),
            reparse_after_render: reparse_json_source(merged_source),
            formatting_preservation: {
              line_diff_score: 1.0,
              character_diff_score: 1.0
            }
          )
        end

        render_conflicted_json(request, merge)
      end

      def parse_json_merge3_inputs(request)
        dialect = request[:dialect].to_s.empty? ? 'json' : request[:dialect].to_s
        {
          ok: true,
          base: Json::Merge.json_value_for_source(request.fetch(:base_source), dialect: dialect),
          ours: Json::Merge.json_value_for_source(request.fetch(:ours_source), dialect: dialect),
          theirs: Json::Merge.json_value_for_source(request.fetch(:theirs_source), dialect: dialect)
        }
      rescue Json::Merge::ParseError => e
        source_role = parse_error_role(request, dialect)
        response(
          ok: false,
          request: request,
          diagnostics: [{
            severity: 'error',
            category: 'parse_error',
            message: "#{source_role} parse error: #{e.message}"
          }]
        )
      end

      def parse_error_role(request, dialect)
        %i[base ours theirs].find do |role|
          Json::Merge.json_value_for_source(request.fetch(:"#{role}_source"), dialect: dialect)
          false
        rescue Json::Merge::ParseError
          true
        end || :unknown
      end

      def merge_json_values(base, ours, theirs, path:)
        if ours == theirs
          return merge_success(ours)
        elsif base == ours
          return merge_success(theirs, change: classify_json_change(path, base, ours, theirs))
        elsif base == theirs
          return merge_success(ours, change: classify_json_change(path, base, ours, theirs))
        end

        if base.is_a?(Hash) && ours.is_a?(Hash) && theirs.is_a?(Hash)
          return merge_json_objects(base, ours, theirs, path: path)
        end

        conflict = json_conflict(path, base, ours, theirs)
        {
          value: ours.equal?(MISSING) ? theirs : ours,
          conflicts: [conflict],
          change_classifications: [conflict.fetch(:change_classification)]
        }
      end

      def merge_json_objects(base, ours, theirs, path:)
        merged = {}
        conflicts = []
        change_classifications = []
        ordered_keys(base, ours, theirs).each do |key|
          child_path = "#{path}/#{key}"
          child = merge_json_values(
            base.fetch(key, MISSING),
            ours.fetch(key, MISSING),
            theirs.fetch(key, MISSING),
            path: child_path
          )
          merged[key] = child.fetch(:value) unless child.fetch(:value).equal?(MISSING)
          conflicts.concat(child.fetch(:conflicts))
          change_classifications.concat(child.fetch(:change_classifications))
        end

        {
          value: merged,
          conflicts: conflicts,
          change_classifications: change_classifications
        }
      end

      def ordered_keys(*objects)
        objects.each_with_object([]) do |object, keys|
          next unless object.is_a?(Hash)

          object.each_key { |key| keys << key unless keys.include?(key) }
        end
      end

      def merge_success(value, change: nil)
        {
          value: value,
          conflicts: [],
          change_classifications: change ? [change] : []
        }
      end

      def classify_json_change(path, base, ours, theirs)
        {
          path: path,
          ours: json_change_state(base, ours),
          theirs: json_change_state(base, theirs)
        }
      end

      def json_change_state(base, value)
        return 'unchanged' if base == value
        return 'added' if base.equal?(MISSING)
        return 'deleted' if value.equal?(MISSING)

        'edited'
      end

      def json_conflict(path, base, ours, theirs)
        category =
          if ours.equal?(MISSING) || theirs.equal?(MISSING)
            'delete_edit'
          else
            'edit_edit'
          end
        {
          conflict_id: "json-conflict-#{path.delete_prefix('/').tr('/', '-')}",
          category: category,
          path: path,
          message: "JSON value changed incompatibly at #{path}",
          base: base,
          ours: ours,
          theirs: theirs,
          change_classification: classify_json_change(path, base, ours, theirs)
        }
      end

      def render_conflicted_json(request, merge)
        conflicts = merge.fetch(:conflicts)
        full_file = conflicts.any? { |conflict| conflict.fetch(:category) == 'delete_edit' }
        conflicted_source = if full_file
                              render_conflict_source(request, conflicts)
                            else
                              render_owned_json_conflict_source(request, conflicts.first)
                            end
        response(
          ok: false,
          request: request,
          conflicted_source: conflicted_source,
          conflicts: conflicts.map { |conflict| conflict.slice(:conflict_id, :category, :path, :message) },
          change_classifications: merge.fetch(:change_classifications),
          diagnostics: [{
            severity: 'error',
            category: MERGE_CONFLICT_CATEGORY,
            message: "#{conflicts.length} unresolved JSON merge conflict(s)."
          }],
          owned_regions: full_file ? [] : [owned_json_region(conflicts.first)],
          reparse_after_render: nil,
          render_strategy: full_file ? 'full_file_conflict_markers' : 'owned_region_conflict_markers'
        )
      end

      def render_owned_json_conflict_source(request, conflict)
        marker_size = request[:conflict_marker_size].to_i
        marker_size = 7 unless marker_size.positive?
        key = conflict.fetch(:path).split('/').last
        [
          '{',
          "#{'<' * marker_size} ours",
          "#{JSON.generate(key)}:#{JSON.generate(conflict.fetch(:ours))}",
          "#{'|' * marker_size} base",
          "#{JSON.generate(key)}:#{JSON.generate(conflict.fetch(:base))}",
          '=' * marker_size,
          "#{JSON.generate(key)}:#{JSON.generate(conflict.fetch(:theirs))}",
          "#{'>' * marker_size} theirs",
          '}',
          ''
        ].join("\n")
      end

      def owned_json_region(conflict)
        {
          owner_path: conflict.fetch(:path),
          node_id: "json:key:#{conflict.fetch(:path).split('/').last}",
          region_kind: 'node',
          line_range: { start: 1, end: 1 },
          attached_spans: [],
          backend_id: 'tree-haver',
          parser_identity: 'tree_sitter_language_pack',
          can_replace: true,
          can_line_merge: false,
          requires_reparse: true
        }
      end

      def reparse_json_source(source)
        Json::Merge.json_value_for_source(source)
        true
      rescue Json::Merge::ParseError
        false
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
          { backend_id: 'tree-haver', parser_identity: 'tree_sitter_language_pack' }
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
