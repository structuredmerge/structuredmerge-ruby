# frozen_string_literal: true

module Psych
  module Merge
    # Shared native Psych projection used by semantic verification and contract
    # snapshot extensions. Location and ownership remain separate concerns.
    module NativeProjection
      ATTRIBUTE_NAMES = %i[anchor tag style plain quoted implicit implicit_end version tag_directives].freeze

      module_function

      def semantic(node)
        {
          type: node.class.name.delete_prefix('Psych::Nodes::'),
          value: (node.value if node.respond_to?(:value)),
          tag: (node.tag if node.respond_to?(:tag)),
          children: children(node).map { |child| semantic(child) }
        }.compact.freeze
      end

      def attribute_tree(node)
        {
          attributes: attributes(node),
          children: children(node).map { |child| attribute_tree(child) }
        }.freeze
      end

      def attributes(node)
        ATTRIBUTE_NAMES.each_with_object({}) do |name, result|
          result[name] = public_value(node.public_send(name)) if node.respond_to?(name)
        end.freeze
      end

      def public_value(value)
        case value
        when Array then value.map { |item| public_value(item) }
        when Hash then value.to_h { |key, item| [key.to_s, public_value(item)] }
        when String, Integer, Float, TrueClass, FalseClass, NilClass then value
        else value.to_s
        end
      end

      def children(node)
        Array(node.respond_to?(:children) ? node.children : [])
      end
      private_class_method :children
    end
  end
end
