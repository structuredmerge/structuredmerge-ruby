# frozen_string_literal: true

module Ast
  module Merge
    # Base class for computing match scores between two nodes.
    #
    # Match scores help determine which nodes from a template should be linked
    # to which nodes in a destination document. This is particularly useful for
    # complex nodes like tables where simple signature matching is insufficient.
    #
    # The scoring algorithm is provided as a callable object (lambda, Proc, or
    # any object responding to :call) which receives the two nodes and returns
    # a score between 0.0 (no match) and 1.0 (perfect match).
    #
    # Includes Comparable for sorting and comparison operations.
    #
    # @example Basic usage with a lambda
    #   algorithm = ->(node_a, node_b) { node_a.type == node_b.type ? 1.0 : 0.0 }
    #   scorer = MatchScoreBase.new(template_node, dest_node, algorithm: algorithm)
    #   puts scorer.score # => 1.0 if types match
    #
    # @example With a custom algorithm class
    #   class TableMatcher
    #     def call(table_a, table_b)
    #       # Complex matching logic
    #       compute_similarity(table_a, table_b)
    #     end
    #   end
    #
    #   scorer = MatchScoreBase.new(table1, table2, algorithm: TableMatcher.new)
    #
    # @example Comparing and sorting scorers
    #   scorers = [scorer1, scorer2, scorer3]
    #   best = scorers.max
    #   sorted = scorers.sort
    #
    # @api public
    class MatchScoreBase
      include Comparable

      # Minimum score threshold for considering two nodes as a potential match
      # @return [Float]
      DEFAULT_THRESHOLD = 0.5

      # @return [Object] The first node to compare (typically from template)
      attr_reader :node_a

      # @return [Object] The second node to compare (typically from destination)
      attr_reader :node_b

      # @return [#call] The algorithm used to compute the match score
      attr_reader :algorithm

      # @return [Float] The minimum score to consider a match
      attr_reader :threshold

      # Initialize a match scorer.
      #
      # @param node_a [Object] First node to compare
      # @param node_b [Object] Second node to compare
      # @param algorithm [#call] Callable that computes the score (receives node_a, node_b)
      # @param threshold [Float] Minimum score to consider a match (default: 0.5)
      # @raise [ArgumentError] If algorithm doesn't respond to :call
      def initialize(node_a, node_b, algorithm:, threshold: DEFAULT_THRESHOLD)
        raise ArgumentError, 'algorithm must respond to :call' unless algorithm.respond_to?(:call)

        @node_a = node_a
        @node_b = node_b
        @algorithm = algorithm
        @threshold = threshold
        @score = nil
      end

      # Compute and return the match score.
      #
      # The score is cached after first computation.
      #
      # @return [Float] Score between 0.0 and 1.0
      def score
        @score ||= compute_score
      end

      # Check if the score meets the threshold for a match.
      #
      # @return [Boolean] True if score >= threshold
      def match?
        score >= threshold
      end

      # Compare two scorers by their scores.
      #
      # Required by Comparable. Enables <, <=, ==, >=, >, and between? operators.
      #
      # @param other [MatchScoreBase] Another scorer to compare
      # @return [Integer] -1, 0, or 1 for comparison
      def <=>(other)
        score <=> other.score
      end

      # Generate a hash code for this scorer.
      #
      # Required for Hash key compatibility. Two scorers with the same
      # node_a, node_b, and score should have the same hash.
      #
      # @return [Integer] Hash code
      def hash
        [node_a, node_b, score].hash
      end

      # Check equality for Hash key compatibility.
      #
      # Two scorers are eql? if they have the same node_a, node_b, and score.
      # This is stricter than == from Comparable (which only compares scores).
      #
      # @param other [MatchScoreBase] Another scorer to compare
      # @return [Boolean] True if equivalent
      def eql?(other)
        return false unless other.is_a?(MatchScoreBase)

        node_a == other.node_a && node_b == other.node_b && score == other.score
      end

      private

      # Compute the score using the algorithm.
      #
      # @return [Float] Score between 0.0 and 1.0
      def compute_score
        result = algorithm.call(node_a, node_b)
        # Clamp to valid range
        result.to_f.clamp(0.0, 1.0)
      end
    end
  end
end
