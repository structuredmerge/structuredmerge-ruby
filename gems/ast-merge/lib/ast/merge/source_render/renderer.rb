# frozen_string_literal: true

require 'digest'

module Ast
  module Merge
    module SourceRender
      # Deterministically assembles a passive render plan without parsing source.
      # rubocop:disable Metrics/ClassLength -- rendering and provenance share one stateful traversal
      class Renderer
        def render(plan)
          reset_state(plan)
          plan.fragments.each { |fragment| render_fragment(fragment) }
          Result.new(
            content: @content,
            line_records: @line_records,
            synthesized_fragments: @synthesized_fragments,
            conflicts: @conflicts,
            verification_input: verification_input
          )
        end

        private

        def reset_state(plan)
          @plan = plan
          @content = +''
          @line_records = []
          @synthesized_fragments = []
          @conflicts = []
          @source_fragment_digests = []
        end

        def render_fragment(fragment, conflict: nil, side: nil)
          case fragment
          when SourceFragment
            render_source_fragment(fragment, conflict: conflict, side: side)
          when SynthesizedFragment
            render_synthesized_fragment(fragment, conflict: conflict, side: side)
          when ConflictFragment
            render_conflict_fragment(fragment)
          else
            raise InvalidPlanError, "Unsupported fragment: #{fragment.class}"
          end
        end

        # rubocop:disable Metrics/MethodLength -- provenance is recorded beside exact source emission
        def render_source_fragment(fragment, conflict:, side:)
          content = @plan.source_content(fragment)
          append_content(
            content,
            fragment.metadata.merge(
              fragment_kind: :source,
              revision: fragment.revision,
              original_line_start: fragment.start_line,
              conflict_id: conflict&.conflict_id,
              conflict_side: side
            )
          )
          @source_fragment_digests << {
            revision: fragment.revision,
            start_line: fragment.start_line,
            end_line: fragment.end_line,
            sha256: digest(content)
          }
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength -- synthesis reporting is coupled to emitted content
        def render_synthesized_fragment(fragment, conflict:, side:)
          append_content(
            fragment.content,
            fragment.metadata.merge(
              fragment_kind: :synthesized,
              synthesized_reason: fragment.reason,
              producer: fragment.producer,
              conflict_id: conflict&.conflict_id,
              conflict_side: side
            )
          )
          record_synthesis(
            content: fragment.content,
            reason: fragment.reason,
            producer: fragment.producer,
            context: {
              conflict_id: conflict&.conflict_id,
              conflict_side: side,
              metadata: fragment.metadata
            }
          )
        end
        # rubocop:enable Metrics/MethodLength

        def render_conflict_fragment(fragment)
          conflict_start_line = next_output_line
          append_marker('<', fragment.labels.fetch(:ours), fragment, :ours)
          render_conflict_side(fragment, :ours)
          append_marker('|', fragment.labels.fetch(:base), fragment, :base)
          render_conflict_side(fragment, :base)
          append_marker('=', nil, fragment, nil)
          render_conflict_side(fragment, :theirs)
          append_marker('>', fragment.labels.fetch(:theirs), fragment, :theirs)
          record_conflict(fragment, conflict_start_line)
        end

        def render_conflict_side(fragment, side)
          fragment.children_for(side).each do |child|
            render_fragment(child, conflict: fragment, side: side)
          end
        end

        def append_marker(character, label, fragment, side)
          content = marker_content(character, label, fragment.marker_size)
          metadata = marker_metadata(fragment, side)
          append_content(content, metadata)
          record_synthesis(
            content: content,
            reason: :conflict_marker,
            producer: :'ast-merge',
            context: metadata.slice(:conflict_id, :conflict_side).merge(metadata: {})
          )
        end

        def marker_content(character, label, marker_size)
          marker = character * marker_size
          marker = "#{marker} #{label}" if label
          "#{marker}\n"
        end

        def marker_metadata(fragment, side)
          {
            fragment_kind: :synthesized,
            synthesized_reason: :conflict_marker,
            producer: :'ast-merge',
            conflict_id: fragment.conflict_id,
            conflict_side: side
          }
        end

        def append_content(content, metadata)
          @content << content
          content.lines.each_with_index do |_line, index|
            @line_records << metadata.merge(
              output_line: next_output_line,
              original_line: original_line(metadata, index)
            ).compact.freeze
          end
        end

        def original_line(metadata, index)
          return unless metadata[:original_line_start]

          metadata[:original_line_start] + index
        end

        def next_output_line
          @line_records.length + 1
        end

        def verification_input
          {
            content_sha256: digest(@content),
            source_fragments: @source_fragment_digests.freeze,
            synthesized_fragment_count: @synthesized_fragments.length,
            conflict_count: @conflicts.length
          }
        end

        def digest(content)
          Digest::SHA256.hexdigest(content)
        end

        def record_synthesis(content:, reason:, producer:, context:)
          @synthesized_fragments << {
            reason: reason,
            producer: producer,
            sha256: digest(content),
            conflict_id: context[:conflict_id],
            conflict_side: context[:conflict_side],
            metadata: context[:metadata]
          }.compact
        end

        def record_conflict(fragment, start_line)
          @conflicts << {
            conflict_id: fragment.conflict_id,
            output_start_line: start_line,
            output_end_line: @line_records.length,
            metadata: fragment.metadata
          }
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
