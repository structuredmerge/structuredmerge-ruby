# frozen_string_literal: true

module Ast
  module Merge
    module RSpec
      # Declarative helpers for configuring downstream CommentBehaviorMatrix
      # adapters with only their true points of variation.
      module CommentBehaviorMatrixAdapters
        def line_based_comment_matrix_adapter(
          analysis_class:,
          merger_class:,
          comment_line_builder:,
          structural_owners_reader:,
          owner_value_reader:,
          line_builder:,
          capabilities: {},
          expected_literal_hash_value: '"literal # hash"',
          source_builder: ->(*lines) { "#{lines.join("\n")}\n" }
        )
          let(:comment_matrix_analysis_class) { analysis_class }
          let(:comment_matrix_merger_class) { merger_class }
          let(:comment_matrix_source_builder) { source_builder }
          let(:comment_matrix_comment_line_builder) { comment_line_builder }
          let(:comment_matrix_capabilities) { capabilities }
          let(:comment_matrix_structural_owners_reader) { structural_owners_reader }
          let(:comment_matrix_owner_value_reader) { owner_value_reader }
          let(:comment_matrix_expected_literal_hash_value) { expected_literal_hash_value }
          let(:comment_matrix_line_builder) { line_builder }
        end

        def hash_comment_line_based_comment_matrix_adapter(
          analysis_class:,
          merger_class:,
          structural_owners_reader:,
          owner_value_reader:,
          line_builder:,
          capabilities: {},
          expected_literal_hash_value: '"literal # hash"',
          source_builder: ->(*lines) { "#{lines.join("\n")}\n" }
        )
          line_based_comment_matrix_adapter(
            analysis_class: analysis_class,
            merger_class: merger_class,
            comment_line_builder: ->(text, indent: '') { "#{indent}# #{text}" },
            structural_owners_reader: structural_owners_reader,
            owner_value_reader: owner_value_reader,
            line_builder: line_builder,
            capabilities: capabilities,
            expected_literal_hash_value: expected_literal_hash_value,
            source_builder: source_builder
          )
        end

        def markdown_link_definition_comment_matrix_adapter(analysis_class:, merger_class:, capabilities: {})
          line_based_comment_matrix_adapter(
            analysis_class: analysis_class,
            merger_class: merger_class,
            comment_line_builder: ->(text, indent: '') { "#{indent}<!-- #{text} -->" },
            structural_owners_reader: lambda do |analysis|
              analysis.statements.select do |statement|
                statement.respond_to?(:merge_type) && statement.merge_type == :link_definition
              end
            end,
            owner_value_reader: ->(owner) { owner.url.inspect },
            line_builder: lambda do |name, value, inline: nil|
              "[#{name}]: #{value}"
            end,
            capabilities: {
              inline_comments: 'Markdown standalone HTML comment tracking does not attach inline comments to structural owners',
              quoted_hash_inline_literals: 'Markdown matrix adapter uses link-reference definitions without inline comment syntax',
              remove_template_missing_nodes: 'Markdown link-reference definitions are preserved even in removal mode'
            }.merge(capabilities),
            expected_literal_hash_value: '"/literal#hash"'
          )
        end
      end
    end
  end
end
