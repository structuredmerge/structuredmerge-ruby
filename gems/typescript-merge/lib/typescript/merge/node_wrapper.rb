# frozen_string_literal: true

module TypeScript
  module Merge
    # Structural identity and source-range adapter for one top-level TypeScript owner.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- TypeScript declaration forms share one structural identity boundary
    class NodeWrapper
      DECLARATION_TYPES = %w[
        ambient_declaration
        class_declaration
        enum_declaration
        expression_statement
        export_statement
        function_declaration
        function_signature
        import_statement
        interface_declaration
        internal_module
        lexical_declaration
        type_alias_declaration
        variable_declaration
      ].freeze
      NAMED_DECLARATIONS = {
        'class_declaration' => [:class, %w[type_identifier identifier]],
        'enum_declaration' => [:enum, %w[identifier type_identifier]],
        'interface_declaration' => [:interface, %w[type_identifier identifier]],
        'type_alias_declaration' => [:type, %w[type_identifier identifier]],
        'internal_module' => [:namespace, %w[identifier string nested_identifier]],
        'function_declaration' => [:function, %w[identifier]],
        'function_signature' => [:function, %w[identifier]]
      }.freeze

      attr_reader :node, :source, :leading_comments, :trailing_comments

      def initialize(node, source:, leading_comments: [])
        @node = node
        @source = source
        @leading_comments = leading_comments.freeze
        @trailing_comments = []
      end

      def signature
        return expression_statement_signature if node.type == 'expression_statement'
        return import_signature if node.type == 'import_statement'
        return export_signature if node.type == 'export_statement'
        return variable_signature(node) if variable_declaration?(node)
        return ambient_signature if node.type == 'ambient_declaration'

        named_signature(node)
      end

      def membership_signature
        signature
      end

      def grouped? = variable_declaration?(node)

      def start_byte = leading_comments.first&.start_byte || node.start_byte
      def end_byte = trailing_comments.last&.end_byte || node.end_byte
      def start_line = line_for_byte(start_byte)
      def end_line = line_for_byte(end_byte.zero? ? 0 : end_byte - 1)
      def source_text = source.byteslice(start_byte...end_byte).to_s
      def attach_trailing_comment!(comment) = trailing_comments << comment
      def semantic_tree = semantic_node(node)

      private

      def expression_statement_signature
        declaration = node.children.find { |child| NAMED_DECLARATIONS.key?(child.type) }
        return named_signature(declaration) if declaration

        call = direct_child(node, 'call_expression')
        raise ArgumentError, 'expression statement is not a supported top-level call' unless call

        callee = call.children.find(&:named?)
        unless callee && callee.type == 'identifier'
          raise ArgumentError, 'top-level call has no safely attributable named callee'
        end

        arguments = direct_child(call, 'arguments')
        identity = arguments&.children&.find(&:named?)
        unless identity && identity.type == 'string'
          raise ArgumentError, 'top-level call has no literal string identity'
        end

        [:call, text(callee), text(identity)]
      end

      def import_signature
        source_node = direct_child(node, 'string') || find_descendant(node, %w[string])
        raise ArgumentError, 'import_statement has no structural module source' unless source_node

        return [:import, text(source_node), :import_equals] if direct_child(node, 'import_require_clause')

        clause = direct_child(node, 'import_clause')
        type_only = !direct_child(node, 'type').nil?
        [:import, text(source_node), type_only ? :type : :value, import_form(clause)]
      end

      def export_signature
        default = node.children.any? { |child| child.type == 'default' }
        return [:default_export] if default

        declaration = node.children.find { |child| DECLARATION_TYPES.include?(child.type) }
        return [:export_declaration, declaration_signature(declaration)] if declaration

        source_node = direct_child(node, 'string')
        type_only = !direct_child(node, 'type').nil?
        if source_node
          return [:export_from, text(source_node), type_only ? :type : :value, export_form]
        end
        return [:export_local, type_only ? :type : :value, :named] if direct_child(node, 'export_clause')
        return [:export_assignment] if node.children.any? { |child| child.type == '=' }
        return [:export_as_namespace] if node.children.any? { |child| child.type == 'namespace' }

        [:export, semantic_node(node)]
      end

      def import_form(clause)
        return :side_effect unless clause

        child_types = clause.children.select(&:named?).map(&:type)
        default = child_types.include?('identifier')
        named = child_types.include?('named_imports')
        namespace = child_types.include?('namespace_import')
        return :default_named if default && named
        return :default_namespace if default && namespace
        return :default if default
        return :named if named
        return :namespace if namespace

        raise ArgumentError, "unsupported structural import clause #{child_types.inspect}"
      end

      def export_form
        return :named if direct_child(node, 'export_clause')
        return :namespace if direct_child(node, 'namespace_export')
        return :all if node.children.any? { |child| child.type == '*' }

        raise ArgumentError, 'unsupported structural export-from form'
      end

      def declaration_signature(declaration)
        return variable_signature(declaration) if variable_declaration?(declaration)
        return ambient_signature(declaration) if declaration.type == 'ambient_declaration'

        named_signature(declaration)
      end

      def named_signature(value)
        kind, name_types = NAMED_DECLARATIONS.fetch(value.type) do
          raise ArgumentError, "Unsupported top-level TypeScript node #{value.type.inspect}"
        end
        name = direct_named_child_text(value, name_types)
        raise ArgumentError, "#{value.type} has no structurally attributable name" unless name

        [kind, name]
      end

      def variable_signature(value)
        declarators = value.children.select { |child| child.type == 'variable_declarator' }
        names = declarators.map do |declarator|
          name = declarator.children.find(&:named?)
          raise ArgumentError, 'variable_declarator has no binding' unless name
          raise ArgumentError, "unsupported variable binding #{name.type}" unless %w[identifier].include?(name.type)

          text(name)
        end
        raise ArgumentError, "#{value.type} has no variable declarators" if names.empty?

        keyword = value.children.find { |child| %w[const let var].include?(child.type) }
        [:variables, keyword&.type, names.freeze]
      end

      def ambient_signature(value = node)
        declaration = value.children.find { |child| child.named? && child.type != 'declare' }
        raise ArgumentError, 'ambient_declaration has no declaration' unless declaration

        if declaration.type == 'module'
          name = declaration.children.find { |child| %w[string identifier nested_identifier].include?(child.type) }
          raise ArgumentError, 'module augmentation has no structural name' unless name

          return [:module_augmentation, text(name)]
        end

        [:ambient, named_signature(declaration)]
      end

      def variable_declaration?(value)
        %w[lexical_declaration variable_declaration].include?(value.type)
      end

      def direct_child(parent, type)
        parent.children.find { |child| child.type == type }
      end

      def direct_named_child_text(parent, types)
        child = parent.children.find { |candidate| types.include?(candidate.type) }
        child && text(child)
      end

      def find_descendant(parent, types)
        return parent if types.include?(parent.type)

        parent.children.each do |child|
          found = find_descendant(child, types)
          return found if found
        end
        nil
      end

      def semantic_node(value)
        children = value.children
        return [value.type, text(value)] if children.empty?

        [value.type, children.select(&:named?).map { |child| semantic_node(child) }]
      end

      def text(value) = source.byteslice(value.start_byte...value.end_byte).to_s
      def line_for_byte(byte) = source.byteslice(0...byte).to_s.count("\n") + 1
    end
    # rubocop:enable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
