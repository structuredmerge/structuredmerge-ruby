# frozen_string_literal: true

module Ast
  module Merge
    # Comment AST nodes for representing comment-only content.
    #
    # This module provides generic, language-agnostic comment representation
    # that supports multiple comment syntax styles:
    # - `:hash_comment` - Ruby/Python/YAML/Shell style (`# comment`)
    # - `:html_comment` - HTML/XML/Markdown style (`<!-- comment -->`)
    # - `:c_style_line` - C/JavaScript/Go line comments (`// comment`)
    # - `:c_style_block` - C/JavaScript/CSS block comments (`/* comment */`)
    # - `:semicolon_comment` - Lisp/Clojure/Assembly style (`; comment`)
    # - `:double_dash_comment` - SQL/Haskell/Lua style (`-- comment`)
    #
    # @example Parsing Ruby-style comments
    #   lines = ["# frozen_string_literal: true", "", "# Main comment"]
    #   nodes = Comment::Parser.parse(lines, style: :hash_comment)
    #
    # @example Parsing JavaScript-style comments
    #   lines = ["// Header comment", "// continues here"]
    #   nodes = Comment::Parser.parse(lines, style: :c_style_line)
    #
    # @example Auto-detecting style
    #   lines = ["<!-- HTML comment -->"]
    #   nodes = Comment::Parser.parse(lines, style: :auto)
    #
    module Comment
      autoload :Attachment, 'ast/merge/comment/attachment'
      autoload :Augmenter, 'ast/merge/comment/augmenter'
      autoload :Capability, 'ast/merge/comment/capability'
      autoload :CStyleTrackerBase, 'ast/merge/comment/c_style_tracker_base'
      autoload :HashTrackerBase, 'ast/merge/comment/hash_tracker_base'
      autoload :Region, 'ast/merge/comment/region'
      autoload :RegionMergePolicy, 'ast/merge/comment/region_merge_policy'
      autoload :SupportStyle, 'ast/merge/comment/support_style'
      autoload :TrackedHashAdapter, 'ast/merge/comment/tracked_hash_adapter'
      autoload :QuotedHashLineParser, 'ast/merge/comment/quoted_hash_line_parser'
      autoload :Style, 'ast/merge/comment/style'
      autoload :Line, 'ast/merge/comment/line'
      autoload :Empty, 'ast/merge/comment/empty'
      autoload :Block, 'ast/merge/comment/block'
      autoload :Parser, 'ast/merge/comment/parser'
    end
  end
end
