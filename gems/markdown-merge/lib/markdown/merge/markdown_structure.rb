# frozen_string_literal: true

module Markdown
  module Merge
    # Defines structural spacing rules for markdown elements.
    #
    # When merging markdown from different sources, gap lines from the original
    # sources may not exist at transition points (e.g., when a dest-only table
    # is followed by a template-only table). This module defines which node types
    # require spacing before/after them for proper markdown formatting.
    #
    # Node types are categorized by their spacing needs:
    # - NEEDS_BLANK_BEFORE: Nodes that need a blank line before them (headings, tables, etc.)
    # - NEEDS_BLANK_AFTER: Nodes that need a blank line after them
    # - CONTIGUOUS_TYPES: Nodes that should NOT have blank lines between consecutive instances
    #   (e.g., link_definition blocks should be together)
    #
    # @example
    #   MarkdownStructure.needs_blank_before?(:table)  # => true
    #   MarkdownStructure.needs_blank_after?(:heading) # => true
    #   MarkdownStructure.contiguous_type?(:link_definition) # => true
    module MarkdownStructure
      # Node types that should have a blank line BEFORE them
      # (when preceded by other content)
      NEEDS_BLANK_BEFORE = %i[
        heading
        paragraph
        table
        code_block
        thematic_break
        list
        block_quote
      ].freeze

      # Node types that should have a blank line AFTER them
      # (when followed by other content)
      NEEDS_BLANK_AFTER = %i[
        heading
        paragraph
        table
        code_block
        thematic_break
        list
        block_quote
        link_definition
      ].freeze

      # Node types that should be contiguous (no blank lines between consecutive
      # nodes of the same type). These form "blocks" that should stay together.
      CONTIGUOUS_TYPES = %i[
        link_definition
      ].freeze

      class << self
        # Check if a node type needs a blank line before it
        #
        # @param node_type [Symbol, String] Node type to check
        # @return [Boolean]
        def needs_blank_before?(node_type)
          NEEDS_BLANK_BEFORE.include?(node_type.to_sym)
        end

        # Check if a node type needs a blank line after it
        #
        # @param node_type [Symbol, String] Node type to check
        # @return [Boolean]
        def needs_blank_after?(node_type)
          NEEDS_BLANK_AFTER.include?(node_type.to_sym)
        end

        # Check if a node type is a contiguous type (should not have blank lines
        # between consecutive nodes of the same type).
        #
        # @param node_type [Symbol, String] Node type to check
        # @return [Boolean]
        def contiguous_type?(node_type)
          CONTIGUOUS_TYPES.include?(node_type.to_sym)
        end

        # Check if we should insert a blank line between two node types
        #
        # Rules:
        # 1. If both types are the same contiguous type, NO blank line
        # 2. If previous node needs blank after, YES blank line
        # 3. If next node needs blank before, YES blank line
        #
        # @param prev_type [Symbol, String, nil] Previous node type
        # @param next_type [Symbol, String, nil] Next node type
        # @return [Boolean]
        def needs_blank_between?(prev_type, next_type)
          return false if prev_type.nil? || next_type.nil?

          prev_sym = prev_type.to_sym
          next_sym = next_type.to_sym

          # Same contiguous type - no blank line between them
          return false if prev_sym == next_sym && contiguous_type?(prev_sym)

          needs_blank_after?(prev_sym) || needs_blank_before?(next_sym)
        end

        # Get the node type from a node object
        #
        # Priority order:
        # 1. merge_type - Explicit merge behavior classification (preferred)
        # 2. type - Parser-specific type fallback
        #
        # @param node [Object] Node to get type from
        # @return [Symbol, nil] Node type
        def node_type(node)
          return unless node

          # Prefer merge_type when available - it's the explicit merge behavior classifier
          if node.respond_to?(:merge_type)
            node.merge_type.to_sym
          elsif node.respond_to?(:type)
            node.type.to_sym
          end
        end
      end
    end
  end
end
