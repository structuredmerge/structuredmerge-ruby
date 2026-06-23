# frozen_string_literal: true

module Psych
  module Merge
    # Match refiner for YAML mapping entries that didn't match by exact signature.
    #
    # This refiner uses fuzzy matching to pair mapping entries (key-value pairs) that have:
    # - Similar keys (e.g., `database_url` vs `db_url`)
    # - Keys with typos or naming convention differences
    # - Renamed keys that contain similar values
    #
    # The matching algorithm considers:
    # - Key name similarity (Levenshtein distance)
    # - Value type similarity (both scalars, both mappings, etc.)
    # - Value content similarity for scalars
    #
    # @example Basic usage
    #   refiner = MappingMatchRefiner.new(threshold: 0.6)
    #   matches = refiner.call(template_nodes, dest_nodes)
    #
    # @example With custom weights
    #   refiner = MappingMatchRefiner.new(
    #     threshold: 0.5,
    #     key_weight: 0.6,
    #     value_weight: 0.4
    #   )
    #
    # @see Ast::Merge::MatchRefinerBase
    class MappingMatchRefiner < Ast::Merge::MatchRefinerBase
      # Default weight for key similarity
      DEFAULT_KEY_WEIGHT = 0.7

      # Default weight for value similarity
      DEFAULT_VALUE_WEIGHT = 0.3

      # @return [Float] Weight for key similarity (0.0-1.0)
      attr_reader :key_weight

      # @return [Float] Weight for value similarity (0.0-1.0)
      attr_reader :value_weight

      # Initialize a mapping match refiner.
      #
      # @param threshold [Float] Minimum score to accept a match (default: 0.5)
      # @param key_weight [Float] Weight for key similarity (default: 0.7)
      # @param value_weight [Float] Weight for value similarity (default: 0.3)
      def initialize(threshold: DEFAULT_THRESHOLD, key_weight: DEFAULT_KEY_WEIGHT, value_weight: DEFAULT_VALUE_WEIGHT,
                     **options)
        super(threshold: threshold, **options)
        @key_weight = key_weight
        @value_weight = value_weight
      end

      # Find matches between unmatched mapping entries.
      #
      # @param template_nodes [Array] Unmatched nodes from template
      # @param dest_nodes [Array] Unmatched nodes from destination
      # @param context [Hash] Additional context
      # @return [Array<MatchResult>] Array of mapping entry matches
      def call(template_nodes, dest_nodes, _context = {})
        template_entries = template_nodes.select { |n| mapping_entry?(n) }
        dest_entries = dest_nodes.select { |n| mapping_entry?(n) }

        return [] if template_entries.empty? || dest_entries.empty?

        greedy_match(template_entries, dest_entries) do |t_node, d_node|
          compute_entry_similarity(t_node, d_node)
        end
      end

      private

      # Check if a node is a mapping entry (has a key).
      #
      # @param node [Object] Node to check
      # @return [Boolean]
      def mapping_entry?(node)
        node.respond_to?(:key) && node.key
      end

      # Compute similarity score between two mapping entries.
      #
      # @param t_entry [NodeWrapper] Template entry
      # @param d_entry [NodeWrapper] Destination entry
      # @return [Float] Similarity score (0.0-1.0)
      def compute_entry_similarity(t_entry, d_entry)
        key_score = key_similarity(t_entry.key, d_entry.key)
        value_score = value_similarity(t_entry, d_entry)

        (key_score * key_weight) + (value_score * value_weight)
      end

      # Compute similarity between two keys.
      #
      # @param key1 [NodeWrapper, String] First key
      # @param key2 [NodeWrapper, String] Second key
      # @return [Float] Key similarity (0.0-1.0)
      def key_similarity(key1, key2)
        str1 = normalize_key(key1.to_s)
        str2 = normalize_key(key2.to_s)

        return 1.0 if str1 == str2

        string_similarity(str1, str2)
      end

      # Normalize a key for comparison.
      # Converts to lowercase and normalizes separators.
      #
      # @param key [String] Key to normalize
      # @return [String] Normalized key
      def normalize_key(key)
        key.downcase.gsub(/[-_]/, '')
      end

      # Compute similarity between two entry values.
      #
      # @param t_entry [NodeWrapper] Template entry
      # @param d_entry [NodeWrapper] Destination entry
      # @return [Float] Value similarity (0.0-1.0)
      def value_similarity(t_entry, d_entry)
        t_node = t_entry.respond_to?(:node) ? t_entry.node : t_entry
        d_node = d_entry.respond_to?(:node) ? d_entry.node : d_entry

        # Check if they're the same type
        return 0.0 unless same_value_type?(t_node, d_node)

        case t_node
        when ::Psych::Nodes::Scalar
          # Compare scalar values
          string_similarity(t_node.value.to_s, d_node.value.to_s)
        when ::Psych::Nodes::Mapping
          # Compare mapping structures (by key overlap)
          mapping_structure_similarity(t_node, d_node)
        when ::Psych::Nodes::Sequence
          # Compare sequence lengths
          sequence_similarity(t_node, d_node)
        else
          # Same type but can't compare content
          0.5
        end
      end

      # Check if two nodes have the same value type.
      #
      # @param node1 [Psych::Nodes::Node] First node
      # @param node2 [Psych::Nodes::Node] Second node
      # @return [Boolean]
      def same_value_type?(node1, node2)
        node1.class == node2.class
      end

      # Compute similarity between two mapping structures.
      #
      # @param map1 [Psych::Nodes::Mapping] First mapping
      # @param map2 [Psych::Nodes::Mapping] Second mapping
      # @return [Float] Structural similarity (0.0-1.0)
      def mapping_structure_similarity(map1, map2)
        keys1 = extract_mapping_keys(map1)
        keys2 = extract_mapping_keys(map2)

        return 1.0 if keys1.empty? && keys2.empty?
        return 0.0 if keys1.empty? || keys2.empty?

        common = (keys1 & keys2).size
        total = (keys1 | keys2).size

        common.to_f / total
      end

      # Extract keys from a mapping node.
      #
      # @param mapping [Psych::Nodes::Mapping] Mapping node
      # @return [Array<String>] Keys
      def extract_mapping_keys(mapping)
        return [] unless mapping.children

        keys = []
        i = 0
        while i < mapping.children.length
          key_node = mapping.children[i]
          keys << key_node.value if key_node.is_a?(::Psych::Nodes::Scalar)
          i += 2
        end
        keys
      end

      # Compute similarity between two sequences.
      #
      # @param seq1 [Psych::Nodes::Sequence] First sequence
      # @param seq2 [Psych::Nodes::Sequence] Second sequence
      # @return [Float] Sequence similarity (0.0-1.0)
      def sequence_similarity(seq1, seq2)
        len1 = seq1.children&.length || 0
        len2 = seq2.children&.length || 0

        return 1.0 if len1 == 0 && len2 == 0
        return 0.0 if len1 == 0 || len2 == 0

        [len1, len2].min.to_f / [len1, len2].max
      end

      # Compute string similarity using Levenshtein distance.
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Float] Similarity score (0.0-1.0)
      def string_similarity(str1, str2)
        return 1.0 if str1 == str2
        return 0.0 if str1.empty? || str2.empty?

        distance = levenshtein_distance(str1, str2)
        max_len = [str1.length, str2.length].max

        1.0 - (distance.to_f / max_len)
      end

      # Compute Levenshtein distance between two strings.
      #
      # Uses Wagner-Fischer algorithm with O(min(m,n)) space.
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Integer] Edit distance
      def levenshtein_distance(str1, str2)
        return str2.length if str1.empty?
        return str1.length if str2.empty?

        # Ensure str1 is the shorter string for space optimization
        str1, str2 = str2, str1 if str1.length > str2.length

        m = str1.length
        n = str2.length

        # Use two rows instead of full matrix
        prev_row = (0..m).to_a
        curr_row = Array.new(m + 1, 0)

        (1..n).each do |j|
          curr_row[0] = j

          (1..m).each do |i|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            curr_row[i] = [
              prev_row[i] + 1,      # deletion
              curr_row[i - 1] + 1,  # insertion
              prev_row[i - 1] + cost # substitution
            ].min
          end

          prev_row, curr_row = curr_row, prev_row
        end

        prev_row[m]
      end
    end
  end
end
