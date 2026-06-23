# frozen_string_literal: true

module TreeHaver
  module RSpec
    Point = Struct.new(:row, :column)

    class TestableNode
      attr_reader :type, :text, :start_byte, :end_byte, :children, :start_line, :end_line

      def self.create(
        type:,
        text: '',
        start_line: 1,
        end_line: nil,
        start_column: 0,
        end_column: nil,
        start_byte: 0,
        end_byte: nil,
        children: [],
        source: nil
      )
        new(
          type: type,
          text: text,
          start_line: start_line,
          end_line: end_line,
          start_column: start_column,
          end_column: end_column,
          start_byte: start_byte,
          end_byte: end_byte,
          children: children,
          source: source
        )
      end

      def self.create_list(*specs)
        specs.flatten.map { |spec| create(**spec) }
      end

      def initialize(type:, text:, start_line:, end_line:, start_column:, end_column:, start_byte:, end_byte:,
                     children:, source:)
        @type = type.to_s
        @text = text.to_s
        @source = source || @text
        @start_line = start_line
        @end_line = end_line || start_line + @text.count("\n")
        @start_column = start_column
        @end_column = end_column || @text.split("\n", -1).last.to_s.length
        @start_byte = start_byte
        @end_byte = end_byte || start_byte + @text.bytesize
        @children = children.map { |child| child.is_a?(Hash) ? self.class.create(**child) : child }
      end

      def start_point
        Point.new(@start_line - 1, @start_column)
      end

      def end_point
        Point.new(@end_line - 1, @end_column)
      end

      def child_count
        @children.length
      end

      def child(index)
        @children[index] if index && index >= 0
      end

      def first_child
        @children.first
      end

      def last_child
        @children.last
      end

      def each(&block)
        return enum_for(:each) unless block

        @children.each(&block)
      end

      def named?
        true
      end

      def has_error?
        false
      end

      def missing?
        false
      end

      def string_content
        @text
      end

      def content
        @text
      end

      def slice
        @text
      end

      def testable?
        true
      end
    end
  end
end

module Ast
  module Merge
    module Testing
      TestableNode = ::TreeHaver::RSpec::TestableNode
    end
  end
end

TestableNode = TreeHaver::RSpec::TestableNode unless defined?(TestableNode)
