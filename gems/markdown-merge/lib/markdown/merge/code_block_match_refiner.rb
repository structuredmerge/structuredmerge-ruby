# frozen_string_literal: true

module Markdown
  module Merge
    # Fuzzy matches fenced code blocks by fence info and surrounding markdown context
    # so inner code-block merging can run even when block content itself differs.
    class CodeBlockMatchRefiner < Ast::Merge::MatchRefinerBase
      include Ast::Merge::JaccardSimilarity

      DEFAULT_THRESHOLD = 0.65

      def initialize(threshold: DEFAULT_THRESHOLD, **options)
        super(threshold: threshold, node_types: [:code_block], **options)
      end

      def call(template_nodes, dest_nodes, context = {})
        template_blocks = template_nodes.select { |node| node_type(node).to_s == 'code_block' }
        dest_blocks = dest_nodes.select { |node| node_type(node).to_s == 'code_block' }
        return [] if template_blocks.empty? || dest_blocks.empty?

        greedy_match(template_blocks, dest_blocks) do |template_node, dest_node|
          compute_similarity(template_node, dest_node, context)
        end
      end

      private

      def compute_similarity(template_node, dest_node, context)
        return 0.0 unless normalized_fence_info(template_node) == normalized_fence_info(dest_node)

        template_analysis = context[:template_analysis]
        dest_analysis = context[:dest_analysis]
        context_score = surrounding_context_similarity(template_node, template_analysis, dest_node, dest_analysis)
        position_score = relative_position_similarity(template_node, template_analysis, dest_node, dest_analysis)

        0.75 + (context_score * 0.15) + (position_score * 0.10)
      end

      def normalized_fence_info(node)
        raw = Ast::Merge::NodeTyping.unwrap(node)
        raw.respond_to?(:fence_info) ? raw.fence_info.to_s.strip.downcase : ''
      end

      def surrounding_context_similarity(template_node, template_analysis, dest_node, dest_analysis)
        template_context = [preceding_context_text(template_node, template_analysis),
                            following_context_text(template_node, template_analysis)].join(' ')
        dest_context = [preceding_context_text(dest_node, dest_analysis),
                        following_context_text(dest_node, dest_analysis)].join(' ')
        return 0.0 if template_context.empty? || dest_context.empty?

        jaccard(extract_tokens(template_context), extract_tokens(dest_context))
      end

      def relative_position_similarity(template_node, template_analysis, dest_node, dest_analysis)
        template_index = statement_index(template_analysis, template_node)
        dest_index = statement_index(dest_analysis, dest_node)
        template_count = statement_count(template_analysis)
        dest_count = statement_count(dest_analysis)
        return 0.0 unless template_index && dest_index && template_count.positive? && dest_count.positive?

        template_ratio = template_index.to_f / template_count
        dest_ratio = dest_index.to_f / dest_count
        1.0 - (template_ratio - dest_ratio).abs
      end

      def preceding_context_text(node, analysis)
        return '' unless analysis

        index = statement_index(analysis, node)
        return '' unless index

        (index - 1).downto(0) do |current_index|
          candidate = analysis.statements[current_index]
          signature = analysis.signature_at(current_index)
          next unless signature.is_a?(Array) && %i[heading paragraph list].include?(signature.first)

          return candidate.text.to_s
        end

        ''
      end

      def following_context_text(node, analysis)
        return '' unless analysis

        index = statement_index(analysis, node)
        return '' unless index

        ((index + 1)...analysis.statements.length).each do |current_index|
          candidate = analysis.statements[current_index]
          signature = analysis.signature_at(current_index)
          next unless signature.is_a?(Array) && %i[heading paragraph list].include?(signature.first)

          return candidate.text.to_s
        end

        ''
      end

      def statement_index(analysis, node)
        return unless analysis

        analysis.statements.index(node)
      end

      def statement_count(analysis)
        Array(analysis&.statements).length
      end
    end
  end
end
