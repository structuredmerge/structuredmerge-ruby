# frozen_string_literal: true

module Json
  module Merge
    # Match refiner for JSON objects and array elements that didn't match by exact signature.
    #
    # This refiner uses fuzzy matching to pair JSON nodes that have:
    # - Similar key names in objects (e.g., `databaseUrl` vs `database_url`)
    # - Array elements with similar structure or content
    # - Objects with overlapping keys but different values
    #
    # The matching algorithm considers:
    # - Key name similarity for object pairs (Levenshtein distance)
    # - Value type and content similarity
    # - Structural overlap for nested objects
    #
    # @example Basic usage
    #   refiner = ObjectMatchRefiner.new(threshold: 0.6)
    #   matches = refiner.call(template_nodes, dest_nodes)
    #
    # @example With custom weights
    #   refiner = ObjectMatchRefiner.new(
    #     threshold: 0.5,
    #     key_weight: 0.6,
    #     value_weight: 0.4
    #   )
    #
    # @see Ast::Merge::MatchRefinerBase
    class ObjectMatchRefiner < Ast::Merge::MatchRefinerBase
      # Default weight for key similarity
      DEFAULT_KEY_WEIGHT = 0.7

      # Default weight for value similarity
      DEFAULT_VALUE_WEIGHT = 0.3

      # @return [Float] Weight for key similarity (0.0-1.0)
      attr_reader :key_weight

      # @return [Float] Weight for value similarity (0.0-1.0)
      attr_reader :value_weight

      # Initialize an object match refiner.
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

      # Find matches between unmatched JSON nodes.
      #
      # Handles both object key-value pairs and array elements.
      #
      # @param template_nodes [Array] Unmatched nodes from template
      # @param dest_nodes [Array] Unmatched nodes from destination
      # @param context [Hash] Additional context
      # @return [Array<MatchResult>] Array of node matches
      def call(template_nodes, dest_nodes, _context = {})
        # Match object pairs (key-value entries)
        pair_matches = match_pairs(template_nodes, dest_nodes)

        # Match array elements (objects within arrays)
        array_matches = match_array_objects(template_nodes, dest_nodes)

        pair_matches + array_matches
      end

      private

      # Match key-value pairs from JSON objects.
      #
      # @param template_nodes [Array] Template nodes
      # @param dest_nodes [Array] Destination nodes
      # @return [Array<MatchResult>]
      def match_pairs(template_nodes, dest_nodes)
        template_pairs = template_nodes.select { |n| pair_node?(n) }
        dest_pairs = dest_nodes.select { |n| pair_node?(n) }

        return [] if template_pairs.empty? || dest_pairs.empty?

        greedy_match(template_pairs, dest_pairs) do |t_node, d_node|
          compute_pair_similarity(t_node, d_node)
        end
      end

      # Match object elements from JSON arrays.
      #
      # @param template_nodes [Array] Template nodes
      # @param dest_nodes [Array] Destination nodes
      # @return [Array<MatchResult>]
      def match_array_objects(template_nodes, dest_nodes)
        template_objects = template_nodes.select { |n| object_node?(n) && !pair_node?(n) }
        dest_objects = dest_nodes.select { |n| object_node?(n) && !pair_node?(n) }

        return [] if template_objects.empty? || dest_objects.empty?

        greedy_match(template_objects, dest_objects) do |t_node, d_node|
          compute_object_similarity(t_node, d_node)
        end
      end

      # Check if a node is a key-value pair.
      #
      # @param node [Object] Node to check
      # @return [Boolean]
      def pair_node?(node)
        return false unless node.respond_to?(:pair?)

        node.pair?
      end

      # Check if a node is a JSON object.
      #
      # @param node [Object] Node to check
      # @return [Boolean]
      def object_node?(node)
        return false unless node.respond_to?(:object?)

        node.object?
      end

      # Compute similarity score between two key-value pairs.
      #
      # @param t_pair [NodeWrapper] Template pair
      # @param d_pair [NodeWrapper] Destination pair
      # @return [Float] Similarity score (0.0-1.0)
      def compute_pair_similarity(t_pair, d_pair)
        t_key = t_pair.key_name
        d_key = d_pair.key_name

        return 0.0 unless t_key && d_key

        key_score = key_similarity(t_key, d_key)
        value_score = value_similarity(t_pair.value_node, d_pair.value_node)

        (key_score * key_weight) + (value_score * value_weight)
      end

      # Compute similarity score between two JSON objects.
      #
      # @param t_obj [NodeWrapper] Template object
      # @param d_obj [NodeWrapper] Destination object
      # @return [Float] Similarity score (0.0-1.0)
      def compute_object_similarity(t_obj, d_obj)
        t_keys = extract_keys(t_obj)
        d_keys = extract_keys(d_obj)

        return 1.0 if t_keys.empty? && d_keys.empty?
        return 0.0 if t_keys.empty? || d_keys.empty?

        # Compute key overlap
        common_keys = (t_keys & d_keys).size
        total_keys = (t_keys | d_keys).size
        key_overlap = common_keys.to_f / total_keys

        # Compute fuzzy key similarity for non-exact matches
        fuzzy_score = compute_fuzzy_key_matches(t_keys - d_keys, d_keys - t_keys)

        # Combine exact overlap and fuzzy matching
        (key_overlap * 0.7) + (fuzzy_score * 0.3)
      end

      # Compute fuzzy matches between two sets of keys.
      #
      # @param keys1 [Array<String>] First set of keys
      # @param keys2 [Array<String>] Second set of keys
      # @return [Float] Fuzzy match score (0.0-1.0)
      def compute_fuzzy_key_matches(keys1, keys2)
        return 1.0 if keys1.empty? && keys2.empty?
        return 0.0 if keys1.empty? || keys2.empty?

        total_similarity = 0.0
        keys1.each do |k1|
          best_match = keys2.map { |k2| key_similarity(k1, k2) }.max || 0.0
          total_similarity += best_match
        end

        total_similarity / keys1.size
      end

      # Extract keys from a JSON object.
      #
      # @param obj [NodeWrapper] Object node
      # @return [Array<String>] Keys
      def extract_keys(obj)
        return [] unless obj.respond_to?(:pairs)

        obj.pairs.map(&:key_name).compact
      end

      # Compute similarity between two keys.
      #
      # @param key1 [String] First key
      # @param key2 [String] Second key
      # @return [Float] Key similarity (0.0-1.0)
      def key_similarity(key1, key2)
        return 1.0 if key1 == key2

        str1 = normalize_key(key1.to_s)
        str2 = normalize_key(key2.to_s)

        string_similarity(str1, str2)
      end

      # Normalize a key for comparison.
      # Converts to lowercase and normalizes common naming conventions.
      #
      # @param key [String] Key to normalize
      # @return [String] Normalized key
      def normalize_key(key)
        # Convert camelCase to snake_case first, then normalize
        key.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }
           .downcase
           .gsub(/[-_]/, '')
      end

      # Compute similarity between two values.
      #
      # @param t_value [NodeWrapper, nil] Template value
      # @param d_value [NodeWrapper, nil] Destination value
      # @return [Float] Value similarity (0.0-1.0)
      def value_similarity(t_value, d_value)
        return 0.5 unless t_value && d_value

        # Check if they're the same type
        return 0.0 unless same_value_type?(t_value, d_value)

        if t_value.string?
          # Compare string values
          t_text = extract_string_value(t_value)
          d_text = extract_string_value(d_value)
          string_similarity(t_text, d_text)
        elsif t_value.object?
          # Compare object structures
          compute_object_similarity(t_value, d_value)
        elsif t_value.array?
          # Compare array lengths
          array_similarity(t_value, d_value)
        else
          # Same type, consider similar
          0.5
        end
      end

      # Check if two values have the same JSON type.
      #
      # @param val1 [NodeWrapper] First value
      # @param val2 [NodeWrapper] Second value
      # @return [Boolean]
      def same_value_type?(val1, val2)
        val1.type == val2.type
      end

      # Extract string content from a string node.
      #
      # @param node [NodeWrapper] String node
      # @return [String]
      def extract_string_value(node)
        # String nodes include quotes, remove them
        text = node.respond_to?(:text) ? node.text : ''
        text.gsub(/\A"|"\z/, '')
      end

      # Compute similarity between two arrays.
      #
      # @param arr1 [NodeWrapper] First array
      # @param arr2 [NodeWrapper] Second array
      # @return [Float] Array similarity (0.0-1.0)
      def array_similarity(arr1, arr2)
        len1 = arr1.respond_to?(:elements) ? arr1.elements.size : 0
        len2 = arr2.respond_to?(:elements) ? arr2.elements.size : 0

        return 1.0 if len1.zero? && len2.zero?
        return 0.0 if len1.zero? || len2.zero?

        [len1, len2].min.to_f / [len1, len2].max
      end

      # Compute string similarity using Levenshtein distance.
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Float] Similarity score (0.0-1.0)
      def string_similarity(str1, str2)
        return 1.0 if str1 == str2
        return 0.0 if str1.to_s.empty? || str2.to_s.empty?

        distance = levenshtein_distance(str1.to_s, str2.to_s)
        max_len = [str1.to_s.length, str2.to_s.length].max

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
