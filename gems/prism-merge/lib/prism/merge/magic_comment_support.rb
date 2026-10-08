# frozen_string_literal: true

module Prism
  module Merge
    # Compatibility wrapper for Ruby substrate magic-comment support.
    #
    # == THIS IS NOT THE PRAGMA RESOLVER
    #
    # Do not add new magic-comment / pragma handling here, or in any of the
    # callers listed below. This module only classifies comment TEXT and reports
    # header line numbers. It does not decide which pragmas survive a merge, nor
    # where they are placed.
    #
    # The authoritative resolver for file-level pragmas is
    # {Prism::Merge::PragmaMerger}, wired in from
    # {Prism::Merge::SmartMerger#apply_pragma_header}. Pragma semantics live there:
    #
    #   KEPT     - preference resolved exactly like ordinary content, honouring
    #              add_template_only_nodes and remove_template_missing_nodes
    #   POSITION - always pinned to the header region (below any shebang), because
    #              Ruby ignores a magic comment that appears after the first
    #              statement
    #
    # Anything built on this module instead will silently reintroduce the two
    # defects PragmaMerger exists to prevent: a pragma stranded below code (inert,
    # Lint/MisplacedMagicComment) and a pragma dropped because retention followed
    # `preference` alone rather than the add/remove flags.
    #
    # == Remaining consumers (legacy, classification only)
    #
    # These still consult this module. Each is a COMMENT CLASSIFICATION or node
    # SIGNATURE concern, not pragma retention or placement, and none may grow
    # pragma handling:
    #
    #   lib/prism/merge/comment/line.rb              magic_comment_type attribute
    #   lib/prism/merge/comment/block.rb             contains_magic_comment?, magic_comments
    #   lib/prism/merge/comment/parser.rb            header classification while parsing
    #   lib/prism/merge/file_analysis.rb             native_header_magic_comment_types
    #   lib/prism/merge/comment_only_file_merger.rb  comment-only file header handling
    #   lib/prism/merge/node_emission_support.rb     leading-comment prefix emission
    #   lib/prism/merge/recursive_node_body_merger.rb prefix comment filtering
    #   lib/prism/merge/wrapper_comment_support.rb   leading-comment emission
    #   lib/prism/merge/ruby_doc_surface_analyzer.rb doc-comment vs directive split
    #   lib/prism/merge.rb                           prism_comment_directive classification
    #
    # Removing them is deliberately deferred: Comment::Line#magic_comment_type
    # feeds node signatures, so deleting it changes match identity well beyond
    # pragmas. That work needs its own pass with the full monorepo suite as guard.
    module MagicCommentSupport
      module_function

      def magic_comment_type_for_text(text)
        Ruby::Merge::MagicCommentSupport.magic_comment_type_for_text(text)
      end

      def comment_only_prefix_info(lines)
        Ruby::Merge::MagicCommentSupport.comment_only_prefix_info(lines)
      end

      def header_magic_comment_types_for_lines(lines)
        Ruby::Merge::MagicCommentSupport.header_magic_comment_types_for_lines(lines)
      end

      def prefix_comment_line_numbers_for_comments(comments)
        Ruby::Merge::MagicCommentSupport.prefix_comment_line_numbers_for_comments(comments)
      end

      def shebang_line?(line)
        Ruby::Merge::MagicCommentSupport.shebang_line?(line)
      end

      def shebang_comment?(comment)
        Ruby::Merge::MagicCommentSupport.shebang_comment?(comment)
      end
    end
  end
end
