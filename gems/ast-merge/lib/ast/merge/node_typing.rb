# frozen_string_literal: true

module Ast
  module Merge
    # Provides node type wrapping support for SmartMerger implementations.
    #
    # NodeTyping allows custom callable objects to be associated with specific
    # node types. When a node is processed, the corresponding callable can:
    # - Return the node unchanged (passthrough)
    # - Return a modified node with a custom `merge_type` attribute
    # - Return nil to indicate the node should be skipped
    #
    # The `merge_type` attribute can then be used by other merge tools like
    # `signature_generator`, `match_refiner`, and per-node-type `preference` settings.
    #
    # ## Important: Two Uses of merge_type
    #
    # The `merge_type` method serves two complementary purposes in the codebase:
    #
    # ### 1. NodeTyping-specific (gated by typed_node?)
    # Wrapped nodes (Wrapper/FrozenWrapper) with custom type tagging for:
    # - Per-node-type preferences (e.g., `:lint_gem` → `:template`)
    # - Match refinement based on custom categories
    # - Only applies when `typed_node?` returns true
    # - Accessed via `NodeTyping.merge_type_for(node)`
    #
    # ### 2. General node classification (any node)
    # Any node can implement `merge_type` for category identification:
    # - FreezeNodeBase has `merge_type` → `:freeze_block`
    # - GapLineNode has `merge_type` → `:gap_line`
    # - Used by systems like MarkdownStructure for structural spacing rules
    # - These nodes are NOT "typed nodes" (typed_node? returns false)
    #
    # The key distinction: **typed_node? is the gate** for NodeTyping wrapper
    # semantics. A node can have `merge_type` without being a NodeTyping wrapper.
    #
    # @example Basic node typing for different gem types
    #   node_typing = {
    #     CallNode: ->(node) {
    #       return node unless node.name == :gem
    #       first_arg = node.arguments&.arguments&.first
    #       return node unless first_arg.is_a?(StringNode)
    #
    #       gem_name = first_arg.unescaped
    #       if gem_name.start_with?("rubocop")
    #         NodeTyping.with_merge_type(node, :lint_gem)
    #       elsif gem_name.start_with?("rspec")
    #         NodeTyping.with_merge_type(node, :test_gem)
    #       else
    #         node
    #       end
    #     }
    #   }
    #
    # @example Using with per-node-type preference
    #   merger = SmartMerger.new(
    #     template,
    #     destination,
    #     node_typing: node_typing,
    #     preference: {
    #       default: :destination,
    #       lint_gem: :template,  # Use template versions for lint gems
    #       test_gem: :destination  # Keep destination versions for test gems
    #     }
    #   )
    #
    # @see MergerConfig
    # @see ConflictResolverBase
    module NodeTyping
      autoload :FrozenWrapper, 'ast/merge/node_typing/frozen_wrapper'
      autoload :Normalizer, 'ast/merge/node_typing/normalizer'
      autoload :Wrapper, 'ast/merge/node_typing/wrapper'

      class << self
        # Wrap a node with a custom merge_type.
        #
        # @param node [Object] The node to wrap
        # @param merge_type [Symbol] The merge type to assign
        # @return [Wrapper] The wrapped node
        #
        # @example
        #   typed_node = NodeTyping.with_merge_type(call_node, :config_call)
        #   typed_node.merge_type  # => :config_call
        #   typed_node.name        # => delegates to call_node.name
        def with_merge_type(node, merge_type)
          Wrapper.new(node, merge_type)
        end

        # Wrap a node as frozen with the Freezable behavior.
        #
        # @param node [Object] The node to wrap as frozen
        # @param merge_type [Symbol] The merge type (defaults to :frozen)
        # @return [FrozenWrapper] The frozen wrapped node
        #
        # @example
        #   frozen_node = NodeTyping.frozen(call_node)
        #   frozen_node.freeze_node?  # => true
        #   frozen_node.is_a?(Ast::Merge::Freezable)  # => true
        def frozen(node, merge_type = :frozen)
          FrozenWrapper.new(node, merge_type)
        end

        # Check if a node is a frozen wrapper.
        #
        # @param node [Object] The node to check
        # @return [Boolean] true if the node is a FrozenWrapper or includes Freezable
        def frozen_node?(node)
          node.is_a?(Freezable)
        end

        # Check if a node is a node type wrapper.
        #
        # @param node [Object] The node to check
        # @return [Boolean] true if the node is a Wrapper
        def typed_node?(node)
          node.respond_to?(:typed_node?) && node.typed_node?
        end

        # Get the merge_type from a node, returning nil if it's not a typed node.
        #
        # @param node [Object] The node to get merge_type from
        # @return [Symbol, nil] The merge_type or nil
        def merge_type_for(node)
          typed_node?(node) ? node.merge_type : nil
        end

        # Unwrap a typed node to get the original node.
        # Returns the node unchanged if it's not wrapped.
        #
        # @param node [Object] The node to unwrap
        # @return [Object] The unwrapped node
        def unwrap(node)
          typed_node?(node) ? node.unwrap : node
        end

        # Process a node through a typing configuration.
        #
        # @param node [Object] The node to process
        # @param typing_config [Hash{Symbol,String => #call}, nil] Hash mapping node type names
        #   to callables. Keys can be symbols or strings representing node class names
        #   (e.g., :CallNode, "DefNode", :Prism_CallNode for fully qualified names)
        # @return [Object, nil] The processed node (possibly wrapped with merge_type),
        #   or nil if the node should be skipped
        #
        # @example
        #   config = {
        #     CallNode: ->(node) {
        #       NodeTyping.with_merge_type(node, :special_call)
        #     }
        #   }
        #   result = NodeTyping.process(call_node, config)
        def process(node, typing_config)
          return node unless typing_config
          return node if typing_config.empty?

          # Get the node type name for lookup
          type_key = node_type_key(node)

          # Try to find a matching typing callable
          callable = find_typing_callable(typing_config, type_key, node)
          return node unless callable

          # Call the typing callable with the node.
          # NOTE: For TreeHaver-based backends, the node already has a unified API
          # with #text, #type, #source_position methods. For other backends, they
          # must conform to the same API (either via TreeHaver or equivalent adapter).
          callable.call(node)
        end

        # Validate a typing configuration hash.
        #
        # @param typing_config [Hash, nil] The configuration to validate
        # @raise [ArgumentError] If the configuration is invalid
        # @return [void]
        def validate!(typing_config)
          return if typing_config.nil?

          raise ArgumentError, "node_typing must be a Hash, got #{typing_config.class}" unless typing_config.is_a?(Hash)

          typing_config.each do |key, value|
            unless key.is_a?(Symbol) || key.is_a?(String)
              raise ArgumentError,
                    "node_typing keys must be Symbol or String, got #{key.class} for #{key.inspect}"
            end

            next if value.respond_to?(:call)

            raise ArgumentError,
                  'node_typing values must be callable (respond to #call), ' \
                    "got #{value.class} for key #{key.inspect}"
          end
        end

        private

        # Get the type key for looking up a typing callable.
        # Handles both simple class names and fully-qualified names.
        #
        # @param node [Object] The node to get the type key for
        # @return [String] The type key
        def node_type_key(node)
          # Handle Wrapper - use the wrapped node's class
          actual_node = typed_node?(node) ? node.unwrap : node
          actual_node.class.name&.split('::')&.last || actual_node.class.to_s
        end

        # Find a typing callable for the given type key.
        #
        # @param config [Hash] The typing configuration
        # @param type_key [String] The type key to look up
        # @param node [Object] The original node (for fully-qualified lookup)
        # @return [#call, nil] The typing callable or nil
        def find_typing_callable(config, type_key, node)
          # Try exact match with symbol key
          return config[type_key.to_sym] if config.key?(type_key.to_sym)

          # Try exact match with string key
          return config[type_key] if config.key?(type_key)

          # Try fully-qualified class name (e.g., "Prism::CallNode")
          actual_node = typed_node?(node) ? node.unwrap : node
          full_name = actual_node.class.name
          return config[full_name.to_sym] if full_name && config.key?(full_name.to_sym)
          return config[full_name] if full_name && config.key?(full_name)

          # Try with underscored naming (e.g., :prism_call_node)
          underscored = full_name&.gsub('::', '_')&.gsub(/([a-z])([A-Z])/, '\1_\2')&.downcase
          return config[underscored&.to_sym] if underscored && config.key?(underscored.to_sym)

          nil
        end
      end
    end
  end
end
