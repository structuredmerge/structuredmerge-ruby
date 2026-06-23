# frozen_string_literal: true

module Toml
  module Merge
    # Match refiner for TOML tables that didn't match by exact signature.
    #
    # This refiner uses string similarity to pair tables that have:
    # - Similar but not identical names
    # - Similar structure (key counts)
    # - Similar key names
    #
    # Tables are matched using a multi-factor scoring algorithm that considers:
    # - Table/section name similarity
    # - Key name overlap
    # - Position in document
    #
    # @example Basic usage
    #   refiner = TableMatchRefiner.new(threshold: 0.5)
    #   matches = refiner.call(template_nodes, dest_nodes)
    #
    # @example With custom weights
    #   refiner = TableMatchRefiner.new(
    #     threshold: 0.6,
    #     weights: {
    #       name_match: 0.5,
    #       key_overlap: 0.3,
    #       position: 0.2
    #     }
    #   )
    #
    # @see Ast::Merge::MatchRefinerBase
    class TableMatchRefiner < Ast::Merge::MatchRefinerBase
      # Default weights for match scoring
      DEFAULT_WEIGHTS = {
        name_match: 0.5,   # Weight for table name similarity
        key_overlap: 0.3,  # Weight for shared keys
        position: 0.2 # Weight for position similarity
      }.freeze

      # @return [Hash] Weights for similarity computation
      attr_reader :weights

      # Initialize a table match refiner.
      #
      # @param threshold [Float] Minimum score to accept a match (default: 0.5)
      # @param weights [Hash] Custom weights for similarity factors
      def initialize(threshold: DEFAULT_THRESHOLD, weights: {}, **options)
        super(threshold: threshold, node_types: [:table], **options)
        @weights = DEFAULT_WEIGHTS.merge(weights)
      end

      # Find matches between unmatched table nodes.
      #
      # @param template_nodes [Array] Unmatched nodes from template
      # @param dest_nodes [Array] Unmatched nodes from destination
      # @param context [Hash] Additional context
      # @return [Array<MatchResult>] Array of table matches
      def call(template_nodes, dest_nodes, _context = {})
        template_tables = extract_tables(template_nodes)
        dest_tables = extract_tables(dest_nodes)

        return [] if template_tables.empty? || dest_tables.empty?

        # Build position information for better matching
        total_template = template_tables.size
        total_dest = dest_tables.size

        greedy_match(template_tables, dest_tables) do |t_node, d_node|
          t_idx = template_tables.index(t_node) || 0
          d_idx = dest_tables.index(d_node) || 0

          compute_table_similarity(t_node, d_node, t_idx, d_idx, total_template, total_dest)
        end
      end

      private

      # Extract table nodes from a collection.
      #
      # @param nodes [Array] Nodes to filter
      # @return [Array] Table nodes only
      def extract_tables(nodes)
        nodes.select { |n| table_node?(n) }
      end

      # Check if a node is a table (TOML section).
      #
      # @param node [Object] Node to check
      # @return [Boolean]
      def table_node?(node)
        return false unless node.respond_to?(:type)

        # Use node's backend if available (NodeWrapper), otherwise default
        backend = node.respond_to?(:backend) ? node.backend : nil
        canonical = if backend
                      NodeTypeNormalizer.canonical_type(node.type,
                                                        backend)
                    else
                      NodeTypeNormalizer.canonical_type(node.type)
                    end
        NodeTypeNormalizer.table_type?(canonical)
      end

      # Compute similarity score between two tables.
      #
      # @param t_table [Object] Template table
      # @param d_table [Object] Destination table
      # @param t_idx [Integer] Template table index
      # @param d_idx [Integer] Destination table index
      # @param total_t [Integer] Total template tables
      # @param total_d [Integer] Total destination tables
      # @return [Float] Similarity score (0.0-1.0)
      def compute_table_similarity(t_table, d_table, t_idx, d_idx, total_t, total_d)
        name_score = compute_name_similarity(t_table, d_table)
        key_score = compute_key_overlap(t_table, d_table)
        position_score = compute_position_similarity(t_idx, d_idx, total_t, total_d)

        # Weighted combination
        @weights[:name_match] * name_score +
          @weights[:key_overlap] * key_score +
          @weights[:position] * position_score
      end

      # Compute name similarity using Levenshtein distance.
      #
      # @param t_table [Object] Template table
      # @param d_table [Object] Destination table
      # @return [Float] Similarity score (0.0-1.0)
      def compute_name_similarity(t_table, d_table)
        t_name = extract_table_name(t_table)
        d_name = extract_table_name(d_table)

        return 1.0 if t_name == d_name
        return 0.0 if t_name.empty? || d_name.empty?

        # Use normalized Levenshtein distance
        distance = levenshtein_distance(t_name, d_name)
        max_len = [t_name.length, d_name.length].max

        1.0 - (distance.to_f / max_len)
      end

      # Extract the table name from a node.
      #
      # @param node [Object] Table node
      # @return [String] Table name
      def extract_table_name(node)
        return node.table_name if node.respond_to?(:table_name) && node.table_name
        return node.key_name if node.respond_to?(:key_name) && node.key_name

        # Fallback: extract from signature if available
        if node.respond_to?(:signature)
          sig = node.signature
          return sig[1] if sig.is_a?(Array) && sig.size > 1
        end

        ''
      end

      # Compute key overlap between two tables.
      #
      # @param t_table [Object] Template table
      # @param d_table [Object] Destination table
      # @return [Float] Jaccard similarity of keys (0.0-1.0)
      def compute_key_overlap(t_table, d_table)
        t_keys = extract_keys(t_table)
        d_keys = extract_keys(d_table)

        return 1.0 if t_keys.empty? && d_keys.empty?
        return 0.0 if t_keys.empty? || d_keys.empty?

        # Jaccard similarity
        intersection = t_keys & d_keys
        union = t_keys | d_keys

        intersection.size.to_f / union.size
      end

      # Extract keys from a table node.
      #
      # @param node [Object] Table node
      # @return [Set<String>] Set of key names
      def extract_keys(node)
        keys = Set.new

        if node.respond_to?(:mergeable_children)
          node.mergeable_children.each do |child|
            keys << child.key_name if child.respond_to?(:key_name) && child.pair?
          end
        end

        keys
      end

      # Compute position similarity.
      #
      # @param t_idx [Integer] Template position
      # @param d_idx [Integer] Destination position
      # @param total_t [Integer] Total template items
      # @param total_d [Integer] Total destination items
      # @return [Float] Position similarity (0.0-1.0)
      def compute_position_similarity(t_idx, d_idx, total_t, total_d)
        return 1.0 if total_t == 1 && total_d == 1

        # Normalize positions to [0, 1]
        t_pos = total_t > 1 ? t_idx.to_f / (total_t - 1) : 0.5
        d_pos = total_d > 1 ? d_idx.to_f / (total_d - 1) : 0.5

        1.0 - (t_pos - d_pos).abs
      end

      # Compute Levenshtein distance between two strings.
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Integer] Edit distance
      def levenshtein_distance(str1, str2)
        m = str1.length
        n = str2.length

        return n if m.zero?
        return m if n.zero?

        # Create distance matrix
        d = Array.new(m + 1) { Array.new(n + 1) }

        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }

        (1..m).each do |i|
          (1..n).each do |j|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,      # deletion
              d[i][j - 1] + 1,      # insertion
              d[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        d[m][n]
      end
    end
  end
end
