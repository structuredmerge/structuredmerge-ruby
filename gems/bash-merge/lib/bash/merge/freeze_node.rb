# frozen_string_literal: true

module Bash
  module Merge
    # Wrapper to represent freeze blocks as first-class nodes in Bash scripts.
    # A freeze block is a section marked with freeze/unfreeze comment markers that
    # should be preserved from the destination during merges.
    #
    # Inherits from Ast::Merge::FreezeNodeBase for shared functionality including
    # the Location struct, InvalidStructureError, and configurable marker patterns.
    #
    # Uses the `:hash_comment` pattern type by default for Bash files (# comments).
    #
    # @example Freeze block in Bash
    #   # bash-merge:freeze
    #   SECRET_KEY="my-secret-value"
    #   API_ENDPOINT="https://custom.example.com"
    #   # bash-merge:unfreeze
    class FreezeNode < Ast::Merge::FreezeNodeBase
      # Inherit InvalidStructureError from base class
      InvalidStructureError = Ast::Merge::FreezeNodeBase::InvalidStructureError

      # Inherit Location from base class
      Location = Ast::Merge::FreezeNodeBase::Location

      # @param start_line [Integer] Line number of freeze marker
      # @param end_line [Integer] Line number of unfreeze marker
      # @param lines [Array<String>] All source lines
      # @param start_marker [String, nil] The freeze start marker text
      # @param end_marker [String, nil] The freeze end marker text
      # @param pattern_type [Symbol] Pattern type for marker matching (defaults to :hash_comment)
      def initialize(start_line:, end_line:, lines:, start_marker: nil, end_marker: nil, pattern_type: Ast::Merge::FreezeNodeBase::DEFAULT_PATTERN)
        # Extract lines for the entire block (lines param is all source lines)
        block_lines = (start_line..end_line).map { |ln| lines[ln - 1] }

        super(
          start_line: start_line,
          end_line: end_line,
          lines: block_lines,
          start_marker: start_marker,
          end_marker: end_marker,
          pattern_type: pattern_type
        )

        validate_structure!
      end

      # Returns a stable signature for this freeze block.
      # Signature includes the normalized content to detect changes.
      # @return [Array] Signature array
      def signature
        # Normalize by stripping each line and joining
        normalized = @lines.map { |l| l&.strip }.compact.reject(&:empty?).join("\n")
        [:FreezeNode, normalized]
      end

      # Check if this is a function definition (always false for FreezeNode)
      # @return [Boolean]
      def function_definition?
        false
      end

      # Check if this is a variable assignment (always false for FreezeNode)
      # @return [Boolean]
      def variable_assignment?
        false
      end

      # Check if this is a command (always false for FreezeNode)
      # @return [Boolean]
      def command?
        false
      end

      # String representation for debugging
      # @return [String]
      def inspect
        # simplecov:disable
        # Defensive: slice is always set via resolve_content in FreezeNodeBase#initialize
        # The || 0 branch is normally unreachable because validate_structure! ensures non-empty content
        content_length = slice&.length || 0
        # simplecov:enable
        "#<#{self.class.name} lines=#{start_line}..#{end_line} content_length=#{content_length}>"
      end

      private

      def validate_structure!
        validate_line_order!

        if @lines.empty? || @lines.all?(&:nil?)
          raise InvalidStructureError.new(
            "Freeze block is empty",
            start_line: @start_line,
            end_line: @end_line,
          )
        end
      end
    end
  end
end
