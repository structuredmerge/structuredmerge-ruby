# frozen_string_literal: true

module Html
  module Merge
    # One native parser pass proving HTML structure, explicit IDs, and safe source ranges.
    class FileAnalysis
      attr_reader :source, :root_node, :wrappers, :errors, :backend, :document_semantics, :issues

      def initialize(source)
        @source = source.to_s
        @backend = BACKEND_REFERENCE.id.to_sym
        @errors = []
        parse!
      rescue StandardError => e
        @root_node = nil
        @wrappers = [].freeze
        @document_semantics = nil
        @issues = [].freeze
        @errors = [e].freeze
      end

      def valid? = errors.empty?

      private

      def parse!
        Html::Merge.register_backend!
        @root_node = TreeHaver.with_backend(backend) { TreeHaver.parser_for(:html).parse(source).root_node }
        raise TreeHaver::NotAvailable, "HTML parse returned no root node" unless root_node
        raise TreeHaver::NotAvailable, "HTML parse contains syntax errors" if root_node.has_error?

        analyze_structure!
      end

      def analyze_structure!
        all = []
        collect_elements(root_node, all)
        duplicate_ids = duplicate_ids(all)
        @issues = duplicate_issues(duplicate_ids)
        unique_ids = unique_id_wrappers(all, duplicate_ids)
        owned = topmost_wrappers(unique_ids)
        singletons = singleton_wrappers(all, owned)
        @wrappers = (owned + singletons).sort_by(&:start_byte).freeze
        @document_semantics = semantic_node(root_node)
      end

      def duplicate_ids(wrappers)
        wrappers.group_by(&:explicit_id).reject { |id, matches| id.nil? || id == true || matches.one? }
      end

      def duplicate_issues(duplicates)
        duplicates.keys.map do |id|
          { category: :ambiguous_owner, identity: [:id, id],
            message: "duplicate explicit HTML id #{id.inspect}" }.freeze
        end.freeze
      end

      def unique_id_wrappers(wrappers, duplicates)
        wrappers.select do |wrapper|
          id = wrapper.explicit_id
          id.is_a?(String) && !id.empty? && !duplicates.key?(id)
        end
      end

      def topmost_wrappers(wrappers)
        wrappers.reject do |wrapper|
          wrappers.any? { |candidate| ancestor?(candidate.node, wrapper.node) }
        end
      end

      def collect_elements(node, collection, parent = nil)
        wrapper = NodeWrapper.new(node, source: source, parent: parent)
        next_parent = parent
        if wrapper.element?
          collection << wrapper
          next_parent = wrapper
        end
        node.children.each { |child| collect_elements(child, collection, next_parent) }
      end

      def singleton_wrappers(all, owned)
        %w[title base].filter_map do |tag|
          matches = all.select { |wrapper| wrapper.tag_name == tag }
          next unless matches.one?
          next if owned.include?(matches.first)
          next if owned.any? { |owner| ancestor?(owner.node, matches.first.node) }

          matches.first
        end
      end

      def ancestor?(ancestor, descendant)
        ancestor.start_byte < descendant.start_byte && ancestor.end_byte >= descendant.end_byte
      end

      def semantic_node(node)
        children = node.children.select(&:structural?)
        return [node.type, node.text.to_s] if children.empty?

        [node.type, children.map { |child| semantic_node(child) }]
      end
    end
  end
end
