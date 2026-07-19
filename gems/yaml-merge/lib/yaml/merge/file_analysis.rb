# frozen_string_literal: true

module Yaml
  module Merge
    class FileAnalysis
      include Ast::Merge::FileAnalyzable

      attr_reader :ast, :errors

      def initialize(source, signature_generator: nil, parser_path: nil, **_options)
        @source = source
        @lines = source.lines.map(&:chomp)
        @signature_generator = signature_generator
        @parser_path = parser_path
        @errors = []

        DebugLogger.time('FileAnalysis#parse_yaml') { parse_yaml }
        @statements = valid? ? documents : []
      end

      def valid?
        @errors.empty? && !@ast.nil?
      end

      def root_node
        return unless valid?

        NodeWrapper.new(@ast.root_node, lines: @lines, source: @source)
      end

      def documents
        return [] unless valid?

        index = 0
        @ast.root_node.children.filter_map do |child|
          next unless child.type.to_s == 'document'

          wrapper = NodeWrapper.new(child, lines: @lines, source: @source, document_index: index)
          index += 1
          wrapper
        end
      end

      alias nodes statements

      def fallthrough_node?(value)
        value.is_a?(NodeWrapper) || super
      end

      def ruleset_owner_selector
        :line_bound_statements
      end

      def ruleset_render_family
        :yaml_documents_and_mappings
      end

      private

      def compute_node_signature(node)
        return node.signature if node.respond_to?(:signature)

        [node.class.name, node.to_s]
      end

      def layout_augmenter_default_owners
        statements
      end

      def parse_yaml
        parser = if @parser_path
                   TreeHaver.parser_for(:yaml, library_path: @parser_path)
                 else
                   TreeHaver.parser_for(:yaml)
                 end
        @ast = parser.parse(@source)
        collect_parse_errors(@ast.root_node) if @ast&.root_node
      rescue TreeHaver::Error, StandardError => e
        @errors << e
        @ast = nil
      end

      def collect_parse_errors(node, found_errors = [])
        if node.type.to_s == 'ERROR' ||
           (node.respond_to?(:has_error?) && node.has_error?) ||
           (node.respond_to?(:missing?) && node.missing?)
          found_errors << node
        end

        node.children.each { |child| collect_parse_errors(child, found_errors) } if node.respond_to?(:children)
        @errors.concat(found_errors) unless found_errors.empty?
        found_errors
      end
    end
  end
end
