# frozen_string_literal: true

module Markdown
  module Merge
    # Algorithm for computing match scores between two Markdown tables.
    #
    # This algorithm uses multiple factors to determine how well two tables match:
    # - (A) Percentage of matching header cells (using Levenshtein similarity)
    # - (B) Percentage of matching cells in the first column (using Levenshtein similarity)
    # - (C) Average percentage of matching cells in rows with matching first column
    # - (D) Percentage of matching total cells
    # - (E) Position distance weight (closer tables score higher)
    #
    # Cell comparisons use Levenshtein distance to compute similarity, allowing
    # partial matches (e.g., "Value" vs "Values" would get a high similarity score).
    #
    # The final score is the weighted average of these factors.
    #
    # @example Basic usage
    #   algorithm = TableMatchAlgorithm.new
    #   score = algorithm.call(table_a, table_b)
    #
    # @example With position information
    #   algorithm = TableMatchAlgorithm.new(
    #     position_a: 0,  # First table in template
    #     position_b: 2,  # Third table in destination
    #     total_tables_a: 3,
    #     total_tables_b: 3
    #   )
    #   score = algorithm.call(table_a, table_b)
    class TableMatchAlgorithm
      # Default weights for each factor in the algorithm
      DEFAULT_WEIGHTS = {
        header_match: 0.25,      # (A) Header row matching
        first_column: 0.20,      # (B) First column matching
        row_content: 0.25,       # (C) Content in matching rows
        total_cells: 0.15,       # (D) Overall cell matching
        position: 0.15 # (E) Position distance
      }.freeze

      # Minimum similarity threshold to consider cells as potentially matching
      # for first column lookup (used in row content matching)
      FIRST_COLUMN_SIMILARITY_THRESHOLD = 0.7

      # @return [Integer, nil] Position of table A in its document (0-indexed)
      attr_reader :position_a

      # @return [Integer, nil] Position of table B in its document (0-indexed)
      attr_reader :position_b

      # @return [Integer] Total number of tables in document A
      attr_reader :total_tables_a

      # @return [Integer] Total number of tables in document B
      attr_reader :total_tables_b

      # @return [Hash] Weights for each scoring factor
      attr_reader :weights

      # @return [Symbol] The markdown backend being used
      attr_reader :backend

      # Initialize the table match algorithm.
      #
      # @param position_a [Integer, nil] Position of first table in its document
      # @param position_b [Integer, nil] Position of second table in its document
      # @param total_tables_a [Integer] Total tables in first document (default: 1)
      # @param total_tables_b [Integer] Total tables in second document (default: 1)
      # @param weights [Hash] Custom weights for scoring factors
      # @param backend [Symbol] Markdown backend for type normalization (default: :commonmarker)
      def initialize(position_a: nil, position_b: nil, total_tables_a: 1, total_tables_b: 1, weights: {},
                     backend: :commonmarker)
        @position_a = position_a
        @position_b = position_b
        @total_tables_a = [total_tables_a, 1].max
        @total_tables_b = [total_tables_b, 1].max
        @weights = DEFAULT_WEIGHTS.merge(weights)
        @backend = backend
      end

      # Compute the match score between two tables.
      #
      # @param table_a [Object] First table node
      # @param table_b [Object] Second table node
      # @return [Float] Score between 0.0 and 1.0
      def call(table_a, table_b)
        rows_a = extract_rows(table_a)
        rows_b = extract_rows(table_b)

        return 0.0 if rows_a.empty? || rows_b.empty?

        scores = {
          header_match: compute_header_match(rows_a, rows_b),
          first_column: compute_first_column_match(rows_a, rows_b),
          row_content: compute_row_content_match(rows_a, rows_b),
          total_cells: compute_total_cells_match(rows_a, rows_b),
          position: compute_position_score
        }

        weighted_average(scores)
      end

      private

      # Compute Levenshtein distance between two strings.
      #
      # Uses the Wagner-Fischer algorithm with O(min(m,n)) space.
      #
      # @param str_a [String] First string
      # @param str_b [String] Second string
      # @return [Integer] Edit distance between the strings
      def levenshtein_distance(str_a, str_b)
        return str_b.length if str_a.empty?
        return str_a.length if str_b.empty?

        # Ensure str_a is the shorter string for space optimization
        str_a, str_b = str_b, str_a if str_a.length > str_b.length

        m = str_a.length
        n = str_b.length

        # Only need two rows at a time
        prev_row = (0..m).to_a
        curr_row = Array.new(m + 1, 0)

        (1..n).each do |j|
          curr_row[0] = j

          (1..m).each do |i|
            cost = str_a[i - 1] == str_b[j - 1] ? 0 : 1
            curr_row[i] = [
              curr_row[i - 1] + 1,      # insertion
              prev_row[i] + 1,          # deletion
              prev_row[i - 1] + cost # substitution
            ].min
          end

          prev_row, curr_row = curr_row, prev_row
        end

        prev_row[m]
      end

      # Compute similarity between two strings using Levenshtein distance.
      #
      # @param str_a [String] First string
      # @param str_b [String] Second string
      # @return [Float] Similarity score between 0.0 and 1.0
      def string_similarity(str_a, str_b)
        a = normalize(str_a)
        b = normalize(str_b)

        return 1.0 if a == b
        return 1.0 if a.empty? && b.empty?
        return 0.0 if a.empty? || b.empty?

        max_len = [a.length, b.length].max
        distance = levenshtein_distance(a, b)

        1.0 - (distance.to_f / max_len)
      end

      # Extract rows from a table node as arrays of cell text.
      #
      # Subclasses may override this for parser-specific iteration.
      #
      # @param table [Object] Table node
      # @return [Array<Array<String>>] Array of rows, each row is array of cell texts
      def extract_rows(table)
        rows = []
        child = table.first_child
        while child
          rows << extract_cells(child) if table_row_type?(child)
          child = next_sibling(child)
        end
        rows
      end

      # Check if a node is a table row type.
      #
      # Uses NodeTypeNormalizer to map backend-specific types to canonical types,
      # enabling portable type checking across different markdown parsers.
      #
      # NOTE: We use `type` here instead of `merge_type` because this method operates
      # on child nodes of tables (table_row, table_header), not top-level statements.
      # Only top-level statements are wrapped by NodeTypeNormalizer with `merge_type`.
      # However, we use NodeTypeNormalizer.canonical_type to normalize the raw type.
      #
      # @param node [Object] Node to check
      # @return [Boolean] true if this is a table row
      def table_row_type?(node)
        return false unless node.respond_to?(:type)

        # Normalize the type using NodeTypeNormalizer for backend portability
        canonical = NodeTypeNormalizer.canonical_type(node.type, @backend || :commonmarker)
        %i[table_row table_header].include?(canonical)
      end

      # Get the next sibling of a node.
      #
      # Different parsers use different methods (next vs next_sibling).
      #
      # @param node [Object] Current node
      # @return [Object, nil] Next sibling or nil
      def next_sibling(node)
        if node.respond_to?(:next_sibling)
          node.next_sibling
        elsif node.respond_to?(:next)
          node.next
        end
      end

      # Extract cell texts from a table row.
      #
      # Uses NodeTypeNormalizer to map backend-specific types to canonical types,
      # enabling portable type checking across different markdown parsers.
      #
      # NOTE: We use `type` here instead of `merge_type` because this method operates
      # on child nodes of table rows (table_cell), not top-level statements.
      # Only top-level statements are wrapped by NodeTypeNormalizer with `merge_type`.
      # However, we use NodeTypeNormalizer.canonical_type to normalize the raw type.
      #
      # @param row [Object] Table row node
      # @return [Array<String>] Array of cell text contents
      def extract_cells(row)
        cells = []
        child = row.first_child
        while child
          if child.respond_to?(:type)
            canonical = NodeTypeNormalizer.canonical_type(child.type, @backend || :commonmarker)
            cells << extract_text_content(child) if canonical == :table_cell
          end
          child = next_sibling(child)
        end
        cells
      end

      # Extract all text content from a node.
      #
      # Uses recursive traversal instead of `walk` for compatibility
      # with tree_haver nodes which don't have a `walk` method.
      #
      # @param node [Object] Node to extract text from
      # @return [String] Concatenated text content
      def extract_text_content(node)
        text_parts = []
        collect_text_recursive(node, text_parts)
        text_parts.join.strip
      end

      # Recursively collect text content from a node and its descendants.
      #
      # Uses NodeTypeNormalizer to map backend-specific types to canonical types,
      # enabling portable type checking across different markdown parsers.
      #
      # NOTE: We use `type` here instead of `merge_type` because this method operates
      # on child nodes (text, code), not top-level statements.
      # Only top-level statements are wrapped by NodeTypeNormalizer with `merge_type`.
      # However, we use NodeTypeNormalizer.canonical_type to normalize the raw type.
      #
      # @param node [Object] The node to traverse
      # @param text_parts [Array<String>] Array to accumulate text into
      # @return [void]
      def collect_text_recursive(node, text_parts)
        # Normalize the type using NodeTypeNormalizer for backend portability
        canonical_type = NodeTypeNormalizer.canonical_type(node.type, @backend || :commonmarker)

        # Collect text from text and code nodes
        if %i[text code].include?(canonical_type)
          content = if node.respond_to?(:string_content)
                      node.string_content.to_s
                    elsif node.respond_to?(:text)
                      node.text.to_s
                    else
                      ''
                    end
          text_parts << content unless content.empty?
        end

        # Recurse into children - support both children array and first_child iteration
        if node.respond_to?(:children)
          node.children.each do |child|
            collect_text_recursive(child, text_parts)
          end
        elsif node.respond_to?(:first_child)
          child = node.first_child
          while child
            collect_text_recursive(child, text_parts)
            child = if child.respond_to?(:next_sibling)
                      child.next_sibling
                    else
                      (child.respond_to?(:next) ? child.next : nil)
                    end
          end
        end
      end

      # (A) Compute header row match percentage using Levenshtein similarity.
      #
      # @param rows_a [Array<Array<String>>] Rows from table A
      # @param rows_b [Array<Array<String>>] Rows from table B
      # @return [Float] Average similarity of header cells (0.0-1.0)
      def compute_header_match(rows_a, rows_b)
        header_a = rows_a.first || []
        header_b = rows_b.first || []

        return 1.0 if header_a.empty? && header_b.empty?
        return 0.0 if header_a.empty? || header_b.empty?

        max_cells = [header_a.size, header_b.size].max

        # Compute similarity for each cell pair
        similarities = header_a.zip(header_b).map do |a, b|
          next 0.0 if a.nil? || b.nil?

          string_similarity(a, b)
        end

        # Pad with zeros for missing cells
        (max_cells - similarities.size).times { similarities << 0.0 }

        similarities.sum / max_cells
      end

      # (B) Compute first column match percentage using Levenshtein similarity.
      #
      # @param rows_a [Array<Array<String>>] Rows from table A
      # @param rows_b [Array<Array<String>>] Rows from table B
      # @return [Float] Percentage of matching first column cells (0.0-1.0)
      def compute_first_column_match(rows_a, rows_b)
        col_a = rows_a.map { |row| row.first }.compact
        col_b = rows_b.map { |row| row.first }.compact

        return 1.0 if col_a.empty? && col_b.empty?
        return 0.0 if col_a.empty? || col_b.empty?

        # For each cell in column A, find best match in column B
        total_similarity = 0.0
        col_a.each do |cell_a|
          best_match = col_b.map { |cell_b| string_similarity(cell_a, cell_b) }.max || 0.0
          total_similarity += best_match
        end

        # Also check cells in B that might not have matches in A
        col_b.each do |cell_b|
          best_match = col_a.map { |cell_a| string_similarity(cell_a, cell_b) }.max || 0.0
          total_similarity += best_match
        end

        # Average over total cells
        total_cells = col_a.size + col_b.size
        total_cells > 0 ? total_similarity / total_cells : 0.0
      end

      # (C) Compute average match percentage for rows with matching first column.
      #
      # Uses Levenshtein similarity to find matching rows by first column.
      #
      # @param rows_a [Array<Array<String>>] Rows from table A
      # @param rows_b [Array<Array<String>>] Rows from table B
      # @return [Float] Average percentage of matching cells in linked rows (0.0-1.0)
      def compute_row_content_match(rows_a, rows_b)
        return 0.0 if rows_a.empty? || rows_b.empty?

        match_scores = []

        rows_a.each do |row_a|
          first_col_a = row_a.first
          next if first_col_a.nil?

          # Find best matching row in B based on first column similarity
          best_row_match = nil
          best_first_col_similarity = 0.0

          rows_b.each do |row_b|
            first_col_b = row_b.first
            next if first_col_b.nil?

            similarity = string_similarity(first_col_a, first_col_b)
            if similarity > best_first_col_similarity && similarity >= FIRST_COLUMN_SIMILARITY_THRESHOLD
              best_first_col_similarity = similarity
              best_row_match = row_b
            end
          end

          next unless best_row_match

          # Compute row content similarity
          match_scores << row_match_score(row_a, best_row_match)
        end

        return 0.0 if match_scores.empty?

        match_scores.sum / match_scores.size
      end

      # Compute match score between two rows using Levenshtein similarity.
      #
      # @param row_a [Array<String>] First row
      # @param row_b [Array<String>] Second row
      # @return [Float] Average similarity of cells (0.0-1.0)
      def row_match_score(row_a, row_b)
        max_cells = [row_a.size, row_b.size].max
        return 1.0 if max_cells == 0

        similarities = row_a.zip(row_b).map do |a, b|
          next 0.0 if a.nil? || b.nil?

          string_similarity(a, b)
        end

        # Pad with zeros for missing cells
        (max_cells - similarities.size).times { similarities << 0.0 }

        similarities.sum / max_cells
      end

      # (D) Compute total cells match percentage using Levenshtein similarity.
      #
      # @param rows_a [Array<Array<String>>] Rows from table A
      # @param rows_b [Array<Array<String>>] Rows from table B
      # @return [Float] Percentage of matching total cells (0.0-1.0)
      def compute_total_cells_match(rows_a, rows_b)
        cells_a = rows_a.flatten.compact
        cells_b = rows_b.flatten.compact

        return 1.0 if cells_a.empty? && cells_b.empty?
        return 0.0 if cells_a.empty? || cells_b.empty?

        # For each cell in A, find best match in B
        used_b_indices = Set.new
        total_similarity = 0.0

        cells_a.each do |cell_a|
          best_similarity = 0.0
          best_index = nil

          cells_b.each_with_index do |cell_b, idx|
            next if used_b_indices.include?(idx)

            similarity = string_similarity(cell_a, cell_b)
            if similarity > best_similarity
              best_similarity = similarity
              best_index = idx
            end
          end

          if best_index && best_similarity > 0.5
            used_b_indices << best_index
            total_similarity += best_similarity
          end
        end

        # Calculate score based on how many cells found good matches
        max_cells = [cells_a.size, cells_b.size].max
        total_similarity / max_cells
      end

      # (E) Compute position-based score.
      #
      # Tables at similar positions in their documents score higher.
      #
      # @return [Float] Position similarity score (0.0-1.0)
      def compute_position_score
        return 1.0 if position_a.nil? || position_b.nil?

        # Normalize positions to 0-1 range based on total tables
        norm_pos_a = position_a.to_f / total_tables_a
        norm_pos_b = position_b.to_f / total_tables_b

        # Distance is absolute difference in normalized positions
        distance = (norm_pos_a - norm_pos_b).abs

        # Convert to similarity (1.0 = same position, 0.0 = max distance)
        1.0 - distance
      end

      # Normalize a cell value for comparison.
      #
      # @param value [String, nil] Cell value
      # @return [String] Normalized value (downcased, stripped)
      def normalize(value)
        value.to_s.strip.downcase
      end

      # Compute weighted average of scores.
      #
      # @param scores [Hash<Symbol, Float>] Individual scores by factor
      # @return [Float] Weighted average score
      def weighted_average(scores)
        total_weight = weights.values.sum
        return 0.0 if total_weight == 0

        weighted_sum = scores.sum { |key, score| score * weights.fetch(key, 0) }
        weighted_sum / total_weight
      end
    end
  end
end
