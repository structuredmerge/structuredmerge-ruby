# frozen_string_literal: true

module Prism
  module Merge
    # Ruby-specific comment AST nodes for prism-merge.
    #
    # These classes extend the generic `Ast::Merge::Comment` classes with
    # Ruby-specific features like magic comment detection.
    #
    # @example Parsing Ruby comments
    #   lines = ["# frozen_string_literal: true", "", "# A comment"]
    #   nodes = Comment::Parser.parse(lines)
    #   nodes.first.contains_magic_comment? #=> true
    #
    module Comment
      autoload :Line, 'prism/merge/comment/line'
      autoload :RuntimeLine, 'prism/merge/comment/runtime_line'
      autoload :Block, 'prism/merge/comment/block'
      autoload :Parser, 'prism/merge/comment/parser'
    end
  end
end
