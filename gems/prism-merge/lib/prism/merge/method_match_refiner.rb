# frozen_string_literal: true

module Prism
  module Merge
    # Match refiner for Ruby methods that didn't match by exact signature.
    #
    # This refiner uses fuzzy matching to pair methods that have:
    # - Similar names (e.g., `process_user` vs `process_users`)
    # - Same name but different parameter signatures
    # - Renamed methods that perform similar functions
    #
    # The matching algorithm considers:
    # - Method name similarity (Levenshtein distance)
    # - Parameter count and name similarity
    # - Method body similarity (optional, for high-confidence matches)
    #
    # @example Basic usage
    #   refiner = MethodMatchRefiner.new(threshold: 0.6)
    #   matches = refiner.call(template_nodes, dest_nodes)
    #
    # @example With custom weights
    #   refiner = MethodMatchRefiner.new(
    #     threshold: 0.5,
    #     name_weight: 0.6,
    #     params_weight: 0.4
    #   )
    #
    # @see Ast::Merge::MatchRefinerBase
    class MethodMatchRefiner < Ast::Merge::MatchRefinerBase
      # Default weight for method name similarity
      DEFAULT_NAME_WEIGHT = 0.7

      # Default weight for parameter similarity
      DEFAULT_PARAMS_WEIGHT = 0.3

      # @return [Float] Weight for name similarity (0.0-1.0)
      attr_reader :name_weight

      # @return [Float] Weight for parameter similarity (0.0-1.0)
      attr_reader :params_weight

      # Initialize a method match refiner.
      #
      # @param threshold [Float] Minimum score to accept a match (default: 0.5)
      # @param name_weight [Float] Weight for name similarity (default: 0.7)
      # @param params_weight [Float] Weight for parameter similarity (default: 0.3)
      def initialize(threshold: DEFAULT_THRESHOLD, name_weight: DEFAULT_NAME_WEIGHT,
                     params_weight: DEFAULT_PARAMS_WEIGHT, **options)
        super(threshold: threshold, node_types: [:def], **options)
        @name_weight = name_weight
        @params_weight = params_weight
      end

      # Find matches between unmatched method definitions.
      #
      # @param template_nodes [Array] Unmatched nodes from template
      # @param dest_nodes [Array] Unmatched nodes from destination
      # @param context [Hash] Additional context
      # @return [Array<MatchResult>] Array of method matches
      def call(template_nodes, dest_nodes, _context = {})
        template_methods = template_nodes.select { |n| method_node?(n) }
        dest_methods = dest_nodes.select { |n| method_node?(n) }

        return [] if template_methods.empty? || dest_methods.empty?

        greedy_match(template_methods, dest_methods) do |t_node, d_node|
          compute_method_similarity(t_node, d_node)
        end
      end

      private

      # Check if a node is a method definition.
      #
      # @param node [Object] Node to check
      # @return [Boolean]
      def method_node?(node)
        NodeTypeNormalizer.canonical_type(node.type.to_s, :prism) == :def
      end

      # Compute similarity score between two methods.
      #
      # @param t_method [Prism::DefNode] Template method
      # @param d_method [Prism::DefNode] Destination method
      # @return [Float] Similarity score (0.0-1.0)
      def compute_method_similarity(t_method, d_method)
        name_score = string_similarity(t_method.name.to_s, d_method.name.to_s)
        param_score = param_similarity(t_method, d_method)

        (name_score * name_weight) + (param_score * params_weight)
      end

      # Compute similarity between method parameters.
      #
      # @param t_method [Prism::DefNode] Template method
      # @param d_method [Prism::DefNode] Destination method
      # @return [Float] Parameter similarity (0.0-1.0)
      def param_similarity(t_method, d_method)
        t_params = extract_param_names(t_method)
        d_params = extract_param_names(d_method)

        return 1.0 if t_params.empty? && d_params.empty?
        return 0.0 if t_params.empty? || d_params.empty?

        # Count matching parameter names
        common = (t_params & d_params).size
        total = [t_params.size, d_params.size].max

        # Also consider parameter count similarity
        count_ratio = [t_params.size, d_params.size].min.to_f / total

        # Combine name matching and count similarity
        name_match_ratio = common.to_f / total
        (name_match_ratio * 0.7) + (count_ratio * 0.3)
      end

      # Extract parameter names from a method definition.
      #
      # @param method_node [Prism::DefNode] Method node
      # @return [Array<Symbol>] Parameter names
      def extract_param_names(method_node)
        return [] unless method_node.parameters

        params = method_node.parameters
        names = []

        names.concat(params.requireds.map(&:name)) if params.requireds
        names.concat(params.optionals.map(&:name)) if params.optionals
        names << params.rest.name if params.rest&.respond_to?(:name) && params.rest.name
        names.concat(params.posts.map(&:name)) if params.posts
        names.concat(params.keywords.map(&:name)) if params.keywords
        names << params.keyword_rest.name if params.keyword_rest&.respond_to?(:name) && params.keyword_rest.name
        names << params.block.name if params.block

        names.compact
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
