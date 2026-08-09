# frozen_string_literal: true

module Rust
  module Merge
    # Structural identity and source-range adapter for one top-level Rust item.
    # rubocop:disable Metrics/AbcSize, Metrics/ClassLength, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- Rust item forms share one structural identity boundary
    class NodeWrapper
      DECLARATION_TYPES = %w[
        const_item
        enum_item
        expression_statement
        extern_crate_declaration
        function_item
        impl_item
        macro_definition
        mod_item
        static_item
        struct_item
        trait_item
        type_item
        union_item
        use_declaration
      ].freeze
      NAMED_ITEMS = {
        'const_item' => [:const, %w[identifier]],
        'enum_item' => [:enum, %w[type_identifier]],
        'function_item' => [:function, %w[identifier]],
        'macro_definition' => [:macro, %w[identifier]],
        'mod_item' => [:module, %w[identifier]],
        'static_item' => [:static, %w[identifier]],
        'struct_item' => [:struct, %w[type_identifier]],
        'trait_item' => [:trait, %w[type_identifier]],
        'type_item' => [:type, %w[type_identifier]],
        'union_item' => [:union, %w[type_identifier]]
      }.freeze
      COMMENT_TYPES = %w[block_comment line_comment].freeze
      ATTRIBUTE_TYPES = %w[attribute_item].freeze

      attr_reader :node, :source, :leading_comments, :trailing_comments

      def initialize(node, source:, leading_comments: [])
        @node = node
        @source = source
        @leading_comments = leading_comments.freeze
        @trailing_comments = []
      end

      def signature
        value = case node.type
                when 'use_declaration' then use_signature
                when 'extern_crate_declaration' then extern_crate_signature
                when 'impl_item' then impl_signature
                when 'expression_statement' then macro_invocation_signature
                else named_signature(node)
                end
        value.freeze
      end

      def membership_signature
        return semantic_node(use_body) if compound_use?

        signature
      end

      def compound? = compound_use?
      def start_byte = leading_comments.first&.start_byte || node.start_byte
      def end_byte = trailing_comments.last&.end_byte || node.end_byte
      def start_line = line_for_byte(start_byte)
      def end_line = line_for_byte(end_byte.zero? ? 0 : end_byte - 1)
      def source_text = source.byteslice(start_byte...end_byte).to_s
      def attach_trailing_comment!(comment) = trailing_comments << comment
      def semantic_tree = semantic_node(node)

      private

      def named_signature(value)
        kind, name_types = NAMED_ITEMS.fetch(value.type) do
          raise ArgumentError, "Unsupported top-level Rust node #{value.type.inspect}"
        end
        name = direct_named_child(value, name_types)
        raise ArgumentError, "#{value.type} has no structurally attributable name" unless name

        [kind, text(name)]
      end

      def use_signature
        body = use_body
        return [:use_tree, use_tree_root(body)] if compound_use?

        [:use, use_target(body)]
      end

      def use_body
        node.children.find do |child|
          child.named? && child.type != 'visibility_modifier'
        end || raise(ArgumentError, 'use declaration has no structural tree')
      end

      def compound_use?
        node.type == 'use_declaration' && !find_descendant(use_body, %w[use_list]).nil?
      end

      def use_tree_root(body)
        return :root if body.type == 'use_list'

        child = body.children.find { |candidate| candidate.named? && candidate.type != 'use_list' }
        raise ArgumentError, 'compound use tree has no structural root' unless child

        path_head(child)
      end

      def use_target(body)
        case body.type
        when 'use_as_clause'
          target = body.children.find(&:named?)
          raise ArgumentError, 'use alias has no structural target' unless target

          path_head(target)
        when 'scoped_identifier'
          path_head(body)
        when 'use_wildcard'
          [:wildcard, path_head(body)]
        when 'identifier', 'self', 'super', 'crate'
          text(body)
        else
          [:tree, semantic_node(body)]
        end
      end

      def extern_crate_signature
        identifiers = node.children.select { |child| child.type == 'identifier' }
        raise ArgumentError, 'extern crate declaration has no crate name' if identifiers.empty?

        [:extern_crate, text(identifiers.first)]
      end

      def impl_signature
        children = node.children
        for_index = children.index { |child| child.type == 'for' }
        type_nodes = children.select { |child| rust_type_node?(child) }
        target = for_index ? children[(for_index + 1)..].find { |child| rust_type_node?(child) } : type_nodes.last
        trait = for_index && children[...for_index].reverse.find { |child| rust_type_node?(child) }
        raise ArgumentError, 'impl item has no structural target' unless target

        polarity = children.any? { |child| child.type == '!' } ? :negative : :positive
        [:impl, trait && path_head(trait), path_head(target), polarity, generic_arity]
      end

      def generic_arity
        parameters = node.children.find { |child| child.type == 'type_parameters' }
        return 0 unless parameters

        parameters.children.count do |child|
          %w[type_parameter lifetime_parameter const_parameter].include?(child.type)
        end
      end

      def rust_type_node?(value)
        return false unless value.named?

        excluded = %w[type_parameters where_clause declaration_list visibility_modifier] +
                   COMMENT_TYPES + ATTRIBUTE_TYPES
        !excluded.include?(value.type)
      end

      def macro_invocation_signature
        invocation = node.children.find { |child| child.type == 'macro_invocation' }
        raise ArgumentError, 'expression statement is not a top-level macro invocation' unless invocation

        path = invocation.children.find do |child|
          %w[identifier scoped_identifier].include?(child.type)
        end
        raise ArgumentError, 'macro invocation has no structural path' unless path

        [:macro_invocation, path_head(path)]
      end

      def path_head(value)
        case value.type
        when 'generic_type', 'reference_type', 'pointer_type'
          child = value.children.find(&:named?)
          child ? path_head(child) : value.type
        when 'scoped_identifier', 'scoped_type_identifier'
          value.children.select(&:named?).map { |child| path_head(child) }
        when 'use_wildcard'
          child = value.children.find(&:named?)
          child ? path_head(child) : :wildcard
        else
          text(value)
        end
      end

      def direct_named_child(parent, types)
        parent.children.find { |candidate| types.include?(candidate.type) }
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
