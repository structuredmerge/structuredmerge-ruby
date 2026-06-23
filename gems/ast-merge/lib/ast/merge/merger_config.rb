# frozen_string_literal: true

module Ast
  module Merge
    # Configuration object for SmartMerger options.
    #
    # This class encapsulates common configuration options used across all
    # *-merge gem SmartMerger implementations. It provides a standardized
    # interface for merge configuration and validates option values.
    #
    # @example Creating a config with defaults
    #   config = MergerConfig.new
    #   config.preference  # => :destination
    #   config.add_template_only_nodes     # => false
    #
    # @example Creating a config for template-wins merge
    #   config = MergerConfig.new(
    #     preference: :template,
    #     add_template_only_nodes: true
    #   )
    #
    # @example Using with SmartMerger
    #   config = MergerConfig.new(preference: :template)
    #   merger = SmartMerger.new(template, dest, **config.to_h)
    #
    # @example Per-node-type preferences with node_typing
    #   node_typing = {
    #     CallNode: ->(node) {
    #       return node unless node.name == :gem
    #       gem_name = node.arguments&.arguments&.first&.unescaped
    #       if gem_name&.start_with?("rubocop")
    #         Ast::Merge::NodeTyping.with_merge_type(node, :lint_gem)
    #       else
    #         node
    #       end
    #     }
    #   }
    #
    #   config = MergerConfig.new(
    #     node_typing: node_typing,
    #     preference: {
    #       default: :destination,
    #       lint_gem: :template  # Use template versions for lint gems
    #     }
    #   )
    class MergerConfig
      # Valid values for preference (when using Symbol)
      VALID_PREFERENCES = %i[destination template].freeze
      VALID_RESOLUTION_MODES = %i[eager unresolved].freeze

      # @return [Symbol, Hash] Which version to prefer when nodes have matching signatures.
      #   As Symbol:
      #   - :destination (default) - Keep destination version (preserves customizations)
      #   - :template - Use template version (applies updates)
      #   As Hash:
      #   - Keys are node types (Symbol) or merge_types from node_typing
      #   - Values are :destination or :template
      #   - Use :default key for fallback preference
      #   @example { default: :destination, lint_gem: :template, config_call: :template }
      attr_reader :preference

      # @return [Boolean] Whether to add nodes that only exist in template
      #   - false (default) - Skip template-only nodes
      #   - true - Add template-only nodes to result
      attr_reader :add_template_only_nodes

      # @return [String] Token used for freeze block markers
      attr_reader :freeze_token

      # @return [Proc, nil] Custom signature generator proc
      attr_reader :signature_generator

      # @return [Hash{Symbol,String => #call}, nil] Node typing configuration.
      #   Maps node type names to callable objects that can transform nodes
      #   and optionally add merge_type attributes for per-node-type preferences.
      attr_reader :node_typing

      # @return [Symbol] How merge differences should be surfaced to callers.
      attr_reader :resolution_mode
      # @return [UnresolvedPolicy] Caller-facing policy for reviewable unresolved behavior.
      attr_reader :unresolved_policy

      # Initialize a new MergerConfig.
      #
      # @param preference [Symbol, Hash] Which version to prefer on match.
      #   As Symbol: :destination or :template
      #   As Hash: Maps node types/merge_types to preferences
      #     @example { default: :destination, lint_gem: :template }
      # @param add_template_only_nodes [Boolean] Whether to add template-only nodes
      # @param freeze_token [String, nil] Token for freeze block markers (nil uses gem default)
      # @param signature_generator [Proc, nil] Custom signature generator
      # @param node_typing [Hash{Symbol,String => #call}, nil] Node typing configuration
      #
      # @raise [ArgumentError] If preference is invalid
      # @raise [ArgumentError] If node_typing is invalid
      def initialize(
        preference: :destination,
        add_template_only_nodes: false,
        freeze_token: nil,
        signature_generator: nil,
        node_typing: nil,
        resolution_mode: :eager,
        unresolved_policy: nil
      )
        validate_preference!(preference)
        validate_resolution_mode!(resolution_mode)
        NodeTyping.validate!(node_typing) if node_typing

        @preference = preference
        @add_template_only_nodes = add_template_only_nodes
        @freeze_token = freeze_token
        @signature_generator = signature_generator
        @node_typing = node_typing
        @resolution_mode = resolution_mode
        @unresolved_policy = normalize_unresolved_policy(unresolved_policy)
      end

      # Check if destination version should be preferred on signature match.
      # For Hash preferences, checks the :default key.
      #
      # @return [Boolean] true if destination preference
      def prefer_destination?
        if @preference.is_a?(Hash)
          @preference.fetch(:default, :destination) == :destination
        else
          @preference == :destination
        end
      end

      # Check if template version should be preferred on signature match.
      # For Hash preferences, checks the :default key.
      #
      # @return [Boolean] true if template preference
      def prefer_template?
        if @preference.is_a?(Hash)
          @preference.fetch(:default, :destination) == :template
        else
          @preference == :template
        end
      end

      # Get the preference for a specific node type or merge_type.
      #
      # When preference is a Hash, looks up the preference
      # for the given type, falling back to :default, then to :destination.
      #
      # @param type [Symbol, nil] The node type or merge_type to look up
      # @return [Symbol] :destination or :template
      #
      # @example With Symbol preference
      #   config = MergerConfig.new(preference: :template)
      #   config.preference_for(:any_type)  # => :template
      #
      # @example With Hash preference
      #   config = MergerConfig.new(
      #     preference: { default: :destination, lint_gem: :template }
      #   )
      #   config.preference_for(:lint_gem)   # => :template
      #   config.preference_for(:other_type) # => :destination
      def preference_for(type)
        if @preference.is_a?(Hash)
          @preference.fetch(type) do
            @preference.fetch(:default, :destination)
          end
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

      def eager_resolution?
        @resolution_mode == :eager
      end

      def unresolved_resolution?
        @resolution_mode == :unresolved
      end

      def unresolved_for?(kind)
        unresolved_resolution? && unresolved_policy.unresolved_for?(kind)
      end

      def provisional_unresolved_winner_for(kind, fallback: nil)
        unresolved_policy.provisional_winner_for(kind, fallback: fallback)
      end

      # Convert config to a hash suitable for passing to SmartMerger.
      #
      # @param default_freeze_token [String, nil] Default freeze token to use if none specified
      # @return [Hash] Configuration as keyword arguments hash
      # @note Uses :preference key to match SmartMerger's API (not :preference)
      def to_h(default_freeze_token: nil)
        result = {
          preference: @preference,
          add_template_only_nodes: @add_template_only_nodes,
          resolution_mode: @resolution_mode,
          unresolved_policy: @unresolved_policy.to_h
        }
        result[:freeze_token] = @freeze_token || default_freeze_token if @freeze_token || default_freeze_token
        result[:signature_generator] = @signature_generator if @signature_generator
        result[:node_typing] = @node_typing if @node_typing
        result
      end

      # Create a new config with updated values.
      #
      # @param options [Hash] Options to override
      # @return [MergerConfig] New config with updated values
      def with(**options)
        self.class.new(
          preference: options.fetch(:preference, @preference),
          add_template_only_nodes: options.fetch(:add_template_only_nodes, @add_template_only_nodes),
          freeze_token: options.fetch(:freeze_token, @freeze_token),
          signature_generator: options.fetch(:signature_generator, @signature_generator),
          node_typing: options.fetch(:node_typing, @node_typing),
          resolution_mode: options.fetch(:resolution_mode, @resolution_mode),
          unresolved_policy: options.fetch(:unresolved_policy, @unresolved_policy)
        )
      end

      class << self
        # Create a config preset for "destination wins" merging.
        # Destination customizations are preserved, template-only content is skipped.
        #
        # @param freeze_token [String, nil] Optional freeze token
        # @param signature_generator [Proc, nil] Optional signature generator
        # @param node_typing [Hash, nil] Optional node typing configuration
        # @return [MergerConfig] Config preset
        def destination_wins(freeze_token: nil, signature_generator: nil, node_typing: nil, resolution_mode: :eager,
                             unresolved_policy: nil)
          new(
            preference: :destination,
            add_template_only_nodes: false,
            freeze_token: freeze_token,
            signature_generator: signature_generator,
            node_typing: node_typing,
            resolution_mode: resolution_mode,
            unresolved_policy: unresolved_policy
          )
        end

        # Create a config preset for "template wins" merging.
        # Template updates are applied, template-only content is added.
        #
        # @param freeze_token [String, nil] Optional freeze token
        # @param signature_generator [Proc, nil] Optional signature generator
        # @param node_typing [Hash, nil] Optional node typing configuration
        # @return [MergerConfig] Config preset
        def template_wins(freeze_token: nil, signature_generator: nil, node_typing: nil, resolution_mode: :eager,
                          unresolved_policy: nil)
          new(
            preference: :template,
            add_template_only_nodes: true,
            freeze_token: freeze_token,
            signature_generator: signature_generator,
            node_typing: node_typing,
            resolution_mode: resolution_mode,
            unresolved_policy: unresolved_policy
          )
        end
      end

      private

      def validate_preference!(preference)
        if preference.is_a?(Hash)
          validate_hash_preference!(preference)
        elsif !VALID_PREFERENCES.include?(preference)
          raise ArgumentError,
                "Invalid preference: #{preference.inspect}. " \
                  "Must be one of: #{VALID_PREFERENCES.map(&:inspect).join(', ')} or a Hash"
        end
      end

      def validate_hash_preference!(preference)
        preference.each do |key, value|
          unless key.is_a?(Symbol)
            raise ArgumentError,
                  "preference Hash keys must be Symbols, got #{key.class} for #{key.inspect}"
          end

          next if VALID_PREFERENCES.include?(value)

          raise ArgumentError,
                'preference Hash values must be :destination or :template, ' \
                  "got #{value.inspect} for key #{key.inspect}"
        end
      end

      def validate_resolution_mode!(resolution_mode)
        return if VALID_RESOLUTION_MODES.include?(resolution_mode)

        raise ArgumentError,
              "Invalid resolution_mode: #{resolution_mode.inspect}. " \
                "Must be one of: #{VALID_RESOLUTION_MODES.map(&:inspect).join(', ')}"
      end

      def normalize_unresolved_policy(unresolved_policy)
        UnresolvedPolicy.coerce(unresolved_policy)
      end
    end
  end
end
