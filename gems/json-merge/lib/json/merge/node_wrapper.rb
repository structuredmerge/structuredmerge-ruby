# frozen_string_literal: true

module Json
  module Merge
    # Wraps TreeHaver nodes with line information and signatures for JSON /
    # JSONC merging.
    class NodeWrapper < Ast::Merge::NodeWrapperBase
      attr_reader :dialect

      def initialize(node, lines:, source: nil, dialect: :jsonc, **options)
        @dialect = dialect.to_sym
        super(node, lines: lines, source: source, **options)
      end

      def object?
        @node.type.to_s == 'object'
      end

      def array?
        @node.type.to_s == 'array'
      end

      def string?
        @node.type.to_s == 'string'
      end

      def number?
        @node.type.to_s == 'number'
      end

      def boolean?
        %w[true false].include?(@node.type.to_s)
      end

      def null?
        @node.type.to_s == 'null'
      end

      def pair?
        @node.type.to_s == 'pair'
      end

      def comment?
        @node.type.to_s == 'comment'
      end

      def key_name
        return unless pair?

        key_node = find_child_by_field('key') || semantic_children.first
        return unless key_node

        Json::Merge.object_key_for_literal(node_text(key_node), dialect: dialect)
      end

      def value_node
        return unless pair?

        value = find_child_by_field('value') || semantic_children[1]
        return unless value

        NodeWrapper.new(value, lines: @lines, source: @source, dialect: dialect)
      end

      def pairs
        return [] unless object?

        result = []
        @node.each do |child|
          next if child.type.to_s == 'comment'
          next unless child.type.to_s == 'pair'

          result << NodeWrapper.new(child, lines: @lines, source: @source, dialect: dialect)
        end
        result
      end

      def elements
        return [] unless array?

        result = []
        @node.each do |child|
          child_type = child.type.to_s
          next if child_type == 'comment'
          next if child_type == ','
          next if child_type == '['
          next if child_type == ']'

          result << NodeWrapper.new(child, lines: @lines, source: @source, dialect: dialect)
        end
        result
      end

      def mergeable_children
        case type
        when :object
          pairs
        when :array
          elements
        else
          []
        end
      end

      def container?
        object? || array?
      end

      def root_level_container?
        return false unless container?

        parent_node = @node.parent if @node.respond_to?(:parent)
        return false unless parent_node

        parent_node.type.to_s == 'document'
      end

      def opening_line
        return unless container? && @start_line

        return opening_bracket if @start_line == @end_line

        @lines[@start_line - 1]
      end

      def closing_line
        return unless container? && @end_line

        return closing_bracket if @start_line == @end_line

        @lines[@end_line - 1]
      end

      def opening_bracket
        return '{' if object?
        return '[' if array?

        nil
      end

      def closing_bracket
        return '}' if object?
        return ']' if array?

        nil
      end

      def find_child_by_field(field_name)
        return unless @node.respond_to?(:child_by_field_name)

        @node.child_by_field_name(field_name)
      end

      def find_child_by_type(type_name)
        return unless @node.respond_to?(:each)

        @node.each do |child|
          return child if child.type.to_s == type_name
        end
        nil
      end

      def semantic_children
        return [] unless @node.respond_to?(:each)

        @node.each.filter_map do |child|
          child_type = child.type.to_s
          next if %w[comment , : { } [ ]].include?(child_type)

          child
        end
      end

      protected

      def wrap_child(child)
        NodeWrapper.new(child, lines: @lines, source: @source, dialect: dialect)
      end

      def compute_signature(node)
        node_type = node.type.to_s

        case node_type
        when 'document'
          child = nil
          node.each do |candidate|
            child = candidate unless candidate.type.to_s == 'comment'
            break if child
          end
          child_type = child&.type&.to_s
          [:document, child_type]
        when 'object'
          if root_level_container?
            [:root_object]
          else
            keys = extract_object_keys(node)
            [:object, keys.sort]
          end
        when 'array'
          if root_level_container?
            [:root_array]
          else
            elements_count = 0
            node.each { |candidate| elements_count += 1 unless %w[comment , \[ \]].include?(candidate.type.to_s) }
            [:array, elements_count]
          end
        when 'pair'
          [:pair, key_name]
        when 'string'
          [:string, node_text(node)]
        when 'number'
          [:number, node_text(node)]
        when 'true', 'false'
          [:boolean, node.type.to_s]
        when 'null'
          [:null]
        when 'comment'
          [:comment, node_text(node)&.strip]
        else
          content_preview = node_text(node)&.slice(0, 50)&.strip
          [node_type.to_sym, content_preview]
        end
      end

      private

      def extract_object_keys(object_node)
        keys = []
        object_node.each do |child|
          next unless child.type.to_s == 'pair'

          key_node = child.respond_to?(:child_by_field_name) ? child.child_by_field_name('key') : nil

          unless key_node
            begin
              child_each = child.method(:each)
              child_each.call do |pair_child|
                pair_child_type = pair_child.type.to_s
                next if [':', 'comment'].include?(pair_child_type)

                key_node = pair_child
                break
              end
            rescue StandardError
              next
            end
          end

          next unless key_node

          key_text = Json::Merge.object_key_for_literal(node_text(key_node), dialect: dialect)
          keys << key_text if key_text
        end
        keys
      end
    end
  end
end
