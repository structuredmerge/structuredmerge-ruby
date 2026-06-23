# frozen_string_literal: true

module Prism
  module Merge
    # Alias for the shared normalizer module from ast-merge
    NodeTypingNormalizer = Ast::Merge::NodeTyping::Normalizer

    # Normalizes backend-specific node types to canonical Ruby types.
    #
    # Uses Ast::Merge::NodeTyping::Normalizer to provide portable merge rules
    # across different Ruby parser backends.
    #
    # ## Backends
    #
    # Currently supports:
    # - `:prism` - Prism Ruby parser (via TreeHaver::Backends::Prism)
    # - `:tree_sitter_ruby` - tree-sitter-ruby grammar (not yet implemented)
    #
    # ## Canonical Types
    #
    # - `:def` - Method definition
    # - `:class` - Class definition
    # - `:module` - Module definition
    # - `:singleton_class` - Singleton class definition
    # - `:call` - Method call
    # - `:const` - Constant assignment
    # - `:local_var` - Local variable assignment
    # - `:ivar` - Instance variable assignment
    # - `:cvar` - Class variable assignment
    # - `:gvar` - Global variable assignment
    # - `:multi_write` - Multiple assignment
    # - `:if` - If conditional
    # - `:unless` - Unless conditional
    # - `:case` - Case statement
    # - `:case_match` - Case/in pattern match
    # - `:while` - While loop
    # - `:until` - Until loop
    # - `:for` - For loop
    # - `:begin` - Begin block
    # - `:rescue` - Rescue clause
    # - `:else` - Else clause
    # - `:ensure` - Ensure clause
    # - `:lambda` - Lambda literal
    # - `:pre_execution` - BEGIN block
    # - `:post_execution` - END block
    # - `:super` - Super call
    # - `:forwarding_super` - Forwarding super call
    # - `:parens` - Parenthesized expression
    # - `:string` - String literal
    # - `:symbol` - Symbol literal
    # - `:program` - Root program node
    # - `:statements` - Statements container
    # - `:block` - Block node
    # - `:local_var_read` - Local variable read
    # - `:const_path` - Constant path
    # - `:call_op_write` - Call operator write (e.g. +=)
    #
    # @see Ast::Merge::NodeTyping::Normalizer
    module NodeTypeNormalizer
      extend NodeTypingNormalizer

      # Configure default backend mappings.
      # Maps backend-specific type strings to canonical type symbols.
      # The `canonical_type` method calls `.to_s` on the input to handle
      # both String (from TreeHaver) and Symbol (from raw Prism) forms.
      configure_normalizer(
        # Prism parser node types
        # TreeHaver::Backends::Prism::Node#type converts PascalCase to snake_case:
        #   Prism::DefNode => "def_node"
        #   Prism::CallNode => "call_node"
        # Raw Prism nodes return a Symbol via #type (e.g. :def_node), use .to_s for consistency.
        prism: {
          def_node: :def,
          class_node: :class,
          module_node: :module,
          singleton_class_node: :singleton_class,
          call_node: :call,
          constant_write_node: :const,
          constant_path_write_node: :const,
          local_variable_write_node: :local_var,
          instance_variable_write_node: :ivar,
          class_variable_write_node: :cvar,
          global_variable_write_node: :gvar,
          multi_write_node: :multi_write,
          if_node: :if,
          unless_node: :unless,
          case_node: :case,
          case_match_node: :case_match,
          while_node: :while,
          until_node: :until,
          for_node: :for,
          begin_node: :begin,
          rescue_node: :rescue,
          else_node: :else,
          ensure_node: :ensure,
          lambda_node: :lambda,
          pre_execution_node: :pre_execution,
          post_execution_node: :post_execution,
          super_node: :super,
          forwarding_super_node: :forwarding_super,
          parentheses_node: :parens,
          string_node: :string,
          symbol_node: :symbol,
          program_node: :program,
          statements_node: :statements,
          block_node: :block,
          local_variable_read_node: :local_var_read,
          constant_path_node: :const_path,
          call_operator_write_node: :call_op_write,
          embedded_statements_node: :embedded
        }.freeze,

        # tree-sitter-ruby backend (not yet implemented)
        tree_sitter_ruby: {}.freeze
      )

      class << self
        # Default backend for Prism normalization
        DEFAULT_BACKEND = :prism

        # Get the canonical type for a backend-specific type.
        # Calls `.to_s` on the input to handle both String (from TreeHaver)
        # and Symbol (from raw Prism) forms.
        #
        # @param backend_type [Symbol, String, nil] The backend's node type
        # @param backend [Symbol] The backend identifier (defaults to :prism)
        # @return [Symbol, nil] Canonical type (or original if no mapping)
        def canonical_type(backend_type, backend = DEFAULT_BACKEND)
          return backend_type if backend_type.nil?

          super(backend_type.to_s.to_sym, backend)
        end
      end
    end
  end
end
