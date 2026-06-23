# frozen_string_literal: true

module Markdown
  module Merge
    # Alias for the shared normalizer module from ast-merge
    NodeTypingNormalizer = Ast::Merge::NodeTyping::Normalizer

    # Normalizes backend-specific node types to canonical markdown types.
    #
    # Uses Ast::Merge::NodeTyping::Wrapper to wrap nodes with canonical
    # merge_type, allowing portable merge rules across backends.
    #
    # ## Thread Safety
    #
    # All backend registration and lookup operations are thread-safe via
    # the shared Ast::Merge::NodeTyping::Normalizer module.
    #
    # ## Extensibility
    #
    # New backends can be registered at runtime:
    #
    # @example Registering a new backend
    #   NodeTypeNormalizer.register_backend(:tree_sitter_markdown, {
    #     atx_heading: :heading,
    #     setext_heading: :heading,
    #     fenced_code_block: :code_block,
    #     indented_code_block: :code_block,
    #     paragraph: :paragraph,
    #     bullet_list: :list,
    #     ordered_list: :list,
    #     block_quote: :block_quote,
    #     thematic_break: :thematic_break,
    #     html_block: :html_block,
    #     pipe_table: :table,
    #   })
    #
    # ## Canonical Types
    #
    # The following canonical types are used for portable merge rules:
    # - `:heading` - Headers/headings (H1-H6)
    # - `:paragraph` - Text paragraphs
    # - `:code_block` - Fenced or indented code blocks
    # - `:list` - Ordered or unordered lists
    # - `:block_quote` - Block quotations
    # - `:thematic_break` - Horizontal rules
    # - `:html_block` - Raw HTML blocks
    # - `:table` - Tables (GFM extension)
    # - `:footnote_definition` - Footnote definitions
    # - `:custom_block` - Custom/extension blocks
    #
    # @see Ast::Merge::NodeTyping::Wrapper
    # @see Ast::Merge::NodeTyping::Normalizer
    module NodeTypeNormalizer
      extend NodeTypingNormalizer

      # Configure default backend mappings.
      # Maps backend-specific type symbols to canonical type symbols.
      #
      # Includes both top-level block types and child node types (table rows, cells, etc.)
      # to enable consistent type checking across the entire AST.
      configure_normalizer(
        commonmarker: {
          # Block types (top-level statements)
          heading: :heading,
          paragraph: :paragraph,
          code_block: :code_block,
          list: :list,
          block_quote: :block_quote,
          thematic_break: :thematic_break,
          html_block: :html_block,
          table: :table,
          footnote_definition: :footnote_definition,
          # Table child types
          table_row: :table_row,
          table_cell: :table_cell,
          table_header: :table_header, # Some parsers distinguish header rows
          # List child types
          list_item: :list_item,
          item: :list_item, # Alias
          # Inline types (usually not top-level, but map them anyway)
          text: :text,
          softbreak: :softbreak,
          linebreak: :linebreak,
          code: :code,
          code_inline: :code, # Alias used by some parsers
          html_inline: :html_inline,
          emph: :emph,
          strong: :strong,
          link: :link,
          image: :image
        }.freeze,
        markly: {
          # Block types - note different names from commonmarker
          header: :heading,           # markly uses :header, not :heading
          paragraph: :paragraph,
          code_block: :code_block,
          list: :list,
          blockquote: :block_quote,   # markly uses :blockquote, not :block_quote
          hrule: :thematic_break,     # markly uses :hrule, not :thematic_break
          html: :html_block,          # markly uses :html, not :html_block
          table: :table,
          footnote_definition: :footnote_definition,
          custom_block: :custom_block,
          # Table child types
          table_row: :table_row,
          table_cell: :table_cell,
          table_header: :table_header,
          # List child types
          list_item: :list_item,
          item: :list_item,
          # Inline types
          text: :text,
          softbreak: :softbreak,
          linebreak: :linebreak,
          code: :code,
          code_inline: :code,
          html_inline: :html_inline,
          emph: :emph,
          strong: :strong,
          link: :link,
          image: :image
        }.freeze
      )
    end
  end
end
