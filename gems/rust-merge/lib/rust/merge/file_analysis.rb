# frozen_string_literal: true

module Rust
  module Merge
    # Native TreeHaver analysis of safely attributable top-level Rust items.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- one AST pass establishes ordered ownership and attribute/comment attachment
    class FileAnalysis
      attr_reader :source, :root_node, :declarations, :errors, :backend

      def initialize(source)
        @source = source
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
        @root_node = TreeHaver.parser_for(:rust, backend_type: :tree_sitter).parse(source).root_node
        raise TreeHaver::NotAvailable, 'Rust parse returned no root node' unless root_node
        raise TreeHaver::NotAvailable, 'Rust parse contains syntax errors' if root_node.has_error?

        wrappers = []
        pending = []
        root_node.children.each do |node|
          if attachable?(node)
            if comment?(node) && trailing_comment?(wrappers.last, node)
              wrappers.last.attach_trailing_comment!(node)
            else
              pending << node
            end
            next
          end
          if NodeWrapper::DECLARATION_TYPES.include?(node.type)
            wrappers << NodeWrapper.new(node, source: source, leading_comments: attached_prefix(pending, node))
            pending.clear
          elsif globally_unmanaged?(node)
            pending.clear
          elsif node.named?
            raise TreeHaver::NotAvailable, "Unmanaged top-level Rust node #{node.type.inspect}"
          end
        end
        @declarations = wrappers.freeze
      end

      def attachable?(node)
        comment?(node) || NodeWrapper::ATTRIBUTE_TYPES.include?(node.type)
      end

      def comment?(node) = NodeWrapper::COMMENT_TYPES.include?(node.type)

      def globally_unmanaged?(node)
        %w[inner_attribute_item shebang].include?(node.type)
      end

      def trailing_comment?(owner, comment)
        owner && whitespace_only?(source.byteslice(owner.end_byte...comment.start_byte).to_s) &&
          source.byteslice(owner.end_byte...comment.start_byte).to_s.count("\n").zero?
      end

      def attached_prefix(items, owner)
        attached = []
        cursor = owner.start_byte
        items.reverse_each do |item|
          gap = source.byteslice(item.end_byte...cursor).to_s
          break unless whitespace_only?(gap)
          break if gap.count("\n") > 1 && !structural_attribute?(item)

          attached.unshift(item)
          cursor = item.start_byte
        end
        attached.freeze
      end

      def structural_attribute?(item)
        return true if NodeWrapper::ATTRIBUTE_TYPES.include?(item.type)

        !find_descendant(item, 'outer_doc_comment_marker').nil?
      end

      def find_descendant(parent, type)
        return parent if parent.type == type

        parent.children.each do |child|
          found = find_descendant(child, type)
          return found if found
        end
        nil
      end

      def whitespace_only?(value)
        value.each_byte.all? { |byte| [9, 10, 13, 32].include?(byte) }
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
