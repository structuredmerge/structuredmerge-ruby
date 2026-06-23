# frozen_string_literal: true

module Psych
  module Merge
    # Custom YAML emitter that preserves comments and formatting.
    # This class provides utilities for emitting YAML while maintaining
    # the original structure, comments, and style choices.
    #
    # Inherits common emitter functionality from Ast::Merge::EmitterBase.
    #
    # @example Basic usage
    #   emitter = Emitter.new
    #   emitter.emit_mapping_entry(key, value, leading_comments: comments)
    class Emitter < Ast::Merge::EmitterBase
      include Ast::Merge::EmitterLineMetadataSupport

      # Initialize subclass-specific state
      def initialize_subclass_state(**_options)
        initialize_line_metadata_state
      end

      # Clear subclass-specific state
      def clear_subclass_state
        clear_line_metadata_state
      end

      def emit_blank_line
        append_line('')
      end

      # Emit a tracked comment from CommentTracker
      # @param comment [Hash] Comment with :text, :indent
      def emit_tracked_comment(comment)
        indent = ' ' * (comment[:indent] || 0)
        append_line("#{indent}# #{comment[:text]}")
      end

      # Emit a comment line
      #
      # @param text [String] Comment text (without #)
      # @param inline [Boolean] Whether this is an inline comment
      def emit_comment(text, inline: false)
        if inline
          # Inline comments are appended to the last line
          return if @lines.empty?

          @lines[-1] = "#{@lines[-1]} # #{text}"
        else
          append_line("#{current_indent}# #{text}")
        end
      end

      # Emit a scalar value
      #
      # @param key [String] Key name
      # @param value [String] Value
      # @param style [Symbol] Style (:plain, :single_quoted, :double_quoted, :literal, :folded)
      # @param inline_comment [String, nil] Optional inline comment
      def emit_scalar_entry(key, value, style: :plain, inline_comment: nil, metadata: nil)
        formatted_value = format_scalar(value, style)
        line = "#{current_indent}#{key}: #{formatted_value}"
        line += " # #{inline_comment}" if inline_comment
        append_line(line, metadata)
      end

      # Emit a mapping start (for nested mappings)
      #
      # @param key [String] Key name
      # @param anchor [String, nil] Anchor name (without &)
      def emit_mapping_start(key, anchor: nil, metadata: nil)
        anchor_str = anchor ? " &#{anchor}" : ''
        append_line("#{current_indent}#{key}:#{anchor_str}", metadata)
        indent
      end

      # Emit a mapping end
      def emit_mapping_end
        dedent
      end

      # Emit a sequence start
      #
      # @param key [String, nil] Key name (nil for inline sequence)
      # @param anchor [String, nil] Anchor name
      def emit_sequence_start(key, anchor: nil, metadata: nil)
        return unless key

        anchor_str = anchor ? " &#{anchor}" : ''
        append_line("#{current_indent}#{key}:#{anchor_str}", metadata)
        indent
      end

      # Emit a sequence item
      #
      # @param value [String] Item value
      # @param inline_comment [String, nil] Optional inline comment
      def emit_sequence_item(value, inline_comment: nil, metadata: nil)
        line = "#{current_indent}- #{value}"
        line += " # #{inline_comment}" if inline_comment
        append_line(line, metadata)
      end

      # Emit a sequence end
      def emit_sequence_end
        dedent
      end

      # Emit an alias reference
      #
      # @param key [String] Key name
      # @param anchor [String] Anchor name being referenced (without *)
      def emit_alias(key, anchor, metadata: nil)
        append_line("#{current_indent}#{key}: *#{anchor}", metadata)
      end

      # Emit a merge key with alias
      #
      # @param anchor [String] Anchor name to merge (without *)
      def emit_merge_key(anchor, metadata: nil)
        append_line("#{current_indent}<<: *#{anchor}", metadata)
      end

      def emit_raw_lines(raw_lines, metadata: nil)
        raw_lines.each_with_index do |line, idx|
          append_line(line.chomp, expanded_line_metadata(metadata, idx))
        end
      end

      # Get the output as a YAML string
      #
      # @return [String]
      def to_yaml
        to_s
      end

      private

      def emit_inline_comment_text(text, region:, target_column: nil)
        return if text.empty? || @lines.empty?

        unless target_column
          emit_comment(text, inline: true)
          return
        end

        base = @lines[-1].to_s.rstrip
        comment_suffix = text.empty? ? '#' : "# #{text}"
        @lines[-1] = base.ljust([target_column.to_i, base.length + 1].max) + comment_suffix
      end

      def inline_comment_region_target_column(region, current_line:)
        tracked_hash = region.respond_to?(:metadata) ? Array(region.metadata[:tracked_hashes]).first : nil
        tracked_hash && (tracked_hash[:indent] || tracked_hash['indent'])
      end

      def comment_region_nodes(region)
        nodes = Array(region.nodes)
        return nodes if nodes.length < 2

        segment_length = repeated_region_segment_length(nodes)
        return nodes unless segment_length

        nodes.first(segment_length)
      end

      def repeated_region_segment_length(nodes)
        signatures = nodes.map { |node| comment_region_node_signature(node) }

        (1..(signatures.length / 2)).each do |segment_length|
          next if (signatures.length % segment_length).nonzero?

          segment = signatures.first(segment_length)
          repeats = signatures.length / segment_length
          return segment_length if repeats > 1 && (0...repeats).all? do |idx|
            signatures.slice(idx * segment_length, segment_length) == segment
          end
        end

        nil
      end

      def comment_region_node_signature(node)
        if node.respond_to?(:slice)
          node.slice.to_s.chomp
        elsif node.respond_to?(:text)
          node.text.to_s.chomp
        elsif node.respond_to?(:normalized_content)
          node.normalized_content.to_s
        else
          node.to_s
        end
      end

      def format_scalar(value, style)
        case style
        when :single_quoted
          "'#{escape_single_quotes(value)}'"
        when :double_quoted
          "\"#{escape_double_quotes(value)}\""
        when :literal
          # Literal scalars need special handling
          "|\n#{indent_multiline(value)}"
        when :folded
          # Folded scalars need special handling
          ">\n#{indent_multiline(value)}"
        else
          # Plain style - check if quoting is needed
          needs_quoting?(value) ? "\"#{escape_double_quotes(value)}\"" : value.to_s
        end
      end

      def escape_single_quotes(value)
        value.to_s.gsub("'", "''")
      end

      def escape_double_quotes(value)
        value.to_s
             .gsub('\\', '\\\\')
             .gsub('"', '\"')
             .gsub("\n", '\\n')
             .gsub("\t", '\\t')
      end

      def indent_multiline(value)
        value.to_s.lines.map { |line| "#{current_indent}  #{line.chomp}" }.join("\n")
      end

      def needs_quoting?(value)
        str = value.to_s

        # Empty string needs quotes
        return true if str.empty?

        # Check for special characters that need quoting
        return true if /^[&*!|>'"%@`]/.match?(str)
        return true if /[:#\[\]{}?,]/.match?(str)
        return true if /^\s|\s$/.match?(str)
        return true if /\n/.match?(str)

        # Check for boolean/null-like values
        return true if %w[true false yes no on off null ~].include?(str.downcase)

        # Check for numeric values that should stay as strings
        return true if str =~ /^\d+$/ && str.start_with?('0') && str.length > 1

        false
      end
    end
  end
end
