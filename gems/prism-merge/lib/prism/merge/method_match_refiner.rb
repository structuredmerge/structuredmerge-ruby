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
      DEFAULT_NAME_WEIGHT = Ruby::Merge::MethodSimilarity::DEFAULT_NAME_WEIGHT

      # Default weight for parameter similarity
      DEFAULT_PARAMS_WEIGHT = Ruby::Merge::MethodSimilarity::DEFAULT_PARAMS_WEIGHT

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
        @method_similarity = Ruby::Merge::MethodSimilarity.new(
          name_weight: name_weight,
          params_weight: params_weight
        )
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
        @method_similarity.call(
          template_name: t_method.name,
          template_params: extract_param_names(t_method),
          dest_name: d_method.name,
          dest_params: extract_param_names(d_method)
        )
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

    end
  end
end
