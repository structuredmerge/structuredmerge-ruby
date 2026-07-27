# frozen_string_literal: true

module Yaml
  module Merge
    class Emitter < Ast::Merge::EmitterBase
      include Ast::Merge::EmitterLineMetadataSupport

      def initialize_subclass_state(**_options)
        initialize_line_metadata_state
      end

      def clear_subclass_state
        clear_line_metadata_state
      end

      def emit_blank_line
        append_line('')
      end

      def emit_tracked_comment(comment)
        indent = ' ' * (comment[:indent] || 0)
        append_line("#{indent}# #{comment[:text]}")
      end

      def emit_comment(text, inline: false)
        if inline
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          append_line("#{current_indent}# #{text}")
        end
      end

      def emit_raw_lines(raw_lines, metadata: nil)
        raw_lines.each_with_index do |line, index|
          append_line(line.chomp, expanded_line_metadata(metadata, index))
        end
      end

      def to_yaml
        to_s
      end
    end
  end
end
