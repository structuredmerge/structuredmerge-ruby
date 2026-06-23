# frozen_string_literal: true

module Prism
  module Merge
    # Thin navigable adapter for top-level Prism statements used by
    # PartialTemplateMerger.
    #
    # The shared navigable substrate expects statement-like objects that expose
    # `type`, `text`, and `source_position`. Prism::Merge::FileAnalysis returns
    # raw Prism nodes (and wrapped frozen nodes) whose native API is richer than
    # that contract but not shaped the same way. This adapter keeps the partial
    # merger thin without changing the full SmartMerger path.
    class PartialTemplateNode
      attr_reader :node

      def initialize(node)
        @node = node
      end

      def type
        return fallback_type_name unless inner_node.respond_to?(:type)

        ct = NodeTypeNormalizer.canonical_type(inner_node.type, :prism)
        return :call_with_block if ct == :call && inner_node.block

        ct || fallback_type_name
      end

      def text
        node.slice.to_s
      end

      def source_position
        loc = node.location
        return unless loc

        {
          start_line: loc.start_line,
          end_line: loc.end_line
        }
      end

      def start_line
        source_position&.dig(:start_line)
      end

      def end_line
        source_position&.dig(:end_line)
      end

      def location
        node.location
      end

      def inner_node
        n = node.respond_to?(:unwrap) ? node.unwrap : node
        n.respond_to?(:node) ? n.node : n
      end

      def method_missing(method_name, *args, &block)
        return node.public_send(method_name, *args, &block) if node.respond_to?(method_name)

        super
      end

      def respond_to_missing?(method_name, include_private = false)
        node.respond_to?(method_name, include_private) || super
      end

      private

      def fallback_type_name
        class_name = inner_node.class.name.to_s.split('::').last
        class_name.sub(/Node\z/, '').gsub(/([a-z\d])([A-Z])/, '\\1_\\2').downcase.to_sym
      end
    end
  end
end
