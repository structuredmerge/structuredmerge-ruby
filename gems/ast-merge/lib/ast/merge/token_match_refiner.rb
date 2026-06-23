# frozen_string_literal: true

module Ast
  module Merge
    # Match refiner using Jaccard token-overlap similarity.
    #
    # Pairs unmatched nodes by extracting significant tokens from their text
    # content and computing the Jaccard similarity index. Useful for matching
    # nodes with minor wording differences (e.g., "Commit changes" vs
    # "Commit your changes").
    #
    # Uses `greedy_match` from MatchRefinerBase for optimal 1:1 pairing.
    #
    # @example Basic usage
    #   refiner = TokenMatchRefiner.new(threshold: 0.35)
    #   matches = refiner.call(template_nodes, dest_nodes)
    #
    # @example With specific node types
    #   refiner = TokenMatchRefiner.new(
    #     threshold: 0.4,
    #     node_types: [:list_item, :paragraph],
    #   )
    #
    # @example With custom text extraction
    #   refiner = TokenMatchRefiner.new(
    #     text_extractor: ->(node) { node.inner_text.strip },
    #   )
    #
    # @see MatchRefinerBase Base class with greedy matching
    # @see JaccardSimilarity Token extraction and Jaccard computation
    class TokenMatchRefiner < MatchRefinerBase
      include JaccardSimilarity

      # Default threshold for Jaccard token overlap
      DEFAULT_TOKEN_THRESHOLD = 0.35

      # @return [Proc, nil] Custom function to extract text from a node
      attr_reader :text_extractor

      # @return [Set<String>] Stopwords to exclude from token extraction
      attr_reader :stopwords

      # Initialize a token match refiner.
      #
      # @param threshold [Float] Minimum Jaccard score to accept a match (default: 0.35)
      # @param node_types [Array<Symbol>] Node types to process (empty = all)
      # @param text_extractor [Proc, nil] Custom function to extract text from a node.
      #   Should accept a node and return a String. Default uses `node.text.to_s`.
      # @param stopwords [Set<String>] Words to exclude (default: JaccardSimilarity::DEFAULT_STOPWORDS)
      # @param options [Hash] Additional options for forward compatibility
      def initialize(
        threshold: DEFAULT_TOKEN_THRESHOLD,
        node_types: [],
        text_extractor: nil,
        stopwords: JaccardSimilarity::DEFAULT_STOPWORDS,
        **_options
      )
        super(threshold: threshold, node_types: node_types)
        @text_extractor = text_extractor
        @stopwords = stopwords
      end

      # Match unmatched nodes by Jaccard token similarity.
      #
      # @param template_nodes [Array] Unmatched template nodes
      # @param dest_nodes [Array] Unmatched destination nodes
      # @param context [Hash] Additional context (unused)
      # @return [Array<MatchResult>] Matched pairs
      def call(template_nodes, dest_nodes, _context = {})
        t_filtered = node_types.empty? ? template_nodes : filter_nodes(template_nodes)
        d_filtered = node_types.empty? ? dest_nodes : filter_nodes(dest_nodes)

        greedy_match(t_filtered, d_filtered) do |t_node, d_node|
          t_tokens = node_tokens(t_node)
          d_tokens = node_tokens(d_node)
          jaccard(t_tokens, d_tokens)
        end
      end

      private

      def filter_nodes(nodes)
        nodes.select { |n| handles_type?(node_type(n)) }
      end

      def node_tokens(node)
        text = if text_extractor
                 text_extractor.call(node)
               elsif node.respond_to?(:text)
                 node.text.to_s
               else
                 ''
               end
        extract_tokens(text, stopwords: stopwords)
      end
    end
  end
end
