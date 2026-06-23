# frozen_string_literal: true

module Ast
  module Merge
    module Navigable
      # Finds injection points in a document based on matching rules.
      #
      # This is language-agnostic - the matching rules work on the unified
      # Statement interface regardless of the underlying parser.
      #
      # @example Find where to inject constants in a Ruby class
      #   finder = InjectionPointFinder.new(statements)
      #   point = finder.find(
      #     type: :class,
      #     text: /class Choo/,
      #     position: :first_child
      #   )
      #
      # @example Find and replace a constant definition
      #   point = finder.find(
      #     type: :constant_assignment,
      #     text: /DAR\s*=/,
      #     position: :replace
      #   )
      #
      class InjectionPointFinder
        # @return [Array<Statement>] The statement list to search
        attr_reader :statements

        def initialize(statements)
          @statements = statements
        end

        # Find an injection point based on matching criteria.
        #
        # @param type [Symbol, String, nil] Node type to match
        # @param text [String, Regexp, nil] Text pattern to match
        # @param position [Symbol] Where to inject (:before, :after, :first_child, :last_child, :replace)
        # @param boundary_type [Symbol, String, nil] Node type for replacement boundary
        # @param boundary_text [String, Regexp, nil] Text pattern for replacement boundary
        # @param boundary_matcher [Proc, nil] Custom matcher for boundary (receives Statement, returns boolean)
        # @param boundary_same_or_shallower [Boolean] If true, boundary is next node at same or shallower tree depth
        # @yield [Statement] Optional custom matcher
        # @return [InjectionPoint, nil] Injection point if anchor found
        def find(position:, type: nil, text: nil, boundary_type: nil, boundary_text: nil, boundary_matcher: nil,
                 boundary_same_or_shallower: false, &block)
          anchor = Statement.find_first(statements, type: type, text: text, &block)
          return unless anchor

          boundary = nil
          if position == :replace && (boundary_type || boundary_text || boundary_matcher || boundary_same_or_shallower)
            # Find boundary starting after anchor
            remaining = statements[(anchor.index + 1)..]

            if boundary_same_or_shallower
              # Find next node at same or shallower tree depth
              # This is language-agnostic: ends section at next sibling or ancestor's sibling
              anchor_depth = anchor.tree_depth
              boundary = remaining.find do |stmt|
                # Must match type if specified
                next false if boundary_type && stmt.type.to_s != boundary_type.to_s
                next false if boundary_text && !stmt.text_matches?(boundary_text)

                # Check tree depth
                stmt.same_or_shallower_than?(anchor_depth)
              end
            elsif boundary_matcher
              # Use custom matcher
              boundary = remaining.find { |stmt| boundary_matcher.call(stmt) }
            else
              boundary = Statement.find_first(
                remaining,
                type: boundary_type,
                text: boundary_text
              )
            end
          end

          InjectionPoint.new(
            anchor: anchor,
            position: position,
            boundary: boundary,
            match: { type: type, text: text }
          )
        end

        # Find all injection points matching criteria.
        #
        # @param (see #find)
        # @return [Array<InjectionPoint>] All matching injection points
        def find_all(position:, type: nil, text: nil, &block)
          anchors = Statement.find_matching(statements, type: type, text: text, &block)
          anchors.map do |anchor|
            InjectionPoint.new(anchor: anchor, position: position)
          end
        end
      end
    end
  end
end
