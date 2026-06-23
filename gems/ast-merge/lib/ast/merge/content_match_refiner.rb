# frozen_string_literal: true

module Ast
  module Merge
    # Match refiner for text content-based fuzzy matching.
    #
    # This refiner uses Levenshtein distance to pair nodes that have similar
    # but not identical text content. It's useful for matching nodes where
    # the content has been slightly modified (typos, rewording, etc.).
    #
    # Unlike signature-based matching which requires exact content hashes,
    # this refiner allows fuzzy matching based on text similarity. This is
    # particularly useful for:
    # - Paragraphs with minor edits
    # - Headings with slight rewording
    # - Comments with updated text
    # - Any text-based node type
    #
    # @example Basic usage
    #   refiner = ContentMatchRefiner.new(threshold: 0.7)
    #   matches = refiner.call(template_nodes, dest_nodes)
    #
    # @example With specific node types
    #   # Only match paragraphs and headings
    #   refiner = ContentMatchRefiner.new(
    #     threshold: 0.6,
    #     node_types: [:paragraph, :heading]
    #   )
    #
    # @example With custom content extractor
    #   refiner = ContentMatchRefiner.new(
    #     threshold: 0.7,
    #     content_extractor: ->(node) { node.text_content.downcase.strip }
    #   )
    #
    # @example Combined with other refiners
    #   merger = SmartMerger.new(
    #     template,
    #     destination,
    #     match_refiner: [
    #       ContentMatchRefiner.new(threshold: 0.7, node_types: [:paragraph]),
    #       TableMatchRefiner.new(threshold: 0.5)
    #     ]
    #   )
    #
    # @see MatchRefinerBase Base class
    class ContentMatchRefiner < MatchRefinerBase
      # Default weights for content similarity scoring
      DEFAULT_WEIGHTS = {
        content: 0.7,   # Text content similarity (Levenshtein)
        length: 0.15,   # Length similarity
        position: 0.15 # Position similarity in document
      }.freeze

      # @return [Hash] Scoring weights
      attr_reader :weights

      # @return [Proc, nil] Custom content extraction function
      attr_reader :content_extractor

      # Initialize a content match refiner.
      #
      # @param threshold [Float] Minimum score to accept a match (default: 0.5)
      # @param node_types [Array<Symbol>] Node types to process (empty = all)
      # @param weights [Hash] Custom scoring weights
      # @param content_extractor [Proc, nil] Custom function to extract text from nodes
      #   Should accept a node and return a String
      # @param options [Hash] Additional options for forward compatibility
      def initialize(
        threshold: DEFAULT_THRESHOLD,
        node_types: [],
        weights: {},
        content_extractor: nil,
        **options
      )
        super(threshold: threshold, node_types: node_types, **options)
        @weights = DEFAULT_WEIGHTS.merge(weights)
        @content_extractor = content_extractor
      end

      # Find matches between unmatched nodes based on content similarity.
      #
      # @param template_nodes [Array] Unmatched nodes from template
      # @param dest_nodes [Array] Unmatched nodes from destination
      # @param context [Hash] Additional context (may contain :template_analysis, :dest_analysis)
      # @return [Array<MatchResult>] Array of content-based matches
      def call(template_nodes, dest_nodes, _context = {})
        template_filtered = filter_nodes(template_nodes)
        dest_filtered = filter_nodes(dest_nodes)

        return [] if template_filtered.empty? || dest_filtered.empty?

        # Build position information for scoring
        total_template = template_filtered.size
        total_dest = dest_filtered.size

        greedy_match(template_filtered, dest_filtered) do |t_node, d_node|
          t_idx = template_filtered.index(t_node) || 0
          d_idx = dest_filtered.index(d_node) || 0

          compute_content_similarity(
            t_node,
            d_node,
            t_idx,
            d_idx,
            total_template,
            total_dest
          )
        end
      end

      protected

      # Filter nodes by configured node types.
      #
      # @param nodes [Array] Nodes to filter
      # @return [Array] Filtered nodes (matching node_types, or all if empty)
      def filter_nodes(nodes)
        return nodes if node_types.empty?

        nodes.select { |n| handles_type?(extract_node_type(n)) }
      end

      # Extract the type from a node.
      #
      # Handles wrapped nodes (merge_type) and raw nodes (type).
      #
      # @param node [Object] The node
      # @return [Symbol, nil] The node type
      def extract_node_type(node)
        if NodeTyping.typed_node?(node)
          NodeTyping.merge_type_for(node)
        elsif node.respond_to?(:merge_type) && node.merge_type
          node.merge_type
        elsif node.respond_to?(:type)
          type = node.type
          type.is_a?(Symbol) ? type : type.to_s.to_sym
        end
      end

      # Extract text content from a node.
      #
      # Uses the custom content_extractor if provided, otherwise uses the
      # standard #text method that all TreeHaver nodes provide.
      #
      # @param node [Object] The node (must conform to TreeHaver Node API)
      # @return [String] The text content
      def extract_content(node)
        return @content_extractor.call(node) if @content_extractor

        # TreeHaver nodes (and any node conforming to the unified API) provide #text.
        # No conditional fallbacks - nodes must conform to the API.
        node.text.to_s
      end

      # Compute similarity score between two nodes based on content.
      #
      # @param t_node [Object] Template node
      # @param d_node [Object] Destination node
      # @param t_idx [Integer] Template node index
      # @param d_idx [Integer] Destination node index
      # @param total_t [Integer] Total template nodes
      # @param total_d [Integer] Total destination nodes
      # @return [Float] Similarity score (0.0-1.0)
      def compute_content_similarity(t_node, d_node, t_idx, d_idx, total_t, total_d)
        t_content = extract_content(t_node)
        d_content = extract_content(d_node)

        # Calculate component scores
        content_score = string_similarity(t_content, d_content)
        length_score = length_similarity(t_content, d_content)
        position_score = position_similarity(t_idx, d_idx, total_t, total_d)

        # Weighted combination
        weights[:content] * content_score +
          weights[:length] * length_score +
          weights[:position] * position_score
      end

      # Calculate string similarity using Levenshtein distance.
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

      # Calculate length similarity between two strings.
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Float] Similarity score (0.0-1.0)
      def length_similarity(str1, str2)
        return 1.0 if str1.length == str2.length
        return 0.0 if str1.empty? && str2.empty?

        min_len = [str1.length, str2.length].min.to_f
        max_len = [str1.length, str2.length].max.to_f
        min_len / max_len
      end

      # Calculate position similarity in document.
      #
      # Nodes at similar relative positions score higher.
      #
      # @param idx1 [Integer] First node index
      # @param idx2 [Integer] Second node index
      # @param total1 [Integer] Total nodes in first collection
      # @param total2 [Integer] Total nodes in second collection
      # @return [Float] Similarity score (0.0-1.0)
      def position_similarity(idx1, idx2, total1, total2)
        # Normalize positions to 0.0-1.0 range
        pos1 = total1 > 1 ? idx1.to_f / (total1 - 1) : 0.5
        pos2 = total2 > 1 ? idx2.to_f / (total2 - 1) : 0.5

        1.0 - (pos1 - pos2).abs
      end

      # Calculate Levenshtein distance between two strings.
      #
      # Uses Wagner-Fischer algorithm with space optimization.
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Integer] Edit distance
      def levenshtein_distance(str1, str2)
        return str2.length if str1.empty?
        return str1.length if str2.empty?

        # Use shorter string as columns for space efficiency
        str1, str2 = str2, str1 if str1.length > str2.length

        m = str1.length
        n = str2.length

        # Only need two rows at a time
        prev_row = (0..m).to_a
        curr_row = Array.new(m + 1)

        (1..n).each do |j|
          curr_row[0] = j

          (1..m).each do |i|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
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
    end
  end
end
