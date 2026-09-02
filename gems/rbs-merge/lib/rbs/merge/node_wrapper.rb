# frozen_string_literal: true

module Rbs
  module Merge
    # Wraps RBS AST nodes with a unified interface for merging.
    # Supports both the RBS gem's native AST and tree-sitter-rbs nodes.
    #
    # Inherits common functionality from Ast::Merge::NodeWrapperBase:
    # - Source context (lines, source, comments)
    # - Line info extraction
    # - Basic methods: #type, #text, #signature
    #
    # Adds RBS-specific functionality:
    # - Backend awareness for RBS gem/tree-sitter normalization
    # - Type predicates using NodeTypeNormalizer
    # - Name extraction for declarations and members
    #
    # @example Basic usage with RBS gem
    #   analysis = FileAnalysis.new(source)
    #   analysis.statements.each do |wrapper|
    #     puts wrapper.canonical_type  # => :class, :module, etc.
    #     puts wrapper.name            # => "Foo", "Bar::Baz"
    #   end
    #
    # @see Ast::Merge::NodeWrapperBase
    class NodeWrapper < Ast::Merge::NodeWrapperBase
      class << self
        # Wrap an RBS node, returning nil for nil input.
        #
        # @param node [Object, nil] RBS node to wrap (RBS::AST::* or tree-sitter node)
        # @param lines [Array<String>] Source lines for content extraction
        # @param source [String, nil] Original source string
        # @param leading_comments [Array<Hash>] Comments before this node
        # @param inline_comment [Hash, nil] Inline comment on the node's line
        # @param backend [Symbol] The backend used for parsing (:rbs or :tree_sitter)
        # @return [NodeWrapper, nil] Wrapped node or nil if node is nil
        def wrap(node, lines, source: nil, leading_comments: [], inline_comment: nil, backend: :rbs)
          return if node.nil?

          new(
            node,
            lines: lines,
            source: source,
            leading_comments: leading_comments,
            inline_comment: inline_comment,
            backend: backend
          )
        end
      end

      # @return [Symbol] The backend used for parsing (:rbs or :tree_sitter)
      attr_reader :backend

      # Process RBS-specific options (backend)
      # @param options [Hash] Additional options
      def process_additional_options(options)
        @backend = options.fetch(:backend, :rbs)
      end

      # Get the raw type from the underlying node
      # @return [Symbol]
      def type
        if @backend == :rbs
          # For RBS gem, use class name as type
          @node.class.name.to_sym
        else
          # For tree-sitter, use the node's type
          @node.type.to_sym
        end
      end

      # Get the canonical (normalized) type for this node
      # @return [Symbol]
      def canonical_type
        NodeTypeNormalizer.canonical_type_for_node(@node, @backend)
      end

      # Check if this node has a specific type (checks both raw and canonical)
      # @param type_name [Symbol, String] Type to check
      # @return [Boolean]
      def type?(type_name)
        type_sym = type_name.to_sym
        type == type_sym || canonical_type == type_sym
      end

      # Get the name of this declaration/member
      # @return [String, nil]
      def name
        return visibility_kind.to_s if visibility_kind

        if @backend == :rbs
          extract_rbs_name
        else
          extract_tree_sitter_name
        end
      end

      # Get the associated comment for this declaration (RBS gem only)
      # RBS gem associates comments with declarations via the `comment` attribute
      # @return [Object, nil] The comment object or nil
      def comment
        return unless @backend == :rbs
        return unless @node.respond_to?(:comment)

        @node.comment
      end

      # Check if this is a class declaration
      # @return [Boolean]
      def class?
        canonical_type == :class
      end

      # Check if this is a module declaration
      # @return [Boolean]
      def module?
        canonical_type == :module
      end

      # Check if this is an interface declaration
      # @return [Boolean]
      def interface?
        canonical_type == :interface
      end

      # Check if this is a type alias declaration
      # @return [Boolean]
      def type_alias?
        canonical_type == :type_alias
      end

      # Check if this is a constant declaration
      # @return [Boolean]
      def constant?
        canonical_type == :constant
      end

      # Check if this is a global variable declaration
      # @return [Boolean]
      def global?
        canonical_type == :global
      end

      # Check if this is a method definition
      # @return [Boolean]
      def method?
        canonical_type == :method
      end

      # Check if this is a method alias
      # @return [Boolean]
      def alias?
        canonical_type == :alias
      end

      # Check if this is an attribute reader
      # @return [Boolean]
      def attr_reader?
        canonical_type == :attr_reader
      end

      # Check if this is an attribute writer
      # @return [Boolean]
      def attr_writer?
        canonical_type == :attr_writer
      end

      # Check if this is an attribute accessor
      # @return [Boolean]
      def attr_accessor?
        canonical_type == :attr_accessor
      end

      # Check if this is any kind of attribute
      # @return [Boolean]
      def attr?
        %i[attr_reader attr_writer attr_accessor].include?(canonical_type)
      end

      # Check if this is an include
      # @return [Boolean]
      def include?
        canonical_type == :include
      end

      # Check if this is an extend
      # @return [Boolean]
      def extend?
        canonical_type == :extend
      end

      # Check if this is a prepend
      # @return [Boolean]
      def prepend?
        canonical_type == :prepend
      end

      # Check if this is an instance variable
      # @return [Boolean]
      def ivar?
        canonical_type == :ivar
      end

      # Check if this is a class instance variable
      # @return [Boolean]
      def civar?
        canonical_type == :civar
      end

      # Check if this is a class variable
      # @return [Boolean]
      def cvar?
        canonical_type == :cvar
      end

      # Check if this is a visibility member
      # @return [Boolean]
      def visibility?
        canonical_type == :visibility
      end

      # Check if this is a declaration (class, module, interface, etc.)
      # @return [Boolean]
      def declaration?
        NodeTypeNormalizer.declaration_type?(canonical_type)
      end

      # Check if this is a member (method, attr, include, etc.)
      # @return [Boolean]
      def member?
        NodeTypeNormalizer.member_type?(canonical_type)
      end

      # Check if this is a container (can have children/members)
      # @return [Boolean]
      def container?
        NodeTypeNormalizer.container_type?(canonical_type)
      end

      # Get the start line of this node
      # @return [Integer, nil]
      def start_line
        if @backend == :rbs
          @node.location&.start_line
        else
          super
        end
      end

      # Get the end line of this node
      # @return [Integer, nil]
      def end_line
        if @backend == :rbs
          @node.location&.end_line
        else
          super
        end
      end

      # Get source text for this node
      # @return [String, nil]
      def text
        if @source
          if @backend == :rbs
            location = @node.respond_to?(:location) ? @node.location : nil
            if location&.start_pos && location.end_pos
              exact = @source.byteslice(location.start_pos...location.end_pos)
              return exact unless exact.nil?
            end
          elsif @node.respond_to?(:start_byte) && @node.respond_to?(:end_byte)
            exact = @source.byteslice(@node.start_byte...@node.end_byte)
            return exact unless exact.nil?
          end
        end

        return unless start_line && end_line

        if @lines && start_line.positive? && end_line <= @lines.length
          @lines[(start_line - 1)..(end_line - 1)].join("\n")
        elsif @source
          @source.lines[(start_line - 1)..(end_line - 1)]&.join
        end
      end

      # Get members of this container (for class/module/interface)
      # @return [Array<NodeWrapper>]
      def members
        return [] unless container?

        if @backend == :rbs
          extract_rbs_members
        else
          extract_tree_sitter_members
        end
      end

      # Generate a signature for this node
      # @return [Array, nil]
      def signature
        case canonical_type
        when :class
          [:class, name]
        when :module
          [:module, name]
        when :interface
          [:interface, name]
        when :type_alias
          [:type_alias, name]
        when :constant
          [:constant, name]
        when :global
          [:global, name]
        when :class_alias
          [:class_alias, name]
        when :module_alias
          [:module_alias, name]
        when :method
          kind = method_kind
          [:method, name, kind]
        when :alias
          [:alias, alias_new_name, alias_old_name]
        when :attr_reader
          [:attr_reader, name]
        when :attr_writer
          [:attr_writer, name]
        when :attr_accessor
          [:attr_accessor, name]
        when :include
          [:include, name]
        when :extend
          [:extend, name]
        when :prepend
          [:prepend, name]
        when :ivar
          [:ivar, name]
        when :civar
          [:civar, name]
        when :cvar
          [:cvar, name]
        when :visibility
          [:visibility, visibility_kind]
        else
          [:unknown, canonical_type, start_line]
        end
      end

      # Get method kind (instance, singleton, singleton_instance)
      # @return [Symbol, nil]
      def method_kind
        return unless method?

        if @backend == :rbs
          @node.respond_to?(:kind) ? @node.kind : :instance
        else
          return :instance unless @node.respond_to?(:each)

          @node.each do |child|
            return :singleton if child.respond_to?(:type) && child.type.to_sym == :self
          end

          :instance
        end
      end

      # Get alias new name
      # @return [String, nil]
      def alias_new_name
        return unless alias?

        if @backend == :rbs
          @node.respond_to?(:new_name) ? @node.new_name.to_s : nil
        else
          method_names = extract_child_texts('method_name')
          method_names.first || extract_child_text('new_name') || extract_child_text('alias_name')
        end
      end

      # Get alias old name
      # @return [String, nil]
      def alias_old_name
        return unless alias?

        if @backend == :rbs
          @node.respond_to?(:old_name) ? @node.old_name.to_s : nil
        else
          method_names = extract_child_texts('method_name')
          method_names[1] || extract_child_text('old_name') || extract_child_text('aliased_name')
        end
      end

      # Get visibility kind (:public or :private)
      # @return [Symbol, nil]
      def visibility_kind
        return unless visibility?

        if @backend == :rbs
          raw_type = @node.class.name.to_s
          return :public if raw_type.end_with?('::Public')
          return :private if raw_type.end_with?('::Private')

          nil
        else
          extract_tree_sitter_visibility_kind
        end
      end

      private

      # Extract name from RBS gem node
      # @return [String, nil]
      def extract_rbs_name
        if @node.respond_to?(:name)
          @node.name.to_s
        elsif @node.respond_to?(:new_name)
          @node.new_name.to_s
        end
      end

      # Extract name from tree-sitter node
      # @return [String, nil]
      def extract_tree_sitter_name
        # Look for name-related children based on actual tree-sitter-rbs grammar
        # class_decl has class_name, module_decl has module_name, etc.
        name_node_types = %w[
          class_name
          module_name
          interface_name
          const_name
          global_name
          alias_name
          method_name
          ivar_name
          cvar_name
        ]

        @node.each do |child|
          child_type = child.type.to_s
          next unless name_node_types.include?(child_type)

          # Name nodes often have a constant or identifier child
          child.each do |inner|
            inner_type = inner.type.to_s
            return extract_node_text(inner) if %w[constant identifier].include?(inner_type)
          end
          # If no inner constant/identifier, try the name node itself
          return extract_node_text(child)
        end

        nil
      end

      # Extract text from a node
      # @param node [Object] The node to extract text from
      # @return [String, nil]
      def extract_node_text(node)
        if node.respond_to?(:text)
          node.text
        elsif node.respond_to?(:start_byte) && node.respond_to?(:end_byte) && @source
          @source.byteslice(node.start_byte, node.end_byte - node.start_byte)
        end
      end

      def extract_child_text(child_type)
        extract_child_texts(child_type).first
      end

      def extract_child_texts(*child_types)
        desired_types = child_types.flatten.map(&:to_s)
        return [] unless @node.respond_to?(:each)

        @node.each_with_object([]) do |child, texts|
          next unless desired_types.include?(child.type.to_s)

          inner_text = if child.respond_to?(:each)
                         child.each do |inner|
                           inner_type = inner.type.to_s
                           break extract_node_text(inner) if %w[constant identifier].include?(inner_type)
                         end
                       end

          texts << (inner_text || extract_node_text(child))
        end.compact
      end

      def extract_tree_sitter_visibility_kind
        return unless @node.respond_to?(:each)

        @node.each do |child|
          next unless child.respond_to?(:type)

          child_type = child.type.to_s
          return child_type.to_sym if %w[public private].include?(child_type)

          next unless child.respond_to?(:each)

          child.each do |inner|
            next unless inner.respond_to?(:type)

            inner_type = inner.type.to_s
            return inner_type.to_sym if %w[public private].include?(inner_type)
          end
        end

        nil
      end

      # Extract members from RBS gem container node
      # @return [Array<NodeWrapper>]
      def extract_rbs_members
        return [] unless @node.respond_to?(:members)

        @node.members.map do |member|
          NodeWrapper.new(
            member,
            lines: @lines,
            source: @source,
            backend: @backend
          )
        end
      end

      # Extract members from tree-sitter container node
      # @return [Array<NodeWrapper>]
      def extract_tree_sitter_members
        @node.each_with_object([]) do |child, members|
          append_tree_sitter_member_nodes(members, child)
        end
      end

      def append_tree_sitter_member_nodes(members, node)
        canonical = NodeTypeNormalizer.canonical_type_for_node(node, @backend)

        if NodeTypeNormalizer.member_type?(canonical)
          members << NodeWrapper.new(
            node,
            lines: @lines,
            source: @source,
            backend: @backend
          )
          return
        end

        return unless %i[members_container member_wrapper].include?(canonical)

        node.each do |child|
          append_tree_sitter_member_nodes(members, child)
        end
      end
    end
  end
end
