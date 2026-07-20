# frozen_string_literal: true

require "ast/crispr"

module Html
  module Merge
    class CrisprAdapter
      Location = Struct.new(:start_line, :end_line, keyword_init: true)
      Owner = Struct.new(:node, :type, :text, :location, keyword_init: true)

      def read_ast(document)
        result = Html::Merge.parse_html(document.content)
        unless result.fetch(:ok)
          raise Ast::Crispr::Error.new(
            "Unable to parse HTML for CRISPR",
            details: {source_label: document.source_label, diagnostics: result.fetch(:diagnostics)}
          )
        end

        result
      end

      def structural_owners(document, owner_scope: :html_element)
        raise Ast::Crispr::Error.new("Unsupported HTML CRISPR owner scope", details: {owner_scope: owner_scope}) unless owner_scope.to_sym == :html_element

        root = Html::Merge.html_root_node(document.content)
        owners = []
        Html::Merge.visit_html_node(root) do |node|
          next unless node.structural?
          next unless node.type == "element"

          span = Html::Merge.html_node_span(node)
          owners << Owner.new(
            node: node,
            type: node.type,
            text: node.text.to_s,
            location: Location.new(start_line: span.fetch(:start_line), end_line: span.fetch(:end_line))
          )
        end
        owners
      end

      def comment_regions_for(_document, _owner, region: :leading, owner_scope: :html_element)
        raise Ast::Crispr::Error.new(
          "HTML CRISPR comment regions are not implemented",
          details: {region: region, owner_scope: owner_scope}
        )
      end

      def comment_region_text(_document, _comment_region)
        raise Ast::Crispr::Error.new("HTML CRISPR comment regions are not implemented")
      end

      def structure_profile(owner_scope: :html_element)
        Ast::Crispr::StructureProfile.new(
          owner_scope: owner_scope,
          owner_selector: :html_element,
          metadata: {source: :html_merge}
        )
      end
    end
  end
end
