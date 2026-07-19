# frozen_string_literal: true

module Prism
  module Merge
    # Wrapper for AST nodes that have an unbalanced or inline nocov marker.
    #
    # Analogous to Ast::Merge::NodeTyping::FrozenWrapper, but for nocov.
    #
    # An unbalanced nocov marker is a `# :nocov:` that appears in a node's leading
    # or trailing comments without a matching close marker at the same level.
    # Example: a method with a trailing `# :nocov:` inline comment.
    #
    # NoCovWrapper wraps the node so merge code can detect and handle it via
    # `is_a?(Prism::Merge::NoCovWrapper)` checks.
    #
    # The wrapped node's structural signature is still used for matching (like
    # FrozenWrapper), not a content-based signature.
    class NoCovWrapper < Ruby::Merge::NocovWrapperBase
      def inspect
        "#<Prism::Merge::NoCovWrapper merge_type=#{@merge_type.inspect} node=#{@node.inspect}>"
      end
    end
  end
end
