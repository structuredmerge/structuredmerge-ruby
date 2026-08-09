# frozen_string_literal: true

module Json
  module Merge
    # Locates JSON object-pair owners that can be copied as whole source lines.
    class SourceLocator
      Range = Data.define(:start_line, :end_line)

      def initialize(source, dialect:, backend: nil)
        @source = source
        @lines = source.lines
        Json::Merge.register_backend!
        backend_id = backend.to_s.empty? ? Json::Merge::TREE_SITTER_BACKEND.id : backend.to_s
        @analysis = TreeHaver.with_backend(backend_id) do
          FileAnalysis.new(source, dialect: dialect)
        end
      end

      def pair_range(path)
        pair = pair_for(path)
        return unless pair
        return unless whole_line_owner?(pair)

        Range.new(start_line: pair.start_line, end_line: pair.end_line)
      end

      private

      def pair_for(path)
        current = @analysis.root_object
        pair = nil
        segments = pointer_segments(path)
        until segments.empty?
          segment = segments.shift
          pair = pair_with_key(current, segment)
          return unless pair

          current = pair.value_node
        end
        pair
      end

      def pair_with_key(object, key)
        return unless object&.object?

        object.pairs.find { |candidate| candidate.key_name == key }
      end

      def pointer_segments(path)
        return [] if path.to_s.empty?

        path.to_s.split('/').drop(1).map do |segment|
          segment.gsub('~1', '/').gsub('~0', '~')
        end
      end

      def whole_line_owner?(pair)
        start_line = pair.start_line
        end_line = pair.end_line
        return false unless start_line && end_line
        return false unless @lines.fetch(end_line - 1, '').end_with?("\n")

        start_column = pair.node.start_point.fetch(:column)
        @lines.fetch(start_line - 1, '').slice(0, start_column).to_s.strip.empty?
      end
    end
  end
end
