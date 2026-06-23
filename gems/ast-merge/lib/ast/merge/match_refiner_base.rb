# frozen_string_literal: true

module Ast
  module Merge
    # Base class for match refiners that pair unmatched nodes after signature matching.
    #
    # Match refiners run after initial signature-based matching to find additional
    # pairings between nodes that didn't match by signature. This is useful when
    # you want more nuanced matching than exact signatures provide - for example,
    # matching tables with similar (but not identical) headers, or finding the
    # closest match among several candidates using multi-factor scoring.
    #
    # By default, most node types use content-based signatures (including tables,
    # which match on row count + header content). Refiners let you override this
    # to implement fuzzy matching, positional matching, or any custom logic.
    #
    # Refiners use a callable interface (`#call`) so simple lambdas/procs can
    # also be used where a full class isn't needed.
    #
    # @example Markdown: Table matching with multi-factor scoring
    #   # Tables may have similar but not identical headers
    #   # See Commonmarker::Merge::TableMatchRefiner
    #   class TableMatchRefiner < Ast::Merge::MatchRefinerBase
    #     def initialize(algorithm: nil, **options)
    #       super(**options)
    #       @algorithm = algorithm || TableMatchAlgorithm.new
    #     end
    #
    #     def call(template_nodes, dest_nodes, context = {})
    #       template_tables = filter_by_type(template_nodes, :table)
    #       dest_tables = filter_by_type(dest_nodes, :table)
    #
    #       greedy_match(template_tables, dest_tables) do |t_node, d_node|
    #         @algorithm.call(t_node, d_node)
    #       end
    #     end
    #   end
    #
    # @example Ruby: Method matching with fuzzy name/signature scoring
    #   # Methods may have similar names (process_user vs process_users)
    #   # or same name with different parameters
    #   # See Prism::Merge::MethodMatchRefiner
    #   class MethodMatchRefiner < Ast::Merge::MatchRefinerBase
    #     def call(template_nodes, dest_nodes, context = {})
    #       template_methods = template_nodes.select { |n| n.is_a?(Prism::DefNode) }
    #       dest_methods = dest_nodes.select { |n| n.is_a?(Prism::DefNode) }
    #
    #       greedy_match(template_methods, dest_methods) do |t_node, d_node|
    #         compute_method_similarity(t_node, d_node)
    #       end
    #     end
    #
    #     private
    #
    #     def compute_method_similarity(t_method, d_method)
    #       name_score = string_similarity(t_method.name.to_s, d_method.name.to_s)
    #       param_score = param_similarity(t_method, d_method)
    #       name_score * 0.7 + param_score * 0.3
    #     end
    #   end
    #
    # @example YAML: Mapping key matching with fuzzy scoring
    #   # YAML keys may be renamed or have typos
    #   # See Psych::Merge::MappingMatchRefiner
    #   class MappingMatchRefiner < Ast::Merge::MatchRefinerBase
    #     def call(template_nodes, dest_nodes, context = {})
    #       template_mappings = template_nodes.select { |n| n.respond_to?(:key) }
    #       dest_mappings = dest_nodes.select { |n| n.respond_to?(:key) }
    #
    #       greedy_match(template_mappings, dest_mappings) do |t_node, d_node|
    #         key_similarity(t_node.key, d_node.key)
    #       end
    #     end
    #   end
    #
    # @example JSON: Object property matching for arrays of objects
    #   # JSON arrays may contain objects that should match by content
    #   # See Json::Merge::ObjectMatchRefiner
    #   class ObjectMatchRefiner < Ast::Merge::MatchRefinerBase
    #     def call(template_nodes, dest_nodes, context = {})
    #       template_objects = template_nodes.select { |n| n.type == :object }
    #       dest_objects = dest_nodes.select { |n| n.type == :object }
    #
    #       greedy_match(template_objects, dest_objects) do |t_node, d_node|
    #         compute_object_similarity(t_node, d_node)
    #       end
    #     end
    #   end
    #
    # @example Using find_best_match with manual tracking (alternative approach)
    #   class TableMatchRefiner < Ast::Merge::MatchRefinerBase
    #     def call(template_nodes, dest_nodes, context = {})
    #       matches = []
    #       used_dest_nodes = Set.new
    #       template_tables = filter_by_type(template_nodes, :table)
    #       dest_tables = filter_by_type(dest_nodes, :table)
    #
    #       template_tables.each do |t_node|
    #         best = find_best_match(t_node, dest_tables, used_dest_nodes: used_dest_nodes) do |t, d|
    #           compute_table_score(t, d)
    #         end
    #         if best
    #           matches << best
    #           used_dest_nodes << best.dest_node
    #         end
    #       end
    #
    #       matches
    #     end
    #   end
    #
    # @example Using a simple lambda refiner
    #   simple_refiner = ->(template, dest, ctx) do
    #     # Return array of MatchResult objects
    #     []
    #   end
    #
    # @example Using refiners with a merger
    #   merger = SmartMerger.new(
    #     template,
    #     destination,
    #     match_refiners: [
    #       TableMatchRefiner.new(threshold: 0.6),
    #       CustomRefiner.new
    #     ]
    #   )
    #
    # @api public
    class MatchRefinerBase
      # Result of a match refinement operation.
      #
      # @!attribute [r] template_node
      #   @return [Object] The node from the template
      # @!attribute [r] dest_node
      #   @return [Object] The node from the destination
      # @!attribute [r] score
      #   @return [Float] Match score between 0.0 and 1.0
      # @!attribute [r] metadata
      #   @return [Hash] Optional metadata about the match
      MatchResult = Struct.new(:template_node, :dest_node, :score, :metadata, keyword_init: true) do
        # Check if this is a high-confidence match.
        #
        # @param threshold [Float] Minimum score for high confidence (default: 0.8)
        # @return [Boolean]
        def high_confidence?(threshold: 0.8)
          score >= threshold
        end

        # Compare match results by score for sorting.
        #
        # @param other [MatchResult]
        # @return [Integer] -1, 0, or 1
        def <=>(other)
          score <=> other.score
        end
      end

      # Default minimum score threshold for accepting a match
      DEFAULT_THRESHOLD = 0.5

      # @return [Float] Minimum score to accept a match
      attr_reader :threshold

      # @return [Array<Symbol>] Node types this refiner handles (empty = all types)
      attr_reader :node_types

      # Initialize a new match refiner.
      #
      # @param threshold [Float] Minimum score to accept a match (0.0-1.0)
      # @param node_types [Array<Symbol>] Node types to process (empty = all)
      def initialize(threshold: DEFAULT_THRESHOLD, node_types: [])
        @threshold = threshold.to_f.clamp(0.0, 1.0)
        @node_types = Array(node_types)
      end

      # Refine matches between unmatched template and destination nodes.
      #
      # This is the main entry point. Override in subclasses to implement
      # custom matching logic.
      #
      # @param template_nodes [Array] Unmatched nodes from template
      # @param dest_nodes [Array] Unmatched nodes from destination
      # @param context [Hash] Additional context (e.g., file analyses)
      # @return [Array<MatchResult>] Array of match results
      # @raise [NotImplementedError] If not overridden in subclass
      def call(template_nodes, dest_nodes, context = {})
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      # Check if this refiner handles a given node type.
      #
      # @param node_type [Symbol] The node type to check
      # @return [Boolean] True if this refiner handles the type
      def handles_type?(node_type)
        node_types.empty? || node_types.include?(node_type)
      end

      protected

      # Filter nodes by type.
      #
      # @param nodes [Array] Nodes to filter
      # @param type [Symbol] Node type to select
      # @return [Array] Filtered nodes
      def filter_by_type(nodes, type)
        nodes.select { |n| node_type(n) == type }
      end

      # Get the type of a node.
      #
      # Override in subclasses for parser-specific type extraction.
      #
      # @param node [Object] The node
      # @return [Symbol, nil] The node type
      def node_type(node)
        if node.respond_to?(:type)
          node.type
        elsif node.respond_to?(:class)
          node.class.name.split('::').last.to_sym
        end
      end

      # Create a match result.
      #
      # @param template_node [Object] Template node
      # @param dest_node [Object] Destination node
      # @param score [Float] Match score
      # @param metadata [Hash] Optional metadata
      # @return [MatchResult]
      def match_result(template_node, dest_node, score, metadata = {})
        MatchResult.new(
          template_node: template_node,
          dest_node: dest_node,
          score: score,
          metadata: metadata
        )
      end

      # Find the best matching destination node for a template node.
      #
      # Uses a scoring algorithm to find the best match above the threshold.
      #
      # @param template_node [Object] The template node to match
      # @param dest_nodes [Array] Candidate destination nodes
      # @param used_dest_nodes [Set] Already-matched destination nodes to skip
      # @yield [template_node, dest_node] Block that returns a score (0.0-1.0)
      # @return [MatchResult, nil] Best match or nil if none above threshold
      def find_best_match(template_node, dest_nodes, used_dest_nodes: Set.new)
        best_match = nil
        best_score = threshold

        dest_nodes.each do |dest_node|
          next if used_dest_nodes.include?(dest_node)

          score = yield(template_node, dest_node)
          next unless score && score > best_score

          best_score = score
          best_match = dest_node
        end

        return unless best_match

        match_result(template_node, best_match, best_score)
      end

      # Perform greedy matching between template and destination nodes.
      #
      # Matches are made greedily by score, with each node matched at most once.
      #
      # @param template_nodes [Array] Template nodes to match
      # @param dest_nodes [Array] Destination nodes to match against
      # @yield [template_node, dest_node] Block that returns a score (0.0-1.0)
      # @return [Array<MatchResult>] Array of matches
      def greedy_match(template_nodes, dest_nodes)
        matches = []
        used_dest_nodes = Set.new

        # Collect all potential matches with scores
        candidates = []
        template_nodes.each do |t_node|
          dest_nodes.each do |d_node|
            score = yield(t_node, d_node)
            next unless score && score >= threshold

            candidates << { template: t_node, dest: d_node, score: score }
          end
        end

        # Sort by score descending
        candidates.sort_by! { |c| -c[:score] }

        # Greedily assign matches
        used_template_nodes = Set.new
        candidates.each do |candidate|
          next if used_template_nodes.include?(candidate[:template])
          next if used_dest_nodes.include?(candidate[:dest])

          matches << match_result(
            candidate[:template],
            candidate[:dest],
            candidate[:score]
          )
          used_template_nodes << candidate[:template]
          used_dest_nodes << candidate[:dest]
        end

        matches
      end
    end
  end
end
