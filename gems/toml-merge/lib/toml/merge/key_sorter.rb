# frozen_string_literal: true

module Toml
  module Merge
    # Sorts key=value pairs alphabetically within gap-separated blocks
    # in merged TOML output. Comments are treated as "leading" — owned
    # by the key that follows them.
    #
    # Blank lines act as block separators. Sorting is applied independently
    # within each contiguous block of key=value pairs (and their leading comments).
    #
    # Table/array-of-tables headers are structural boundaries that start new blocks.
    #
    # @example
    #   sorter = KeySorter.new(result_lines)
    #   sorter.sort!
    class KeySorter
      # Pattern matching a TOML key=value pair line
      KEY_VALUE_RE = /\A\s*([^\[#\s][^\s=]*)\s*=/

      # Pattern matching a table header [name] or [[name]]
      TABLE_HEADER_RE = /\A\s*\[{1,2}[^\]]+\]{1,2}/

      # Pattern matching a comment line
      COMMENT_RE = /\A\s*#/

      # @param lines [Array<Hash>] MergeResult line hashes with :content key
      def initialize(lines)
        @lines = lines
      end

      # Sort key=value pairs alphabetically within gap-separated blocks.
      # Modifies @lines in place.
      #
      # @return [Array<Hash>] The sorted lines
      def sort!
        blocks = partition_into_blocks
        sorted_lines = []

        blocks.each do |block|
          if block[:sortable]
            sorted_lines.concat(sort_block(block[:entries]))
          else
            sorted_lines.concat(block[:lines])
          end
        end

        @lines.replace(sorted_lines)
      end

      private

      # Partition lines into structural blocks.
      # A block is either:
      # - A sortable block: contiguous key=value pairs with optional leading comments
      # - A non-sortable block: blank lines, table headers, preamble comments
      #
      # @return [Array<Hash>] blocks with :sortable, :lines/:entries keys
      def partition_into_blocks
        blocks = []
        current_entries = []  # accumulates {comments: [...], key_line: hash, sort_key: str}
        pending_comments = [] # comments waiting to be assigned to next key

        flush_sortable = lambda {
          unless current_entries.empty?
            blocks << { sortable: true, entries: current_entries }
            current_entries = []
          end
          unless pending_comments.empty?
            # Trailing comments with no following key — emit as non-sortable
            blocks << { sortable: false, lines: pending_comments }
            pending_comments = []
          end
        }

        @lines.each do |line_hash|
          content = line_hash[:content].to_s

          if content.strip.empty?
            # Blank line = gap separator
            flush_sortable.call
            blocks << { sortable: false, lines: [line_hash] }
          elsif TABLE_HEADER_RE.match?(content)
            # Table header = structural boundary
            flush_sortable.call
            blocks << { sortable: false, lines: [line_hash] }
          elsif (match = KEY_VALUE_RE.match(content))
            # Key=value pair
            sort_key = match[1]
            current_entries << {
              comments: pending_comments,
              key_line: line_hash,
              sort_key: sort_key
            }
            pending_comments = []
          elsif COMMENT_RE.match?(content)
            # Comment — accumulate as leading for next key
            pending_comments << line_hash
          else
            # Unknown line — treat as non-sortable boundary
            flush_sortable.call
            blocks << { sortable: false, lines: [line_hash] }
          end
        end

        flush_sortable.call
        blocks
      end

      # Sort entries within a block alphabetically by key name.
      #
      # @param entries [Array<Hash>] entries with :comments, :key_line, :sort_key
      # @return [Array<Hash>] flattened sorted lines
      def sort_block(entries)
        sorted = entries.sort_by { |e| e[:sort_key] }
        sorted.flat_map { |e| e[:comments] + [e[:key_line]] }
      end
    end
  end
end
