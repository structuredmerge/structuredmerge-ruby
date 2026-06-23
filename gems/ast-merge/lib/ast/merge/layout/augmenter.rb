# frozen_string_literal: true

module Ast
  module Merge
    module Layout
      # Builds shared blank-line gap objects and per-owner attachments from source
      # lines plus structural owner ranges.
      class Augmenter
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
                       **options)
          @lines = normalize_lines(lines, source)
          @start_line_for = start_line_for
          @end_line_for = end_line_for
          @owners = normalize_owners(owners)
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
            before_owner = owners.reverse_each.find { |owner| owner_end_line(owner) == run[:start_line] - 1 }
            after_owner = owners.find { |owner| owner_start_line(owner) == run[:end_line] + 1 }
            next unless before_owner || after_owner

            kind = if before_owner && after_owner
                     :interstitial
                   elsif before_owner
                     :postlude
                   else
                     :preamble
                   end

            gap = Gap.new(
              kind: kind,
              start_line: run[:start_line],
              end_line: run[:end_line],
              lines: run[:lines],
              before_owner: before_owner,
              after_owner: after_owner,
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
          return owner.start_line if owner.respond_to?(:start_line)

          nil
        end

        def owner_end_line(owner)
          return @end_line_for.call(owner) if @end_line_for
          return owner.end_line if owner.respond_to?(:end_line)

          nil
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
