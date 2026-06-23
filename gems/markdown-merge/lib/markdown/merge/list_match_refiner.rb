# frozen_string_literal: true

module Markdown
  module Merge
    # Fuzzy matches markdown list nodes by item-token overlap so inner list merging
    # can repair previously-corrupted lists that no longer share an exact signature.
    class ListMatchRefiner < Ast::Merge::MatchRefinerBase
      include Ast::Merge::JaccardSimilarity

      DEFAULT_THRESHOLD = 0.45

      def initialize(threshold: DEFAULT_THRESHOLD, **options)
        super(threshold: threshold, node_types: [:list], **options)
      end

      def call(template_nodes, dest_nodes, context = {})
        template_lists = template_nodes.select { |node| node_type(node).to_s == 'list' }
        dest_lists = dest_nodes.select { |node| node_type(node).to_s == 'list' }
        return [] if template_lists.empty? || dest_lists.empty?

        greedy_match(template_lists, dest_lists) do |template_node, dest_node|
          compute_similarity(template_node, dest_node, context)
        end
      end

      private

      def compute_similarity(template_node, dest_node, context)
        template_items = list_item_anchors(template_node)
        dest_items = list_item_anchors(dest_node)
        return 0.0 if template_items.empty? || dest_items.empty?

        containment = template_item_containment(template_items, dest_items)
        token_overlap = jaccard(list_tokens(template_node), list_tokens(dest_node))
        first_item_score = template_items.first == dest_items.first ? 1.0 : 0.0
        context_score = context_similarity(
          template_node,
          context[:template_analysis],
          dest_node,
          context[:dest_analysis]
        )

        (containment * 0.35) + (token_overlap * 0.35) + (context_score * 0.2) + (first_item_score * 0.1)
      end

      def list_item_anchors(list_node)
        raw = Ast::Merge::NodeTyping.unwrap(list_node)

        raw.each_with_object([]) do |child, anchors|
          next unless child.respond_to?(:type) && %w[list_item item].include?(child.type.to_s)

          anchors << normalize_anchor(child.text.to_s)
        end
      end

      def list_tokens(list_node)
        extract_tokens(list_node.text.to_s)
      end

      def template_item_containment(template_items, dest_items)
        template_set = template_items.to_set
        dest_set = dest_items.to_set
        return 0.0 if template_set.empty?

        (template_set & dest_set).size.to_f / template_set.size
      end

      def context_similarity(template_node, template_analysis, dest_node, dest_analysis)
        template_context = preceding_context_text(template_node, template_analysis)
        dest_context = preceding_context_text(dest_node, dest_analysis)
        return 0.0 if template_context.empty? || dest_context.empty?

        jaccard(extract_tokens(template_context), extract_tokens(dest_context))
      end

      def preceding_context_text(node, analysis)
        return '' unless analysis

        index = analysis.statements.index(node)
        return '' unless index

        (index - 1).downto(0) do |current_index|
          candidate = analysis.statements[current_index]
          signature = analysis.signature_at(current_index)
          next unless signature.is_a?(Array) && %i[heading paragraph code_block].include?(signature.first)

          return candidate.text.to_s
        end

        ''
      end

      def normalize_anchor(text)
        text.to_s.strip.gsub(/\s+/, ' ').downcase
      end
    end
  end
end
