# frozen_string_literal: true

module Json
  module Merge
    # Extracts and tracks comments with their line numbers from JSON / JSONC
    # source. The current tree-sitter JSON grammar can surface JSONC comments,
    # so json-merge now uses the shared C-style comment tracker as well.
    class CommentTracker < Ast::Merge::Comment::CStyleTrackerBase
      # @param source [String] JSON / JSONC source code
      def initialize(source)
        @source = source
        super(source.lines.map(&:chomp))
      end

      private

      def owner_line_num(owner)
        return owner.start_line if owner.respond_to?(:start_line) && owner.start_line
        if owner.respond_to?(:key) && owner.key&.respond_to?(:start_line) && owner.key.start_line
          return owner.key.start_line
        end

        nil
      end
    end
  end
end
