# frozen_string_literal: true

module Ast
  module Merge
    module Layout
      # Builds shared blank-line gap objects and per-owner attachments from source
      # lines plus structural owner ranges.
      class Augmenter
        include LineRangeSupport

        attr_reader :lines, :owners, :attachments_by_owner, :preamble_gap, :postlude_gap, :interstitial_gaps, :metadata

        class << self
          # Build an augmenter and run gap inference immediately.
          #
          # @param options [Hash] arguments forwarded to {.new}
          # @return [Augmenter]
          def call(**options)
            new(**options)
          end
        end

        def initialize(lines: nil, source: nil, owners: [], start_line_for: nil, end_line_for: nil, metadata: {},
                       comment_boundaries: [], **options)
          @lines = normalize_lines(lines, source)
          @start_line_for = start_line_for
          @end_line_for = end_line_for
          @owners = normalize_owners(owners)
          @comment_boundaries = normalize_comment_boundaries(comment_boundaries)
          @metadata = metadata.merge(options).freeze
          @attachments_by_owner = {}
          @preamble_gap = nil
          @postlude_gap = nil
          @interstitial_gaps = []

          build!
        end

        # Return the inferred attachment for a specific owner.
        #
        # @param owner [Object] structural owner
        # @return [Attachment, nil]
        def attachment_for(owner)
          attachments_by_owner[owner]
        end

        # Return all inferred gaps in source order.
        #
        # @return [Array<Gap>]
        def gaps
          [preamble_gap, *interstitial_gaps, postlude_gap].compact
        end

        private

        def build!
          attachment_state = owners.each_with_object({}) do |owner, hash|
            hash[owner] = { leading_gap: nil, trailing_gap: nil }
          end

          blank_runs.each do |run|
            structural_before = owners.reverse_each.find { |owner| owner_end_line(owner) == run[:start_line] - 1 }
            structural_after = owners.find { |owner| owner_start_line(owner) == run[:end_line] + 1 }
            comment_before = comment_boundary_owner(:trailing, run[:start_line], :end_line)
            comment_after = comment_boundary_owner(:leading, run[:end_line] + 1, :start_line)
            before_owner = structural_before || comment_before
            after_owner = structural_after || comment_after
            next unless before_owner || after_owner

            kind = if before_owner && after_owner
                     :interstitial
                   elsif before_owner
                     :postlude
                   else
                     :preamble
                   end

            controller_side = if structural_before && !structural_after && comment_after
                                :before
                              elsif structural_after || after_owner
                                :after
                              else
                                :before
                              end

            gap = Gap.new(
              kind: kind,
              start_line: run[:start_line],
              end_line: run[:end_line],
              lines: run[:lines],
              before_owner: before_owner,
              after_owner: after_owner,
              controller_side: controller_side,
              metadata: { source: :layout_augmenter }
            )

            attachment_state[before_owner][:trailing_gap] = gap if before_owner
            attachment_state[after_owner][:leading_gap] = gap if after_owner

            case kind
            when :preamble
              @preamble_gap = gap
            when :postlude
              @postlude_gap = gap
            else
              @interstitial_gaps << gap
            end
          end

          @attachments_by_owner = owners.each_with_object({}) do |owner, hash|
            state = attachment_state.fetch(owner)
            hash[owner] = Attachment.new(
              owner: owner,
              leading_gap: state[:leading_gap],
              trailing_gap: state[:trailing_gap],
              metadata: { source: :layout_augmenter }
            )
          end
        end

        def normalize_comment_boundaries(boundaries)
          Array(boundaries).map do |boundary|
            owner = boundary.fetch(:owner)
            kind = boundary.fetch(:kind).to_sym
            start_line = Integer(boundary.fetch(:start_line))
            end_line = Integer(boundary.fetch(:end_line))
            unless owners.include?(owner) && %i[leading trailing].include?(kind) &&
                   start_line.positive? && end_line >= start_line && end_line <= lines.length
              raise ArgumentError, 'comment boundary has an invalid owner, kind, or line range'
            end

            outside_owner = if kind == :leading
                              end_line < owner_start_line(owner)
                            else
                              start_line > owner_end_line(owner)
                            end
            raise ArgumentError, 'comment boundary overlaps its structural owner' unless outside_owner

            { owner: owner, kind: kind, start_line: start_line, end_line: end_line }.freeze
          end.freeze
        end

        def comment_boundary_owner(kind, line, edge)
          boundary = @comment_boundaries.find do |candidate|
            candidate.fetch(:kind) == kind && candidate.fetch(edge) == line
          end
          boundary&.fetch(:owner)
        end

        def blank_runs
          runs = []
          index = 0

          while index < lines.length
            unless blank_line?(index + 1)
              index += 1
              next
            end

            start_index = index
            index += 1 while index < lines.length && blank_line?(index + 1)

            runs << {
              start_line: start_index + 1,
              end_line: index,
              lines: lines[start_index...index]
            }
          end

          runs
        end

        def normalize_lines(lines, source)
          return Array(lines) if lines
          return [] unless source

          values = source.split("\n", -1)
          values.pop if values.last&.empty? && source.end_with?("\n")
          values
        end

        def normalize_owners(owners)
          Array(owners)
            .tap { |values| values.each { |owner| validate_owner!(owner) } }
            .sort_by { |owner| [owner_start_line(owner) || Float::INFINITY, owner_end_line(owner) || Float::INFINITY] }
        end

        def validate_owner!(owner)
          unless owner_line_reader_available?(owner, :start_line,
                                              @start_line_for) && owner_line_reader_available?(owner, :end_line,
                                                                                               @end_line_for)
            raise ArgumentError,
                  'owner must respond to #start_line and #end_line or be supported by configured line extractors'
          end
        end

        def owner_start_line(owner)
          return @start_line_for.call(owner) if @start_line_for

          object_start_line(owner)
        end

        def owner_end_line(owner)
          return @end_line_for.call(owner) if @end_line_for

          object_end_line(owner)
        end

        def owner_line_reader_available?(owner, method_name, extractor)
          extractor || owner.respond_to?(method_name)
        end

        def blank_line?(line_number)
          line_at(line_number).to_s.strip.empty?
        end

        def line_at(line_number)
          return if line_number < 1

          lines[line_number - 1]
        end
      end
    end
  end
end
