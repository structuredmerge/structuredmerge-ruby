# frozen_string_literal: true

module Json
  module Merge
    # Wrapper to represent comment-marked freeze blocks as first-class nodes in
    # JSON / JSONC files.
    class FreezeNode < Ast::Merge::FreezeNodeBase
      InvalidStructureError = Ast::Merge::FreezeNodeBase::InvalidStructureError
      Location = Ast::Merge::FreezeNodeBase::Location

      def initialize(start_line:, end_line:, lines:, start_marker: nil, end_marker: nil, pattern_type: :c_style_line)
        block_lines = (start_line..end_line).map { |ln| lines[ln - 1] }

        super(
          start_line: start_line,
          end_line: end_line,
          lines: block_lines,
          start_marker: start_marker,
          end_marker: end_marker,
          pattern_type: pattern_type,
        )

        validate_structure!
      end

      def signature
        normalized = @lines.map { |line| line&.strip }.compact.reject(&:empty?).join("\n")
        [:FreezeNode, normalized]
      end

      def object?
        false
      end

      def array?
        false
      end

      def pair?
        false
      end

      def inspect
        "#<#{self.class.name} lines=#{start_line}..#{end_line} content_length=#{slice&.length || 0}>"
      end

      private

      def validate_structure!
        validate_line_order!

        return unless @lines.empty? || @lines.all?(&:nil?)

        raise InvalidStructureError.new(
          'Freeze block is empty',
          start_line: @start_line,
          end_line: @end_line
        )
      end
    end
  end
end
