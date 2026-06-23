# frozen_string_literal: true

module Psych
  module Merge
    # Maps unified git diffs to YAML AST paths.
    #
    # DiffMapper parses unified diffs and maps changed lines to their
    # corresponding YAML key paths (e.g., ["AllCops", "Exclude"]).
    #
    # @example Basic usage
    #   mapper = DiffMapper.new
    #   mappings = mapper.map(diff_text, original_yaml)
    #
    #   mappings.each do |mapping|
    #     puts "Path: #{mapping.path.join('.')}"
    #     puts "Operation: #{mapping.operation}"
    #   end
    #
    # @see Ast::Merge::DiffMapperBase
    class DiffMapper < ::Ast::Merge::DiffMapperBase
      # Create a FileAnalysis for the original YAML content.
      #
      # @param content [String] The original YAML content
      # @return [FileAnalysis] Analyzed YAML file
      def create_analysis(content)
        FileAnalysis.new(content)
      end

      # Map a diff hunk to YAML key paths.
      #
      # @param hunk [DiffHunk] The hunk to map
      # @param original_analysis [FileAnalysis] Analysis of the original YAML
      # @return [Array<DiffMapping>] Mappings for this hunk
      def map_hunk_to_paths(hunk, original_analysis)
        mappings = []

        # Group consecutive changed lines by their containing node
        path_groups = group_lines_by_path(hunk, original_analysis)

        path_groups.each do |path, lines|
          mappings << DiffMapping.new(
            path: path,
            operation: determine_operation_for_lines(lines),
            lines: lines,
            hunk: hunk
          )
        end

        mappings
      end

      protected

      # Build the YAML key path for a node.
      #
      # @param node [MappingEntry, NodeWrapper] The AST node
      # @param analysis [FileAnalysis] The file analysis
      # @return [Array<String, Integer>] Path components
      def build_path_for_node(node, _analysis)
        path = []

        # For MappingEntry, the key name is the primary identifier
        path << node.key_name if node.respond_to?(:key_name) && node.key_name

        path
      end

      private

      # Group changed lines by their containing YAML path.
      #
      # @param hunk [DiffHunk] The hunk to process
      # @param analysis [FileAnalysis] Analysis of the original file
      # @return [Hash<Array, Array<DiffLine>>] Map of path to lines
      def group_lines_by_path(hunk, analysis)
        path_groups = Hash.new { |h, k| h[k] = [] }

        hunk.lines.each do |line|
          next if line.type == :context

          # For removals, use old_line_num; for additions, we need to infer
          line_num = line.old_line_num || infer_insertion_line(line, hunk, analysis)

          if line_num
            path = find_path_at_line(line_num, line.content, analysis)
            path_groups[path] << line
          else
            # Can't determine line position, use root path
            path_groups[[]] << line
          end
        end

        path_groups
      end

      # Find the YAML key path containing a specific line.
      #
      # @param line_num [Integer] 1-based line number
      # @param content [String] The line content (for inferring nested position)
      # @param analysis [FileAnalysis] The file analysis
      # @return [Array<String>] The key path
      def find_path_at_line(line_num, content, analysis)
        path = []

        # Find the statement containing this line
        containing_node = find_node_at_line(line_num, analysis.statements)

        if containing_node
          # Get the top-level key
          path << containing_node.key_name if containing_node.respond_to?(:key_name)

          # Check if this line is inside a nested structure
          nested_path = find_nested_path(line_num, content, containing_node, analysis)
          path.concat(nested_path) if nested_path.any?
        else
          # Line is outside any known statement - infer from indentation
          inferred_path = infer_path_from_indentation(line_num, content, analysis)
          path.concat(inferred_path)
        end

        path
      end

      # Find the nested path within a container node.
      #
      # @param line_num [Integer] 1-based line number
      # @param content [String] Line content
      # @param container [MappingEntry] The containing node
      # @param analysis [FileAnalysis] The file analysis
      # @return [Array<String>] Nested path components
      def find_nested_path(line_num, content, container, analysis)
        nested_path = []

        return nested_path unless container.respond_to?(:value)

        value = container.value

        # If the value is a mapping, look for nested keys
        if value.respond_to?(:mapping?) && value.mapping?
          entries = value.mapping_entries(comment_tracker: analysis.comment_tracker)

          entries.each do |key_wrapper, value_wrapper|
            key_start = key_wrapper.start_line
            value_end = value_wrapper.end_line

            next unless key_start && value_end && line_num >= key_start && line_num <= value_end

            nested_path << key_wrapper.value if key_wrapper.value

            # Recursively check for deeper nesting
            nested_entry = MappingEntry.new(
              key: key_wrapper,
              value: value_wrapper,
              lines: analysis.lines,
              comment_tracker: analysis.comment_tracker
            )
            deeper = find_nested_path(line_num, content, nested_entry, analysis)
            nested_path.concat(deeper)
            break
          end
        elsif value.respond_to?(:sequence?) && value.sequence?
          # For sequences, try to find the index
          items = value.sequence_items(comment_tracker: analysis.comment_tracker)
          items.each_with_index do |item, idx|
            next unless item.start_line && item.end_line &&
                        line_num >= item.start_line && line_num <= item.end_line

            nested_path << idx
            break
          end
        end

        nested_path
      end

      # Infer path from indentation when line is outside known nodes.
      # This happens for additions where we can't find the exact position.
      #
      # @param line_num [Integer] 1-based line number
      # @param content [String] Line content
      # @param analysis [FileAnalysis] The file analysis
      # @return [Array<String>] Inferred path
      def infer_path_from_indentation(line_num, content, analysis)
        path = []

        # Calculate indentation level
        indent = content.match(/^(\s*)/)[1].length

        # Look backwards for parent keys at lower indentation
        (line_num - 1).downto(1) do |check_line|
          line = analysis.line_at(check_line)
          next unless line

          line_indent = line.match(/^(\s*)/)[1].length

          # If this line has less indentation and looks like a key
          next unless line_indent < indent && line =~ /^(\s*)(\w+):/

          key = ::Regexp.last_match(2)
          path.unshift(key)
          indent = line_indent

          # Stop if we've reached root level
          break if indent == 0
        end

        path
      end

      # Infer the insertion line for an addition based on context.
      #
      # @param line [DiffLine] The addition line
      # @param hunk [DiffHunk] The containing hunk
      # @param analysis [FileAnalysis] The file analysis
      # @return [Integer, nil] The inferred line number or nil
      def infer_insertion_line(line, hunk, _analysis)
        # Find the nearest context or removal line before this addition
        line_index = hunk.lines.index(line)
        return unless line_index

        # Look backwards for a line with an old_line_num
        (line_index - 1).downto(0) do |idx|
          prev_line = hunk.lines[idx]
          return prev_line.old_line_num if prev_line.old_line_num
        end

        # If no previous line, use hunk's old_start
        hunk.old_start
      end

      # Determine operation type for a group of lines.
      #
      # @param lines [Array<DiffLine>] Lines in the group
      # @return [Symbol] :add, :remove, or :modify
      def determine_operation_for_lines(lines)
        has_additions = lines.any? { |l| l.type == :addition }
        has_removals = lines.any? { |l| l.type == :removal }

        if has_additions && has_removals
          :modify
        elsif has_additions
          :add
        else
          :remove
        end
      end
    end
  end
end
