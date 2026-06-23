# frozen_string_literal: true

module Markdown
  module Merge
    module Cleanse
      # Repairs templating corruption where an ordered-list marker was prefixed
      # onto an existing unordered-list marker, producing lines like:
      #
      #   1. - item
      #   2. * item
      #
      # The repair keeps the original inner bullet marker and removes the
      # synthetic ordered marker.
      class ListMarkerDuplication
        DUPLICATED_MARKER = /\A(?<indent>\s*)(?<number>\d+)\.\s+(?<bullet>[-*+])(?<tail>(?:\s+.*)?\s*)\z/

        attr_reader :source, :issues

        def initialize(source)
          @source = source.to_s
          @issues = []
          analyze
        end

        def malformed?
          issues.any?
        end

        def issue_count
          issues.length
        end

        def fix
          return source unless malformed?

          source.each_line.with_index(1).map do |line, line_number|
            duplicated_marker_line?(line) ? repaired_line(line, line_number) : line
          end.join
        end

        private

        def analyze
          source.each_line.with_index(1) do |line, line_number|
            next unless duplicated_marker_line?(line)

            issues << {
              type: :duplicated_list_marker,
              line: line_number,
              description: 'Ordered-list marker duplicated an existing unordered-list marker'
            }
          end
        end

        def duplicated_marker_line?(line)
          line.match?(DUPLICATED_MARKER)
        end

        def repaired_line(line, _line_number)
          match = line.match(DUPLICATED_MARKER)
          "#{match[:indent]}#{match[:bullet]}#{match[:tail]}"
        end
      end
    end
  end
end
