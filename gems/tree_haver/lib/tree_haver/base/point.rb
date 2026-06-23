# frozen_string_literal: true

module TreeHaver
  module Base
    # Point struct for position information (row/column)
    #
    # Provides a consistent interface for 0-based row/column positions.
    # Compatible with both hash-style access and method access.
    #
    # @example
    #   point = TreeHaver::Base::Point.new(5, 10)
    #   point.row      # => 5
    #   point.column   # => 10
    #   point[:row]    # => 5
    #   point[:column] # => 10
    Point = Struct.new(:row, :column) do
      # Hash-style access for compatibility
      # @param key [Symbol, String] :row or :column
      # @return [Integer, nil]
      def [](key)
        case key
        when :row, 'row', 0
          row
        when :column, 'column', 1
          column
        end
      end

      # Convert to hash
      # @return [Hash{Symbol => Integer}]
      def to_h
        { row: row, column: column }
      end

      # String representation
      # @return [String]
      def to_s
        "(#{row}, #{column})"
      end

      # Human-readable representation
      # @return [String]
      def inspect
        "#<TreeHaver::Base::Point row=#{row} column=#{column}>"
      end
    end
  end
end
