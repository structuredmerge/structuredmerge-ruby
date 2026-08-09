# frozen_string_literal: true

module TypeScript
  module Merge
    # Native TreeHaver analysis of safely attributable top-level TypeScript source.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- one AST pass establishes ordered ownership and comment attachment
    class FileAnalysis
      attr_reader :source, :root_node, :declarations, :errors, :backend, :dialect

      def initialize(source, dialect: :typescript)
        @source = source
        @dialect = dialect.to_sym
        @backend = TREE_SITTER_BACKEND.id.to_sym
        @errors = []
        parse!
      rescue StandardError => e
        @root_node = nil
        @declarations = [].freeze
        @errors = [e].freeze
      end

      private

      def parse!
        language = dialect == :tsx ? :tsx : :typescript
        @root_node = TreeHaver.parser_for(language, backend_type: :tree_sitter).parse(source).root_node
        raise TreeHaver::NotAvailable, 'TypeScript parse returned no root node' unless root_node
        raise TreeHaver::NotAvailable, 'TypeScript parse contains syntax errors' if root_node.has_error?

        wrappers = []
        pending_comments = []
        root_node.children.each do |node|
          if node.type == 'comment'
            if trailing_comment?(wrappers.last, node)
              wrappers.last.attach_trailing_comment!(node)
            else
              pending_comments << node
            end
            next
          end
          unless NodeWrapper::DECLARATION_TYPES.include?(node.type)
            raise TreeHaver::NotAvailable, "Unmanaged top-level TypeScript node #{node.type.inspect}" if node.named?

            pending_comments.clear
            next
          end

          wrappers << NodeWrapper.new(node, source: source, leading_comments: attached_comments(pending_comments, node))
          pending_comments.clear
        end
        @declarations = wrappers.freeze
      end

      def trailing_comment?(owner, comment)
        owner && whitespace_only?(source.byteslice(owner.end_byte...comment.start_byte).to_s) &&
          source.byteslice(owner.end_byte...comment.start_byte).to_s.count("\n").zero?
      end

      def attached_comments(comments, owner)
        attached = []
        cursor = owner.start_byte
        comments.reverse_each do |comment|
          gap = source.byteslice(comment.end_byte...cursor).to_s
          break unless whitespace_only?(gap) && gap.count("\n") <= 1

          attached.unshift(comment)
          cursor = comment.start_byte
        end
        attached.freeze
      end

      def whitespace_only?(value)
        value.each_byte.all? { |byte| [9, 10, 13, 32].include?(byte) }
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
