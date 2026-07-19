# frozen_string_literal: true

module Yaml
  module Merge
    class NodeWrapper < Ast::Merge::NodeWrapperBase
      attr_reader :document_index

      def process_additional_options(options)
        @document_index = options[:document_index]
      end

      def document?
        type?(:document)
      end

      def mapping?
        %i[block_mapping flow_mapping].include?(type)
      end

      def sequence?
        %i[block_sequence flow_sequence].include?(type)
      end

      def mapping_pair?
        type.to_s.end_with?('mapping_pair')
      end

      def comment?
        type?(:comment)
      end

      def container?
        document? || mapping?
      end

      def key_name
        return unless mapping_pair?

        key = semantic_children.first
        scalar_text(key)
      end

      def value_node
        return unless mapping_pair?

        value = semantic_children[1]
        value ? wrap_child(value) : nil
      end

      def body_node
        return unless document?

        semantic_children.find { |child| %w[block_node flow_node].include?(child.type.to_s) }&.then do |node|
          wrap_child(node).unwrap_value_node
        end
      end

      def unwrap_value_node
        current = self
        loop do
          break unless %i[block_node flow_node].include?(current.type)

          child = current.semantic_children.find { |candidate| !%w[anchor tag].include?(candidate.type.to_s) }
          break unless child

          current = current.wrap_child(child)
        end
        current
      end

      def mapping_pairs
        return [] unless mapping?

        semantic_children.filter_map do |child|
          wrapper = wrap_child(child)
          wrapper if wrapper.mapping_pair?
        end
      end

      def mergeable_children
        if document?
          body = body_node
          body&.mapping? ? body.mapping_pairs : []
        elsif mapping?
          mapping_pairs
        else
          []
        end
      end

      def semantic_children
        return [] unless @node.respond_to?(:children)

        @node.children.select do |child|
          (!child.respond_to?(:named?) || child.named?) &&
            child.type.to_s != 'comment'
        end
      end

      def header_lines_before(child)
        return [] unless start_line && child&.start_line

        first = start_line
        last = child.start_line - 1
        return [] if last < first

        (first..last).filter_map { |line_num| @lines[line_num - 1] }
      end

      protected

      def wrap_child(child)
        NodeWrapper.new(child, lines: @lines, source: @source, document_index: @document_index)
      end

      def compute_signature(node)
        case node.type.to_s
        when 'document'
          [:document, @document_index]
        when /mapping_pair\z/
          [:pair, key_name]
        when 'block_mapping', 'flow_mapping'
          [:mapping, mapping_pairs.map(&:key_name).compact.sort]
        else
          [node.type.to_sym, text.to_s.strip]
        end
      end

      private

      def scalar_text(node)
        return unless node

        leaf = NodeWrapper.new(node, lines: @lines, source: @source, document_index: @document_index)
        loop do
          children = leaf.semantic_children
          break if children.empty?

          leaf = NodeWrapper.new(children.first, lines: @lines, source: @source, document_index: @document_index)
        end
        raw = leaf.text.to_s.strip
        if raw.start_with?('"') && raw.end_with?('"')
          raw[1...-1]
        elsif raw.start_with?("'") && raw.end_with?("'")
          raw[1...-1].gsub("''", "'")
        else
          raw
        end
      end
    end
  end
end
