# frozen_string_literal: true

require 'digest'

module Dotenv
  module Merge
    # Source-preserving, base-aware provider for dotenv assignment documents.
    # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider planning, rendering, and reporting form one boundary
    class Provider
      DEFAULT_PROFILE = :source_preserving
      DIALECTS = %i[dotenv].freeze

      Analysis = Data.define(:role, :source, :file, :lines, :assignments, :by_key, :unowned, :issues)
      Decision = Data.define(:key, :base, :ours, :theirs, :selected_role, :classification, :conflict)

      def provider_id = 'ruby.dotenv'
      def family = 'dotenv'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: DIALECTS,
          backends: [Dotenv::Merge::BACKEND_REFERENCE.id.to_sym],
          profiles: [DEFAULT_PROFILE],
          role: :workflow,
          source_preservation: %i[exact_source assignment_fragments line_provenance reparse]
        }.freeze
      end

      def analyze(request)
        analysis = analyze_role(:source, request.fetch(:source))
        result(
          :analyze,
          request,
          analysis: analysis_payload(analysis),
          diagnostics: diagnostics_for(analysis),
          verification: { source_parsed: true, structurally_unambiguous: analysis.issues.empty? }
        )
      end

      def diff2(request)
        before = analyze_role(:before, request.fetch(:before_source))
        after = analyze_role(:after, request.fetch(:after_source))
        changes = assignment_changes(before, after)
        result(
          :diff2,
          request,
          diff: { before: analysis_payload(before), after: analysis_payload(after), changes: changes },
          changes: changes,
          diagnostics: diagnostics_for(before, after),
          verification: { before_parsed: true, after_parsed: true }
        )
      end

      def merge2(request)
        incoming = request.fetch(:incoming_source)
        current = request.fetch(:current_source)
        inputs = [
          analyze_role(:incoming, incoming),
          analyze_role(:current, current)
        ]
        unsafe = inputs.reject { |analysis| analysis.issues.empty? }
        unless unsafe.empty?
          return unsafe_failure(
            :merge2,
            request,
            unsafe,
            message: 'dotenv merge2 input is structurally ambiguous'
          )
        end

        merged = SmartMerger.new(incoming, current, add_template_only_nodes: true).merge.to_s
        output = analyze_role(:output, merged)
        unless output.issues.empty?
          return unsafe_failure(
            :merge2,
            request,
            [output],
            message: 'dotenv merge2 output is structurally ambiguous'
          )
        end

        result(
          :merge2,
          request,
          output: merged,
          render_report: { strategy: :dotenv_smart_merger, synthesis: :family_emission },
          verification: { output_reparsed: true, ordered_assignments: semantic_assignments(output) }
        )
      rescue Dotenv::Merge::ParseError => e
        failure(:merge2, request, category: :parse_error, message: e.message)
      end

      def merge3(request)
        analyses = %i[base ours theirs].to_h do |role|
          [role, analyze_role(role, request.fetch(:"#{role}_source"))]
        end
        exact_role = exact_revision_role(analyses)
        if exact_role
          winner = analyses.fetch(exact_role)
          return unsafe_conflict(request, analyses, [winner]) unless winner.issues.empty?

          return render_exact(request, analyses, exact_role)
        end

        unsafe = analyses.values.reject { |analysis| analysis.issues.empty? }
        return unsafe_conflict(request, analyses, unsafe) unless unsafe.empty?
        return unowned_conflict(request, analyses) unless unowned_unchanged?(analyses)

        decisions = three_way_decisions(analyses)
        conflicts = decisions.select(&:conflict)
        return render_conflicts(request, analyses, decisions, conflicts) unless conflicts.empty?

        render_composite(request, analyses, decisions)
      end

      private

      def analyze_role(role, source)
        file = FileAnalysis.new(source)
        lines = source.lines.each_index.map { |index| file.line_at(index + 1) }
        assignments = file.all_assignments
        grouped = assignments.group_by(&:key)
        issues = file.structural_diagnostics.dup
        grouped.each do |key, values|
          next if values.one?

          issues << { category: :duplicate_key, key: key, message: "Duplicate dotenv key #{key}" }.freeze
        end
        lines.select(&:invalid?).each do |line|
          issues << {
            category: :invalid_line,
            line: line.line_number,
            message: "Invalid dotenv line #{line.line_number}"
          }.freeze
        end
        if file.structural_owners.any? { |owner| owner.is_a?(FreezeNode) }
          issues << { category: :freeze_block, message: 'Freeze blocks require an exact one-sided merge' }.freeze
        end

        Analysis.new(
          role: role,
          source: source,
          file: file,
          lines: lines.freeze,
          assignments: assignments.freeze,
          by_key: grouped.transform_values(&:first).freeze,
          unowned: lines.reject(&:assignment?).map(&:raw).freeze,
          issues: issues.freeze
        )
      end

      def analysis_payload(analysis)
        {
          dialect: 'dotenv',
          backend: Dotenv::Merge::BACKEND_REFERENCE.id,
          assignments: semantic_assignments(analysis),
          comment_capability: analysis.file.comment_capability.to_h,
          comment_support_style: analysis.file.comment_support_style.to_h,
          structurally_unambiguous: analysis.issues.empty?
        }
      end

      def semantic_assignments(analysis)
        analysis.assignments.map do |line|
          { key: line.key, value: line.value, export: line.export? }.freeze
        end.freeze
      end

      def line_state(line)
        line && [line.key, line.value, line.export?, line.raw]
      end

      def exact_revision_role(analyses)
        return :ours if analyses[:ours].source == analyses[:theirs].source
        return :ours if analyses[:base].source == analyses[:theirs].source

        :theirs if analyses[:base].source == analyses[:ours].source
      end

      def render_exact(request, analyses, role)
        rendered = render_plan(request, [whole_source_fragment(role, analyses.fetch(role).source)])
        verification = verify_output(rendered.content, analyses.fetch(role).assignments, role)
        result(
          :merge3,
          request,
          output: rendered.content,
          changes: assignment_changes(analyses[:base], analyses.fetch(role)),
          diagnostics: diagnostics_for(*analyses.values),
          render_report: render_report(rendered, :exact_revision),
          verification: verification.merge(base_participated: true)
        )
      end

      def assignment_changes(before, after)
        ordered_keys(before, after).filter_map do |key|
          left = before.by_key[key]
          right = after.by_key[key]
          next if line_state(left) == line_state(right)

          {
            path: "/assignments/#{key}",
            ours: :unchanged,
            theirs: change_kind(left, right)
          }.freeze
        end.freeze
      end

      def ordered_keys(*analyses)
        analyses.flat_map { |analysis| analysis.assignments.map(&:key) }.uniq
      end

      def change_kind(before, after)
        return :added unless before
        return :deleted unless after

        :edited
      end

      def three_way_decisions(analyses)
        ordered_keys(analyses[:ours], analyses[:theirs], analyses[:base]).map do |key|
          base = analyses[:base].by_key[key]
          ours = analyses[:ours].by_key[key]
          theirs = analyses[:theirs].by_key[key]
          base_semantic = line_state(base)
          ours_semantic = line_state(ours)
          theirs_semantic = line_state(theirs)
          selected_role =
            if ours_semantic == theirs_semantic
              :ours
            elsif ours_semantic == base_semantic
              :theirs
            elsif theirs_semantic == base_semantic
              :ours
            end
          classification = {
            path: "/assignments/#{key}",
            ours: side_change(base, ours),
            theirs: side_change(base, theirs)
          }.freeze
          Decision.new(
            key: key,
            base: base,
            ours: ours,
            theirs: theirs,
            selected_role: selected_role,
            classification: classification,
            conflict: selected_role.nil?
          )
        end.freeze
      end

      def side_change(base, side)
        return :unchanged if line_state(base) == line_state(side)

        change_kind(base, side)
      end

      def unowned_unchanged?(analyses)
        anchor_keys = analyses.values.map { |analysis| analysis.by_key.keys }.reduce(&:intersection)
        signatures = analyses.transform_values { |analysis| unmanaged_signature(analysis, anchor_keys) }
        signatures[:base] == signatures[:ours] && signatures[:base] == signatures[:theirs]
      end

      def unmanaged_signature(analysis, anchor_keys)
        analysis.lines.filter_map do |line|
          if line.assignment?
            [:assignment, line.key] if anchor_keys.include?(line.key)
          else
            [:unmanaged, line.raw]
          end
        end
      end

      def render_composite(request, analyses, decisions)
        by_key = decisions.to_h { |decision| [decision.key, decision] }
        fragments = []
        selected = []
        analyses[:ours].lines.each do |line|
          if line.assignment?
            decision = by_key.fetch(line.key)
            next unless decision.selected_role

            selected_line = decision.public_send(decision.selected_role)
            next unless selected_line

            fragments << line_fragment(decision.selected_role, selected_line.line_number, decision.key)
            selected << selected_assignment(decision, selected_line)
          else
            fragments << line_fragment(:ours, line.line_number)
          end
        end
        decisions.each do |decision|
          next if decision.ours || decision.selected_role != :theirs || !decision.theirs

          fragments << line_fragment(:theirs, decision.theirs.line_number, decision.key)
          selected << selected_assignment(decision, decision.theirs)
        end

        rendered = render_plan(request, line_bounded_fragments(fragments, analyses))
        expected = selected.map { |item| item.fetch(:semantic) }
        verification = verify_composite(rendered.content, expected, selected)
        return verification_failure(request, rendered, decisions, verification) unless verification[:semantic_match]

        result(
          :merge3,
          request,
          output: rendered.content,
          changes: decisions.map(&:classification),
          render_report: render_report(rendered, :exact_assignment_composite),
          verification: verification.merge(base_participated: true)
        )
      end

      def selected_assignment(decision, line)
        {
          key: decision.key,
          source_role: decision.selected_role,
          source_line: line.line_number,
          source: line.raw,
          semantic: { key: line.key, value: line.value, export: line.export? }.freeze
        }.freeze
      end

      def fragment_content(fragment, analyses)
        return fragment.content if fragment.is_a?(Ast::Merge::SourceRender::SynthesizedFragment)

        analyses.fetch(fragment.revision).source.lines[fragment.start_line - 1].to_s
      end

      def line_bounded_fragments(fragments, analyses)
        fragments.each_with_index.flat_map do |fragment, index|
          next [fragment] if index == fragments.length - 1
          next [fragment] if fragment.is_a?(Ast::Merge::SourceRender::ConflictFragment)
          next [fragment] if fragment_content(fragment, analyses).end_with?("\n")

          content = fragment_content(fragment, analyses)
          [
            Ast::Merge::SourceRender::SynthesizedFragment.new(
              content: "#{content}\n",
              reason: :assignment_separator,
              producer: provider_id,
              metadata: fragment.metadata.merge(copied_source: true)
            )
          ]
        end
      end

      def verify_composite(output, expected, selected)
        parsed = analyze_role(:output, output)
        actual = semantic_assignments(parsed)
        source_match = parsed.assignments.map(&:raw) == selected.map { |item| item.fetch(:source) }
        {
          output_reparsed: true,
          semantic_match: parsed.issues.empty? && actual == expected && source_match,
          source_match: source_match,
          ordered_assignments: actual,
          assignment_sources: selected.map { |item| item.except(:semantic, :source) }
        }
      end

      def verify_output(output, expected_lines, role)
        parsed = analyze_role(:output, output)
        expected = expected_lines.map { |line| { key: line.key, value: line.value, export: line.export? }.freeze }
        {
          output_reparsed: true,
          semantic_match: semantic_assignments(parsed) == expected,
          structurally_unambiguous: parsed.issues.empty?,
          ordered_assignments: semantic_assignments(parsed),
          source_role: role
        }
      end

      def render_conflicts(request, analyses, decisions, conflicts)
        if conflicts.any? { |item| item.ours.nil? }
          return full_file_conflict(
            request,
            analyses,
            decisions,
            conflicts,
            :conflict_not_line_addressable
          )
        end

        by_key = conflicts.to_h { |conflict| [conflict.key, conflict] }
        fragments = analyses[:ours].lines.map do |line|
          conflict = line.assignment? && by_key[line.key]
          conflict ? conflict_fragment(request, conflict) : line_fragment(:ours, line.line_number)
        end
        rendered = render_plan(request, fragments)
        conflict_failure(request, decisions, conflicts, rendered, :assignment_localized_conflict)
      end

      def conflict_fragment(request, decision)
        Ast::Merge::SourceRender::ConflictFragment.new(
          conflict_id: conflict_id(decision.key),
          base: conflict_side(request, :base, decision.base),
          ours: conflict_side(request, :ours, decision.ours),
          theirs: conflict_side(request, :theirs, decision.theirs),
          labels: request.fetch(:labels, {}),
          marker_size: request.fetch(:conflict_marker_size, 7),
          metadata: { path: decision.classification.fetch(:path), category: conflict_category(decision) }
        )
      end

      def conflict_side(request, role, line)
        return [] unless line

        fragment = line_fragment(role, line.line_number, line.key)
        source_line = request.fetch(:"#{role}_source").lines[line.line_number - 1].to_s
        return [fragment] if source_line.end_with?("\n")

        [
          Ast::Merge::SourceRender::SynthesizedFragment.new(
            content: "#{source_line}\n",
            reason: :conflict_line_boundary,
            producer: provider_id,
            metadata: { source_role: role, assignment_key: line.key, copied_source: true }
          )
        ]
      end

      def conflict_category(decision)
        return :delete_edit if decision.ours.nil? || decision.theirs.nil?

        :edit_edit
      end

      def conflict_id(key)
        "dotenv-assignment-#{Digest::SHA256.hexdigest(key)[0, 16]}"
      end

      def conflict_failure(request, decisions, conflicts, rendered, strategy)
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: 'Dotenv assignments changed incompatibly.',
          changes: decisions.map(&:classification),
          conflicts: conflicts.map do |decision|
            {
              conflict_id: conflict_id(decision.key),
              category: conflict_category(decision),
              path: decision.classification.fetch(:path),
              change_classification: decision.classification
            }.freeze
          end,
          conflicted_output: rendered.content,
          conflicted_source: rendered.content,
          render_report: render_report(rendered, strategy),
          verification: { base_participated: true }
        )
      end

      def unsafe_conflict(request, analyses, unsafe)
        source_role = unsafe.first.role
        diagnostics = [{
          category: :parse_error,
          severity: :error,
          message: "#{source_role} structural parse is ambiguous.",
          blocking: true,
          source_role: source_role
        }.freeze, *diagnostics_for(*unsafe)]
        full_file_conflict(
          request,
          analyses,
          three_way_decisions(analyses),
          [],
          :structural_ambiguity,
          diagnostics: diagnostics
        )
      end

      def unowned_conflict(request, analyses)
        full_file_conflict(
          request,
          analyses,
          three_way_decisions(analyses),
          [],
          :unmanaged_source_change,
          diagnostics: [{
            category: :unmanaged_source_change,
            severity: :error,
            message: 'Non-assignment dotenv source changed independently.',
            blocking: true
          }]
        )
      end

      def full_file_conflict(request, analyses, decisions, conflicts, reason, diagnostics: nil)
        conflict = {
          conflict_id: 'dotenv-conflict-root',
          category: reason,
          path: '<unmanaged-source>'
        }.freeze
        rendered = render_plan(
          request,
          [
            Ast::Merge::SourceRender::ConflictFragment.new(
              conflict_id: conflict.fetch(:conflict_id),
              base: conflict_source(:base, analyses[:base].source),
              ours: conflict_source(:ours, analyses[:ours].source),
              theirs: conflict_source(:theirs, analyses[:theirs].source),
              labels: request.fetch(:labels, {}),
              marker_size: request.fetch(:conflict_marker_size, 7),
              metadata: { category: reason }
            )
          ]
        )
        failure(
          :merge3,
          request,
          category: reason,
          message: 'Dotenv source cannot be safely combined structurally.',
          diagnostics: diagnostics,
          changes: decisions.map(&:classification),
          conflicts: conflicts.empty? ? [conflict] : conflicts.map { |item| conflict_payload(item) },
          fallbacks: [{ from: :assignment_composite, to: :full_file_conflict, reason: reason }],
          conflicted_output: rendered.content,
          conflicted_source: rendered.content,
          render_report: render_report(rendered, :full_file_conflict),
          verification: { base_participated: true },
          source_role: diagnostics&.first&.fetch(:source_role, nil)
        )
      end

      def conflict_source(role, source)
        return [] if source.empty?
        return [whole_source_fragment(role, source)] if source.end_with?("\n")

        [
          Ast::Merge::SourceRender::SynthesizedFragment.new(
            content: "#{source}\n",
            reason: :conflict_line_boundary,
            producer: provider_id,
            metadata: { source_role: role, copied_source: true }
          )
        ]
      end

      def conflict_payload(decision)
        return decision if decision.is_a?(Hash)

        {
          conflict_id: conflict_id(decision.key),
          category: conflict_category(decision),
          path: decision.classification.fetch(:path),
          change_classification: decision.classification
        }.freeze
      end

      def whole_source_fragment(role, source)
        if source.empty?
          return Ast::Merge::SourceRender::SynthesizedFragment.new(
            content: '',
            reason: :exact_empty_source,
            producer: provider_id,
            metadata: { source_role: role }
          )
        end

        Ast::Merge::SourceRender::SourceFragment.new(
          revision: role,
          start_line: 1,
          end_line: source.lines.length,
          metadata: { source_role: role }
        )
      end

      def line_fragment(role, line_number, key = nil)
        Ast::Merge::SourceRender::SourceFragment.new(
          revision: role,
          start_line: line_number,
          end_line: line_number,
          metadata: { source_role: role, assignment_key: key }.compact
        )
      end

      def render_plan(request, fragments)
        Ast::Merge::SourceRender::Renderer.new.render(
          Ast::Merge::SourceRender::Plan.new(
            sources: {
              base: request[:base_source].to_s,
              ours: request[:ours_source].to_s,
              theirs: request[:theirs_source].to_s
            },
            fragments: fragments,
            metadata: { provider_id: provider_id }
          )
        )
      end

      def render_report(rendered, strategy)
        {
          strategy: strategy,
          line_records: rendered.line_records,
          synthesized_fragments: rendered.synthesized_fragments,
          conflicts: rendered.conflicts,
          verification_input: rendered.verification_input
        }
      end

      def diagnostics_for(*analyses)
        analyses.flat_map do |analysis|
          analysis.issues.map do |issue|
            issue.merge(
              severity: :warning,
              blocking: false,
              source_role: analysis.role
            ).freeze
          end
        end.freeze
      end

      def unsafe_failure(operation, request, analyses, message:)
        failure(
          operation,
          request,
          category: :structural_ambiguity,
          message: message,
          diagnostics: diagnostics_for(*analyses)
        )
      end

      def verification_failure(request, rendered, decisions, verification)
        failure(
          :merge3,
          request,
          category: :verification_failure,
          message: 'Rendered dotenv assignments did not match the planned ordered semantics.',
          changes: decisions.map(&:classification),
          render_report: render_report(rendered, :exact_assignment_composite),
          verification: verification.merge(base_participated: true)
        )
      end

      def result(operation, request, diagnostics: [], changes: [], conflicts: [], fallbacks: [],
                 render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: envelope(
            request,
            diagnostics: diagnostics,
            changes: changes,
            conflicts: conflicts,
            fallbacks: fallbacks,
            render_report: render_report,
            verification: verification
          ),
          **payload
        )
      end

      def failure(operation, request, category:, message:, diagnostics: nil, changes: [], conflicts: [],
                  fallbacks: [], render_report: {}, verification: {}, **payload)
        diagnostics ||= [{ category: category, severity: :error, message: message, blocking: true }]
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: false,
          envelope: envelope(
            request,
            diagnostics: diagnostics,
            changes: changes,
            conflicts: conflicts,
            fallbacks: fallbacks,
            render_report: render_report,
            verification: verification
          ),
          **payload
        )
      end

      def envelope(request, **fields)
        {
          provider: {
            provider_id: provider_id,
            family: family,
            dialect: request[:dialect] || :dotenv,
            backend: request[:backend] || Dotenv::Merge::BACKEND_REFERENCE.id,
            package: 'dotenv-merge',
            package_version: Dotenv::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
