# frozen_string_literal: true

require 'digest'

module Yaml
  # Parser-neutral YAML structural merge provider integration.
  module Merge
    # Conservative source-preserving provider for top-level YAML mappings.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity -- provider validation, planning, rendering, and verification form one safety boundary
    class SourcePreservingProvider
      DEFAULT_PROFILE = :source_preserving
      DIALECTS = %i[yaml].freeze

      Entry = Data.define(
        :key,
        :start_line,
        :end_line,
        :fragment,
        :semantic,
        :attributes,
        :role,
        :ownership_provable
      )
      Document = Data.define(
        :role,
        :source,
        :analysis,
        :entries,
        :by_key,
        :issues,
        :document_attributes
      )
      Decision = Data.define(:key, :base, :ours, :theirs, :selected_role, :classification, :conflict)

      def provider_id = self.class::PROVIDER_ID
      def family = 'yaml'
      def backend_reference = self.class::BACKEND
      def backend_id = backend_reference.id.to_sym
      def package_name = self.class::PACKAGE_NAME
      def package_version = self.class::PACKAGE_VERSION
      def role = self.class.const_defined?(:ROLE, false) ? self.class::ROLE : :backend

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: DIALECTS,
          backends: [backend_id],
          profiles: [DEFAULT_PROFILE],
          role: role,
          source_preservation: %i[
            exact_source
            mapping_entry_fragments
            comment_ownership
            line_provenance
            reparse
            semantic_verification
            ast_attribute_verification
          ]
        }.freeze
      end

      def analyze(request)
        document = analyze_role(:source, request.fetch(:source))
        return invalid_document_failure(:analyze, request, [document]) unless document.issues.empty?

        result(
          :analyze,
          request,
          analysis: analysis_payload(document),
          extensions: analysis_extensions(document),
          verification: { source_parsed: true, structurally_unambiguous: true }
        )
      end

      def diff2(request)
        before = analyze_role(:before, request.fetch(:before_source))
        after = analyze_role(:after, request.fetch(:after_source))
        unsafe = [before, after].reject { |document| document.issues.empty? }
        return invalid_document_failure(:diff2, request, unsafe) unless unsafe.empty?

        changes = mapping_changes(before, after)
        result(
          :diff2,
          request,
          diff: { before: analysis_payload(before), after: analysis_payload(after), changes: changes },
          changes: changes,
          verification: { before_parsed: true, after_parsed: true }
        )
      end

      def merge2(request)
        documents = {
          incoming: analyze_role(:incoming, request.fetch(:incoming_source)),
          current: analyze_role(:current, request.fetch(:current_source))
        }
        unsafe = documents.values.reject { |document| document.issues.empty? }
        return invalid_document_failure(:merge2, request, unsafe) unless unsafe.empty?

        additions = documents[:incoming].entries.reject { |entry| documents[:current].by_key.key?(entry.key) }
        render_documents = { ours: documents[:current], theirs: documents[:incoming] }
        fragments = [whole_source_fragment(:ours, documents[:current].source)]
        fragments.concat(additions.map { |entry| entry_fragment(:theirs, entry) })
        rendered = render_plan(request, separated_fragments(fragments, render_documents))
        expected = [
          *documents[:current].entries.map { |entry| selected_entry(entry, :current) },
          *additions.map { |entry| selected_entry(entry, :incoming) }
        ]
        verification = verify_composite(rendered.content, expected)
        return verification_failure(:merge2, request, rendered, [], verification) unless verification[:semantic_match]

        result(
          :merge2,
          request,
          output: rendered.content,
          changes: mapping_changes(documents[:current], analyze_role(:output, rendered.content)),
          render_report: render_report(rendered, :exact_mapping_entry_composite),
          verification: verification
        )
      end

      def merge3(request)
        documents = %i[base ours theirs].to_h do |role|
          [role, analyze_role(role, request.fetch(:"#{role}_source"))]
        end
        exact_role = exact_revision_role(documents)
        return render_exact(request, documents, exact_role) if exact_role

        unsafe = documents.values.reject { |document| document.issues.empty? }
        return structural_conflict(request, documents, unsafe) unless unsafe.empty?
        return unmanaged_conflict(request, documents) unless unmanaged_unchanged?(documents)

        decisions = three_way_decisions(documents)
        conflicts = decisions.select(&:conflict)
        return render_conflicts(request, documents, decisions, conflicts) unless conflicts.empty?

        render_composite(request, documents, decisions)
      end

      private

      def analyze_role(_role, _source)
        raise NotImplementedError, "#{self.class} must implement #analyze_role"
      end

      def invalid_document(role, source, category, message)
        Document.new(
          role: role,
          source: source,
          analysis: nil,
          entries: [].freeze,
          by_key: {}.freeze,
          issues: [issue(category, message)].freeze,
          document_attributes: {}
        )
      end

      def analysis_payload(document)
        {
          dialect: 'yaml',
          backend: backend_id.to_s,
          document_attributes: document.document_attributes,
          entries: document.entries.map do |entry|
            {
              key: entry.key,
              value: entry.semantic,
              attributes: entry.attributes,
              source_lines: [entry.start_line, entry.end_line]
            }
          end,
          structurally_unambiguous: document.issues.empty?
        }
      end

      def analysis_extensions(_document)
        []
      end

      def entry_state(entry)
        entry && [entry.semantic, entry.attributes, entry.fragment]
      end

      def exact_revision_role(documents)
        return :ours if documents[:ours].source == documents[:theirs].source
        return :ours if documents[:base].source == documents[:theirs].source

        :theirs if documents[:base].source == documents[:ours].source
      end

      def render_exact(request, documents, role)
        winner = documents.fetch(role)
        return structural_conflict(request, documents, [winner]) unless fatal_issues(winner).empty?

        rendered = render_plan(request, [whole_source_fragment(role, winner.source)])
        verification = verify_exact(rendered.content, winner, role)
        return verification_failure(:merge3, request, rendered, [], verification) unless verification[:semantic_match]

        result(
          :merge3,
          request,
          output: rendered.content,
          changes: mapping_changes(documents[:base], winner),
          diagnostics: diagnostics_for(*documents.values),
          render_report: render_report(rendered, :exact_revision),
          verification: verification.merge(base_participated: true)
        )
      end

      def verify_exact(output, expected, role)
        parsed = analyze_role(:output, output)
        {
          output_reparsed: true,
          byte_exact: output == expected.source,
          semantic_match: fatal_issues(parsed).empty? && document_signature(parsed) == document_signature(expected),
          ast_attributes_match: parsed.document_attributes == expected.document_attributes &&
            parsed.entries.map(&:attributes) == expected.entries.map(&:attributes),
          ordered_entries: ordered_semantics(parsed),
          source_role: role
        }
      end

      def mapping_changes(before, after)
        ordered_keys(before, after).filter_map do |key|
          left = before.by_key[key]
          right = after.by_key[key]
          next if entry_state(left) == entry_state(right)

          { path: "/#{key}", ours: :unchanged, theirs: change_kind(left, right) }.freeze
        end.freeze
      end

      def ordered_keys(*documents)
        documents.flat_map { |document| document.entries.map(&:key) }.uniq
      end

      def change_kind(before, after)
        return :added unless before
        return :deleted unless after

        :edited
      end

      def three_way_decisions(documents)
        ordered_keys(documents[:ours], documents[:theirs], documents[:base]).map do |key|
          base = documents[:base].by_key[key]
          ours = documents[:ours].by_key[key]
          theirs = documents[:theirs].by_key[key]
          selected_role =
            if entry_state(ours) == entry_state(theirs)
              :ours
            elsif entry_state(ours) == entry_state(base)
              :theirs
            elsif entry_state(theirs) == entry_state(base)
              :ours
            end
          classification = {
            path: "/#{key}",
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
        entry_state(base) == entry_state(side) ? :unchanged : change_kind(base, side)
      end

      def unmanaged_unchanged?(documents)
        anchor_keys = documents.values.map { |document| document.by_key.keys }.reduce(&:intersection)
        signatures = documents.transform_values { |document| unmanaged_signature(document, anchor_keys) }
        signatures[:base] == signatures[:ours] && signatures[:base] == signatures[:theirs]
      end

      def unmanaged_signature(document, anchor_keys)
        entries = document.entries.sort_by(&:start_line)
        signature = []
        cursor = 1
        entries.each do |entry|
          if cursor < entry.start_line
            signature << [:source, source_lines(document.source, cursor, entry.start_line - 1)]
          end
          signature << [:entry, entry.key] if anchor_keys.include?(entry.key)
          cursor = entry.end_line + 1
        end
        signature << [:source, source_lines(document.source, cursor, document.source.lines.length)]
        signature
      end

      def render_composite(request, documents, decisions)
        by_key = decisions.to_h { |decision| [decision.key, decision] }
        fragments = []
        selected = []
        cursor = 1
        documents[:ours].entries.sort_by(&:start_line).each do |ours_entry|
          fragments << range_fragment(:ours, cursor, ours_entry.start_line - 1) if cursor < ours_entry.start_line
          decision = by_key.fetch(ours_entry.key)
          selected_entry_value = decision.selected_role && decision.public_send(decision.selected_role)
          if selected_entry_value
            fragments << entry_fragment(decision.selected_role, selected_entry_value)
            selected << selected_entry(selected_entry_value, decision.selected_role)
          end
          cursor = ours_entry.end_line + 1
        end
        ours_line_count = documents[:ours].source.lines.length
        fragments << range_fragment(:ours, cursor, ours_line_count) if cursor <= ours_line_count
        decisions.each do |decision|
          next if decision.ours || decision.selected_role != :theirs || !decision.theirs

          fragments << entry_fragment(:theirs, decision.theirs)
          selected << selected_entry(decision.theirs, :theirs)
        end

        rendered = render_plan(request, separated_fragments(fragments.compact, documents))
        verification = verify_composite(rendered.content, selected)
        unless verification[:semantic_match]
          return verification_failure(:merge3, request, rendered, decisions, verification)
        end

        result(
          :merge3,
          request,
          output: rendered.content,
          changes: decisions.map(&:classification),
          render_report: render_report(rendered, :exact_mapping_entry_composite),
          verification: verification.merge(base_participated: true)
        )
      end

      def selected_entry(entry, role)
        {
          key: entry.key,
          semantic: entry.semantic,
          attributes: entry.attributes,
          source_role: role,
          source_lines: [entry.start_line, entry.end_line],
          fragment: entry.fragment
        }.freeze
      end

      def verify_composite(output, selected)
        parsed = analyze_role(:output, output)
        expected_semantics = selected.map { |entry| [entry[:key], entry[:semantic]] }
        expected_attributes = selected.map { |entry| [entry[:key], entry[:attributes]] }
        actual_semantics = parsed.entries.map { |entry| [entry.key, entry.semantic] }
        actual_attributes = parsed.entries.map { |entry| [entry.key, entry.attributes] }
        source_match = parsed.entries.zip(selected).all? do |actual, expected|
          actual.fragment == expected[:fragment] ||
            (!expected[:fragment].end_with?("\n") && actual.fragment == "#{expected[:fragment]}\n")
        end
        {
          output_reparsed: true,
          semantic_match: parsed.issues.empty? && actual_semantics == expected_semantics &&
            actual_attributes == expected_attributes && source_match,
          ast_attributes_match: actual_attributes == expected_attributes,
          source_match: source_match,
          ordered_entries: actual_semantics,
          entry_sources: selected.map { |entry| entry.slice(:key, :source_role, :source_lines) }
        }
      end

      def ordered_semantics(document)
        document.entries.map { |entry| [entry.key, entry.semantic] }
      end

      def document_signature(document)
        [ordered_semantics(document), document.entries.map(&:attributes)]
      end

      def fatal_issues(document)
        document.issues.select { |item| %i[parse_error structural_error].include?(item[:category]) }
      end

      def render_conflicts(request, documents, decisions, conflicts)
        unless conflicts.all? { |conflict| conflict.ours&.ownership_provable }
          return full_file_conflict(request, documents, decisions, conflicts, :ownership_unproven)
        end
        unless unmanaged_unchanged?(documents)
          return full_file_conflict(request, documents, decisions, conflicts, :unmanaged_source_change)
        end

        by_key = conflicts.to_h { |conflict| [conflict.key, conflict] }
        fragments = []
        cursor = 1
        documents[:ours].entries.sort_by(&:start_line).each do |entry|
          fragments << range_fragment(:ours, cursor, entry.start_line - 1) if cursor < entry.start_line
          conflict = by_key[entry.key]
          fragments << (conflict ? conflict_fragment(request, conflict) : entry_fragment(:ours, entry))
          cursor = entry.end_line + 1
        end
        ours_line_count = documents[:ours].source.lines.length
        fragments << range_fragment(:ours, cursor, ours_line_count) if cursor <= ours_line_count
        rendered = render_plan(request, fragments.compact)
        conflict_failure(request, decisions, conflicts, rendered, :mapping_entry_localized_conflict)
      end

      def conflict_fragment(request, decision)
        Ast::Merge::SourceRender::ConflictFragment.new(
          conflict_id: conflict_id(decision.key),
          base: conflict_side(:base, decision.base),
          ours: conflict_side(:ours, decision.ours),
          theirs: conflict_side(:theirs, decision.theirs),
          labels: request.fetch(:labels, {}),
          marker_size: request.fetch(:conflict_marker_size, 7),
          metadata: { path: decision.classification[:path], category: conflict_category(decision) }
        )
      end

      def conflict_side(role, entry)
        return [] unless entry

        [entry_fragment(role, entry, line_bounded: true)]
      end

      def conflict_category(decision)
        decision.ours.nil? || decision.theirs.nil? ? :delete_edit : :edit_edit
      end

      def conflict_id(key)
        "yaml-mapping-#{Digest::SHA256.hexdigest(key)[0, 16]}"
      end

      def conflict_failure(request, decisions, conflicts, rendered, strategy)
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: 'YAML mapping entries changed incompatibly.',
          changes: decisions.map(&:classification),
          conflicts: conflicts.map { |decision| conflict_payload(decision) },
          conflicted_output: rendered.content,
          conflicted_source: rendered.content,
          render_report: render_report(rendered, strategy),
          verification: { base_participated: true }
        )
      end

      def structural_conflict(request, documents, unsafe)
        source_role = unsafe.first.role
        full_file_conflict(
          request,
          documents,
          safe_decisions(documents),
          [],
          :structural_ambiguity,
          diagnostics: [
            {
              category: unsafe.first.issues.first[:category],
              severity: :error,
              message: "#{source_role} YAML input is unsafe for structural merge.",
              blocking: true,
              source_role: source_role
            },
            *diagnostics_for(*unsafe)
          ]
        )
      end

      def safe_decisions(documents)
        return [] unless documents.values.all? { |document| document.issues.empty? }

        three_way_decisions(documents)
      end

      def unmanaged_conflict(request, documents)
        full_file_conflict(
          request,
          documents,
          three_way_decisions(documents),
          [],
          :unmanaged_source_change,
          diagnostics: [{
            category: :unmanaged_source_change,
            severity: :error,
            message: 'Unmanaged YAML layout or comments changed independently.',
            blocking: true
          }]
        )
      end

      def full_file_conflict(request, documents, decisions, conflicts, reason, diagnostics: nil)
        conflict = { conflict_id: 'yaml-conflict-root', category: reason, path: '<document>' }.freeze
        rendered = render_plan(
          request,
          [
            Ast::Merge::SourceRender::ConflictFragment.new(
              conflict_id: conflict[:conflict_id],
              base: conflict_source(:base, documents[:base].source),
              ours: conflict_source(:ours, documents[:ours].source),
              theirs: conflict_source(:theirs, documents[:theirs].source),
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
          message: 'YAML source cannot be safely combined structurally.',
          diagnostics: diagnostics,
          changes: decisions.map(&:classification),
          conflicts: conflicts.empty? ? [conflict] : conflicts.map { |item| conflict_payload(item) },
          fallbacks: [{ from: :mapping_entry_composite, to: :full_file_conflict, reason: reason }],
          conflicted_output: rendered.content,
          conflicted_source: rendered.content,
          render_report: render_report(rendered, :full_file_conflict),
          verification: { base_participated: true },
          source_role: diagnostics&.first&.fetch(:source_role, nil)
        )
      end

      def conflict_payload(decision)
        {
          conflict_id: conflict_id(decision.key),
          category: conflict_category(decision),
          path: decision.classification[:path],
          change_classification: decision.classification
        }.freeze
      end

      def conflict_source(role, source)
        return [] if source.empty?

        [whole_source_fragment(role, source, line_bounded: true)]
      end

      def separated_fragments(fragments, documents)
        fragments.each_with_index.flat_map do |fragment, index|
          next [fragment] if index == fragments.length - 1
          next [fragment] if fragment.is_a?(Ast::Merge::SourceRender::ConflictFragment)

          content = fragment_content(fragment, documents)
          next [fragment] if content.empty? || content.end_with?("\n")

          [
            Ast::Merge::SourceRender::SynthesizedFragment.new(
              content: "#{content}\n",
              reason: :mapping_entry_separator,
              producer: provider_id,
              metadata: fragment.metadata.merge(copied_source: true)
            )
          ]
        end
      end

      def fragment_content(fragment, documents)
        return fragment.content if fragment.is_a?(Ast::Merge::SourceRender::SynthesizedFragment)

        document = documents.fetch(fragment.revision)
        source_lines(document.source, fragment.start_line, fragment.end_line)
      end

      def whole_source_fragment(role, source, line_bounded: false)
        if source.empty?
          return Ast::Merge::SourceRender::SynthesizedFragment.new(
            content: '',
            reason: :exact_empty_source,
            producer: provider_id,
            metadata: { source_role: role }
          )
        end
        fragment = range_fragment(role, 1, source.lines.length)
        return fragment unless line_bounded && !source.end_with?("\n")

        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "#{source}\n",
          reason: :conflict_line_boundary,
          producer: provider_id,
          metadata: { source_role: role, copied_source: true }
        )
      end

      def entry_fragment(role, entry, line_bounded: false)
        unless line_bounded && !entry.fragment.end_with?("\n")
          return range_fragment(role, entry.start_line, entry.end_line, yaml_key: entry.key)
        end

        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: "#{entry.fragment}\n",
          reason: :conflict_line_boundary,
          producer: provider_id,
          metadata: { source_role: role, yaml_key: entry.key, copied_source: true }
        )
      end

      def range_fragment(role, start_line, end_line, **metadata)
        return if end_line < start_line

        Ast::Merge::SourceRender::SourceFragment.new(
          revision: role,
          start_line: start_line,
          end_line: end_line,
          metadata: { source_role: role }.merge(metadata)
        )
      end

      def source_lines(source, start_line, end_line)
        return '' if end_line < start_line

        source.lines.slice(start_line - 1, end_line - start_line + 1).to_a.join
      end

      def render_plan(request, fragments)
        Ast::Merge::SourceRender::Renderer.new.render(
          Ast::Merge::SourceRender::Plan.new(
            sources: {
              base: request[:base_source].to_s,
              ours: request[:ours_source] || request[:current_source].to_s,
              theirs: request[:theirs_source] || request[:incoming_source].to_s
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

      def issue(category, message, **metadata)
        { category: category, message: message, **metadata }.freeze
      end

      def diagnostics_for(*documents)
        documents.flat_map do |document|
          document.issues.map do |item|
            item.merge(severity: :warning, blocking: false, source_role: document.role).freeze
          end
        end.freeze
      end

      def invalid_document_failure(operation, request, documents)
        first = documents.first
        failure(
          operation,
          request,
          category: first.issues.first[:category],
          message: "#{first.role} YAML input is unsafe",
          diagnostics: diagnostics_for(*documents).map { |diagnostic| diagnostic.merge(blocking: true) },
          source_role: first.role
        )
      end

      def verification_failure(operation, request, rendered, decisions, verification)
        failure(
          operation,
          request,
          category: :verification_failure,
          message: 'Rendered YAML did not preserve planned ordered semantics, AST attributes, and source fragments.',
          changes: decisions.map(&:classification),
          render_report: render_report(rendered, :exact_mapping_entry_composite),
          verification: operation == :merge3 ? verification.merge(base_participated: true) : verification
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
            dialect: request[:dialect] || :yaml,
            backend: request[:backend] || backend_id,
            package: package_name,
            package_version: package_version
          },
          profile: { profile_id: request[:profile_id] || DEFAULT_PROFILE }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/ParameterLists, Metrics/PerceivedComplexity
  end
end
