# frozen_string_literal: true

module Ast
  module Merge
    module EmitterLineMetadataSupport
      attr_reader :line_metadata

      private

      def initialize_line_metadata_state
        @line_metadata = []
      end

      def clear_line_metadata_state
        @line_metadata = []
      end

      def append_line(line, metadata = nil)
        @lines << line
        @line_metadata << metadata.to_h.compact
      end

      def expanded_line_metadata(metadata, index)
        data = metadata.to_h
        return {} if data.empty?

        compact_line_metadata(
          source: data[:source],
          original_line: if data.key?(:line_numbers)
                           Array(data[:line_numbers])[index]
                         elsif data.key?(:original_line_start)
                           data[:original_line_start].to_i + index
                         else
                           data[:original_line]
                         end
        )
      end

      def compact_line_metadata(metadata)
        metadata.each_with_object({}) do |(key, value), hash|
          hash[key] = value unless value.nil?
        end
      end
    end
  end
end
