# frozen_string_literal: true

require 'parslet'

module Ast
  module Merge
    module Comment
      # Parses single source lines for hash-style comments while respecting
      # quoted regions. This is intended for ambiguous inline `#` syntaxes
      # where a simple regex becomes brittle.
      class QuotedHashLineParser
        # Normalized result from parsing a line.
        Result = Struct.new(:kind, :indent, :text, :raw, :column, keyword_init: true) do
          def full_line?
            kind == :full_line
          end

          def inline?
            kind == :inline
          end
        end

        # Parslet grammar for finding the first `#` outside quoted segments.
        class Grammar < Parslet::Parser
          root :line

          rule(:line) { full_line_comment.as(:full_line) | inline_candidate.as(:inline) | any.repeat.as(:text) }

          rule(:full_line_comment) do
            whitespace.repeat.as(:indent) >> str('#') >> str(' ').maybe >> any.repeat.as(:comment_text)
          end

          rule(:inline_candidate) do
            prefix.as(:prefix) >> str('#') >> str(' ').maybe >> any.repeat.as(:comment_text)
          end

          rule(:prefix) do
            (double_quoted | single_quoted | escaped_char | non_hash_char).repeat(1)
          end

          rule(:double_quoted) do
            str('"') >> (escaped_char | str('"').absent? >> any).repeat >> str('"')
          end

          rule(:single_quoted) do
            str("'") >> (str("'").absent? >> any).repeat >> str("'")
          end

          rule(:escaped_char) { str('\\') >> any }
          rule(:non_hash_char) { str('#').absent? >> any }
          rule(:whitespace) { match('\s') }
        end

        def initialize
          @grammar = Grammar.new
        end

        # Parse a line into a normalized comment result.
        #
        # @param line [String]
        # @return [Result, nil]
        def parse(line)
          source = line.to_s
          tree = @grammar.parse(source)

          full_line_result(tree[:full_line], source) ||
            inline_result(tree[:inline], source)
        rescue Parslet::ParseFailed
          nil
        end

        private

        def full_line_result(node, source)
          return unless node

          indent = stringify(node[:indent]).length
          # Parser text is normalized; the raw source line stays available separately.
          text = stringify(node[:comment_text]).rstrip
          raw = source

          Result.new(
            kind: :full_line,
            indent: indent,
            text: text,
            raw: raw,
            column: indent
          )
        end

        def inline_result(node, source)
          return unless node

          prefix = stringify(node[:prefix])
          return if prefix.strip.empty?
          return unless prefix[-1]&.match?(/\s/)

          column = prefix.length
          raw = source[column..]
          return unless raw&.start_with?('#')

          Result.new(
            kind: :inline,
            indent: source[/\A\s*/].to_s.length,
            # Parser text is normalized; the raw inline slice is preserved in :raw.
            text: stringify(node[:comment_text]).rstrip,
            raw: raw,
            column: column
          )
        end

        def stringify(value)
          case value
          when Array
            value.map { |entry| stringify(entry) }.join
          when Hash
            value.values.map { |entry| stringify(entry) }.join
          when nil
            +''
          else
            value.to_s
          end
        end
      end
    end
  end
end
