# frozen_string_literal: true

module Prism
  module Merge
    # Compatibility wrapper for Ruby substrate magic-comment support.
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
