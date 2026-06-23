# frozen_string_literal: true

module Ast
  module Merge
    module Navigable
      # Represents a location in a document where content can be injected.
      #
      # InjectionPoint is language-agnostic - it works with any AST structure.
      # It defines WHERE to inject content and HOW (as child, sibling, or replacement).
      #
      # @example Inject as first child of a class
      #   point = InjectionPoint.new(
      #     anchor: class_node,
      #     position: :first_child
      #   )
      #
      # @example Inject after a specific method
      #   point = InjectionPoint.new(
      #     anchor: method_node,
      #     position: :after
      #   )
      #
      # @example Replace a range of nodes
      #   point = InjectionPoint.new(
      #     anchor: start_node,
      #     position: :replace,
      #     boundary: end_node
      #   )
      #
      class InjectionPoint
        # Valid positions for injection
        POSITIONS = %i[
          before
          after
          first_child
          last_child
          replace
        ].freeze

        # @return [Statement] The anchor node for injection
        attr_reader :anchor

        # @return [Symbol] Position relative to anchor (:before, :after, :first_child, :last_child, :replace)
        attr_reader :position

        # @return [Statement, nil] End boundary for :replace position
        attr_reader :boundary

        # @return [Hash] Additional metadata about this injection point
        attr_reader :metadata

        # Initialize an InjectionPoint.
        #
        # @param anchor [Statement] The reference node
        # @param position [Symbol] Where to inject relative to anchor
        # @param boundary [Statement, nil] End boundary for replacements
        # @param metadata [Hash] Additional info (e.g., match details)
        def initialize(anchor:, position:, boundary: nil, **metadata)
          validate_position!(position)
          validate_boundary!(position, boundary)

          @anchor = anchor
          @position = position
          @boundary = boundary
          @metadata = metadata
        end

        # @return [Boolean] true if this is a replacement (not insertion)
        def replacement?
          position == :replace
        end

        # @return [Boolean] true if this injects as a child
        def child_injection?
          %i[first_child last_child].include?(position)
        end

        # @return [Boolean] true if this injects as a sibling
        def sibling_injection?
          %i[before after].include?(position)
        end

        # Get all statements that would be replaced.
        #
        # @return [Array<Statement>] Statements to replace (empty if not replacement)
        def replaced_statements
          return [] unless replacement?
          return [anchor] unless boundary

          result = [anchor]
          current = anchor.next
          while current && current != boundary
            result << current
            current = current.next
          end
          result << boundary if boundary
          result
        end

        # @return [Integer, nil] Start line of injection point
        def start_line
          anchor.start_line
        end

        # @return [Integer, nil] End line of injection point
        def end_line
          (boundary || anchor).end_line
        end

        # @return [String] Human-readable representation
        def inspect
          boundary_info = boundary ? " to #{boundary.index}" : ''
          "#<Navigable::InjectionPoint position=#{position} anchor=#{anchor.index}#{boundary_info}>"
        end

        private

        def validate_position!(position)
          return if POSITIONS.include?(position)

          raise ArgumentError, "Invalid position: #{position}. Must be one of: #{POSITIONS.join(', ')}"
        end

        def validate_boundary!(position, boundary)
          return unless boundary && position != :replace

          raise ArgumentError, 'boundary is only valid with position: :replace'
        end
      end
    end
  end
end
