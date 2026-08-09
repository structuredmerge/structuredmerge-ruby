# frozen_string_literal: true

module Binary
  module Merge
    # Safety-first provider for opaque binary documents.
    # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists -- provider operations and envelopes form one cohesive boundary
    class Provider
      def provider_id = 'ruby.binary'
      def family = 'binary'

      def capabilities
        {
          operations: Ast::Merge::ProviderContract::OPERATIONS,
          dialects: %i[binary],
          backends: %i[raw_bytes],
          profiles: %i[opaque_document],
          role: :workflow,
          source_preservation: %i[exact_source opaque_conflict_retains_ours]
        }.freeze
      end

      def analyze(request)
        source = request.fetch(:source)
        result(:analyze, request, analysis: { bytesize: source.bytesize, binary: true })
      end

      def diff2(request)
        before = request.fetch(:before_source)
        after = request.fetch(:after_source)
        changes = before == after ? [] : [classification(before, before, after)]
        result(:diff2, request, changes: changes, diff: { changed: before != after })
      end

      def merge2(request)
        current = request.fetch(:current_source)
        incoming = request.fetch(:incoming_source)
        rendered = render(request, :ours, current)
        fallback = if current == incoming
                     []
                   else
                     [{
                       category: :opaque_binary_preserve_current,
                       reason: 'Opaque binary documents cannot be combined safely without a format-specific provider.'
                     }]
                   end
        result(
          :merge2,
          request,
          output: rendered.content,
          changes: current == incoming ? [] : [classification(current, current, incoming)],
          fallbacks: fallback,
          render_report: render_report(rendered, current == incoming ? :exact_revision : :preserve_current),
          verification: exact_verification(rendered, current)
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
        rendered = render(request, role, output)
        result(
          :merge3,
          request,
          output: rendered.content,
          changes: [classification(base, ours, theirs)],
          render_report: render_report(rendered, :exact_revision),
          verification: exact_verification(rendered, output).merge(base_participated: true)
        )
      end

      def conflicted_merge3(request, base, ours, theirs)
        rendered = render(request, :ours, ours)
        conflict = {
          conflict_id: 'binary-conflict-root',
          category: :opaque_edit_edit,
          path: '',
          change_classification: classification(base, ours, theirs)
        }
        failure(
          :merge3,
          request,
          category: :merge_conflict,
          message: 'Opaque binary content changed independently on both sides; retaining ours without markers.',
          changes: [conflict.fetch(:change_classification)],
          conflicts: [conflict],
          conflicted_output: rendered.content,
          render_report: render_report(rendered, :opaque_conflict_retains_ours),
          verification: { base_participated: true, ours_preserved_exactly: rendered.content == ours }
        )
      end

      def classification(base, ours, theirs)
        {
          path: '',
          ours: base == ours ? :unchanged : :edited,
          theirs: base == theirs ? :unchanged : :edited
        }.freeze
      end

      def render(request, role, source)
        Ast::Merge::SourceRender::Renderer.new.render(
          Ast::Merge::SourceRender::Plan.new(
            sources: {
              base: request[:base_source].to_s,
              ours: (request[:ours_source] || request[:current_source]).to_s,
              theirs: request[:theirs_source].to_s
            },
            fragments: [source_fragment(role, source)],
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

      def render_report(rendered, strategy)
        {
          strategy: strategy,
          line_records: rendered.line_records,
          synthesized_fragments: rendered.synthesized_fragments,
          conflicts: rendered.conflicts,
          verification_input: rendered.verification_input
        }
      end

      def exact_verification(rendered, source)
        {
          output_reparsed: true,
          semantic_match: rendered.content == source,
          bytes_preserved: rendered.content.b == source.b
        }
      end

      def result(operation, request, changes: [], fallbacks: [], render_report: {}, verification: {}, **payload)
        Ast::Merge::ProviderResult.build(
          operation: operation,
          success: true,
          envelope: envelope(
            request,
            changes: changes,
            fallbacks: fallbacks,
            render_report: render_report,
            verification: verification
          ),
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
            dialect: request[:dialect] || :binary,
            backend: request[:backend],
            package: Binary::Merge::PACKAGE_NAME,
            package_version: Binary::Merge::Version::VERSION
          },
          profile: { profile_id: request[:profile_id] || :opaque_document }
        }.merge(fields)
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/ParameterLists
  end
end
