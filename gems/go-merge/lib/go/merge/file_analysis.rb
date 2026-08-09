# frozen_string_literal: true

module Go
  module Merge
    # Native TreeHaver analysis of safely attributable top-level Go source.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- one AST pass establishes ordered ownership and comment attachment
    class FileAnalysis
      attr_reader :source, :root_node, :declarations, :errors, :backend

      def initialize(source, require_package: true)
        @source = source
        @require_package = require_package
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
        parser = TreeHaver.parser_for(:go, backend_type: :tree_sitter)
        @root_node = parser.parse(source).root_node
        raise TreeHaver::NotAvailable, 'Go parse returned no root node' unless root_node
        raise TreeHaver::NotAvailable, 'Go parse contains syntax errors' if root_node.has_error?

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
            pending_comments.clear
            next
          end

          comments = attached_comments(pending_comments, node)
          wrappers << NodeWrapper.new(node, source: source, leading_comments: comments)
          pending_comments.clear
        end
        validate_package!(wrappers) if @require_package
        @declarations = wrappers.freeze
      end

      def trailing_comment?(owner, comment)
        return false unless owner

        gap = source.byteslice(owner.end_byte...comment.start_byte).to_s
        whitespace_only?(gap) && gap.count("\n").zero?
      end

      def attached_comments(comments, owner)
        return [] if comments.empty?

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

      def validate_package!(wrappers)
        packages = wrappers.select { |wrapper| wrapper.node.type == 'package_clause' }
        raise TreeHaver::NotAvailable, 'Go source must contain exactly one package clause' unless packages.length == 1
        return if wrappers.first.equal?(packages.first)

        raise TreeHaver::NotAvailable, 'Go package clause must be the first owned top-level construct'
      end

      def whitespace_only?(value)
        value.each_byte.all? { |byte| [9, 10, 13, 32].include?(byte) }
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
