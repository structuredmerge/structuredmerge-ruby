# frozen_string_literal: true

module Html
  module Merge
    # Parser-derived identity, attributes, semantics, and source range for an HTML element.
    class NodeWrapper
      ELEMENT_TYPES = %w[element script_element style_element].freeze

      attr_reader :node, :source, :parent

      def initialize(node, source:, parent: nil)
        @node = node
        @source = source
        @parent = parent
      end

      def element? = ELEMENT_TYPES.include?(node.type)
      def start_byte = node.start_byte

      def end_byte
        return start_node.end_byte if !explicit_end_tag? && start_node

        node.end_byte
      end

      def source_text = source.byteslice(start_byte...end_byte).to_s
      def tag_name = node_text(first_descendant(start_node, "tag_name"))&.downcase
      def explicit_end_tag? = node.children.any? { |child| child.type == "end_tag" }
      def self_closing? = start_node&.type == "self_closing_tag"

      def attributes
        return {} unless start_node

        start_node.children.select { |child| child.type == "attribute" }.to_h do |attribute|
          attribute_pair(attribute)
        end.freeze
      end

      def explicit_id = attributes["id"]

      def semantic_tree
        semantic_node(node)
      end

      private

      def start_node
        node.children.find { |child| %w[start_tag self_closing_tag].include?(child.type) }
      end

      def attribute_pair(attribute)
        name_node = attribute.children.find { |child| child.type == "attribute_name" }
        value_node = first_descendant(attribute, "attribute_value")
        [node_text(name_node).to_s.downcase, value_node ? node_text(value_node) : true]
      end

      def first_descendant(value, type)
        return unless value
        return value if value.type == type

        value.children.each do |child|
          found = first_descendant(child, type)
          return found if found
        end
        nil
      end

      def node_text(value)
        value&.text&.to_s
      end

      def semantic_node(value)
        children = value.children.select(&:structural?)
        return [value.type, node_text(value)] if children.empty?

        [value.type, children.map { |child| semantic_node(child) }]
      end
    end
  end
end
