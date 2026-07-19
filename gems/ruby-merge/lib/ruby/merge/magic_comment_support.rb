# frozen_string_literal: true

module Ruby
  module Merge
    # Ruby magic comment detection and file-header prefix handling.
    module MagicCommentSupport
      MAGIC_COMMENT_PATTERNS = {
        frozen_string_literal: /^frozen_string_literal:\s*(true|false)$/i,
        encoding: /^(encoding|coding):\s*\S+$/i,
        warn_indent: /^warn_indent:\s*(true|false)$/i,
        shareable_constant_value: /^shareable_constant_value:\s*\S+$/i
      }.freeze

      module_function

      def magic_comment_type_for_text(text)
        stripped = DocCommentSupport.normalize_comment_content(text)

        MAGIC_COMMENT_PATTERNS.each do |type, pattern|
          return type if stripped.match?(pattern)
        end

        nil
      end

      def comment_only_prefix_info(lines)
        entries = []
        suppressed_line_nums = Set.new
        duplicate_magic_line_nums = Set.new

        if shebang_line?(lines.first)
          entries << { line_num: 1, text: lines.first.to_s, kind: :shebang }
          suppressed_line_nums << 1
        end

        header_magic_types = header_magic_comment_types_for_lines(lines)
        seen_magic_types = Set.new

        header_magic_types.keys.sort.each do |line_num|
          magic_type = header_magic_types[line_num]
          suppressed_line_nums << line_num
          entries << { line_num: line_num, text: lines[line_num - 1].to_s.chomp, kind: :magic }

          if seen_magic_types.include?(magic_type)
            duplicate_magic_line_nums << line_num
          else
            seen_magic_types << magic_type
          end
        end

        if header_magic_types.any?
          blank_line_num = header_magic_types.keys.max + 1

          while blank_line_num <= lines.length && lines[blank_line_num - 1].to_s.rstrip.empty?
            entries << { line_num: blank_line_num, text: lines[blank_line_num - 1].to_s, kind: :blank }
            suppressed_line_nums << blank_line_num
            blank_line_num += 1
          end
        end

        {
          entries: entries,
          suppressed_line_nums: suppressed_line_nums,
          duplicate_magic_line_nums: duplicate_magic_line_nums,
          header_magic_comment_types: header_magic_types
        }
      end

      def header_magic_comment_types_for_lines(lines)
        types = {}
        index = shebang_line?(lines.first) ? 1 : 0
        previous_line_num = shebang_line?(lines.first) ? 1 : nil

        while index < lines.length
          line_num = index + 1
          stripped = lines[index].to_s.rstrip
          break if stripped.empty?

          expected_line_num = previous_line_num ? previous_line_num + 1 : 1
          break unless line_num == expected_line_num

          magic_type = magic_comment_type_for_text(stripped)
          break unless magic_type

          types[line_num] = magic_type
          previous_line_num = line_num
          index += 1
        end

        types
      end

      def prefix_comment_line_numbers_for_comments(comments)
        prefix_line_nums = Set.new
        previous_line_num = nil
        index = 0

        if shebang_comment?(comments.first)
          prefix_line_nums << 1
          previous_line_num = 1
          index = 1
        end

        while index < comments.length
          comment = comments[index]
          line_num = comment.location.start_line
          expected_line_num = previous_line_num ? previous_line_num + 1 : 1
          break unless line_num == expected_line_num
          break unless magic_comment_type_for_text(comment.slice)

          prefix_line_nums << line_num
          previous_line_num = line_num
          index += 1
        end

        prefix_line_nums
      end

      def shebang_line?(line)
        line.to_s.start_with?('#!')
      end

      def shebang_comment?(comment)
        comment&.slice&.start_with?('#!')
      end
    end
  end
end
