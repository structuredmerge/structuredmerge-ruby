# frozen_string_literal: true

require_relative 'unresolved_support'

module Ast
  module Merge
    # Base class for conflict resolvers across all *-merge gems.
    #
    # Provides common functionality for resolving conflicts between template
    # and destination content during merge operations. Supports three resolution
    # strategies that can be selected based on the needs of each file format:
    #
    # - `:node` - Per-node resolution (resolve individual node pairs)
    # - `:batch` - Batch resolution (resolve entire file using signature maps)
    # - `:boundary` - Boundary resolution (resolve sections/ranges of content)
    #
    # @example Node-based resolution (commonmarker-merge style)
    #   class ConflictResolver < Ast::Merge::ConflictResolverBase
    #     def initialize(preference:, template_analysis:, dest_analysis:)
    #       super(
    #         strategy: :node,
    #         preference: preference,
    #         template_analysis: template_analysis,
    #         dest_analysis: dest_analysis
    #       )
    #     end
    #
    #     # Called for each node pair
    #     def resolve_node_pair(template_node, dest_node, template_index:, dest_index:)
    #       # Return resolution hash
    #     end
    #   end
    #
    # @example Batch resolution (psych-merge/json-merge style)
    #   class ConflictResolver < Ast::Merge::ConflictResolverBase
    #     def initialize(template_analysis, dest_analysis, preference: :destination)
    #       super(
    #         strategy: :batch,
    #         preference: preference,
    #         template_analysis: template_analysis,
    #         dest_analysis: dest_analysis
    #       )
    #     end
    #
    #     # Called once for entire merge
    #     def resolve_batch(result)
    #       # Populate result with merged content
    #     end
    #   end
    #
    # @example Boundary resolution (prism-merge style)
    #   class ConflictResolver < Ast::Merge::ConflictResolverBase
    #     def initialize(template_analysis, dest_analysis, preference: :destination)
    #       super(
    #         strategy: :boundary,
    #         preference: preference,
    #         template_analysis: template_analysis,
    #         dest_analysis: dest_analysis
    #       )
    #     end
    #
    #     # Called for each boundary (section with differences)
    #     def resolve_boundary(boundary, result)
    #       # Process boundary and populate result
    #     end
    #   end
    #
    # @abstract Subclass and implement resolve_node_pair, resolve_batch, or resolve_boundary
    class ConflictResolverBase
      include UnresolvedSupport

      # Decision constants - shared across all conflict resolvers

      # Use destination version (customization preserved)
      DECISION_DESTINATION = :destination

      # Use template version (update applied)
      DECISION_TEMPLATE = :template

      # Content was added from template (template-only)
      DECISION_ADDED = :added

      # Content preserved from frozen block
      DECISION_FROZEN = :frozen

      # Content was identical (no conflict)
      DECISION_IDENTICAL = :identical

      # Content was kept from destination (signature match, dest preferred)
      DECISION_KEPT_DEST = :kept_destination

      # Content was kept from template (signature match, template preferred)
      DECISION_KEPT_TEMPLATE = :kept_template

      # Content was appended from destination (dest-only)
      DECISION_APPENDED = :appended

      # Content preserved from freeze block marker
      DECISION_FREEZE_BLOCK = :freeze_block

      # Content requires recursive merge (container types)
      DECISION_RECURSIVE = :recursive

      # Content was replaced (signature match with different content)
      DECISION_REPLACED = :replaced

      # @return [Symbol] Resolution strategy (:node, :batch, or :boundary)
      attr_reader :strategy

      # @return [Symbol, Hash] Merge preference.
      #   As Symbol: :destination or :template (applies to all nodes)
      #   As Hash: Maps node types/merge_types to preferences
      #     @example { default: :destination, lint_gem: :template }
      attr_reader :preference

      # @return [Object] Template file analysis
      attr_reader :template_analysis

      # @return [Object] Destination file analysis
      attr_reader :dest_analysis

      # @return [Boolean] Whether to add template-only nodes (batch strategy)
      attr_reader :add_template_only_nodes

      # @return [Boolean] Whether to remove destination nodes not in template (batch strategy)
      attr_reader :remove_template_missing_nodes

      # @return [Boolean, Integer] Whether to merge nested structures recursively
      #   - true: unlimited depth (default)
      #   - false: disabled
      #   - Integer > 0: max depth
      attr_reader :recursive

      # @return [Object, nil] Match refiner for fuzzy matching
      attr_reader :match_refiner

      # Initialize the conflict resolver
      #
      # @param strategy [Symbol] Resolution strategy (:node, :batch, or :boundary)
      # @param preference [Symbol, Hash] Which version to prefer.
      #   As Symbol: :destination or :template (applies to all nodes)
      #   As Hash: Maps node types/merge_types to preferences
      #     - Use :default key for fallback preference
      #     @example { default: :destination, lint_gem: :template }
      # @param template_analysis [Object] Analysis of the template file
      # @param dest_analysis [Object] Analysis of the destination file
      # @param add_template_only_nodes [Boolean] Whether to add nodes only in template (batch/boundary strategy)
      # @param remove_template_missing_nodes [Boolean] Whether to remove destination nodes not in template
      # @param recursive [Boolean, Integer] Whether to merge nested structures recursively
      #   - true: unlimited depth (default)
      #   - false: disabled
      #   - Integer > 0: max depth
      #   - 0: invalid, raises ArgumentError
      # @param match_refiner [#call, nil] Optional match refiner for fuzzy matching
      # @param options [Hash] Additional options for forward compatibility
      def initialize(strategy:, preference:, template_analysis:, dest_analysis:, add_template_only_nodes: false,
                     remove_template_missing_nodes: false, recursive: true, match_refiner: nil, **_options)
        unless %i[node batch boundary].include?(strategy)
          raise ArgumentError, "Invalid strategy: #{strategy}. Must be :node, :batch, or :boundary"
        end

        validate_preference!(preference)
        validate_recursive!(recursive)

        @strategy = strategy
        @preference = preference
        @template_analysis = template_analysis
        @dest_analysis = dest_analysis
        @add_template_only_nodes = add_template_only_nodes
        @remove_template_missing_nodes = remove_template_missing_nodes
        @recursive = recursive
        @match_refiner = match_refiner
        # **options captured for forward compatibility - subclasses may use additional options
      end

      # Resolve conflicts using the configured strategy
      #
      # For :node strategy, this delegates to resolve_node_pair
      # For :batch strategy, this delegates to resolve_batch
      # For :boundary strategy, this delegates to resolve_boundary
      #
      # @param args [Array] Arguments passed to the strategy method
      # @return [Object] Resolution result (format depends on strategy)
      def resolve(*args, **kwargs)
        case @strategy
        when :node
          resolve_node_pair(*args, **kwargs)
        when :batch
          resolve_batch(*args)
        when :boundary
          resolve_boundary(*args)
        end
      end

      # Check if a node is a freeze node using duck typing
      #
      # @param node [Object] Node to check
      # @return [Boolean] True if node is a freeze node
      def freeze_node?(node)
        node.respond_to?(:freeze_node?) && node.freeze_node?
      end

      # Get the preference for a specific node.
      #
      # When preference is a Hash, looks up the preference for the node's
      # merge_type (if wrapped with NodeTyping) or falls back to :default.
      #
      # @param node [Object, nil] The node to get preference for
      # @return [Symbol] :destination or :template
      #
      # @example With Symbol preference
      #   preference_for_node(any_node)  # => returns @preference
      #
      # @example With Hash preference and typed node
      #   # Given preference: { default: :destination, lint_gem: :template }
      #   preference_for_node(lint_gem_node)  # => :template
      #   preference_for_node(other_node)     # => :destination
      def preference_for_node(node)
        return default_preference unless @preference.is_a?(Hash)
        return default_preference unless node

        # Check if node has a merge_type (from NodeTyping)
        merge_type = NodeTyping.merge_type_for(node)
        return @preference.fetch(merge_type) { default_preference } if merge_type

        # Fall back to default
        default_preference
      end

      # Get the default preference (used as fallback).
      #
      # @return [Symbol] :destination or :template
      def default_preference
        if @preference.is_a?(Hash)
          @preference.fetch(:default, :destination)
        else
          @preference
        end
      end

      # Check if Hash-based per-type preferences are configured.
      #
      # @return [Boolean] true if preference is a Hash
      def per_type_preference?
        @preference.is_a?(Hash)
      end

      protected

      # Resolve a single node pair (for :node strategy)
      # Override this method in subclasses using node strategy
      #
      # @param template_node [Object] Node from template
      # @param dest_node [Object] Node from destination
      # @param template_index [Integer] Index in template statements
      # @param dest_index [Integer] Index in destination statements
      # @return [Hash] Resolution with :source, :decision, and node references
      def resolve_node_pair(template_node, dest_node, template_index:, dest_index:)
        raise NotImplementedError, 'Subclass must implement resolve_node_pair for :node strategy'
      end

      # Resolve all conflicts in batch (for :batch strategy)
      # Override this method in subclasses using batch strategy
      #
      # @param result [Object] Result object to populate
      # @return [void]
      def resolve_batch(result)
        raise NotImplementedError, 'Subclass must implement resolve_batch for :batch strategy'
      end

      # Resolve a boundary/section (for :boundary strategy)
      # Override this method in subclasses using boundary strategy
      #
      # Boundaries represent sections of content where template and destination
      # differ. This strategy is useful for ASTs where content is processed
      # in ranges/sections rather than individual nodes or all at once.
      #
      # @param boundary [Object] Boundary object with template_range and dest_range
      # @param result [Object] Result object to populate
      # @return [void]
      def resolve_boundary(boundary, result)
        raise NotImplementedError, 'Subclass must implement resolve_boundary for :boundary strategy'
      end

      # Build a signature map from nodes
      # Useful for batch resolution strategy
      #
      # @param nodes [Array] Nodes to map
      # @param analysis [Object] Analysis for signature generation
      # @return [Hash] Map of signature => [{node:, index:}, ...]
      def build_signature_map(nodes, analysis)
        map = {}
        nodes.each_with_index do |node, idx|
          sig = analysis.generate_signature(node)
          next unless sig

          map[sig] ||= []
          map[sig] << { node: node, index: idx }
        end
        map
      end

      # Build a signature map from node_info hashes
      # Useful for boundary resolution strategy where nodes are wrapped in info hashes
      #
      # @param node_infos [Array<Hash>] Node info hashes with :signature and :index keys
      # @return [Hash] Map of signature => [node_info, ...]
      def build_signature_map_from_infos(node_infos)
        map = Hash.new { |h, k| h[k] = [] }
        node_infos.each do |node_info|
          sig = node_info[:signature]
          map[sig] << node_info if sig
        end
        map
      end

      # Check if two line ranges overlap
      #
      # @param range1 [Range] First range
      # @param range2 [Range] Second range
      # @return [Boolean] True if ranges overlap
      def ranges_overlap?(range1, range2)
        range1.begin <= range2.end && range2.begin <= range1.end
      end

      # Create a resolution hash for frozen block
      #
      # @param source [Symbol] :template or :destination
      # @param template_node [Object] Template node
      # @param dest_node [Object] Destination node
      # @param reason [String, nil] Freeze reason
      # @return [Hash] Resolution hash
      def frozen_resolution(source:, template_node:, dest_node:, reason: nil)
        {
          source: source,
          decision: DECISION_FROZEN,
          template_node: template_node,
          dest_node: dest_node,
          reason: reason
        }
      end

      # Create a resolution hash for identical content
      #
      # @param template_node [Object] Template node
      # @param dest_node [Object] Destination node
      # @return [Hash] Resolution hash
      def identical_resolution(template_node:, dest_node:)
        {
          source: :destination,
          decision: DECISION_IDENTICAL,
          template_node: template_node,
          dest_node: dest_node
        }
      end

      # Create a resolution hash based on preference.
      # Supports per-node-type preferences when a Hash is configured.
      #
      # When per-type preferences are configured, checks template_node for
      # merge_type (from NodeTyping wrapping). If template_node has no merge_type,
      # falls back to dest_node's merge_type, then to the default preference.
      #
      # @param template_node [Object] Template node (may be a Wrapper)
      # @param dest_node [Object] Destination node (may be a Wrapper)
      # @return [Hash] Resolution hash
      def preference_resolution(template_node:, dest_node:)
        # Get the appropriate preference for this node pair
        # Template node's merge_type takes precedence, then dest_node's
        node_preference = if NodeTyping.typed_node?(template_node)
                            preference_for_node(template_node)
                          elsif NodeTyping.typed_node?(dest_node)
                            preference_for_node(dest_node)
                          else
                            default_preference
                          end

        if node_preference == :template
          {
            source: :template,
            decision: DECISION_TEMPLATE,
            template_node: template_node,
            dest_node: dest_node
          }
        else
          {
            source: :destination,
            decision: DECISION_DESTINATION,
            template_node: template_node,
            dest_node: dest_node
          }
        end
      end

      private

      # Validate the preference parameter.
      #
      # @param preference [Symbol, Hash] The preference to validate
      # @raise [ArgumentError] If preference is invalid
      def validate_preference!(preference)
        if preference.is_a?(Hash)
          validate_hash_preference!(preference)
        elsif !%i[destination template].include?(preference)
          raise ArgumentError, "Invalid preference: #{preference}. Must be :destination, :template, or a Hash"
        end
      end

      # Validate a Hash preference configuration.
      #
      # @param preference [Hash] The preference hash to validate
      # @raise [ArgumentError] If any key or value is invalid
      def validate_hash_preference!(preference)
        preference.each do |key, value|
          unless key.is_a?(Symbol)
            raise ArgumentError,
                  "preference Hash keys must be Symbols, got #{key.class} for #{key.inspect}"
          end

          next if %i[destination template].include?(value)

          raise ArgumentError,
                'preference Hash values must be :destination or :template, ' \
                  "got #{value.inspect} for key #{key.inspect}"
        end
      end

      # Validate the recursive parameter.
      #
      # @param recursive [Boolean, Integer] The recursive value to validate
      # @raise [ArgumentError] If recursive is invalid
      def validate_recursive!(recursive)
        return if [true, false].include?(recursive)
        return if recursive.is_a?(Integer) && recursive > 0

        raise ArgumentError, 'recursive: 0 is invalid, use false to disable recursive merging' if recursive == 0

        raise ArgumentError,
              "Invalid recursive: #{recursive.inspect}. Must be true, false, or a positive Integer"
      end

      # Check if recursive merging should be applied at a given depth.
      #
      # @param current_depth [Integer] Current recursion depth (0 = root level)
      # @return [Boolean] Whether to continue recursive merging
      def should_recurse?(current_depth)
        return false if @recursive == false
        return true if @recursive == true

        # @recursive is a positive Integer representing max depth
        current_depth < @recursive
      end
    end
  end
end
