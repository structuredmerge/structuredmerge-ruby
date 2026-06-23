# frozen_string_literal: true

module Json
  module Merge
    class SyntheticParser
      Point = Struct.new(:row, :column, keyword_init: true) do
        def [](key)
          public_send(key)
        end
      end

      class Tree
        attr_reader :root_node

        def initialize(root_node)
          @root_node = root_node
        end
      end

      class Node
        attr_reader :type, :start_byte, :end_byte, :source
        attr_accessor :parent

        def initialize(type, start_byte:, end_byte:, source:, children: [], fields: {})
          @type = type.to_s
          @start_byte = start_byte
          @end_byte = end_byte
          @source = source
          @children = children
          @fields = fields
          @children.each { |child| child.parent = self }
          @fields.each_value { |child| child.parent = self }
        end

        def each(&block)
          return @children.each unless block

          @children.each(&block)
        end

        def child_by_field_name(name)
          @fields[name.to_s]
        end

        def text
          @source.byteslice(@start_byte...@end_byte).to_s
        end
        alias to_s text

        def start_point
          point_for(@start_byte)
        end

        def end_point
          point_for(@end_byte)
        end

        def missing?
          false
        end

        def has_error?
          false
        end

        private

        def point_for(byte)
          prefix = @source.byteslice(0...byte).to_s
          lines = prefix.split("\n", -1)
          Point.new(row: lines.length - 1, column: lines.last.to_s.bytesize)
        end
      end

      def initialize(source)
        @source = source
        @index = 0
      end

      def parse
        skip_ignored
        value = parse_value
        skip_ignored
        Tree.new(Node.new('document', start_byte: 0, end_byte: @source.bytesize, source: @source, children: [value]))
      end

      private

      def parse_value
        skip_ignored
        case current_char
        when '{'
          parse_object
        when '['
          parse_array
        when '"'
          parse_string
        when 't'
          parse_literal('true')
        when 'f'
          parse_literal('false')
        when 'n'
          parse_literal('null')
        else
          parse_number
        end
      end

      def parse_object
        start = @index
        @index += 1
        pairs = []
        loop do
          skip_ignored
          break if consume?('}')

          pairs << parse_pair
          skip_ignored
          consume?(',')
        end
        Node.new('object', start_byte: start, end_byte: @index, source: @source, children: pairs)
      end

      def parse_pair
        start = @index
        key = parse_string
        skip_ignored
        consume?(':')
        value = parse_value
        Node.new(
          'pair',
          start_byte: start,
          end_byte: value.end_byte,
          source: @source,
          children: [key, value],
          fields: { 'key' => key, 'value' => value }
        )
      end

      def parse_array
        start = @index
        @index += 1
        elements = []
        loop do
          skip_ignored
          break if consume?(']')

          elements << parse_value
          skip_ignored
          consume?(',')
        end
        Node.new('array', start_byte: start, end_byte: @index, source: @source, children: elements)
      end

      def parse_string
        start = @index
        @index += 1
        escaped = false
        while @index < @source.bytesize
          char = current_char
          @index += 1
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            break
          end
        end
        Node.new('string', start_byte: start, end_byte: @index, source: @source)
      end

      def parse_number
        start = @index
        @index += 1 while @index < @source.bytesize && current_char.match?(/[0-9eE+\-.]/)
        Node.new('number', start_byte: start, end_byte: @index, source: @source)
      end

      def parse_literal(literal)
        start = @index
        @index += literal.bytesize
        Node.new(literal, start_byte: start, end_byte: @index, source: @source)
      end

      def skip_ignored
        loop do
          skip_whitespace
          if current_char == '/' && peek_char == '/'
            @index += 2
            @index += 1 while @index < @source.bytesize && current_char != "\n"
            next
          end
          if current_char == '/' && peek_char == '*'
            @index += 2
            @index += 1 while @index < @source.bytesize && !(current_char == '*' && peek_char == '/')
            @index += 2 if @index < @source.bytesize
            next
          end
          break
        end
      end

      def skip_whitespace
        @index += 1 while @index < @source.bytesize && current_char.match?(/\s/)
      end

      def consume?(char)
        return false unless current_char == char

        @index += 1
        true
      end

      def current_char
        @source.byteslice(@index, 1)
      end

      def peek_char
        @source.byteslice(@index + 1, 1)
      end
    end
  end
end
