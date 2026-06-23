# frozen_string_literal: true

module Ast
  module Merge
    # Base class for mapping unified git diffs to AST node paths.
    #
    # DiffMapperBase provides a format-agnostic foundation for parsing unified
    # git diffs and mapping changed lines to AST node paths. Subclasses implement
    # format-specific logic to determine which AST nodes are affected by each change.
    #
    # @example Basic usage with a subclass
    #   class Psych::Merge::DiffMapper < Ast::Merge::DiffMapperBase
    #     def map_hunk_to_paths(hunk, original_analysis)
    #       # YAML-specific implementation
    #     end
    #   end
    #
    #   mapper = Psych::Merge::DiffMapper.new
    #   mappings = mapper.map(diff_text, original_content)
    #
    # @abstract Subclass and implement {#map_hunk_to_paths}
    class DiffMapperBase
      # Represents a single hunk from a unified diff
      DiffHunk = Struct.new(
        :old_start,    # Starting line in original file (1-based)
        :old_count,    # Number of lines in original
        :new_start,    # Starting line in new file (1-based)
        :new_count,    # Number of lines in new file
        :lines,        # Array of DiffLine objects
        :header,       # The @@ header line
        keyword_init: true
      )

      # Represents a single line in a diff hunk
      DiffLine = Struct.new(
        :type,         # :context, :addition, :removal
        :content,      # Line content (without +/- prefix)
        :old_line_num, # Line number in original file (nil for additions)
        :new_line_num, # Line number in new file (nil for removals)
        keyword_init: true
      )

      # Represents a mapping from diff changes to AST paths
      DiffMapping = Struct.new(
        :path,         # Array of keys/indices representing AST path (e.g., ["AllCops", "Exclude"])
        :operation,    # :add, :remove, or :modify
        :lines,        # Array of DiffLine objects for this path
        :hunk,         # The source DiffHunk
        keyword_init: true
      )

      # Result of parsing a diff file
      DiffParseResult = Struct.new(
        :old_file,     # Original file path from --- line
        :new_file,     # New file path from +++ line
        :hunks,        # Array of DiffHunk objects
        keyword_init: true
      )

      # Parse a unified diff and map changes to AST paths.
      #
      # @param diff_text [String] The unified diff content
      # @param original_content [String] The original file content (for AST path mapping)
      # @return [Array<DiffMapping>] Mappings from changes to AST paths
      def map(diff_text, original_content)
        parse_result = parse_diff(diff_text)
        return [] if parse_result.hunks.empty?

        original_analysis = create_analysis(original_content)

        parse_result.hunks.flat_map do |hunk|
          map_hunk_to_paths(hunk, original_analysis)
        end
      end

      # Parse a unified diff into structured hunks.
      #
      # @param diff_text [String] The unified diff content
      # @return [DiffParseResult] Parsed diff with file paths and hunks
      def parse_diff(diff_text)
        lines = diff_text.lines.map(&:chomp)

        old_file = nil
        new_file = nil
        hunks = []
        current_hunk = nil
        old_line_num = nil
        new_line_num = nil

        lines.each do |line|
          case line
          when /^---\s+(.+)$/
            # Original file path
            old_file = extract_file_path(::Regexp.last_match(1))
          when /^\+\+\+\s+(.+)$/
            # New file path
            new_file = extract_file_path(::Regexp.last_match(1))
          when /^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@/
            # Hunk header
            # Finalize previous hunk
            hunks << current_hunk if current_hunk

            old_start = ::Regexp.last_match(1).to_i
            old_count = (::Regexp.last_match(2) || '1').to_i
            new_start = ::Regexp.last_match(3).to_i
            new_count = (::Regexp.last_match(4) || '1').to_i

            current_hunk = DiffHunk.new(
              old_start: old_start,
              old_count: old_count,
              new_start: new_start,
              new_count: new_count,
              lines: [],
              header: line
            )
            old_line_num = old_start
            new_line_num = new_start
          when /^\+(.*)$/
            # Addition (not +++ header line, already handled)
            next unless current_hunk

            current_hunk.lines << DiffLine.new(
              type: :addition,
              content: ::Regexp.last_match(1),
              old_line_num: nil,
              new_line_num: new_line_num
            )
            new_line_num += 1
          when /^-(.*)$/
            # Removal (not --- header line, already handled)
            next unless current_hunk

            current_hunk.lines << DiffLine.new(
              type: :removal,
              content: ::Regexp.last_match(1),
              old_line_num: old_line_num,
              new_line_num: nil
            )
            old_line_num += 1
          when /^ (.*)$/
            # Context line
            next unless current_hunk

            current_hunk.lines << DiffLine.new(
              type: :context,
              content: ::Regexp.last_match(1),
              old_line_num: old_line_num,
              new_line_num: new_line_num
            )
            old_line_num += 1
            new_line_num += 1
          end
        end

        # Finalize last hunk
        hunks << current_hunk if current_hunk

        DiffParseResult.new(
          old_file: old_file,
          new_file: new_file,
          hunks: hunks
        )
      end

      # Determine the operation type for a hunk.
      #
      # @param hunk [DiffHunk] The hunk to analyze
      # @return [Symbol] :add, :remove, or :modify
      def determine_operation(hunk)
        has_additions = hunk.lines.any? { |l| l.type == :addition }
        has_removals = hunk.lines.any? { |l| l.type == :removal }

        if has_additions && has_removals
          :modify
        elsif has_additions
          :add
        elsif has_removals
          :remove
        else
          :modify # Context-only hunk (unusual)
        end
      end

      # Create a file analysis for the original content.
      # Subclasses must implement this to return their format-specific analysis.
      #
      # @param content [String] The original file content
      # @return [Object] A FileAnalysis object for the format
      # @abstract
      def create_analysis(content)
        raise NotImplementedError, 'Subclasses must implement #create_analysis'
      end

      # Map a single hunk to AST paths.
      # Subclasses must implement this with format-specific logic.
      #
      # @param hunk [DiffHunk] The hunk to map
      # @param original_analysis [Object] FileAnalysis of the original content
      # @return [Array<DiffMapping>] Mappings for this hunk
      # @abstract
      def map_hunk_to_paths(hunk, original_analysis)
        raise NotImplementedError, 'Subclasses must implement #map_hunk_to_paths'
      end

      protected

      # Extract file path from diff header, handling common prefixes.
      #
      # @param path_string [String] Path from --- or +++ line
      # @return [String] Cleaned file path
      def extract_file_path(path_string)
        # Remove common prefixes: a/, b/, or timestamp suffixes
        path_string
          .sub(%r{^[ab]/}, '')
          .sub(/\t.*$/, '') # Remove timestamp suffix
          .strip
      end

      # Find the AST node that contains a given line number.
      # Helper method for subclasses.
      #
      # @param line_num [Integer] 1-based line number
      # @param statements [Array] Array of statement nodes
      # @return [Object, nil] The containing node or nil
      def find_node_at_line(line_num, statements)
        statements.find do |node|
          next unless node.respond_to?(:start_line) && node.respond_to?(:end_line)
          next unless node.start_line && node.end_line

          line_num.between?(node.start_line, node.end_line)
        end
      end

      # Build a path array from a node's ancestry.
      # Helper method for subclasses to override with format-specific logic.
      #
      # @param node [Object] The AST node
      # @param analysis [Object] The file analysis
      # @return [Array<String, Integer>] Path components
      def build_path_for_node(node, analysis)
        raise NotImplementedError, 'Subclasses must implement #build_path_for_node'
      end
    end
  end
end
