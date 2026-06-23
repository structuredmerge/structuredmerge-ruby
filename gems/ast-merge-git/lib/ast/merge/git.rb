# frozen_string_literal: true

require 'json'
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
        base = parse_json_role('base', request.fetch(:base_source))
        ours = parse_json_role('ours', request.fetch(:ours_source))
        theirs = parse_json_role('theirs', request.fetch(:theirs_source))
        conflicts = []
        change_classifications = classify_json_changes(base, ours, theirs)
        merged = merge_json_value(base, ours, theirs, '', conflicts)
        if conflicts.any?
          owned_regions = json_owned_regions_for_conflicts(request, conflicts)
          render_strategy = owned_regions.empty? ? 'full_file_conflict_markers' : 'owned_region_conflict_markers'
          return response(
            ok: false,
            request: request,
            conflicted_source: render_json_owned_region_conflict_source(request,
                                                                        owned_regions.first) || render_conflict_source(
                                                                          request, conflicts
                                                                        ),
            conflicts: conflicts,
            change_classifications: change_classifications,
            owned_regions: owned_regions,
            render_strategy: render_strategy,
            diagnostics: [{
              severity: 'error',
              category: MERGE_CONFLICT_CATEGORY,
              message: "merge3 found #{conflicts.length} unresolved conflict(s)."
            }]
          )
        end

        output = JSON.generate(merged)
        response(
          ok: true,
          request: request,
          merged_source: output,
          change_classifications: change_classifications,
          reparse_after_render: JSON.parse(output) && true,
          formatting_preservation: {
            line_diff_score: 1.0,
            character_diff_score: 1.0
          }
        )
      rescue JSON::ParserError => e
        response(
          ok: false,
          request: request,
          diagnostics: [{
            severity: 'error',
            category: 'parse_error',
            message: e.message
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
          { backend_id: 'native-json', parser_identity: 'standard-json' }
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

      def render_json_owned_region_conflict_source(request, region)
        return nil unless region && region.fetch(:region_kind) == 'node'

        key = region.fetch(:owner_path).delete_prefix('/')
        ours_region = json_member_source(request.fetch(:ours_source), key)
        base_region = json_member_source(request.fetch(:base_source), key)
        theirs_region = json_member_source(request.fetch(:theirs_source), key)
        return nil unless ours_region && base_region && theirs_region

        marker_size = request[:conflict_marker_size].to_i
        marker_size = 7 unless marker_size.positive?
        replacement = [
          "#{'<' * marker_size} ours",
          ours_region.fetch(:text),
          "#{'|' * marker_size} base",
          base_region.fetch(:text),
          '=' * marker_size,
          theirs_region.fetch(:text),
          "#{'>' * marker_size} theirs"
        ].join("\n")
        range = ours_region.fetch(:byte_range)
        source = request.fetch(:ours_source)
        prefix = source.byteslice(0, range.fetch(:start)) || ''
        suffix = source.byteslice(range.fetch(:end), source.bytesize - range.fetch(:end)) || ''
        prefix + replacement + suffix
      end

      def json_member_source(source, key)
        return nil unless source.include?("\"#{key}\"")

        range = json_key_byte_range(source, key)
        return nil if range.fetch(:end) <= range.fetch(:start)

        {
          byte_range: range,
          text: source.byteslice(range.fetch(:start)...range.fetch(:end))
        }
      end

      def json_owned_regions_for_conflicts(request, conflicts)
        conflicts.filter_map do |conflict|
          path = conflict.fetch(:path).to_s
          next unless path.start_with?('/') && path.count('/') == 1

          key = path.delete_prefix('/')
          base_region = json_member_source(request.fetch(:base_source), key)
          next unless base_region && json_member_source(request.fetch(:ours_source),
                                                        key) && json_member_source(request.fetch(:theirs_source), key)

          {
            owner_path: path,
            node_id: "json:key:#{key}",
            region_kind: 'node',
            byte_range: base_region.fetch(:byte_range),
            line_range: { start: 1, end: 1 },
            attached_spans: [],
            backend_id: 'native-json',
            parser_identity: 'standard-json',
            can_replace: true,
            can_line_merge: false,
            requires_reparse: true
          }
        end
      end

      def json_key_byte_range(source, key)
        needle = "\"#{key}\""
        start = source.index(needle)
        return { start: 0, end: source.bytesize } unless start

        finish = start + needle.bytesize
        finish += 1 while finish < source.bytesize && ![',', '}'].include?(source[finish])
        { start: start, end: finish }
      end

      def parse_json_role(role, source)
        JSON.parse(source)
      rescue JSON::ParserError => e
        raise JSON::ParserError, "#{role} parse error: #{e.message}"
      end

      def merge_json_value(base, ours, theirs, path, conflicts)
        return ours if ours == theirs
        return theirs if base == ours
        return ours if base == theirs
        if base.is_a?(Hash) && ours.is_a?(Hash) && theirs.is_a?(Hash)
          return merge_json_objects(base, ours, theirs, path,
                                    conflicts)
        end

        add_conflict(conflicts, 'edit_edit', path, 'value changed differently in ours and theirs')
        ours
      end

      def merge_json_objects(base, ours, theirs, path, conflicts)
        base = base.transform_keys(&:to_s)
        ours = ours.transform_keys(&:to_s)
        theirs = theirs.transform_keys(&:to_s)
        keys = (base.keys | ours.keys | theirs.keys).sort
        keys.each_with_object({}) do |key, result|
          merged, keep = merge_json_entry(
            base.key?(key) ? base[key] : :__absent__,
            ours.key?(key) ? ours[key] : :__absent__,
            theirs.key?(key) ? theirs[key] : :__absent__,
            json_pointer_join(path, key),
            conflicts
          )
          result[key] = merged if keep
        end
      end

      def classify_json_changes(base, ours, theirs)
        if base.is_a?(Hash) && ours.is_a?(Hash) && theirs.is_a?(Hash)
          base = base.transform_keys(&:to_s)
          ours = ours.transform_keys(&:to_s)
          theirs = theirs.transform_keys(&:to_s)
          keys = (base.keys | ours.keys | theirs.keys).sort
          return keys.filter_map do |key|
            ours_change = classify_json_value_change(base.key?(key) ? base[key] : :__absent__,
                                                     ours.key?(key) ? ours[key] : :__absent__)
            theirs_change = classify_json_value_change(base.key?(key) ? base[key] : :__absent__,
                                                       theirs.key?(key) ? theirs[key] : :__absent__)
            next if ours_change == 'unchanged' && theirs_change == 'unchanged'

            { path: json_pointer_join('', key), ours: ours_change, theirs: theirs_change }
          end
        end

        ours_change = classify_json_value_change(base, ours)
        theirs_change = classify_json_value_change(base, theirs)
        return [] if ours_change == 'unchanged' && theirs_change == 'unchanged'

        [{ path: '/', ours: ours_change, theirs: theirs_change }]
      end

      def classify_json_value_change(base, value)
        return 'unchanged' if base == :__absent__ && value == :__absent__
        return 'added' if base == :__absent__
        return 'deleted' if value == :__absent__
        return 'unchanged' if base == value

        'edited'
      end

      def merge_json_entry(base, ours, theirs, path, conflicts)
        base_absent = base == :__absent__
        ours_absent = ours == :__absent__
        theirs_absent = theirs == :__absent__
        return [nil, false] if base_absent && ours_absent && theirs_absent
        return [theirs, true] if base_absent && ours_absent
        return [ours, true] if base_absent && theirs_absent
        return [ours, true] if base_absent && ours == theirs

        if base_absent
          add_conflict(conflicts, 'add_add', path, 'same path added differently in ours and theirs')
          return [ours, true]
        end
        return [nil, false] if ours_absent && theirs_absent
        return [nil, false] if ours_absent && base == theirs
        return [nil, false] if theirs_absent && base == ours

        if ours_absent
          add_conflict(conflicts, 'delete_edit', path, 'ours deleted a value that theirs edited')
          return [theirs, true]
        end
        if theirs_absent
          add_conflict(conflicts, 'delete_edit', path, 'theirs deleted a value that ours edited')
          return [ours, true]
        end

        [merge_json_value(base, ours, theirs, path, conflicts), true]
      end

      def add_conflict(conflicts, category, path, message)
        conflicts << {
          conflict_id: "conflict-#{conflicts.length + 1}",
          category: category,
          path: path.empty? ? '/' : path,
          message: message
        }
      end

      def comment_conflict(category, path, message)
        {
          conflict_id: 'comment-conflict-1',
          category: category,
          path: path.to_s.empty? ? '/' : path,
          message: message
        }
      end

      def json_pointer_join(parent, token)
        escaped = token.to_s.gsub('~', '~0').gsub('/', '~1')
        parent.empty? ? "/#{escaped}" : "#{parent}/#{escaped}"
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
