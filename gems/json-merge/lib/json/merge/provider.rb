# frozen_string_literal: true

module Json
  module Merge
    # Portable JSON-family provider for Ast::Merge dispatch.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider operations keep request, rendering, and result-envelope logic together
    class Provider
      DIALECTS = %i[json jsonc json5].freeze
      DEFAULT_PROFILE = :source_preserving

      def provider_id
        'ruby.json'
      end

      def family
        'json'
      end

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: DIALECTS,
          backends: [Json::Merge::TREE_SITTER_BACKEND.id.to_sym],
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          source_preservation: %i[exact_source family_synthesis line_provenance reparse]
        }.freeze
      end

      def analyze(request)
        dialect = dialect_for(request)
        parsed = Json::Merge.parse_json(request.fetch(:source), dialect, backend: request[:backend])
        return parse_failure(:analyze, :source, parsed, request) unless parsed[:ok]

        result(
          :analyze,
          request,
          analysis: parsed.fetch(:analysis),
          verification: { source_parsed: true }
        )
      end

      def diff2(request)
        before = parse_role!(:diff2, request, :before)
        return before if provider_failure?(before)

        after = parse_role!(:diff2, request, :after)
        return after if provider_failure?(after)

        changes = diff_values(before, after, path: '')
        result(
          :diff2,
          request,
          diff: { changes: changes, before: before, after: after },
          changes: changes,
          verification: { before_parsed: true, after_parsed: true }
        )
      end

      def merge2(request)
        dialect = dialect_for(request)
        merged = Json::Merge.merge_json(
          request.fetch(:incoming_source),
          request.fetch(:current_source),
          dialect,
          backend: request[:backend]
        )
        return merge2_failure(merged, request) unless merged[:ok]

        output = merged.fetch(:output)
        verified = parse_output(output, request)
        result(
          :merge2,
          request,
          output: output,
          changes: [],
          render_report: { strategy: :json_smart_merger, synthesis: :family_emission },
          verification: { output_reparsed: true, semantic_value: verified }
        )
      rescue Json::Merge::ParseError => e
        failure(
          :merge2,
          request,
          category: :render_failure,
          message: "JSON family emitter produced invalid output: #{e.message}"
        )
      end

      def merge3(request)
        values = parse_merge3_roles(request)
        return values if provider_failure?(values)

        decision = ThreeWayDecision.new.call(**values)
        rendered = render_merge3(decision, request, values)
        return rendered if provider_failure?(rendered)

        result(
          :merge3,
          request,
          **rendered,
          changes: decision.changes,
          conflicts: decision.conflicts,
          verification: rendered.fetch(:verification).merge(base_participated: true)
        )
      end

      private

      def parse_merge3_roles(request)
        %i[base ours theirs].each_with_object({}) do |role, values|
          parsed = parse_role!(:merge3, request, role)
          return parsed if provider_failure?(parsed)

          values[role] = parsed
        end
      end

      def parse_role!(operation, request, role)
        Json::Merge.json_value_for_source(
          request.fetch(:"#{role}_source"),
          dialect: dialect_for(request),
          backend: request[:backend]
        )
      rescue Json::Merge::ParseError => e
        failure(
          operation,
          request,
          category: :parse_error,
          message: "#{role} parse error: #{e.message}",
          source_role: role
        )
      end

      def render_merge3(decision, request, values)
        return render_conflict(request, decision) if decision.conflicted?

        exact_role = %i[ours theirs base].find { |role| values.fetch(role) == decision.value }
        return render_exact_role(exact_role, request, decision) if exact_role

        render_composite(request, decision)
      end

      def diff_values(before, after, path:)
        return [] if before == after
        return diff_objects(before, after, path: path) if before.is_a?(Hash) && after.is_a?(Hash)

        [{ path: path, ours: :unchanged, theirs: :edited }.freeze]
      end

      def diff_objects(before, after, path:)
        ordered_diff_keys(before, after).flat_map do |key|
          child_path = "#{path}/#{escape_path_segment(key)}"
          if !before.key?(key)
            [{ path: child_path, ours: :unchanged, theirs: :added }.freeze]
          elsif !after.key?(key)
            [{ path: child_path, ours: :unchanged, theirs: :deleted }.freeze]
          else
            diff_values(before.fetch(key), after.fetch(key), path: child_path)
          end
        end.freeze
      end

      def ordered_diff_keys(before, after)
        [*before.keys, *after.keys].uniq
      end

      def escape_path_segment(key)
        key.to_s.gsub('~', '~0').gsub('/', '~1')
      end

      def render_exact_role(role, request, decision)
        rendered = render_plan(
          request,
          [
            source_fragment(role, request.fetch(:"#{role}_source"))
          ]
        )
        {
          output: rendered.content,
          render_report: render_report(rendered, strategy: :exact_revision),
          verification: verify_rendered(rendered.content, decision.value, request)
        }
      end

      def render_composite(request, decision)
        candidate = Json::Merge.merge_json(
          request.fetch(:theirs_source),
          request.fetch(:ours_source),
          dialect_for(request),
          backend: request[:backend]
        )
        emitted = verified_family_composite(candidate, request, decision)
        return emitted if emitted

        exact = render_exact_composite(request, decision)
        return exact if exact

        composite_failure(request, 'JSON family renderers did not reproduce the planned three-way value.')
      end

      def verified_family_composite(candidate, request, decision)
        return unless candidate[:ok]

        output = candidate.fetch(:output)
        verification = verify_rendered(output, decision.value, request)
        return unless verification[:semantic_match]

        rendered = render_plan(
          request,
          [
            Ast::Merge::SourceRender::SynthesizedFragment.new(
              content: output,
              reason: :family_emission,
              producer: provider_id
            )
          ]
        )
        {
          output: rendered.content,
          render_report: render_report(rendered, strategy: :family_composite),
          verification: verification
        }
      end

      def render_exact_composite(request, decision)
        replacements = exact_composite_replacements(request, decision)
        return unless replacements

        rendered = render_plan(request, replacement_fragments(request, replacements))
        verification = verify_rendered(rendered.content, decision.value, request)
        return unless verification[:semantic_match]

        {
          output: rendered.content,
          render_report: render_report(rendered, strategy: :exact_owner_composite),
          fallbacks: [
            {
              from: :family_composite,
              to: :exact_owner_composite,
              reason: :semantic_verification_failed
            }
          ],
          verification: verification
        }
      end

      def exact_composite_replacements(request, decision)
        locators = conflict_locators(request)
        changes = decision.changes.select do |change|
          change[:ours] == :unchanged && change[:theirs] != :unchanged
        end
        replacements = []
        until changes.empty?
          change = changes.shift
          ours_range = locators.fetch(:ours).pair_range(change.fetch(:path))
          return unless ours_range

          theirs_range = if change[:theirs] == :deleted
                           nil
                         else
                           locators.fetch(:theirs).pair_range(change.fetch(:path))
                         end
          return if change[:theirs] != :deleted && theirs_range.nil?

          replacements << { ours: ours_range, theirs: theirs_range }
        end
        return unless non_overlapping_ours_ranges?(replacements)

        replacements
      end

      def replacement_fragments(request, replacements)
        fragments = []
        cursor = 1
        replacements.sort_by { |item| item.fetch(:ours).start_line }.each do |item|
          ours_range = item.fetch(:ours)
          fragments << source_range_fragment(:ours, cursor, ours_range.start_line - 1) if cursor < ours_range.start_line
          theirs_range = item[:theirs]
          fragments << source_range_fragment(:theirs, theirs_range.start_line, theirs_range.end_line) if theirs_range
          cursor = ours_range.end_line + 1
        end
        final_line = request.fetch(:ours_source).lines.length
        fragments << source_range_fragment(:ours, cursor, final_line) if cursor <= final_line
        fragments
      end

      def render_conflict(request, decision)
        localized = localized_conflict_plan(request, decision)
        return localized if localized

        synthesized = synthesized_conflict_plan(request, decision)
        return synthesized if synthesized

        render_full_file_conflict(request, decision)
      end

      def localized_conflict_plan(request, decision)
        ranges = localized_conflict_ranges(request, decision)
        return if ranges.nil?

        rendered = render_plan(request, localized_conflict_fragments(request, decision, ranges))
        conflict_failure(request, decision, rendered, strategy: :owner_localized_conflict)
      end

      def localized_conflict_ranges(request, decision)
        locators = conflict_locators(request)
        ranges = decision.conflicts.map do |conflict|
          conflict_ranges(conflict, locators)
        end
        return if ranges.any?(&:nil?)
        return unless non_overlapping_ours_ranges?(ranges)

        ranges
      end

      def synthesized_conflict_plan(request, decision)
        candidate = Json::Merge.merge_json(
          request.fetch(:theirs_source),
          request.fetch(:ours_source),
          dialect_for(request),
          backend: request[:backend]
        )
        return unless candidate[:ok]
        return unless verify_rendered(candidate.fetch(:output), decision.value, request)[:semantic_match]

        ranges = synthesized_conflict_ranges(request, decision, candidate.fetch(:output))
        return unless ranges

        rendered = render_plan(
          request,
          synthesized_conflict_fragments(request, decision, candidate.fetch(:output), ranges)
        )
        conflict_failure(
          request,
          decision,
          rendered,
          strategy: :synthesized_owner_localized_conflict,
          fallbacks: [
            {
              from: :exact_owner_localization,
              to: :synthesized_conflict_context,
              reason: :missing_side_owner
            }
          ]
        )
      end

      def synthesized_conflict_ranges(request, decision, candidate)
        locators = conflict_locators(request)
        candidate_locator = SourceLocator.new(
          candidate,
          dialect: dialect_for(request),
          backend: request[:backend]
        )
        conflicts = decision.conflicts.dup
        ranges = []
        until conflicts.empty?
          conflict = conflicts.shift
          sides = conflict_source_ranges(conflict, locators)
          context = candidate_locator.pair_range(conflict.fetch(:path))
          return unless sides && context

          ranges << sides.merge(context: context)
        end
        return unless non_overlapping_ranges?(ranges.map { |item| item.fetch(:context) })

        ranges
      end

      def conflict_source_ranges(conflict, locators)
        ranges = {}
        roles = %i[base ours theirs]
        until roles.empty?
          role = roles.shift
          state = conflict.fetch(role)
          range = state.fetch(:present) ? locators.fetch(role).pair_range(conflict.fetch(:path)) : nil
          return if state.fetch(:present) && range.nil?

          ranges[role] = range
        end
        ranges
      end

      def synthesized_conflict_fragments(request, decision, candidate, ranges)
        fragments = []
        cursor = 1
        decision.conflicts
                .zip(ranges)
                .sort_by { |_conflict, item| item.fetch(:context).start_line }
                .each do |conflict, item|
                  context = item.fetch(:context)
                  append_synthesized_context(fragments, candidate, cursor, context.start_line - 1)
                  fragments << conflict_fragment(request, conflict, item)
                  cursor = context.end_line + 1
                end
        append_synthesized_context(fragments, candidate, cursor, candidate.lines.length)
        fragments
      end

      def append_synthesized_context(fragments, source, start_line, end_line)
        return if start_line > end_line

        content = source.lines.slice(start_line - 1, end_line - start_line + 1).join
        fragments << Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: content,
          reason: :conflict_context,
          producer: provider_id,
          metadata: { candidate_line_start: start_line }
        )
      end

      def conflict_locators(request)
        %i[base ours theirs].to_h do |role|
          [
            role,
            SourceLocator.new(
              request.fetch(:"#{role}_source"),
              dialect: dialect_for(request),
              backend: request[:backend]
            )
          ]
        end
      end

      def conflict_ranges(conflict, locators)
        ranges = {}
        roles = %i[base ours theirs]
        until roles.empty?
          role = roles.shift
          state = conflict.fetch(role)
          range = state.fetch(:present) ? locators.fetch(role).pair_range(conflict.fetch(:path)) : nil
          return if state.fetch(:present) && range.nil?

          ranges[role] = range
        end
        return if ranges[:ours].nil?

        ranges
      end

      def non_overlapping_ours_ranges?(ranges)
        non_overlapping_ranges?(ranges.map { |item| item.fetch(:ours) })
      end

      def non_overlapping_ranges?(ranges)
        ranges
          .sort_by(&:start_line)
          .each_cons(2)
          .none? { |left, right| left.end_line >= right.start_line }
      end

      def localized_conflict_fragments(request, decision, ranges)
        fragments = []
        cursor = 1
        decision.conflicts
                .zip(ranges)
                .sort_by { |_conflict, item| item.fetch(:ours).start_line }
                .each do |conflict, item|
                  ours_range = item.fetch(:ours)
                  if cursor < ours_range.start_line
                    fragments << source_range_fragment(:ours, cursor, ours_range.start_line - 1)
                  end
                  fragments << conflict_fragment(request, conflict, item)
                  cursor = ours_range.end_line + 1
                end
        final_line = request.fetch(:ours_source).lines.length
        fragments << source_range_fragment(:ours, cursor, final_line) if cursor <= final_line
        fragments
      end

      def conflict_fragment(request, conflict, ranges)
        Ast::Merge::SourceRender::ConflictFragment.new(
          conflict_id: conflict.fetch(:conflict_id),
          base: conflict_side_fragment(:base, ranges[:base]),
          ours: conflict_side_fragment(:ours, ranges[:ours]),
          theirs: conflict_side_fragment(:theirs, ranges[:theirs]),
          labels: request.fetch(:labels, {}),
          marker_size: request.fetch(:conflict_marker_size, 7),
          metadata: { path: conflict.fetch(:path), category: conflict.fetch(:category) }
        )
      end

      def conflict_side_fragment(role, range)
        range ? [source_range_fragment(role, range.start_line, range.end_line)] : []
      end

      def source_range_fragment(role, start_line, end_line)
        Ast::Merge::SourceRender::SourceFragment.new(
          revision: role,
          start_line: start_line,
          end_line: end_line,
          metadata: { source_role: role }
        )
      end

      def render_full_file_conflict(request, decision)
        rendered = render_plan(
          request,
          [
            Ast::Merge::SourceRender::ConflictFragment.new(
              conflict_id: decision.conflicts.first.fetch(:conflict_id),
              base: [source_fragment(:base, request.fetch(:base_source))],
              ours: [source_fragment(:ours, request.fetch(:ours_source))],
              theirs: [source_fragment(:theirs, request.fetch(:theirs_source))],
              labels: request.fetch(:labels, {}),
              marker_size: request.fetch(:conflict_marker_size, 7),
              metadata: { conflicts: decision.conflicts.map { |conflict| conflict[:conflict_id] } }
            )
          ]
        )
        conflict_failure(
          request,
          decision,
          rendered,
          strategy: :full_file_conflict,
          fallbacks: [
            {
              from: :owner_localization,
              to: :full_file_conflict,
              reason: :owner_not_whole_line_addressable
            }
          ]
        )
      end

      def conflict_failure(request, decision, rendered, strategy:, fallbacks: [])
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: "#{decision.conflicts.length} unresolved JSON merge conflict(s).",
          conflicts: decision.conflicts,
          fallbacks: fallbacks,
          conflicted_output: rendered.content,
          render_report: render_report(rendered, strategy: strategy)
        )
      end

      def render_plan(request, fragments)
        plan = Ast::Merge::SourceRender::Plan.new(
          sources: {
            base: request[:base_source].to_s,
            ours: request[:ours_source].to_s,
            theirs: request[:theirs_source].to_s
          },
          fragments: fragments,
          metadata: { provider_id: provider_id, dialect: dialect_for(request) }
        )
        Ast::Merge::SourceRender::Renderer.new.render(plan)
      end

      def source_fragment(role, source)
        line_count = source.lines.length
        raise Ast::Merge::SourceRender::InvalidPlanError, "#{role} source has no renderable lines" if line_count.zero?

        Ast::Merge::SourceRender::SourceFragment.new(
          revision: role,
          start_line: 1,
          end_line: line_count,
          metadata: { source_role: role }
        )
      end

      def verify_rendered(output, expected_value, request)
        actual = parse_output(output, request)
        {
          output_reparsed: true,
          semantic_match: actual == expected_value
        }
      rescue Json::Merge::ParseError
        {
          output_reparsed: false,
          semantic_match: false
        }
      end

      def parse_output(output, request)
        Json::Merge.json_value_for_source(
          output,
          dialect: dialect_for(request),
          backend: request[:backend]
        )
      end

      def result(
        operation, request, verification:, changes: [], conflicts: [], fallbacks: [], render_report: {}, **payload
      )
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: {
            provider: provider_metadata(request),
            profile: profile_metadata(request),
            changes: changes,
            conflicts: conflicts,
            fallbacks: fallbacks,
            render_report: render_report,
            verification: verification
          },
          **payload
        )
      end

      def failure(operation, request, category:, message:, conflicts: [], fallbacks: [], render_report: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: false,
          envelope: {
            provider: provider_metadata(request),
            profile: profile_metadata(request),
            diagnostics: [{ category: category, severity: :error, message: message, blocking: true }],
            conflicts: conflicts,
            fallbacks: fallbacks,
            render_report: render_report,
            verification: { base_participated: operation == :merge3 }
          },
          **payload
        )
      end

      def parse_failure(operation, role, parsed, request)
        diagnostic = parsed.fetch(:diagnostics).first || {}
        failure(
          operation,
          request,
          category: :parse_error,
          message: "#{role} parse error: #{diagnostic[:message]}",
          source_role: role
        )
      end

      def merge2_failure(merged, request)
        diagnostic = merged.fetch(:diagnostics).first || {}
        failure(
          :merge2,
          request,
          category: diagnostic[:category] || :merge_failed,
          message: diagnostic[:message] || 'JSON two-way merge failed.'
        )
      end

      def composite_failure(request, message)
        failure(:merge3, request, category: :render_failure, message: message)
      end

      def provider_failure?(value)
        value.is_a?(Hash) && value[:ok] == false
      end

      def render_report(rendered, strategy:)
        {
          strategy: strategy,
          line_records: rendered.line_records,
          synthesized_fragments: rendered.synthesized_fragments,
          conflicts: rendered.conflicts,
          verification_input: rendered.verification_input
        }
      end

      def provider_metadata(request)
        {
          provider_id: provider_id,
          family: family,
          dialect: dialect_for(request),
          backend: request[:backend],
          package: Json::Merge::PACKAGE_NAME,
          package_version: Json::Merge::Version::VERSION
        }.compact
      end

      def profile_metadata(request)
        { profile_id: request[:profile_id] || DEFAULT_PROFILE }
      end

      def dialect_for(request)
        (request[:dialect] || :json).to_sym
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
