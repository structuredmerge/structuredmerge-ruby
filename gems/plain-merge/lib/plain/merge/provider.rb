# frozen_string_literal: true

module Plain
  module Merge
    # Coarse whole-document provider for unstructured plain text.
    # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists -- provider operations and envelopes form one cohesive boundary
    class Provider
      def provider_id = 'ruby.text'
      def family = 'text'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[text],
          backends: [Plain::Merge::BACKEND_REFERENCE.id.to_sym],
          profiles: %i[coarse_document],
          role: :workflow,
          source_preservation: %i[exact_source whole_document_conflict]
        }.freeze
      end

      def analyze(request)
        result(:analyze, request, analysis: Plain::Merge.analyze_text(request.fetch(:source)))
      end

      def diff2(request)
        before = request.fetch(:before_source)
        after = request.fetch(:after_source)
        changes = before == after ? [] : [classification(before, before, after)]
        result(:diff2, request, changes: changes, diff: { before: before, after: after, changes: changes })
      end

      def merge2(request)
        merged = Plain::Merge.merge_text(request.fetch(:incoming_source), request.fetch(:current_source))
        result(
          :merge2,
          request,
          output: merged.fetch(:output),
          render_report: { strategy: :normalized_block_merge },
          verification: { output_rendered: true }
        )
      end

      def merge3(request)
        base = request.fetch(:base_source)
        ours = request.fetch(:ours_source)
        theirs = request.fetch(:theirs_source)
        return exact_merge3(request, :ours, ours, base, ours, theirs) if ours == theirs || base == theirs
        return exact_merge3(request, :theirs, theirs, base, ours, theirs) if base == ours

        conflicted_merge3(request, base, ours, theirs)
      end

      private

      def exact_merge3(request, role, output, base, ours, theirs)
        rendered = render(request, [source_fragment(role, output)])
        result(
          :merge3,
          request,
          output: rendered.content,
          changes: [classification(base, ours, theirs)],
          render_report: render_report(rendered, :exact_revision),
          verification: { base_participated: true, output_reparsed: true, semantic_match: rendered.content == output }
        )
      end

      def conflicted_merge3(request, base, ours, theirs)
        conflict = {
          conflict_id: 'text-conflict-root',
          category: :edit_edit,
          path: '',
          change_classification: classification(base, ours, theirs)
        }
        rendered = render(
          request,
          [
            Ast::Merge::SourceRender::ConflictFragment.new(
              conflict_id: conflict.fetch(:conflict_id),
              base: [conflict_side(:base, base)],
              ours: [conflict_side(:ours, ours)],
              theirs: [conflict_side(:theirs, theirs)],
              labels: request.fetch(:labels, {}),
              marker_size: request.fetch(:conflict_marker_size, 7),
              metadata: { path: '', category: :edit_edit }
            )
          ]
        )
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: 'Plain text changed independently on both sides.',
          changes: [conflict.fetch(:change_classification)],
          conflicts: [conflict],
          conflicted_output: rendered.content,
          render_report: render_report(rendered, :whole_document_conflict),
          verification: { base_participated: true }
        )
      end

      def classification(base, ours, theirs)
        {
          path: '',
          ours: base == ours ? :unchanged : :edited,
          theirs: base == theirs ? :unchanged : :edited
        }.freeze
      end

      def render(request, fragments)
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

      def source_fragment(role, source)
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
          end_line: [source.lines.length, 1].max,
          metadata: { source_role: role }
        )
      end

      def conflict_side(role, source)
        return source_fragment(role, source) if !source.empty? && source.end_with?("\n")

        Ast::Merge::SourceRender::SynthesizedFragment.new(
          content: source.empty? ? '' : "#{source}\n",
          reason: :conflict_line_boundary,
          producer: provider_id,
          metadata: { source_role: role, copied_source: true }
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

      def result(operation, request, changes: [], render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: envelope(request, changes: changes, render_report: render_report, verification: verification),
          **payload
        )
      end

      def failure(operation, request, category:, message:, changes: [], conflicts: [], render_report: {},
                  verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: false,
          envelope: envelope(
            request,
            changes: changes,
            conflicts: conflicts,
            diagnostics: [{ category: category, severity: :error, message: message, blocking: true }],
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
            dialect: request[:dialect] || :text,
            backend: request[:backend],
            package: Plain::Merge::PACKAGE_NAME,
            package_version: Plain::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || :coarse_document }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists
  end
end
