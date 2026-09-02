# frozen_string_literal: true

module Ast
  module Merge
    # Shared line-range helpers for parser-neutral merge code.
    #
    # This module intentionally stays small: it normalizes common owner location
    # shapes and source line access so higher-level comment, layout, and
    # structural-edit helpers do not each grow their own variant.
    module LineRangeSupport
      private

      def object_start_line(object)
        if object.respond_to?(:start_line)
          object.start_line
        elsif object.respond_to?(:location) && object.location
          object.location.start_line
        elsif object.respond_to?(:source_position)
          object.source_position&.dig(:start_line)
        elsif object.respond_to?(:start_point) && object.start_point
          row = line_point_row(object.start_point)
          row + 1 if row
        end
      end

      def object_end_line(object)
        if object.respond_to?(:end_line)
          object.end_line
        elsif object.respond_to?(:location) && object.location
          object.location.end_line
        elsif object.respond_to?(:source_position)
          object.source_position&.dig(:end_line)
        elsif object.respond_to?(:end_point) && object.end_point
          row = line_point_row(object.end_point)
          row + 1 if row
        end
      end

      def line_point_row(point)
        return point.row if point.respond_to?(:row)
        return point[:row] if point.respond_to?(:[])

        nil
      end

      def source_line_at(analysis, line_number)
        line = analysis.line_at(line_number)
        line.respond_to?(:raw) ? line.raw : line
      end
    end
  end
end
