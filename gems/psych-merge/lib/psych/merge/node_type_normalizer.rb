# frozen_string_literal: true

module Psych
  module Merge
    # Alias for the shared normalizer module from ast-merge
    NodeTypingNormalizer = Ast::Merge::NodeTyping::Normalizer

    # Normalizes backend-specific node types to canonical YAML types.
    #
    # Uses Ast::Merge::NodeTyping::Wrapper to wrap nodes with canonical
    # merge_type, allowing portable merge rules across backends.
    #
    # ## Thread Safety
    #
    # All backend registration and lookup operations are thread-safe via
    # the shared Ast::Merge::NodeTyping::Normalizer module.
    #
    # ## Backends
    #
    # Currently supports:
    # - `:psych` - Ruby's built-in Psych YAML parser (via TreeHaver Psych backend)
    #
    # ## Extensibility
    #
    # New backends can be registered at runtime:
    #
    # @example Registering a new backend
    #   NodeTypeNormalizer.register_backend(:my_yaml_parser, {
    #     mapping: :mapping,
    #     sequence: :sequence,
    #   })
    #
    # ## Canonical Types
    #
    # The following canonical types are used for portable merge rules:
    #
    # ### Document Structure
    # - `:stream` - Root stream node (may contain multiple documents)
    # - `:document` - A single YAML document
    #
    # ### Collection Types
    # - `:mapping` - YAML mapping (hash/object)
    # - `:sequence` - YAML sequence (array/list)
    #
    # ### Scalar/Reference Types
    # - `:scalar` - YAML scalar (string, number, boolean, null)
    # - `:alias` - YAML alias (reference to an anchor)
    #
    # @see Ast::Merge::NodeTyping::Wrapper
    # @see Ast::Merge::NodeTyping::Normalizer
    module NodeTypeNormalizer
      extend NodeTypingNormalizer

      # Configure default backend mappings.
      # Maps backend-specific type strings to canonical type symbols.
      #
      # TreeHaver's Psych backend derives node type via:
      #   inner_node.class.name.split("::").last.downcase
      # yielding lowercase strings: "stream", "document", "mapping", "sequence",
      # "scalar", "alias".
      configure_normalizer(
        psych: {
          mapping: :mapping,
          sequence: :sequence,
          scalar: :scalar,
          alias: :alias,
          document: :document,
          stream: :stream
        }.freeze
      )
    end
  end
end
