# frozen_string_literal: true

module Rbs
  module Merge
    # Alias for the shared normalizer module from ast-merge
    NodeTypingNormalizer = Ast::Merge::NodeTyping::Normalizer

    # Normalizes backend-specific node types to canonical RBS types.
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
    # - `:rbs` - Official RBS gem parser (MRI only, full-featured)
    # - `:tree_sitter` - tree-sitter-rbs grammar (cross-platform)
    #
    # ## Extensibility
    #
    # New backends can be registered at runtime:
    #
    # @example Registering a new backend
    #   NodeTypeNormalizer.register_backend(:my_rbs_parser, {
    #     class_decl: :class,
    #     module_decl: :module,
    #   })
    #
    # ## Canonical Types
    #
    # The following canonical types are used for portable merge rules:
    #
    # ### Declaration Types
    # - `:class` - Class declaration
    # - `:module` - Module declaration
    # - `:interface` - Interface declaration
    # - `:type_alias` - Type alias declaration
    # - `:constant` - Constant declaration
    # - `:global` - Global variable declaration
    #
    # ### Member Types
    # - `:method` - Method definition
    # - `:alias` - Method alias
    # - `:attr_reader` - Attribute reader
    # - `:attr_writer` - Attribute writer
    # - `:attr_accessor` - Attribute accessor
    # - `:include` - Module include
    # - `:extend` - Module extend
    # - `:prepend` - Module prepend
    # - `:ivar` - Instance variable
    # - `:civar` - Class instance variable
    # - `:cvar` - Class variable
    #
    # ### Other
    # - `:comment` - Comment lines
    # - `:document` - Root document node
    #
    # @see Ast::Merge::NodeTyping::Wrapper
    # @see Ast::Merge::NodeTyping::Normalizer
    module NodeTypeNormalizer
      extend NodeTypingNormalizer

      # Configure default backend mappings.
      # Maps backend-specific type symbols to canonical type symbols.
      configure_normalizer(
        # RBS gem parser node types (from RBS::AST::Declarations::* and RBS::AST::Members::*)
        # These are Ruby class names, so we map them to canonical symbols
        rbs: {
          # Document structure
          document: :document,

          # Declaration types (RBS::AST::Declarations::*)
          "RBS::AST::Declarations::Class": :class,
          "RBS::AST::Declarations::Module": :module,
          "RBS::AST::Declarations::Interface": :interface,
          "RBS::AST::Declarations::TypeAlias": :type_alias,
          "RBS::AST::Declarations::Constant": :constant,
          "RBS::AST::Declarations::Global": :global,
          "RBS::AST::Declarations::ClassAlias": :class_alias,
          "RBS::AST::Declarations::ModuleAlias": :module_alias,

          # Member types (RBS::AST::Members::*)
          "RBS::AST::Members::MethodDefinition": :method,
          "RBS::AST::Members::Alias": :alias,
          "RBS::AST::Members::AttrReader": :attr_reader,
          "RBS::AST::Members::AttrWriter": :attr_writer,
          "RBS::AST::Members::AttrAccessor": :attr_accessor,
          "RBS::AST::Members::Include": :include,
          "RBS::AST::Members::Extend": :extend,
          "RBS::AST::Members::Prepend": :prepend,
          "RBS::AST::Members::InstanceVariable": :ivar,
          "RBS::AST::Members::ClassInstanceVariable": :civar,
          "RBS::AST::Members::ClassVariable": :cvar,
          "RBS::AST::Members::Public": :visibility,
          "RBS::AST::Members::Private": :visibility,

          # Simplified type names (for when we use .type method)
          class: :class,
          module: :module,
          interface: :interface,
          type_alias: :type_alias,
          constant: :constant,
          global: :global,
          class_alias: :class_alias,
          module_alias: :module_alias,
          method: :method,
          method_definition: :method,
          alias: :alias,
          attr_reader: :attr_reader,
          attr_writer: :attr_writer,
          attr_accessor: :attr_accessor,
          include: :include,
          extend: :extend,
          prepend: :prepend,
          ivar: :ivar,
          instance_variable: :ivar,
          civar: :civar,
          class_instance_variable: :civar,
          cvar: :cvar,
          class_variable: :cvar,
          public: :visibility,
          private: :visibility,

          # Other
          comment: :comment
        }.freeze,

        # tree-sitter-rbs grammar node types
        # Discovered via examples/map_tree_sitter_node_types.rb
        # Structure: program -> decl -> *_decl (class_decl, module_decl, etc.)
        tree_sitter: {
          # Document structure
          program: :document,
          decl: :declaration_wrapper, # Wrapper around all top-level declarations

          # Declaration types (direct children of decl)
          class_decl: :class,
          module_decl: :module,
          interface_decl: :interface,
          type_alias_decl: :type_alias,
          const_decl: :constant,
          global_decl: :global,
          class_alias_decl: :class_alias,
          module_alias_decl: :module_alias,

          # Member container nodes
          members: :members_container,
          interface_members: :members_container,
          member: :member_wrapper,
          interface_member: :member_wrapper,

          # Member types (inside member wrapper)
          method_member: :method,
          alias_member: :alias,
          attribute_member: :attribute, # Generic attribute, check attribyte_type child
          include_member: :include,
          extend_member: :extend,
          prepend_member: :prepend,
          ivar_member: :ivar,
          visibility_member: :visibility,

          # Attribute type specifiers (child of attribute_member)
          attribyte_type: :attribute_type, # NOTE: typo in grammar
          attr_reader: :attr_reader,
          attr_writer: :attr_writer,
          attr_accessor: :attr_accessor,

          # Variable types
          ivar_name: :ivar_name,
          cvar_name: :cvar_name,

          # Name nodes
          class_name: :type_name,
          module_name: :type_name,
          interface_name: :type_name,
          const_name: :const_name,
          global_name: :global_name,
          alias_name: :alias_name,
          method_name: :method_name,
          constant: :constant_ref,
          identifier: :identifier,

          # Type system nodes
          type: :type,
          class_type: :class_type,
          union_type: :union_type,
          builtin_type: :builtin_type,
          type_arguments: :type_arguments,
          type_variable: :type_variable,

          # Method signature nodes
          method_types: :method_types,
          method_type: :method_type,
          method_type_body: :method_type_body,
          parameters: :parameters,
          required_positionals: :required_positionals,
          parameter: :parameter,

          # Inheritance/mixin nodes
          superclass: :superclass,
          module_type_parameters: :type_parameters,
          module_type_parameter: :type_parameter,

          # Keywords (usually not needed for merge logic)
          class: :keyword_class,
          module: :keyword_module,
          interface: :keyword_interface,
          def: :keyword_def,
          end: :keyword_end,
          include: :keyword_include,
          extend: :keyword_extend,
          prepend: :keyword_prepend,
          public: :keyword_public,
          private: :keyword_private,
          self: :keyword_self,
          void: :keyword_void,
          bool: :keyword_bool,
          visibility: :visibility,

          # Other
          comment: :comment
        }.freeze
      )

      class << self
        # Default backend for RBS normalization
        DEFAULT_BACKEND = :rbs

        # Get the canonical type for a backend-specific type.
        # Overrides the shared Normalizer to default to :rbs backend.
        #
        # @param backend_type [Symbol, String, nil] The backend's node type
        # @param backend [Symbol] The backend identifier (defaults to :rbs)
        # @return [Symbol, nil] Canonical type (or original if no mapping)
        def canonical_type(backend_type, backend = DEFAULT_BACKEND)
          super(backend_type, backend)
        end

        # Get the canonical type for a specific node, allowing node-shape-aware
        # refinement when a backend uses generic wrapper/member node types.
        #
        # @param node [Object, nil] Backend node responding to #type and optionally #each
        # @param backend [Symbol] Backend identifier
        # @return [Symbol, nil]
        def canonical_type_for_node(node, backend = DEFAULT_BACKEND)
          return if node.nil?

          backend_type = if backend == :tree_sitter && node.respond_to?(:type)
                           node.type
                         else
                           node.class.name
                         end

          canonical = canonical_type(backend_type, backend)
          return canonical unless backend == :tree_sitter

          case canonical
          when :attribute
            refine_tree_sitter_attribute_type(node) || canonical
          when :ivar
            refine_tree_sitter_variable_type(node) || canonical
          else
            canonical
          end
        end

        # Wrap a node with its canonical type as merge_type.
        # Overrides the shared Normalizer to default to :rbs backend.
        #
        # @param node [Object] The backend node to wrap (must respond to #type)
        # @param backend [Symbol] The backend identifier (defaults to :rbs)
        # @return [Ast::Merge::NodeTyping::Wrapper] Wrapped node with canonical merge_type
        def wrap(node, backend = DEFAULT_BACKEND)
          super(node, backend)
        end

        # Check if a type is a declaration type (class, module, interface, etc.)
        # Also includes :declaration_wrapper which wraps declarations in tree-sitter-rbs
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def declaration_type?(type)
          canonical = type.to_sym
          %i[class module interface type_alias constant global class_alias module_alias
             declaration_wrapper].include?(canonical)
        end

        # Check if a type is a member type (method, attr, include, etc.)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def member_type?(type)
          canonical = type.to_sym
          %i[method alias attr_reader attr_writer attr_accessor include extend prepend ivar civar cvar
             visibility].include?(canonical)
        end

        # Check if a type is a container type (can have children/members)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def container_type?(type)
          canonical = type.to_sym
          %i[document class module interface].include?(canonical)
        end

        # Check if a type is a type definition (type_alias, etc.)
        #
        # @param type [Symbol, String] The type to check
        # @return [Boolean]
        def type_definition?(type)
          canonical = type.to_sym
          %i[type_alias].include?(canonical)
        end

        private

        def refine_tree_sitter_attribute_type(node)
          return unless node.respond_to?(:each)

          node.each do |child|
            next unless child.respond_to?(:type) && child.type.to_sym == :attribyte_type

            if child.respond_to?(:each)
              child.each do |grandchild|
                refined = canonical_type(grandchild.type, :tree_sitter)
                return refined if %i[attr_reader attr_writer attr_accessor].include?(refined)
              end
            end

            refined = canonical_type(child.type, :tree_sitter)
            return refined if %i[attr_reader attr_writer attr_accessor].include?(refined)
          end

          nil
        end

        def refine_tree_sitter_variable_type(node)
          return unless node.respond_to?(:each)

          saw_self = false

          node.each do |child|
            next unless child.respond_to?(:type)

            case child.type.to_sym
            when :self
              saw_self = true
            when :cvar_name
              return :cvar
            when :ivar_name
              return saw_self ? :civar : :ivar
            end
          end

          nil
        end
      end
    end
  end
end
